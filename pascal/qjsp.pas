program qjsp;

{$mode objfpc}{$H+}

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  SysUtils, ctypes, quickjs_types, quickjs_core, quickjs_intrinsics, quickjs_memdebug,
  quickjs_std, quickjs_qar, quickjs_miniz, quickjs_debug, quickjslibc, qar, Classes,
  fpjson, jsonparser,
  qar_helpers, dll_helpers, compression_helpers;

procedure WriteLnUtf8(const p: PChar);
{$IFDEF WINDOWS}
var
  wide: UnicodeString;
  len: Integer;
  handle: THandle;
  written: DWORD;
  newlineWide: WideString;
begin
  if p = nil then Exit;
  len := MultiByteToWideChar(CP_UTF8, 0, p, -1, nil, 0);
  if len <= 0 then Exit;
  // Allocate space including null terminator, then trim after conversion
  SetLength(wide, len);
  if len > 0 then
  begin
    MultiByteToWideChar(CP_UTF8, 0, p, -1, PWideChar(wide), len);
    SetLength(wide, len - 1); // drop null terminator
  end;
  handle := GetStdHandle(STD_OUTPUT_HANDLE);
  if (handle <> INVALID_HANDLE_VALUE) and (GetFileType(handle) = FILE_TYPE_CHAR) then
  begin
    WriteConsoleW(handle, PWideChar(wide), Length(wide), @written, nil);
    newlineWide := WideString(LineEnding);
    WriteConsoleW(handle, PWideChar(newlineWide), Length(newlineWide), @written, nil);
  end
  else
    WriteLn(wide);
end;
{$ELSE}
begin
  if p = nil then Exit;
  WriteLn(p);
end;
{$ENDIF}

function ReadLnUtf8: string;
{$IFDEF WINDOWS}
var
  handle: THandle;
  buf: array[0..255] of WideChar;
  readCount: DWORD;
  ws: UnicodeString;
  i: Integer;
begin
  handle := GetStdHandle(STD_INPUT_HANDLE);
  if (handle <> INVALID_HANDLE_VALUE) and (GetFileType(handle) = FILE_TYPE_CHAR) then
  begin
    ws := '';
    while True do
    begin
      if not ReadConsoleW(handle, @buf[0], Length(buf), @readCount, nil) then
        Break;
      if readCount = 0 then
        Break;
      for i := 0 to readCount - 1 do
      begin
        case buf[i] of
          #10:
            begin
              Result := UTF8Encode(ws);
              Exit;
            end;
          #13:
            Continue;
        else
          ws := ws + buf[i];
        end;
      end;
      // If buffer ended without newline, continue reading
    end;
    Result := UTF8Encode(ws);
    Exit;
  end;
  // If not a console (redirected), fall through to RTL ReadLn (code page already set to UTF-8)
{$ENDIF}
  ReadLn(Result);
end;

// Example test configuration type
type
  TExampleConfig = record
    enabled: boolean;
    name: string;
  end;

var
  ExampleConfigs: array of TExampleConfig;
  ExamplesConfigFile: string = 'examples_config.json';

// Forward declaration so it can be used from LoadExamplesConfig
procedure SaveExamplesConfig(ctx: PJSContext); forward;

// Helper function to load examples config from JSON file
procedure LoadExamplesConfig(ctx: PJSContext);
var
  json_content, line: string;
  f: TextFile;
  jsonData, examplesData: TJSONData;
  rootObj, examplesObj: TJSONObject;
  i, count: integer;
  key: string;
  item: TJSONData;
  enabled: boolean;
begin
  // Start with empty configuration
  SetLength(ExampleConfigs, 0);

  // If config file does not exist, leave the list empty
  if not FileExists(ExamplesConfigFile) then
    Exit;

  // Read JSON file into a single string
  json_content := '';
  AssignFile(f, ExamplesConfigFile);
  Reset(f);
  try
    while not EOF(f) do
    begin
      ReadLn(f, line);
      if json_content <> '' then
        json_content := json_content + LineEnding;
      json_content := json_content + line;
    end;
  finally
    CloseFile(f);
  end;

  if json_content = '' then
    Exit;

  // Parse JSON using FreePascal's fpjson
  try
    jsonData := GetJSON(json_content);
  except
    on E: Exception do
    begin
      if qar_helpers.DebugLevel > 0 then
        WriteLn('[DEBUG] Failed to parse examples config JSON (fpjson): ', E.Message);
      Exit;
    end;
  end;

  try
    if not (jsonData is TJSONObject) then
      Exit;

    rootObj := TJSONObject(jsonData);
    examplesData := rootObj.Find('examples');
    if (examplesData = nil) or not (examplesData is TJSONObject) then
      Exit;

    examplesObj := TJSONObject(examplesData);
    count := examplesObj.Count;
    SetLength(ExampleConfigs, count);

    for i := 0 to count - 1 do
    begin
      key := examplesObj.Names[i];
      item := examplesObj.Items[i];

      if (item <> nil) and (item.JSONType = jtBoolean) then
        enabled := item.AsBoolean
      else
        enabled := False;

      ExampleConfigs[i].name := key;
      ExampleConfigs[i].enabled := enabled;
    end;
  finally
    jsonData.Free;
  end;
end;

// Helper function to save examples config to JSON file
procedure SaveExamplesConfig(ctx: PJSContext);
var
  rootObj, examplesObj: TJSONObject;
  f: TextFile;
  i: integer;
  jsonStr: string;
begin
  // Build JSON structure: { "examples": { "name": boolean, ... } }
  rootObj := TJSONObject.Create;
  try
    examplesObj := TJSONObject.Create;
    rootObj.Add('examples', examplesObj);

    // Add each example to examples object
    for i := 0 to Length(ExampleConfigs) - 1 do
      examplesObj.Add(ExampleConfigs[i].name, ExampleConfigs[i].enabled);

    // Serialize to string
    jsonStr := rootObj.FormatJSON([]);

    // Write to file
    AssignFile(f, ExamplesConfigFile);
    Rewrite(f);
    try
      Write(f, jsonStr);
    finally
      CloseFile(f);
    end;
  finally
    rootObj.Free;
  end;
end;

procedure ApplyDebugSettings(rt: PJSRuntime);
begin
  if qar_helpers.DebugLevel > 1 then
    EnableAllDebugDumps(rt)
  else
    DisableAllDebugDumps(rt);

  if qar_helpers.DebugLevel > 0 then
    JS_InstallLoggingPromiseRejectionTracker(rt)
  else
    JS_InstallStdPromiseRejectionTracker(rt);
end;

// Helper function to find example config index by name
function FindExampleConfig(const name: string): integer;
var
  i: integer;
begin
  Result := -1;
  for i := 0 to Length(ExampleConfigs) - 1 do
  begin
    if ExampleConfigs[i].name = name then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

// Helper function to load and execute a JS file
function LoadAndExecuteJSFile(ctx: PJSContext; const filename: string): boolean;
var
  file_content, line: string;
  f: TextFile;
  result_val: JSValue;
  eval_flags: cint;
  script_path, exe_dir, test_path: string;
begin
  Result := False;
  
  // Try multiple paths: current dir, executable dir, executable dir/tests
  script_path := ExpandFileName(filename);
  if not FileExists(script_path) then
  begin
    exe_dir := ExtractFileDir(ParamStr(0));
    if exe_dir <> '' then
    begin
      test_path := IncludeTrailingPathDelimiter(exe_dir) + filename;
      if FileExists(test_path) then
        script_path := test_path
      else
      begin
        test_path := IncludeTrailingPathDelimiter(exe_dir) + 'tests' + PathDelim + ExtractFileName(filename);
        if FileExists(test_path) then
          script_path := test_path;
      end;
    end;
  end;
  
  if not FileExists(script_path) then
  begin
    if qar_helpers.DebugLevel > 0 then
      WriteLn('[DEBUG] File not found: ', filename, ' (tried: ', script_path, ')');
    Exit;
  end;
  
  if qar_helpers.DebugLevel > 0 then
    WriteLn('[DEBUG] Loading file: ', script_path);
  
  // Read file content
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
  
  // Execute file content
  eval_flags := JS_EVAL_TYPE_GLOBAL;
  if JS_DetectModule(PChar(file_content), QWord(Length(file_content))) <> 0 then
  begin
    eval_flags := JS_EVAL_TYPE_MODULE;
    if qar_helpers.DebugLevel > 1 then
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

// Main program
var
  rt: PJSRuntime;
  ctx: PJSContext;
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

// Run a JS file (non-interactive mode)
function RunScriptFile(ctx: PJSContext; const filename: string): boolean;
var
  file_content, line: string;
  f: TextFile;
  eval_flags: cint;
  script_path, exe_dir, test_path: string;
  old_dir, script_dir: string;
  is_module: boolean;
  result_val: JSValue;
  job_result, loop_result: cint;
  pending_ctx: PJSContext;
begin
  Result := False;

  script_path := ExpandFileName(filename);
  if not FileExists(script_path) then
  begin
    exe_dir := ExtractFileDir(ParamStr(0));
    if exe_dir <> '' then
    begin
      test_path := IncludeTrailingPathDelimiter(exe_dir) + filename;
      if FileExists(test_path) then
        script_path := test_path
      else
      begin
        test_path := IncludeTrailingPathDelimiter(exe_dir) + 'tests' + PathDelim + ExtractFileName(filename);
        if FileExists(test_path) then
          script_path := test_path;
      end;
    end;
  end;

  if not FileExists(script_path) then
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
    if script_dir <> '' then
    begin
      test_path := IncludeTrailingPathDelimiter(script_dir) + 'qar_test.qar';
      if FileExists(test_path) then
      begin
        if qar_helpers.DebugLevel > 0 then
          WriteLn('[DEBUG] Found qar_test.qar in script directory (no auto-register; use LoadLibrary("', test_path, '") if needed)');
      end;
    end;
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

begin
  {$IFDEF WINDOWS}
  // Ensure console I/O and RTL conversions use UTF-8 so JS strings print correctly
  SetMultiByteConversionCodePage(CP_UTF8);
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
  {$ENDIF}

  // Check for build QAR mode
  build_mode := False;
  output_file := '';
  input_count := 0;
  SetLength(input_files, 0);
  run_script_mode := False;
  script_filename := '';
  script_argc := 0;
  exit_code := 0;
  
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
        qar_helpers.DebugLevel := 1; // Default to level 1 if no value provided
      end
      else
      begin
        try
          qar_helpers.DebugLevel := StrToInt(ParamStr(i));
          if (qar_helpers.DebugLevel < 0) or (qar_helpers.DebugLevel > 2) then
          begin
            WriteLn('Warning: Debug level must be 0-2, using 1');
            qar_helpers.DebugLevel := 1;
          end;
        except
          WriteLn('Warning: Invalid debug level, using 1');
          qar_helpers.DebugLevel := 1;
        end;
      end;
    end
    else if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
    begin
      WriteLn('QuickJS Pascal Demo');
      WriteLn('==================');
      WriteLn;
      WriteLn('Usage:');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' [options] [script.js [args...]]');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' [options] -o output.qar inputs...');
      WriteLn;
      WriteLn('Options:');
      WriteLn('  -o, --output FILE    Build QAR file from JavaScript files/directories');
      WriteLn('  -b, --build-qar      Build QAR file (same as -o)');
      WriteLn('  -d, --debug [LEVEL]  Enable debug output (0=off, 1=basic, 2=verbose, default=1)');
      WriteLn('  -h, --help           Show this help');
      WriteLn;
      WriteLn('Examples:');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' script.js arg1 arg2   (run JS file, no REPL)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -o mylib.qar math.js utils.js');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -o mylib.qar src/');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -d 2                  (interactive mode with verbose debug)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), '                        (interactive mode)');
      Halt(0);
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
  
  // If not building, treat first non-option argument as script to run (non-interactive)
  if (not build_mode) and (input_count > 0) then
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
    
    SetLength(input_files, input_count);
    // Khi gọi từ main.pas không chỉ định entry_points (dùng giá trị mặc định rỗng)
    if qar.BuildQar(output_file, input_files) < 0 then
      Halt(1)
    else
      Halt(0);
  end;
  
  if not run_script_mode then
  begin
    WriteLn('QuickJS Pascal Demo');
    WriteLn('==================');
    WriteLn;
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
  js_init_module_bjson(ctx, 'bjson');
  js_init_module_bjson(ctx, 'qjs:bjson');

  // Initialize standard handlers
  js_std_init_handlers(rt);

  ApplyDebugSettings(rt);

  // Set up module loader
  // - Script mode: default loader (filesystem + built-ins)
  // - Interactive/QAR mode: wrapper to support QAR lookups
  if run_script_mode then
    JS_SetModuleLoaderFunc(rt, nil, @js_module_loader, nil)
  else
    JS_SetModuleLoaderFunc(rt, nil, @qar_helpers.js_module_loader_wrapper, nil);

  // Add standard helpers (console, print, etc.) and scriptArgs
  if (run_script_mode) and (script_argc > 0) then
    js_std_add_helpers(ctx, script_argc, @script_args[0])
  else
    js_std_add_helpers(ctx, 0, nil);

  // Preload std/os/bjson and set globals (interactive mode only)
  if not run_script_mode then
  begin
    file_content :=
      'import * as bjson from ''qjs:bjson'';' + LineEnding +
      'import * as std from ''qjs:std'';' + LineEnding +
      'import * as os from ''qjs:os'';' + LineEnding +
      'globalThis.bjson = bjson;' + LineEnding +
      'globalThis.std = std;' + LineEnding +
      'globalThis.os = os;' + LineEnding +
      'if (globalThis.setTimeout === void 0) globalThis.setTimeout = os.setTimeout;' + LineEnding +
      'if (globalThis.clearTimeout === void 0) globalThis.clearTimeout = os.clearTimeout;' + LineEnding +
      'if (globalThis.setInterval === void 0) globalThis.setInterval = os.setInterval;' + LineEnding +
      'if (globalThis.clearInterval === void 0) globalThis.clearInterval = os.clearInterval;' + LineEnding;

    result_val := JS_Eval(ctx,
      PChar(file_content),
      QWord(Length(file_content)),
      PChar('<init>'),
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

  if run_script_mode then
  begin
    if not RunScriptFile(ctx, script_filename) then
      exit_code := 1;
  end
  else
  begin
    // Load examples configuration
    LoadExamplesConfig(ctx);

    WriteLn('QuickJS version: ', JS_GetVersion);
    if qar_helpers.DebugLevel > 0 then
      WriteLn('Debug level: ', qar_helpers.DebugLevel);
    WriteLn;

    // Interactive mode help
    WriteLn('Interactive JavaScript REPL');
    WriteLn('Type JavaScript code (or "exit" to quit):');
    WriteLn('Note: To use QAR modules, first run: LoadLibrary("qar_test.qar")');
    WriteLn('      Then check entries with: GetQarInfo("qar_test.qar")');
    WriteLn('      To build QAR files, use: BuildQar("output.qar", ["file1.js", "file2.js"])');
    WriteLn('      Or with single file: BuildQar("output.qar", "file.js")');
    WriteLn('      Or with directory: BuildQar("output.qar", "src/")');
    WriteLn('      To load a JS file, use: .load filename.js');
    WriteLn('      To build QAR from REPL, use: .build output.qar file1.js file2.js');
    WriteLn('      Or: .build output.qar src/');
    WriteLn('      To call dynamic library functions:');
    WriteLn('        lib_id = LoadLib("mylib")        // tries .qar then platform lib');
    {$IFDEF WINDOWS}
    WriteLn('        // Or load specific: lib_id = LoadDLL("mylib.dll")');
    {$ELSE}
    {$IFDEF UNIX}
    WriteLn('        // Or load specific: lib_id = LoadDLL("mylib.so")');
    {$ENDIF}
    {$IFDEF DARWIN}
    WriteLn('        // Or load specific: lib_id = LoadDLL("mylib.dylib")');
    {$ENDIF}
    {$ENDIF}
    WriteLn('        result = CallDllFunction(lib_id, "MyFunction", "i", 42)');
    WriteLn('        FreeDLL(lib_id)');
    WriteLn('      QAR helper commands:');
    WriteLn('        .qar info [--init-lib]           - QAR/QuickJS information');
    WriteLn('        .qar build <out.qar> <files...>  - Build QAR (same as qar_tool build)');
    WriteLn('        .qar code <file.qar> <entry>     - Display source code of entry');
    WriteLn('        .qar inspect <file.qar>          - Inspect QAR file details');
    WriteLn('        .qar rebuild <in.qar> <out.qar>  - Rebuild QAR file');
    WriteLn('        .qar version                     - QAR/QuickJS version');
    WriteLn('        .verify <file.qar>               - Check compatibility only');
    WriteLn('        .tool ...                        - Same as .qar ...');
    WriteLn('        .example [command]              - Manage and run example tests');
    WriteLn('          .example                      - Run all enabled tests');
    WriteLn('          .example list                 - List all tests and status');
    WriteLn('          .example add <name>           - Add a test');
    WriteLn('          .example remove <name>        - Remove a test');
    WriteLn('          .example enable <name>         - Enable a test');
    WriteLn('          .example disable <name>       - Disable a test');
    WriteLn;

    // Simple interactive loop
    while True do
    begin
      Write('js> ');
      script := ReadLnUtf8;
      if (script = 'exit') or (script = 'quit') then
        Break;

    if script <> '' then
    begin
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
          WriteLn('Current debug level: ', qar_helpers.DebugLevel);
          WriteLn('Usage: .debug on | off | 0 | 1 | 2');
          Flush(Output);
        end
        else
        begin
          cmdLine := LowerCase(cmdLine);
          newDebugLevel := qar_helpers.DebugLevel;

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

          if newDebugLevel = qar_helpers.DebugLevel then
          begin
            WriteLn('Debug level is already ', qar_helpers.DebugLevel);
            Flush(Output);
          end
          else
          begin
            qar_helpers.DebugLevel := newDebugLevel;
            ApplyDebugSettings(rt);
            WriteLn('Debug level set to ', qar_helpers.DebugLevel);
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
            if FileExists(script) then
            begin
              WriteLn('Loading file: ', script);
              Flush(Output);
              
              // Lưu working directory hiện tại và chuyển sang thư mục của file
              old_dir := GetCurrentDir;
              script_path := ExpandFileName(script);
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
              
              // Execute file content
              if qar_helpers.DebugLevel > 1 then
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
                if qar_helpers.DebugLevel > 0 then
                  WriteLn('[DEBUG] Detected as MODULE - imports will be resolved before top-level code');
              end
              else
              begin
                eval_flags := JS_EVAL_TYPE_GLOBAL;

                if qar_helpers.DebugLevel > 1 then
                  WriteLn('[DEBUG] Detected as GLOBAL script');

                // Pre-register QAR files in script directory to avoid import resolution issues
                // QuickJS resolves imports before executing top-level code, so LoadLibrary
                // calls may happen too late. Pre-register common QAR files.
                if script_dir <> '' then
                begin
                  test_path := IncludeTrailingPathDelimiter(script_dir) + 'qar_test.qar';
                  if FileExists(test_path) then
                  begin
                    if qar_helpers.DebugLevel > 0 then
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
                    if qar_helpers.DebugLevel > 0 then
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
          end
          else
          begin
            WriteLn('Error: .load requires a filename');
            Flush(Output);
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
                    if qar_helpers.DebugLevel > 0 then
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
                      if qar_helpers.DebugLevel > 0 then
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
                    if qar_helpers.DebugLevel > 0 then
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
                    if qar_helpers.DebugLevel > 0 then
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
                    if qar_helpers.DebugLevel > 0 then
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
            j := FindExampleConfig(cmdArgs[1]);
            if j >= 0 then
            begin
              WriteLn('Test "', cmdArgs[1], '" already exists');
            end
            else
            begin
              SetLength(ExampleConfigs, Length(ExampleConfigs) + 1);
              ExampleConfigs[Length(ExampleConfigs) - 1].name := cmdArgs[1];
              ExampleConfigs[Length(ExampleConfigs) - 1].enabled := True;
              SaveExamplesConfig(ctx);
              WriteLn('Added test "', cmdArgs[1], '" (enabled)');
            end;
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'remove') then
          begin
            // Remove a test
            j := FindExampleConfig(cmdArgs[1]);
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
              SaveExamplesConfig(ctx);
              WriteLn('Removed test "', cmdArgs[1], '"');
            end;
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'enable') then
          begin
            // Enable a test
            j := FindExampleConfig(cmdArgs[1]);
            if j < 0 then
            begin
              WriteLn('Test "', cmdArgs[1], '" not found');
            end
            else
            begin
              ExampleConfigs[j].enabled := True;
              SaveExamplesConfig(ctx);
              WriteLn('Enabled test "', cmdArgs[1], '"');
            end;
          end
          else if (cmdArgs.Count >= 2) and (LowerCase(cmdArgs[0]) = 'disable') then
          begin
            // Disable a test
            j := FindExampleConfig(cmdArgs[1]);
            if j < 0 then
            begin
              WriteLn('Test "', cmdArgs[1], '" not found');
            end
            else
            begin
              ExampleConfigs[j].enabled := False;
              SaveExamplesConfig(ctx);
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
                SetLength(build_inputs, build_args.Count - 1);
                for j := 1 to build_args.Count - 1 do
                  build_inputs[j - 1] := build_args[j];
                
                WriteLn('Building QAR file: ', build_output);
                WriteLn('Input files/directories:');
                for j := 0 to Length(build_inputs) - 1 do
                  WriteLn('  ', build_inputs[j]);
                Flush(Output);
                
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
              cmdArgs.Free;
              Continue;
            end;
            qar_input := cmdArgs[0];
            if not FileExists(qar_input) then
            begin
              WriteLn('Error: QAR file not found: ', qar_input);
              Flush(Output);
              cmdArgs.Free;
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
            cmdArgs.Free;
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
            WriteLn('  help                        - Hiển thị trợ giúp');
            WriteLn;
            WriteLn('Ví dụ:');
            WriteLn('  .qar info --init-lib');
            WriteLn('  .qar build output.qar src/');
            WriteLn('  .qar inspect file.qar');
            WriteLn('  .qar rebuild old.qar new.qar');
            Flush(Output);
            cmdArgs.Free;
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
              cmdArgs.Free;
              Continue;
            end;
            qar_output := cmdArgs[1];
            SetLength(qar_inputs, cmdArgs.Count - 2);
            for k_qar := 2 to cmdArgs.Count - 1 do
              qar_inputs[k_qar - 2] := cmdArgs[k_qar];

            WriteLn('Building QAR file: ', qar_output);
            WriteLn('Input files/directories:');
            for k_qar := 0 to Length(qar_inputs) - 1 do
              WriteLn('  ', qar_inputs[k_qar]);
            Flush(Output);

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
              cmdArgs.Free;
              Continue;
            end;
            qar_input := cmdArgs[1];
            if not FileExists(qar_input) then
            begin
              WriteLn('Error: QAR file not found: ', qar_input);
              Flush(Output);
              cmdArgs.Free;
              Continue;
            end;
            qar_inspection := qar.InspectQarFile(qar_input);
            try
              qar.PrintQarInspection(qar_inspection);
            finally
              qar_inspection.dependencies.Free;
            end;
          end
          else if (subcmd = 'rebuild') then
          begin
            if cmdArgs.Count < 3 then
            begin
              WriteLn('Usage: .qar rebuild <input.qar> <output.qar>');
              Flush(Output);
              cmdArgs.Free;
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
        if qar_helpers.DebugLevel > 1 then
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
    end;
  end;

  // End interactive mode block
  end;

  // Cleanup
  if qar_helpers.DebugLevel > 1 then
    DumpRuntimeMemoryUsageToConsole(rt);

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
