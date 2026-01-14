program qjsp;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Types, ctypes, process,
  {$IFDEF WINDOWS}
  Windows,
  {$ENDIF}
  quickjs_types, quickjs_core, quickjs_std,
  qjs_log,
  qcrypto_base64,
  qcrypto_ed25519_sign,
  qar_tooling_backend,
  qar, qjsp_qar_tooling, quickjs_debug, quickjs_memdebug,
  fpjson, jsonparser,
  qar_helpers, dll_helpers, compression_helpers,
  console_utf8,
  tests_config,
  file_utils,
  qjsp_module_loader, http_helpers, http_async_helpers, fs_watch_helpers,
  qjsp_zip_shim, qjsp_spawn_shim, qjsp_crypto_shim;

const
  APP_AUTHOR = 'Nguyen Duc Thinh - dr.nguyenducthinh@gmail.com';
  APP_VERSION_CONST = '1.0.0';
  APP_BUILD_DATE = {$I %DATE%};
  APP_BUILD_TIME = {$I %TIME%};

var
  APP_VERSION: string = APP_VERSION_CONST;

var
  g_print_exec_time: boolean = False;
  g_exec_start_tick: QWord = 0;
  g_exec_time_exitproc_installed: boolean = False;

procedure PrintExecTimeAtExit;
var
  elapsed: QWord;
begin
  if not g_print_exec_time then
    Exit;
  if g_exec_start_tick = 0 then
    Exit;
  elapsed := GetTickCount64 - g_exec_start_tick;
  try
    WriteLn(StdErr, '[TIME] elapsed_ms=', elapsed);
  except
  end;

end;

procedure PrependAppFolderToPath;
var
  appDir: string;
  oldPath: string;
  sep: string;
  appDirNorm: string;
  oldPathNorm: string;
begin
  appDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))));
  if appDir = '' then
    Exit;

  sep := ';';
  oldPath := SysUtils.GetEnvironmentVariable('PATH');

  appDirNorm := LowerCase(appDir);
  oldPathNorm := LowerCase(oldPath);

  if (oldPathNorm <> '') and ((Pos(sep + appDirNorm + sep, sep + oldPathNorm + sep) > 0) or (Pos(sep + appDirNorm, sep + oldPathNorm) = Length(sep + oldPathNorm) - Length(sep + appDirNorm) + 1)) then
    Exit;

  if oldPath = '' then
  begin
    {$IFDEF WINDOWS}
    Windows.SetEnvironmentVariable(PChar('PATH'), PChar(appDir));
    {$ELSE}
    SetEnvironmentVariable('PATH', appDir);
    {$ENDIF}
  end
  else
  begin
    {$IFDEF WINDOWS}
    Windows.SetEnvironmentVariable(PChar('PATH'), PChar(appDir + sep + oldPath));
    {$ELSE}
    SetEnvironmentVariable('PATH', appDir + sep + oldPath);
    {$ENDIF}
  end;
end;

procedure RunBundledNano(const FilePath: string);
var
  p: string;
  nanoPath: string;
  proc: TProcess;
begin
  p := ExpandFileName(FilePath);
  nanoPath := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0)))) + 'nano.exe';
  if not FileExists(nanoPath) then
  begin
    WriteLn('Error: nano.exe not found: ', nanoPath);
    Exit;
  end;

  proc := TProcess.Create(nil);
  try
    proc.Executable := nanoPath;
    proc.Parameters.Clear;
    proc.Parameters.Add(p);
    proc.Options := [poWaitOnExit];
    proc.Execute;
  finally
    proc.Free;
  end;
end;

function GetAppVersion: string;
begin
  Result := APP_VERSION;
  if Result = '' then
    Result := JS_GetVersion;
end;

function GetAppBuildDateTime: string;
begin
  Result := APP_BUILD_DATE + ' ' + APP_BUILD_TIME;
end;

function GetAppIntroLine: string;
begin
  Result := 'QuickJS Pascal ' + GetAppVersion + ' (build ' + GetAppBuildDateTime + ')';
end;

procedure ApplyDebugSettings(rt: PJSRuntime);
begin
  if qjs_log.DebugLevel >= 4 then
    EnableAllDebugDumps(rt)
  else if qjs_log.DebugLevel >= 3 then
    EnableBasicDebugDumps(rt)
  else
    DisableAllDebugDumps(rt);

  if qjs_log.DebugLevel > 0 then
    JS_InstallLoggingPromiseRejectionTracker(rt)
  else
    JS_InstallStdPromiseRejectionTracker(rt);
end;

procedure LoadQjspMountsFromFile(const FileName: string; DebugLevel: integer);
var
  json_content: string;
  jsonData, mountsData: TJSONData;
  rootObj, mountsObj: TJSONObject;
  i: integer;
  key: string;
  item: TJSONData;
  folder: string;
begin
  qjsp_clear_mounts;

  if not FileExists(FileName) then
    Exit;

  if not ReadTextFileToString(FileName, json_content) then
    Exit;

  if json_content = '' then
    Exit;

  try
    jsonData := GetJSON(json_content);
  except
    on E: Exception do
    begin
      if DebugLevel > 0 then
        WriteLn('[DEBUG] Failed to parse config JSON (fpjson): ', E.Message);
      Exit;
    end;
  end;

  try
    if not (jsonData is TJSONObject) then
      Exit;

    rootObj := TJSONObject(jsonData);
    mountsData := rootObj.Find('libraries');
    if (mountsData = nil) or not (mountsData is TJSONObject) then
      Exit;

    mountsObj := TJSONObject(mountsData);
    for i := 0 to mountsObj.Count - 1 do
    begin
      key := mountsObj.Names[i];
      item := mountsObj.Items[i];
      if (item = nil) or (item.JSONType <> jtString) then
        Continue;
      folder := item.AsString;
      qjsp_register_mount(key, folder);
    end;
  finally
    jsonData.Free;
  end;
end;

function JsonGetStringArray(const Obj: TJSONObject; const Name: string): TStringDynArray;
var
  data: TJSONData;
  arr: TJSONArray;
  i: integer;
  item: TJSONData;
begin
  Result := nil;
  if Obj = nil then
    Exit;
  data := Obj.Find(Name);
  if (data = nil) or (not (data is TJSONArray)) then
    Exit;
  arr := TJSONArray(data);
  if arr.Count <= 0 then
    Exit;
  SetLength(Result, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    item := arr.Items[i];
    if (item <> nil) and (item.JSONType = jtString) then
      Result[i] := item.AsString
    else
      Result[i] := '';
  end;
end;

function ReadConfigJsonObject(const FileName: string; DebugLevel: integer): TJSONObject; forward;
function JsonGetString(const Obj: TJSONObject; const Name: string; const DefaultValue: string): string; forward;
function JsonGetInt(const Obj: TJSONObject; const Name: string; const DefaultValue: integer): integer; forward;
function JsonGetQWord(const Obj: TJSONObject; const Name: string; const DefaultValue: QWord): QWord; forward;

procedure LoadSpawnPolicyFromConfig(const FileName: string);
var
  rootObj: TJSONObject;
  settingsData: TJSONData;
  settingsObj: TJSONObject;
  profileName: string;
  spawnData: TJSONData;
  spawnObj: TJSONObject;
  timeoutDefaultMs: QWord;
  maxOutputDefaultKb: QWord;
  maxConcurrent: integer;
  roots: TStringDynArray;
  envNames: TStringDynArray;
begin
  profileName := 'dev_repl';
  timeoutDefaultMs := 30000;
  maxOutputDefaultKb := 256;
  maxConcurrent := 0;
  SetLength(roots, 0);
  SetLength(envNames, 0);

  rootObj := ReadConfigJsonObject(FileName, 0);
  if rootObj = nil then
  begin
    qjsp_spawn_shim.SetSpawnDefaultTimeoutMs(timeoutDefaultMs);
    qjsp_spawn_shim.SetSpawnDefaultMaxOutputKb(maxOutputDefaultKb);
    qjsp_spawn_shim.SetSpawnMaxConcurrent(maxConcurrent);
    SetLength(roots, 0);
    qjsp_spawn_shim.SetSpawnAllowedCwdRoots(roots);
    SetLength(envNames, 0);
    qjsp_spawn_shim.SetSpawnEnvAllowlist(envNames);
    Exit;
  end;

  try
    settingsData := rootObj.Find('settings');
    if (settingsData <> nil) and (settingsData is TJSONObject) then
    begin
      settingsObj := TJSONObject(settingsData);
      profileName := LowerCase(JsonGetString(settingsObj, 'profile', profileName));
    end;

    if profileName = 'prod_automation' then
    begin
      timeoutDefaultMs := 5000;
      maxOutputDefaultKb := 64;
      maxConcurrent := 2;
    end
    else
    begin
      timeoutDefaultMs := 30000;
      maxOutputDefaultKb := 256;
      maxConcurrent := 0;
    end;

    spawnData := rootObj.Find('spawn');
    if (spawnData <> nil) and (spawnData is TJSONObject) then
    begin
      spawnObj := TJSONObject(spawnData);
      timeoutDefaultMs := JsonGetQWord(spawnObj, 'timeout_ms_default', timeoutDefaultMs);
      maxOutputDefaultKb := JsonGetQWord(spawnObj, 'max_output_kb_default', maxOutputDefaultKb);
      maxConcurrent := JsonGetInt(spawnObj, 'max_concurrent', maxConcurrent);
      roots := JsonGetStringArray(spawnObj, 'allowed_cwd_roots');
      envNames := JsonGetStringArray(spawnObj, 'env_allowlist');
    end
    else
    begin
      SetLength(roots, 0);
      SetLength(envNames, 0);
    end;
  finally
    rootObj.Free;
  end;

  qjsp_spawn_shim.SetSpawnDefaultTimeoutMs(timeoutDefaultMs);
  qjsp_spawn_shim.SetSpawnDefaultMaxOutputKb(maxOutputDefaultKb);
  qjsp_spawn_shim.SetSpawnMaxConcurrent(maxConcurrent);
  qjsp_spawn_shim.SetSpawnAllowedCwdRoots(roots);
  qjsp_spawn_shim.SetSpawnEnvAllowlist(envNames);
end;

function ReadConfigJsonObject(const FileName: string; DebugLevel: integer): TJSONObject;
var
  json_content: string;
  jsonData: TJSONData;
begin
  Result := nil;
  if not FileExists(FileName) then
    Exit;
  if not ReadTextFileToString(FileName, json_content) then
    Exit;
  if json_content = '' then
    Exit;
  try
    jsonData := GetJSON(json_content);
  except
    on E: Exception do
    begin
      if DebugLevel > 0 then
        WriteLn('[DEBUG] Failed to parse config JSON (fpjson): ', E.Message);
      Exit;
    end;
  end;
  if (jsonData <> nil) and (jsonData is TJSONObject) then
    Result := TJSONObject(jsonData)
  else if jsonData <> nil then
    jsonData.Free;
end;

procedure WriteConfigJsonObject(const FileName: string; const RootObj: TJSONObject);
var
  f: TextFile;
  jsonStr: string;
  out_dir: string;
begin
  if RootObj = nil then
    Exit;
  jsonStr := RootObj.FormatJSON([]);
  out_dir := ExtractFileDir(FileName);
  if (out_dir <> '') and (not DirectoryExists(out_dir)) then
    ForceDirectories(out_dir);
  AssignFile(f, FileName);
  Rewrite(f);
  try
    Write(f, jsonStr);
  finally
    CloseFile(f);
  end;
end;

type
  TReplGuardMode = (rgStrict, rgFriendly);

function EnsureChildObject(Parent: TJSONObject; const Name: string): TJSONObject;
var
  data: TJSONData;
begin
  Result := nil;
  if Parent = nil then
    Exit;
  data := Parent.Find(Name);
  if (data <> nil) and (data is TJSONObject) then
    Exit(TJSONObject(data));
  if data <> nil then
    Parent.Delete(Parent.IndexOfName(Name));
  Result := TJSONObject.Create;
  Parent.Add(Name, Result);
end;

function JsonGetString(const Obj: TJSONObject; const Name: string; const DefaultValue: string): string;
var
  data: TJSONData;
begin
  Result := DefaultValue;
  if Obj = nil then
    Exit;
  data := Obj.Find(Name);
  if (data <> nil) and (data.JSONType = jtString) then
    Result := data.AsString;
end;

function JsonGetBoolean(const Obj: TJSONObject; const Name: string; const DefaultValue: boolean): boolean;
var
  data: TJSONData;
begin
  Result := DefaultValue;
  if Obj = nil then
    Exit;
  data := Obj.Find(Name);
  if (data <> nil) and (data.JSONType = jtBoolean) then
    Result := data.AsBoolean;
end;

function JsonGetInt(const Obj: TJSONObject; const Name: string; const DefaultValue: integer): integer;
var
  data: TJSONData;
begin
  Result := DefaultValue;
  if Obj = nil then
    Exit;
  data := Obj.Find(Name);
  if (data <> nil) and (data.JSONType = jtNumber) then
    Result := data.AsInteger;
end;

function JsonGetQWord(const Obj: TJSONObject; const Name: string; const DefaultValue: QWord): QWord;
var
  data: TJSONData;
begin
  Result := DefaultValue;
  if Obj = nil then
    Exit;
  data := Obj.Find(Name);
  if (data <> nil) and ((data.JSONType = jtNumber) or (data.JSONType = jtString)) then
  begin
    try
      if data.JSONType = jtString then
        Result := StrToQWord(Trim(data.AsString))
      else
        Result := QWord(data.AsInt64);
    except
      Result := DefaultValue;
    end;
  end;
end;

procedure LoadBoundaryPolicyFromConfig(const FileName: string);
var
  rootObj: TJSONObject;
  spawnData: TJSONData;
  spawnObj: TJSONObject;
  httpData: TJSONData;
  httpObj: TJSONObject;
  fsData: TJSONData;
  fsObj: TJSONObject;
  spawnEnabled: boolean;
  httpEnabled: boolean;
  fsEnabled: boolean;
  httpAllowedHosts: TStringDynArray;
  httpTimeoutDefaultMs: integer;
  httpTimeoutMaxMs: integer;
  httpMaxBodyDefaultKb: integer;
  httpMaxBodyMaxKb: integer;
  fsAllowedRoots: TStringDynArray;
  fsMaxWatchers: integer;
  fsThrottleMs: QWord;
begin
  spawnEnabled := True;
  httpEnabled := True;
  fsEnabled := True;

  SetLength(httpAllowedHosts, 0);
  httpTimeoutDefaultMs := 0;
  httpTimeoutMaxMs := 0;
  httpMaxBodyDefaultKb := 0;
  httpMaxBodyMaxKb := 0;

  SetLength(fsAllowedRoots, 0);
  fsMaxWatchers := 0;
  fsThrottleMs := 0;

  rootObj := ReadConfigJsonObject(FileName, 0);
  if rootObj = nil then
  begin
    qjsp_spawn_shim.SetSpawnEnabled(spawnEnabled);
    http_helpers.SetHttpEnabled(httpEnabled);
    http_async_helpers.SetHttpAsyncEnabled(httpEnabled);
    fs_watch_helpers.SetFsWatchEnabled(fsEnabled);

    http_helpers.SetHttpAllowedHosts(httpAllowedHosts);
    http_helpers.SetHttpDefaultTimeoutMs(httpTimeoutDefaultMs);
    http_helpers.SetHttpMaxTimeoutMs(httpTimeoutMaxMs);
    http_helpers.SetHttpDefaultMaxBodyKb(httpMaxBodyDefaultKb);
    http_helpers.SetHttpMaxBodyKb(httpMaxBodyMaxKb);

    http_async_helpers.SetHttpAsyncAllowedHosts(httpAllowedHosts);
    http_async_helpers.SetHttpAsyncDefaultTimeoutMs(httpTimeoutDefaultMs);
    http_async_helpers.SetHttpAsyncMaxTimeoutMs(httpTimeoutMaxMs);
    http_async_helpers.SetHttpAsyncDefaultMaxBodyKb(httpMaxBodyDefaultKb);
    http_async_helpers.SetHttpAsyncMaxBodyKb(httpMaxBodyMaxKb);

    fs_watch_helpers.SetFsWatchAllowedRoots(fsAllowedRoots);
    fs_watch_helpers.SetFsWatchMaxWatchers(fsMaxWatchers);
    fs_watch_helpers.SetFsWatchThrottleMs(fsThrottleMs);
    Exit;
  end;

  try
    spawnData := rootObj.Find('spawn');
    if (spawnData <> nil) and (spawnData is TJSONObject) then
    begin
      spawnObj := TJSONObject(spawnData);
      spawnEnabled := JsonGetBoolean(spawnObj, 'enabled', spawnEnabled);
    end;

    httpData := rootObj.Find('http');
    if (httpData <> nil) and (httpData is TJSONObject) then
    begin
      httpObj := TJSONObject(httpData);
      httpEnabled := JsonGetBoolean(httpObj, 'enabled', httpEnabled);
      httpAllowedHosts := JsonGetStringArray(httpObj, 'allowed_hosts');
      httpTimeoutDefaultMs := JsonGetInt(httpObj, 'timeout_ms', httpTimeoutDefaultMs);
      httpTimeoutMaxMs := JsonGetInt(httpObj, 'timeout_ms_max', httpTimeoutMaxMs);
      httpMaxBodyDefaultKb := JsonGetInt(httpObj, 'max_body_kb', httpMaxBodyDefaultKb);
      httpMaxBodyMaxKb := JsonGetInt(httpObj, 'max_body_kb_max', httpMaxBodyMaxKb);
    end;

    fsData := rootObj.Find('fs_watch');
    if (fsData <> nil) and (fsData is TJSONObject) then
    begin
      fsObj := TJSONObject(fsData);
      fsEnabled := JsonGetBoolean(fsObj, 'enabled', fsEnabled);
      fsAllowedRoots := JsonGetStringArray(fsObj, 'allowed_roots');
      fsMaxWatchers := JsonGetInt(fsObj, 'max_watchers', fsMaxWatchers);
      fsThrottleMs := JsonGetQWord(fsObj, 'throttle_ms', fsThrottleMs);
    end;
  finally
    rootObj.Free;
  end;

  qjsp_spawn_shim.SetSpawnEnabled(spawnEnabled);
  http_helpers.SetHttpEnabled(httpEnabled);
  http_async_helpers.SetHttpAsyncEnabled(httpEnabled);
  fs_watch_helpers.SetFsWatchEnabled(fsEnabled);

  http_helpers.SetHttpAllowedHosts(httpAllowedHosts);
  http_helpers.SetHttpDefaultTimeoutMs(httpTimeoutDefaultMs);
  http_helpers.SetHttpMaxTimeoutMs(httpTimeoutMaxMs);
  http_helpers.SetHttpDefaultMaxBodyKb(httpMaxBodyDefaultKb);
  http_helpers.SetHttpMaxBodyKb(httpMaxBodyMaxKb);

  http_async_helpers.SetHttpAsyncAllowedHosts(httpAllowedHosts);
  http_async_helpers.SetHttpAsyncDefaultTimeoutMs(httpTimeoutDefaultMs);
  http_async_helpers.SetHttpAsyncMaxTimeoutMs(httpTimeoutMaxMs);
  http_async_helpers.SetHttpAsyncDefaultMaxBodyKb(httpMaxBodyDefaultKb);
  http_async_helpers.SetHttpAsyncMaxBodyKb(httpMaxBodyMaxKb);

  fs_watch_helpers.SetFsWatchAllowedRoots(fsAllowedRoots);
  fs_watch_helpers.SetFsWatchMaxWatchers(fsMaxWatchers);
  fs_watch_helpers.SetFsWatchThrottleMs(fsThrottleMs);
end;

procedure ReadBoundaryPolicyFlagsFromConfig(const FileName: string;
  out SpawnEnabled: boolean; out HttpEnabled: boolean; out FsWatchEnabled: boolean);
var
  rootObj: TJSONObject;
  spawnData: TJSONData;
  spawnObj: TJSONObject;
  httpData: TJSONData;
  httpObj: TJSONObject;
  fsData: TJSONData;
  fsObj: TJSONObject;
begin
  SpawnEnabled := True;
  HttpEnabled := True;
  FsWatchEnabled := True;

  rootObj := ReadConfigJsonObject(FileName, 0);
  if rootObj = nil then
    Exit;
  try
    spawnData := rootObj.Find('spawn');
    if (spawnData <> nil) and (spawnData is TJSONObject) then
    begin
      spawnObj := TJSONObject(spawnData);
      SpawnEnabled := JsonGetBoolean(spawnObj, 'enabled', SpawnEnabled);
    end;

    httpData := rootObj.Find('http');
    if (httpData <> nil) and (httpData is TJSONObject) then
    begin
      httpObj := TJSONObject(httpData);
      HttpEnabled := JsonGetBoolean(httpObj, 'enabled', HttpEnabled);
    end;

    fsData := rootObj.Find('fs_watch');
    if (fsData <> nil) and (fsData is TJSONObject) then
    begin
      fsObj := TJSONObject(fsData);
      FsWatchEnabled := JsonGetBoolean(fsObj, 'enabled', FsWatchEnabled);
    end;
  finally
    rootObj.Free;
  end;
end;

procedure LoadRuntimeAndHostSettingsFromConfig(const FileName: string;
  var ConfigDirty: boolean;
  var ReplGuardMode: TReplGuardMode; var GuardExplicit: boolean;
  var ActiveReplMode: string;
  var DumpFlagsExplicit: boolean; var DumpFlagsValue: cuint64);
var
  rootObj: TJSONObject;
  settingsData: TJSONData;
  settingsObj: TJSONObject;
  debugLevel: integer;
  tsOn: boolean;
  guardMode: string;
  modeName: string;
  dumpFlags: QWord;
begin
  rootObj := ReadConfigJsonObject(FileName, 0);
  if rootObj = nil then
    Exit;
  try
    settingsData := rootObj.Find('settings');
    if (settingsData = nil) or (not (settingsData is TJSONObject)) then
      Exit;
    settingsObj := TJSONObject(settingsData);

    debugLevel := JsonGetInt(settingsObj, 'debug_level', -1);
    if (debugLevel >= 0) and (debugLevel <= 4) then
      qjs_log.SetLogLevelFromDebugLevel(debugLevel);

    tsOn := JsonGetBoolean(settingsObj, 'log_timestamp', qjs_log.LogShowTimestamp);
    qjs_log.LogShowTimestamp := tsOn;

    guardMode := LowerCase(JsonGetString(settingsObj, 'guard', ''));
    if guardMode <> '' then
    begin
      if guardMode = 'strict' then
        ReplGuardMode := rgStrict
      else if guardMode = 'friendly' then
        ReplGuardMode := rgFriendly;
      GuardExplicit := True;
    end;

    modeName := JsonGetString(settingsObj, 'mode', '');
    if modeName <> '' then
      ActiveReplMode := modeName;

    dumpFlags := JsonGetQWord(settingsObj, 'dump_flags', QWord(0));
    if dumpFlags <> 0 then
    begin
      DumpFlagsExplicit := True;
      DumpFlagsValue := cuint64(dumpFlags);
    end
    else if (settingsObj.Find('dump_flags') <> nil) then
    begin
      DumpFlagsExplicit := True;
      DumpFlagsValue := 0;
    end;
  finally
    rootObj.Free;
  end;
end;

procedure SaveRuntimeAndHostSettingsToConfig(const FileName: string;
  const ReplGuardMode: TReplGuardMode; const GuardExplicit: boolean;
  const ActiveReplMode: string;
  const DumpFlagsExplicit: boolean; const DumpFlagsValue: cuint64);
var
  rootObj: TJSONObject;
  settingsObj: TJSONObject;
begin
  rootObj := ReadConfigJsonObject(FileName, qjs_log.DebugLevel);
  if rootObj = nil then
    rootObj := TJSONObject.Create;
  try
    if rootObj.Find('config_version') = nil then
      rootObj.Add('config_version', 1);

    settingsObj := EnsureChildObject(rootObj, 'settings');
    if settingsObj <> nil then
    begin
      if settingsObj.IndexOfName('debug_level') >= 0 then
        settingsObj.Integers['debug_level'] := qjs_log.DebugLevel
      else
        settingsObj.Add('debug_level', qjs_log.DebugLevel);

      if settingsObj.IndexOfName('log_timestamp') >= 0 then
        settingsObj.Booleans['log_timestamp'] := qjs_log.LogShowTimestamp
      else
        settingsObj.Add('log_timestamp', qjs_log.LogShowTimestamp);

      if GuardExplicit then
      begin
        if ReplGuardMode = rgStrict then
        begin
          if settingsObj.IndexOfName('guard') >= 0 then
            settingsObj.Strings['guard'] := 'strict'
          else
            settingsObj.Add('guard', 'strict');
        end
        else
        begin
          if settingsObj.IndexOfName('guard') >= 0 then
            settingsObj.Strings['guard'] := 'friendly'
          else
            settingsObj.Add('guard', 'friendly');
        end;
      end;

      if ActiveReplMode <> '' then
      begin
        if settingsObj.IndexOfName('mode') >= 0 then
          settingsObj.Strings['mode'] := ActiveReplMode
        else
          settingsObj.Add('mode', ActiveReplMode);
      end;

      if DumpFlagsExplicit then
      begin
        if settingsObj.IndexOfName('dump_flags') >= 0 then
          settingsObj.Int64s['dump_flags'] := Int64(QWord(DumpFlagsValue))
        else
          settingsObj.Add('dump_flags', Int64(QWord(DumpFlagsValue)));
      end;
    end;

    WriteConfigJsonObject(FileName, rootObj);
  finally
    rootObj.Free;
  end;
end;

// Forward declaration (used by LoadAndExecuteJSFile helper)
function RunScriptFile(ctx: PJSContext; const filename: string): boolean; forward;

procedure ConfigLibrariesList(const FileName: string; DebugLevel: integer);
var
  rootObj: TJSONObject;
  libsData: TJSONData;
  libsObj: TJSONObject;
  i: integer;
begin
  rootObj := ReadConfigJsonObject(FileName, DebugLevel);
  if rootObj = nil then
  begin
    WriteLn('No config file: ', FileName);
    Exit;
  end;
  try
    libsData := rootObj.Find('libraries');
    if (libsData = nil) or (not (libsData is TJSONObject)) then
    begin
      WriteLn('No libraries configured.');
      Exit;
    end;
    libsObj := TJSONObject(libsData);
    if libsObj.Count = 0 then
    begin
      WriteLn('No libraries configured.');
      Exit;
    end;
    WriteLn('Libraries:');
    for i := 0 to libsObj.Count - 1 do
      WriteLn('  ', libsObj.Names[i], '=', libsObj.Strings[libsObj.Names[i]]);
  finally
    rootObj.Free;
  end;
end;

procedure ConfigLibrariesListPretty(const FileName: string; DebugLevel: integer);
var
  rootObj: TJSONObject;
  libsData: TJSONData;
  libsObj: TJSONObject;
  i: integer;
  maxPfx: integer;
  pfx, cfgPath, resolvedPath: string;
  configDir, pascalRoot: string;
  ok: boolean;
begin
  rootObj := ReadConfigJsonObject(FileName, DebugLevel);
  if rootObj = nil then
  begin
    WriteLn('No config file: ', FileName);
    Exit;
  end;
  try
    libsData := rootObj.Find('libraries');
    if (libsData = nil) or (not (libsData is TJSONObject)) then
    begin
      WriteLn('No libraries configured.');
      Exit;
    end;
    libsObj := TJSONObject(libsData);
    if libsObj.Count = 0 then
    begin
      WriteLn('No libraries configured.');
      Exit;
    end;

    maxPfx := 0;
    for i := 0 to libsObj.Count - 1 do
      if Length(libsObj.Names[i]) > maxPfx then
        maxPfx := Length(libsObj.Names[i]);
    if maxPfx < 3 then
      maxPfx := 3;

    configDir := ExtractFileDir(ExpandFileName(FileName));
    pascalRoot := ExpandFileName(IncludeTrailingPathDelimiter(configDir) + '..');

    WriteLn('Libraries (mounts):');
    WriteLn('  ', Format('%-*s  %-22s  %-7s %s', [maxPfx, 'PFX', 'PATH', 'STATUS', 'RESOLVED']));
    for i := 0 to libsObj.Count - 1 do
    begin
      pfx := libsObj.Names[i];
      cfgPath := libsObj.Strings[pfx];
      if (ExtractFileDrive(cfgPath) <> '') or ((Length(cfgPath) > 0) and ((cfgPath[1] = PathDelim) or (cfgPath[1] = '/'))) then
        resolvedPath := ExpandFileName(cfgPath)
      else
        resolvedPath := ExpandFileName(IncludeTrailingPathDelimiter(pascalRoot) + cfgPath);

      ok := DirectoryExists(resolvedPath);
      if ok then
        WriteLn('  ', Format('%-*s  %-22s  %-7s %s', [maxPfx, pfx, cfgPath, 'OK', resolvedPath]))
      else
        WriteLn('  ', Format('%-*s  %-22s  %-7s %s', [maxPfx, pfx, cfgPath, 'MISSING', resolvedPath]));
    end;
  finally
    rootObj.Free;
  end;
end;

procedure ConfigLibrariesAdd(const FileName: string; DebugLevel: integer; const Prefix: string; const Folder: string);
var
  rootObj: TJSONObject;
  libsData: TJSONData;
  libsObj: TJSONObject;
  idx: integer;
begin
  rootObj := ReadConfigJsonObject(FileName, DebugLevel);
  if rootObj = nil then
    rootObj := TJSONObject.Create;
  try
    libsData := rootObj.Find('libraries');
    if (libsData = nil) or (not (libsData is TJSONObject)) then
    begin
      libsObj := TJSONObject.Create;
      rootObj.Add('libraries', libsObj);
    end
    else
      libsObj := TJSONObject(libsData);

    idx := libsObj.IndexOfName(Prefix);
    if idx >= 0 then
      libsObj.Strings[Prefix] := Folder
    else
      libsObj.Add(Prefix, Folder);

    WriteConfigJsonObject(FileName, rootObj);
  finally
    rootObj.Free;
  end;
end;

procedure ConfigLibrariesRemove(const FileName: string; DebugLevel: integer; const Prefix: string);
var
  rootObj: TJSONObject;
  libsData: TJSONData;
  libsObj: TJSONObject;
  idx: integer;
begin
  rootObj := ReadConfigJsonObject(FileName, DebugLevel);
  if rootObj = nil then
    Exit;
  try
    libsData := rootObj.Find('libraries');
    if (libsData = nil) or (not (libsData is TJSONObject)) then
      Exit;
    libsObj := TJSONObject(libsData);
    idx := libsObj.IndexOfName(Prefix);
    if idx >= 0 then
      libsObj.Delete(idx);
    WriteConfigJsonObject(FileName, rootObj);
  finally
    rootObj.Free;
  end;
end;

function LoadAndExecuteJSFile(ctx: PJSContext; const filename: string): Boolean;
begin
  Result := RunScriptFile(ctx, filename);
end;

function EnsureDirExists(const dir: string): boolean;
begin
  if dir = '' then
    Exit(False);
  if DirectoryExists(dir) then
    Exit(True);
  Result := ForceDirectories(dir);
end;

function CopyFileTo(const src, dst: string): boolean;
var
  inS, outS: TFileStream;
begin
  Result := False;
  if not FileExists(src) then
    Exit;
  if not EnsureDirExists(ExtractFileDir(dst)) then
    Exit;
  try
    inS := TFileStream.Create(src, fmOpenRead or fmShareDenyNone);
    try
      outS := TFileStream.Create(dst, fmCreate);
      try
        outS.CopyFrom(inS, 0);
        Result := True;
      finally
        outS.Free;
      end;
    finally
      inS.Free;
    end;
  except
    Result := False;
  end;
end;

function DeleteDirRecursive(const dir: string): boolean;
var
  sr: TSearchRec;
  p: string;
begin
  Result := True;
  if (dir = '') or (not DirectoryExists(dir)) then
    Exit(True);

  if FindFirst(IncludeTrailingPathDelimiter(dir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        Continue;
      p := IncludeTrailingPathDelimiter(dir) + sr.Name;
      if (sr.Attr and faDirectory) <> 0 then
      begin
        if not DeleteDirRecursive(p) then
          Result := False;
      end
      else
      begin
        try
          if not SysUtils.DeleteFile(p) then
            Result := False;
        except
          Result := False;
        end;
      end;
    until FindNext(sr) <> 0;
    SysUtils.FindClose(sr);
  end;

  try
    if not RemoveDir(dir) then
      Result := False;
  except
    Result := False;
  end;
end;

function RunMinifyScript(const minify_script: string; const minify_flags: array of string;
  const input_js, output_js: string): boolean;
var
  p: TProcess;
  self_path: string;
  k: integer;
begin
  Result := False;
  self_path := ExpandFileName(ParamStr(0));
  if not FileExists(self_path) then
    Exit;
  if not FileExists(minify_script) then
    Exit;
  if not EnsureDirExists(ExtractFileDir(output_js)) then
    Exit;

  p := TProcess.Create(nil);
  try
    p.Executable := self_path;
    p.Options := [poWaitOnExit, poUsePipes];
    p.Parameters.Add(minify_script);
    p.Parameters.Add(input_js);
    p.Parameters.Add(output_js);
    for k := 0 to Length(minify_flags) - 1 do
      p.Parameters.Add(minify_flags[k]);
    try
      p.Execute;
    except
      Exit;
    end;
    Result := p.ExitStatus = 0;
  finally
    p.Free;
  end;
end;

function CopyDirRecursive(const minify_script: string; const minify_flags: array of string;
  do_minify: boolean; const src_dir, dst_dir: string): boolean;
var
  sr: TSearchRec;
  src_path, dst_path: string;
  ext: string;
begin
  Result := False;
  if not DirectoryExists(src_dir) then
    Exit;
  if not EnsureDirExists(dst_dir) then
    Exit;

  if FindFirst(IncludeTrailingPathDelimiter(src_dir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        Continue;
      src_path := IncludeTrailingPathDelimiter(src_dir) + sr.Name;
      dst_path := IncludeTrailingPathDelimiter(dst_dir) + sr.Name;
      if (sr.Attr and faDirectory) <> 0 then
      begin
        if not CopyDirRecursive(minify_script, minify_flags, do_minify, src_path, dst_path) then
        begin
          SysUtils.FindClose(sr);
          Exit;
        end;
      end
      else
      begin
        ext := LowerCase(ExtractFileExt(sr.Name));
        if (do_minify) and ((ext = '.js') or (ext = '.mjs')) then
        begin
          if not RunMinifyScript(minify_script, minify_flags, src_path, dst_path) then
          begin
            SysUtils.FindClose(sr);
            Exit;
          end;
        end
        else
        begin
          if not CopyFileTo(src_path, dst_path) then
          begin
            SysUtils.FindClose(sr);
            Exit;
          end;
        end;
      end;
    until FindNext(sr) <> 0;
    SysUtils.FindClose(sr);
  end;
  Result := True;
end;

// shell parsing is handled by qjsp:sh (see sh.repl)

function ExtractManifestEntryPointMain(const manifest_json: UTF8String): UTF8String;
var
  keyPos, p: SizeInt;
  startQ, endQ: SizeInt;
  s: UTF8String;
begin
  Result := '';
  s := manifest_json;
  keyPos := Pos('"entry_points"', s);
  if keyPos <= 0 then
    Exit;
  p := keyPos + Length('"entry_points"');
  while (p <= Length(s)) and (s[p] <> '{') do
    Inc(p);
  if p > Length(s) then
    Exit;

  keyPos := Pos('"main"', Copy(s, p, Length(s)));
  if keyPos <= 0 then
    Exit;
  keyPos := keyPos + p - 1;

  p := keyPos + Length('"main"');
  while (p <= Length(s)) and (s[p] <> ':') do
    Inc(p);
  if p > Length(s) then
    Exit;
  Inc(p);
  while (p <= Length(s)) and (s[p] <= ' ') do
    Inc(p);
  if (p > Length(s)) or (s[p] <> '"') then
    Exit;
  startQ := p + 1;
  endQ := startQ;
  while (endQ <= Length(s)) and (s[endQ] <> '"') do
    Inc(endQ);
  if endQ > Length(s) then
    Exit;
  Result := Copy(s, startQ, endQ - startQ);
end;

function ParseQarEntrySpec(const spec: string; out qar_path: string; out entry_path: string): boolean;
var
  sep_pos: SizeInt;
  lower_spec: string;
begin
  Result := False;
  qar_path := '';
  entry_path := '';
  lower_spec := LowerCase(spec);
  sep_pos := Pos('.qar/', lower_spec);
  if sep_pos = 0 then
    sep_pos := Pos('.qar\\', lower_spec);
  if sep_pos <= 0 then
    Exit;
  qar_path := Copy(spec, 1, sep_pos + 3);
  entry_path := Copy(spec, sep_pos + 5, Length(spec));
  entry_path := StringReplace(entry_path, '\\', '/', [rfReplaceAll]);
  Result := (qar_path <> '') and (entry_path <> '');
end;

function ReadFileToBytes(const filename: string; out bytes: TBytes): boolean;
var
  fs: TFileStream;
begin
  Result := False;
  SetLength(bytes, 0);
  if not FileExists(filename) then
    Exit;
  try
    fs := TFileStream.Create(filename, fmOpenRead or fmShareDenyNone);
    try
      if fs.Size > 0 then
      begin
        SetLength(bytes, fs.Size);
        if fs.Read(bytes[0], Length(bytes)) <> Length(bytes) then
        begin
          SetLength(bytes, 0);
          Exit;
        end;
      end;
      Result := True;
    finally
      fs.Free;
    end;
  except
    SetLength(bytes, 0);
    Result := False;
  end;
end;

function WriteBytesToFile(const filename: string; const bytes: TBytes): boolean;
var
  fs: TFileStream;
begin
  Result := False;
  if not EnsureDirExists(ExtractFileDir(filename)) then
    Exit;
  try
    fs := TFileStream.Create(filename, fmCreate);
    try
      if Length(bytes) > 0 then
        fs.WriteBuffer(bytes[0], Length(bytes));
      Result := True;
    finally
      fs.Free;
    end;
  except
    Result := False;
  end;
end;

function PrepareStagedInputs(const minify_script: string; const minify_flags: array of string;
  do_minify: boolean; var temp_stage_dir: string;
  const in_files: array of string; out staged_files: array of string): boolean;
var
  t: string;
  src, dst: string;
  idx: integer;
  ext: string;
begin
  Result := False;
  if Length(in_files) <> Length(staged_files) then
    Exit;

  t := GetTempDir(False);
  temp_stage_dir := IncludeTrailingPathDelimiter(t) + 'qjsp_qar_stage_' + IntToStr(GetTickCount64);
  if not EnsureDirExists(temp_stage_dir) then
    Exit;

  for idx := 0 to Length(in_files) - 1 do
  begin
    src := in_files[idx];
    if DirectoryExists(src) then
    begin
      dst := IncludeTrailingPathDelimiter(temp_stage_dir) + 'dir_' + IntToStr(idx);
      if not CopyDirRecursive(minify_script, minify_flags, do_minify, src, dst) then
        Exit;
      staged_files[idx] := dst;
    end
    else
    begin
      dst := IncludeTrailingPathDelimiter(temp_stage_dir) + ExtractFileName(src);
      ext := LowerCase(ExtractFileExt(src));
      if (do_minify) and ((ext = '.js') or (ext = '.mjs')) then
      begin
        if not RunMinifyScript(minify_script, minify_flags, src, dst) then
          Exit;
      end
      else
      begin
        if not CopyFileTo(src, dst) then
          Exit;
      end;
      staged_files[idx] := dst;
    end;
  end;
  Result := True;
end;

type
  TReplModeConfig = record
    Name: string;
    ModuleName: string;
    GlobalName: string;
    ReplFunction: string;
    Prompt: string;
  end;

var
  ReplModes: array of TReplModeConfig;
  ActiveReplMode: string;
  ImportedReplModes: TStringList;

function FindReplModeConfig(const ModeName: string; out cfg: TReplModeConfig): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to High(ReplModes) do
  begin
    if SameText(ReplModes[i].Name, ModeName) then
    begin
      cfg := ReplModes[i];
      Exit(True);
    end;
  end;
end;

function ListReplModeNames: string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to High(ReplModes) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + ReplModes[i].Name;
  end;
  if Result = '' then
    Result := '(none)';
end;

const
  HostDotCommands: array[0..19] of string = (
    '.help', '.menu', '.config', '.load',
    '.import', '.reload', '.dump', '.dumpflags',
    '.build', '.qar', '.tool', '.verify',
    '.lib', '.test', '.debug', '.guard',
    '.mode', '.mem', '.gc', '.js'
  );

function IsHostDotCommand(const s: string): boolean;
var
  t: string;
  cmd: string;
  p: SizeInt;
  i: integer;
begin
  t := Trim(LowerCase(s));
  Result := False;
  if (t = '') or (t[1] <> '.') then
    Exit;

  // Extract command name (up to first space)
  p := Pos(' ', t);
  if p > 0 then
    cmd := Copy(t, 1, p - 1)
  else
    cmd := t;

  // Host-reserved dot-commands (handled by qjsp.pas)
  for i := Low(HostDotCommands) to High(HostDotCommands) do
    if cmd = HostDotCommands[i] then
      Exit(True);

  Result := (cmd = '.exit') or (cmd = '.quit');
end;

procedure LoadReplModesFromFile(const FileName: string; DebugLevel: integer);
var
  json_content: string;
  jsonData, modesData, itemData: TJSONData;
  rootObj, modesObj, itemObj: TJSONObject;
  i: integer;
  key: string;
  cfg: TReplModeConfig;
  tmp: TJSONData;

  procedure AddOrReplaceMode(const newCfg: TReplModeConfig);
  var
    j: integer;
  begin
    for j := 0 to High(ReplModes) do
      if SameText(ReplModes[j].Name, newCfg.Name) then
      begin
        ReplModes[j] := newCfg;
        Exit;
      end;
    SetLength(ReplModes, Length(ReplModes) + 1);
    ReplModes[High(ReplModes)] := newCfg;
  end;

begin
  SetLength(ReplModes, 0);

  if not FileExists(FileName) then
    Exit;

  if not ReadTextFileToString(FileName, json_content) then
    Exit;

  if json_content = '' then
    Exit;

  try
    jsonData := GetJSON(json_content);
  except
    on E: Exception do
    begin
      if DebugLevel > 0 then
        WriteLn('[DEBUG] Failed to parse config JSON (fpjson): ', E.Message);
      Exit;
    end;
  end;

  try
    if not (jsonData is TJSONObject) then
      Exit;

    rootObj := TJSONObject(jsonData);

    // New multi-mode block
    modesData := rootObj.Find('repl_modes');
    if (modesData <> nil) and (modesData is TJSONObject) then
    begin
      modesObj := TJSONObject(modesData);
      for i := 0 to modesObj.Count - 1 do
      begin
        key := modesObj.Names[i];
        itemData := modesObj.Items[i];
        if (itemData = nil) or not (itemData is TJSONObject) then
          Continue;
        itemObj := TJSONObject(itemData);

        cfg.Name := key;
        cfg.ModuleName := 'lib:' + key;
        cfg.GlobalName := key;
        cfg.ReplFunction := 'repl';
        cfg.Prompt := key + '> ';

        tmp := itemObj.Find('module');
        if (tmp <> nil) and (tmp.JSONType = jtString) then
          cfg.ModuleName := tmp.AsString;
        tmp := itemObj.Find('global');
        if (tmp <> nil) and (tmp.JSONType = jtString) then
          cfg.GlobalName := tmp.AsString;
        tmp := itemObj.Find('replFunction');
        if (tmp <> nil) and (tmp.JSONType = jtString) then
          cfg.ReplFunction := tmp.AsString;
        tmp := itemObj.Find('prompt');
        if (tmp <> nil) and (tmp.JSONType = jtString) then
          cfg.Prompt := tmp.AsString;

        AddOrReplaceMode(cfg);
      end;
    end;

  finally
    jsonData.Free;
  end;
end;

// Main program
var
  ExampleConfigs: TExampleConfigs;
  ExamplesConfigFile: string;
  config_file_override: string;
  daemon_mode: boolean;
  daemon_in_file: string;
  daemon_out_file: string;
  lib_add_specs: TStringList;
  lib_rm_prefixes: TStringList;
  qar_meta: TStringList;
  qar_created_by: string;
  qar_tool: string;
  lib_ls_mode: boolean;
  lib_changed: boolean;
  config_dirty: boolean;
  dump_flags_explicit: boolean;
  dump_flags_value: cuint64;
  cmdKey: string;
  cmdValue: string;
  eq_pos: SizeInt;
  spec_pfx: string;
  spec_folder: string;
  rt: PJSRuntime;
  ctx: PJSContext;
  globalObj: JSValue;
  ReplGuardMode: TReplGuardMode;
  GuardExplicit: boolean;
  script: string;
  suite_tick0: QWord;
  suite_tick1: QWord;
  test_tick0: QWord;
  test_tick1: QWord;
  result_val: JSValue;
  run_script_mode: boolean;
  script_filename: string;
  script_argc: integer;
  script_args: array of PChar;
  script_args_str: array of string;
  // Used for pretty-printing objects/arrays in the interactive loop
  original_val, stringified: JSValue;
  result_str: PChar;
  i: integer;
  eval_flags: cint;
  // For .load command
  file_content, line: string;
  f: TextFile;
  // For working directory management
  old_dir, script_dir, script_path, test_path, test_key, test_file: string;
  daemon_job_line: string;
  daemon_result_line: string;
  daemon_in: TextFile;
  daemon_out: TextFile;
  daemon_has_in: boolean;
  daemon_has_out: boolean;
  daemon_failed: integer;
  // For QAR pre-registration
  ret: cint;
  is_module: boolean;
  job_result, loop_result: cint;
  pending_ctx: PJSContext;
  // For QAR debugging
  qar_debug: PQarFile;
  entry_count_debug, i_debug: cint;
  entry_debug: qar_helpers.PQarEntryRead;
  entry_path_debug: PChar;
  // For .qar code command
  qar_source_len: csize_t;
  qar_source_ptr: qar.Pcuint8;
  qar_source_str: string;
  // For QAR building
  build_mode: boolean;
  output_file: string;
  input_files: array of string;
  input_count: integer;
  cat_mode: boolean;
  cat_file: string;
  qar_run_mode: boolean;
  qar_run_spec: string;
  qar_extract_mode: boolean;
  qar_extract_file: string;
  qar_extract_dir: string;
  qar_in_place: boolean;
  qar_add_mode: boolean;
  qar_rm_mode: boolean;
  qar_edit_in: string;
  qar_edit_out: string;
  qar_edit_entry: string;
  qar_add_local_file: string;
  qar_ls_mode: boolean;
  qar_ls_file: string;
  qar_ls_prefix: string;
  qar_sep_pos: SizeInt;
  qar_path: string;
  entry_path: string;
  qar_entry_count: cint;
  qar_entry_i: cint;
  qar_entry_p: PQarEntry;
  qar_entry_s: PChar;
  pfx: string;
  qar_manifest_len: csize_t;
  qar_manifest_ptr: PChar;
  dumpFlags: cuint64;
  qar_manifest_str: UTF8String;
  qar_main_entry: UTF8String;
  qar_src_bytes: TBytes;
  qar_src_len: csize_t;
  qar_src_ptr: Pcuint8;
  qar_run_qar_path: string;
  qar_run_entry: string;
  eval_filename: string;
  qar_temp_dir: string;
  qar_tmp_out: string;
  qar_tmp_in: string;
  qar_tmp_out_entry: string;
  qar_tmp_in_entry: string;
  qar_tmp_content: string;
  cmdPrefixLen: integer;
  out_path: string;
  remove_found: boolean;
  do_minify: boolean;
  keep_temp: boolean;
  minify_safe: boolean;
  omit_source: boolean;
  minify_script: string;
  qar_sign_key_file: string;
  minify_flags: array of string;
  temp_stage_dir: string;
  staged: array of string;
  build_inputs_stage: array of string;
  build_inputs_list: array of string;
  qar_inputs_list: array of string;
  qar_inputs_stage: array of string;
  qar_format_version: integer;
  // For .build command
  build_args: TStringList;
  build_output: string;
  build_inputs: array of string;
  build_format_version: integer;
  j: integer;
  // For .qar/.tool/.verify commands
  cmdLine: string;
  cmdArgs: TStringList;
  subcmd: string;
  init_default_lib_qar: boolean;
  qar_file: string;
  qar_output: string;
  qar_input: string;
  qar_inputs: array of string;
  qar_ret: cint;
  qar_inspection: TQarInspectionResult;
  k_qar: integer;
  newDebugLevel: integer;
  exit_code: integer;
  guardArg: string;
  eval_mode: boolean;
  eval_code: string;
  shellJs: string;
  replCfg: TReplModeConfig;
  cmdName: string;
  modeLine: string;
  isOn: boolean;
  policySpawnEnabled: boolean;
  policyHttpEnabled: boolean;
  policyFsWatchEnabled: boolean;
  // QAR keygen
  keygen_seed: TEd25519Seed;
  keygen_pk: TEd25519PublicKey;
  reload_requested: boolean;

{$IFDEF WINDOWS}
type
  NTSTATUS = LongInt;
  ULONG = Cardinal;

function BCryptGenRandom(hAlgorithm: pointer; pbBuffer: PByte; cbBuffer: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external 'bcrypt.dll';

const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = ULONG($00000002);
{$ENDIF}

function QjspGetRandomBytes(out buf: TBytes; len: Integer): boolean;
{$IFDEF WINDOWS}
var
  st: NTSTATUS;
{$ENDIF}
begin
  Result := False;
  SetLength(buf, 0);
  if len <= 0 then
    Exit(True);
  SetLength(buf, len);
{$IFDEF WINDOWS}
  st := BCryptGenRandom(nil, @buf[0], ULONG(len), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  Result := st = 0;
{$ELSE}
  // Fallback (non-Windows): not implemented
  Result := False;
{$ENDIF}
end;

function WriteAllBytesToFile(const filename: string; const bytes: TBytes; out err: string): boolean;
var
  fs: TFileStream;
begin
  Result := False;
  err := '';
  try
    fs := TFileStream.Create(filename, fmCreate);
    try
      if Length(bytes) > 0 then
        fs.WriteBuffer(bytes[0], Length(bytes));
      Result := True;
    finally
      fs.Free;
    end;
  except
    on E: Exception do
      err := E.Message;
  end;
end;

function WriteAllTextToFile(const filename: string; const text: string; out err: string): boolean;
var
  fs: TFileStream;
  b: TBytes;
begin
  Result := False;
  err := '';
  try
    fs := TFileStream.Create(filename, fmCreate);
    try
      if text <> '' then
      begin
        b := BytesOf(AnsiString(text));
        if Length(b) > 0 then
          fs.WriteBuffer(b[0], Length(b));
      end;
      Result := True;
    finally
      fs.Free;
    end;
  except
    on E: Exception do
      err := E.Message;
  end;
end;

procedure AppendDerLen(var outb: TBytes; len: Integer);
var
  n: Integer;
  tmp: array[0..3] of Byte;
begin
  if len < 128 then
  begin
    SetLength(outb, Length(outb) + 1);
    outb[High(outb)] := Byte(len);
    Exit;
  end;
  n := 0;
  while (len > 0) and (n < 4) do
  begin
    tmp[3 - n] := Byte(len and $FF);
    len := len shr 8;
    Inc(n);
  end;
  SetLength(outb, Length(outb) + 1 + n);
  outb[Length(outb) - (1 + n)] := Byte($80 or n);
  Move(tmp[4 - n], outb[Length(outb) - n], n);
end;

function GenerateEd25519PrivateKeyPem(const seed32: TBytes): string;
// RFC 8410 PrivateKeyInfo:
// SEQUENCE { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING (OCTET STRING seed32) }
const
  OID_ED25519: array[0..4] of Byte = ($06, $03, $2B, $65, $70);
var
  der: TBytes;
  inner: TBytes;
  alg: TBytes;
  pk: TBytes;
  pkInner: TBytes;
  total: Integer;
  b64: string;
  i: Integer;
begin
  der := nil;
  inner := nil;
  alg := nil;
  pk := nil;
  pkInner := nil;

  // AlgorithmIdentifier = SEQUENCE(OID)
  SetLength(alg, 0);
  SetLength(alg, Length(alg) + 1);
  alg[High(alg)] := $30;
  AppendDerLen(alg, Length(OID_ED25519));
  SetLength(alg, Length(alg) + Length(OID_ED25519));
  Move(OID_ED25519[0], alg[Length(alg) - Length(OID_ED25519)], Length(OID_ED25519));

  // privateKey = OCTET STRING( OCTET STRING(seed32) )
  SetLength(pkInner, 0);
  SetLength(pkInner, 1);
  pkInner[0] := $04;
  AppendDerLen(pkInner, 32);
  SetLength(pkInner, Length(pkInner) + 32);
  Move(seed32[0], pkInner[Length(pkInner) - 32], 32);

  SetLength(pk, 0);
  SetLength(pk, 1);
  pk[0] := $04;
  AppendDerLen(pk, Length(pkInner));
  SetLength(pk, Length(pk) + Length(pkInner));
  Move(pkInner[0], pk[Length(pk) - Length(pkInner)], Length(pkInner));

  // inner = version + alg + pk
  SetLength(inner, 0);
  // version INTEGER 0
  SetLength(inner, 3);
  inner[0] := $02; inner[1] := $01; inner[2] := $00;
  // append alg
  total := Length(inner);
  SetLength(inner, total + Length(alg));
  Move(alg[0], inner[total], Length(alg));
  // append pk
  total := Length(inner);
  SetLength(inner, total + Length(pk));
  Move(pk[0], inner[total], Length(pk));

  // outer SEQUENCE
  SetLength(der, 0);
  SetLength(der, 1);
  der[0] := $30;
  AppendDerLen(der, Length(inner));
  SetLength(der, Length(der) + Length(inner));
  Move(inner[0], der[Length(der) - Length(inner)], Length(inner));

  b64 := Base64Encode(der);
  Result := '-----BEGIN PRIVATE KEY-----' + LineEnding;
  i := 1;
  while i <= Length(b64) do
  begin
    Result := Result + Copy(b64, i, 64) + LineEnding;
    Inc(i, 64);
  end;
  Result := Result + '-----END PRIVATE KEY-----' + LineEnding;
end;

function DrainPendingJobs(ctx: PJSContext): cint;
var
  job_result: cint;
  pending_ctx: PJSContext;
begin
  Result := 0;
  if ctx = nil then
    Exit;

  pending_ctx := nil;
  repeat
    job_result := JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx);
    if job_result < 0 then
    begin
      if pending_ctx <> nil then
        js_std_dump_error(pending_ctx)
      else
        js_std_dump_error(ctx);
      Result := job_result;
      Exit;
    end;
  until job_result = 0;
end;

function RunExecutionPipeline(ctx: PJSContext; run_std_loop: boolean): boolean;
var
  loop_result: cint;
begin
  Result := False;
  if ctx = nil then
    Exit;

  if DrainPendingJobs(ctx) < 0 then
    Exit;

  SpawnPoll(ctx);
  if run_std_loop then
  begin
    loop_result := js_std_loop(ctx);
    if loop_result <> 0 then
    begin
      js_std_dump_error(ctx);
      Exit;
    end;
  end;

  Result := True;
end;

// Run a JS file (non-interactive mode)
function RunScriptFile(ctx: PJSContext; const filename: string): boolean;
var
  file_content: string;
  eval_flags: cint;
  script_path: string;
  old_dir, script_dir: string;
  is_module: boolean;
  result_val: JSValue;
begin
  Result := False;

  if not ResolveScriptPath(filename, script_path) then
  begin
    if qjs_log.DebugLevel > 0 then
      WriteLn('[DEBUG] File not found: ', filename, ' (tried: ', script_path, ')');
    Exit;
  end;

  old_dir := GetCurrentDir;
  script_dir := ExtractFileDir(script_path);
  qar_helpers.CurrentScriptDir := script_dir;
  if script_dir <> '' then
  begin
    try
      SetCurrentDir(script_dir);
    except
      // ignore
    end;
  end;

  file_content := '';
  AssignFile(f, script_path);
  Reset(f);
  while not EOF(f) do
  begin
    ReadLn(f, line);
    if file_content <> '' then
      file_content := file_content + LineEnding;
    file_content := file_content + line;
  end;
  CloseFile(f);

  is_module := False;
  if (Pos('import ', file_content) > 0) or (Pos('export ', file_content) > 0) then
    is_module := True
  else if JS_DetectModule(PChar(file_content), QWord(Length(file_content))) <> 0 then
    is_module := True;

  if is_module then
    eval_flags := JS_EVAL_TYPE_MODULE
  else
  begin
    eval_flags := JS_EVAL_TYPE_GLOBAL;
  end;

  result_val := JS_Eval(ctx, PChar(file_content), QWord(Length(file_content)),
    PChar(script_path), eval_flags);

  try
    SetCurrentDir(old_dir);
  except
    // ignore restore errors
  end;

  if JS_IsException(result_val) <> 0 then
  begin
    WriteLn('Error executing file: ', script_path);
    js_std_dump_error(ctx);
    JS_FreeValue(ctx, result_val);
    Result := False;
  end
  else
  begin
    if RunExecutionPipeline(ctx, True) then
    begin
      Flush(Output);
      Result := True;
    end
    else
      Result := False;

    JS_FreeValue(ctx, result_val);
  end;
end;

function RunEvalCode(ctx: PJSContext; const source_name: string; const code: string): boolean;
var
  eval_flags: cint;
  is_module: boolean;
  result_val: JSValue;
begin
  Result := False;

  is_module := False;
  if (Pos('import ', code) > 0) or (Pos('export ', code) > 0) then
    is_module := True
  else if JS_DetectModule(PChar(code), QWord(Length(code))) <> 0 then
    is_module := True;

  if is_module then
    eval_flags := JS_EVAL_TYPE_MODULE
  else
    eval_flags := JS_EVAL_TYPE_GLOBAL;

  if not is_module then
    eval_flags := eval_flags or JS_EVAL_FLAG_ASYNC;

  result_val := JS_Eval(ctx, PChar(code), QWord(Length(code)), PChar(source_name), eval_flags);
  if JS_IsException(result_val) <> 0 then
  begin
    js_std_dump_error(ctx);
    JS_FreeValue(ctx, result_val);
    Exit;
  end;

  if not RunExecutionPipeline(ctx, True) then
  begin
    JS_FreeValue(ctx, result_val);
    Exit;
  end;

  JS_FreeValue(ctx, result_val);
  Result := True;
end;

function JsonEscape(const s: string): string;
var
  i: Integer;
  ch: Char;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    case ch of
      '"': Result := Result + '\\"';
      '\': Result := Result + '\\\\';
      #8: Result := Result + '\\b';
      #9: Result := Result + '\\t';
      #10: Result := Result + '\\n';
      #12: Result := Result + '\\f';
      #13: Result := Result + '\\r';
    else
      if Ord(ch) < 32 then
        Result := Result + '\\u' + IntToHex(Ord(ch), 4)
      else
        Result := Result + ch;
    end;
  end;
end;

function JsTryGetJobResultString(ctx: PJSContext; out outStr: string): boolean;
var
  globalObj: JSValue;
  v: JSValue;
  p: PChar;
begin
  Result := False;
  outStr := '';
  if ctx = nil then
    Exit;

  globalObj := JS_GetGlobalObject(ctx);
  v := JS_GetPropertyStr(ctx, globalObj, PChar('__job_result'));
  JS_FreeValue(ctx, globalObj);

  if (JS_IsUndefined(v) <> 0) or (JS_IsNull(v) <> 0) then
  begin
    JS_FreeValue(ctx, v);
    Exit;
  end;

  p := JS_ToCString(ctx, v);
  if p <> nil then
  begin
    outStr := string(p);
    JS_FreeCString(ctx, p);
    Result := True;
  end;
  JS_FreeValue(ctx, v);
end;

function RunDaemonJobOnce(const ExamplesConfigFile: string; const jobJson: string; out resultJson: string): boolean;
var
  rt: PJSRuntime;
  ctx: PJSContext;
  globalObj: JSValue;
  old_dir: string;
  script_dir: string;
  jsonData: TJSONData;
  jobObj: TJSONObject;
  jobId: string;
  codeStr: string;
  scriptFile: string;
  ok: boolean;
  jobResultStr: string;
begin
  Result := False;
  resultJson := '';

  rt := nil;
  ctx := nil;
  jsonData := nil;
  jobId := '';
  codeStr := '';
  scriptFile := '';
  jobResultStr := '';

  try
    try
      jsonData := GetJSON(jobJson);
    except
      on E: Exception do
      begin
        resultJson := '{"ok":false,"error":"invalid_job_json: ' + JsonEscape(E.Message) + '"}';
        Exit;
      end;
    end;
    if (jsonData = nil) or (not (jsonData is TJSONObject)) then
    begin
      if jsonData <> nil then
        jsonData.Free;
      resultJson := '{"ok":false,"error":"invalid_job_json: expected object"}';
      Exit;
    end;
    jobObj := TJSONObject(jsonData);
    try
      jobId := jobObj.Get('id', '');
      codeStr := jobObj.Get('code', '');
      scriptFile := jobObj.Get('script', '');
    finally
      jsonData.Free;
      jsonData := nil;
    end;

    rt := JS_NewRuntime;
    if rt = nil then
    begin
      resultJson := '{"ok":false,"id":"' + JsonEscape(jobId) + '","error":"Failed to create JS runtime"}';
      Exit;
    end;

    JS_SetMemoryLimit(rt, 64 * 1024 * 1024);
    JS_SetCanBlock(rt, True);

    ctx := JS_NewContext(rt);
    if ctx = nil then
    begin
      resultJson := '{"ok":false,"id":"' + JsonEscape(jobId) + '","error":"Failed to create JS context"}';
      Exit;
    end;

    js_init_module_std(ctx, 'std');
    js_init_module_std(ctx, 'qjs:std');
    js_init_module_os(ctx, 'os');
    js_init_module_os(ctx, 'qjs:os');
    js_init_module_bjson(ctx, 'bjson');
    js_init_module_bjson(ctx, 'qjs:bjson');

    RegisterZipModuleShims(ctx);
    RegisterSpawnModuleShims(ctx);
    RegisterCryptoModuleShims(ctx);

    js_std_init_handlers(rt);
    ApplyDebugSettings(rt);

    JS_SetModuleLoaderFunc(rt, nil, @qjsp_module_loader.qjsp_module_loader, nil);
    js_std_add_helpers(ctx, 0, nil);

    globalObj := JS_GetGlobalObject(ctx);
    JS_DefinePropertyValueStr(ctx, globalObj, PChar('__qjspDebugLevel'), JS_NewInt32(ctx, qjs_log.DebugLevel), JS_PROP_C_W_E);
    JS_FreeValue(ctx, globalObj);

    LoadQjspMountsFromFile(ExamplesConfigFile, qjs_log.DebugLevel);
    LoadReplModesFromFile(ExamplesConfigFile, qjs_log.DebugLevel);
    LoadBoundaryPolicyFromConfig(ExamplesConfigFile);
    LoadSpawnPolicyFromConfig(ExamplesConfigFile);

    qar_helpers.RegisterQarHelpers(ctx);
    dll_helpers.RegisterDllHelpers(ctx);
    compression_helpers.RegisterCompressionHelpers(ctx);
    http_helpers.RegisterHttpHelpers(ctx);
    http_async_helpers.RegisterHttpAsyncHelpers(ctx);
    fs_watch_helpers.RegisterFsWatchHelpers(ctx);

    old_dir := GetCurrentDir;
    try
      script_dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
      script_dir := ExpandFileName(IncludeTrailingPathDelimiter(script_dir) + '..');
      try
        SetCurrentDir(script_dir);
      except
      end;

      ok := True;
      if scriptFile <> '' then
        ok := RunScriptFile(ctx, scriptFile)
      else
        ok := RunEvalCode(ctx, '<daemon_job>', codeStr);
    finally
      try
        SetCurrentDir(old_dir);
      except
      end;
    end;

    if ok then
    begin
      if JsTryGetJobResultString(ctx, jobResultStr) then
        resultJson := '{"ok":true,"id":"' + JsonEscape(jobId) + '","result":"' + JsonEscape(jobResultStr) + '"}'
      else
        resultJson := '{"ok":true,"id":"' + JsonEscape(jobId) + '"}';
      Result := True;
    end
    else
    begin
      resultJson := '{"ok":false,"id":"' + JsonEscape(jobId) + '","error":"job_failed"}';
      Result := False;
    end;
  finally
    if rt <> nil then
      js_std_free_handlers(rt);
    if ctx <> nil then
      JS_FreeContext(ctx);
    if rt <> nil then
      JS_FreeRuntime(rt);
  end;
end;

label
  RestartRuntime;

begin
  ConsoleInitUtf8;

  ExamplesConfigFile := DefaultExamplesConfigFile;
  config_file_override := '';
  daemon_mode := False;
  daemon_in_file := '';
  daemon_out_file := '';
  g_print_exec_time := False;
  if g_exec_start_tick = 0 then
    g_exec_start_tick := GetTickCount64;
  lib_add_specs := TStringList.Create;
  lib_rm_prefixes := TStringList.Create;
  qar_meta := TStringList.Create;
  qar_meta.NameValueSeparator := '=';
  qar_meta.CaseSensitive := False;
  qar_created_by := '';
  qar_tool := '';
  lib_ls_mode := False;
  lib_changed := False;
  config_dirty := False;
  dump_flags_explicit := False;
  dump_flags_value := 0;

  // Check for build QAR mode
  build_mode := False;
  output_file := '';
  input_count := 0;
  input_files := nil;
  cat_mode := False;
  cat_file := '';
  qar_run_mode := False;
  qar_run_spec := '';
  qar_extract_mode := False;
  qar_extract_file := '';
  qar_extract_dir := '';
  qar_in_place := False;
  qar_add_mode := False;
  qar_rm_mode := False;
  qar_edit_in := '';
  qar_edit_out := '';
  qar_edit_entry := '';
  qar_add_local_file := '';
  qar_ls_mode := False;
  qar_ls_file := '';
  qar_ls_prefix := '';
  eval_filename := '<eval>';
  do_minify := False;
  keep_temp := False;
  minify_safe := False;
  minify_script := '';
  minify_flags := nil;
  temp_stage_dir := '';
  run_script_mode := False;
  script_filename := '';
  script_argc := 0;
  exit_code := 0;
  eval_mode := False;
  eval_code := '';
  ReplGuardMode := rgFriendly;
  GuardExplicit := False;
  ActiveReplMode := '';
  ImportedReplModes := TStringList.Create;
  ImportedReplModes.CaseSensitive := False;

  // Resolve --config early so we can load persistent settings before parsing other flags
  for i := 1 to ParamCount do
  begin
    if (ParamStr(i) = '--config') and (i < ParamCount) then
    begin
      ExamplesConfigFile := ParamStr(i + 1);
      Break;
    end;
  end;

  LoadRuntimeAndHostSettingsFromConfig(ExamplesConfigFile,
    config_dirty, ReplGuardMode, GuardExplicit, ActiveReplMode,
    dump_flags_explicit, dump_flags_value);

  LoadBoundaryPolicyFromConfig(ExamplesConfigFile);
  LoadSpawnPolicyFromConfig(ExamplesConfigFile);

  // Parse command line arguments
  i := 1;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '--config') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --config');
        Halt(1);
      end;
      ExamplesConfigFile := ParamStr(i);
    end
    else if (ParamStr(i) = '--daemon') then
    begin
      daemon_mode := True;
    end
    else if (ParamStr(i) = '--time') or (ParamStr(i) = '--print-time') then
    begin
      g_print_exec_time := True;
      if not g_exec_time_exitproc_installed then
      begin
        AddExitProc(@PrintExecTimeAtExit);
        g_exec_time_exitproc_installed := True;
      end;
    end
    else if (ParamStr(i) = '--daemon-in') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --daemon-in');
        Halt(1);
      end;
      daemon_in_file := ParamStr(i);
    end
    else if (ParamStr(i) = '--daemon-out') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --daemon-out');
        Halt(1);
      end;
      daemon_out_file := ParamStr(i);
    end
    else if (ParamStr(i) = '--lib-ls') then
    begin
      lib_ls_mode := True;
    end
    else if (ParamStr(i) = '--lib-add') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --lib-add (expected PREFIX=FOLDER)');
        Halt(1);
      end;
      lib_add_specs.Add(ParamStr(i));
      lib_changed := True;
    end
    else if (ParamStr(i) = '--lib-rm') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --lib-rm (expected PREFIX)');
        Halt(1);
      end;
      lib_rm_prefixes.Add(ParamStr(i));
      lib_changed := True;
    end
    else if (ParamStr(i) = '-o') or (ParamStr(i) = '--output') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for -o');
        Halt(1);
      end;
      output_file := ParamStr(i);
      build_mode := True;
    end
    else if (ParamStr(i) = '--build-qar') or (ParamStr(i) = '-b') then
    begin
      build_mode := True;
    end
    else if (ParamStr(i) = '--created-by') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --created-by');
        Halt(1);
      end;
      qar_created_by := ParamStr(i);
    end
    else if (ParamStr(i) = '--tool') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --tool');
        Halt(1);
      end;
      qar_tool := ParamStr(i);
    end
    else if (ParamStr(i) = '--meta') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --meta (expected K=V)');
        Halt(1);
      end;
      qar_meta.Add(ParamStr(i));
    end
    else if (ParamStr(i) = '--verify') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --verify (off|warn|strict)');
        Halt(1);
      end;
      qar_helpers.SetQarVerifyModeFromString(ParamStr(i));
    end
    else if (ParamStr(i) = '-d') or (ParamStr(i) = '--debug') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        qjs_log.SetLogLevelFromDebugLevel(1); // Default to level 1 if no value provided
      end
      else
      begin
        try
          qjs_log.SetLogLevelFromDebugLevel(StrToInt(ParamStr(i)));
          if (qjs_log.DebugLevel < 0) or (qjs_log.DebugLevel > 4) then
          begin
            WriteLn('Warning: Debug level must be 0-4, using 1');
            qjs_log.SetLogLevelFromDebugLevel(1);
          end;
        except
          WriteLn('Warning: Invalid debug level, using 1');
          qjs_log.SetLogLevelFromDebugLevel(1);
        end;
      end;
    end
    else if (ParamStr(i) = '--guard') or (ParamStr(i) = '--repl-guard') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --guard (strict|friendly)');
        Halt(1);
      end;
      guardArg := LowerCase(ParamStr(i));
      if guardArg = 'strict' then
        ReplGuardMode := rgStrict
      else if guardArg = 'friendly' then
        ReplGuardMode := rgFriendly
      else
      begin
        WriteLn('Error: Invalid --guard value: ', guardArg);
        WriteLn('       Expected: strict | friendly');
        Halt(1);
      end;
      GuardExplicit := True;
    end
    else if (ParamStr(i) = '--mode') or (ParamStr(i) = '--repl-mode') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --mode');
        Halt(1);
      end;
      ActiveReplMode := ParamStr(i);
    end
    else if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
    begin
      WriteLn('QuickJS Pascal');
      WriteLn('Author: ', APP_AUTHOR);
      WriteLn('Version: ', GetAppVersion);
      WriteLn('Build: ', GetAppBuildDateTime);
      WriteLn;
      WriteLn('Usage:');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' [options] [script.js [args...]]');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' [options] -e "code" [args...]');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' [options] -o output.qar inputs...');
      WriteLn;
      WriteLn('Options:');
      WriteLn('  --config FILE        Use config file (default: config/qjsp_config.json)');
      WriteLn('  --lib-ls             List registered libraries (mounts) from config');
      WriteLn('  --lib-add PFX=DIR    Add/update a library mount (relative to pascal_root)');
      WriteLn('  --lib-rm PFX         Remove a library mount');
      WriteLn('  -o, --output FILE    Build QAR file from JavaScript files/directories');
      WriteLn('  -b, --build-qar      Build QAR file (same as -o)');
      WriteLn('  --created-by STR     QAR manifest metadata: created_by');
      WriteLn('  --tool STR           QAR manifest metadata: tool');
      WriteLn('  --meta K=V           QAR manifest metadata: add key/value (repeatable)');
      WriteLn('  --verify MODE        QAR verification mode: off | warn | strict (default: warn)');
      WriteLn('  -d, --debug [LEVEL]  Enable debug output (0=off, 1=basic, 2=verbose, default=1)');
      WriteLn('  --time, --print-time Print total execution time on exit (stderr)');
      WriteLn('  -e CODE              Evaluate JavaScript CODE');
      WriteLn('  --guard MODE         REPL crash guard: strict | friendly');
      WriteLn('  --mode NAME          Start interactive REPL with REPL mode enabled (e.g. sh)');
      WriteLn('  --cat FILE           Print file contents and exit');
      WriteLn('                      (supports: file.qar/entryPath to print embedded source)');
      WriteLn('  --qar-cat FILE       Alias of --cat (for QAR tooling compatibility)');
      WriteLn('  --qar-ls FILE [PFX]  List entries in a QAR file (optionally filtered by prefix)');
      WriteLn('  --qar-run TARGET     Run QAR entry: file.qar/entry.js or file.qar (manifest main)');
      WriteLn('  --qar-extract FILE DIR  Extract QAR entries to DIR/<entryPath>');
      WriteLn('  --in-place           For --qar-add/--qar-rm: update input QAR in place (rebuild+replace)');
      WriteLn('  --qar-add IN OUT ENTRY  Add/replace entry from local file path ENTRY');
      WriteLn('  --qar-rm IN OUT ENTRY   Remove entry path from QAR');
      WriteLn('  --minify             Minify JS sources via minify_qjsp.js before building QAR');
      WriteLn('  --minify-safe        Shortcut: --minify + --safe-rename + --encode-strings');
      WriteLn('  --minify-script FILE Specify minify script (default: minify_qjsp.js)');
      WriteLn('  --minify-flag ARG    Pass through flag(s) to minify script (repeatable)');
      WriteLn('  --keep-temp          Keep temp staging folder when using --minify');
      WriteLn('  -h, --help           Show this help');
      WriteLn;
      WriteLn('Examples:');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --lib-ls');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --lib-add java=java');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --lib-rm java');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' script.js arg1 arg2   (run JS file, no REPL)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -e "print(1+2)"       (run inline code)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -o mylib.qar math.js utils.js');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -o mylib.qar src/');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --cat src/main.js');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --cat mylib.qar/index.js');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --qar-ls mylib.qar');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --qar-run mylib.qar/index.js arg1 arg2');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --qar-extract mylib.qar out_dir');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --qar-rm --in-place mylib.qar index.js');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -d 2                  (interactive mode with verbose debug)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --guard friendly      (interactive mode, no hard crash on AV)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' --mode sh             (interactive shell mode: prompt sh>)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), '                        (interactive mode)');
      Halt(0);
    end
    else if (ParamStr(i) = '--version') or (ParamStr(i) = '-version') then
    begin
      WriteLn(GetAppIntroLine);
      WriteLn('QuickJS Engine: ', JS_GetVersion);
      WriteLn('Author: ', APP_AUTHOR);
      Halt(0);
    end
    else if (ParamStr(i) = '--cat') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --cat');
        Halt(1);
      end;
      cat_mode := True;
      cat_file := ParamStr(i);
    end
    else if (ParamStr(i) = '--qar-cat') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --qar-cat');
        Halt(1);
      end;
      cat_mode := True;
      cat_file := ParamStr(i);
    end
    else if (ParamStr(i) = '--qar-run') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing target for --qar-run');
        Halt(1);
      end;
      qar_run_mode := True;
      qar_run_spec := ParamStr(i);
    end
    else if (ParamStr(i) = '--qar-extract') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --qar-extract');
        Halt(1);
      end;
      qar_extract_mode := True;
      qar_extract_file := ParamStr(i);
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing output directory for --qar-extract');
        Halt(1);
      end;
      qar_extract_dir := ParamStr(i);
    end
    else if (ParamStr(i) = '--in-place') then
    begin
      qar_in_place := True;
    end
    else if (ParamStr(i) = '--qar-add') then
    begin
      // Support: --qar-add --in-place in.qar entry/path.js
      if (i + 1 <= ParamCount) and (ParamStr(i + 1) = '--in-place') then
      begin
        qar_in_place := True;
        Inc(i);
      end;

      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing input filename for --qar-add');
        Halt(1);
      end;
      qar_add_mode := True;
      qar_edit_in := ParamStr(i);

      if not qar_in_place then
      begin
        Inc(i);
        if i > ParamCount then
        begin
          WriteLn('Error: Missing output filename for --qar-add');
          Halt(1);
        end;
        qar_edit_out := ParamStr(i);
      end
      else
      begin
        qar_edit_out := qar_edit_in;
      end;

      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing entry path for --qar-add');
        Halt(1);
      end;
      qar_add_local_file := ParamStr(i);
      // Default archive entry path: just the filename of the local file.
      // This matches common usage: --qar-add --in-place in.qar ../path/to/file.js
      qar_edit_entry := ExtractFileName(qar_add_local_file);
    end
    else if (ParamStr(i) = '--qar-rm') then
    begin
      // Support: --qar-rm --in-place in.qar entry/path.js
      if (i + 1 <= ParamCount) and (ParamStr(i + 1) = '--in-place') then
      begin
        qar_in_place := True;
        Inc(i);
      end;

      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing input filename for --qar-rm');
        Halt(1);
      end;
      qar_rm_mode := True;
      qar_edit_in := ParamStr(i);

      if not qar_in_place then
      begin
        Inc(i);
        if i > ParamCount then
        begin
          WriteLn('Error: Missing output filename for --qar-rm');
          Halt(1);
        end;
        qar_edit_out := ParamStr(i);
      end
      else
      begin
        qar_edit_out := qar_edit_in;
      end;

      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing entry path for --qar-rm');
        Halt(1);
      end;
      qar_edit_entry := ParamStr(i);
    end
    else if (ParamStr(i) = '--qar-ls') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --qar-ls');
        Halt(1);
      end;
      qar_ls_mode := True;
      qar_ls_file := ParamStr(i);

      // Optional prefix argument
      if (i + 1 <= ParamCount) and (Copy(ParamStr(i + 1), 1, 2) <> '--') then
      begin
        Inc(i);
        qar_ls_prefix := ParamStr(i);
      end;
    end
    else if (ParamStr(i) = '--minify') then
    begin
      do_minify := True;
    end
    else if (ParamStr(i) = '--minify-safe') then
    begin
      do_minify := True;
      minify_safe := True;
    end
    else if (ParamStr(i) = '--keep-temp') then
    begin
      keep_temp := True;
    end
    else if (ParamStr(i) = '--minify-script') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing filename for --minify-script');
        Halt(1);
      end;
      minify_script := ParamStr(i);
    end
    else if (ParamStr(i) = '--minify-flag') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing value for --minify-flag');
        Halt(1);
      end;
      SetLength(minify_flags, Length(minify_flags) + 1);
      minify_flags[Length(minify_flags) - 1] := ParamStr(i);
    end
    else if (ParamStr(i) = '-e') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        WriteLn('Error: Missing code for -e');
        Halt(1);
      end;
      eval_mode := True;
      eval_code := ParamStr(i);
    end
    else
    begin
      // Input file/directory
      if Length(input_files) <= input_count then
        SetLength(input_files, input_count + 10);
      input_files[input_count] := ParamStr(i);
      Inc(input_count);
    end;
    Inc(i);
  end;

  if lib_ls_mode then
  begin
    ConfigLibrariesList(ExamplesConfigFile, qjs_log.DebugLevel);
    Halt(0);
  end;
  if lib_changed then
  begin
    for i := 0 to lib_add_specs.Count - 1 do
    begin
      eq_pos := Pos('=', lib_add_specs[i]);
      if eq_pos <= 0 then
      begin
        WriteLn('Error: Invalid --lib-add value (expected PREFIX=FOLDER): ', lib_add_specs[i]);
        Halt(1);
      end;
      spec_pfx := Copy(lib_add_specs[i], 1, eq_pos - 1);
      spec_folder := Copy(lib_add_specs[i], eq_pos + 1, Length(lib_add_specs[i]));
      ConfigLibrariesAdd(ExamplesConfigFile, qjs_log.DebugLevel, spec_pfx, spec_folder);
    end;
    for i := 0 to lib_rm_prefixes.Count - 1 do
      ConfigLibrariesRemove(ExamplesConfigFile, qjs_log.DebugLevel, lib_rm_prefixes[i]);
    Halt(0);
  end;

  lib_add_specs.Free;
  lib_add_specs := nil;
  lib_rm_prefixes.Free;
  lib_rm_prefixes := nil;

  if qar_meta <> nil then
  begin
    // Fallback defaults for manifest metadata (only used when building QAR)
    if qar_created_by = '' then
      qar_created_by := SysUtils.GetEnvironmentVariable('USERNAME') + '@' + SysUtils.GetEnvironmentVariable('COMPUTERNAME');
    if qar_tool = '' then
      qar_tool := ExtractFileName(ParamStr(0)) + ' ' + GetAppVersion + ' (build ' + GetAppBuildDateTime + ')';
  end;

  // If cat mode, print file contents and exit (before any runtime init)
  if cat_mode then
  begin
    if cat_file = '-' then
    begin
      while not EOF(Input) do
      begin
        ReadLn(line);
        WriteLn(line);
      end;
      Halt(0);
    end;

    // Support: file.qar/entryPath -> print embedded source/asset payload
    qar_sep_pos := Pos('.qar/', LowerCase(cat_file));
    if qar_sep_pos = 0 then
      qar_sep_pos := Pos('.qar\\', LowerCase(cat_file));

    if qar_sep_pos > 0 then
    begin
      if not QarCatSpecToStdout(cat_file, file_content) then
      begin
        WriteLn(file_content);
        Halt(1);
      end;
      Halt(0);
    end;

    if not ResolveScriptPath(cat_file, script_path) then
    begin
      WriteLn('Error: File not found: ', cat_file);
      Halt(1);
    end;

    if not ReadTextFileToString(script_path, file_content) then
    begin
      WriteLn('Error: Failed to read file: ', script_path);
      Halt(1);
    end;

    Write(file_content);
    Halt(0);
  end;

  // If QAR list mode, list entries and exit (before any runtime init)
  if qar_ls_mode then
  begin
    if not ResolveScriptPath(qar_ls_file, script_path) then
    begin
      WriteLn('Error: File not found: ', qar_ls_file);
      Halt(1);
    end;

    // Keep CLI compatibility: optional prefix filter, but use the same formatter as qar_tool inspect
    pfx := qar_ls_prefix;
    if not QarPrintInspection(script_path, pfx, file_content) then
    begin
      WriteLn(file_content);
      Halt(1);
    end;
    Halt(0);
  end;

  // If QAR extract mode, extract entries and exit (before any runtime init)
  if qar_extract_mode then
  begin
    if not ResolveScriptPath(qar_extract_file, script_path) then
    begin
      WriteLn('Error: File not found: ', qar_extract_file);
      Halt(1);
    end;
    if not EnsureDirExists(qar_extract_dir) then
    begin
      WriteLn('Error: Cannot create output directory: ', qar_extract_dir);
      Halt(1);
    end;

    if not QarExtractToDir(script_path, qar_extract_dir, file_content) then
    begin
      WriteLn(file_content);
      Halt(1);
    end;
    Halt(0);
  end;

  // QAR add/rm are rebuild-based operations and exit (before any runtime init)
  if qar_add_mode or qar_rm_mode then
  begin
    if not ResolveScriptPath(qar_edit_in, script_path) then
    begin
      WriteLn('Error: File not found: ', qar_edit_in);
      Halt(1);
    end;
    if not FileExists(script_path) then
    begin
      WriteLn('Error: QAR file not found: ', script_path);
      Halt(1);
    end;

    if qar_add_mode and (not FileExists(qar_add_local_file)) then
    begin
      WriteLn('Error: Local file not found for --qar-add: ', qar_add_local_file);
      Halt(1);
    end;

    if (do_minify) and (minify_script = '') then
      minify_script := 'minify_qjsp.js';
    if do_minify then
    begin
      if not FileExists(minify_script) then
        minify_script := 'minify.js';
      if not FileExists(minify_script) then
      begin
        WriteLn('Error: minify script not found: ', minify_script);
        Halt(1);
      end;
      minify_script := ExpandFileName(minify_script);
    end;

    qar_temp_dir := IncludeTrailingPathDelimiter(GetTempDir) +
      'qjsp_qar_edit_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + PathDelim;
    if not ForceDirectories(qar_temp_dir) then
    begin
      WriteLn('Error: Cannot create temporary directory');
      Halt(1);
    end;

    try
      qar_debug := qar_open(PChar(script_path));
      if qar_debug = nil then
      begin
        WriteLn('Error: Failed to open QAR file: ', script_path);
        Halt(1);
      end;

      try
        // Extract all sources/assets to temp dir
        qar_entry_count := qar_get_entry_count(qar_debug);
        for qar_entry_i := 0 to qar_entry_count - 1 do
        begin
          qar_entry_p := qar_get_entry(qar_debug, qar_entry_i);
          if qar_entry_p = nil then
            Continue;
          qar_entry_s := qar_entry_get_path(qar_entry_p);
          if qar_entry_s = nil then
            Continue;
          if qar_entry_load_data(qar_debug, qar_entry_p) < 0 then
            Continue;

          qar_src_len := 0;
          qar_src_ptr := qar_entry_get_source(qar_entry_p, @qar_src_len);
          if qar_src_ptr = nil then
            Continue;

          qar_src_bytes := nil;
          SetLength(qar_src_bytes, qar_src_len);
          if qar_src_len > 0 then
            Move(qar_src_ptr^, qar_src_bytes[0], qar_src_len);

          out_path := qar_temp_dir + string(qar_entry_s);
          out_path := StringReplace(out_path, '/', PathDelim, [rfReplaceAll]);
          if not WriteBytesToFile(out_path, qar_src_bytes) then
          begin
            WriteLn('Error: Failed to write temp file: ', out_path);
            Halt(1);
          end;
        end;
      finally
        qar_close(qar_debug);
        qar_debug := nil;
      end;

      // Apply operation
      qar_edit_entry := StringReplace(qar_edit_entry, '\\', '/', [rfReplaceAll]);
      if qar_rm_mode then
      begin
        out_path := qar_temp_dir + qar_edit_entry;
        out_path := StringReplace(out_path, '/', PathDelim, [rfReplaceAll]);
        remove_found := FileExists(out_path);
        if remove_found then
          SysUtils.DeleteFile(out_path);
        if not remove_found then
        begin
          WriteLn('Error: Entry not found in QAR: ', qar_edit_entry);
          Halt(1);
        end;
      end
      else if qar_add_mode then
      begin
        out_path := qar_temp_dir + qar_edit_entry;
        out_path := StringReplace(out_path, '/', PathDelim, [rfReplaceAll]);
        if not CopyFileTo(qar_add_local_file, out_path) then
        begin
          WriteLn('Error: Failed to copy file into temp dir');
          Halt(1);
        end;
      end;

      // Rebuild (optionally via minify staging)
      if qar_in_place then
        qar_tmp_out := script_path + '.tmp'
      else
        qar_tmp_out := qar_edit_out;

      if do_minify then
      begin
        staged := nil;
        SetLength(staged, 1);
        build_inputs_stage := [qar_temp_dir];
        if not PrepareStagedInputs(minify_script, minify_flags, True, temp_stage_dir, build_inputs_stage, staged) then
        begin
          WriteLn('Error: Failed to prepare minified inputs');
          Halt(1);
        end;
        if qar.BuildQar(qar_tmp_out, staged, '', '', qar_created_by, qar_tool, qar_meta) < 0 then
          Halt(1);
      end
      else
      begin
        if qar.BuildQar(qar_tmp_out, [qar_temp_dir], '', '', qar_created_by, qar_tool, qar_meta) < 0 then
          Halt(1);
      end;

      if qar_in_place then
      begin
        if not CopyFileTo(qar_tmp_out, script_path) then
        begin
          WriteLn('Error: Failed to replace input QAR');
          Halt(1);
        end;
        SysUtils.DeleteFile(qar_tmp_out);
      end;
    finally
      if (do_minify) and (temp_stage_dir <> '') then
      begin
        if keep_temp then
          WriteLn('Keeping temp staging dir: ', temp_stage_dir)
        else
          DeleteDirRecursive(temp_stage_dir);
        temp_stage_dir := '';
      end;
      DeleteDirRecursive(qar_temp_dir);
    end;
    Halt(0);
  end;

  // If QAR run mode, load source and configure eval + args (before any runtime init)
  if qar_run_mode then
  begin
    qar_run_qar_path := '';
    qar_run_entry := '';
    if ParseQarEntrySpec(qar_run_spec, qar_run_qar_path, qar_run_entry) then
    begin
      // ok
    end
    else
    begin
      // treat as file.qar (run manifest main)
      qar_run_qar_path := qar_run_spec;
      qar_run_entry := '';
    end;

    if not ResolveScriptPath(qar_run_qar_path, script_path) then
    begin
      WriteLn('Error: File not found: ', qar_run_qar_path);
      Halt(1);
    end;

    qar_debug := qar_open(PChar(script_path));
    if qar_debug = nil then
    begin
      WriteLn('Error: Failed to open QAR file: ', script_path);
      Halt(1);
    end;

    try
      if qar_run_entry = '' then
      begin
        qar_manifest_len := 0;
        qar_manifest_ptr := qar_get_manifest(qar_debug, @qar_manifest_len);
        if (qar_manifest_ptr = nil) or (qar_manifest_len = 0) then
        begin
          WriteLn('Error: QAR has no manifest; cannot auto-run main entry');
          Halt(1);
        end;
        SetString(qar_manifest_str, qar_manifest_ptr, qar_manifest_len);
        qar_main_entry := ExtractManifestEntryPointMain(qar_manifest_str);
        if qar_main_entry = '' then
        begin
          WriteLn('Error: Manifest has no entry_points.main');
          Halt(1);
        end;
        qar_run_entry := string(qar_main_entry);
      end;

      qar_run_entry := StringReplace(qar_run_entry, '\\', '/', [rfReplaceAll]);
      qar_entry_p := qar_find_entry(qar_debug, PChar(qar_run_entry));
      if qar_entry_p = nil then
      begin
        WriteLn('Error: Entry not found: ', qar_run_entry);
        Halt(1);
      end;
      if qar_entry_load_data(qar_debug, qar_entry_p) < 0 then
      begin
        WriteLn('Error: Failed to load entry data: ', qar_run_entry);
        Halt(1);
      end;

      qar_source_len := 0;
      qar_source_ptr := qar_entry_get_source(qar_entry_p, @qar_source_len);
      if (qar_source_ptr = nil) or (qar_source_len = 0) then
      begin
        WriteLn('Error: Entry has no source/asset payload: ', qar_run_entry);
        Halt(1);
      end;

      SetString(eval_code, PChar(qar_source_ptr), qar_source_len);
      eval_filename := script_path + '/' + qar_run_entry;
      eval_mode := True;

      run_script_mode := True;
      script_filename := eval_filename;
      script_argc := input_count + 1;
      script_args := nil;
      script_args_str := nil;
      SetLength(script_args, script_argc);
      SetLength(script_args_str, script_argc);
      script_args_str[0] := script_filename;
      script_args[0] := PChar(script_args_str[0]);
      for i := 0 to input_count - 1 do
      begin
        script_args_str[i + 1] := input_files[i];
        script_args[i + 1] := PChar(script_args_str[i + 1]);
      end;
    finally
      qar_close(qar_debug);
      qar_debug := nil;
    end;
  end;
  
  // If not building, decide between -e code and script file execution
  if (not build_mode) and eval_mode then
  begin
    run_script_mode := True;
    script_filename := '<eval>';
    script_argc := input_count + 1;
    script_args := nil;
    script_args_str := nil;
    SetLength(script_args, script_argc);
    SetLength(script_args_str, script_argc);

    script_args_str[0] := script_filename;
    script_args[0] := PChar(script_args_str[0]);

    for i := 0 to input_count - 1 do
    begin
      script_args_str[i + 1] := input_files[i];
      script_args[i + 1] := PChar(script_args_str[i + 1]);
    end;
  end
  else if (not build_mode) and (input_count > 0) then
  begin
    run_script_mode := True;
    script_filename := input_files[0];
    script_argc := input_count;
    script_args := nil;
    script_args_str := nil;
    SetLength(script_args, script_argc);
    SetLength(script_args_str, script_argc);
    for i := 0 to script_argc - 1 do
    begin
      script_args_str[i] := input_files[i];
      script_args[i] := PChar(script_args_str[i]);
    end;
  end;

  // If build mode, build QAR and exit
  if build_mode then
  begin
    if output_file = '' then
    begin
      WriteLn('Error: Output filename required (use -o filename.qar)');
      Halt(1);
    end;
    
    if input_count = 0 then
    begin
      WriteLn('Error: No input files specified');
      Halt(1);
    end;
    
    if minify_safe then
    begin
      SetLength(minify_flags, Length(minify_flags) + 2);
      minify_flags[Length(minify_flags) - 2] := '--safe-rename';
      minify_flags[Length(minify_flags) - 1] := '--encode-strings';
    end;

    if do_minify then
    begin
      if minify_script = '' then
        minify_script := 'minify_qjsp.js';
      if not FileExists(minify_script) then
        minify_script := 'minify.js';
      if not FileExists(minify_script) then
      begin
        WriteLn('Error: minify script not found: ', minify_script);
        Halt(1);
      end;
      minify_script := ExpandFileName(minify_script);
    end;

    SetLength(input_files, input_count);

    if do_minify then
    begin
      SetLength(staged, Length(input_files));
      build_inputs_stage := input_files;
      try
        if not PrepareStagedInputs(minify_script, minify_flags, True, temp_stage_dir, input_files, staged) then
        begin
          WriteLn('Error: Failed to prepare minified inputs');
          Halt(1);
        end;
        build_inputs_stage := staged;
        if qar.BuildQar(output_file, build_inputs_stage, '', '', qar_created_by, qar_tool, qar_meta) < 0 then
          Halt(1)
        else
          Halt(0);
      finally
        if temp_stage_dir <> '' then
        begin
          if keep_temp then
            WriteLn('Keeping temp staging dir: ', temp_stage_dir)
          else
            DeleteDirRecursive(temp_stage_dir);
        end;
        temp_stage_dir := '';
      end;
    end
    else
    begin
      if qar.BuildQar(output_file, input_files, '', '', qar_created_by, qar_tool, qar_meta) < 0 then
        Halt(1)
      else
        Halt(0);
    end;
  end;

  if daemon_mode then
  begin
    daemon_failed := 0;
    daemon_has_in := False;
    daemon_has_out := False;

    if daemon_in_file <> '' then
    begin
      AssignFile(daemon_in, daemon_in_file);
      Reset(daemon_in);
      daemon_has_in := True;
    end;

    if daemon_out_file <> '' then
    begin
      AssignFile(daemon_out, daemon_out_file);
      Rewrite(daemon_out);
      daemon_has_out := True;
    end;

    try
      while True do
      begin
        daemon_job_line := '';
        if daemon_has_in then
        begin
          if EOF(daemon_in) then
            Break;
          ReadLn(daemon_in, daemon_job_line);
        end
        else
        begin
          if EOF(Input) then
            Break;
          ReadLn(daemon_job_line);
        end;

        daemon_job_line := Trim(daemon_job_line);
        if daemon_job_line = '' then
          Continue;

        if not RunDaemonJobOnce(ExamplesConfigFile, daemon_job_line, daemon_result_line) then
          Inc(daemon_failed);

        if daemon_has_out then
        begin
          WriteLn(daemon_out, daemon_result_line);
          Flush(daemon_out);
        end
        else
        begin
          WriteLn(daemon_result_line);
          Flush(Output);
        end;
      end;
    finally
      if daemon_has_in then
        CloseFile(daemon_in);
      if daemon_has_out then
        CloseFile(daemon_out);
    end;

    if daemon_failed > 0 then
      Halt(1)
    else
      Halt(0);
  end;

  if not run_script_mode then
  begin
    WriteLn(GetAppIntroLine);
    WriteLn('QuickJS Engine: ', JS_GetVersion);
    WriteLn('Author: ', APP_AUTHOR);
    WriteLn;
  end;

  // Default guard mode if not set explicitly
  if not GuardExplicit then
  begin
    if qjs_log.DebugLevel > 0 then
      ReplGuardMode := rgStrict
    else
      ReplGuardMode := rgFriendly;
  end;

  // Initialize dynamic library handle storage
  dll_helpers.LoadedDynamicLibraries := TStringList.Create;
  dll_helpers.LoadedDynamicLibraries.Sorted := False;

  PrependAppFolderToPath;

RestartRuntime:
  reload_requested := False;

  // Initialize QuickJS runtime
  rt := JS_NewRuntime;
  if rt = nil then
  begin
    WriteLn('Failed to create JS runtime');
    Halt(1);
  end;

  // Set memory limit (64 MB)
  JS_SetMemoryLimit(rt, 64 * 1024 * 1024);

  // Allow the runtime to block while polling OS events (required for timers/async)
  JS_SetCanBlock(rt, True);

  // Create context
  ctx := JS_NewContext(rt);
  if ctx = nil then
  begin
    WriteLn('Failed to create JS context');
    JS_FreeRuntime(rt);
    Halt(1);
  end;

  // Register built-in modules with both default and prefixed names for compatibility
  js_init_module_std(ctx, 'std');
  js_init_module_std(ctx, 'qjs:std');
  js_init_module_os(ctx, 'os');
  js_init_module_os(ctx, 'qjs:os');
  js_init_module_bjson(ctx, 'bjson');
  js_init_module_bjson(ctx, 'qjs:bjson');

  RegisterZipModuleShims(ctx);
  RegisterSpawnModuleShims(ctx);
  RegisterCryptoModuleShims(ctx);

  // Initialize standard handlers
  js_std_init_handlers(rt);

  ApplyDebugSettings(rt);

  if dump_flags_explicit then
    JS_SetDumpFlags(rt, dump_flags_value);

  LoadQjspMountsFromFile(ExamplesConfigFile, qjs_log.DebugLevel);
  LoadReplModesFromFile(ExamplesConfigFile, qjs_log.DebugLevel);

  // Set up module loader
  // App policy loader handles qjsp: prefix then falls back to std QAR/filesystem loader
  JS_SetModuleLoaderFunc(rt, nil, @qjsp_module_loader.qjsp_module_loader, nil);

  // Add standard helpers (console, print, etc.) and scriptArgs
  if (run_script_mode) and (script_argc > 0) then
    js_std_add_helpers(ctx, script_argc, @script_args[0])
  else
    js_std_add_helpers(ctx, 0, nil);

  globalObj := JS_GetGlobalObject(ctx);
  JS_DefinePropertyValueStr(ctx, globalObj, PChar('__qjspDebugLevel'), JS_NewInt32(ctx, qjs_log.DebugLevel), JS_PROP_C_W_E);
  JS_FreeValue(ctx, globalObj);

  // Ensure stdjs/ can be resolved regardless of where qjsp is launched from.
  // After restructuring, stdjs/ is a sibling of app/.
  old_dir := GetCurrentDir;
  try
    script_dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
    script_dir := ExpandFileName(IncludeTrailingPathDelimiter(script_dir) + '..');
    try
      SetCurrentDir(script_dir);
    except
      // ignore
    end;

    file_content :=
      'import ''qjsp:runtime/globals.js'';' + LineEnding;

    result_val := JS_Eval(ctx,
      PChar(file_content),
      QWord(Length(file_content)),
      PChar('<init_stdjs_runtime>'),
      JS_EVAL_TYPE_MODULE);

    if JS_IsException(result_val) <> 0 then
    begin
      js_std_dump_error(ctx);
      JS_FreeValue(ctx, result_val);
    end
    else
    begin
      JS_FreeValue(ctx, result_val);
      RunExecutionPipeline(ctx, False);
    end;
  finally
    try
      SetCurrentDir(old_dir);
    except
      // ignore
    end;
  end;

  // Preload std/os/bjson and set globals (interactive mode only)
  if not run_script_mode then
  begin
    file_content :=
      'import ''qjsp:runtime/repl_globals.js'';' + LineEnding;

    result_val := JS_Eval(ctx,
      PChar(file_content),
      QWord(Length(file_content)),
      PChar('<init_repl_globals>'),
      JS_EVAL_TYPE_MODULE);

    if JS_IsException(result_val) <> 0 then
    begin
      js_std_dump_error(ctx);
      JS_FreeValue(ctx, result_val);
    end
    else
    begin
      JS_FreeValue(ctx, result_val);
      RunExecutionPipeline(ctx, False);
    end;
  end;

  // Register helper functions
  qar_helpers.RegisterQarHelpers(ctx);
  dll_helpers.RegisterDllHelpers(ctx);
  compression_helpers.RegisterCompressionHelpers(ctx);
  http_helpers.RegisterHttpHelpers(ctx);
  http_async_helpers.RegisterHttpAsyncHelpers(ctx);
  fs_watch_helpers.RegisterFsWatchHelpers(ctx);

  if run_script_mode then
  begin
    if eval_mode then
    begin
      if not RunEvalCode(ctx, eval_filename, eval_code) then
        exit_code := 1;
    end
    else
    begin
      if not RunScriptFile(ctx, script_filename) then
        exit_code := 1;
    end;
  end
  else
  begin
    // Load examples configuration
    ExampleConfigs := nil;
    LoadExamplesConfigFromFile(ExampleConfigs, ExamplesConfigFile, qjs_log.DebugLevel);
    if qjs_log.DebugLevel > 0 then
      WriteLn('Debug level: ', qjs_log.DebugLevel);
    if (ActiveReplMode <> '') then
    begin
      if not FindReplModeConfig(ActiveReplMode, replCfg) then
      begin
        WriteLn('Error: unknown REPL mode: ', ActiveReplMode);
        ActiveReplMode := '';
      end
      else
      begin
        if ImportedReplModes.IndexOf(replCfg.Name) < 0 then
        begin
          file_content :=
            'import * as ' + replCfg.GlobalName + ' from ' + QuotedStr(replCfg.ModuleName) + ';' + LineEnding +
            'globalThis[' + QuotedStr(replCfg.GlobalName) + '] = ' + replCfg.GlobalName + ';' + LineEnding;

          if RunEvalCode(ctx, '<repl_mode_import>', file_content) then
            ImportedReplModes.Add(replCfg.Name)
          else
          begin
            WriteLn('Error: failed to import ', replCfg.ModuleName);
            ActiveReplMode := '';
          end;
        end;

        if ActiveReplMode <> '' then
        begin
          file_content :=
            'if (typeof ' + replCfg.GlobalName + '.help === ''function'') ' + replCfg.GlobalName + '.help();' + LineEnding;
          RunEvalCode(ctx, '<repl_mode_help>', file_content);
        end;
      end;
    end;

    if (ActiveReplMode = '') then
    begin
      WriteLn('Commands:');
      WriteLn('  .help                       - Detailed help');
      WriteLn('  .menu                       - Quick command menu');
      WriteLn('  .config ...                 - Persistent settings (show/set/unset/save/reload/reset)');
      WriteLn('  .load <file.js>             - Load & run a JS file');
      WriteLn('  .import <module> [name]     - Import ESM module and bind to global');
      WriteLn('  .reload                     - Reload JS runtime (recreate context/runtime)');
      WriteLn('  .dump <0|on|off|n>           - QuickJS dump flags (bytecode/memory/GC)');
      WriteLn('  .build <out.qar> <inputs..> - Build QAR from JS files/folder');
      WriteLn('  .qar / .tool / .verify      - QAR tooling commands');
      WriteLn('  .lib ...                    - Manage libraries (mounts)');
      WriteLn('  .test ...                   - Run/manage example tests (prints [TIME] per test to stderr)');
      WriteLn('  .debug [on|off|0|1|2|3|4]   - Toggle debug');
      WriteLn('  .guard [strict|friendly]    - REPL crash guard mode');
      WriteLn('  .mode <name> on|off         - Toggle REPL mode (plugin-driven)');
      WriteLn('  .mem                        - Runtime memory usage');
      WriteLn('  .exit/.quit (exit/quit)     - Leave program');
    end;

    // Simple interactive loop
    while True do
    begin
      if (ActiveReplMode <> '') and FindReplModeConfig(ActiveReplMode, replCfg) then
        Write(replCfg.Prompt)
      else
        Write('js> ');
      script := ReadLnUtf8;
      if (script = 'exit') or (script = 'quit') or (script = '.exit') or (script = '.quit') then
        Break;

      if script = '' then
        Continue;

      // Run nano as a host-launched interactive console app.
      // Avoid JS spawn/exec fallback which captures stdout/stderr and can hang/crash for TUI apps.
      if (ActiveReplMode <> '') and SameText(ActiveReplMode, 'sh') and (Length(script) > 0) and (script[1] <> '.') then
      begin
        cmdLine := Trim(script);
        if (Copy(LowerCase(cmdLine), 1, 5) = 'nano ') then
        begin
          cmdArgs := TStringList.Create;
          try
            cmdArgs.Delimiter := ' ';
            cmdArgs.StrictDelimiter := True;
            cmdArgs.DelimitedText := cmdLine;
            if cmdArgs.Count >= 2 then
            begin
              RunBundledNano(cmdArgs[1]);
              Flush(Output);
              Continue;
            end
            else
            begin
              WriteLn('Usage: nano <file>');
              Flush(Output);
              Continue;
            end;
          finally
            cmdArgs.Free;
          end;
        end;
      end;

      // When a REPL mode is active, forward any non-host dot-command to the mode handler.
      // This avoids hardcoding plugin/editor commands in the host.
      if (ActiveReplMode <> '') and (Length(script) > 0) and (script[1] = '.') then
      begin
        if (not IsHostDotCommand(script)) and FindReplModeConfig(ActiveReplMode, replCfg) then
        begin
          if ImportedReplModes.IndexOf(replCfg.Name) < 0 then
          begin
            file_content :=
              'import * as ' + replCfg.GlobalName + ' from ' + QuotedStr(replCfg.ModuleName) + ';' + LineEnding +
              'globalThis[' + QuotedStr(replCfg.GlobalName) + '] = ' + replCfg.GlobalName + ';' + LineEnding;

            if RunEvalCode(ctx, '<repl_mode_import>', file_content) then
              ImportedReplModes.Add(replCfg.Name)
            else
            begin
              WriteLn('Error: failed to import ', replCfg.ModuleName);
              Flush(Output);
              Continue;
            end;
          end;

          shellJs := replCfg.GlobalName + '.' + replCfg.ReplFunction + '(' + QuotedStr(script) + ')';
          script := shellJs;
        end;
      end;

      if (script[1] <> '.') then
      begin
        if (script = 'help') then
        begin
          WriteLn('Hint: use ".help"');
          Flush(Output);
          Continue;
        end;
        if (script = 'menu') then
        begin
          WriteLn('Hint: use ".menu"');
          Flush(Output);
          Continue;
        end;
        if (script = 'reload') then
        begin
          WriteLn('Hint: use ".reload"');
          Flush(Output);
          Continue;
        end;
        if (script = 'js') then
        begin
          WriteLn('Hint: use ".js"');
          Flush(Output);
          Continue;
        end;
        if (script = 'gc') then
        begin
          WriteLn('Hint: use ".gc"');
          Flush(Output);
          Continue;
        end;
        if (script = 'mem') then
        begin
          WriteLn('Hint: use ".mem"');
          Flush(Output);
          Continue;
        end;
        if (script = 'dump') or (script = 'dumpflags') then
        begin
          WriteLn('Hint: use ".dump"');
          Flush(Output);
          Continue;
        end;
        if (script = 'debug') then
        begin
          WriteLn('Hint: use ".debug"');
          Flush(Output);
          Continue;
        end;
        if (script = 'ts') then
        begin
          WriteLn('Hint: use ".ts"');
          Flush(Output);
          Continue;
        end;
        if (script = 'guard') then
        begin
          WriteLn('Hint: use ".guard"');
          Flush(Output);
          Continue;
        end;
        if (script = 'mode') or (Copy(script, 1, 5) = 'mode ') then
        begin
          WriteLn('Hint: use ".mode"');
          Flush(Output);
          Continue;
        end;
      end;

      if (script = '.menu') then
      begin
        dumpFlags := JS_GetDumpFlags(rt);
        if (dumpFlags = 0) then
          modeLine := 'off'
        else
          modeLine := UIntToStr(QWord(dumpFlags));

        if ReplGuardMode = rgStrict then
          cmdName := 'strict'
        else
          cmdName := 'friendly';

        if ActiveReplMode <> '' then
          cmdLine := ActiveReplMode
        else
          cmdLine := 'off';

        if ActiveReplMode <> '' then
        begin
          WriteLn('Menu (', ActiveReplMode, ')');
          WriteLn('============');
          WriteLn('  Status: debug:', qjs_log.DebugLevel, '; dump:', modeLine, '; ts:', BoolToStr(qjs_log.LogShowTimestamp, True), '; guard:', cmdName, '; mode:', cmdLine);
          WriteLn('  .js                         - Back to js>');
          WriteLn('  .reload                     - Reload JS runtime');
          WriteLn('  .config ...                 - Persistent settings');
          WriteLn('  .help                       - Full help');
          WriteLn('  .menu                       - This menu');
          WriteLn('  .exit/.quit                 - Exit program');
        end
        else
        begin
          WriteLn('Menu');
          WriteLn('====');
          WriteLn('  Status: debug:', qjs_log.DebugLevel, '; dump:', modeLine, '; ts:', BoolToStr(qjs_log.LogShowTimestamp, True), '; guard:', cmdName, '; mode:', cmdLine);
          WriteLn('  .reload                     - Reload JS runtime');
          WriteLn('  .gc                         - Run QuickJS garbage collector');
          WriteLn('  .dump <0|on|off|n>           - QuickJS dump flags');
          WriteLn('  .config ...                 - Persistent settings');
          WriteLn('  .mode <name> on|off         - Enable/disable mode (e.g. sh)');
          WriteLn('  .help                       - Full help');
          WriteLn('  .menu                       - This menu');
          WriteLn('  .exit/.quit                 - Exit program');
        end;
        Flush(Output);
        Continue;
      end;

      if (script = '.reload') then
      begin
        reload_requested := True;
        Break;
      end;

      try
        if (script = '.help') then
        begin
          if (ActiveReplMode <> '') and FindReplModeConfig(ActiveReplMode, replCfg) then
          begin
            if ImportedReplModes.IndexOf(replCfg.Name) < 0 then
            begin
              file_content :=
                'import * as ' + replCfg.GlobalName + ' from ' + QuotedStr(replCfg.ModuleName) + ';' + LineEnding +
                'globalThis[' + QuotedStr(replCfg.GlobalName) + '] = ' + replCfg.GlobalName + ';' + LineEnding;

              if RunEvalCode(ctx, '<repl_mode_import>', file_content) then
                ImportedReplModes.Add(replCfg.Name)
              else
              begin
                WriteLn('Error: failed to import ', replCfg.ModuleName);
                Flush(Output);
                Continue;
              end;
            end;

            file_content :=
              'if (typeof ' + replCfg.GlobalName + '.help === ''function'') ' + replCfg.GlobalName + '.help();' + LineEnding;
            RunEvalCode(ctx, '<repl_mode_help>', file_content);
            Flush(Output);
            Continue;
          end;

          WriteLn('Help');
          WriteLn('====');
          WriteLn;
          WriteLn('REPL basics:');
          WriteLn('  - Enter JavaScript expressions/statements to evaluate.');
          WriteLn('  - Type "exit" or "quit" to close the REPL.');
          WriteLn;
          WriteLn('REPL commands:');
          WriteLn('  .help');
          WriteLn('    Show this help.');
          WriteLn;
          WriteLn('  .menu');
          WriteLn('    Show a quick command menu.');
          WriteLn;

          WriteLn('  .config show|set|unset|save|reload|reset');
          WriteLn('    Manage persistent host/runtime settings stored in config/qjsp_config.json.');
          WriteLn('    Example: .config set debug 1');
          WriteLn('             .config save');
          WriteLn;

          WriteLn('  .reload');
          WriteLn('    Reload JS runtime (recreate runtime/context + reload modules).');
          WriteLn;
          WriteLn('  .gc');
          WriteLn('    Run QuickJS garbage collector (free unused JS objects sooner).');
          WriteLn;
          WriteLn('  .dump <0|on|off|n>');
          WriteLn('    Set QuickJS dump flags (bitmask).');
          WriteLn('    Alias: .dumpflags');
          WriteLn('    Common flags: 1=bytecode(final), 2=bytecode(pass2), 32=gc, 128=mem');
          WriteLn('    See: qdocs/01_build_run/dump-flags.md');
          WriteLn;
          WriteLn('QAR security flags (CLI):');
          WriteLn('  --verify off|warn|strict');
          WriteLn('    Control QAR signature/hash verification when loading .qar.');
          WriteLn('  --created-by STR / --tool STR / --meta K=V');
          WriteLn('    Add build metadata into QAR manifest when using -o/--build-qar.');
          WriteLn;

          WriteLn('QAR build format selection (REPL):');
          WriteLn('  .build <out.qar> [--v1|--v2|--format N] [--no-source|--omit-source] [--sign-key <file>] <inputs...>');
          WriteLn('  .qar build <out.qar> [--v1|--v2|--format N] [--no-source|--omit-source] [--sign-key <file>] <inputs...>');
          WriteLn('    Default is v1; use --v2 to emit QAR v2.');
          WriteLn;
          WriteLn('  .load <file.js>');
          WriteLn('    Load and execute a JavaScript file.');
          WriteLn('  .import <module> [name]');
          WriteLn('Library management:');
          WriteLn('  .lib ls');
          WriteLn('    List registered libraries (mounts).');
          WriteLn('  .lib add PFX=DIR');
          WriteLn('    Add/update a library mount (relative to pascal_root).');
          WriteLn('    Import an ES module in MODULE mode and bind it to globalThis.');
          WriteLn('    Example: .import qjsp:sh sh');
          WriteLn('             sh.ls(".")');
          WriteLn;
          WriteLn('  .mode sh on|off');
          WriteLn('    Toggle shell REPL mode. When ON, prompt becomes "sh>" and commands like');
          WriteLn('    "pwd", "ls", "cd <dir>", "which <cmd>" are mapped to qjsp:sh helpers.');
          WriteLn('    Type ".js" to return to JS prompt.');
          WriteLn;
          WriteLn('  .build <out.qar> <file1.js> [file2.js ...]');
          WriteLn('  .build <out.qar> <directory/>');
          WriteLn('    Build a QAR bundle from JS input(s).');
          WriteLn;
          WriteLn('  .qar [subcommand] ...');
          WriteLn('  .tool [subcommand] ...      (alias of .qar)');
          WriteLn('    QAR tooling:');
          WriteLn('      info [--init-lib]       - QAR/QuickJS info');
          WriteLn('      build <out.qar> <inputs...> [--sign-key <keyfile>]');
          WriteLn('      ls <file.qar> [prefix]  - List entries (inspect-style output)');
          WriteLn('      inspect <file.qar>      - Inspect QAR details');
          WriteLn('      cat <file.qar/entryPath>');
          WriteLn('      cat <file.qar> <entryPath> - Print embedded source/asset payload');
          WriteLn('      extract <file.qar> <out_dir> - Extract entries to directory');
          WriteLn('      rebuild <in.qar> <out.qar> [--sign-key <keyfile>]');
          WriteLn('      keygen [<out>] [--raw64 <file>] [--pem <file>]');
          WriteLn('      code <file.qar> <entryPath> - (legacy) Print embedded source code');
          WriteLn('      version                 - QAR/QuickJS version');
          WriteLn('      help                    - This command list');
          WriteLn;
          WriteLn('    QAR signing:');
          WriteLn('      - Use .qar keygen to create an Ed25519 key (raw64 or PEM PKCS#8).');
          WriteLn('      - Use --sign-key with .qar build/rebuild to embed signature into manifest.');
          WriteLn('      Examples:');
          WriteLn('        .qar keygen --pem mykey.pem');
          WriteLn('        .qar build out.qar src/ --sign-key mykey.pem');
          WriteLn;
          WriteLn('  .verify <file.qar>');
          WriteLn('    Quick compatibility check (inspect + compatibility message).');
          WriteLn;
          WriteLn('  .lib [command]');
          WriteLn('    Manage library mounts (stored in config under "libraries"):');
          WriteLn('      list                    - List registered mounts (prefix=folder)');
          WriteLn('      add <pfx> <folder>      - Add/update a mount');
          WriteLn('      remove <pfx>            - Remove a mount');
          WriteLn;
          WriteLn('  .test [command]');
          WriteLn('    Manage and run built-in example tests:');
          WriteLn('      (no args) | run         - Run all enabled tests');
          WriteLn('      list                    - List tests + enabled/disabled');
          WriteLn('      add <name>              - Add a test');
          WriteLn('      remove <name>           - Remove a test');
          WriteLn('      enable <name>           - Enable a test');
          WriteLn('      disable <name>          - Disable a test');
          WriteLn('    Notes:');
          WriteLn('      - .test run prints timing to stderr as: [TIME] test=<name> elapsed_ms=<ms>');
          WriteLn('      - Suite total is printed as: [TIME] suite=tests elapsed_ms=<ms>');
          WriteLn;
          WriteLn('  .debug [on|off|0|1|2|3|4]');
          WriteLn('    Control debug output and runtime debug settings.');
          WriteLn;
          WriteLn('  .mem');
          WriteLn('    Print runtime memory usage.');
          WriteLn;
          WriteLn('Java helper functions (available inside JS):');
          WriteLn('  QAR helpers:');
          WriteLn('    - LoadLibrary("file.qar")   : Load a QAR container');
          WriteLn('    - GetQarInfo("file.qar")    : List/inspect entries');
          WriteLn('    - BuildQar("out.qar", inputs): Build QAR from files/folder');
          WriteLn;
          WriteLn('  Dynamic library helpers:');
          WriteLn('    - LoadLib("name")           : Try load from .qar then system library');
          WriteLn('    - LoadDLL("path")           : Load a specific dynamic library file');
          WriteLn('    - CallDllFunction(id, "Func", "sig", ...args)');
          WriteLn('    - FreeDLL(id)');
          WriteLn;
          WriteLn;
          WriteLn('Tips:');
          WriteLn('  - Use ".qar help" to see QAR tooling commands.');
          WriteLn('  - Use ".qar keygen --pem mykey.pem" then "--sign-key mykey.pem" to sign QAR builds.');
          WriteLn('  - Use ".test list" to see available example test names.');
          WriteLn('  - Use ".lib list" to see registered library mounts.');
          WriteLn;
          Flush(Output);
          Continue;
        end;

        if (Copy(script, 1, 6) = '.mode ') or (script = '.mode') then
        begin
          cmdLine := '';
          if Length(script) > 6 then
            cmdLine := Trim(Copy(script, 7, Length(script)));

          if cmdLine = '' then
          begin
            if ActiveReplMode <> '' then
              WriteLn('REPL mode: ', ActiveReplMode)
            else
              WriteLn('REPL mode: off');
            WriteLn('Usage: .mode <name> on | off');
            Flush(Output);
            Continue;
          end;

          cmdArgs := TStringList.Create;
          try
            cmdArgs.Delimiter := ' ';
            cmdArgs.StrictDelimiter := True;
            cmdArgs.DelimitedText := cmdLine;

            if cmdArgs.Count < 1 then
            begin
              WriteLn('Usage: .mode <name> on | off');
              Flush(Output);
              Continue;
            end;

            cmdName := cmdArgs[0];

            if cmdArgs.Count >= 2 then
              modeLine := LowerCase(cmdArgs[1])
            else
              modeLine := 'on';

            if (modeLine <> 'on') and (modeLine <> 'off') then
            begin
              WriteLn('Warning: Invalid .mode value, must be on or off');
              Flush(Output);
              Continue;
            end;

            isOn := modeLine = 'on';
            if isOn then
            begin
              if not FindReplModeConfig(cmdName, replCfg) then
              begin
                WriteLn('Error: unknown REPL mode: ', cmdName);
                WriteLn('Config file: ', ExamplesConfigFile);
                WriteLn('Available modes: ', ListReplModeNames);
                Flush(Output);
                Continue;
              end;
              ActiveReplMode := replCfg.Name;
              WriteLn('REPL mode enabled: ', ActiveReplMode, ' (type ".js" to return)');
            end
            else
            begin
              ActiveReplMode := '';
              WriteLn('REPL mode disabled');
            end;
          finally
            cmdArgs.Free;
          end;

          Flush(Output);
          Continue;
        end;

        if (ActiveReplMode <> '') and (script = '.js') then
        begin
          ActiveReplMode := '';
          Flush(Output);
          Continue;
        end;

        if (ActiveReplMode <> '') and (Length(script) > 0) and (script[1] <> '.') then
        begin
          if not FindReplModeConfig(ActiveReplMode, replCfg) then
          begin
            WriteLn('Error: invalid REPL mode: ', ActiveReplMode);
            ActiveReplMode := '';
            Flush(Output);
            Continue;
          end;

          // If the line has already been wrapped (e.g. editor dot-commands passed through
          // to the mode handler earlier in the loop), do not wrap it again.
          if Pos(replCfg.GlobalName + '.' + replCfg.ReplFunction + '(', script) = 1 then
          begin
            // keep as-is
          end
          else
          begin

            if ImportedReplModes.IndexOf(replCfg.Name) < 0 then
            begin
              file_content :=
                'import * as ' + replCfg.GlobalName + ' from ' + QuotedStr(replCfg.ModuleName) + ';' + LineEnding +
                'globalThis[' + QuotedStr(replCfg.GlobalName) + '] = ' + replCfg.GlobalName + ';' + LineEnding;

              if RunEvalCode(ctx, '<repl_mode_import>', file_content) then
                ImportedReplModes.Add(replCfg.Name)
              else
              begin
                WriteLn('Error: failed to import ', replCfg.ModuleName);
                Flush(Output);
                Continue;
              end;
            end;

            shellJs := replCfg.GlobalName + '.' + replCfg.ReplFunction + '(' + QuotedStr(script) + ')';
            script := shellJs;
          end;
        end;

        if (Copy(script, 1, 7) = '.guard ') or (script = '.guard') then
        begin
          cmdLine := '';
          if Length(script) > 7 then
            cmdLine := Trim(Copy(script, 8, Length(script)));

          if cmdLine = '' then
          begin
            if ReplGuardMode = rgStrict then
              WriteLn('REPL guard mode: strict')
            else
              WriteLn('REPL guard mode: friendly');
            WriteLn('Usage: .guard strict | friendly');
            Flush(Output);
          end
          else
          begin
            cmdLine := LowerCase(cmdLine);
            if cmdLine = 'strict' then
              ReplGuardMode := rgStrict
            else if cmdLine = 'friendly' then
              ReplGuardMode := rgFriendly
            else
            begin
              WriteLn('Warning: Invalid guard mode, must be strict or friendly');
              Flush(Output);
              Continue;
            end;

            GuardExplicit := True;

            if ReplGuardMode = rgStrict then
              WriteLn('REPL guard mode set to strict')
            else
              WriteLn('REPL guard mode set to friendly');
            Flush(Output);
          end;

          Continue;
        end;

        if (Copy(script, 1, 5) = '.mem ') or (script = '.mem') then
        begin
          DumpRuntimeMemoryUsageToConsole(rt);
          Flush(Output);
          Continue;
        end;

        if (Copy(script, 1, 4) = '.gc ') or (script = '.gc') then
        begin
          WriteLn('GC: Run QuickJS garbage collector to reclaim unused JS objects.');
          try
            JS_RunGC(rt);
            WriteLn('GC: success');
            if qjs_log.DebugLevel > 0 then
              qjs_log.LogMsg(llInfo, 'gc', 'JS_RunGC executed');
          except
            on E: Exception do
            begin
              WriteLn('GC: failed - ', E.Message);
              if qjs_log.DebugLevel > 0 then
                qjs_log.LogMsg(llError, 'gc', 'JS_RunGC failed: ' + E.Message);
            end;
          end;
          Flush(Output);
          Continue;
        end;

        if (Copy(script, 1, 6) = '.dump ') or (script = '.dump') or (Copy(script, 1, 11) = '.dumpflags ') or (script = '.dumpflags') then
        begin
          cmdPrefixLen := 0;
          if Copy(script, 1, 11) = '.dumpflags ' then
            cmdPrefixLen := 11
          else if script = '.dumpflags' then
            cmdPrefixLen := 9
          else if Copy(script, 1, 6) = '.dump ' then
            cmdPrefixLen := 5
          else
            cmdPrefixLen := 4;

          cmdLine := '';
          if Length(script) > cmdPrefixLen then
            cmdLine := Trim(Copy(script, cmdPrefixLen + 1, Length(script)));

          if cmdLine = '' then
          begin
            dumpFlags := JS_GetDumpFlags(rt);
            WriteLn('QuickJS dump flags: ', UIntToStr(QWord(dumpFlags)));
            WriteLn('Usage: .dump <0|on|off|number>');
            WriteLn('Alias: .dumpflags');
            WriteLn('Common flags: 1=bytecode(final), 2=bytecode(pass2), 32=gc, 128=mem');
            WriteLn('See: qdocs/01_build_run/dump-flags.md');
            Flush(Output);
          end
          else
          begin
            cmdLine := LowerCase(cmdLine);
            dumpFlags := JS_GetDumpFlags(rt);
            if cmdLine = 'on' then
              dumpFlags := cuint64($FFFFFFFFFFFFFFFF)
            else if cmdLine = 'off' then
              dumpFlags := 0
            else
            begin
              try
                dumpFlags := cuint64(StrToQWord(cmdLine));
              except
                WriteLn('Warning: Invalid dump flags value');
                Flush(Output);
                Continue;
              end;
            end;
            JS_SetDumpFlags(rt, dumpFlags);
            dumpFlags := JS_GetDumpFlags(rt);
            dump_flags_explicit := True;
            dump_flags_value := dumpFlags;
            config_dirty := True;
            WriteLn('QuickJS dump flags set to ', UIntToStr(QWord(dumpFlags)));
            if (dumpFlags = 0) and (cmdLine <> '0') and (cmdLine <> 'off') then
            begin
              WriteLn('Warning: dump flags remain 0. libqjs may be built without ENABLE_DUMPS.');
              Flush(Output);
            end;
            Flush(Output);
          end;
          Continue;
        end;

        if (Copy(script, 1, 4) = '.ts ') or (script = '.ts') then
        begin
          cmdLine := '';
          if Length(script) > 4 then
            cmdLine := Trim(Copy(script, 5, Length(script)));

          if cmdLine = '' then
          begin
            if qjs_log.LogShowTimestamp then
              WriteLn('Log timestamp: on')
            else
              WriteLn('Log timestamp: off');
            WriteLn('Usage: .ts on | off');
            Flush(Output);
          end
          else
          begin
            cmdLine := LowerCase(cmdLine);
            if cmdLine = 'on' then
              qjs_log.LogShowTimestamp := True
            else if cmdLine = 'off' then
              qjs_log.LogShowTimestamp := False
            else
            begin
              WriteLn('Warning: Invalid .ts value, must be on or off');
              Flush(Output);
              Continue;
            end;
            if qjs_log.LogShowTimestamp then
              WriteLn('Log timestamp enabled')
            else
              WriteLn('Log timestamp disabled');
            config_dirty := True;
            Flush(Output);
          end;
          Continue;
        end;

        if (Copy(script, 1, 7) = '.debug ') or (script = '.debug') then
        begin
          cmdLine := '';
          if Length(script) > 7 then
            cmdLine := Trim(Copy(script, 8, Length(script)));

          if cmdLine = '' then
          begin
            WriteLn('Current debug level: ', qjs_log.DebugLevel);
            WriteLn('Usage: .debug on | off | 0 | 1 | 2 | 3 | 4');
            Flush(Output);
          end
          else
          begin
            cmdLine := LowerCase(cmdLine);
            newDebugLevel := qjs_log.DebugLevel;

            if cmdLine = 'on' then
              newDebugLevel := 1
            else if cmdLine = 'off' then
              newDebugLevel := 0
            else
            begin
              try
                newDebugLevel := StrToInt(cmdLine);
              except
                WriteLn('Warning: Invalid debug level, must be 0-4');
                Flush(Output);
                Continue;
              end;
            end;

            if (newDebugLevel < 0) or (newDebugLevel > 4) then
            begin
              WriteLn('Warning: Debug level must be between 0 and 4');
              Flush(Output);
              Continue;
            end;

            if newDebugLevel = qjs_log.DebugLevel then
            begin
              WriteLn('Debug level is already ', qjs_log.DebugLevel);
              Flush(Output);
            end
            else
            begin
              qjs_log.SetLogLevelFromDebugLevel(newDebugLevel);
              ApplyDebugSettings(rt);
              if dump_flags_explicit then
                JS_SetDumpFlags(rt, dump_flags_value);
              WriteLn('Debug level set to ', qjs_log.DebugLevel);
              Flush(Output);
            end;
          end;

          Continue;
        end;

        if (Copy(script, 1, 8) = '.config ') or (script = '.config') then
        begin
          cmdLine := '';
          if Length(script) > 8 then
            cmdLine := Trim(Copy(script, 9, Length(script)));

          if cmdLine = '' then
          begin
            WriteLn('Usage: .config <show|set|unset|save|reload|reset>');
            Flush(Output);
            Continue;
          end;

          cmdArgs := TStringList.Create;
          try
            cmdArgs.Delimiter := ' ';
            cmdArgs.StrictDelimiter := True;
            cmdArgs.DelimitedText := cmdLine;

            if cmdArgs.Count = 0 then
            begin
              WriteLn('Usage: .config <show|set|unset|save|reload|reset>');
              Flush(Output);
              Continue;
            end;

            cmdName := LowerCase(cmdArgs[0]);
            if cmdName = 'show' then
            begin
              ReadBoundaryPolicyFlagsFromConfig(ExamplesConfigFile, policySpawnEnabled, policyHttpEnabled, policyFsWatchEnabled);
              WriteLn('Config file: ', ExamplesConfigFile);
              WriteLn('settings.debug_level: ', qjs_log.DebugLevel);
              if qjs_log.LogShowTimestamp then
                WriteLn('settings.log_timestamp: on')
              else
                WriteLn('settings.log_timestamp: off');

              if ReplGuardMode = rgStrict then
                WriteLn('settings.guard: strict')
              else
                WriteLn('settings.guard: friendly');

              if ActiveReplMode <> '' then
                WriteLn('settings.mode: ', ActiveReplMode)
              else
                WriteLn('settings.mode: (off)');

              if dump_flags_explicit and (dump_flags_value <> 0) then
                WriteLn('settings.dump: on')
              else
                WriteLn('settings.dump: off');

              if policySpawnEnabled then
                WriteLn('spawn.enabled: on')
              else
                WriteLn('spawn.enabled: off');

              if policyHttpEnabled then
                WriteLn('http.enabled: on')
              else
                WriteLn('http.enabled: off');

              if policyFsWatchEnabled then
                WriteLn('fs_watch.enabled: on')
              else
                WriteLn('fs_watch.enabled: off');
            end
            else if (cmdName = 'set') and (cmdArgs.Count >= 3) then
            begin
              cmdKey := LowerCase(cmdArgs[1]);
              cmdValue := cmdArgs[2];
              if cmdKey = 'debug' then
              begin
                try
                  newDebugLevel := StrToInt(cmdValue);
                except
                  WriteLn('Warning: Invalid debug level, must be 0-4');
                  Flush(Output);
                  Continue;
                end;
                if (newDebugLevel < 0) or (newDebugLevel > 4) then
                begin
                  WriteLn('Warning: Debug level must be between 0 and 4');
                  Flush(Output);
                  Continue;
                end;
                qjs_log.SetLogLevelFromDebugLevel(newDebugLevel);
                ApplyDebugSettings(rt);
                if dump_flags_explicit then
                  JS_SetDumpFlags(rt, dump_flags_value);
                config_dirty := True;
              end
              else if (cmdKey = 'ts') or (cmdKey = 'timestamp') then
              begin
                cmdValue := LowerCase(cmdValue);
                if cmdValue = 'on' then
                  qjs_log.LogShowTimestamp := True
                else if cmdValue = 'off' then
                  qjs_log.LogShowTimestamp := False
                else
                begin
                  WriteLn('Warning: Invalid value for ts, must be on/off');
                  Flush(Output);
                  Continue;
                end;
                config_dirty := True;
              end
              else if cmdKey = 'guard' then
              begin
                cmdValue := LowerCase(cmdValue);
                if cmdValue = 'strict' then
                  ReplGuardMode := rgStrict
                else if cmdValue = 'friendly' then
                  ReplGuardMode := rgFriendly
                else
                begin
                  WriteLn('Warning: Invalid guard mode, must be strict/friendly');
                  Flush(Output);
                  Continue;
                end;
                GuardExplicit := True;
                config_dirty := True;
              end
              else if cmdKey = 'mode' then
              begin
                ActiveReplMode := cmdValue;
                config_dirty := True;
              end
              else if cmdKey = 'dump' then
              begin
                cmdValue := LowerCase(cmdValue);
                if cmdValue = 'on' then
                  dump_flags_value := cuint64($FFFFFFFFFFFFFFFF)
                else if (cmdValue = 'off') or (cmdValue = '0') then
                  dump_flags_value := 0
                else
                begin
                  try
                    dump_flags_value := cuint64(StrToQWord(cmdValue));
                  except
                    WriteLn('Warning: Invalid dump flags value');
                    Flush(Output);
                    Continue;
                  end;
                end;
                dump_flags_explicit := True;
                JS_SetDumpFlags(rt, dump_flags_value);
                config_dirty := True;
              end
              else
              begin
                WriteLn('Unknown config key: ', cmdArgs[1]);
              end;
            end
            else if (cmdName = 'unset') and (cmdArgs.Count >= 2) then
            begin
              cmdKey := LowerCase(cmdArgs[1]);
              if cmdKey = 'mode' then
              begin
                ActiveReplMode := '';
                config_dirty := True;
              end
              else if (cmdKey = 'dump') or (cmdKey = 'dump_flags') then
              begin
                dump_flags_explicit := False;
                config_dirty := True;
              end
              else if cmdKey = 'guard' then
              begin
                GuardExplicit := False;
                config_dirty := True;
              end
              else
              begin
                WriteLn('Unknown config key: ', cmdArgs[1]);
              end;
            end
            else if cmdName = 'save' then
            begin
              SaveRuntimeAndHostSettingsToConfig(ExamplesConfigFile, ReplGuardMode, GuardExplicit,
                ActiveReplMode, dump_flags_explicit, dump_flags_value);
              config_dirty := False;
              WriteLn('Config saved');
            end
            else if cmdName = 'reload' then
            begin
              LoadRuntimeAndHostSettingsFromConfig(ExamplesConfigFile,
                config_dirty, ReplGuardMode, GuardExplicit, ActiveReplMode,
                dump_flags_explicit, dump_flags_value);
              LoadBoundaryPolicyFromConfig(ExamplesConfigFile);
              LoadSpawnPolicyFromConfig(ExamplesConfigFile);
              ApplyDebugSettings(rt);
              if dump_flags_explicit then
                JS_SetDumpFlags(rt, dump_flags_value);
              WriteLn('Config reloaded');
            end
            else if cmdName = 'reset' then
            begin
              qjs_log.SetLogLevelFromDebugLevel(0);
              qjs_log.LogShowTimestamp := True;
              GuardExplicit := False;
              ReplGuardMode := rgFriendly;
              ActiveReplMode := '';
              dump_flags_explicit := False;
              dump_flags_value := 0;
              ApplyDebugSettings(rt);
              config_dirty := True;
              WriteLn('Config reset (not saved yet)');
            end
            else
            begin
              WriteLn('Usage: .config <show|set|unset|save|reload|reset>');
            end;
          finally
            cmdArgs.Free;
          end;

          Flush(Output);
          Continue;
        end;
      
      // Xử lý lệnh .load để load và chạy file JS
      if (Copy(script, 1, 6) = '.load ') or (Copy(script, 1, 5) = '.load') then
      begin
        if Length(script) > 6 then
        begin
          script := Trim(Copy(script, 7, Length(script)));
          if script <> '' then
          begin
            if ResolveScriptPath(script, script_path) then
            begin
              WriteLn('Loading file: ', script_path);
              Flush(Output);

              // Lưu working directory hiện tại và chuyển sang thư mục của file
              old_dir := GetCurrentDir;
              script_dir := ExtractFileDir(script_path);

              // Lưu script directory để LoadLibrary có thể tìm QAR files
              qar_helpers.CurrentScriptDir := script_dir;

              if script_dir <> '' then
              begin
                try
                  SetCurrentDir(script_dir);
                except
                  // Nếu không thể đổi directory, tiếp tục với directory hiện tại
                end;
              end;

              // Đọc file và execute
              file_content := '';
              if not ReadTextFileToString(script_path, file_content) then
              begin
                try
                  SetCurrentDir(old_dir);
                except
                  // ignore
                end;
                WriteLn('Error loading file: ', script_path);
                Flush(Output);
                Continue;
              end;
              
              // Execute file content
              if qjs_log.DebugLevel > 1 then
              begin
                WriteLn('[DEBUG] Before executing script:');
                WriteLn('  Current working directory: ', GetCurrentDir);
                WriteLn('  Script directory: ', script_dir);
                WriteLn('  CurrentScriptDir: ', qar_helpers.CurrentScriptDir);
                Flush(Output);
              end;
              
              is_module := False;
              if (Pos('import ', file_content) > 0) or (Pos('export ', file_content) > 0) then
                is_module := True
              else if JS_DetectModule(PChar(file_content), QWord(Length(file_content))) <> 0 then
                is_module := True;

              if is_module then
              begin
                eval_flags := JS_EVAL_TYPE_MODULE;
                if qjs_log.DebugLevel > 0 then
                  WriteLn('[DEBUG] Detected as MODULE - imports will be resolved before top-level code');
              end
              else
              begin
                eval_flags := JS_EVAL_TYPE_GLOBAL;

                if qjs_log.DebugLevel > 1 then
                  WriteLn('[DEBUG] Detected as GLOBAL script');

                // Pre-register QAR files in script directory to avoid import resolution issues
                // QuickJS resolves imports before executing top-level code, so LoadLibrary
                // calls may happen too late. Pre-register common QAR files.
                if script_dir <> '' then
                begin
                  test_path := IncludeTrailingPathDelimiter(script_dir) + 'qar_test.qar';
                  if FileExists(test_path) then
                  begin
                    if qjs_log.DebugLevel > 0 then
                    begin
                      WriteLn('[DEBUG] Found qar_test.qar (no auto-register; use LoadLibrary("', test_path, '") if needed)');

                      qar_debug := qar_open(PChar(test_path));
                      if qar_debug <> nil then
                      begin
                        entry_count_debug := qar_get_entry_count(qar_debug);
                        WriteLn('[DEBUG] QAR file contains ', entry_count_debug, ' entries:');
                        for i_debug := 0 to entry_count_debug - 1 do
                        begin
                          entry_debug := qar_get_entry(qar_debug, i_debug);
                          if entry_debug <> nil then
                          begin
                            entry_path_debug := qar_entry_get_path(entry_debug);
                            WriteLn('[DEBUG]   Entry ', i_debug, ': "', entry_path_debug, '"');
                          end;
                        end;
                        qar_close(qar_debug);
                      end;
                    end;
                    Flush(Output);
                  end;

                  // Also try to find QAR files mentioned in LoadLibrary calls
                  if Pos('LoadLibrary', file_content) > 0 then
                  begin
                    if qjs_log.DebugLevel > 0 then
                    begin
                      WriteLn('[DEBUG] Found LoadLibrary calls in script');
                      WriteLn('[DEBUG] Note: QAR files in script directory have been pre-registered');
                      WriteLn('[DEBUG] LoadLibrary calls will still execute but may be redundant');
                      Flush(Output);
                    end;
                  end;
                end;
              end;
              
              result_val := JS_Eval(ctx, PChar(file_content), QWord(Length(file_content)),
                PChar(script_path), eval_flags);
              
              // Khôi phục working directory
              try
                SetCurrentDir(old_dir);
              except
                // Ignore errors when restoring directory
              end;
              
              // Clear script directory after loading (chỉ clear sau khi đã xử lý exception)
              // KHÔNG clear ngay vì có thể cần cho error handling
              
              if JS_IsException(result_val) <> 0 then
              begin
                WriteLn('Error loading file: ', script_path);
                js_std_dump_error(ctx);
                JS_FreeValue(ctx, result_val);
              end
              else
              begin
                if eval_flags = JS_EVAL_TYPE_MODULE then
                begin
                  // Execute pending jobs (module initialization)
                end;

                if RunExecutionPipeline(ctx, True) then
                begin
                  // Flush output to ensure all console.log output is displayed
                  Flush(Output);
                  if qjs_log.DebugLevel > 0 then
                    WriteLn('File loaded successfully');
                  // Flush again after execution
                  Flush(Output);
                end;

                JS_FreeValue(ctx, result_val);
              end;
              
              // Clear script directory after loading
              qar_helpers.CurrentScriptDir := '';
              Flush(Output);
            end
            else
            begin
              WriteLn('Error: File not found: ', script);
              Flush(Output);
            end;
            Continue;
          end;
        end
        else
        begin
          WriteLn('Error: .load requires a filename');
          Flush(Output);
        end;
        Continue; // Bỏ qua phần xử lý script thông thường
      end;
      
      if (Copy(script, 1, 5) = '.lib ') or (script = '.lib') then
      begin
        cmdLine := '';
        if Length(script) > 5 then
          cmdLine := Trim(Copy(script, 6, Length(script)));

        cmdArgs := TStringList.Create;
        try
          cmdArgs.Delimiter := ' ';
          cmdArgs.StrictDelimiter := True;
          cmdArgs.DelimitedText := cmdLine;

          if (cmdArgs.Count = 0) or ((cmdArgs.Count = 1) and (LowerCase(cmdArgs[0]) = 'list')) then
          begin
            ConfigLibrariesListPretty(ExamplesConfigFile, qjs_log.DebugLevel);
          end
          else if (cmdArgs.Count >= 3) and (LowerCase(cmdArgs[0]) = 'add') then
          begin
            ConfigLibrariesAdd(ExamplesConfigFile, qjs_log.DebugLevel, cmdArgs[1], cmdArgs[2]);
            LoadQjspMountsFromFile(ExamplesConfigFile, qjs_log.DebugLevel);
            WriteLn('Added library mount: ', cmdArgs[1], '=', cmdArgs[2]);
          end
          else if (cmdArgs.Count >= 2) and ((LowerCase(cmdArgs[0]) = 'remove') or (LowerCase(cmdArgs[0]) = 'rm')) then
          begin
            ConfigLibrariesRemove(ExamplesConfigFile, qjs_log.DebugLevel, cmdArgs[1]);
            LoadQjspMountsFromFile(ExamplesConfigFile, qjs_log.DebugLevel);
            WriteLn('Removed library mount: ', cmdArgs[1]);
          end
          else
          begin
            WriteLn('Usage: .lib <command>');
            WriteLn('Commands:');
            WriteLn('  list');
            WriteLn('  add <prefix> <folder>');
            WriteLn('  remove <prefix>');
          end;
        finally
          cmdArgs.Free;
        end;

        Flush(Output);
        Continue;
      end;

      // Handle .test command to manage and run example scripts
      if (Copy(script, 1, 6) = '.test ') or (script = '.test') then
      begin
        cmdLine := '';
        if Length(script) > 6 then
          cmdLine := Trim(Copy(script, 7, Length(script)));
        
        cmdArgs := TStringList.Create;
        try
          cmdArgs.Delimiter := ' ';
          cmdArgs.StrictDelimiter := True;
          cmdArgs.DelimitedText := cmdLine;
          test_path := '';
          test_key := '';
          test_file := '';
          
          // No subcommand or "run" - run enabled examples
          if (cmdArgs.Count = 0) or ((cmdArgs.Count = 1) and (LowerCase(cmdArgs[0]) = 'run')) then
          begin
            suite_tick0 := GetTickCount64;
            // Run enabled examples based on config
            for i := 0 to Length(ExampleConfigs) - 1 do
            begin
              if ExampleConfigs[i].enabled then
              begin
                test_key := ExampleConfigs[i].name;
                test_path := test_key;
                if (Pos('/', test_path) = 0) and (Pos('\\', test_path) = 0) and (ExtractFileDrive(test_path) = '') and ((Length(test_path) = 0) or ((test_path[1] <> PathDelim) and (test_path[1] <> '/'))) then
                  test_file := 'tests/' + test_path
                else
                  test_file := test_path;

                WriteLn('=== Running: ', test_key, ' ===');
                test_tick0 := GetTickCount64;
                if LoadAndExecuteJSFile(ctx, test_file) then
                begin
                  if qjs_log.DebugLevel > 0 then
                    WriteLn('[DEBUG] ', test_key, ' completed successfully');
                end
                else
                begin
                  WriteLn('Warning: Could not load ', test_file);
                end;
                test_tick1 := GetTickCount64;
                try
                  WriteLn(StdErr, '[TIME] test=', test_key, ' elapsed_ms=', (test_tick1 - test_tick0));
                except
                end;
                WriteLn;
              end;
            end;
            suite_tick1 := GetTickCount64;
            try
              WriteLn(StdErr, '[TIME] suite=tests elapsed_ms=', (suite_tick1 - suite_tick0));
            except
            end;
          end
          else if (cmdArgs.Count >= 1) and (LowerCase(cmdArgs[0]) = 'list') then
          begin
            // List all examples and their status
            WriteLn('Example tests configuration:');
            WriteLn;
            for i := 0 to Length(ExampleConfigs) - 1 do
            begin
              if ExampleConfigs[i].enabled then
                WriteLn('  [X] ', ExampleConfigs[i].name)
              else
                WriteLn('  [ ] ', ExampleConfigs[i].name);
            end;
            WriteLn;
            WriteLn('Use .test add <name> to add a test');
            WriteLn('Use .test remove <name> to remove a test');
            WriteLn('Use .test enable <name> to enable a test');
            WriteLn('Use .test disable <name> to disable a test');
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'add') then
          begin
            // Add a new test (enabled by default)
            j := tests_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
            if j >= 0 then
            begin
              WriteLn('Test "', cmdArgs[1], '" already exists');
            end
            else
            begin
              SetLength(ExampleConfigs, Length(ExampleConfigs) + 1);
              ExampleConfigs[Length(ExampleConfigs) - 1].name := cmdArgs[1];
              ExampleConfigs[Length(ExampleConfigs) - 1].enabled := True;
              SaveExamplesConfigToFile(ExamplesConfigFile, ExampleConfigs);
              WriteLn('Added test "', cmdArgs[1], '" (enabled)');
            end;
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'remove') then
          begin
            // Remove a test
            j := tests_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
            if j < 0 then
            begin
              WriteLn('Test "', cmdArgs[1], '" not found');
            end
            else
            begin
              // Remove from array
              for i := j to Length(ExampleConfigs) - 2 do
                ExampleConfigs[i] := ExampleConfigs[i + 1];
              SetLength(ExampleConfigs, Length(ExampleConfigs) - 1);
              SaveExamplesConfigToFile(ExamplesConfigFile, ExampleConfigs);
              WriteLn('Removed test "', cmdArgs[1], '"');
            end;
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'enable') then
          begin
            // Enable a test
            j := tests_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
            if j < 0 then
            begin
              WriteLn('Test "', cmdArgs[1], '" not found');
            end
            else
            begin
              ExampleConfigs[j].enabled := True;
              SaveExamplesConfigToFile(ExamplesConfigFile, ExampleConfigs);
              WriteLn('Enabled test "', cmdArgs[1], '"');
            end;
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'disable') then
          begin
            // Disable a test
            j := tests_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
            if j < 0 then
            begin
              WriteLn('Test "', cmdArgs[1], '" not found');
            end
            else
            begin
              ExampleConfigs[j].enabled := False;
              SaveExamplesConfigToFile(ExamplesConfigFile, ExampleConfigs);
              WriteLn('Disabled test "', cmdArgs[1], '"');
            end;
          end
          else
          begin
            WriteLn('Usage: .test [command]');
            WriteLn('Commands:');
            WriteLn('  (no args) or run  - Run all enabled example tests');
            WriteLn('  list              - List all tests and their status');
            WriteLn('  add <name>        - Add a new test (enabled by default)');
            WriteLn('  remove <name>     - Remove a test');
            WriteLn('  enable <name>     - Enable a test');
            WriteLn('  disable <name>    - Disable a test');
          end;
          
          Flush(Output);
        finally
          cmdArgs.Free;
        end;
        Continue; // Skip normal script processing
      end;
      
      // Xử lý lệnh .build để build QAR file
      if (Copy(script, 1, 7) = '.build ') or (Copy(script, 1, 6) = '.build') then
      begin
        if Length(script) > 7 then
        begin
          script := Trim(Copy(script, 8, Length(script)));
          if script <> '' then
          begin
            // Parse arguments: .build output.qar file1.js file2.js ...
            build_args := TStringList.Create;
            try
              // Simple space-separated parsing
              build_args.Delimiter := ' ';
              build_args.DelimitedText := script;
              
              if build_args.Count < 2 then
              begin
                WriteLn('Error: .build requires at least 2 arguments: output.qar and input file(s)');
                WriteLn('Usage: .build output.qar file1.js file2.js');
                WriteLn('   or: .build output.qar src/');
                WriteLn('Options: --v1 | --v2 | --format <n> | --no-source/--omit-source | --sign-key <file> | --minify ...');
                Flush(Output);
              end
              else
              begin
                build_output := build_args[0];
                do_minify := False;
                keep_temp := False;
                minify_safe := False;
                omit_source := False;
                minify_script := '';
                qar_sign_key_file := '';
                build_format_version := 1;
                SetLength(minify_flags, 0);
                SetLength(build_inputs_list, 0);

                j := 1;
                while j <= build_args.Count - 1 do
                begin
                  if build_args[j] = '--minify' then
                    do_minify := True
                  else if build_args[j] = '--minify-safe' then
                  begin
                    do_minify := True;
                    minify_safe := True;
                  end
                  else if build_args[j] = '--v2' then
                    build_format_version := 2
                  else if build_args[j] = '--v1' then
                    build_format_version := 1
                  else if (build_args[j] = '--format') and (j + 1 <= build_args.Count - 1) then
                  begin
                    Inc(j);
                    build_format_version := StrToIntDef(build_args[j], 1);
                  end
                  else if (build_args[j] = '--no-source') or (build_args[j] = '--omit-source') then
                    omit_source := True
                  else if (build_args[j] = '--sign-key') and (j + 1 <= build_args.Count - 1) then
                  begin
                    Inc(j);
                    qar_sign_key_file := build_args[j];
                  end
                  else if build_args[j] = '--keep-temp' then
                    keep_temp := True
                  else if (build_args[j] = '--minify-script') and (j + 1 <= build_args.Count - 1) then
                  begin
                    Inc(j);
                    minify_script := build_args[j];
                  end
                  else if (build_args[j] = '--minify-flag') and (j + 1 <= build_args.Count - 1) then
                  begin
                    Inc(j);
                    SetLength(minify_flags, Length(minify_flags) + 1);
                    minify_flags[Length(minify_flags) - 1] := build_args[j];
                  end
                  else
                  begin
                    SetLength(build_inputs_list, Length(build_inputs_list) + 1);
                    build_inputs_list[Length(build_inputs_list) - 1] := build_args[j];
                  end;
                  Inc(j);
                end;

                build_inputs := build_inputs_list;

                if Length(build_inputs) = 0 then
                begin
                  WriteLn('Error: No input files specified');
                  Flush(Output);
                  Continue;
                end;

                if minify_safe then
                begin
                  SetLength(minify_flags, Length(minify_flags) + 2);
                  minify_flags[Length(minify_flags) - 2] := '--safe-rename';
                  minify_flags[Length(minify_flags) - 1] := '--encode-strings';
                end;

                if do_minify then
                begin
                  if minify_script = '' then
                    minify_script := 'minify_qjsp.js';
                  if not FileExists(minify_script) then
                    minify_script := 'minify.js';
                  if not FileExists(minify_script) then
                  begin
                    WriteLn('Error: minify script not found: ', minify_script);
                    Flush(Output);
                    Continue;
                  end;
                  minify_script := ExpandFileName(minify_script);
                end;
                
                WriteLn('Building QAR file: ', build_output);
                WriteLn('Input files/directories:');
                for j := 0 to Length(build_inputs) - 1 do
                  WriteLn('  ', build_inputs[j]);
                Flush(Output);
                
                if do_minify then
                begin
                  SetLength(staged, Length(build_inputs));
                  build_inputs_stage := build_inputs;
                  temp_stage_dir := '';
                  try
                    if not PrepareStagedInputs(minify_script, minify_flags, True, temp_stage_dir, build_inputs, staged) then
                    begin
                      WriteLn('Error: Failed to prepare minified inputs');
                      Flush(Output);
                      Continue;
                    end;
                    build_inputs_stage := staged;
                    if qar.BuildQar(build_output, build_inputs_stage, '', '', qar_created_by, qar_tool, qar_meta, '', '', qar_sign_key_file, omit_source, build_format_version) < 0 then
                    begin
                      WriteLn('Error: Failed to build QAR file');
                      Flush(Output);
                    end
                    else
                    begin
                      WriteLn('Successfully created QAR file: ', build_output);
                      Flush(Output);
                    end;
                  finally
                    if temp_stage_dir <> '' then
                    begin
                      if keep_temp then
                        WriteLn('Keeping temp staging dir: ', temp_stage_dir)
                      else
                        DeleteDirRecursive(temp_stage_dir);
                    end;
                    temp_stage_dir := '';
                  end;
                end
                else
                begin
                  if qar.BuildQar(build_output, build_inputs, '', '', qar_created_by, qar_tool, qar_meta, '', '', qar_sign_key_file, omit_source, build_format_version) < 0 then
                  begin
                    WriteLn('Error: Failed to build QAR file');
                    Flush(Output);
                  end
                  else
                  begin
                    WriteLn('Successfully created QAR file: ', build_output);
                    Flush(Output);
                  end;
                end;
              end;
            finally
              build_args.Free;
            end;
          end
          else
          begin
            WriteLn('Error: .build requires arguments');
            WriteLn('Usage: .build output.qar file1.js file2.js');
            WriteLn('   or: .build output.qar src/');
            Flush(Output);
          end;
        end
        else
        begin
          WriteLn('Error: .build requires arguments');
          WriteLn('Usage: .build output.qar file1.js file2.js');
          WriteLn('   or: .build output.qar src/');
          Flush(Output);
        end;
        Continue; // Bỏ qua phần xử lý script thông thường
      end;

      // Xử lý các lệnh QAR tool: .qar, .tool, .verify
      if (Copy(script, 1, 4) = '.qar') or (Copy(script, 1, 5) = '.tool') or
         (Copy(script, 1, 7) = '.verify') then
      begin
        // Tách phần sau tên lệnh (.qar / .tool / .verify)
        if Copy(script, 1, 7) = '.verify' then
          cmdLine := Trim(Copy(script, 8, Length(script)))
        else
        begin
          // Bỏ prefix ".qar" hoặc ".tool"
          if Copy(script, 1, 4) = '.qar' then
            cmdLine := Trim(Copy(script, 5, Length(script)))
          else
            cmdLine := Trim(Copy(script, 6, Length(script)));
        end;

        cmdArgs := TStringList.Create;
        try
          cmdArgs.Delimiter := ' ';
          cmdArgs.StrictDelimiter := True;
          cmdArgs.DelimitedText := cmdLine;

          // .verify là alias nhanh cho "inspect + check compatibility"
          if Copy(script, 1, 7) = '.verify' then
          begin
            if cmdArgs.Count < 1 then
            begin
              WriteLn('Usage: .verify <file.qar>');
              Flush(Output);
              Continue;
            end;
            qar_input := cmdArgs[0];
            if not FileExists(qar_input) then
            begin
              WriteLn('Error: QAR file not found: ', qar_input);
              Flush(Output);
              Continue;
            end;

            qar_inspection := qar.InspectQarFile(qar_input);
            try
              WriteLn('File: ', qar_inspection.qar_file);
              WriteLn('QuickJS in QAR: ', qar_inspection.quickjs_version);
              WriteLn('Check: ', qar_inspection.compatibility_message);
            finally
              qar_inspection.dependencies.Free;
            end;
            Flush(Output);
            Continue;
          end;

          // .qar / .tool mà không có subcommand => help
          if cmdArgs.Count = 0 then
          begin
            WriteLn('QAR Tool commands (.qar / .tool):');
            WriteLn('  info <file.qar> [--init-lib] - Show QAR file information (detect v1/v2)');
            WriteLn('  build <out.qar> <files...>  - Create QAR from file JS/folder');
            WriteLn('  inspect <file.qar>          - Check detail file QAR');
            WriteLn('  rebuild <in.qar> <out.qar>  - Rebuild QAR');
            WriteLn('  keygen <out> [--raw64 <file>] [--pem <file>] - Generate Ed25519 key');
            WriteLn('  code <file.qar> <entry>     - Display source code of entry');
            WriteLn('  version                     - QAR/QuickJS version');
            WriteLn('  help                        - Display help');
            WriteLn;
            WriteLn('Examples:');
            WriteLn('  .qar info qa3.qar');
            WriteLn('  .qar info qa3.qar --init-lib');
            WriteLn('  .qar keygen mykey');
            WriteLn('  .qar build --v2 output.qar src/ --sign-key mykey.bin');
            WriteLn('  .qar inspect file.qar');
            WriteLn('  .qar rebuild old.qar new.qar --sign-key mykey.pem');
            Flush(Output);
            Continue;
          end;

          subcmd := LowerCase(cmdArgs[0]);

          if (subcmd = 'help') then
          begin
            WriteLn('QAR Tool commands (.qar / .tool):');
            WriteLn('  info <file.qar> [--init-lib] - Show QAR file information (detect v1/v2)');
            WriteLn('  build <out.qar> <files...>  - Create QAR from file JS/folder');
            WriteLn('    Options: --v1 | --v2 | --format <n> | --no-source/--omit-source | --sign-key <file> | --minify ...');
            WriteLn('  inspect <file.qar>          - Check detail file QAR');
            WriteLn('  rebuild <in.qar> <out.qar>  - Rebuild QAR');
            WriteLn('  keygen <out> [--raw64 <file>] [--pem <file>] - Generate Ed25519 key');
            WriteLn('  code <file.qar> <entry>     - Display source code of entry');
            WriteLn('  version                     - QAR/QuickJS version');
            WriteLn('  help                        - Display help');
          end
          else if (subcmd = 'keygen') then
          begin
            // .qar keygen <out> [--raw64 <file>] [--pem <file>]
            // default: <out>.bin and <out>.pem
            // Supports:
            // - .qar keygen mykey
            // - .qar keygen mykey --pem hello.pem --raw64 hello.bin
            // - .qar keygen --pem hello.pem
            // - .qar keygen --raw64 hello.bin
            if cmdArgs.Count < 2 then
            begin
              WriteLn('Usage: .qar keygen [<out>] [--raw64 <file>] [--pem <file>]');
              Flush(Output);
              Continue;
            end;

            qar_output := '';
            out_path := '';
            qar_input := '';

            // If first arg after keygen is not an option, treat it as <out>
            if (cmdArgs.Count >= 2) and (cmdArgs[1] <> '') and (Copy(cmdArgs[1], 1, 2) <> '--') then
            begin
              qar_output := cmdArgs[1];
              k_qar := 2;
            end
            else
              k_qar := 1;

            // Parse options starting at k_qar
            while k_qar <= cmdArgs.Count - 1 do
            begin
              if (cmdArgs[k_qar] = '--raw64') and (k_qar + 1 <= cmdArgs.Count - 1) then
              begin
                Inc(k_qar);
                out_path := cmdArgs[k_qar];
              end
              else if (cmdArgs[k_qar] = '--pem') and (k_qar + 1 <= cmdArgs.Count - 1) then
              begin
                Inc(k_qar);
                qar_input := cmdArgs[k_qar];
              end
              else if (qar_output = '') and (cmdArgs[k_qar] <> '') and (Copy(cmdArgs[k_qar], 1, 2) <> '--') then
              begin
                // Allow <out> to appear later (rare, but robust)
                qar_output := cmdArgs[k_qar];
              end;
              Inc(k_qar);
            end;

            // If <out> not provided, derive from explicit filenames.
            if qar_output = '' then
            begin
              if qar_input <> '' then
                qar_output := ChangeFileExt(qar_input, '')
              else if out_path <> '' then
                qar_output := ChangeFileExt(out_path, '')
              else
              begin
                WriteLn('Error: missing output name. Provide <out> or --pem/--raw64');
                Flush(Output);
                Continue;
              end;
            end;

            // Defaults
            if qar_input = '' then
              qar_input := qar_output + '.pem';
            if out_path = '' then
              out_path := qar_output + '.bin';

            // Shared backend implementation (same as JS helpers)
            guardArg := '';
            if not qar_tooling_backend.QarKeygenFiles(out_path, qar_input, guardArg) then
            begin
              WriteLn('Error: keygen failed: ', guardArg);
              Flush(Output);
              Continue;
            end;

            WriteLn('Ed25519 key generated:');
            WriteLn('  raw64: ', out_path);
            WriteLn('  pem:   ', qar_input);
            Flush(Output);
          end
          else if (subcmd = 'info') then
          begin
            init_default_lib_qar := False;
            qar_file := '';
            for k_qar := 1 to cmdArgs.Count - 1 do
            begin
              if (cmdArgs[k_qar] = '--init-lib') or (cmdArgs[k_qar] = '-i') then
                init_default_lib_qar := True;
              if (qar_file = '') and (Length(cmdArgs[k_qar]) > 0) and (cmdArgs[k_qar][1] <> '-') then
                qar_file := cmdArgs[k_qar];
            end;
            if qar_file <> '' then
            begin
              qar_inspection := qar.InspectQarFile(qar_file);
              WriteLn('QAR Version: ', qar.GetQarVersion);
              WriteLn('QAR Format Version: ', qar_inspection.qar_format_version);
              if qar_inspection.quickjs_version <> '' then
                WriteLn('QuickJS Version: ', qar_inspection.quickjs_version)
              else
                WriteLn('QuickJS Version: ', qar.GetQuickJsVersion);
              WriteLn('Entry Count: ', qar_inspection.entry_count);
              if init_default_lib_qar then
                WriteLn('QuickJS Runtime: Initialized')
              else
                WriteLn('QuickJS Runtime: Not initialized');
            end
            else
              qar.PrintQarInfo(init_default_lib_qar);
          end
          else if (subcmd = 'version') then
          begin
            WriteLn('QAR Version: ', qar.GetQarVersion);
            WriteLn('QAR Format Version: ', QAR_FORMAT_VERSION);
            WriteLn('QuickJS Version: ', qar.GetQuickJsVersion);
          end
          else if (subcmd = 'build') then
          begin
            do_minify := False;
            keep_temp := False;
            minify_safe := False;
            omit_source := False;
            minify_script := '';
            qar_sign_key_file := '';
            qar_format_version := 1;
            SetLength(minify_flags, 0);
            SetLength(qar_inputs_list, 0);

            qar_output := '';

            k_qar := 1;
            while k_qar <= cmdArgs.Count - 1 do
            begin
              if cmdArgs[k_qar] = '--minify' then
                do_minify := True
              else if cmdArgs[k_qar] = '--minify-safe' then
              begin
                do_minify := True;
                minify_safe := True;
              end
              else if cmdArgs[k_qar] = '--keep-temp' then
                keep_temp := True
              else if (cmdArgs[k_qar] = '--minify-script') and (k_qar + 1 <= cmdArgs.Count - 1) then
              begin
                Inc(k_qar);
                minify_script := cmdArgs[k_qar];
              end
              else if (cmdArgs[k_qar] = '--minify-flag') and (k_qar + 1 <= cmdArgs.Count - 1) then
              begin
                Inc(k_qar);
                SetLength(minify_flags, Length(minify_flags) + 1);
                minify_flags[Length(minify_flags) - 1] := cmdArgs[k_qar];
              end
              else if cmdArgs[k_qar] = '--v2' then
                qar_format_version := 2
              else if cmdArgs[k_qar] = '--v1' then
                qar_format_version := 1
              else if (cmdArgs[k_qar] = '--format') and (k_qar + 1 <= cmdArgs.Count - 1) then
              begin
                Inc(k_qar);
                qar_format_version := StrToIntDef(cmdArgs[k_qar], 1);
              end
              else if (cmdArgs[k_qar] = '--sign-key') and (k_qar + 1 <= cmdArgs.Count - 1) then
              begin
                Inc(k_qar);
                qar_sign_key_file := cmdArgs[k_qar];
              end
              else if (cmdArgs[k_qar] = '--no-source') or (cmdArgs[k_qar] = '--omit-source') then
              begin
                omit_source := True;
              end
              else
              begin
                if (qar_output = '') and (cmdArgs[k_qar] <> '') and (cmdArgs[k_qar][1] <> '-') then
                  qar_output := cmdArgs[k_qar]
                else
                begin
                  SetLength(qar_inputs_list, Length(qar_inputs_list) + 1);
                  qar_inputs_list[Length(qar_inputs_list) - 1] := cmdArgs[k_qar];
                end;
              end;
              Inc(k_qar);
            end;
            qar_inputs := qar_inputs_list;

            if (qar_output = '') or (Length(qar_inputs) = 0) then
            begin
              WriteLn('Usage: .qar build <output.qar> <file1.js> [file2.js ...]');
              WriteLn('   or: .qar build <output.qar> <directory/>');
              WriteLn('Options: --v1 | --v2 | --format <n> | --no-source/--omit-source | --sign-key <file> | --minify ...');
              Flush(Output);
              Continue;
            end;

            if Length(qar_inputs) = 0 then
            begin
              WriteLn('Error: No input files specified');
              Flush(Output);
              Continue;
            end;

            if minify_safe then
            begin
              SetLength(minify_flags, Length(minify_flags) + 2);
              minify_flags[Length(minify_flags) - 2] := '--safe-rename';
              minify_flags[Length(minify_flags) - 1] := '--encode-strings';
            end;

            if do_minify then
            begin
              if minify_script = '' then
                minify_script := 'minify_qjsp.js';
              if not FileExists(minify_script) then
                minify_script := 'minify.js';
              if not FileExists(minify_script) then
              begin
                WriteLn('Error: minify script not found: ', minify_script);
                Flush(Output);
                Continue;
              end;
              minify_script := ExpandFileName(minify_script);
            end;

            WriteLn('Building QAR file: ', qar_output);
            WriteLn('QAR Format Version: ', qar_format_version);
            WriteLn('Input files/directories:');
            for k_qar := 0 to Length(qar_inputs) - 1 do
              WriteLn('  ', qar_inputs[k_qar]);
            Flush(Output);

            if do_minify then
            begin
              SetLength(staged, Length(qar_inputs));
              qar_inputs_stage := qar_inputs;
              temp_stage_dir := '';
              try
                if not PrepareStagedInputs(minify_script, minify_flags, True, temp_stage_dir, qar_inputs, staged) then
                begin
                  WriteLn('Error: Failed to prepare minified inputs');
                  Flush(Output);
                  Continue;
                end;
                qar_inputs_stage := staged;
                qar_ret := qar.BuildQar(qar_output, qar_inputs_stage, '', '', qar_created_by, qar_tool, qar_meta, '', '', qar_sign_key_file, omit_source, qar_format_version);
              finally
                if temp_stage_dir <> '' then
                begin
                  if keep_temp then
                    WriteLn('Keeping temp staging dir: ', temp_stage_dir)
                  else
                    DeleteDirRecursive(temp_stage_dir);
                end;
                temp_stage_dir := '';
              end;
            end
            else
              qar_ret := qar.BuildQar(qar_output, qar_inputs, '', '', qar_created_by, qar_tool, qar_meta, '', '', qar_sign_key_file, omit_source, qar_format_version);

            if qar_ret < 0 then
              WriteLn('Error: Failed to build QAR file')
            else
              WriteLn('Successfully created QAR file: ', qar_output);
          end
          else if (subcmd = 'inspect') then
          begin
            if cmdArgs.Count < 2 then
            begin
              WriteLn('Usage: .qar inspect <file.qar>');
              Flush(Output);
              Continue;
            end;
            qar_input := cmdArgs[1];
            if not QarPrintInspection(qar_input, '', file_content) then
            begin
              WriteLn(file_content);
              Flush(Output);
              Continue;
            end;
          end
          else if (subcmd = 'ls') then
          begin
            if cmdArgs.Count < 2 then
            begin
              WriteLn('Usage: .qar ls <file.qar> [prefix]');
              Flush(Output);
              Continue;
            end;
            qar_input := cmdArgs[1];
            if cmdArgs.Count >= 3 then
              pfx := cmdArgs[2]
            else
              pfx := '';
            if not QarPrintInspection(qar_input, pfx, file_content) then
            begin
              WriteLn(file_content);
              Flush(Output);
              Continue;
            end;
          end
          else if (subcmd = 'cat') then
          begin
            if cmdArgs.Count < 2 then
            begin
              WriteLn('Usage: .qar cat <file.qar/entryPath>');
              WriteLn('   or: .qar cat <file.qar> <entryPath>');
              Flush(Output);
              Continue;
            end;

            if cmdArgs.Count >= 3 then
              cmdLine := cmdArgs[1] + '/' + cmdArgs[2]
            else
              cmdLine := cmdArgs[1];

            if not QarCatSpecToStdout(cmdLine, file_content) then
            begin
              WriteLn(file_content);
              Flush(Output);
              Continue;
            end;

            // Ensure the next REPL prompt starts on a new line.
            WriteLn;
          end
          else if (subcmd = 'extract') then
          begin
            if cmdArgs.Count < 3 then
            begin
              WriteLn('Usage: .qar extract <file.qar> <out_dir>');
              Flush(Output);
              Continue;
            end;
            qar_input := cmdArgs[1];
            qar_output := cmdArgs[2];
            if not QarExtractToDir(qar_input, qar_output, file_content) then
            begin
              WriteLn(file_content);
              Flush(Output);
              Continue;
            end;
          end
          else if (subcmd = 'rebuild') then
          begin
            if cmdArgs.Count < 3 then
            begin
              WriteLn('Usage: .qar rebuild <input.qar> <output.qar>');
              Flush(Output);
              Continue;
            end;
            qar_input := cmdArgs[1];
            qar_output := cmdArgs[2];
            qar_sign_key_file := '';
            if (cmdArgs.Count >= 5) and (cmdArgs[3] = '--sign-key') then
              qar_sign_key_file := cmdArgs[4];
            qar_ret := qar.RebuildQarFile(qar_input, qar_output, '', '', qar_sign_key_file);
            if qar_ret < 0 then
              WriteLn('Error: Failed to rebuild QAR file');
          end
          else if (subcmd = 'code') then
          begin
            if cmdArgs.Count < 3 then
            begin
              WriteLn('Usage: .qar code <file.qar> <entryPath>');
              Flush(Output);
              Continue;
            end;

            qar_input := cmdArgs[1];
            if not FileExists(qar_input) then
            begin
              WriteLn('Error: QAR file not found: ', qar_input);
              Flush(Output);
              Continue;
            end;

            // Open QAR file
            qar_debug := qar_open(PChar(qar_input));
            if qar_debug = nil then
            begin
              WriteLn('Error: Failed to open QAR file: ', qar_input);
              Flush(Output);
              Continue;
            end;

            // Find entry by path
            entry_debug := qar_find_entry(qar_debug, PChar(cmdArgs[2]));
            if entry_debug = nil then
            begin
              WriteLn('Error: Entry not found in QAR file: ', cmdArgs[2]);
              qar_close(qar_debug);
              Flush(Output);
              Continue;
            end;

            // Load entry data (bytecode + source)
            if qar_entry_load_data(qar_debug, entry_debug) < 0 then
            begin
              WriteLn('Error: Failed to load entry data');
              qar_close(qar_debug);
              Flush(Output);
              Continue;
            end;

            // Get source code buffer
            qar_source_len := 0;
            qar_source_ptr := qar_entry_get_source(entry_debug, @qar_source_len);
            if (qar_source_ptr = nil) or (qar_source_len = 0) then
            begin
              WriteLn('Error: Entry has no source code available');
              qar_close(qar_debug);
              Flush(Output);
              Continue;
            end;

            // Convert to Pascal string and print
            SetString(qar_source_str, PChar(qar_source_ptr), qar_source_len);
            WriteLn('--- QAR source: ', qar_input, ' -> ', cmdArgs[2], ' ---');
            WriteLn(qar_source_str);
            Flush(Output);

            qar_close(qar_debug);
          end
          else
          begin
            WriteLn('Error: Unknown .qar/.tool command: ', subcmd);
            WriteLn('Type ".qar help" for usage.');
          end;

          Flush(Output);
        finally
          cmdArgs.Free;
        end;
        Continue; // Đã xử lý lệnh .qar/.tool/.verify
      end;

      // .import <module> [name]
      // REPL input is evaluated in GLOBAL mode for expression results, so ESM syntax
      // like "import ... from" cannot be typed directly. This command loads the module
      // in MODULE mode and exposes it on globalThis.
      if (Copy(script, 1, 8) = '.import ') or (script = '.import') then
      begin
        cmdLine := '';
        if Length(script) > 8 then
          cmdLine := Trim(Copy(script, 9, Length(script)));

        if cmdLine = '' then
        begin
          WriteLn('Usage: .import <module> [name]');
          WriteLn('Example: .import qjsp:sh sh');
          Flush(Output);
          Continue;
        end;

        // Parse: first token = module, second (optional) = name
        cmdArgs := TStringList.Create;
        try
          cmdArgs.Delimiter := ' ';
          cmdArgs.StrictDelimiter := False;
          cmdArgs.DelimitedText := cmdLine;

          if cmdArgs.Count < 1 then
          begin
            WriteLn('Usage: .import <module> [name]');
            Flush(Output);
            Continue;
          end;

          script_path := Trim(cmdArgs[0]);
          if script_path = '' then
          begin
            WriteLn('Usage: .import <module> [name]');
            Flush(Output);
            Continue;
          end;

          // Determine binding name
          if cmdArgs.Count >= 2 then
            line := Trim(cmdArgs[1])
          else
          begin
            // Derive from module specifier
            line := script_path;
            i := LastDelimiter('/\\', line);
            if i > 0 then
              line := Copy(line, i + 1, Length(line));
            i := Pos('.', line);
            if i > 0 then
              line := Copy(line, 1, i - 1);
            if line = '' then
              line := 'mod';
          end;

          // Make a safe JS identifier (very conservative)
          for i := 1 to Length(line) do
          begin
            if not (line[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']) then
              line[i] := '_';
          end;
          if (Length(line) = 0) or not (line[1] in ['A'..'Z', 'a'..'z', '_', '$']) then
            line := '_' + line;

          // Build module code
          file_content :=
            'import * as ' + line + ' from ' + QuotedStr(script_path) + ';' + LineEnding +
            'globalThis[' + QuotedStr(line) + '] = ' + line + ';' + LineEnding;

          if RunEvalCode(ctx, '<repl_import>', file_content) then
          begin
            WriteLn('Imported ', script_path, ' as globalThis.', line);
            Flush(Output);
          end
          else
          begin
            WriteLn('Error: import failed: ', script_path);
            Flush(Output);
          end;
        finally
          cmdArgs.Free;
        end;

        Continue;
      end;
      
      // REPL nên luôn chạy ở GLOBAL để trả về giá trị biểu thức (giống qjs REPL)
      // Tránh JS_DetectModule: code đơn giản như "1+2" có thể bị xem là module,
      // JS_Eval sẽ trả về Promise/undefined khiến REPL không in kết quả.
      eval_flags := JS_EVAL_TYPE_GLOBAL;

      // Nếu code có "await" ở đầu dòng (top-level await), thêm cờ ASYNC
      // (chỉ áp dụng cho GLOBAL mode, MODULE mode đã hỗ trợ top-level await mặc định)
      if (eval_flags = JS_EVAL_TYPE_GLOBAL) and (Pos('await', LowerCase(script)) > 0) then
        eval_flags := eval_flags or JS_EVAL_FLAG_ASYNC;

      // Với GLOBAL mode, QuickJS sẽ trả về giá trị của expression
      // Không cần thay đổi eval_flags, chỉ cần đảm bảo xử lý đúng kết quả

      result_val := JS_Eval(ctx, PChar(script), QWord(Length(script)),
        PChar('<stdin>'), eval_flags);
      if JS_IsException(result_val) <> 0 then
      begin
        js_std_dump_error(ctx);
        JS_FreeValue(ctx, result_val);
        Flush(Output);
      end
      else
      begin
        // Debug: kiểm tra giá trị trả về
        // WriteLn('[DEBUG] Result is not exception');
        // Nếu là Promise thì chờ hoàn thành rồi mới in kết quả
        if JS_IsPromise(result_val) <> 0 then
        begin
          result_val := js_std_await(ctx, result_val);
          if (JS_IsException(result_val) = 0) and (JS_IsObject(result_val) <> 0) then
          begin
            original_val := JS_GetPropertyStr(ctx, result_val, PChar('value'));
            if (JS_IsException(original_val) = 0) and (JS_IsUndefined(original_val) = 0) then
            begin
              JS_FreeValue(ctx, result_val);
              result_val := original_val;
            end
            else
            begin
              JS_FreeValue(ctx, original_val);
            end;
          end;
          // Sau khi await, kiểm tra lại exception (Promise có thể reject)
          if JS_IsException(result_val) <> 0 then
          begin
            js_std_dump_error(ctx);
            JS_FreeValue(ctx, result_val);
            Flush(Output);
            Continue; // Bỏ qua phần in kết quả
          end;
        end;

        if not RunExecutionPipeline(ctx, False) then
        begin
          if result_val.tag <> JS_TAG_UNDEFINED then
            JS_FreeValue(ctx, result_val);
          Continue;
        end;

        // Print result if not undefined
        // Trong QuickJS, với JS_EVAL_TYPE_GLOBAL, expression sẽ trả về giá trị của nó
        // Kiểm tra cả tag và JS_IsUndefined để chắc chắn
        // Debug: kiểm tra giá trị trả về
        if qjs_log.DebugLevel > 1 then
          WriteLn('[DEBUG] Result tag=', result_val.tag, ', IsUndefined=', JS_IsUndefined(result_val), 
                ', IsString=', JS_IsString(result_val), ', IsNumber=', JS_IsNumber(result_val),
                ', IsObject=', JS_IsObject(result_val));
        Flush(Output);
        
        // Kiểm tra cả tag và JS_IsUndefined
        if (result_val.tag <> JS_TAG_UNDEFINED) and (JS_IsUndefined(result_val) = 0) then
        begin
          // Nếu là string, dùng trực tiếp JS_ToCString (không cần stringify)
          if JS_IsString(result_val) <> 0 then
          begin
            result_str := JS_ToCString(ctx, result_val);
            if result_str <> nil then
            begin
              WriteLnUtf8(result_str);
              JS_FreeCString(ctx, result_str);
              Flush(Output);
            end;
            // result_val sẽ được free ở cuối block
          end
          // Nếu là object hoặc array (nhưng không phải string), stringify để dễ đọc
          else if (JS_IsObject(result_val) <> 0) or (JS_IsArray(ctx, result_val) <> 0) then
          begin
            // Dùng JSON.stringify để format object/array
            original_val := JS_DupValue(ctx, result_val); // Dup để giữ lại nếu cần fallback
            stringified := JS_JSONStringify(ctx, result_val, JS_UNDEFINED, JS_UNDEFINED);
            JS_FreeValue(ctx, result_val); // Free giá trị cũ
            if JS_IsException(stringified) = 0 then
            begin
              result_val := stringified;
              // Stringified result là string, dùng JS_ToCString trực tiếp
              result_str := JS_ToCString(ctx, result_val);
              if result_str <> nil then
              begin
                WriteLnUtf8(result_str);
                JS_FreeCString(ctx, result_str);
                Flush(Output);
              end;
              // result_val sẽ được free ở cuối block
            end
            else
            begin
              // Nếu stringify thất bại, fallback về toString của object gốc
              JS_FreeValue(ctx, stringified);
              result_val := JS_ToString(ctx, original_val);
              JS_FreeValue(ctx, original_val);
              // result_val bây giờ là string, dùng JS_ToCString trực tiếp
              result_str := JS_ToCString(ctx, result_val);
              if result_str <> nil then
              begin
                WriteLnUtf8(result_str);
                JS_FreeCString(ctx, result_str);
                Flush(Output);
              end;
              // result_val sẽ được free ở cuối block
            end;
          end
          else
          begin
            // Các kiểu primitive khác (number, boolean, etc.), convert sang string
            stringified := JS_ToString(ctx, result_val);
            JS_FreeValue(ctx, result_val);
            if JS_IsException(stringified) = 0 then
            begin
              result_val := stringified;
              result_str := JS_ToCString(ctx, result_val);
              if result_str <> nil then
              begin
                WriteLnUtf8(result_str);
                JS_FreeCString(ctx, result_str);
                Flush(Output);
              end
              else
              begin
                // JS_ToCString trả về nil - có thể là lỗi
                WriteLn('Error: Failed to convert to C string');
                Flush(Output);
              end;
              // result_val sẽ được free ở cuối block
            end
            else
            begin
              // JS_ToString thất bại
              js_std_dump_error(ctx);
              JS_FreeValue(ctx, stringified);
              Flush(Output);
              // Set result_val thành undefined để không free lại
              result_val.tag := JS_TAG_UNDEFINED;
              result_val.u.int32 := 0;
            end;
          end;
        end;
        // Free result_val nếu chưa được free (không phải undefined tag)
        if result_val.tag <> JS_TAG_UNDEFINED then
          JS_FreeValue(ctx, result_val);
      end;

      except
        on E: EAccessViolation do
        begin
          if ReplGuardMode = rgStrict then
            raise
          else
          begin
            WriteLn('Fatal: Access violation detected (internal error).');
            WriteLn('The REPL will now exit cleanly.');
            Flush(Output);
            exit_code := 1;
            Break;
          end;
        end;
        on E: Exception do
        begin
          WriteLn('Error: ', E.ClassName, ': ', E.Message);
          Flush(Output);
          Continue;
        end;
      end;

    end;
  end;

  // End interactive mode block
  if (not run_script_mode) and reload_requested then
  begin
    // Reset mode/module tracking so the next REPL session re-imports cleanly.
    ImportedReplModes.Clear;

    try
      file_content :=
        'import * as rt from ''qjsp:runtime/index.js'';' + LineEnding +
        'if (rt && typeof rt.shutdown === ''function'') rt.shutdown();' + LineEnding;

      result_val := JS_Eval(ctx,
        PChar(file_content),
        QWord(Length(file_content)),
        PChar('<stdjs_shutdown_reload>'),
        JS_EVAL_TYPE_MODULE);

      if JS_IsException(result_val) <> 0 then
      begin
        if qjs_log.DebugLevel > 0 then
          js_std_dump_error(ctx);
        JS_FreeValue(ctx, result_val);
      end
      else
      begin
        JS_FreeValue(ctx, result_val);
        RunExecutionPipeline(ctx, False);
      end;
    except
      // ignore
    end;

    js_std_free_handlers(rt);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);

    goto RestartRuntime;
  end;

  // Cleanup
  if qjs_log.DebugLevel > 1 then
    DumpRuntimeMemoryUsageToConsole(rt);

  if not run_script_mode then
  begin
    if config_dirty then
      SaveRuntimeAndHostSettingsToConfig(ExamplesConfigFile, ReplGuardMode, GuardExplicit,
        ActiveReplMode, dump_flags_explicit, dump_flags_value);
  end;

  try
    file_content :=
      'import * as rt from ''qjsp:runtime/index.js'';' + LineEnding +
      'if (rt && typeof rt.shutdown === ''function'') rt.shutdown();' + LineEnding;

    result_val := JS_Eval(ctx,
      PChar(file_content),
      QWord(Length(file_content)),
      PChar('<stdjs_shutdown>'),
      JS_EVAL_TYPE_MODULE);

    if JS_IsException(result_val) <> 0 then
    begin
      if qjs_log.DebugLevel > 0 then
        js_std_dump_error(ctx);
      JS_FreeValue(ctx, result_val);
    end
    else
    begin
      JS_FreeValue(ctx, result_val);
      RunExecutionPipeline(ctx, False);
    end;
  except
    // ignore
  end;

  js_std_free_handlers(rt);
  JS_FreeContext(ctx);
  JS_FreeRuntime(rt);

  // Free all loaded dynamic libraries
  dll_helpers.CleanupAllDynamicLibraries;
  if dll_helpers.LoadedDynamicLibraries <> nil then
    dll_helpers.LoadedDynamicLibraries.Free;

  if run_script_mode then
  begin
    Halt(exit_code);
  end
  else
  begin
    WriteLn;
    WriteLn('Goodbye!');
  end;
end.
