unit dll_helpers;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ctypes, quickjs_types, quickjs_core, Classes
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

// Dynamic library handle storage for loaded libraries
type
  TDynamicLibraryHandle = record
    handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
    filename: string;
  end;
  PDynamicLibraryHandle = ^TDynamicLibraryHandle;

var
  LoadedDynamicLibraries: TStringList;  // Maps library filename -> TDynamicLibraryHandle

// Helper functions for dynamic library operations
function LoadDynamicLibrary(const filename: string): {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
procedure FreeDynamicLibrary(handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF});
function GetDynamicLibraryProcAddress(handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF}; const proc_name: PChar): Pointer;

// JavaScript bindings for DLL functions
function js_load_dynamic_library(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_get_proc_address(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_call_dll_function(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_free_dynamic_library(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;

// Register DLL helper functions to JavaScript global object
procedure RegisterDllHelpers(ctx: PJSContext);

// Cleanup all loaded dynamic libraries (called on error or exit)
procedure CleanupAllDynamicLibraries;

implementation

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

// Register DLL helper functions to JavaScript global object
procedure RegisterDllHelpers(ctx: PJSContext);
var
  global_obj: JSValue;
begin
  global_obj := JS_GetGlobalObject(ctx);

  // Register dynamic library calling functions (cross-platform)
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('LoadDynamicLibrary'),
    JS_NewCFunction(ctx, @js_load_dynamic_library, PChar('LoadDynamicLibrary'), 1), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('GetProcAddress'),
    JS_NewCFunction(ctx, @js_get_proc_address, PChar('GetProcAddress'), 2), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('CallDllFunction'),
    JS_NewCFunction(ctx, @js_call_dll_function, PChar('CallDllFunction'), 10), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('FreeDynamicLibrary'),
    JS_NewCFunction(ctx, @js_free_dynamic_library, PChar('FreeDynamicLibrary'), 1), JS_PROP_C_W_E);

  JS_FreeValue(ctx, global_obj);
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

end.

