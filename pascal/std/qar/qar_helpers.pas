unit qar_helpers;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ctypes, quickjs_types, quickjs_core, quickjs_std, qar, qjs_log;

// Type alias for QAR reading functions (from qar unit)
type
  PQarEntryRead = qar.PQarEntry;

// Global variable to store current script directory for LoadLibrary resolution
var
  CurrentScriptDir: string = '';

type
  TRegisteredQar = record
    filename: string;
    prefix: string;
    qar: PQarFile;
  end;

var
  RegisteredQars: array of TRegisteredQar;

function RegisterQarFile(const qar_filename: string; const prefix: string): cint;
procedure UnregisterAllQarFiles;
function TryLoadModuleFromRegisteredQars(ctx: PJSContext; const module_name: string): PJSModuleDef;

// Helper function to find QAR file in multiple locations
function FindQarFile(const qar_filename: string): string;

// JavaScript bindings for QAR functions
function js_load_qar_library(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_get_qar_info(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_execute_qar_entry(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_get_qar_asset(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_build_qar(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_module_loader_wrapper(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;

// Register QAR helper functions to JavaScript global object
procedure RegisterQarHelpers(ctx: PJSContext);

// Example functions
procedure ExampleLoadQar(ctx: PJSContext; qar_filename: string);
procedure ExampleReadQarInfo(qar_filename: string);
procedure ExampleExecuteQarEntry(ctx: PJSContext; qar_filename, entry_path: string);

implementation

function QarRebuildBytecodeFromSource(ctx: PJSContext; entry: PQarEntryRead; const entry_name_for_log: string; is_module: boolean; out obj: JSValue): boolean;
var
  source_len: csize_t;
  source: Pcuint8;
  eval_flags: cint;
  bc_ptr: Pcuint8;
  bc_len: csize_t;
  rt: PJSRuntime;
begin
  Result := False;
  obj := JS_UNDEFINED;

  source_len := 0;
  source := qar_entry_get_source(entry, @source_len);
  if (source = nil) or (source_len = 0) then
    Exit;

  eval_flags := JS_EVAL_FLAG_COMPILE_ONLY;
  if is_module then
    eval_flags := eval_flags or JS_EVAL_TYPE_MODULE
  else
    eval_flags := eval_flags or JS_EVAL_TYPE_GLOBAL;

  obj := JS_Eval(ctx, PChar(source), QWord(source_len), PChar(entry_name_for_log), eval_flags);
  if JS_IsException(obj) <> 0 then
    Exit;

  bc_len := 0;
  bc_ptr := JS_WriteObject(ctx, @bc_len, obj, JS_WRITE_OBJ_BYTECODE or JS_WRITE_OBJ_REFERENCE);
  if (bc_ptr <> nil) and (bc_len > 0) then
  begin
    SetLength(entry^.bytecode_cache, bc_len);
    Move(bc_ptr^, entry^.bytecode_cache[0], bc_len);
    rt := JS_GetRuntime(ctx);
    if rt <> nil then
      js_free_rt(rt, bc_ptr)
    else
      js_free(ctx, bc_ptr);
  end;

  Result := True;
end;

function RegisterQarFile(const qar_filename: string; const prefix: string): cint;
var
  q: PQarFile;
  n: integer;
begin
  q := qar_open(PChar(qar_filename));
  if q = nil then
    Exit(-1);

  n := Length(RegisteredQars);
  SetLength(RegisteredQars, n + 1);
  RegisteredQars[n].filename := qar_filename;
  RegisteredQars[n].prefix := prefix;
  RegisteredQars[n].qar := q;
  Result := 0;
end;

procedure UnregisterAllQarFiles;
var
  i: integer;
begin
  for i := 0 to High(RegisteredQars) do
    if RegisteredQars[i].qar <> nil then
      qar_close(RegisteredQars[i].qar);
  SetLength(RegisteredQars, 0);
end;

function JSValuePtr(const v: JSValue): pointer; inline;
begin
  Result := v.u.ptr;
end;

function TryLoadModuleFromRegisteredQars(ctx: PJSContext; const module_name: string): PJSModuleDef;
var
  nameNoPrefix: string;
  requestedPrefix: string;
  colonPos: integer;
  i: integer;
  entry: PQarEntryRead;
  bytecode_len: csize_t;
  bytecode: Pcuint8;
  obj: JSValue;
  eval_flags: cint;
  m: PJSModuleDef;
  ok: boolean;
  exc: JSValue;
begin
  try
    Result := nil;
    if module_name = '' then
      Exit;

  requestedPrefix := '';
  nameNoPrefix := module_name;
  colonPos := Pos(':', module_name);
  if colonPos > 0 then
  begin
    requestedPrefix := Copy(module_name, 1, colonPos);
    nameNoPrefix := Copy(module_name, colonPos + 1, Length(module_name));
  end;

  for i := 0 to High(RegisteredQars) do
  begin
    if (requestedPrefix <> '') and (RegisteredQars[i].prefix <> requestedPrefix) then
      Continue;
    if RegisteredQars[i].qar = nil then
      Continue;

    entry := qar_find_entry(RegisteredQars[i].qar, PChar(nameNoPrefix));
    if entry = nil then
      Continue;

    if qar_entry_get_type(entry) = 0 then
      Continue;

    if qar_entry_load_data(RegisteredQars[i].qar, entry) < 0 then
      Continue;

    bytecode_len := 0;
    bytecode := qar_entry_get_bytecode(entry, @bytecode_len);
    obj := JS_UNDEFINED;
    ok := False;
    if (bytecode <> nil) and (bytecode_len > 0) then
    begin
      eval_flags := JS_READ_OBJ_BYTECODE or JS_READ_OBJ_REFERENCE;
      obj := JS_ReadObject(ctx, bytecode, QWord(bytecode_len), LongInt(eval_flags));
      if JS_IsException(obj) = 0 then
        ok := True
      else
      begin
        if qjs_log.DebugLevel > 0 then
        begin
          WriteLn('[QAR] Bytecode load failed for module "', nameNoPrefix, '". Rebuilding from source...');
          js_std_dump_error(ctx);
          Flush(Output);
          Flush(StdErr);
        end;
        exc := JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
      end;
    end;

    if not ok then
    begin
      ok := QarRebuildBytecodeFromSource(ctx, entry, nameNoPrefix, True, obj);
      if not ok then
        Continue;
    end;

    if js_module_set_import_meta(ctx, obj, cbool(1), cbool(0)) < 0 then
    begin
      JS_FreeValue(ctx, obj);
      Exit(nil);
    end;

    m := PJSModuleDef(JSValuePtr(obj));
    JS_FreeValue(ctx, obj);
    Result := m;
    Exit;
  end;
  except
    on E: Exception do
    begin
      JS_ThrowReferenceError(ctx, PChar('qar:TryLoadModule: ' + E.Message));
      Result := nil;
      Exit;
    end;
  end;
end;

// Helper function to find QAR file in multiple locations
function FindQarFile(const qar_filename: string): string;
var
  search_paths: array of string;
  i, path_count: integer;
  test_path: string;
  exe_dir: string;
begin
  Result := '';
  
  // 1. Exact path (if absolute or relative to current dir)
  if FileExists(qar_filename) then
  begin
    Result := ExpandFileName(qar_filename);
    Exit;
  end;
  
  // Build search paths
  path_count := 0;
  SetLength(search_paths, 10); // Pre-allocate space
  
  // 2. Current working directory
  search_paths[path_count] := GetCurrentDir;
  Inc(path_count);
  
  // 3. Current script directory (if set)
  if CurrentScriptDir <> '' then
  begin
    search_paths[path_count] := CurrentScriptDir;
    Inc(path_count);
  end;
  
  // 4. Executable directory
  exe_dir := ExtractFileDir(ParamStr(0));
  if exe_dir <> '' then
  begin
    search_paths[path_count] := exe_dir;
    Inc(path_count);
  end;
  
  // 5. Parent of executable directory (for master/ subdirectory)
  if exe_dir <> '' then
  begin
    test_path := ExtractFileDir(exe_dir);
    if test_path <> '' then
    begin
      search_paths[path_count] := test_path;
      Inc(path_count);
    end;
  end;
  
  // Try each search path
  for i := 0 to path_count - 1 do
  begin
    test_path := IncludeTrailingPathDelimiter(search_paths[i]) + qar_filename;
    if FileExists(test_path) then
    begin
      Result := ExpandFileName(test_path);
      Exit;
    end;
  end;
end;

// Helper function to register QAR from JavaScript
function js_load_qar_library(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename, prefix: PChar;
  filename_str, found_path: string;
  ret: cint;
  search_paths: string;
  prefix_str: string;
begin
  try
  // Debug: function được gọi
  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[LoadLibrary] Function called with argc=', argc);
    Flush(Output);
    Flush(StdErr);
  end;
  
  if argc < 1 then
  begin
    if qjs_log.DebugLevel > 0 then
    begin
      WriteLn('[LoadLibrary] Error: argc < 1');
      Flush(Output);
    end;
    Result := JS_ThrowTypeError(ctx, PChar('LoadLibrary expects at least 1 argument'));
    Exit;
  end;

  filename := JS_ToCString(ctx, argv[0]);
  if filename = nil then
  begin
    if qjs_log.DebugLevel > 0 then
    begin
      WriteLn('[LoadLibrary] Error: JS_ToCString returned nil');
      Flush(Output);
    end;
    Result := JS_EXCEPTION;
    Exit;
  end;

  filename_str := string(filename);
  JS_FreeCString(ctx, filename);

  prefix := nil;
  prefix_str := '';
  if argc >= 2 then
  begin
    prefix := JS_ToCString(ctx, argv[1]);
    if prefix = nil then
    begin
      if qjs_log.DebugLevel > 0 then
      begin
        WriteLn('[LoadLibrary] Error: JS_ToCString for prefix returned nil');
        Flush(Output);
      end;
      Result := JS_EXCEPTION;
      Exit;
    end;
  end;

  // Try to find QAR file in multiple locations
  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[LoadLibrary] Looking for QAR file: ', filename_str);
    WriteLn('[LoadLibrary] Current working directory: ', GetCurrentDir);
    WriteLn('[LoadLibrary] CurrentScriptDir: ', CurrentScriptDir);
    Flush(Output);
    Flush(StdErr);
  end;
  
  found_path := FindQarFile(filename_str);
  
  if found_path = '' then
  begin
    if qjs_log.DebugLevel > 0 then
    begin
      // Build search paths message
      search_paths := 'Searched in: ' + GetCurrentDir;
      if CurrentScriptDir <> '' then
        search_paths := search_paths + ', ' + CurrentScriptDir;
      search_paths := search_paths + ', ' + ExtractFileDir(ParamStr(0));
      
      WriteLn('Error: QAR file not found: ', filename_str);
      WriteLn('  ', search_paths);
      WriteLn('  Current working directory: ', GetCurrentDir);
      if CurrentScriptDir <> '' then
        WriteLn('  Script directory: ', CurrentScriptDir);
      WriteLn('  Executable directory: ', ExtractFileDir(ParamStr(0)));
      Flush(Output);
      Flush(StdErr);
    end;
    
    if prefix <> nil then
      JS_FreeCString(ctx, prefix);
    
    Result := JS_ThrowTypeError(ctx, PChar('QAR file not found: ' + filename_str));
    Exit;
  end;
  
  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[LoadLibrary] Found QAR file at: ', found_path);
    Flush(Output);
  end;

  // Register with found path
  ret := RegisterQarFile(found_path, prefix_str);

  // Log kết quả trước khi free prefix
  if qjs_log.DebugLevel > 0 then
  begin
    if ret < 0 then
    begin
      WriteLn('Error: Failed to register QAR file: ', found_path);
      WriteLn('  (Original path: ', filename_str, ')');
      Flush(Output);
    end
    else
    begin
      WriteLn('Successfully registered QAR file: ', found_path);
      if found_path <> filename_str then
        WriteLn('  (Resolved from: ', filename_str, ')');
      if prefix <> nil then
        WriteLn('  (Using prefix: "', prefix, '" - import with "', prefix, 'module.js")')
      else
        WriteLn('  (No prefix - modules will be searched in all registered QAR files)');
      Flush(Output);
    end;
  end;

  if prefix <> nil then
    JS_FreeCString(ctx, prefix);

  if ret < 0 then
    Result := JS_ThrowTypeError(ctx, PChar('Failed to register QAR file'))
  else
    Result := JS_UNDEFINED;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:LoadLibrary: ' + E.Message));
  end;
end;

// Helper function to get QAR info from JavaScript
function js_get_qar_info(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename: PChar;
  filename_str, found_path: string;
  qar: PQarFile;
  entry_count: cint;
  i: cint;
  entry: PQarEntryRead;
  entry_path: PChar;
  entry_type: cint;
  obj, arr, item, stringified: JSValue;
  manifest_len: csize_t;
  manifest: PChar;
  version: PChar;
begin
  try
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('GetQarInfo expects 1 argument'));
    Exit;
  end;

  filename := JS_ToCString(ctx, argv[0]);
  if filename = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  filename_str := string(filename);
  JS_FreeCString(ctx, filename);

  // Try to find QAR file in multiple locations
  found_path := FindQarFile(filename_str);
  
  if found_path = '' then
  begin
    WriteLn('Error: QAR file not found: ', filename_str);
    WriteLn('  Searched in: ', GetCurrentDir);
    if CurrentScriptDir <> '' then
      WriteLn('  Script dir: ', CurrentScriptDir);
    WriteLn('  Exe dir: ', ExtractFileDir(ParamStr(0)));
    Flush(Output);
    Result := JS_ThrowTypeError(ctx, PChar('QAR file not found: ' + filename_str));
    Exit;
  end;

  qar := qar_open(PChar(found_path));
  if qar = nil then
  begin
    WriteLn('Error: Failed to open QAR file: ', found_path);
    Flush(Output);
    Result := JS_ThrowTypeError(ctx, PChar('Failed to open QAR file'));
    Exit;
  end;

  // Create result object
  obj := JS_NewObject(ctx);
  entry_count := qar_get_entry_count(qar);
  JS_DefinePropertyValueStr(ctx, obj, PChar('entryCount'), JS_NewInt32(ctx, LongInt(entry_count)), JS_PROP_C_W_E);

  // Create entries array
  arr := JS_NewArray(ctx);
  for i := 0 to entry_count - 1 do
  begin
    entry := qar_get_entry(qar, LongInt(i));
    if entry <> nil then
    begin
      item := JS_NewObject(ctx);
      entry_path := qar_entry_get_path(entry);
      entry_type := qar_entry_get_type(entry);

      JS_DefinePropertyValueStr(ctx, item, PChar('path'), JS_NewString(ctx, entry_path), JS_PROP_C_W_E);
      if entry_type = 2 then
        JS_DefinePropertyValueStr(ctx, item, PChar('type'), JS_NewString(ctx, PChar('asset')), JS_PROP_C_W_E)
      else if entry_type <> 0 then
        JS_DefinePropertyValueStr(ctx, item, PChar('type'), JS_NewString(ctx, PChar('module')), JS_PROP_C_W_E)
      else
        JS_DefinePropertyValueStr(ctx, item, PChar('type'), JS_NewString(ctx, PChar('script')), JS_PROP_C_W_E);
      JS_SetPropertyUint32(ctx, arr, LongWord(i), item);
    end;
  end;
  JS_DefinePropertyValueStr(ctx, obj, PChar('entries'), arr, JS_PROP_C_W_E);

  // Get manifest
  manifest_len := 0;
  manifest := qar_get_manifest(qar, @manifest_len);
  if manifest <> nil then
  begin
    JS_DefinePropertyValueStr(ctx, obj, PChar('manifest'), JS_NewStringLen(ctx, manifest, QWord(manifest_len)), JS_PROP_C_W_E);
  end;

  // Get QuickJS version
  version := qar_get_quickjs_version(qar);
  if version <> nil then
  begin
    JS_DefinePropertyValueStr(ctx, obj, PChar('quickjsVersion'), JS_NewString(ctx, version), JS_PROP_C_W_E);
  end;

  qar_close(qar);
  
  // Stringify object để dễ đọc
  stringified := JS_JSONStringify(ctx, obj, JS_UNDEFINED, JS_UNDEFINED);
  if JS_IsException(stringified) = 0 then
  begin
    JS_FreeValue(ctx, obj);
    Result := stringified;
  end
  else
  begin
    // Nếu stringify thất bại, fallback về toString
    JS_FreeValue(ctx, stringified);
    stringified := JS_ToString(ctx, obj);
    JS_FreeValue(ctx, obj);
    if JS_IsException(stringified) = 0 then
      Result := stringified
    else
    begin
      JS_FreeValue(ctx, stringified);
      Result := JS_NewString(ctx, PChar('[object Object]'));
    end;
  end;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:GetQarInfo: ' + E.Message));
  end;
end;

// Helper function to execute QAR entry from JavaScript
function js_execute_qar_entry(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename, entry_path: PChar;
  qar: PQarFile;
  entry: PQarEntryRead;
  entry_type: cint;
  bytecode_len, source_len: csize_t;
  bytecode, source: Pcuint8;
  obj: JSValue;
  eval_flags: cint;
  ok: boolean;
  exc: JSValue;
begin
  try
  if argc < 2 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('ExecuteQarEntry expects 2 arguments: filename and entryPath'));
    Exit;
  end;

  filename := JS_ToCString(ctx, argv[0]);
  if filename = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  entry_path := JS_ToCString(ctx, argv[1]);
  if entry_path = nil then
  begin
    JS_FreeCString(ctx, filename);
    Result := JS_EXCEPTION;
    Exit;
  end;

  qar := qar_open(filename);
  JS_FreeCString(ctx, filename);

  if qar = nil then
  begin
    JS_FreeCString(ctx, entry_path);
    Result := JS_ThrowTypeError(ctx, PChar('Failed to open QAR file'));
    Exit;
  end;

  entry := qar_find_entry(qar, entry_path);
  JS_FreeCString(ctx, entry_path);

  if entry = nil then
  begin
    qar_close(qar);
    Result := JS_ThrowTypeError(ctx, PChar('Entry not found in QAR file'));
    Exit;
  end;

  // Load entry data
  if qar_entry_load_data(qar, entry) < 0 then
  begin
    qar_close(qar);
    Result := JS_ThrowTypeError(ctx, PChar('Failed to load entry data'));
    Exit;
  end;

  entry_type := qar_entry_get_type(entry);

  // Assets: return ArrayBuffer with raw payload (stored in source slot)
  if entry_type = 2 then
  begin
    source := qar_entry_get_source(entry, @source_len);
    if source = nil then
    begin
      qar_close(qar);
      Result := JS_ThrowTypeError(ctx, PChar('Failed to get asset payload'));
      Exit;
    end;
    Result := JS_NewArrayBufferCopy(ctx, source, csize_t(source_len));
    qar_close(qar);
    Exit;
  end;

  bytecode_len := 0;
  bytecode := qar_entry_get_bytecode(entry, @bytecode_len);
  obj := JS_UNDEFINED;
  ok := False;
  if (bytecode <> nil) and (bytecode_len > 0) then
  begin
    eval_flags := JS_READ_OBJ_BYTECODE or JS_READ_OBJ_REFERENCE;
    obj := JS_ReadObject(ctx, bytecode, QWord(bytecode_len), LongInt(eval_flags));
    if JS_IsException(obj) = 0 then
      ok := True
    else
    begin
      if qjs_log.DebugLevel > 0 then
      begin
        WriteLn('[QAR] Bytecode load failed for entry. Rebuilding from source...');
        js_std_dump_error(ctx);
        Flush(Output);
        Flush(StdErr);
      end;
      exc := JS_GetException(ctx);
      JS_FreeValue(ctx, exc);
    end;
  end;

  if not ok then
  begin
    ok := QarRebuildBytecodeFromSource(ctx, entry, 'qar_entry', (entry_type <> 0), obj);
    if not ok then
    begin
      source_len := 0;
      source := qar_entry_get_source(entry, @source_len);
      if (source = nil) or (source_len = 0) then
      begin
        qar_close(qar);
        Result := JS_ThrowTypeError(ctx, PChar('Failed to get bytecode and source'));
        Exit;
      end;
      eval_flags := JS_EVAL_FLAG_COMPILE_ONLY;
      if entry_type <> 0 then
        eval_flags := eval_flags or JS_EVAL_TYPE_MODULE
      else
        eval_flags := eval_flags or JS_EVAL_TYPE_GLOBAL;
      obj := JS_Eval(ctx, PChar(source), QWord(source_len), PChar('qar_entry'), eval_flags);
      if JS_IsException(obj) <> 0 then
      begin
        qar_close(qar);
        Result := obj;
        Exit;
      end;
    end;
  end;

  // Check if it's a module
  if qar_entry_get_type(entry) <> 0 then
  begin
    // It's a module
    if js_module_set_import_meta(ctx, obj, cbool(1), cbool(0)) < 0 then
    begin
      JS_FreeValue(ctx, obj);
      qar_close(qar);
      Result := JS_EXCEPTION;
      Exit;
    end;
    JS_FreeValue(ctx, obj);
    Result := JS_UNDEFINED;
  end
  else
  begin
    // It's a script, evaluate it
    Result := JS_EvalFunction(ctx, obj);
    JS_FreeValue(ctx, obj);
  end;

  qar_close(qar);
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:ExecuteQarEntry: ' + E.Message));
  end;
end;

// Helper function to get asset payload as ArrayBuffer
function js_get_qar_asset(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename, entry_path: PChar;
  qar: PQarFile;
  entry: PQarEntryRead;
  entry_type: cint;
  source_len: csize_t;
  source: Pcuint8;
begin
  try
  if argc < 2 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('GetQarAsset expects 2 arguments: filename and entryPath'));
    Exit;
  end;

  filename := JS_ToCString(ctx, argv[0]);
  if filename = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  entry_path := JS_ToCString(ctx, argv[1]);
  if entry_path = nil then
  begin
    JS_FreeCString(ctx, filename);
    Result := JS_EXCEPTION;
    Exit;
  end;

  qar := qar_open(filename);
  JS_FreeCString(ctx, filename);
  if qar = nil then
  begin
    JS_FreeCString(ctx, entry_path);
    Result := JS_ThrowTypeError(ctx, PChar('Failed to open QAR file'));
    Exit;
  end;

  entry := qar_find_entry(qar, entry_path);
  JS_FreeCString(ctx, entry_path);
  if entry = nil then
  begin
    qar_close(qar);
    Result := JS_ThrowTypeError(ctx, PChar('Entry not found in QAR file'));
    Exit;
  end;

  if qar_entry_load_data(qar, entry) < 0 then
  begin
    qar_close(qar);
    Result := JS_ThrowTypeError(ctx, PChar('Failed to load entry data'));
    Exit;
  end;

  entry_type := qar_entry_get_type(entry);
  if entry_type <> 2 then
  begin
    qar_close(qar);
    Result := JS_ThrowTypeError(ctx, PChar('Entry is not an asset'));
    Exit;
  end;

  source := qar_entry_get_source(entry, @source_len);
  if source = nil then
  begin
    qar_close(qar);
    Result := JS_ThrowTypeError(ctx, PChar('Failed to get asset payload'));
    Exit;
  end;

  Result := JS_NewArrayBufferCopy(ctx, source, csize_t(source_len));
  qar_close(qar);
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:GetQarAsset: ' + E.Message));
  end;
end;

// Helper function to build QAR from JavaScript
function js_build_qar(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  output_file: PChar;
  output_file_str: string;
  input_files: array of string;
  input_count: integer;
  i: integer;
  array_len: cint;
  item: JSValue;
  item_str: PChar;
  ret: cint;
begin
  try
  if argc < 2 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('BuildQar expects 2 arguments: outputFile and inputFiles (string or array)'));
    Exit;
  end;

  // Get output filename
  output_file := JS_ToCString(ctx, argv[0]);
  if output_file = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;
  output_file_str := string(output_file);
  JS_FreeCString(ctx, output_file);

  // Get input files
  input_count := 0;
  SetLength(input_files, 0);

  // Check if second argument is array or string
  // Try to check if it's an array by checking for 'length' property
  // (JS_IsArray might not work correctly with JSValueConst)
  item := JS_GetPropertyStr(ctx, argv[1], 'length');
  if JS_IsNumber(item) <> 0 then
  begin
    // It's likely an array (has numeric length property)
    if JS_ToInt32(ctx, @array_len, item) >= 0 then
    begin
      JS_FreeValue(ctx, item);
      // It's an array
      SetLength(input_files, array_len);
      
      for i := 0 to array_len - 1 do
      begin
        item := JS_GetPropertyStr(ctx, argv[1], PChar(IntToStr(i)));
        if JS_IsString(item) <> 0 then
        begin
          item_str := JS_ToCString(ctx, item);
          if item_str <> nil then
          begin
            input_files[input_count] := string(item_str);
            JS_FreeCString(ctx, item_str);
            Inc(input_count);
          end;
        end
        else
        begin
          // Try to convert to string
          item_str := JS_ToCString(ctx, item);
          if item_str <> nil then
          begin
            input_files[input_count] := string(item_str);
            JS_FreeCString(ctx, item_str);
            Inc(input_count);
          end;
        end;
        JS_FreeValue(ctx, item);
      end;
      
      SetLength(input_files, input_count);
      
      if input_count = 0 then
      begin
        Result := JS_ThrowTypeError(ctx, PChar('BuildQar: Array contains no valid file paths'));
        Exit;
      end;
    end
    else
    begin
      JS_FreeValue(ctx, item);
      // Fall through to check if it's a string
    end;
  end
  else
  begin
    JS_FreeValue(ctx, item);
  end;
  
  // If not processed as array, check if it's a string
  if input_count = 0 then
  begin
    if JS_IsString(argv[1]) <> 0 then
    begin
      // It's a single string
      item_str := JS_ToCString(ctx, argv[1]);
      if item_str <> nil then
      begin
        SetLength(input_files, 1);
        input_files[0] := string(item_str);
        JS_FreeCString(ctx, item_str);
        input_count := 1;
      end;
    end
    else
    begin
      Result := JS_ThrowTypeError(ctx, PChar('BuildQar: inputFiles must be a string or array of strings'));
      Exit;
    end;
  end;

  if input_count = 0 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('BuildQar: No input files specified'));
    Exit;
  end;

  // Build QAR file
  WriteLn('Building QAR file: ', output_file_str);
  WriteLn('Input files:');
  for i := 0 to input_count - 1 do
    WriteLn('  ', input_files[i]);
  
  // JS binding hiện tại không truyền entry_points, giữ behavior cũ
  ret := qar.BuildQar(output_file_str, input_files);
  
  if ret < 0 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('BuildQar: Failed to build QAR file'));
  end
  else
  begin
    Result := JS_NewBool(ctx, 1);
  end;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:BuildQar: ' + E.Message));
  end;
end;

// Custom module loader with fallback path resolution
// Tries multiple path variations to handle QAR files that store only basenames
// NOTE: When multiple QAR files have files with the same basename, use prefixes
//       when registering QAR files to avoid conflicts:
//       LoadLibrary('lib1.qar', 'lib1:')  -> import from 'lib1:math.js'
//       LoadLibrary('lib2.qar', 'lib2:')  -> import from 'lib2:math.js'
function js_module_loader_wrapper(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;
var
  m: PJSModuleDef;
  module_name_str: string;
  basename: string;
  last_slash: integer;
begin
  try
  module_name_str := string(module_name);

  if qjs_log.DebugLevel > 1 then
  begin
    WriteLn('[DEBUG] module_loader: request "', module_name_str, '"');
    Flush(Output);
  end;

  // First try registered QARs (both prefixed and non-prefixed module names)
  m := TryLoadModuleFromRegisteredQars(ctx, module_name_str);
  if m <> nil then
    Exit(m);

  // Then try the standard loader (filesystem + native modules)
  m := js_module_loader(ctx, module_name, opaque);
  if m <> nil then
    Exit(m);
  
  // If not found and module_name doesn't contain ':' (not a prefixed import),
  // try extracting basename (for QAR files that only store filenames)
  // This is a fallback for backward compatibility
  
  // Skip fallback if using prefix notation (e.g., "lib1:math.js")
  if Pos(':', module_name_str) > 0 then
  begin
    Result := nil;
    Exit;
  end;
  

  
  // Last resort: try extracting basename (filename only)
  last_slash := LastDelimiter('/\', module_name_str);
  if last_slash > 0 then
  begin
    basename := Copy(module_name_str, last_slash + 1, Length(module_name_str));
    if qjs_log.DebugLevel > 0 then
      WriteLn('[DEBUG] Trying basename only: "', basename, '"');
    if qjs_log.DebugLevel > 0 then
    begin
      WriteLn('[WARNING] Using basename fallback - if multiple QAR files contain "', basename, '",');
      WriteLn('          the first one found will be used. Consider using prefixes to avoid conflicts.');
      Flush(Output);
    end;
    m := TryLoadModuleFromRegisteredQars(ctx, basename);
    if m <> nil then
      Exit(m);

    m := js_module_loader(ctx, PChar(basename), opaque);
    if m <> nil then
      Exit(m);
  end;
  
  // Not found with any variation
  Result := nil;
  except
    on E: Exception do
    begin
      JS_ThrowReferenceError(ctx, PChar('qar:module_loader: ' + E.Message));
      Result := nil;
    end;
  end;
end;

// Register QAR helper functions to JavaScript global object
procedure RegisterQarHelpers(ctx: PJSContext);
var
  global_obj: JSValue;
begin
  global_obj := JS_GetGlobalObject(ctx);

  // Register LoadLibrary (same as js_std_add_helpers but we add it explicitly)
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('LoadLibrary'),
    JS_NewCFunction(ctx, @js_load_qar_library, PChar('LoadLibrary'), 2), JS_PROP_C_W_E);

  // Register GetQarInfo
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('GetQarInfo'),
    JS_NewCFunction(ctx, @js_get_qar_info, PChar('GetQarInfo'), 1), JS_PROP_C_W_E);

  // Register ExecuteQarEntry
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('ExecuteQarEntry'),
    JS_NewCFunction(ctx, @js_execute_qar_entry, PChar('ExecuteQarEntry'), 2), JS_PROP_C_W_E);

  // Register GetQarAsset
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('GetQarAsset'),
    JS_NewCFunction(ctx, @js_get_qar_asset, PChar('GetQarAsset'), 2), JS_PROP_C_W_E);

  // Register BuildQar
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('BuildQar'),
    JS_NewCFunction(ctx, @js_build_qar, PChar('BuildQar'), 2), JS_PROP_C_W_E);

  JS_FreeValue(ctx, global_obj);
end;

// Example: Load and execute a QAR file
procedure ExampleLoadQar(ctx: PJSContext; qar_filename: string);
var
  ret: cint;
  script: string;
  result_val: JSValue;
begin
  WriteLn('=== Example: Loading QAR file ===');
  WriteLn('Loading QAR file: ', qar_filename);

  // Register QAR file
  ret := RegisterQarFile(qar_filename, '');
  if ret < 0 then
  begin
    WriteLn('Failed to register QAR file');
    Exit;
  end;

  WriteLn('QAR file registered successfully');

  // Example: Execute JavaScript that imports from QAR
  script := 'import * as math from ''./qar_test_lib/math.js''; ' +
            'console.log("Math.add(2, 3) =", math.add(2, 3));';

  result_val := JS_Eval(ctx, PChar(script), QWord(Length(script)), PChar('test.js'), JS_EVAL_TYPE_MODULE);
  if JS_IsException(result_val) <> 0 then
  begin
    WriteLn('Error executing script:');
    js_std_dump_error(ctx);
  end
  else
  begin
    JS_FreeValue(ctx, result_val);
  end;
end;

// Example: Read QAR file info
procedure ExampleReadQarInfo(qar_filename: string);
var
  qar: PQarFile;
  entry_count, i: cint;
  entry: PQarEntryRead;
  entry_path: PChar;
  entry_type: cint;
  manifest: PChar;
  manifest_len: csize_t;
  version: PChar;
begin
  WriteLn('=== Example: Reading QAR file info ===');
  WriteLn('Opening QAR file: ', qar_filename);

  qar := qar_open(PChar(qar_filename));
  if qar = nil then
  begin
    WriteLn('Failed to open QAR file');
    Exit;
  end;

  entry_count := qar_get_entry_count(qar);
  WriteLn('Entry count: ', entry_count);

  for i := 0 to entry_count - 1 do
  begin
    entry := qar_get_entry(qar, LongInt(i));
    if entry <> nil then
    begin
      entry_path := qar_entry_get_path(entry);
      entry_type := qar_entry_get_type(entry);
      if entry_type <> 0 then
        WriteLn('  Entry ', i, ': ', entry_path, ' (module)')
      else
        WriteLn('  Entry ', i, ': ', entry_path, ' (script)');
    end;
  end;

  manifest := qar_get_manifest(qar, @manifest_len);
  if manifest <> nil then
  begin
    WriteLn('Manifest (', manifest_len, ' bytes):');
    WriteLn(Copy(manifest, 1, manifest_len));
  end;

  version := qar_get_quickjs_version(qar);
  if version <> nil then
  begin
    WriteLn('QuickJS version: ', version);
  end;

  qar_close(qar);
end;

// Example: Execute QAR entry directly
procedure ExampleExecuteQarEntry(ctx: PJSContext; qar_filename, entry_path: string);
var
  qar: PQarFile;
  entry: PQarEntryRead;
  bytecode_len: csize_t;
  bytecode: Pcuint8;
  obj: JSValue;
  eval_flags: cint;
begin
  WriteLn('=== Example: Executing QAR entry ===');
  WriteLn('Opening QAR file: ', qar_filename);
  WriteLn('Entry path: ', entry_path);

  qar := qar_open(PChar(qar_filename));
  if qar = nil then
  begin
    WriteLn('Failed to open QAR file');
    Exit;
  end;

  entry := qar_find_entry(qar, PChar(entry_path));
  if entry = nil then
  begin
    WriteLn('Entry not found');
    qar_close(qar);
    Exit;
  end;

  // Load entry data
  if qar_entry_load_data(qar, entry) < 0 then
  begin
    WriteLn('Failed to load entry data');
    qar_close(qar);
    Exit;
  end;

  // Get bytecode
  bytecode := qar_entry_get_bytecode(entry, @bytecode_len);
  if bytecode = nil then
  begin
    WriteLn('Failed to get bytecode');
    qar_close(qar);
    Exit;
  end;

  WriteLn('Bytecode size: ', bytecode_len, ' bytes');

  // Read and execute bytecode
  eval_flags := JS_READ_OBJ_BYTECODE or JS_READ_OBJ_REFERENCE;
  obj := JS_ReadObject(ctx, bytecode, QWord(bytecode_len), LongInt(eval_flags));

  if JS_IsException(obj) <> 0 then
  begin
    WriteLn('Error reading bytecode:');
    js_std_dump_error(ctx);
    qar_close(qar);
    Exit;
  end;

  // Check if it's a module
  if qar_entry_get_type(entry) <> 0 then
  begin
    // It's a module
    WriteLn('Loading as module...');
    if js_module_set_import_meta(ctx, obj, cbool(1), cbool(0)) < 0 then
    begin
      WriteLn('Failed to set import meta');
      JS_FreeValue(ctx, obj);
      qar_close(qar);
      Exit;
    end;
    WriteLn('Module loaded successfully');
    JS_FreeValue(ctx, obj);
  end
  else
  begin
    // It's a script, evaluate it
    WriteLn('Executing as script...');
    obj := JS_EvalFunction(ctx, obj);
    if JS_IsException(obj) <> 0 then
    begin
      WriteLn('Error executing script:');
      js_std_dump_error(ctx);
    end
    else
    begin
      WriteLn('Script executed successfully');
      JS_FreeValue(ctx, obj);
    end;
  end;

  qar_close(qar);
end;

end.

