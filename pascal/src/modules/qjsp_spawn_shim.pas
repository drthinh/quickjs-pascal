unit qjsp_spawn_shim;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, quickjs_types;

procedure RegisterSpawnModuleShims(ctx: PJSContext);
procedure SpawnPoll(ctx: PJSContext);

implementation

uses
  quickjs_core, quickjs_std, qjs_log, Process
  {$IFDEF WINDOWS}
  , Windows
  {$ENDIF}
  ;

type
  PSpawnProcRec = ^TSpawnProcRec;
  PSpawnChunk = ^TSpawnChunk;

  TSpawnChunkKind = (sckStdout, sckStderr);

  TSpawnChunk = record
    Kind: TSpawnChunkKind;
    Data: TBytes;
    Len: SizeInt;
  end;

  TSpawnReaderThread = class(TThread)
  private
    FOwner: PSpawnProcRec;
    FKind: TSpawnChunkKind;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: PSpawnProcRec; AKind: TSpawnChunkKind);
  end;

  TSpawnProcRec = record
    Id: cint64;
    P: TProcess;
    OutThread: TSpawnReaderThread;
    ErrThread: TSpawnReaderThread;
    Lock: TRTLCriticalSection;
    Chunks: TList;
    WaitPromise: JSValue;
    WaitResolve: JSValue;
    WaitReject: JSValue;
    WaitAttachedCtx: PJSContext;
  end;

var
  g_procs: TList;
  g_next_id: cint64 = 1;

procedure WriteBytesToStdOut(const buf: TBytes; n: SizeInt); forward;
procedure WriteBytesToStdErr(const buf: TBytes; n: SizeInt); forward;

function PopChunk(sp: PSpawnProcRec): PSpawnChunk;
begin
  Result := nil;
  if (sp = nil) or (sp^.Chunks = nil) then
    Exit;
  EnterCriticalSection(sp^.Lock);
  try
    if sp^.Chunks.Count > 0 then
    begin
      Result := PSpawnChunk(sp^.Chunks[0]);
      sp^.Chunks.Delete(0);
    end;
  finally
    LeaveCriticalSection(sp^.Lock);
  end;
end;

procedure PushChunk(sp: PSpawnProcRec; kind: TSpawnChunkKind; const buf: TBytes; n: SizeInt);
var
  ch: PSpawnChunk;
begin
  if (sp = nil) or (n <= 0) then
    Exit;
  New(ch);
  FillChar(ch^, SizeOf(ch^), 0);
  ch^.Kind := kind;
  ch^.Len := n;
  SetLength(ch^.Data, n);
  Move(buf[0], ch^.Data[0], n);

  EnterCriticalSection(sp^.Lock);
  try
    if sp^.Chunks <> nil then
      sp^.Chunks.Add(ch)
    else
      Dispose(ch);
  finally
    LeaveCriticalSection(sp^.Lock);
  end;
end;

constructor TSpawnReaderThread.Create(AOwner: PSpawnProcRec; AKind: TSpawnChunkKind);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FKind := AKind;
  Start;
end;

procedure TSpawnReaderThread.Execute;
var
  tmp: TBytes;
  n: SizeInt;
  avail: SizeInt;
begin
  tmp := nil;
  SetLength(tmp, 8192);
  while (not Terminated) and (FOwner <> nil) and (FOwner^.P <> nil) do
  begin
    try
      if FKind = sckStdout then
        avail := FOwner^.P.Output.NumBytesAvailable
      else
        avail := FOwner^.P.Stderr.NumBytesAvailable;
    except
      Break;
    end;

    if avail <= 0 then
    begin
      if FOwner^.P.WaitOnExit(0) then
        Break;
      Sleep(10);
      Continue;
    end;

    try
      if FKind = sckStdout then
        n := FOwner^.P.Output.Read(tmp[0], Length(tmp))
      else
        n := FOwner^.P.Stderr.Read(tmp[0], Length(tmp));
    except
      Break;
    end;

    if n > 0 then
    begin
      if FKind = sckStdout then
        WriteBytesToStdOut(tmp, n)
      else
        WriteBytesToStdErr(tmp, n);
    end
    else
      Sleep(1);
  end;
end;

{$IFDEF WINDOWS}
var
  g_ctrl_handler_installed: boolean = False;

function WinTaskKill(pid: DWORD; force: boolean): boolean;
var
  cmd: AnsiString;
  si: STARTUPINFOA;
  pi: PROCESS_INFORMATION;
begin
  Result := False;
  if pid = 0 then
    Exit;
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  FillChar(pi, SizeOf(pi), 0);
  cmd := 'taskkill /PID ' + AnsiString(IntToStr(pid)) + ' /T';
  if force then
    cmd := cmd + ' /F';
  Result := CreateProcessA(nil, PAnsiChar(cmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, si, pi);
  if Result then
  begin
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  end;
end;

function WinSendCtrlBreak(pid: DWORD): boolean;
var
  ignore: WINBOOL;
begin
  Result := False;
  if pid = 0 then
    Exit;
  ignore := SetConsoleCtrlHandler(nil, True);
  try
    Result := GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, pid);
  finally
    if ignore then
      SetConsoleCtrlHandler(nil, False);
  end;
end;

procedure WinKillProcessTree(pid: DWORD);
var
  cmd: AnsiString;
  si: STARTUPINFOA;
  pi: PROCESS_INFORMATION;
begin
  if pid = 0 then
    Exit;
  FillChar(si, SizeOf(si), 0);
  si.cb := SizeOf(si);
  FillChar(pi, SizeOf(pi), 0);
  cmd := 'taskkill /PID ' + AnsiString(IntToStr(pid)) + ' /T /F';
  if CreateProcessA(nil, PAnsiChar(cmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, si, pi) then
  begin
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  end;
end;

function CtrlHandler(dwCtrlType: DWORD): WINBOOL; stdcall;
var
  i: integer;
  sp: PSpawnProcRec;
begin
  Result := False;
  if (dwCtrlType <> CTRL_C_EVENT) and (dwCtrlType <> CTRL_BREAK_EVENT) then
    Exit;

  if g_procs <> nil then
  begin
    for i := 0 to g_procs.Count - 1 do
    begin
      sp := PSpawnProcRec(g_procs[i]);
      if (sp <> nil) and (sp^.P <> nil) then
      begin
        try
          if not WinSendCtrlBreak(DWORD(sp^.P.ProcessID)) then
            WinTaskKill(DWORD(sp^.P.ProcessID), False);
        except
        end;
      end;
    end;
  end;

  // Always consume CTRL+C/CTRL+BREAK so the REPL doesn't terminate.
  Result := True;
end;

procedure EnsureCtrlHandler;
begin
  if g_ctrl_handler_installed then
    Exit;
  SetConsoleCtrlHandler(@CtrlHandler, True);
  g_ctrl_handler_installed := True;
end;
{$ENDIF}

function GetProcById(id: cint64): PSpawnProcRec;
var
  i: integer;
  sp: PSpawnProcRec;
begin
  Result := nil;
  if g_procs = nil then
    Exit;
  for i := 0 to g_procs.Count - 1 do
  begin
    sp := PSpawnProcRec(g_procs[i]);
    if (sp <> nil) and (sp^.Id = id) then
      Exit(sp);
  end;
end;

procedure RemoveProcById(id: cint64);
var
  i: integer;
  sp: PSpawnProcRec;
  ch: PSpawnChunk;
begin
  if g_procs = nil then
    Exit;
  for i := g_procs.Count - 1 downto 0 do
  begin
    sp := PSpawnProcRec(g_procs[i]);
    if (sp <> nil) and (sp^.Id = id) then
    begin
      if sp^.OutThread <> nil then
      begin
        try
          sp^.OutThread.Terminate;
        except
        end;
        try
          sp^.OutThread.WaitFor;
        except
        end;
        sp^.OutThread.Free;
        sp^.OutThread := nil;
      end;

      if sp^.ErrThread <> nil then
      begin
        try
          sp^.ErrThread.Terminate;
        except
        end;
        try
          sp^.ErrThread.WaitFor;
        except
        end;
        sp^.ErrThread.Free;
        sp^.ErrThread := nil;
      end;

      if sp^.Chunks <> nil then
      begin
        repeat
          ch := PopChunk(sp);
          if ch <> nil then
            Dispose(ch);
        until ch = nil;
        sp^.Chunks.Free;
        sp^.Chunks := nil;
      end;

      try
        DoneCriticalSection(sp^.Lock);
      except
      end;

      if (sp^.WaitAttachedCtx <> nil) and (JS_IsUndefined(sp^.WaitPromise) = 0) then
      begin
        JS_FreeValue(sp^.WaitAttachedCtx, sp^.WaitPromise);
        JS_FreeValue(sp^.WaitAttachedCtx, sp^.WaitResolve);
        JS_FreeValue(sp^.WaitAttachedCtx, sp^.WaitReject);
      end;
      sp^.WaitPromise := JS_UNDEFINED;
      sp^.WaitResolve := JS_UNDEFINED;
      sp^.WaitReject := JS_UNDEFINED;
      sp^.WaitAttachedCtx := nil;

      if sp^.P <> nil then
        sp^.P.Free;
      Dispose(sp);
      g_procs.Delete(i);
      Exit;
    end;
  end;
end;

procedure WriteBytesToStdOut(const buf: TBytes; n: SizeInt);
{$IFDEF WINDOWS}
var
  h: HANDLE;
  written: DWORD;
{$ELSE}
var
  s: AnsiString;
{$ENDIF}
begin
  if n <= 0 then
    Exit;

  {$IFDEF WINDOWS}
  h := GetStdHandle(STD_OUTPUT_HANDLE);
  if (h <> 0) and (h <> INVALID_HANDLE_VALUE) then
    WriteFile(h, buf[0], DWORD(n), written, nil);
  {$ELSE}
  SetString(s, PAnsiChar(@buf[0]), n);
  Write(s);
  Flush(Output);
  {$ENDIF}
end;

procedure WriteBytesToStdErr(const buf: TBytes; n: SizeInt);
{$IFDEF WINDOWS}
var
  h: HANDLE;
  written: DWORD;
{$ELSE}
var
  s: AnsiString;
{$ENDIF}
begin
  if n <= 0 then
    Exit;

  {$IFDEF WINDOWS}
  h := GetStdHandle(STD_ERROR_HANDLE);
  if (h <> 0) and (h <> INVALID_HANDLE_VALUE) then
    WriteFile(h, buf[0], DWORD(n), written, nil);
  {$ELSE}
  SetString(s, PAnsiChar(@buf[0]), n);
  Write(StdErr, s);
  Flush(StdErr);
  {$ENDIF}
end;

function js_spawn(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  argvVal: JSValueConst;
  optsVal: JSValueConst;
  len64: cint64;
  i: cint64;
  item: JSValue;
  s: PChar;
  cmd: string;
  p: TProcess;
  sp: PSpawnProcRec;
  obj: JSValue;
  cwdStr: string;
  mergeErr: boolean;
  inheritStdio: boolean;
  v: JSValue;
  b: cint;
  shellCmd: string;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('spawn expects argv array')));

  argvVal := argv[0];
  optsVal := JS_UNDEFINED;
  if argc >= 2 then
    optsVal := argv[1];

  // Accept both arrays and array-like objects (with length + numeric properties).
  // Also accept a string and treat it like a shell command (spawnShell behavior).
  len64 := 0;
  if JS_IsString(argvVal) <> 0 then
  begin
    shellCmd := '';
    s := JS_ToCString(ctx, argvVal);
    if s = nil then
      Exit(JS_EXCEPTION);
    try
      shellCmd := string(s);
    finally
      JS_FreeCString(ctx, s);
    end;
    len64 := -1;
  end
  else
  begin
    if JS_IsObject(argvVal) = 0 then
      Exit(JS_ThrowTypeError(ctx, PChar('spawn: argv must be an array')));
    if JS_GetLength(ctx, argvVal, @len64) <> 0 then
      Exit(JS_ThrowTypeError(ctx, PChar('spawn: invalid argv length')));
    if len64 <= 0 then
      Exit(JS_ThrowTypeError(ctx, PChar('spawn: argv must not be empty')));
  end;

  p := TProcess.Create(nil);
  try
    p.Options := [poUsePipes];

    cwdStr := '';
    mergeErr := False;
    inheritStdio := False;
    if JS_IsObject(optsVal) <> 0 then
    begin
      v := JS_GetPropertyStr(ctx, optsVal, PChar('cwd'));
      if JS_IsException(v) = 0 then
      begin
        if (JS_IsUndefined(v) = 0) and (JS_IsNull(v) = 0) then
        begin
          s := JS_ToCString(ctx, v);
          if s <> nil then
          begin
            cwdStr := string(s);
            JS_FreeCString(ctx, s);
          end;
        end;
      end;
      JS_FreeValue(ctx, v);

      v := JS_GetPropertyStr(ctx, optsVal, PChar('mergeStderr'));
      if JS_IsException(v) = 0 then
      begin
        b := JS_ToBool(ctx, v);
        if b <> 0 then
          mergeErr := True;
      end;
      JS_FreeValue(ctx, v);

      v := JS_GetPropertyStr(ctx, optsVal, PChar('inheritStdio'));
      if JS_IsException(v) = 0 then
      begin
        b := JS_ToBool(ctx, v);
        if b <> 0 then
          inheritStdio := True;
      end;
      JS_FreeValue(ctx, v);
    end;

    if (cwdStr <> '') and (cwdStr <> 'undefined') then
      p.CurrentDirectory := cwdStr;

    if inheritStdio then
      p.Options := []
    else
    begin
      p.Options := [poUsePipes];
      if mergeErr then
        p.Options := p.Options + [poStderrToOutPut];
    end;

    if len64 = -1 then
    begin
      {$IFDEF WINDOWS}
      p.Executable := SysUtils.GetEnvironmentVariable('ComSpec');
      if p.Executable = '' then
        p.Executable := 'cmd.exe';
      p.Parameters.Add('/C');
      p.Parameters.Add(shellCmd);
      {$ELSE}
      p.Executable := 'sh';
      p.Parameters.Add('-c');
      p.Parameters.Add(shellCmd);
      {$ENDIF}
    end
    else
    begin
      item := JS_GetPropertyUint32(ctx, argvVal, 0);
      if JS_IsException(item) <> 0 then
        Exit(JS_EXCEPTION);
      try
        s := JS_ToCString(ctx, item);
        if s = nil then
          Exit(JS_EXCEPTION);
        try
          cmd := string(s);
        finally
          JS_FreeCString(ctx, s);
        end;
      finally
        JS_FreeValue(ctx, item);
      end;

      if cmd = '' then
        Exit(JS_ThrowTypeError(ctx, PChar('spawn: argv[0] must be a non-empty string')));

      {$IFDEF WINDOWS}
      if SameText(cmd, 'cmd.exe') then
      begin
        p.Executable := SysUtils.GetEnvironmentVariable('ComSpec');
        if p.Executable = '' then
          p.Executable := cmd;
      end
      else
      {$ENDIF}
      p.Executable := cmd;

      for i := 1 to len64 - 1 do
      begin
        item := JS_GetPropertyUint32(ctx, argvVal, cuint32(i));
        if JS_IsException(item) <> 0 then
          Exit(JS_EXCEPTION);
        try
          s := JS_ToCString(ctx, item);
          if s <> nil then
          begin
            try
              p.Parameters.Add(string(s));
            finally
              JS_FreeCString(ctx, s);
            end;
          end;
        finally
          JS_FreeValue(ctx, item);
        end;
      end;
    end;

    try
      p.Execute;
    except
      on E: Exception do
        Exit(JS_ThrowPlainError(ctx, PChar('spawn: failed to execute "' + p.Executable + '" (cwd="' + p.CurrentDirectory + '"): ' + E.Message)));
    end;

    New(sp);
    FillChar(sp^, SizeOf(sp^), 0);
    sp^.Id := g_next_id;
    Inc(g_next_id);
    sp^.P := p;

    InitCriticalSection(sp^.Lock);
    sp^.Chunks := TList.Create;
    sp^.WaitPromise := JS_UNDEFINED;
    sp^.WaitResolve := JS_UNDEFINED;
    sp^.WaitReject := JS_UNDEFINED;
    sp^.WaitAttachedCtx := nil;

    if (poUsePipes in p.Options) then
    begin
      sp^.OutThread := TSpawnReaderThread.Create(sp, sckStdout);
      if not (poStderrToOutPut in p.Options) then
        sp^.ErrThread := TSpawnReaderThread.Create(sp, sckStderr);
    end;

    if g_procs = nil then
      g_procs := TList.Create;
    g_procs.Add(sp);

    {$IFDEF WINDOWS}
    EnsureCtrlHandler;
    {$ENDIF}

    obj := JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, PChar('id'), JS_NewInt64(ctx, sp^.Id));
    JS_SetPropertyStr(ctx, obj, PChar('pid'), JS_NewInt64(ctx, p.ProcessID));
    Result := obj;

    p := nil;
  finally
    if p <> nil then
      p.Free;
  end;
end;

function js_kill(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  id: cint64;
  sp: PSpawnProcRec;
  sig: cint32;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('kill expects id')));
  if JS_ToInt64(ctx, @id, argv[0]) < 0 then
    Exit(JS_EXCEPTION);
  sp := GetProcById(id);
  if (sp = nil) or (sp^.P = nil) then
    Exit(JS_ThrowTypeError(ctx, PChar('kill: invalid process id')));

  sig := 15;
  if argc >= 2 then
    JS_ToInt32(ctx, @sig, argv[1]);
  try
    {$IFDEF WINDOWS}
    case sig of
      2:
        begin
          if not WinSendCtrlBreak(DWORD(sp^.P.ProcessID)) then
            WinTaskKill(DWORD(sp^.P.ProcessID), False);
        end;
      9:
        begin
          WinTaskKill(DWORD(sp^.P.ProcessID), True);
          WinKillProcessTree(DWORD(sp^.P.ProcessID));
        end;
    else
      begin
        WinTaskKill(DWORD(sp^.P.ProcessID), False);
      end;
    end;
    {$ENDIF}
    if sig = 9 then
      sp^.P.Terminate(1)
    else if (sig = 15) or (sig = 9) then
      sp^.P.Terminate(1);
  except
  end;
  Result := JS_UNDEFINED;
end;

function js_wait(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  id: cint64;
  sp: PSpawnProcRec;
  outBuf: TBytes;
  errBuf: TBytes;
  n: SizeInt;
  obj: JSValue;
  exitCode: cint32;
begin
  outBuf := nil;
  errBuf := nil;
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('wait expects id')));
  if JS_ToInt64(ctx, @id, argv[0]) < 0 then
    Exit(JS_EXCEPTION);
  sp := GetProcById(id);
  if (sp = nil) or (sp^.P = nil) then
    Exit(JS_ThrowTypeError(ctx, PChar('wait: invalid process id')));

  if (poUsePipes in sp^.P.Options) then
  begin
    SetLength(outBuf, 8192);
    SetLength(errBuf, 8192);
  end;

  try
    while not sp^.P.WaitOnExit(10) do
    begin
      if (poUsePipes in sp^.P.Options) then
      begin
        while sp^.P.Output.NumBytesAvailable > 0 do
        begin
          n := sp^.P.Output.Read(outBuf[0], Length(outBuf));
          if n > 0 then
            WriteBytesToStdOut(outBuf, n)
          else
            Break;
        end;

        if not (poStderrToOutPut in sp^.P.Options) then
        begin
          while sp^.P.Stderr.NumBytesAvailable > 0 do
          begin
            n := sp^.P.Stderr.Read(errBuf[0], Length(errBuf));
            if n > 0 then
              WriteBytesToStdErr(errBuf, n)
            else
              Break;
          end;
        end;
      end;
    end;

    if (poUsePipes in sp^.P.Options) then
    begin
      while sp^.P.Output.NumBytesAvailable > 0 do
      begin
        n := sp^.P.Output.Read(outBuf[0], Length(outBuf));
        if n > 0 then
          WriteBytesToStdOut(outBuf, n)
        else
          Break;
      end;

      if not (poStderrToOutPut in sp^.P.Options) then
      begin
        while sp^.P.Stderr.NumBytesAvailable > 0 do
        begin
          n := sp^.P.Stderr.Read(errBuf[0], Length(errBuf));
          if n > 0 then
            WriteBytesToStdErr(errBuf, n)
          else
            Break;
        end;
      end;
    end;

    exitCode := sp^.P.ExitStatus;
  finally
    RemoveProcById(id);
  end;

  obj := JS_NewObject(ctx);
  JS_SetPropertyStr(ctx, obj, PChar('code'), JS_NewInt32(ctx, exitCode));
  Result := obj;
end;

function js_wait_async(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  id: cint64;
  sp: PSpawnProcRec;
  resolving_funcs: array[0..1] of JSValue;
  promise: JSValue;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('waitAsync expects id')));
  if JS_ToInt64(ctx, @id, argv[0]) < 0 then
    Exit(JS_EXCEPTION);
  sp := GetProcById(id);
  if (sp = nil) or (sp^.P = nil) then
    Exit(JS_ThrowTypeError(ctx, PChar('waitAsync: invalid process id')));

  if (sp^.WaitAttachedCtx = ctx) and (JS_IsUndefined(sp^.WaitPromise) = 0) then
    Exit(JS_DupValue(ctx, sp^.WaitPromise));

  resolving_funcs[0] := JS_UNDEFINED;
  resolving_funcs[1] := JS_UNDEFINED;
  promise := JS_NewPromiseCapability(ctx, @resolving_funcs[0]);
  if JS_IsException(promise) <> 0 then
    Exit(JS_EXCEPTION);

  if (sp^.WaitAttachedCtx <> nil) and (JS_IsUndefined(sp^.WaitPromise) = 0) then
  begin
    JS_FreeValue(sp^.WaitAttachedCtx, sp^.WaitPromise);
    JS_FreeValue(sp^.WaitAttachedCtx, sp^.WaitResolve);
    JS_FreeValue(sp^.WaitAttachedCtx, sp^.WaitReject);
  end;

  sp^.WaitAttachedCtx := ctx;
  sp^.WaitPromise := JS_DupValue(ctx, promise);
  sp^.WaitResolve := JS_DupValue(ctx, resolving_funcs[0]);
  sp^.WaitReject := JS_DupValue(ctx, resolving_funcs[1]);

  JS_FreeValue(ctx, resolving_funcs[0]);
  JS_FreeValue(ctx, resolving_funcs[1]);

  Result := promise;
end;

procedure RegisterSpawnGlobals(ctx: PJSContext);
var
  global_obj: JSValue;
  native_obj: JSValue;
begin
  if ctx = nil then
    Exit;

  global_obj := JS_GetGlobalObject(ctx);
  native_obj := JS_NewObject(ctx);

  JS_DefinePropertyValueStr(ctx, native_obj, PChar('spawn'),
    JS_NewCFunction(ctx, @js_spawn, PChar('spawn'), 2), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, native_obj, PChar('wait'),
    JS_NewCFunction(ctx, @js_wait, PChar('wait'), 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, native_obj, PChar('waitAsync'),
    JS_NewCFunction(ctx, @js_wait_async, PChar('waitAsync'), 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, native_obj, PChar('kill'),
    JS_NewCFunction(ctx, @js_kill, PChar('kill'), 2), JS_PROP_C_W_E);

  JS_DefinePropertyValueStr(ctx, global_obj, PChar('__qjsp_native_spawn'), native_obj, JS_PROP_C_W_E);
  JS_FreeValue(ctx, global_obj);
end;

procedure SpawnPoll(ctx: PJSContext);
var
  i: integer;
  sp: PSpawnProcRec;
  ch: PSpawnChunk;
  exitCode: cint32;
  obj, arg, rv: JSValue;
begin
  if (ctx = nil) or (g_procs = nil) then
    Exit;

  for i := g_procs.Count - 1 downto 0 do
  begin
    sp := PSpawnProcRec(g_procs[i]);
    if (sp = nil) or (sp^.P = nil) then
      Continue;

    repeat
      ch := PopChunk(sp);
      if ch = nil then
        Break;
      try
        // Chunks are printed by reader threads. Only dispose here.
      finally
        Dispose(ch);
      end;
    until False;

    if sp^.P.WaitOnExit(0) then
    begin
      exitCode := sp^.P.ExitStatus;

      if (sp^.WaitAttachedCtx = ctx) and (JS_IsUndefined(sp^.WaitPromise) = 0) then
      begin
        obj := JS_NewObject(ctx);
        JS_SetPropertyStr(ctx, obj, PChar('code'), JS_NewInt32(ctx, exitCode));
        arg := obj;
        rv := JS_Call(ctx, sp^.WaitResolve, JS_UNDEFINED, 1, @arg);
        if JS_IsException(rv) <> 0 then
          js_std_dump_error(ctx);
        JS_FreeValue(ctx, rv);
        JS_FreeValue(ctx, obj);
      end;

      RemoveProcById(sp^.Id);
    end;
  end;
end;

procedure RegisterSpawnModuleShims(ctx: PJSContext);
begin
  if ctx = nil then
    Exit;
  RegisterSpawnGlobals(ctx);

  {$IFDEF WINDOWS}
  EnsureCtrlHandler;
  {$ENDIF}
end;

end.
