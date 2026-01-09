unit dll_helpers;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ctypes, quickjs_types, quickjs_core, Classes, qar_helpers
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
function LoadDLL(const filename: string): {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
procedure FreeDLL(handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF});
function GetDynamicLibraryProcAddress(handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF}; const proc_name: PChar): Pointer;

// JavaScript bindings for DLL functions
function js_load_dll(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_load_library_auto(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_get_proc_address(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_call_dll_function(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_free_dll(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;

// Register DLL helper functions to JavaScript global object
procedure RegisterDllHelpers(ctx: PJSContext);

// Cleanup all loaded dynamic libraries (called on error or exit)
procedure CleanupAllDynamicLibraries;

implementation

// Helper function to load dynamic library (cross-platform)
function LoadDLL(const filename: string): {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
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
procedure FreeDLL(handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF});
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
function js_load_dll(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  lib_filename: PChar;
  lib_filename_str: string;
  lib_handle: {$IFDEF WINDOWS}THandle{$ELSE}Pointer{$ENDIF};
  lib_info: PDynamicLibraryHandle;
begin
  try
    if argc < 1 then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('LoadDLL expects 1 argument: library_filename'));
      Exit;
    end;

    if LoadedDynamicLibraries = nil then
      LoadedDynamicLibraries := TStringList.Create;

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
    lib_handle := LoadDLL(lib_filename_str);
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
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:dll:LoadDLL: ' + E.Message));
  end;
end;

function js_load_library_auto(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename: PChar;
  filename_str, ext, candidate: string;
  tmp_argv: array[0..1] of JSValueConst;
  res: JSValue;
  has_prefix: boolean;
  i: integer;
  candidates: array of string;
begin
  try
    if argc < 1 then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('LoadLib expects at least 1 argument: filename (.qar/.dll/.so/.dylib)'));
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

    has_prefix := argc >= 2;
    ext := LowerCase(ExtractFileExt(filename_str));

  // Build candidate list (try given name first, then inferred extensions when missing)
  SetLength(candidates, 0);
  if ext <> '' then
  begin
    SetLength(candidates, Length(candidates) + 1);
    candidates[High(candidates)] := filename_str;
  end
  else
  begin
    // No extension: try .qar first, then platform native libs
    SetLength(candidates, Length(candidates) + 1);
    candidates[High(candidates)] := filename_str + '.qar';
    {$IFDEF WINDOWS}
    SetLength(candidates, Length(candidates) + 1);
    candidates[High(candidates)] := filename_str + '.dll';
    {$ELSE}
    SetLength(candidates, Length(candidates) + 1);
    candidates[High(candidates)] := filename_str + '.so';
    {$IFDEF DARWIN}
    SetLength(candidates, Length(candidates) + 1);
    candidates[High(candidates)] := filename_str + '.dylib';
    {$ENDIF}
    {$ENDIF}
  end;

  for i := 0 to High(candidates) do
  begin
    candidate := candidates[i];
    ext := LowerCase(ExtractFileExt(candidate));

    // Try QAR
    if ext = '.qar' then
    begin
      tmp_argv[0] := JS_NewString(ctx, PChar(candidate));
      if has_prefix then
        tmp_argv[1] := argv[1];
      res := js_load_qar_library(ctx, this_val, 1 + cint(ord(has_prefix)), @tmp_argv[0]);
      JS_FreeValue(ctx, tmp_argv[0]);
      if JS_IsException(res) = 0 then
      begin
        Result := res;
        Exit;
      end
      else
      begin
        JS_FreeValue(ctx, res);
        // Clear pending exception so we can try the next candidate without leaking the error state
        JS_FreeValue(ctx, JS_GetException(ctx));
      end;
    end
    else if (ext = '.dll') or (ext = '.so') or (ext = '.dylib') then
    begin
      tmp_argv[0] := JS_NewString(ctx, PChar(candidate));
      res := js_load_dll(ctx, this_val, 1, @tmp_argv[0]);
      JS_FreeValue(ctx, tmp_argv[0]);
      if JS_IsException(res) = 0 then
      begin
        Result := res;
        Exit;
      end
      else
      begin
        JS_FreeValue(ctx, res);
        // Clear pending exception so we can try the next candidate without leaking the error state
        JS_FreeValue(ctx, JS_GetException(ctx));
      end;
    end;
  end;

  // Fallback: if original had known extension but failed, return last error
    Result := JS_ThrowTypeError(ctx, PChar('LoadLib: failed to load as QAR or dynamic library: ' + filename_str));
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:dll:LoadLib: ' + E.Message));
  end;
end;

// Get function address from dynamic library
function js_get_proc_address(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  lib_id, func_name: PChar;
  lib_id_str: string;
  func_name_str: string;
  lib_info: PDynamicLibraryHandle;
  proc_addr: pointer;
  proc_addr_int: int64;
begin
  try
    if argc < 2 then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('GetProcAddress expects 2 arguments: library_id, function_name'));
      Exit;
    end;

    if LoadedDynamicLibraries = nil then
      LoadedDynamicLibraries := TStringList.Create;

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
    func_name_str := string(func_name);
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
      Result := JS_ThrowTypeError(ctx, PChar('Function not found in library: ' + func_name_str));
      Exit;
    end;

    // Return address as number (can be used for calling)
    proc_addr_int := int64(proc_addr);
    Result := JS_NewInt64(ctx, proc_addr_int);
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:dll:GetProcAddress: ' + E.Message));
  end;
end;

// Call DLL function (supports basic scalar and pointer/string parameters)
// Usage: CallDllFunction(dll_id, function_name, return_type, [argTypes], [args...])
// return_type: 'i' = int32/intptr, 'I' = int64/intptr, 'f' = float64, 'v' = void, 's' = PChar
// argTypes: optional string (all args must share the same kind) with chars: i/I/p, f, s
// Supports up to 6 arguments. If argTypes omitted, defaults to int ('i') for all args.
function js_call_dll_function(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
const
  MAX_ARGS = 6;
type
  {$IFDEF WINDOWS}
  TCallConvFunc0Int = function: NativeInt; stdcall;
  TCallConvFunc0Float = function: cdouble; stdcall;
  TCallConvProc0 = procedure; stdcall;

  TCallConvFunc1Int = function(a1: NativeInt): NativeInt; stdcall;
  TCallConvFunc1Float = function(a1: NativeInt): cdouble; stdcall;
  TCallConvFunc1FloatArg = function(a1: cdouble): cdouble; stdcall;
  TCallConvFunc1FloatArgInt = function(a1: cdouble): NativeInt; stdcall;
  TCallConvFunc1Str = function(a1: NativeInt): PChar; stdcall;
  TCallConvProc1Int = procedure(a1: NativeInt); stdcall;
  TCallConvProc1Float = procedure(a1: cdouble); stdcall;

  TCallConvFunc2Int = function(a1, a2: NativeInt): NativeInt; stdcall;
  TCallConvFunc2Float = function(a1, a2: NativeInt): cdouble; stdcall;
  TCallConvFunc2FloatArg = function(a1, a2: cdouble): cdouble; stdcall;
  TCallConvFunc2FloatArgInt = function(a1, a2: cdouble): NativeInt; stdcall;
  TCallConvFunc2Str = function(a1, a2: NativeInt): PChar; stdcall;
  TCallConvProc2Int = procedure(a1, a2: NativeInt); stdcall;
  TCallConvProc2Float = procedure(a1, a2: cdouble); stdcall;

  TCallConvFunc3Int = function(a1, a2, a3: NativeInt): NativeInt; stdcall;
  TCallConvFunc3Float = function(a1, a2, a3: NativeInt): cdouble; stdcall;
  TCallConvFunc3FloatArg = function(a1, a2, a3: cdouble): cdouble; stdcall;
  TCallConvFunc3FloatArgInt = function(a1, a2, a3: cdouble): NativeInt; stdcall;
  TCallConvFunc3Str = function(a1, a2, a3: NativeInt): PChar; stdcall;
  TCallConvProc3Int = procedure(a1, a2, a3: NativeInt); stdcall;
  TCallConvProc3Float = procedure(a1, a2, a3: cdouble); stdcall;

  TCallConvFunc4Int = function(a1, a2, a3, a4: NativeInt): NativeInt; stdcall;
  TCallConvFunc4Float = function(a1, a2, a3, a4: NativeInt): cdouble; stdcall;
  TCallConvFunc4FloatArg = function(a1, a2, a3, a4: cdouble): cdouble; stdcall;
  TCallConvFunc4FloatArgInt = function(a1, a2, a3, a4: cdouble): NativeInt; stdcall;
  TCallConvFunc4Str = function(a1, a2, a3, a4: NativeInt): PChar; stdcall;
  TCallConvProc4Int = procedure(a1, a2, a3, a4: NativeInt); stdcall;
  TCallConvProc4Float = procedure(a1, a2, a3, a4: cdouble); stdcall;

  TCallConvFunc5Int = function(a1, a2, a3, a4, a5: NativeInt): NativeInt; stdcall;
  TCallConvFunc5Float = function(a1, a2, a3, a4, a5: NativeInt): cdouble; stdcall;
  TCallConvFunc5FloatArg = function(a1, a2, a3, a4, a5: cdouble): cdouble; stdcall;
  TCallConvFunc5FloatArgInt = function(a1, a2, a3, a4, a5: cdouble): NativeInt; stdcall;
  TCallConvFunc5Str = function(a1, a2, a3, a4, a5: NativeInt): PChar; stdcall;
  TCallConvProc5Int = procedure(a1, a2, a3, a4, a5: NativeInt); stdcall;
  TCallConvProc5Float = procedure(a1, a2, a3, a4, a5: cdouble); stdcall;

  TCallConvFunc6Int = function(a1, a2, a3, a4, a5, a6: NativeInt): NativeInt; stdcall;
  TCallConvFunc6Float = function(a1, a2, a3, a4, a5, a6: NativeInt): cdouble; stdcall;
  TCallConvFunc6FloatArg = function(a1, a2, a3, a4, a5, a6: cdouble): cdouble; stdcall;
  TCallConvFunc6FloatArgInt = function(a1, a2, a3, a4, a5, a6: cdouble): NativeInt; stdcall;
  TCallConvFunc6Str = function(a1, a2, a3, a4, a5, a6: NativeInt): PChar; stdcall;
  TCallConvProc6Int = procedure(a1, a2, a3, a4, a5, a6: NativeInt); stdcall;
  TCallConvProc6Float = procedure(a1, a2, a3, a4, a5, a6: cdouble); stdcall;
  {$ELSE}
  TCallConvFunc0Int = function: NativeInt; cdecl;
  TCallConvFunc0Float = function: cdouble; cdecl;
  TCallConvProc0 = procedure; cdecl;

  TCallConvFunc1Int = function(a1: NativeInt): NativeInt; cdecl;
  TCallConvFunc1Float = function(a1: NativeInt): cdouble; cdecl;
  TCallConvFunc1FloatArg = function(a1: cdouble): cdouble; cdecl;
  TCallConvFunc1FloatArgInt = function(a1: cdouble): NativeInt; cdecl;
  TCallConvFunc1Str = function(a1: NativeInt): PChar; cdecl;
  TCallConvProc1Int = procedure(a1: NativeInt); cdecl;
  TCallConvProc1Float = procedure(a1: cdouble); cdecl;

  TCallConvFunc2Int = function(a1, a2: NativeInt): NativeInt; cdecl;
  TCallConvFunc2Float = function(a1, a2: NativeInt): cdouble; cdecl;
  TCallConvFunc2FloatArg = function(a1, a2: cdouble): cdouble; cdecl;
  TCallConvFunc2FloatArgInt = function(a1, a2: cdouble): NativeInt; cdecl;
  TCallConvFunc2Str = function(a1, a2: NativeInt): PChar; cdecl;
  TCallConvProc2Int = procedure(a1, a2: NativeInt); cdecl;
  TCallConvProc2Float = procedure(a1, a2: cdouble); cdecl;

  TCallConvFunc3Int = function(a1, a2, a3: NativeInt): NativeInt; cdecl;
  TCallConvFunc3Float = function(a1, a2, a3: NativeInt): cdouble; cdecl;
  TCallConvFunc3FloatArg = function(a1, a2, a3: cdouble): cdouble; cdecl;
  TCallConvFunc3FloatArgInt = function(a1, a2, a3: cdouble): NativeInt; cdecl;
  TCallConvFunc3Str = function(a1, a2, a3: NativeInt): PChar; cdecl;
  TCallConvProc3Int = procedure(a1, a2, a3: NativeInt); cdecl;
  TCallConvProc3Float = procedure(a1, a2, a3: cdouble); cdecl;

  TCallConvFunc4Int = function(a1, a2, a3, a4: NativeInt): NativeInt; cdecl;
  TCallConvFunc4Float = function(a1, a2, a3, a4: NativeInt): cdouble; cdecl;
  TCallConvFunc4FloatArg = function(a1, a2, a3, a4: cdouble): cdouble; cdecl;
  TCallConvFunc4FloatArgInt = function(a1, a2, a3, a4: cdouble): NativeInt; cdecl;
  TCallConvFunc4Str = function(a1, a2, a3, a4: NativeInt): PChar; cdecl;
  TCallConvProc4Int = procedure(a1, a2, a3, a4: NativeInt); cdecl;
  TCallConvProc4Float = procedure(a1, a2, a3, a4: cdouble); cdecl;

  TCallConvFunc5Int = function(a1, a2, a3, a4, a5: NativeInt): NativeInt; cdecl;
  TCallConvFunc5Float = function(a1, a2, a3, a4, a5: NativeInt): cdouble; cdecl;
  TCallConvFunc5FloatArg = function(a1, a2, a3, a4, a5: cdouble): cdouble; cdecl;
  TCallConvFunc5FloatArgInt = function(a1, a2, a3, a4, a5: cdouble): NativeInt; cdecl;
  TCallConvFunc5Str = function(a1, a2, a3, a4, a5: NativeInt): PChar; cdecl;
  TCallConvProc5Int = procedure(a1, a2, a3, a4, a5: NativeInt); cdecl;
  TCallConvProc5Float = procedure(a1, a2, a3, a4, a5: cdouble); cdecl;

  TCallConvFunc6Int = function(a1, a2, a3, a4, a5, a6: NativeInt): NativeInt; cdecl;
  TCallConvFunc6Float = function(a1, a2, a3, a4, a5, a6: NativeInt): cdouble; cdecl;
  TCallConvFunc6FloatArg = function(a1, a2, a3, a4, a5, a6: cdouble): cdouble; cdecl;
  TCallConvFunc6FloatArgInt = function(a1, a2, a3, a4, a5, a6: cdouble): NativeInt; cdecl;
  TCallConvFunc6Str = function(a1, a2, a3, a4, a5, a6: NativeInt): PChar; cdecl;
  TCallConvProc6Int = procedure(a1, a2, a3, a4, a5, a6: NativeInt); cdecl;
  TCallConvProc6Float = procedure(a1, a2, a3, a4, a5, a6: cdouble); cdecl;
  {$ENDIF}
var
  lib_id, func_name, return_type: PChar;
  lib_id_str: string;
  lib_info: PDynamicLibraryHandle;
  proc_addr: pointer;
  i: integer;
  arg_types_cstr: PChar;
  arg_types_str: string;
  arg_start_idx: integer;
  arg_count: integer;
  uniform_arg_kind: char;
  has_arg_types: boolean;
  args_int: array[0..MAX_ARGS - 1] of NativeInt;
  args_float: array[0..MAX_ARGS - 1] of cdouble;
  args_str: array[0..MAX_ARGS - 1] of PChar;
  need_free_str: array[0..MAX_ARGS - 1] of boolean;
  result_int: NativeInt;
  result_float: cdouble;
  valid: boolean;
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

  // Extended implementation with up to MAX_ARGS arguments and uniform arg type
  arg_types_cstr := nil;
  try
    has_arg_types := (argc > 3) and (JS_IsString(argv[3]) <> 0);
    arg_start_idx := 3;
    arg_types_str := '';

    if has_arg_types then
    begin
      arg_types_cstr := JS_ToCString(ctx, argv[3]);
      if arg_types_cstr = nil then
      begin
        JS_FreeCString(ctx, return_type);
        Result := JS_EXCEPTION;
        Exit;
      end;
      arg_types_str := string(arg_types_cstr);
      arg_start_idx := 4;
    end;

    arg_count := argc - arg_start_idx;
    if arg_count < 0 then
      arg_count := 0;

    if (arg_types_str <> '') and (Length(arg_types_str) <> arg_count) then
    begin
      JS_FreeCString(ctx, return_type);
      if arg_types_cstr <> nil then
        JS_FreeCString(ctx, arg_types_cstr);
      Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: argTypes length must match number of arguments'));
      Exit;
    end;

    if arg_types_str = '' then
    begin
      // Default: assume all int arguments
      arg_types_str := StringOfChar('i', arg_count);
    end;

    if arg_count > MAX_ARGS then
    begin
      JS_FreeCString(ctx, return_type);
      if arg_types_cstr <> nil then
        JS_FreeCString(ctx, arg_types_cstr);
      Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: too many arguments (max ' + IntToStr(MAX_ARGS) + ')'));
      Exit;
    end;

    uniform_arg_kind := #0;
    valid := True;
    for i := 1 to Length(arg_types_str) do
    begin
      case arg_types_str[i] of
        'i', 'I', 'p': if uniform_arg_kind = #0 then uniform_arg_kind := 'i';
        'f': if uniform_arg_kind = #0 then uniform_arg_kind := 'f';
        's': if uniform_arg_kind = #0 then uniform_arg_kind := 's';
        else valid := False;
      end;
      if not valid then Break;
      // Ensure uniform kind
      case arg_types_str[i] of
        'i', 'I', 'p': if uniform_arg_kind <> 'i' then valid := False;
        'f': if uniform_arg_kind <> 'f' then valid := False;
        's': if uniform_arg_kind <> 's' then valid := False;
      end;
      if not valid then Break;
    end;

    if not valid then
    begin
      JS_FreeCString(ctx, return_type);
      if arg_types_cstr <> nil then
        JS_FreeCString(ctx, arg_types_cstr);
      Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: mixed or unsupported argument types. Use uniform types (i/I/p, f, or s)'));
      Exit;
    end;

    // Convert arguments
    FillChar(need_free_str, SizeOf(need_free_str), 0);
    for i := 0 to arg_count - 1 do
    begin
      case uniform_arg_kind of
        'i':
          begin
            if JS_ToInt64(ctx, @args_int[i], argv[arg_start_idx + i]) < 0 then
            begin
              JS_FreeCString(ctx, return_type);
              if arg_types_cstr <> nil then
                JS_FreeCString(ctx, arg_types_cstr);
              Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: argument ' + IntToStr(i) + ' is not an integer'));
              Exit;
            end;
          end;
        'f':
          begin
            if JS_ToFloat64(ctx, @args_float[i], argv[arg_start_idx + i]) < 0 then
            begin
              JS_FreeCString(ctx, return_type);
              if arg_types_cstr <> nil then
                JS_FreeCString(ctx, arg_types_cstr);
              Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: argument ' + IntToStr(i) + ' is not a number'));
              Exit;
            end;
          end;
        's':
          begin
            args_str[i] := JS_ToCString(ctx, argv[arg_start_idx + i]);
            if args_str[i] = nil then
            begin
              JS_FreeCString(ctx, return_type);
              if arg_types_cstr <> nil then
                JS_FreeCString(ctx, arg_types_cstr);
              Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: argument ' + IntToStr(i) + ' is not a string'));
              Exit;
            end;
            need_free_str[i] := True;
            args_int[i] := NativeInt(args_str[i]);
          end;
      end;
    end;

    // Dispatch based on arg_count and uniform_arg_kind
    case uniform_arg_kind of
      'f': // floating args
        case arg_count of
          0:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc0Float(proc_addr)(); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc0Int(proc_addr)(); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc0(proc_addr)(); Result := JS_UNDEFINED; end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          1:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc1FloatArg(proc_addr)(args_float[0]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc1FloatArgInt(proc_addr)(args_float[0]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc1Float(proc_addr)(args_float[0]); Result := JS_UNDEFINED; end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          2:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc2FloatArg(proc_addr)(args_float[0], args_float[1]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc2FloatArgInt(proc_addr)(args_float[0], args_float[1]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc2Float(proc_addr)(args_float[0], args_float[1]); Result := JS_UNDEFINED; end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          3:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc3FloatArg(proc_addr)(args_float[0], args_float[1], args_float[2]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc3FloatArgInt(proc_addr)(args_float[0], args_float[1], args_float[2]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc3Float(proc_addr)(args_float[0], args_float[1], args_float[2]); Result := JS_UNDEFINED; end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          4:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc4FloatArg(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc4FloatArgInt(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc4Float(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3]); Result := JS_UNDEFINED; end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          5:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc5FloatArg(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3], args_float[4]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc5FloatArgInt(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3], args_float[4]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc5Float(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3], args_float[4]); Result := JS_UNDEFINED; end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          6:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc6FloatArg(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3], args_float[4], args_float[5]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc6FloatArgInt(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3], args_float[4], args_float[5]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc6Float(proc_addr)(args_float[0], args_float[1], args_float[2], args_float[3], args_float[4], args_float[5]); Result := JS_UNDEFINED; end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported argument count'));
        end;
      else // integer / pointer / string pointer arguments
        case arg_count of
          0:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc0Float(proc_addr)(); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc0Int(proc_addr)(); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc0(proc_addr)(); Result := JS_UNDEFINED; end;
              's': begin Result := JS_NewString(ctx, PChar(TCallConvFunc0Int(proc_addr)())); end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          1:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc1Float(proc_addr)(args_int[0]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc1Int(proc_addr)(args_int[0]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc1Int(proc_addr)(args_int[0]); Result := JS_UNDEFINED; end;
              's': begin Result := JS_NewString(ctx, TCallConvFunc1Str(proc_addr)(args_int[0])); end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          2:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc2Float(proc_addr)(args_int[0], args_int[1]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc2Int(proc_addr)(args_int[0], args_int[1]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc2Int(proc_addr)(args_int[0], args_int[1]); Result := JS_UNDEFINED; end;
              's': begin Result := JS_NewString(ctx, TCallConvFunc2Str(proc_addr)(args_int[0], args_int[1])); end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          3:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc3Float(proc_addr)(args_int[0], args_int[1], args_int[2]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc3Int(proc_addr)(args_int[0], args_int[1], args_int[2]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc3Int(proc_addr)(args_int[0], args_int[1], args_int[2]); Result := JS_UNDEFINED; end;
              's': begin Result := JS_NewString(ctx, TCallConvFunc3Str(proc_addr)(args_int[0], args_int[1], args_int[2])); end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          4:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc4Float(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc4Int(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc4Int(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3]); Result := JS_UNDEFINED; end;
              's': begin Result := JS_NewString(ctx, TCallConvFunc4Str(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3])); end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          5:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc5Float(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc5Int(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc5Int(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4]); Result := JS_UNDEFINED; end;
              's': begin Result := JS_NewString(ctx, TCallConvFunc5Str(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4])); end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          6:
            case return_type[0] of
              'f': begin result_float := TCallConvFunc6Float(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4], args_int[5]); Result := JS_NewFloat64(ctx, result_float); end;
              'i', 'I', 'p': begin result_int := TCallConvFunc6Int(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4], args_int[5]); Result := JS_NewInt64(ctx, result_int); end;
              'v': begin TCallConvProc6Int(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4], args_int[5]); Result := JS_UNDEFINED; end;
              's': begin Result := JS_NewString(ctx, TCallConvFunc6Str(proc_addr)(args_int[0], args_int[1], args_int[2], args_int[3], args_int[4], args_int[5])); end;
              else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported return type'));
            end;
          else Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Unsupported argument count'));
        end;
    end;

    JS_FreeCString(ctx, return_type);
    if arg_types_cstr <> nil then
      JS_FreeCString(ctx, arg_types_cstr);
    // Free strings if any
    for i := 0 to arg_count - 1 do
      if need_free_str[i] then
        JS_FreeCString(ctx, args_str[i]);
  except
    JS_FreeCString(ctx, return_type);
    if arg_types_cstr <> nil then
      JS_FreeCString(ctx, arg_types_cstr);
    for i := 0 to arg_count - 1 do
      if need_free_str[i] then
        JS_FreeCString(ctx, args_str[i]);
    Result := JS_ThrowTypeError(ctx, PChar('CallDllFunction: Exception occurred while calling DLL function'));
  end;
end;

// Free dynamic library
function js_free_dll(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  lib_id: PChar;
  lib_id_str: string;
  lib_info: PDynamicLibraryHandle;
  idx: integer;
begin
  try
    if argc < 1 then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('FreeDLL expects 1 argument: library_id'));
      Exit;
    end;

    if LoadedDynamicLibraries = nil then
      LoadedDynamicLibraries := TStringList.Create;

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
    FreeDLL(lib_info^.handle);
    Dispose(lib_info);
    LoadedDynamicLibraries.Delete(idx);

    Result := JS_UNDEFINED;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('qar:dll:FreeDLL: ' + E.Message));
  end;
end;

// Register DLL helper functions to JavaScript global object
procedure RegisterDllHelpers(ctx: PJSContext);
var
  global_obj: JSValue;
begin
  global_obj := JS_GetGlobalObject(ctx);

  // Register dynamic library calling functions (cross-platform)
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('LoadLib'),
    JS_NewCFunction(ctx, @js_load_library_auto, PChar('LoadLib'), 2), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('LoadDLL'),
    JS_NewCFunction(ctx, @js_load_dll, PChar('LoadDLL'), 1), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('GetProcAddress'),
    JS_NewCFunction(ctx, @js_get_proc_address, PChar('GetProcAddress'), 2), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('CallDllFunction'),
    JS_NewCFunction(ctx, @js_call_dll_function, PChar('CallDllFunction'), 10), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('FreeDLL'),
    JS_NewCFunction(ctx, @js_free_dll, PChar('FreeDLL'), 1), JS_PROP_C_W_E);

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
      FreeDLL(lib_info^.handle);
      Dispose(lib_info);
    end;
    LoadedDynamicLibraries.Delete(i);
  end;
end;

end.

