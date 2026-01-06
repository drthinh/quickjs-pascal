program QuickJSPascal;

{$mode objfpc}{$H+}

uses
  SysUtils, ctypes, quickjs, quickjslibc, qar;

// Helper function to register QAR from JavaScript
function js_load_qar_library(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename, prefix: PChar;
  ret: cint;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('LoadLibrary expects at least 1 argument'));
    Exit;
  end;

  filename := JS_ToCString(ctx, argv[0]);
  if filename = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  prefix := nil;
  if argc >= 2 then
  begin
    prefix := JS_ToCString(ctx, argv[1]);
    if prefix = nil then
    begin
      JS_FreeCString(ctx, filename);
      Result := JS_EXCEPTION;
      Exit;
    end;
  end;

  ret := js_register_qar_file(ctx, filename, prefix);

  // Log kết quả trước khi free
  if ret < 0 then
  begin
    WriteLn('Error: Failed to register QAR file: ', filename);
    Flush(Output);
  end
  else
  begin
    WriteLn('Successfully registered QAR file: ', filename);
    Flush(Output);
  end;

  JS_FreeCString(ctx, filename);
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
  qar: PQarFile;
  entry_count: cint;
  i: cint;
  entry: PQarEntry;
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

  qar := qar_open(filename);
  JS_FreeCString(ctx, filename);

  if qar = nil then
  begin
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
  entry: PQarEntry;
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

// Example: Read QAR file info
procedure ExampleReadQarInfo(qar_filename: string);
var
  qar: PQarFile;
  entry_count, i: cint;
  entry: PQarEntry;
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
  entry: PQarEntry;
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
begin
  WriteLn('QuickJS Pascal Demo');
  WriteLn('==================');
  WriteLn;

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

  // Add standard helpers (console, print, etc.)
  js_std_add_helpers(ctx, 0, nil);

  // Register QAR helper functions
  RegisterQarHelpers(ctx);

  WriteLn('QuickJS version: ', JS_GetVersion);
  WriteLn;

  // Example 1: Basic JavaScript execution
  WriteLn('=== Example 1: Basic JavaScript execution ===');
  script := 'console.log("Hello from QuickJS!"); ' +
            'console.log("2 + 3 =", 2 + 3);';
  result_val := JS_Eval(ctx, PChar(script), QWord(Length(script)), PChar('test.js'), JS_EVAL_TYPE_GLOBAL);
  if JS_IsException(result_val) <> 0 then
  begin
    WriteLn('Error:');
    js_std_dump_error(ctx);
  end
  else
  begin
    JS_FreeValue(ctx, result_val);
  end;
  WriteLn;

  // Example 2: Read QAR file info (if file exists)
  if FileExists('qar_test.qar') then
  begin
    ExampleReadQarInfo('qar_test.qar');
    WriteLn;
  end
  else
  begin
    WriteLn('=== Example 2: QAR file info ===');
    WriteLn('QAR file "qar_test.qar" not found. Skipping QAR examples.');
    WriteLn('To test QAR functionality, create a QAR file first using:');
    WriteLn('  qjar -o qar_test.qar your_js_file.js');
    WriteLn;
  end;

  // Example 3: Use QAR from JavaScript
  WriteLn('=== Example 3: Using QAR from JavaScript ===');
  script := 'if (typeof LoadLibrary !== "undefined") { ' +
            '  console.log("LoadLibrary function is available"); ' +
            '  console.log("You can use: LoadLibrary(''qar_test.qar'')"); ' +
            '} else { ' +
            '  console.log("LoadLibrary not available"); ' +
            '}';
  result_val := JS_Eval(ctx, PChar(script), QWord(Length(script)), PChar('math.js'), JS_EVAL_TYPE_GLOBAL);
  if JS_IsException(result_val) <> 0 then
  begin
    js_std_dump_error(ctx);
  end
  else
  begin
    JS_FreeValue(ctx, result_val);
  end;
  WriteLn;

  // Example 4: Interactive mode (optional)
  WriteLn('=== Example 4: Interactive JavaScript ===');
  WriteLn('Type JavaScript code (or "exit" to quit):');
  WriteLn('Note: To use QAR modules, first run: LoadLibrary("qar_test.qar")');
  WriteLn('      Then check entries with: GetQarInfo("qar_test.qar")');
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
      // Tự động chọn GLOBAL hay MODULE dựa trên nội dung script
      eval_flags := JS_EVAL_TYPE_GLOBAL;
      if JS_DetectModule(PChar(script), QWord(Length(script))) <> 0 then
        eval_flags := JS_EVAL_TYPE_MODULE;

      // Nếu code có "await" ở đầu dòng (top-level await), thêm cờ ASYNC
      // (chỉ áp dụng cho GLOBAL mode, MODULE mode đã hỗ trợ top-level await mặc định)
      if (eval_flags = JS_EVAL_TYPE_GLOBAL) and (Pos('await', LowerCase(script)) > 0) then
        eval_flags := eval_flags or JS_EVAL_FLAG_ASYNC;

      // Với GLOBAL mode, wrap expression để lấy kết quả (nếu không phải statement)
      // QuickJS REPL thường wrap expression trong (expression) để lấy giá trị
      // Chỉ wrap nếu không phải statement (không có ; ở cuối và không phải declaration)
      if (eval_flags = JS_EVAL_TYPE_GLOBAL) and 
         (Pos(';', script) = 0) and 
         (Pos('=', script) = 0) and
         (Pos('function', LowerCase(script)) = 0) and
         (Pos('class', LowerCase(script)) = 0) and
         (Pos('const ', LowerCase(script)) = 0) and
         (Pos('let ', LowerCase(script)) = 0) and
         (Pos('var ', LowerCase(script)) = 0) and
         (Pos('return', LowerCase(script)) = 0) then
      begin
        // Wrap expression trong parentheses để lấy giá trị
        // Điều này cho phép function calls và các expression khác trả về giá trị
        script := '(' + script + ')';
      end;

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
        // Trong QuickJS, với JS_EVAL_TYPE_GLOBAL, expression có thể trả về undefined
        // Kiểm tra tag để xác định chính xác
        // Debug: kiểm tra giá trị trả về
        if result_val.tag = JS_TAG_UNDEFINED then
        begin
          WriteLn('[DEBUG] Result is undefined (tag=', result_val.tag, ')');
          Flush(Output);
        end
        else
        begin
          WriteLn('[DEBUG] Result tag=', result_val.tag, ', IsString=', JS_IsString(result_val), ', IsObject=', JS_IsObject(result_val));
          Flush(Output);
        end;
        
        if result_val.tag <> JS_TAG_UNDEFINED then
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

  WriteLn;
  WriteLn('Goodbye!');
end.

