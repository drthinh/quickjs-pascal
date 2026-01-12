unit fs_watch_helpers;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes,
  quickjs_types, quickjs_core, qjsp_host_errors
  {$IFDEF WINDOWS}
  , Windows
  {$ENDIF}
  ;

procedure RegisterFsWatchHelpers(ctx: PJSContext);
procedure SetFsWatchEnabled(enabled: boolean);
procedure SetFsWatchAllowedRoots(const roots: array of string);
procedure SetFsWatchMaxWatchers(maxWatchers: integer);
procedure SetFsWatchThrottleMs(throttleMs: QWord);

implementation

var
  g_fs_watch_enabled: boolean = True;
  g_fs_watch_allowed_roots: TStringList;
  g_fs_watch_max_watchers: integer = 0;
  g_fs_watch_throttle_ms: QWord = 0;

procedure SetFsWatchEnabled(enabled: boolean);
begin
  g_fs_watch_enabled := enabled;
end;

procedure SetFsWatchAllowedRoots(const roots: array of string);
var
  i: integer;
  s: string;
begin
  if g_fs_watch_allowed_roots = nil then
  begin
    g_fs_watch_allowed_roots := TStringList.Create;
    g_fs_watch_allowed_roots.CaseSensitive := False;
  end;
  g_fs_watch_allowed_roots.Clear;
  for i := 0 to High(roots) do
  begin
    s := Trim(roots[i]);
    if s <> '' then
      g_fs_watch_allowed_roots.Add(s);
  end;
end;

procedure SetFsWatchMaxWatchers(maxWatchers: integer);
begin
  if maxWatchers < 0 then
    maxWatchers := 0;
  g_fs_watch_max_watchers := maxWatchers;
end;

procedure SetFsWatchThrottleMs(throttleMs: QWord);
begin
  g_fs_watch_throttle_ms := throttleMs;
end;

{$IFDEF WINDOWS}
type
  DWORD = Windows.DWORD;

  PFILE_NOTIFY_INFORMATION = ^FILE_NOTIFY_INFORMATION;
  FILE_NOTIFY_INFORMATION = packed record
    NextEntryOffset: DWORD;
    Action: DWORD;
    FileNameLength: DWORD;
    FileName: array[0..0] of WideChar;
  end;

const
  FILE_ACTION_ADDED = DWORD(1);
  FILE_ACTION_REMOVED = DWORD(2);
  FILE_ACTION_MODIFIED = DWORD(3);
  FILE_ACTION_RENAMED_OLD_NAME = DWORD(4);
  FILE_ACTION_RENAMED_NEW_NAME = DWORD(5);

type
  TWatchEvent = record
    watch_id: cint;
    action: cuint32;
    path: UnicodeString;
  end;

  TWatchEventArray = array of TWatchEvent;

  PWatch = ^TWatch;
  TWatch = record
    id: cint;
    dir: UnicodeString;
    recursive: Boolean;
    hDir: THandle;
    thread: TThread;
    last_emit_tick: QWord;
  end;

  TWatchThread = class(TThread)
  private
    FWatch: PWatch;
  protected
    procedure Execute; override;
  public
    constructor Create(w: PWatch);
  end;

var
  Watches: TList;
  NextWatchId: cint = 1;
  EventQueue: array of TWatchEvent;
  QueueCS: TRTLCriticalSection;

function FindWatchById(id: cint): PWatch;
var
  i: Integer;
  w: PWatch;
begin
  Result := nil;
  if Watches = nil then
    Exit;
  for i := 0 to Watches.Count - 1 do
  begin
    w := PWatch(Watches[i]);
    if (w <> nil) and (w^.id = id) then
      Exit(w);
  end;
end;

procedure RemoveWatch(w: PWatch);
var
  i: Integer;
begin
  if (Watches = nil) or (w = nil) then
    Exit;
  for i := 0 to Watches.Count - 1 do
  begin
    if Watches[i] = w then
    begin
      Watches.Delete(i);
      Exit;
    end;
  end;
end;

procedure QueuePush(const ev: TWatchEvent);
begin
  EnterCriticalSection(QueueCS);
  try
    SetLength(EventQueue, Length(EventQueue) + 1);
    EventQueue[High(EventQueue)] := ev;
  finally
    LeaveCriticalSection(QueueCS);
  end;
end;

function IsDirAllowedByPolicy(const dirAbs: string): Boolean;
var
  i: Integer;
  rootAbs: string;
  rootCmp: string;
  dirCmp: string;
begin
  Result := True;
  if (g_fs_watch_allowed_roots = nil) or (g_fs_watch_allowed_roots.Count <= 0) then
    Exit;

  dirCmp := ExpandFileName(dirAbs);
  {$IFDEF WINDOWS}
  dirCmp := LowerCase(StringReplace(dirCmp, '/', PathDelim, [rfReplaceAll]));
  {$ENDIF}

  for i := 0 to g_fs_watch_allowed_roots.Count - 1 do
  begin
    rootAbs := ExpandFileName(g_fs_watch_allowed_roots[i]);
    rootCmp := rootAbs;
    {$IFDEF WINDOWS}
    rootCmp := LowerCase(StringReplace(rootCmp, '/', PathDelim, [rfReplaceAll]));
    {$ENDIF}
    if (rootCmp <> '') and (rootCmp[Length(rootCmp)] <> PathDelim) then
      rootCmp := rootCmp + PathDelim;
    if (rootCmp <> '') and (Copy(dirCmp, 1, Length(rootCmp)) = rootCmp) then
      Exit(True);
  end;
  Result := False;
end;

function QueueDrain: TWatchEventArray;
var
  outArr: TWatchEventArray;
  i: Integer;
begin
  EnterCriticalSection(QueueCS);
  try
    SetLength(outArr, Length(EventQueue));
    for i := 0 to High(EventQueue) do
      outArr[i] := EventQueue[i];
    SetLength(EventQueue, 0);
  finally
    LeaveCriticalSection(QueueCS);
  end;
  Result := outArr;
end;

procedure CloseWatch(w: PWatch);
var
  t: TThread;
begin
  if w = nil then
    Exit;

  t := w^.thread;
  if t <> nil then
  begin
    t.Terminate;
    try
      CancelIoEx(w^.hDir, nil);
    except
    end;
  end;

  if w^.hDir <> 0 then
  begin
    CloseHandle(w^.hDir);
    w^.hDir := 0;
  end;

  if t <> nil then
  begin
    t.WaitFor;
    t.Free;
    w^.thread := nil;
  end;
end;

function WideToUTF8JS(ctx: PJSContext; const ws: UnicodeString): JSValue;
var
  u8: UTF8String;
begin
  u8 := UTF8Encode(ws);
  Result := JS_NewStringLen(ctx, PChar(u8), Length(u8));
end;

constructor TWatchThread.Create(w: PWatch);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FWatch := w;
end;

procedure TWatchThread.Execute;
const
  BUF_SIZE = 64 * 1024;
var
  buf: array[0..BUF_SIZE - 1] of Byte;
  bytesReturned: DWORD;
  p: PFILE_NOTIFY_INFORMATION;
  off: DWORD;
  nameLenChars: DWORD;
  ev: TWatchEvent;
  fileName: UnicodeString;
  notifyFilter: DWORD;
  w: PWatch;
  nowTick: QWord;
begin
  notifyFilter := FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
                  FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_SIZE;

  while not Terminated do
  begin
    bytesReturned := 0;
    if not ReadDirectoryChangesW(
      FWatch^.hDir,
      @buf[0],
      BUF_SIZE,
      FWatch^.recursive,
      notifyFilter,
      @bytesReturned,
      nil,
      nil) then
    begin
      if Terminated then
        Break;
      Sleep(10);
      Continue;
    end;

    off := 0;
    while (off < bytesReturned) and (not Terminated) do
    begin
      p := PFILE_NOTIFY_INFORMATION(@buf[off]);
      nameLenChars := p^.FileNameLength div SizeOf(WideChar);
      SetString(fileName, PWideChar(@p^.FileName[0]), nameLenChars);

      ev.watch_id := FWatch^.id;
      ev.action := p^.Action;
      ev.path := fileName;

      w := FWatch;
      if (w <> nil) and (g_fs_watch_throttle_ms > 0) then
      begin
        nowTick := GetTickCount64;
        if (w^.last_emit_tick <> 0) and ((nowTick - w^.last_emit_tick) < g_fs_watch_throttle_ms) then
        begin
        end
        else
        begin
          w^.last_emit_tick := nowTick;
          QueuePush(ev);
        end;
      end
      else
      begin
        QueuePush(ev);
      end;

      if p^.NextEntryOffset = 0 then
        Break;
      Inc(off, p^.NextEntryOffset);
    end;
  end;
end;

function js_watch_dir(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  dirC: PChar;
  dirW: UnicodeString;
  recursive: Boolean;
  h: THandle;
  wptr: PWatch;
  dirAbs8: string;
begin
  try
    if not g_fs_watch_enabled then
      Exit(QjspThrowHostError(ctx, QJSP_E_FSWATCH_DISABLED, 'fs_watch is disabled by host policy', 'fs_watch'));

    if argc < 1 then
      Exit(JS_ThrowTypeError(ctx, PChar('WatchDir expects 1 argument: dir')));

  dirC := JS_ToCString(ctx, argv[0]);
  if dirC = nil then
    Exit(JS_EXCEPTION);
  try
    dirW := UTF8Decode(UTF8String(dirC));
  finally
    JS_FreeCString(ctx, dirC);
  end;

  recursive := True;
  if argc >= 2 then
    recursive := JS_ToBool(ctx, argv[1]) <> 0;

  dirAbs8 := UTF8Encode(dirW);
  if not IsDirAllowedByPolicy(string(dirAbs8)) then
    Exit(QjspThrowHostError(ctx, QJSP_E_FSWATCH_ROOT_DENIED, 'watch root is not allowed by host policy', 'fs_watch'));

  if (g_fs_watch_max_watchers > 0) and (Watches <> nil) and (Watches.Count >= g_fs_watch_max_watchers) then
    Exit(QjspThrowHostError(ctx, QJSP_E_FSWATCH_LIMIT, 'max watchers limit reached', 'fs_watch'));

  h := CreateFileW(PWideChar(dirW),
    FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil,
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS,
    0);

  if h = INVALID_HANDLE_VALUE then
    Exit(JS_ThrowTypeError(ctx, PChar('WatchDir: cannot open directory')));

  New(wptr);
  FillChar(wptr^, SizeOf(TWatch), 0);
  wptr^.id := NextWatchId;
  Inc(NextWatchId);
  wptr^.dir := dirW;
  wptr^.recursive := recursive;
  wptr^.hDir := h;
  wptr^.thread := TWatchThread.Create(wptr);
  wptr^.last_emit_tick := 0;

  if Watches = nil then
    Watches := TList.Create;
  Watches.Add(wptr);

    Result := JS_NewInt32(ctx, wptr^.id);
  except
    on E: Exception do
    begin
      Result := JS_ThrowPlainError(ctx, PChar('fs_watch:WatchDir: ' + E.Message));
    end;
  end;
end;

function js_close_watch(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  id: cint;
  w: PWatch;
begin
  try
    if not g_fs_watch_enabled then
      Exit(QjspThrowHostError(ctx, QJSP_E_FSWATCH_DISABLED, 'fs_watch is disabled by host policy', 'fs_watch'));

    if argc < 1 then
      Exit(JS_ThrowTypeError(ctx, PChar('CloseWatch expects 1 argument: id')));

  if JS_ToInt32(ctx, @id, argv[0]) <> 0 then
    Exit(JS_EXCEPTION);

  w := FindWatchById(id);
  if w = nil then
    Exit(JS_UNDEFINED);

  CloseWatch(w);
  RemoveWatch(w);
  Dispose(w);

    Result := JS_UNDEFINED;
  except
    on E: Exception do
    begin
      Result := JS_ThrowPlainError(ctx, PChar('fs_watch:CloseWatch: ' + E.Message));
    end;
  end;
end;

function js_pump_watch_events(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  arr: JSValue;
  evs: TWatchEventArray;
  i: Integer;
  o: JSValue;
  actionStr: PChar;
begin
  try
    if not g_fs_watch_enabled then
      Exit(QjspThrowHostError(ctx, QJSP_E_FSWATCH_DISABLED, 'fs_watch is disabled by host policy', 'fs_watch'));

    evs := QueueDrain;
    arr := JS_NewArray(ctx);

  for i := 0 to High(evs) do
  begin
    o := JS_NewObject(ctx);
    JS_DefinePropertyValueStr(ctx, o, PChar('id'), JS_NewInt32(ctx, evs[i].watch_id), JS_PROP_C_W_E);

    case evs[i].action of
      FILE_ACTION_ADDED: actionStr := PChar('add');
      FILE_ACTION_REMOVED: actionStr := PChar('remove');
      FILE_ACTION_MODIFIED: actionStr := PChar('modify');
      FILE_ACTION_RENAMED_OLD_NAME: actionStr := PChar('rename_old');
      FILE_ACTION_RENAMED_NEW_NAME: actionStr := PChar('rename_new');
    else
      actionStr := PChar('unknown');
    end;

    JS_DefinePropertyValueStr(ctx, o, PChar('type'), JS_NewString(ctx, actionStr), JS_PROP_C_W_E);
    JS_DefinePropertyValueStr(ctx, o, PChar('path'), WideToUTF8JS(ctx, evs[i].path), JS_PROP_C_W_E);
    JS_SetPropertyUint32(ctx, arr, cuint32(i), o);
  end;

    Result := arr;
  except
    on E: Exception do
    begin
      Result := JS_ThrowPlainError(ctx, PChar('fs_watch:PumpWatchEvents: ' + E.Message));
    end;
  end;
end;

procedure RegisterFsWatchHelpers(ctx: PJSContext);
var
  global_obj: JSValue;
begin
  global_obj := JS_GetGlobalObject(ctx);
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('WatchDir'),
    JS_NewCFunction(ctx, @js_watch_dir, PChar('WatchDir'), 2), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('CloseWatch'),
    JS_NewCFunction(ctx, @js_close_watch, PChar('CloseWatch'), 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('PumpWatchEvents'),
    JS_NewCFunction(ctx, @js_pump_watch_events, PChar('PumpWatchEvents'), 0), JS_PROP_C_W_E);
  JS_FreeValue(ctx, global_obj);
end;

initialization
  InitCriticalSection(QueueCS);
  Watches := TList.Create;
finalization
  if Watches <> nil then
  begin
    while Watches.Count > 0 do
    begin
      CloseWatch(PWatch(Watches[0]));
      Dispose(PWatch(Watches[0]));
      Watches.Delete(0);
    end;
    Watches.Free;
    Watches := nil;
  end;
  DoneCriticalSection(QueueCS);

{$ELSE}

procedure RegisterFsWatchHelpers(ctx: PJSContext);
begin
end;

{$ENDIF}

end.
