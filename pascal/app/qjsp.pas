program qjsp;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, ctypes, process,
  quickjs_types, quickjs_core, quickjs_std,
  qjs_log,
  qar, qjsp_qar_tooling, quickjs_miniz, quickjs_debug, quickjs_memdebug,
  fpjson, jsonparser,
  qar_helpers, dll_helpers, compression_helpers,
  console_utf8,
  examples_config,
  file_utils,
  qjsp_module_loader, http_helpers, http_async_helpers, fs_watch_helpers;

const
  APP_AUTHOR = 'Nguyen Duc Thinh - dr.nguyenducthinh@gmail.com';
  APP_VERSION = '1.0.0';
  APP_BUILD_DATE = {$I %DATE%};
  APP_BUILD_TIME = {$I %TIME%};

function GetAppVersion: string;
begin
  if APP_VERSION <> '' then
    Result := APP_VERSION
  else
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
  if qjs_log.DebugLevel > 1 then
    EnableAllDebugDumps(rt)
  else
    DisableAllDebugDumps(rt);

  if qjs_log.DebugLevel > 0 then
    JS_InstallLoggingPromiseRejectionTracker(rt)
  else
    JS_InstallStdPromiseRejectionTracker(rt);
end;

// Helper function to load and execute a JS file
function LoadAndExecuteJSFile(ctx: PJSContext; const filename: string): boolean;
var
  file_content: string;
  result_val: JSValue;
  eval_flags: cint;
  script_path: string;
begin
  Result := False;

  if not ResolveScriptPath(filename, script_path) then
  begin
    if qjs_log.DebugLevel > 0 then
      WriteLn('[DEBUG] File not found: ', filename, ' (tried: ', script_path, ')');
    Exit;
  end;

  if qjs_log.DebugLevel > 0 then
    WriteLn('[DEBUG] Loading file: ', script_path);

  if not ReadTextFileToString(script_path, file_content) then
    Exit;
  
  // Execute file content
  eval_flags := JS_EVAL_TYPE_GLOBAL;
  if JS_DetectModule(PChar(file_content), QWord(Length(file_content))) <> 0 then
  begin
    eval_flags := JS_EVAL_TYPE_MODULE;
    if qjs_log.DebugLevel > 1 then
      WriteLn('[DEBUG] Detected as MODULE');
  end;
  
  result_val := JS_Eval(ctx, PChar(file_content), QWord(Length(file_content)),
    PChar(script_path), eval_flags);
  
  if JS_IsException(result_val) <> 0 then
  begin
    WriteLn('Error executing file: ', script_path);
    js_std_dump_error(ctx);
    Result := False;
  end
  else
  begin
    JS_FreeValue(ctx, result_val);
    Result := True;
  end;
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
          if not DeleteFile(p) then
            Result := False;
        except
          Result := False;
        end;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
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
          FindClose(sr);
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
            FindClose(sr);
            Exit;
          end;
        end
        else
        begin
          if not CopyFileTo(src_path, dst_path) then
          begin
            FindClose(sr);
            Exit;
          end;
        end;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
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
  TReplGuardMode = (rgStrict, rgFriendly);

// Main program
var
  ExampleConfigs: TExampleConfigs;
  ExamplesConfigFile: string;
  rt: PJSRuntime;
  ctx: PJSContext;
  ReplGuardMode: TReplGuardMode;
  GuardExplicit: boolean;
  ReplShellMode: boolean;
  ReplShellImported: boolean;
  script: string;
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
  old_dir, script_dir, script_path, test_path: string;
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
  out_path: string;
  remove_found: boolean;
  do_minify: boolean;
  keep_temp: boolean;
  minify_safe: boolean;
  minify_script: string;
  minify_flags: array of string;
  temp_stage_dir: string;
  staged: array of string;
  build_inputs_stage: array of string;
  build_inputs_list: array of string;
  qar_inputs_list: array of string;
  qar_inputs_stage: array of string;
  // For .build command
  build_args: TStringList;
  build_output: string;
  build_inputs: array of string;
  j: integer;
  // For .qar/.tool/.verify commands
  cmdLine: string;
  cmdArgs: TStringList;
  subcmd: string;
  init_default_lib_qar: boolean;
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

// Run a JS file (non-interactive mode)
function RunScriptFile(ctx: PJSContext; const filename: string): boolean;
var
  file_content: string;
  eval_flags: cint;
  script_path: string;
  old_dir, script_dir: string;
  is_module: boolean;
  result_val: JSValue;
  job_result, loop_result: cint;
  pending_ctx: PJSContext;
begin
  Result := False;

  if not ResolveScriptPath(filename, script_path) then
  begin
    WriteLn('Error: File not found: ', filename);
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
    js_std_dump_error(ctx);
    JS_FreeValue(ctx, result_val);
    qar_helpers.CurrentScriptDir := '';
    Exit;
  end;

  job_result := 0;
  pending_ctx := nil;
  if eval_flags = JS_EVAL_TYPE_MODULE then
  begin
    repeat
      job_result := JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx);
      if job_result < 0 then
      begin
        if pending_ctx <> nil then
          js_std_dump_error(pending_ctx)
        else
          js_std_dump_error(ctx);
        Break;
      end;
    until job_result = 0;
  end;

  if job_result >= 0 then
  begin
    loop_result := js_std_loop(ctx);
    if loop_result <> 0 then
    begin
      js_std_dump_error(ctx);
      JS_FreeValue(ctx, result_val);
      qar_helpers.CurrentScriptDir := '';
      Exit;
    end;
  end;

  JS_FreeValue(ctx, result_val);
  qar_helpers.CurrentScriptDir := '';
  Result := True;
end;

function RunEvalCode(ctx: PJSContext; const source_name: string; const code: string): boolean;
var
  eval_flags: cint;
  is_module: boolean;
  result_val: JSValue;
  job_result, loop_result: cint;
  pending_ctx: PJSContext;
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

  result_val := JS_Eval(ctx, PChar(code), QWord(Length(code)), PChar(source_name), eval_flags);
  if JS_IsException(result_val) <> 0 then
  begin
    js_std_dump_error(ctx);
    JS_FreeValue(ctx, result_val);
    Exit;
  end;

  job_result := 0;
  pending_ctx := nil;
  if eval_flags = JS_EVAL_TYPE_MODULE then
  begin
    repeat
      job_result := JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx);
      if job_result < 0 then
      begin
        if pending_ctx <> nil then
          js_std_dump_error(pending_ctx)
        else
          js_std_dump_error(ctx);
        Break;
      end;
    until job_result = 0;
  end;

  if job_result >= 0 then
  begin
    loop_result := js_std_loop(ctx);
    if loop_result <> 0 then
    begin
      js_std_dump_error(ctx);
      JS_FreeValue(ctx, result_val);
      Exit;
    end;
  end;

  JS_FreeValue(ctx, result_val);
  Result := True;
end;

begin
  ConsoleInitUtf8;

  ExamplesConfigFile := DefaultExamplesConfigFile;

  // Check for build QAR mode
  build_mode := False;
  output_file := '';
  input_count := 0;
  SetLength(input_files, 0);
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
  SetLength(minify_flags, 0);
  temp_stage_dir := '';
  run_script_mode := False;
  script_filename := '';
  script_argc := 0;
  exit_code := 0;
  eval_mode := False;
  eval_code := '';
  ReplGuardMode := rgFriendly;
  GuardExplicit := False;
  ReplShellMode := False;
  ReplShellImported := False;
  
  // Parse command line arguments
  i := 1;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '-o') or (ParamStr(i) = '--output') then
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
    else if (ParamStr(i) = '-d') or (ParamStr(i) = '--debug') then
    begin
      Inc(i);
      if i > ParamCount then
      begin
        qjs_log.DebugLevel := 1; // Default to level 1 if no value provided
      end
      else
      begin
        try
          qjs_log.DebugLevel := StrToInt(ParamStr(i));
          if (qjs_log.DebugLevel < 0) or (qjs_log.DebugLevel > 2) then
          begin
            WriteLn('Warning: Debug level must be 0-2, using 1');
            qjs_log.DebugLevel := 1;
          end;
        except
          WriteLn('Warning: Invalid debug level, using 1');
          qjs_log.DebugLevel := 1;
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
      WriteLn('  -o, --output FILE    Build QAR file from JavaScript files/directories');
      WriteLn('  -b, --build-qar      Build QAR file (same as -o)');
      WriteLn('  -d, --debug [LEVEL]  Enable debug output (0=off, 1=basic, 2=verbose, default=1)');
      WriteLn('  -e CODE              Evaluate JavaScript CODE');
      WriteLn('  --guard MODE         REPL crash guard: strict | friendly');
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
          DeleteFile(out_path);
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
        SetLength(staged, 1);
        build_inputs_stage := [qar_temp_dir];
        if not PrepareStagedInputs(minify_script, minify_flags, True, temp_stage_dir, build_inputs_stage, staged) then
        begin
          WriteLn('Error: Failed to prepare minified inputs');
          Halt(1);
        end;
        if qar.BuildQar(qar_tmp_out, staged) < 0 then
          Halt(1);
      end
      else
      begin
        if qar.BuildQar(qar_tmp_out, [qar_temp_dir]) < 0 then
          Halt(1);
      end;

      if qar_in_place then
      begin
        if not CopyFileTo(qar_tmp_out, script_path) then
        begin
          WriteLn('Error: Failed to replace input QAR');
          Halt(1);
        end;
        DeleteFile(qar_tmp_out);
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
        if qar.BuildQar(output_file, build_inputs_stage) < 0 then
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
      if qar.BuildQar(output_file, input_files) < 0 then
        Halt(1)
      else
        Halt(0);
    end;
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
  js_init_module_zip(ctx, 'zip');
  js_init_module_zip(ctx, 'qjs:zip');
  js_init_module_bjson(ctx, 'bjson');
  js_init_module_bjson(ctx, 'qjs:bjson');

  // Initialize standard handlers
  js_std_init_handlers(rt);

  ApplyDebugSettings(rt);

  // Set up module loader
  // App policy loader handles qjsp: prefix then falls back to std QAR/filesystem loader
  JS_SetModuleLoaderFunc(rt, nil, @qjsp_module_loader.qjsp_module_loader, nil);

  // Add standard helpers (console, print, etc.) and scriptArgs
  if (run_script_mode) and (script_argc > 0) then
    js_std_add_helpers(ctx, script_argc, @script_args[0])
  else
    js_std_add_helpers(ctx, 0, nil);

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
      pending_ctx := nil;
      while JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx) > 0 do
      begin
      end;
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
      pending_ctx := nil;
      while JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx) > 0 do
      begin
      end;
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
    LoadExamplesConfigFromFile(ExampleConfigs, ExamplesConfigFile, qjs_log.DebugLevel);
    if qjs_log.DebugLevel > 0 then
      WriteLn('Debug level: ', qjs_log.DebugLevel);
    WriteLn('Commands:');
    WriteLn('  .help | help                - Detailed help');
    WriteLn('  .load <file.js>             - Load & run a JS file');
    WriteLn('  .import <module> [name]     - Import ESM module and bind to global');
    WriteLn('  .build <out.qar> <inputs..> - Build QAR from JS files/folder');
    WriteLn('  .qar / .tool / .verify      - QAR tooling commands');
    WriteLn('  .example ...                - Run/manage example tests');
    WriteLn('  .debug [on|off|0|1|2]       - Toggle debug');
    WriteLn('  .guard [strict|friendly]    - REPL crash guard mode');
    WriteLn('  .sh on|off                  - Toggle shell mode (sh> prompt)');
    WriteLn('  .mem                        - Runtime memory usage');
    WriteLn('  .exit/.quit (exit/quit)     - Leave program');

    // Simple interactive loop
    while True do
    begin
      if ReplShellMode then
        Write('sh> ')
      else
        Write('js> ');
      script := ReadLnUtf8;
      if (script = 'exit') or (script = 'quit') or (script = '.exit') or (script = '.quit') then
        Break;

      if script = '' then
        Continue;

      try
        if (script = 'help') or (script = '.help') then
        begin
          WriteLn('Help');
          WriteLn('====');
          WriteLn;
          WriteLn('REPL basics:');
          WriteLn('  - Enter JavaScript expressions/statements to evaluate.');
          WriteLn('  - Type "exit" or "quit" to close the REPL.');
          WriteLn;
          WriteLn('REPL commands:');
          WriteLn('  .help | help');
          WriteLn('    Show this help.');
          WriteLn;
          WriteLn('  .load <file.js>');
          WriteLn('    Load and execute a JavaScript file.');
          WriteLn;
          WriteLn('  .import <module> [name]');
          WriteLn('    Import an ES module in MODULE mode and bind it to globalThis.');
          WriteLn('    Example: .import qjsp:sh sh');
          WriteLn('             sh.ls(".")');
          WriteLn;
          WriteLn('  .sh on|off');
          WriteLn('    Toggle shell mode. When ON, prompt becomes "sh>" and commands like');
          WriteLn('    "pwd", "ls", "cd <dir>", "which <cmd>" are mapped to qjsp:sh helpers.');
          WriteLn('    Type ".js" (or "js") to return to JS prompt.');
          WriteLn;
          WriteLn('  .build <out.qar> <file1.js> [file2.js ...]');
          WriteLn('  .build <out.qar> <directory/>');
          WriteLn('    Build a QAR bundle from JS input(s).');
          WriteLn;
          WriteLn('  .qar [subcommand] ...');
          WriteLn('  .tool [subcommand] ...      (alias of .qar)');
          WriteLn('    QAR tooling:');
          WriteLn('      info [--init-lib]       - QAR/QuickJS info');
          WriteLn('      build <out.qar> <inputs...>');
          WriteLn('      ls <file.qar> [prefix]  - List entries (inspect-style output)');
          WriteLn('      inspect <file.qar>      - Inspect QAR details');
          WriteLn('      cat <file.qar/entryPath>');
          WriteLn('      cat <file.qar> <entryPath> - Print embedded source/asset payload');
          WriteLn('      extract <file.qar> <out_dir> - Extract entries to directory');
          WriteLn('      rebuild <in.qar> <out.qar>');
          WriteLn('      code <file.qar> <entryPath> - (legacy) Print embedded source code');
          WriteLn('      version                 - QAR/QuickJS version');
          WriteLn('      help                    - This command list');
          WriteLn;
          WriteLn('  .verify <file.qar>');
          WriteLn('    Quick compatibility check (inspect + compatibility message).');
          WriteLn;
          WriteLn('  .example [command]');
          WriteLn('    Manage and run built-in example tests:');
          WriteLn('      (no args) | run         - Run all enabled tests');
          WriteLn('      list                    - List tests + enabled/disabled');
          WriteLn('      add <name>              - Add a test');
          WriteLn('      remove <name>           - Remove a test');
          WriteLn('      enable <name>           - Enable a test');
          WriteLn('      disable <name>          - Disable a test');
          WriteLn;
          WriteLn('  .debug [on|off|0|1|2]');
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
          WriteLn('Tips:');
          WriteLn('  - Use ".qar help" to see QAR tooling commands.');
          WriteLn('  - Use ".example list" to see available example test names.');
          WriteLn;
          Flush(Output);
          Continue;
        end;

        if (Copy(script, 1, 4) = '.sh ') or (script = '.sh') then
        begin
          cmdLine := '';
          if Length(script) > 4 then
            cmdLine := Trim(Copy(script, 5, Length(script)));

          if cmdLine = '' then
          begin
            if ReplShellMode then
              WriteLn('Shell mode: on')
            else
              WriteLn('Shell mode: off');
            WriteLn('Usage: .sh on | off');
            Flush(Output);
            Continue;
          end;

          cmdLine := LowerCase(cmdLine);
          if cmdLine = 'on' then
          begin
            ReplShellMode := True;
            WriteLn('Shell mode enabled (type ".js" to return)');
          end
          else if cmdLine = 'off' then
          begin
            ReplShellMode := False;
            WriteLn('Shell mode disabled');
          end
          else
          begin
            WriteLn('Warning: Invalid .sh value, must be on or off');
          end;

          Flush(Output);
          Continue;
        end;

        if ReplShellMode and ((script = '.js') or (script = 'js')) then
        begin
          ReplShellMode := False;
          Flush(Output);
          Continue;
        end;

        if ReplShellMode then
        begin
          if not ReplShellImported then
          begin
            file_content :=
              'import * as sh from "qjsp:sh";' + LineEnding +
              'globalThis["sh"] = sh;' + LineEnding;

            if RunEvalCode(ctx, '<repl_sh_import>', file_content) then
              ReplShellImported := True
            else
            begin
              WriteLn('Error: failed to import qjsp:sh');
              Flush(Output);
              Continue;
            end;
          end;

          shellJs := 'sh.repl(' + QuotedStr(script) + ')';
          script := shellJs;
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

        if (Copy(script, 1, 7) = '.debug ') or (script = '.debug') then
        begin
          cmdLine := '';
          if Length(script) > 7 then
            cmdLine := Trim(Copy(script, 8, Length(script)));

          if cmdLine = '' then
          begin
            WriteLn('Current debug level: ', qjs_log.DebugLevel);
            WriteLn('Usage: .debug on | off | 0 | 1 | 2');
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
                WriteLn('Warning: Invalid debug level, must be 0, 1, or 2');
                Flush(Output);
                Continue;
              end;
            end;

            if (newDebugLevel < 0) or (newDebugLevel > 2) then
            begin
              WriteLn('Warning: Debug level must be between 0 and 2');
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
              qjs_log.DebugLevel := newDebugLevel;
              ApplyDebugSettings(rt);
              WriteLn('Debug level set to ', qjs_log.DebugLevel);
              Flush(Output);
            end;
          end;

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
                job_result := 0;
                pending_ctx := nil;
                if eval_flags = JS_EVAL_TYPE_MODULE then
                begin
                  // Execute pending jobs (module initialization)
                  repeat
                    job_result := JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx);
                    if job_result < 0 then
                    begin
                      if pending_ctx <> nil then
                        js_std_dump_error(pending_ctx)
                      else
                        js_std_dump_error(ctx);
                      Break;
                    end;
                  until job_result = 0;
                end;

                if job_result >= 0 then
                begin
                  loop_result := js_std_loop(ctx);
                  if loop_result <> 0 then
                  begin
                    js_std_dump_error(ctx);
                  end
                  else
                  begin
                    // Flush output to ensure all console.log output is displayed
                    Flush(Output);
                    WriteLn('File loaded successfully');
                  end;
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
      
      // Handle .example command to manage and run example scripts
      if (Copy(script, 1, 9) = '.example ') or (script = '.example') then
      begin
        cmdLine := '';
        if Length(script) > 9 then
          cmdLine := Trim(Copy(script, 10, Length(script)));
        
        cmdArgs := TStringList.Create;
        try
          cmdArgs.Delimiter := ' ';
          cmdArgs.StrictDelimiter := True;
          cmdArgs.DelimitedText := cmdLine;
          
          // No subcommand or "run" - run enabled examples
          if (cmdArgs.Count = 0) or ((cmdArgs.Count = 1) and (LowerCase(cmdArgs[0]) = 'run')) then
          begin
            // Run enabled examples based on config
            for i := 0 to Length(ExampleConfigs) - 1 do
            begin
              if ExampleConfigs[i].enabled then
              begin
                if ExampleConfigs[i].name = 'example1_basic.js' then
                begin
                  WriteLn('=== Example 1: Basic JavaScript execution ===');
                  if LoadAndExecuteJSFile(ctx, 'tests/example1_basic.js') then
                  begin
                    if qjs_log.DebugLevel > 0 then
                      WriteLn('[DEBUG] Example 1 completed successfully');
                  end
                  else
                  begin
                    WriteLn('Warning: Could not load tests/example1_basic.js');
                  end;
                  WriteLn;
                end
                else if ExampleConfigs[i].name = 'example2_qar_info.js' then
                begin
                  if FileExists('qar_test.qar') then
                  begin
                    WriteLn('=== Example 2: QAR file info ===');
                    qar_helpers.ExampleReadQarInfo('qar_test.qar');
                    WriteLn;
                  end
                  else
                  begin
                    WriteLn('=== Example 2: QAR file info ===');
                    if LoadAndExecuteJSFile(ctx, 'tests/example2_qar_info.js') then
                    begin
                      if qjs_log.DebugLevel > 0 then
                        WriteLn('[DEBUG] Example 2 info displayed');
                    end
                    else
                    begin
                      WriteLn('QAR file "qar_test.qar" not found. Skipping QAR examples.');
                      WriteLn('To test QAR functionality, create a QAR file first using:');
                      WriteLn('  qjar -o qar_test.qar your_js_file.js');
                    end;
                    WriteLn;
                  end;
                end
                else if ExampleConfigs[i].name = 'example3_qar_usage.js' then
                begin
                  WriteLn('=== Example 3: Using QAR from JavaScript ===');
                  if LoadAndExecuteJSFile(ctx, 'tests/example3_qar_usage.js') then
                  begin
                    if qjs_log.DebugLevel > 0 then
                      WriteLn('[DEBUG] Example 3 completed successfully');
                  end
                  else
                  begin
                    WriteLn('Warning: Could not load tests/example3_qar_usage.js');
                  end;
                  WriteLn;
                end
                else if ExampleConfigs[i].name = 'example4_dll_test.js' then
                begin
                  WriteLn('=== Example 4: Dynamic Library Function Calls ===');
                  if LoadAndExecuteJSFile(ctx, 'tests/example4_dll_test.js') then
                  begin
                    if qjs_log.DebugLevel > 0 then
                      WriteLn('[DEBUG] Example 4 completed successfully');
                  end
                  else
                  begin
                    WriteLn('Warning: Could not load tests/example4_dll_test.js');
                    WriteLn('Note: To test dynamic library functionality:');
                    {$IFDEF WINDOWS}
                    WriteLn('      Compile test_dll.pas to test_dll.dll with: fpc -XX test_dll.pas');
                    {$ELSE}
                    {$IFDEF UNIX}
                    WriteLn('      Compile test_dll.pas to test_dll.so with: fpc -XX test_dll.pas');
                    {$ENDIF}
                    {$IFDEF DARWIN}
                    WriteLn('      Compile test_dll.pas to test_dll.dylib with: fpc -XX test_dll.pas');
                    {$ENDIF}
                    {$ENDIF}
                  end;
                  WriteLn;
                end
                else
                begin
                  // Generic test file
                  WriteLn('=== Running: ', ExampleConfigs[i].name, ' ===');
                  if LoadAndExecuteJSFile(ctx, 'tests/' + ExampleConfigs[i].name) then
                  begin
                    if qjs_log.DebugLevel > 0 then
                      WriteLn('[DEBUG] ', ExampleConfigs[i].name, ' completed successfully');
                  end
                  else
                  begin
                    WriteLn('Warning: Could not load tests/', ExampleConfigs[i].name);
                  end;
                  WriteLn;
                end;
              end;
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
            WriteLn('Use .example add <name> to add a test');
            WriteLn('Use .example remove <name> to remove a test');
            WriteLn('Use .example enable <name> to enable a test');
            WriteLn('Use .example disable <name> to disable a test');
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'add') then
          begin
            // Add a new test (enabled by default)
            j := examples_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
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
            j := examples_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
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
            j := examples_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
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
            j := examples_config.FindExampleConfig(ExampleConfigs, cmdArgs[1]);
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
            WriteLn('Usage: .example [command]');
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
                Flush(Output);
              end
              else
              begin
                build_output := build_args[0];
                do_minify := False;
                keep_temp := False;
                minify_safe := False;
                minify_script := '';
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
                    if qar.BuildQar(build_output, build_inputs_stage) < 0 then
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
                  if qar.BuildQar(build_output, build_inputs) < 0 then
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
            WriteLn('  info [--init-lib]           - QAR/QuickJS information');
            WriteLn('  build <out.qar> <files...>  - Create QAR from file JS/folder');
            WriteLn('  inspect <file.qar>          - Check detail file QAR');
            WriteLn('  rebuild <in.qar> <out.qar>  - Rebuild QAR');
            WriteLn('  code <file.qar> <entry>     - Display source code of entry');
            WriteLn('  version                     - QAR/QuickJS version');
            WriteLn('  help                        - Display help');
            WriteLn;
            WriteLn('Examples:');
            WriteLn('  .qar info --init-lib');
            WriteLn('  .qar build output.qar src/');
            WriteLn('  .qar inspect file.qar');
            WriteLn('  .qar rebuild old.qar new.qar');
            Flush(Output);
            Continue;
          end;

          subcmd := LowerCase(cmdArgs[0]);

          if (subcmd = 'help') then
          begin
            WriteLn('QAR Tool commands (.qar / .tool):');
            WriteLn('  info [--init-lib]           - QAR/QuickJS infomation');
            WriteLn('  build <out.qar> <files...>  - Create QAR from file JS/folder');
            WriteLn('  inspect <file.qar>          - Check detail file QAR');
            WriteLn('  rebuild <in.qar> <out.qar>  - Rebuild QAR');
            WriteLn('  code <file.qar> <entry>     - Display source code of entry');
            WriteLn('  version                     - QAR/QuickJS version');
            WriteLn('  help                        - Display help');
          end
          else if (subcmd = 'info') then
          begin
            init_default_lib_qar := False;
            for k_qar := 1 to cmdArgs.Count - 1 do
            begin
              if (cmdArgs[k_qar] = '--init-lib') or (cmdArgs[k_qar] = '-i') then
                init_default_lib_qar := True;
            end;
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
            if cmdArgs.Count < 3 then
            begin
              WriteLn('Usage: .qar build <output.qar> <file1.js> [file2.js ...]');
              WriteLn('   or: .qar build <output.qar> <directory/>');
              Flush(Output);
              Continue;
            end;
            qar_output := cmdArgs[1];

            do_minify := False;
            keep_temp := False;
            minify_safe := False;
            minify_script := '';
            SetLength(minify_flags, 0);
            SetLength(qar_inputs_list, 0);

            k_qar := 2;
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
              else
              begin
                SetLength(qar_inputs_list, Length(qar_inputs_list) + 1);
                qar_inputs_list[Length(qar_inputs_list) - 1] := cmdArgs[k_qar];
              end;
              Inc(k_qar);
            end;
            qar_inputs := qar_inputs_list;

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
                qar_ret := qar.BuildQar(qar_output, qar_inputs_stage);
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
              qar_ret := qar.BuildQar(qar_output, qar_inputs);

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
            qar_ret := qar.RebuildQarFile(qar_input, qar_output);
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
          // Sau khi await, kiểm tra lại exception (Promise có thể reject)
          if JS_IsException(result_val) <> 0 then
          begin
            js_std_dump_error(ctx);
            JS_FreeValue(ctx, result_val);
            Flush(Output);
            Continue; // Bỏ qua phần in kết quả
          end;
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
  // Cleanup
  if qjs_log.DebugLevel > 1 then
    DumpRuntimeMemoryUsageToConsole(rt);

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
      pending_ctx := nil;
      while JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx) > 0 do
      begin
      end;
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
