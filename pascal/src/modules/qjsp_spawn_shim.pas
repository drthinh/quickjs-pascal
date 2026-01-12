unit qjsp_spawn_shim;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, quickjs_types;

procedure RegisterSpawnModuleShims(ctx: PJSContext);
procedure SpawnPoll(ctx: PJSContext);
procedure SetSpawnEnabled(enabled: boolean);
procedure SetSpawnMaxConcurrent(maxConcurrent: integer);
procedure SetSpawnDefaultTimeoutMs(defaultTimeoutMs: QWord);
procedure SetSpawnDefaultMaxOutputKb(defaultMaxOutputKb: QWord);
procedure SetSpawnAllowedCwdRoots(const roots: array of string);
procedure SetSpawnEnvAllowlist(const names: array of string);

implementation

uses
  quickjs_core, quickjs_std, qjs_log, Process, qjsp_host_errors
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
    StartTick: QWord;
    TimeoutMs: QWord;
    MaxOutputBytes: QWord;
    TotalOutBytes: QWord;
    TotalErrBytes: QWord;
    TruncatedOut: boolean;
    TruncatedErr: boolean;
    TimedOut: boolean;
    Killed: boolean;
    CmdLine: string;
    Cwd: string;
    {$IFDEF WINDOWS}
    Job: HANDLE;
    {$ENDIF}
    WaitPromise: JSValue;
    WaitResolve: JSValue;
    WaitReject: JSValue;
    WaitAttachedCtx: PJSContext;
  end;

var
  g_procs: TList;
  g_next_id: cint64 = 1;
  g_spawn_enabled: boolean = True;
  g_spawn_max_concurrent: integer = 0;
  g_spawn_default_timeout_ms: QWord = 30000;
  g_spawn_default_max_output_kb: QWord = 256;
  g_spawn_allowed_cwd_roots: TStringList;
  g_spawn_env_allowlist: TStringList;

procedure SetSpawnEnabled(enabled: boolean);
begin
  g_spawn_enabled := enabled;
end;

procedure SetSpawnMaxConcurrent(maxConcurrent: integer);
begin
  if maxConcurrent < 0 then
    maxConcurrent := 0;
  g_spawn_max_concurrent := maxConcurrent;
end;

procedure SetSpawnDefaultTimeoutMs(defaultTimeoutMs: QWord);
begin
  g_spawn_default_timeout_ms := defaultTimeoutMs;
end;

procedure SetSpawnDefaultMaxOutputKb(defaultMaxOutputKb: QWord);
begin
  g_spawn_default_max_output_kb := defaultMaxOutputKb;
end;

procedure SetSpawnAllowedCwdRoots(const roots: array of string);
var
  i: integer;
begin
  if g_spawn_allowed_cwd_roots = nil then
    g_spawn_allowed_cwd_roots := TStringList.Create;
  g_spawn_allowed_cwd_roots.Clear;
  for i := 0 to High(roots) do
    if Trim(roots[i]) <> '' then
      g_spawn_allowed_cwd_roots.Add(Trim(roots[i]));
end;

procedure SetSpawnEnvAllowlist(const names: array of string);
var
  i: integer;
begin
  if g_spawn_env_allowlist = nil then
    g_spawn_env_allowlist := TStringList.Create;
  g_spawn_env_allowlist.Clear;
  for i := 0 to High(names) do
    if Trim(names[i]) <> '' then
      g_spawn_env_allowlist.Add(Trim(names[i]));
end;

procedure WriteBytesToStdOut(const buf: TBytes; n: SizeInt); forward;
procedure WriteBytesToStdErr(const buf: TBytes; n: SizeInt); forward;
procedure AuditSpawn(const sp: PSpawnProcRec; const exitCode: cint32); forward;

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
  allow_n: SizeInt;
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
      allow_n := 0;
      EnterCriticalSection(FOwner^.Lock);
      try
        if (FOwner^.MaxOutputBytes > 0) then
        begin
          if FKind = sckStdout then
          begin
            if not FOwner^.TruncatedOut then
            begin
              if FOwner^.TotalOutBytes >= FOwner^.MaxOutputBytes then
              begin
                FOwner^.TruncatedOut := True;
                allow_n := 0;
              end
              else
              begin
                if QWord(n) > (FOwner^.MaxOutputBytes - FOwner^.TotalOutBytes) then
                  allow_n := SizeInt(FOwner^.MaxOutputBytes - FOwner^.TotalOutBytes)
                else
                  allow_n := n;
                FOwner^.TotalOutBytes := FOwner^.TotalOutBytes + QWord(allow_n);
                if QWord(allow_n) < QWord(n) then
                  FOwner^.TruncatedOut := True;
              end;
            end
            else
              allow_n := 0;
          end
          else
          begin
            if not FOwner^.TruncatedErr then
            begin
              if FOwner^.TotalErrBytes >= FOwner^.MaxOutputBytes then
              begin
                FOwner^.TruncatedErr := True;
                allow_n := 0;
              end
              else
              begin
                if QWord(n) > (FOwner^.MaxOutputBytes - FOwner^.TotalErrBytes) then
                  allow_n := SizeInt(FOwner^.MaxOutputBytes - FOwner^.TotalErrBytes)
                else
                  allow_n := n;
                FOwner^.TotalErrBytes := FOwner^.TotalErrBytes + QWord(allow_n);
                if QWord(allow_n) < QWord(n) then
                  FOwner^.TruncatedErr := True;
              end;
            end
            else
              allow_n := 0;
          end;
        end
        else
        begin
          allow_n := n;
          if FKind = sckStdout then
            FOwner^.TotalOutBytes := FOwner^.TotalOutBytes + QWord(n)
          else
            FOwner^.TotalErrBytes := FOwner^.TotalErrBytes + QWord(n);
        end;
      finally
        LeaveCriticalSection(FOwner^.Lock);
      end;

      if allow_n > 0 then
        PushChunk(FOwner, FKind, tmp, allow_n);
    end
    else
      Sleep(1);
  end;
end;

{$IFDEF WINDOWS}
var
  g_ctrl_handler_installed: boolean = False;

type
  JOBOBJECT_BASIC_LIMIT_INFORMATION = record
    PerProcessUserTimeLimit: LARGE_INTEGER;
    PerJobUserTimeLimit: LARGE_INTEGER;
    LimitFlags: DWORD;
    MinimumWorkingSetSize: SIZE_T;
    MaximumWorkingSetSize: SIZE_T;
    ActiveProcessLimit: DWORD;
    Affinity: ULONG_PTR;
    PriorityClass: DWORD;
    SchedulingClass: DWORD;
  end;

  IO_COUNTERS = record
    ReadOperationCount: ULONGLONG;
    WriteOperationCount: ULONGLONG;
    OtherOperationCount: ULONGLONG;
    ReadTransferCount: ULONGLONG;
    WriteTransferCount: ULONGLONG;
    OtherTransferCount: ULONGLONG;
  end;

  JOBOBJECT_EXTENDED_LIMIT_INFORMATION = record
    BasicLimitInformation: JOBOBJECT_BASIC_LIMIT_INFORMATION;
    IoInfo: IO_COUNTERS;
    ProcessMemoryLimit: SIZE_T;
    JobMemoryLimit: SIZE_T;
    PeakProcessMemoryUsed: SIZE_T;
    PeakJobMemoryUsed: SIZE_T;
  end;

const
  JobObjectExtendedLimitInformation = 9;
  JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $00002000;

function CreateJobObjectW(lpJobAttributes: PSecurityAttributes; lpName: PWideChar): HANDLE; stdcall; external 'kernel32.dll' name 'CreateJobObjectW';
function SetInformationJobObject(hJob: HANDLE; JobObjectInfoClass: DWORD; lpJobObjectInfo: Pointer; cbJobObjectInfoLength: DWORD): WINBOOL; stdcall; external 'kernel32.dll' name 'SetInformationJobObject';
function AssignProcessToJobObject(hJob: HANDLE; hProcess: HANDLE): WINBOOL; stdcall; external 'kernel32.dll' name 'AssignProcessToJobObject';

function WinCreateKillJob(out job: HANDLE): boolean;
var
  info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION;
begin
  Result := False;
  job := CreateJobObjectW(nil, nil);
  if job = 0 then
    Exit;
  FillChar(info, SizeOf(info), 0);
  info.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if not SetInformationJobObject(job, JobObjectExtendedLimitInformation, @info, SizeOf(info)) then
  begin
    CloseHandle(job);
    job := 0;
    Exit;
  end;
  Result := True;
end;

function WinAssignProcessToJob(job: HANDLE; pid: DWORD): boolean;
var
  ph: HANDLE;
begin
  Result := False;
  if (job = 0) or (pid = 0) then
    Exit;
  ph := OpenProcess(PROCESS_SET_QUOTA or PROCESS_TERMINATE, False, pid);
  if ph = 0 then
    Exit;
  try
    Result := AssignProcessToJobObject(job, ph);
  finally
    CloseHandle(ph);
  end;
end;

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
  exitCode: cint32;
begin
  if g_procs = nil then
    Exit;
  for i := g_procs.Count - 1 downto 0 do
  begin
    sp := PSpawnProcRec(g_procs[i]);
    if (sp <> nil) and (sp^.Id = id) then
    begin
      exitCode := 0;
      if sp^.P <> nil then
      begin
        try
          exitCode := sp^.P.ExitStatus;
        except
        end;
      end;
      AuditSpawn(sp, exitCode);

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
          begin
            Finalize(ch^);
            Dispose(ch);
          end;
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

      {$IFDEF WINDOWS}
      if sp^.Job <> 0 then
      begin
        CloseHandle(sp^.Job);
        sp^.Job := 0;
      end;
      {$ENDIF}

      if sp^.P <> nil then
        sp^.P.Free;
      Dispose(sp);
      g_procs.Delete(i);
      Exit;
    end;
  end;
end;

procedure AuditSpawn(const sp: PSpawnProcRec; const exitCode: cint32);
var
  durMs: QWord;
  pidVal: int64;
  flags: string;
begin
  if (sp = nil) then
    Exit;
  durMs := 0;
  if sp^.StartTick <> 0 then
    durMs := GetTickCount64 - sp^.StartTick;
  pidVal := 0;
  if sp^.P <> nil then
  begin
    try
      pidVal := sp^.P.ProcessID;
    except
    end;
  end;

  flags := '';
  if sp^.TimedOut then
    flags := flags + ' timedOut';
  if sp^.Killed then
    flags := flags + ' killed';
  if sp^.TruncatedOut or sp^.TruncatedErr then
    flags := flags + ' truncated';
  flags := Trim(flags);

  qjs_log.LogMsg(llInfo, 'spawn',
    'id=' + IntToStr(sp^.Id) +
    ' pid=' + IntToStr(pidVal) +
    ' code=' + IntToStr(exitCode) +
    ' durationMs=' + IntToStr(durMs) +
    ' timeoutMs=' + IntToStr(sp^.TimeoutMs) +
    ' maxOutputBytes=' + IntToStr(sp^.MaxOutputBytes) +
    ' outBytes=' + IntToStr(sp^.TotalOutBytes) +
    ' errBytes=' + IntToStr(sp^.TotalErrBytes) +
    ' cwd="' + sp^.Cwd + '"' +
    ' cmd="' + sp^.CmdLine + '"' +
    ' flags="' + flags + '"'
  );
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
  timeoutMs: QWord;
  maxOutputKb: QWord;
  tmpI64: cint64;
  cwdAbs: string;
  rootAbs: string;
  cwdAbsCmp: string;
  rootAbsCmp: string;
  rootOk: boolean;
  allowName: string;
  allowValue: string;
begin
  if not g_spawn_enabled then
    Exit(QjspThrowHostError(ctx, QJSP_E_SPAWN_DISABLED, 'spawn is disabled by host policy', 'spawn'));

  if (g_spawn_max_concurrent > 0) and (g_procs <> nil) and (g_procs.Count >= g_spawn_max_concurrent) then
    Exit(QjspThrowHostError(ctx, QJSP_E_SPAWN_CONCURRENCY_LIMIT,
      'spawn concurrency limit exceeded (max_concurrent=' + IntToStr(g_spawn_max_concurrent) + ')', 'spawn'));

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

      timeoutMs := g_spawn_default_timeout_ms;
      v := JS_GetPropertyStr(ctx, optsVal, PChar('timeoutMs'));
      if JS_IsException(v) = 0 then
      begin
        if (JS_IsUndefined(v) = 0) and (JS_IsNull(v) = 0) then
        begin
          tmpI64 := 0;
          if JS_ToInt64(ctx, @tmpI64, v) = 0 then
          begin
            if tmpI64 < 0 then
              tmpI64 := 0;
            timeoutMs := QWord(tmpI64);
          end;
        end;
      end;
      JS_FreeValue(ctx, v);

      maxOutputKb := g_spawn_default_max_output_kb;
      v := JS_GetPropertyStr(ctx, optsVal, PChar('maxOutputKb'));
      if JS_IsException(v) = 0 then
      begin
        if (JS_IsUndefined(v) = 0) and (JS_IsNull(v) = 0) then
        begin
          tmpI64 := 0;
          if JS_ToInt64(ctx, @tmpI64, v) = 0 then
          begin
            if tmpI64 < 0 then
              tmpI64 := 0;
            maxOutputKb := QWord(tmpI64);
          end;
        end;
      end;
      JS_FreeValue(ctx, v);
    end;

    if JS_IsObject(optsVal) = 0 then
    begin
      timeoutMs := g_spawn_default_timeout_ms;
      maxOutputKb := g_spawn_default_max_output_kb;
    end;

    if (cwdStr <> '') and (cwdStr <> 'undefined') then
    begin
      // CWD jail: only enforce for explicit cwd requests.
      if (g_spawn_allowed_cwd_roots <> nil) and (g_spawn_allowed_cwd_roots.Count > 0) then
      begin
        cwdAbs := ExpandFileName(cwdStr);
        rootOk := False;
        for tmpI64 := 0 to g_spawn_allowed_cwd_roots.Count - 1 do
        begin
          rootAbs := ExpandFileName(g_spawn_allowed_cwd_roots[integer(tmpI64)]);
          rootAbsCmp := rootAbs;
          cwdAbsCmp := cwdAbs;
          if (rootAbsCmp <> '') and (rootAbsCmp[Length(rootAbsCmp)] <> PathDelim) then
            rootAbsCmp := rootAbsCmp + PathDelim;
          if (cwdAbsCmp <> '') and (cwdAbsCmp[Length(cwdAbsCmp)] <> PathDelim) then
            cwdAbsCmp := cwdAbsCmp + PathDelim;
          {$IFDEF WINDOWS}
          if SameText(Copy(cwdAbsCmp, 1, Length(rootAbsCmp)), rootAbsCmp) then
            rootOk := True;
          {$ELSE}
          if Copy(cwdAbsCmp, 1, Length(rootAbsCmp)) = rootAbsCmp then
            rootOk := True;
          {$ENDIF}
          if rootOk then
            Break;
        end;
        if not rootOk then
          Exit(QjspThrowHostError(ctx, QJSP_E_SPAWN_CWD_DENIED,
            'spawn cwd is denied by host policy: "' + cwdStr + '"', 'spawn'));
      end;

      p.CurrentDirectory := cwdStr;
    end;

    // Environment scrubbing (best-effort): if allowlist is configured, only pass
    // those variables to the child process.
    if (g_spawn_env_allowlist <> nil) and (g_spawn_env_allowlist.Count > 0) then
    begin
      try
        p.Environment.Clear;
        for tmpI64 := 0 to g_spawn_env_allowlist.Count - 1 do
        begin
          allowName := g_spawn_env_allowlist[integer(tmpI64)];
          if Trim(allowName) = '' then
            Continue;
          allowValue := SysUtils.GetEnvironmentVariable(allowName);
          if allowValue <> '' then
            p.Environment.Add(allowName + '=' + allowValue);
        end;
      except
        // If FPC TProcess.Environment isn't available in this build, skip.
      end;
    end;

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
    sp^.StartTick := GetTickCount64;
    sp^.TimeoutMs := timeoutMs;
    sp^.MaxOutputBytes := maxOutputKb * 1024;
    sp^.TotalOutBytes := 0;
    sp^.TotalErrBytes := 0;
    sp^.TruncatedOut := False;
    sp^.TruncatedErr := False;
    sp^.TimedOut := False;
    sp^.Killed := False;
    sp^.Cwd := p.CurrentDirectory;
    if len64 = -1 then
      sp^.CmdLine := shellCmd
    else
      sp^.CmdLine := p.Executable;
    {$IFDEF WINDOWS}
    sp^.Job := 0;
    {$ENDIF}

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
    if WinCreateKillJob(sp^.Job) then
    begin
      if not WinAssignProcessToJob(sp^.Job, DWORD(p.ProcessID)) then
      begin
        CloseHandle(sp^.Job);
        sp^.Job := 0;
      end;
    end;
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
  if not g_spawn_enabled then
    Exit(QjspThrowHostError(ctx, QJSP_E_SPAWN_DISABLED, 'spawn is disabled by host policy', 'spawn'));

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
    sp^.Killed := True;
    if sp^.Job <> 0 then
    begin
      CloseHandle(sp^.Job);
      sp^.Job := 0;
    end
    else
    begin
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
  obj: JSValue;
  exitCode: cint32;
begin
  if not g_spawn_enabled then
    Exit(QjspThrowHostError(ctx, QJSP_E_SPAWN_DISABLED, 'spawn is disabled by host policy', 'spawn'));

  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('wait expects id')));
  if JS_ToInt64(ctx, @id, argv[0]) < 0 then
    Exit(JS_EXCEPTION);
  sp := GetProcById(id);
  if (sp = nil) or (sp^.P = nil) then
    Exit(JS_ThrowTypeError(ctx, PChar('wait: invalid process id')));

  try
    while not sp^.P.WaitOnExit(10) do
    begin
      SpawnPoll(ctx);
    end;
    exitCode := sp^.P.ExitStatus;

    if sp^.TimedOut then
      exitCode := -1;
  finally
    RemoveProcById(id);
  end;

  obj := JS_NewObject(ctx);
  JS_SetPropertyStr(ctx, obj, PChar('code'), JS_NewInt32(ctx, exitCode));
  JS_SetPropertyStr(ctx, obj, PChar('timedOut'), JS_NewBool(ctx, Ord(sp^.TimedOut)));
  JS_SetPropertyStr(ctx, obj, PChar('truncated'), JS_NewBool(ctx, Ord(sp^.TruncatedOut or sp^.TruncatedErr)));
  Result := obj;
end;

function js_wait_async(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  id: cint64;
  sp: PSpawnProcRec;
  resolving_funcs: array[0..1] of JSValue;
  promise: JSValue;
begin
  if not g_spawn_enabled then
    Exit(QjspThrowHostError(ctx, QJSP_E_SPAWN_DISABLED, 'spawn is disabled by host policy', 'spawn'));

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
  nowTick: QWord;
  do_kill: boolean;
begin
  if (ctx = nil) or (g_procs = nil) then
    Exit;

  for i := g_procs.Count - 1 downto 0 do
  begin
    sp := PSpawnProcRec(g_procs[i]);
    if (sp = nil) or (sp^.P = nil) then
      Continue;

    nowTick := GetTickCount64;
    do_kill := False;
    if (sp^.TimeoutMs > 0) and (sp^.StartTick > 0) and (nowTick - sp^.StartTick >= sp^.TimeoutMs) then
    begin
      EnterCriticalSection(sp^.Lock);
      try
        if not sp^.TimedOut then
        begin
          sp^.TimedOut := True;
          do_kill := True;
        end;
      finally
        LeaveCriticalSection(sp^.Lock);
      end;
    end;

    if do_kill then
    begin
      {$IFDEF WINDOWS}
      if sp^.Job <> 0 then
      begin
        CloseHandle(sp^.Job);
        sp^.Job := 0;
      end
      else
        WinKillProcessTree(DWORD(sp^.P.ProcessID));
      {$ENDIF}
      try
        sp^.P.Terminate(1);
      except
      end;
    end;

    repeat
      ch := PopChunk(sp);
      if ch = nil then
        Break;
      try
        if ch^.Kind = sckStdout then
          WriteBytesToStdOut(ch^.Data, ch^.Len)
        else
          WriteBytesToStdErr(ch^.Data, ch^.Len);
      finally
        Finalize(ch^);
        Dispose(ch);
      end;
    until False;

    if sp^.P.WaitOnExit(0) then
    begin
      exitCode := sp^.P.ExitStatus;

      if sp^.TimedOut then
        exitCode := -1;

      if (sp^.WaitAttachedCtx = ctx) and (JS_IsUndefined(sp^.WaitPromise) = 0) then
      begin
        obj := JS_NewObject(ctx);
        JS_SetPropertyStr(ctx, obj, PChar('code'), JS_NewInt32(ctx, exitCode));
        JS_SetPropertyStr(ctx, obj, PChar('timedOut'), JS_NewBool(ctx, Ord(sp^.TimedOut)));
        JS_SetPropertyStr(ctx, obj, PChar('truncated'), JS_NewBool(ctx, Ord(sp^.TruncatedOut or sp^.TruncatedErr)));
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
