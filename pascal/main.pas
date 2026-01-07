program QuickJSPascal;

{$mode objfpc}{$H+}

uses
  SysUtils, ctypes, quickjs, quickjslibc, qar, Classes
  {$IFDEF WINDOWS}
  , Windows
  {$ELSE}
  {$IFDEF UNIX}
  , dl, Unix
  {$ENDIF}
  {$IFDEF DARWIN}
  , dl
  {$ENDIF}
  {$ENDIF}
  ;

// Type alias for QAR reading functions (from qar unit)
type
  PQarEntryRead = qar.PQarEntry;

// Global variable to store current script directory for LoadLibrary resolution
var
  CurrentScriptDir: string = '';
  // Debug level: 0 = off, 1 = basic, 2 = verbose
  DebugLevel: integer = 0;

// Dynamic library handle storage for loaded libraries
type
  TDynamicLibraryHandle = record
    handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
    filename: string;
  end;
  PDynamicLibraryHandle = ^TDynamicLibraryHandle;

var
  LoadedDynamicLibraries: TStringList;  // Maps library filename -> TDynamicLibraryHandle

// QAR building functions are now in qar.pas unit

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
begin
  // Debug: function được gọi
  WriteLn('[LoadLibrary] Function called with argc=', argc);
  Flush(Output);
  Flush(StdErr);
  
  if argc < 1 then
  begin
    WriteLn('[LoadLibrary] Error: argc < 1');
    Flush(Output);
    Result := JS_ThrowTypeError(ctx, PChar('LoadLibrary expects at least 1 argument'));
    Exit;
  end;

  filename := JS_ToCString(ctx, argv[0]);
  if filename = nil then
  begin
    WriteLn('[LoadLibrary] Error: JS_ToCString returned nil');
    Flush(Output);
    Result := JS_EXCEPTION;
    Exit;
  end;

  filename_str := string(filename);
  JS_FreeCString(ctx, filename);

  prefix := nil;
  if argc >= 2 then
  begin
    prefix := JS_ToCString(ctx, argv[1]);
    if prefix = nil then
    begin
      WriteLn('[LoadLibrary] Error: JS_ToCString for prefix returned nil');
      Flush(Output);
      Result := JS_EXCEPTION;
      Exit;
    end;
  end;

  // Try to find QAR file in multiple locations
  WriteLn('[LoadLibrary] Looking for QAR file: ', filename_str);
  WriteLn('[LoadLibrary] Current working directory: ', GetCurrentDir);
  WriteLn('[LoadLibrary] CurrentScriptDir: ', CurrentScriptDir);
  Flush(Output);
  Flush(StdErr);
  
  found_path := FindQarFile(filename_str);
  
  if found_path = '' then
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
    
    if prefix <> nil then
      JS_FreeCString(ctx, prefix);
    
    Result := JS_ThrowTypeError(ctx, PChar('QAR file not found: ' + filename_str));
    Exit;
  end;
  
  WriteLn('[LoadLibrary] Found QAR file at: ', found_path);
  Flush(Output);

  // Register with found path
  ret := js_register_qar_file(ctx, PChar(found_path), prefix);

  // Log kết quả trước khi free prefix
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

  if prefix <> nil then
    JS_FreeCString(ctx, prefix);

  if ret < 0 then
    Result := JS_ThrowTypeError(ctx, PChar('Failed to register QAR file'))
  else
    Result := JS_UNDEFINED;
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
      if entry_type <> 0 then
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
end;

// Helper function to execute QAR entry from JavaScript
function js_execute_qar_entry(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename, entry_path: PChar;
  qar: PQarFile;
  entry: PQarEntryRead;
  bytecode_len: csize_t;
  bytecode: Pcuint8;
  obj: JSValue;
  eval_flags: cint;
begin
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

  // Get bytecode
  bytecode := qar_entry_get_bytecode(entry, @bytecode_len);
  if bytecode = nil then
  begin
    qar_close(qar);
    Result := JS_ThrowTypeError(ctx, PChar('Failed to get bytecode'));
    Exit;
  end;

  // Read and execute bytecode
  eval_flags := JS_READ_OBJ_BYTECODE or JS_READ_OBJ_REFERENCE;
  obj := JS_ReadObject(ctx, bytecode, QWord(bytecode_len), LongInt(eval_flags));

  if JS_IsException(obj) <> 0 then
  begin
    qar_close(qar);
    Result := obj;
    Exit;
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
  
  ret := qar.BuildQar(output_file_str, input_files);
  
  if ret < 0 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('BuildQar: Failed to build QAR file'));
  end
  else
  begin
    Result := JS_NewBool(ctx, 1);
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
  // First try the exact path (standard behavior - this handles prefixed imports correctly)
  // If module_name starts with a prefix like "lib1:", the standard loader will find it
  m := js_module_loader(ctx, module_name, opaque);
  if m <> nil then
  begin
    Result := m;
    Exit;
  end;
  
  // If not found and module_name doesn't contain ':' (not a prefixed import),
  // try extracting basename (for QAR files that only store filenames)
  // This is a fallback for backward compatibility
  module_name_str := string(module_name);
  
  // Skip fallback if using prefix notation (e.g., "lib1:math.js")
  if Pos(':', module_name_str) > 0 then
  begin
    Result := nil;
    Exit;
  end;
  
  // NOTE: Code below is a workaround for path mismatch issues.
  // It handles specific test paths that may not match QAR entry paths.
  // 
  // WHY THIS EXISTS:
  // - When JS code imports 'qar_test_lib/math.js' but QAR stores 'math.js',
  //   the import fails. This code tries removing the prefix as a fallback.
  // 
  // WHEN TO REMOVE:
  // - If all QAR files are built with correct paths matching import statements,
  //   this code is NOT necessary and can be removed.
  // - This is a temporary workaround, not a permanent solution.
  // - Better solution: Build QAR files with paths that match import statements.
  //
  // Try removing common path prefixes first (more specific)
  // TODO: Consider removing this if QAR files are built with correct paths

//   if Pos('qar_test_lib/', module_name_str) > 0 then
//   begin
//     basename := StringReplace(module_name_str, 'qar_test_lib/', '', []);
//     WriteLn('[DEBUG] Module not found with path "', module_name_str, '", trying without "qar_test_lib/" prefix: "', basename, '"');
//     Flush(Output);
//     m := js_module_loader(ctx, PChar(basename), opaque);
//     if m <> nil then
//     begin
//       Result := m;
//       Exit;
//     end;
//   end;
  
//   if Pos('tests/qar_test_lib/', module_name_str) > 0 then
//   begin
//     basename := StringReplace(module_name_str, 'tests/qar_test_lib/', '', []);
//     WriteLn('[DEBUG] Trying without "tests/qar_test_lib/" prefix: "', basename, '"');
//     Flush(Output);
//     m := js_module_loader(ctx, PChar(basename), opaque);
//     if m <> nil then
//     begin
//       Result := m;
//       Exit;
//     end;
//   end;
  
  // Last resort: try extracting basename (filename only)
  last_slash := LastDelimiter('/\', module_name_str);
  if last_slash > 0 then
  begin
    basename := Copy(module_name_str, last_slash + 1, Length(module_name_str));
    if DebugLevel > 0 then
      WriteLn('[DEBUG] Trying basename only: "', basename, '"');
    WriteLn('[WARNING] Using basename fallback - if multiple QAR files contain "', basename, '",');
    WriteLn('          the first one found will be used. Consider using prefixes to avoid conflicts.');
    Flush(Output);
    m := js_module_loader(ctx, PChar(basename), opaque);
    if m <> nil then
    begin
      Result := m;
      Exit;
    end;
  end;
  
  // Not found with any variation
  Result := nil;
end;

// Dynamic library calling functions (cross-platform)

// Helper function to load dynamic library (cross-platform)
function LoadDynamicLibrary(const filename: string): {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
var
  lib_name: string;
begin
  Result := {$IFDEF WINDOWS}0{$ELSE}nil{$ENDIF};
  
  {$IFDEF WINDOWS}
  Result := Windows.LoadLibrary(PChar(filename));
  {$ELSE}
  {$IFDEF UNIX}
  // On Linux/Unix, try loading with different prefixes if needed
  lib_name := filename;
  if (Pos('.so', lib_name) = 0) and (Pos('.dylib', lib_name) = 0) then
  begin
    // Try adding .so extension
    Result := dlopen(PChar(lib_name + '.so'), RTLD_LAZY);
    if Result = nil then
      Result := dlopen(PChar(lib_name), RTLD_LAZY);
  end
  else
    Result := dlopen(PChar(lib_name), RTLD_LAZY);
  {$ENDIF}
  {$IFDEF DARWIN}
  // On macOS, try .dylib or .so
  lib_name := filename;
  if (Pos('.dylib', lib_name) = 0) and (Pos('.so', lib_name) = 0) then
  begin
    Result := dlopen(PChar(lib_name + '.dylib'), RTLD_LAZY);
    if Result = nil then
      Result := dlopen(PChar(lib_name + '.so'), RTLD_LAZY);
    if Result = nil then
      Result := dlopen(PChar(lib_name), RTLD_LAZY);
  end
  else
    Result := dlopen(PChar(lib_name), RTLD_LAZY);
  {$ENDIF}
  {$ENDIF}
end;

// Helper function to free dynamic library (cross-platform)
procedure FreeDynamicLibrary(handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF});
begin
  {$IFDEF WINDOWS}
  if handle <> 0 then
    Windows.FreeLibrary(handle);
  {$ELSE}
  if handle <> nil then
    dlclose(handle);
  {$ENDIF}
end;

// Helper function to get procedure address (cross-platform)
function GetDynamicLibraryProcAddress(handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF}; const proc_name: PChar): Pointer;
begin
  Result := nil;
  {$IFDEF WINDOWS}
  if handle <> 0 then
    Result := Windows.GetProcAddress(handle, proc_name);
  {$ELSE}
  if handle <> nil then
    Result := dlsym(handle, proc_name);
  {$ENDIF}
end;

// Load dynamic library and return handle (as string identifier)
function js_load_dynamic_library(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  lib_filename: PChar;
  lib_filename_str: string;
  lib_handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
  lib_info: PDynamicLibraryHandle;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('LoadDynamicLibrary expects 1 argument: library_filename'));
    Exit;
  end;

  lib_filename := JS_ToCString(ctx, argv[0]);
  if lib_filename = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  lib_filename_str := string(lib_filename);
  JS_FreeCString(ctx, lib_filename);

  // Check if already loaded
  if LoadedDynamicLibraries.IndexOf(lib_filename_str) >= 0 then
  begin
    Result := JS_NewString(ctx, PChar(lib_filename_str));
    Exit;
  end;

  // Load dynamic library
  lib_handle := LoadDynamicLibrary(lib_filename_str);
  {$IFDEF WINDOWS}
  if lib_handle = 0 then
  {$ELSE}
  if lib_handle = nil then
  {$ENDIF}
  begin
    {$IFDEF WINDOWS}
    Result := JS_ThrowTypeError(ctx, PChar('Failed to load library: ' + lib_filename_str + ' (Error: ' + IntToStr(GetLastError) + ')'));
    {$ELSE}
    Result := JS_ThrowTypeError(ctx, PChar('Failed to load library: ' + lib_filename_str + ' (Error: ' + string(dlerror) + ')'));
    {$ENDIF}
    Exit;
  end;

  // Store handle
  New(lib_info);
  lib_info^.handle := lib_handle;
  lib_info^.filename := lib_filename_str;
  LoadedDynamicLibraries.AddObject(lib_filename_str, TObject(lib_info));

  Result := JS_NewString(ctx, PChar(lib_filename_str));
end;

// Get function address from dynamic library
function js_get_proc_address(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  lib_id, func_name: PChar;
  lib_id_str: string;
  lib_info: PDynamicLibraryHandle;
  proc_addr: pointer;
  proc_addr_int: int64;
begin
  if argc < 2 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('GetProcAddress expects 2 arguments: library_id, function_name'));
    Exit;
  end;

  lib_id := JS_ToCString(ctx, argv[0]);
  if lib_id = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  func_name := JS_ToCString(ctx, argv[1]);
  if func_name = nil then
  begin
    JS_FreeCString(ctx, lib_id);
    Result := JS_EXCEPTION;
    Exit;
  end;

  lib_id_str := string(lib_id);
  JS_FreeCString(ctx, lib_id);

  // Find library handle
  if LoadedDynamicLibraries.IndexOf(lib_id_str) < 0 then
  begin
    JS_FreeCString(ctx, func_name);
    Result := JS_ThrowTypeError(ctx, PChar('Library not loaded: ' + lib_id_str));
    Exit;
  end;

  lib_info := PDynamicLibraryHandle(LoadedDynamicLibraries.Objects[LoadedDynamicLibraries.IndexOf(lib_id_str)]);

  // Get function address
  proc_addr := GetDynamicLibraryProcAddress(lib_info^.handle, func_name);
  JS_FreeCString(ctx, func_name);

  if proc_addr = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Function not found in library: ' + string(func_name)));
    Exit;
  end;

  // Return address as number (can be used for calling)
  proc_addr_int := int64(proc_addr);
  Result := JS_NewInt64(ctx, proc_addr_int);
end;

// Call DLL function (simplified version - supports basic types)
// Usage: CallDllFunction(dll_id, function_name, return_type, [args...])
// return_type: 'i' = int32, 'I' = int64, 'f' = float64, 'v' = void, 's' = string
// args: numbers for int/float, strings for string pointers
function js_call_dll_function(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
type
  TStdCallFunc = function: cint32; stdcall;
  TCdeclFunc = function: cint32; cdecl;
  TStdCallFuncInt = function(arg: cint32): cint32; stdcall;
  TCdeclFuncInt = function(arg: cint32): cint32; cdecl;
  TStdCallFuncFloat0 = function: cdouble; stdcall;
  TCdeclFuncFloat0 = function: cdouble; cdecl;
  TStdCallFuncFloat = function(arg: cdouble): cdouble; stdcall;
  TCdeclFuncFloat = function(arg: cdouble): cdouble; cdecl;
var
  lib_id, func_name, return_type: PChar;
  lib_id_str: string;
  lib_info: PDynamicLibraryHandle;
  proc_addr: pointer;
  i: integer;
  arg_val: JSValue;
  arg_int: cint32;
  arg_float: cdouble;
  result_int: cint32;
  result_float: cdouble;
  stdcall_func: TStdCallFunc;
  cdecl_func: TCdeclFunc;
  stdcall_func_int: TStdCallFuncInt;
  cdecl_func_int: TCdeclFuncInt;
  stdcall_func_float0: TStdCallFuncFloat0;
  cdecl_func_float0: TCdeclFuncFloat0;
  stdcall_func_float: TStdCallFuncFloat;
  cdecl_func_float: TCdeclFuncFloat;
begin
  if argc < 3 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction expects at least 3 arguments: dll_id, function_name, return_type, [args...]'));
    Exit;
  end;

  lib_id := JS_ToCString(ctx, argv[0]);
  if lib_id = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  func_name := JS_ToCString(ctx, argv[1]);
  if func_name = nil then
  begin
    JS_FreeCString(ctx, lib_id);
    Result := JS_EXCEPTION;
    Exit;
  end;

  return_type := JS_ToCString(ctx, argv[2]);
  if return_type = nil then
  begin
    JS_FreeCString(ctx, lib_id);
    JS_FreeCString(ctx, func_name);
    Result := JS_EXCEPTION;
    Exit;
  end;

  lib_id_str := string(lib_id);
  JS_FreeCString(ctx, lib_id);

  // Find library handle
  if LoadedDynamicLibraries.IndexOf(lib_id_str) < 0 then
  begin
    JS_FreeCString(ctx, func_name);
    JS_FreeCString(ctx, return_type);
    Result := JS_ThrowTypeError(ctx, PChar('Library not loaded: ' + lib_id_str));
    Exit;
  end;

  lib_info := PDynamicLibraryHandle(LoadedDynamicLibraries.Objects[LoadedDynamicLibraries.IndexOf(lib_id_str)]);

  // Get function address
  proc_addr := GetDynamicLibraryProcAddress(lib_info^.handle, func_name);
  JS_FreeCString(ctx, func_name);

  if proc_addr = nil then
  begin
    JS_FreeCString(ctx, return_type);
    Result := JS_ThrowTypeError(ctx, PChar('Function not found in DLL'));
    Exit;
  end;

  // Simple implementation: support functions with 0 or 1 argument
  // For more complex cases, users can use GetProcAddress and call manually
  try
    // PChar is 0-indexed (C string), so use [0] to get first character
    case return_type[0] of
      'i', 'I': // int32 or int64
      begin
        if argc = 3 then
        begin
          // No arguments
          stdcall_func := TStdCallFunc(proc_addr);
          result_int := stdcall_func();
          JS_FreeCString(ctx, return_type);
          Result := JS_NewInt32(ctx, result_int);
        end
        else if argc = 4 then
        begin
          // One int argument
          if JS_ToInt32(ctx, @arg_int, argv[3]) < 0 then
          begin
            JS_FreeCString(ctx, return_type);
            Result := JS_ThrowTypeError(ctx, PChar('Invalid argument type (expected integer)'));
            Exit;
          end;
          stdcall_func_int := TStdCallFuncInt(proc_addr);
          result_int := stdcall_func_int(arg_int);
          JS_FreeCString(ctx, return_type);
          Result := JS_NewInt32(ctx, result_int);
        end
        else
        begin
          JS_FreeCString(ctx, return_type);
          Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Only 0 or 1 argument supported in this version'));
        end;
      end;
      'f': // float64
      begin
        if argc = 3 then
        begin
          // No arguments
          stdcall_func_float0 := TStdCallFuncFloat0(proc_addr);
          result_float := stdcall_func_float0();
          JS_FreeCString(ctx, return_type);
          Result := JS_NewFloat64(ctx, result_float);
        end
        else if argc = 4 then
        begin
          // One float argument
          if JS_ToFloat64(ctx, @arg_float, argv[3]) < 0 then
          begin
            JS_FreeCString(ctx, return_type);
            Result := JS_ThrowTypeError(ctx, PChar('Invalid argument type (expected number)'));
            Exit;
          end;
          stdcall_func_float := TStdCallFuncFloat(proc_addr);
          result_float := stdcall_func_float(arg_float);
          JS_FreeCString(ctx, return_type);
          Result := JS_NewFloat64(ctx, result_float);
        end
        else
        begin
          JS_FreeCString(ctx, return_type);
          Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Only 0 or 1 argument supported in this version'));
        end;
      end;
      'v': // void
      begin
        if argc = 3 then
        begin
          // No arguments, no return
          stdcall_func := TStdCallFunc(proc_addr);
          stdcall_func();
          JS_FreeCString(ctx, return_type);
          Result := JS_UNDEFINED;
        end
        else
        begin
          JS_FreeCString(ctx, return_type);
          Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Void functions with arguments not yet supported'));
        end;
      end;
      else
      begin
        JS_FreeCString(ctx, return_type);
        Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type. Use: i/I (int), f (float), v (void)'));
      end;
    end;
  except
    JS_FreeCString(ctx, return_type);
    Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Exception occurred while calling DLL function'));
  end;
end;

// Free dynamic library
function js_free_dynamic_library(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  lib_id: PChar;
  lib_id_str: string;
  lib_info: PDynamicLibraryHandle;
  idx: integer;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('FreeDynamicLibrary expects 1 argument: library_id'));
    Exit;
  end;

  lib_id := JS_ToCString(ctx, argv[0]);
  if lib_id = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  lib_id_str := string(lib_id);
  JS_FreeCString(ctx, lib_id);

  idx := LoadedDynamicLibraries.IndexOf(lib_id_str);
  if idx < 0 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Library not loaded: ' + lib_id_str));
    Exit;
  end;

  lib_info := PDynamicLibraryHandle(LoadedDynamicLibraries.Objects[idx]);
  FreeDynamicLibrary(lib_info^.handle);
  Dispose(lib_info);
  LoadedDynamicLibraries.Delete(idx);

  Result := JS_UNDEFINED;
end;

// Cleanup all loaded dynamic libraries (called on error or exit)
procedure CleanupAllDynamicLibraries;
var
  i: integer;
  lib_info: PDynamicLibraryHandle;
begin
  if LoadedDynamicLibraries = nil then
    Exit;
    
  for i := LoadedDynamicLibraries.Count - 1 downto 0 do
  begin
    if LoadedDynamicLibraries.Objects[i] <> nil then
    begin
      lib_info := PDynamicLibraryHandle(LoadedDynamicLibraries.Objects[i]);
      FreeDynamicLibrary(lib_info^.handle);
      Dispose(lib_info);
    end;
    LoadedDynamicLibraries.Delete(i);
  end;
end;

// Forward declarations for compression functions
function js_compress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl; forward;
function js_uncompress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl; forward;
function js_compressBound(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl; forward;

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

  // Register BuildQar
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('BuildQar'),
    JS_NewCFunction(ctx, @js_build_qar, PChar('BuildQar'), 2), JS_PROP_C_W_E);

  // Register dynamic library calling functions (cross-platform)
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('LoadDynamicLibrary'),
    JS_NewCFunction(ctx, @js_load_dynamic_library, PChar('LoadDynamicLibrary'), 1), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('GetProcAddress'),
    JS_NewCFunction(ctx, @js_get_proc_address, PChar('GetProcAddress'), 2), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('CallDllFunction'),
    JS_NewCFunction(ctx, @js_call_dll_function, PChar('CallDllFunction'), 10), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('FreeDynamicLibrary'),
    JS_NewCFunction(ctx, @js_free_dynamic_library, PChar('FreeDynamicLibrary'), 1), JS_PROP_C_W_E);

  // Register compression functions
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('compress'),
    JS_NewCFunction(ctx, @js_compress, PChar('compress'), 2), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('uncompress'),
    JS_NewCFunction(ctx, @js_uncompress, PChar('uncompress'), 2), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('compressBound'),
    JS_NewCFunction(ctx, @js_compressBound, PChar('compressBound'), 1), JS_PROP_C_W_E);

  JS_FreeValue(ctx, global_obj);
  
  if DebugLevel > 1 then
    WriteLn('[DEBUG] Compression functions registered: compress, uncompress, compressBound');
end;

// Compression functions exposed to JavaScript

// Compress data: compress(data: ArrayBuffer|Uint8Array, level?: number): ArrayBuffer
function js_compress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  input_buf: Pcuint8;
  input_size: csize_t;
  output_buf: Pcuint8;
  output_size: mz_ulong;
  level: cint;
  ret: cint;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('compress expects at least 1 argument: data'));
    Exit;
  end;

  // Get input buffer - support both ArrayBuffer and Uint8Array
  if JS_IsArrayBuffer(argv[0]) <> 0 then
  begin
    input_buf := JS_GetArrayBuffer(ctx, @input_size, argv[0]);
    if input_buf = nil then
    begin
      Result := JS_EXCEPTION;
      Exit;
    end;
  end
  else
  begin
    // Try to get as Uint8Array
    input_buf := JS_GetUint8Array(ctx, @input_size, argv[0]);
    if input_buf = nil then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('compress expects ArrayBuffer or Uint8Array'));
      Exit;
    end;
  end;

  // Get compression level (optional, default to MZ_DEFAULT_LEVEL)
  level := MZ_DEFAULT_LEVEL;
  if argc >= 2 then
  begin
    if JS_ToInt32(ctx, @level, argv[1]) < 0 then
    begin
      Result := JS_EXCEPTION;
      Exit;
    end;
    // Clamp level to valid range (0-9)
    if level < 0 then level := 0;
    if level > 9 then level := 9;
  end;

  // Calculate output buffer size
  output_size := mz_compressBound(mz_ulong(input_size));
  output_buf := GetMem(output_size);
  if output_buf = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('compress: out of memory'));
    Exit;
  end;

  // Compress
  ret := mz_compress2(output_buf, @output_size, input_buf, mz_ulong(input_size), level);
  if ret <> MZ_OK then
  begin
    FreeMem(output_buf);
    Result := JS_ThrowTypeError(ctx, PChar('compress: compression failed'));
    Exit;
  end;

  // Create ArrayBuffer with compressed data
  Result := JS_NewArrayBufferCopy(ctx, output_buf, csize_t(output_size));
  FreeMem(output_buf);
end;

// Uncompress data: uncompress(data: ArrayBuffer|Uint8Array, uncompressed_size?: number): ArrayBuffer
function js_uncompress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  input_buf: Pcuint8;
  input_size: csize_t;
  output_buf: Pcuint8;
  output_size: mz_ulong;
  uncompressed_size: cint64;
  ret: cint;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('uncompress expects at least 1 argument: data'));
    Exit;
  end;

  // Get input buffer - support both ArrayBuffer and Uint8Array
  if JS_IsArrayBuffer(argv[0]) <> 0 then
  begin
    input_buf := JS_GetArrayBuffer(ctx, @input_size, argv[0]);
    if input_buf = nil then
    begin
      Result := JS_EXCEPTION;
      Exit;
    end;
  end
  else
  begin
    // Try to get as Uint8Array
    input_buf := JS_GetUint8Array(ctx, @input_size, argv[0]);
    if input_buf = nil then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('uncompress expects ArrayBuffer or Uint8Array'));
      Exit;
    end;
  end;

  // Get uncompressed size (optional, but recommended for efficiency)
  if argc >= 2 then
  begin
    if JS_ToInt64(ctx, @uncompressed_size, argv[1]) < 0 then
    begin
      Result := JS_EXCEPTION;
      Exit;
    end;
    output_size := mz_ulong(uncompressed_size);
  end
  else
  begin
    // Estimate: compressed data is usually smaller, so start with input_size * 2
    // This is a heuristic and may need adjustment
    output_size := mz_ulong(input_size) * 2;
  end;

  // Allocate output buffer
  output_buf := GetMem(output_size);
  if output_buf = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('uncompress: out of memory'));
    Exit;
  end;

  // Uncompress
  ret := mz_uncompress(output_buf, @output_size, input_buf, mz_ulong(input_size));
  if ret <> MZ_OK then
  begin
    FreeMem(output_buf);
    // Try with larger buffer if size was not provided
    if argc < 2 then
    begin
      output_size := mz_ulong(input_size) * 4;
      output_buf := GetMem(output_size);
      if output_buf <> nil then
      begin
        ret := mz_uncompress(output_buf, @output_size, input_buf, mz_ulong(input_size));
        if ret = MZ_OK then
        begin
          Result := JS_NewArrayBufferCopy(ctx, output_buf, csize_t(output_size));
          FreeMem(output_buf);
          Exit;
        end;
        FreeMem(output_buf);
      end;
    end;
    Result := JS_ThrowTypeError(ctx, PChar('uncompress: decompression failed'));
    Exit;
  end;

  // Create ArrayBuffer with uncompressed data
  Result := JS_NewArrayBufferCopy(ctx, output_buf, csize_t(output_size));
  FreeMem(output_buf);
end;

// Get compression bound: compressBound(source_size: number): number
function js_compressBound(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  source_size: cint64;
  bound: mz_ulong;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('compressBound expects 1 argument: source_size'));
    Exit;
  end;

  if JS_ToInt64(ctx, @source_size, argv[0]) < 0 then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  if source_size < 0 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('compressBound: source_size must be non-negative'));
    Exit;
  end;

  bound := mz_compressBound(mz_ulong(source_size));
  Result := JS_NewInt64(ctx, cint64(bound));
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
  ret := js_register_qar_file(ctx, PChar(qar_filename), nil);
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
    if DebugLevel > 0 then
      WriteLn('[DEBUG] File not found: ', filename, ' (tried: ', script_path, ')');
    Exit;
  end;
  
  if DebugLevel > 0 then
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
    if DebugLevel > 1 then
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

// QAR building functions are now in qar.pas unit

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

// Main program
var
  rt: PJSRuntime;
  ctx: PJSContext;
  script: string;
  result_val: JSValue;
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
  // For QAR debugging
  qar_debug: PQarFile;
  entry_count_debug, i_debug: cint;
  entry_debug: PQarEntryRead;
  entry_path_debug: PChar;
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
begin
  // Check for build QAR mode
  build_mode := False;
  output_file := '';
  input_count := 0;
  SetLength(input_files, 0);
  
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
        DebugLevel := 1; // Default to level 1 if no value provided
      end
      else
      begin
        try
          DebugLevel := StrToInt(ParamStr(i));
          if (DebugLevel < 0) or (DebugLevel > 2) then
          begin
            WriteLn('Warning: Debug level must be 0-2, using 1');
            DebugLevel := 1;
          end;
        except
          WriteLn('Warning: Invalid debug level, using 1');
          DebugLevel := 1;
        end;
      end;
    end
    else if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
    begin
      WriteLn('QuickJS Pascal Demo');
      WriteLn('==================');
      WriteLn;
      WriteLn('Usage:');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' [options] [files...]');
      WriteLn;
      WriteLn('Options:');
      WriteLn('  -o, --output FILE    Build QAR file from JavaScript files/directories');
      WriteLn('  -b, --build-qar      Build QAR file (same as -o)');
      WriteLn('  -d, --debug [LEVEL]  Enable debug output (0=off, 1=basic, 2=verbose, default=1)');
      WriteLn('  -h, --help           Show this help');
      WriteLn;
      WriteLn('Examples:');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -o mylib.qar math.js utils.js');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -o mylib.qar src/');
      WriteLn('  ', ExtractFileName(ParamStr(0)), ' -d 2              (interactive mode with verbose debug)');
      WriteLn('  ', ExtractFileName(ParamStr(0)), '                    (interactive mode)');
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
    if qar.BuildQar(output_file, input_files) < 0 then
      Halt(1)
    else
      Halt(0);
  end;
  
  WriteLn('QuickJS Pascal Demo');
  WriteLn('==================');
  WriteLn;

  // Initialize dynamic library handle storage
  LoadedDynamicLibraries := TStringList.Create;
  LoadedDynamicLibraries.Sorted := False;

  // Initialize QuickJS runtime
  rt := JS_NewRuntime;
  if rt = nil then
  begin
    WriteLn('Failed to create JS runtime');
    Halt(1);
  end;

  // Set memory limit (64 MB)
  JS_SetMemoryLimit(rt, 64 * 1024 * 1024);

  // Create context
  ctx := JS_NewContext(rt);
  if ctx = nil then
  begin
    WriteLn('Failed to create JS context');
    JS_FreeRuntime(rt);
    Halt(1);
  end;

  // Initialize standard handlers
  js_std_init_handlers(rt);

  // Set up module loader (required for QAR module resolution)
  JS_SetModuleLoaderFunc(rt, nil, @js_module_loader_wrapper, nil);

  // Add standard helpers (console, print, etc.)
  js_std_add_helpers(ctx, 0, nil);

  // Register QAR helper functions
  RegisterQarHelpers(ctx);

  WriteLn('QuickJS version: ', JS_GetVersion);
  if DebugLevel > 0 then
    WriteLn('Debug level: ', DebugLevel);
  WriteLn;

  // Example 1: Basic JavaScript execution
  WriteLn('=== Example 1: Basic JavaScript execution ===');
  if LoadAndExecuteJSFile(ctx, 'tests/example1_basic.js') then
  begin
    if DebugLevel > 0 then
      WriteLn('[DEBUG] Example 1 completed successfully');
  end
  else
  begin
    WriteLn('Warning: Could not load tests/example1_basic.js');
  end;
  WriteLn;

  // Example 2: Read QAR file info (if file exists)
  if FileExists('qar_test.qar') then
  begin
    WriteLn('=== Example 2: QAR file info ===');
    ExampleReadQarInfo('qar_test.qar');
    WriteLn;
  end
  else
  begin
    WriteLn('=== Example 2: QAR file info ===');
    if LoadAndExecuteJSFile(ctx, 'tests/example2_qar_info.js') then
    begin
      if DebugLevel > 0 then
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

  // Example 3: Use QAR from JavaScript
  WriteLn('=== Example 3: Using QAR from JavaScript ===');
  if LoadAndExecuteJSFile(ctx, 'tests/example3_qar_usage.js') then
  begin
    if DebugLevel > 0 then
      WriteLn('[DEBUG] Example 3 completed successfully');
  end
  else
  begin
    WriteLn('Warning: Could not load tests/example3_qar_usage.js');
  end;
  WriteLn;

  // Example 4: Dynamic library function calls
  WriteLn('=== Example 4: Dynamic Library Function Calls ===');
  if LoadAndExecuteJSFile(ctx, 'tests/example4_dll_test.js') then
  begin
    if DebugLevel > 0 then
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

  // Example 5: Interactive mode (optional)
  WriteLn('=== Example 5: Interactive JavaScript ===');
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
      {$IFDEF WINDOWS}
      WriteLn('        lib_id = LoadDynamicLibrary("mylib.dll")');
      {$ELSE}
      {$IFDEF UNIX}
      WriteLn('        lib_id = LoadDynamicLibrary("mylib.so")');
      {$ENDIF}
      {$IFDEF DARWIN}
      WriteLn('        lib_id = LoadDynamicLibrary("mylib.dylib")');
      {$ENDIF}
      {$ENDIF}
      WriteLn('        result = CallDllFunction(lib_id, "MyFunction", "i", 42)');
      WriteLn('        FreeDynamicLibrary(lib_id)');
  WriteLn;

  // Simple interactive loop
  while True do
  begin
    Write('js> ');
    ReadLn(script);
    if (script = 'exit') or (script = 'quit') then
      Break;

    if script <> '' then
    begin
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
              CurrentScriptDir := script_dir;
              
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
              if DebugLevel > 1 then
              begin
                WriteLn('[DEBUG] Before executing script:');
                WriteLn('  Current working directory: ', GetCurrentDir);
                WriteLn('  Script directory: ', script_dir);
                WriteLn('  CurrentScriptDir: ', CurrentScriptDir);
                Flush(Output);
              end;
              
              // Force GLOBAL script for .load command to ensure immediate execution
              // (unless file explicitly uses import/export)
              eval_flags := JS_EVAL_TYPE_GLOBAL;
              if (Pos('import ', file_content) > 0) or (Pos('export ', file_content) > 0) then
              begin
                eval_flags := JS_EVAL_TYPE_MODULE;
                if DebugLevel > 0 then
                  WriteLn('[DEBUG] Detected as MODULE (has import/export) - imports will be resolved before top-level code');
              end
              else if JS_DetectModule(PChar(file_content), QWord(Length(file_content))) <> 0 then
              begin
                // Only use module mode if explicitly detected AND has import/export
                eval_flags := JS_EVAL_TYPE_GLOBAL;  // Force global for immediate execution
                if DebugLevel > 1 then
                  WriteLn('[DEBUG] File detected as module but no import/export found, using GLOBAL mode for immediate execution');
              end
              else
              begin
                if DebugLevel > 1 then
                  WriteLn('[DEBUG] Detected as GLOBAL script');
                
                // Pre-register QAR files in script directory to avoid import resolution issues
                // QuickJS resolves imports before executing top-level code, so LoadLibrary
                // calls may happen too late. Pre-register common QAR files.
                if script_dir <> '' then
                begin
                  test_path := IncludeTrailingPathDelimiter(script_dir) + 'qar_test.qar';
                  if FileExists(test_path) then
                  begin
                    if DebugLevel > 0 then
                      WriteLn('[DEBUG] Pre-registering QAR file found in script directory: ', test_path);
                    ret := js_register_qar_file(ctx, PChar(test_path), nil);
                    if ret < 0 then
                    begin
                      if DebugLevel > 0 then
                        WriteLn('[DEBUG] Warning: Failed to pre-register QAR file');
                    end
                    else
                    begin
                      if DebugLevel > 0 then
                        WriteLn('[DEBUG] Successfully pre-registered QAR file');
                      // Debug: List all entries in QAR file to see actual paths
                      if DebugLevel > 1 then
                      begin
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
                    end;
                    Flush(Output);
                  end;
                  
                  // Also try to find QAR files mentioned in LoadLibrary calls
                  if Pos('LoadLibrary', file_content) > 0 then
                  begin
                    if DebugLevel > 0 then
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
                // For modules, we need to execute pending jobs to run top-level code
                if eval_flags = JS_EVAL_TYPE_MODULE then
                begin
                  // Execute pending jobs (module initialization)
                  while JS_ExecutePendingJob(JS_GetRuntime(ctx), @ctx) > 0 do
                  begin
                    // Continue executing jobs until done
                  end;
                end;
                // Flush output to ensure all console.log output is displayed
                Flush(Output);
                WriteLn('File loaded successfully');
                JS_FreeValue(ctx, result_val);
                // Flush again after execution
                Flush(Output);
              end;
              
              // Clear script directory after loading
              CurrentScriptDir := '';
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
      
      // Tự động chọn GLOBAL hay MODULE dựa trên nội dung script
      eval_flags := JS_EVAL_TYPE_GLOBAL;
      if JS_DetectModule(PChar(script), QWord(Length(script))) <> 0 then
        eval_flags := JS_EVAL_TYPE_MODULE;

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
        if DebugLevel > 1 then
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
              WriteLn(result_str);
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
                WriteLn(result_str);
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
                WriteLn(result_str);
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
                WriteLn(result_str);
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

  // Cleanup
  js_std_free_handlers(rt);
  JS_FreeContext(ctx);
  JS_FreeRuntime(rt);

  // Free all loaded dynamic libraries
  CleanupAllDynamicLibraries;
  if LoadedDynamicLibraries <> nil then
    LoadedDynamicLibraries.Free;

  WriteLn;
  WriteLn('Goodbye!');
end.

