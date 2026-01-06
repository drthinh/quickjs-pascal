unit UnitQuickJS;

{$mode delphi}
{$H+}
{$packrecords C}

{
  QuickJS Delphi Binding
  Wrapper for libquickjs.dll - Modern JavaScript Engine

  QuickJS Version: 2025-09-13 (bellard/quickjs)
  Build with: -DJS_PTR64 (non-NAN_BOXING, JSValue = 16 bytes struct)

  IMPORTANT: This binding requires QuickJS built WITHOUT NAN_BOXING
  to ensure JSValue is a 16-byte struct compatible with Delphi.
}

interface

uses
  Windows, SysUtils;

type
  // Delphi 7 compatibility types
  Int32 = Longint;
  PInt32 = ^Int32;
  PInt64 = ^Int64;
  PCardinal = ^Cardinal;
  UInt64 = Int64; // Delphi 7 không có UInt64, dùng Int64 thay thế

const
  QUICKJS_DLL = 'libquickjs64.dll';

  // JS_TAG values (QuickJS 2025-09-13, non-NAN_BOXING mode)
  // All tags with reference count are negative
  JS_TAG_FIRST             = -9;
  JS_TAG_BIG_INT           = -9;
  JS_TAG_SYMBOL            = -8;
  JS_TAG_STRING            = -7;
  JS_TAG_STRING_ROPE       = -6;  // New in 2025
  JS_TAG_MODULE            = -3;  // Used internally
  JS_TAG_FUNCTION_BYTECODE = -2;  // Used internally
  JS_TAG_OBJECT            = -1;
  JS_TAG_INT               = 0;
  JS_TAG_BOOL              = 1;
  JS_TAG_NULL              = 2;
  JS_TAG_UNDEFINED         = 3;
  JS_TAG_UNINITIALIZED     = 4;
  JS_TAG_CATCH_OFFSET      = 5;
  JS_TAG_EXCEPTION         = 6;
  JS_TAG_SHORT_BIG_INT     = 7;   // New in 2025
  JS_TAG_FLOAT64           = 8;   // Changed from 7

  // Eval flags (QuickJS 2025-09-13)
  JS_EVAL_TYPE_GLOBAL   = 0;   // Global code (default)
  JS_EVAL_TYPE_MODULE   = 1;   // Module code
  JS_EVAL_TYPE_DIRECT   = 2;   // Direct call (internal use)
  JS_EVAL_TYPE_INDIRECT = 3;   // Indirect call (internal use)
  JS_EVAL_TYPE_MASK     = 3;
  JS_EVAL_FLAG_STRICT   = 8;   // Force 'strict' mode
  JS_EVAL_FLAG_COMPILE_ONLY = 32;        // Compile but do not run
  JS_EVAL_FLAG_BACKTRACE_BARRIER = 64;   // Don't include stack frames before this eval
  JS_EVAL_FLAG_ASYNC    = 128; // Allow top-level await in normal script

  // Property flags
  JS_PROP_CONFIGURABLE  = 1;
  JS_PROP_WRITABLE      = 2;
  JS_PROP_ENUMERABLE    = 4;
  JS_PROP_C_W_E         = JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE or JS_PROP_ENUMERABLE;
  JS_PROP_LENGTH        = 8;
  JS_PROP_TMASK         = 48;
  JS_PROP_NORMAL        = 0;
  JS_PROP_GETSET        = 16;
  JS_PROP_VARREF        = 32;
  JS_PROP_AUTOINIT      = 48;

  // GPN flags
  JS_GPN_STRING_MASK    = 1;
  JS_GPN_SYMBOL_MASK    = 2;
  JS_GPN_PRIVATE_MASK   = 4;
  JS_GPN_ENUM_ONLY      = 16;
  JS_GPN_SET_ENUM       = 32;

type
  // Pointer types
  PJSRuntime = Pointer;
  PJSContext = Pointer;
  PJSValue = ^TJSValue;

  // JSValue - 16 bytes total (theo quickjs.h)
  // KHÔNG dùng packed để đảm bảo alignment giống C compiler
  TJSValueUnion = record
    case Integer of
      0: (int32: Int32);
      1: (float64: Double);
      2: (ptr: Pointer);
  end;

  TJSValue = record
    u: TJSValueUnion;  // 8 bytes (aligned)
    tag: Int64;        // 8 bytes
  end;

  // C function callback type
  TJSCFunction = function(ctx: PJSContext; this_val: TJSValue;
    argc: Integer; argv: PJSValue): TJSValue; cdecl;

  TJSCFunctionMagic = function(ctx: PJSContext; this_val: TJSValue;
    argc: Integer; argv: PJSValue; magic: Integer): TJSValue; cdecl;

  // CFunctionListEntry for bulk registration
  TJSCFunctionListEntry = packed record
    name: PAnsiChar;
    prop_flags: Byte;
    def_type: Byte;
    magic: Int16;
    case Integer of
      0: (func: record
            length: Byte;
            cproto: Byte;
            cfunc: TJSCFunction;
          end);
      1: (getset: record
            get: TJSCFunction;
            set_: TJSCFunction;
          end);
      2: (alias: record
            alias_name: PAnsiChar;
            base: Integer;
          end);
      3: (prop_list: record
            tab: Pointer;
            len: Integer;
          end);
      4: (str: PAnsiChar);
      5: (i32: Int32);
      6: (i64: Int64);
      7: (f64: Double);
  end;

  TJSInterruptHandler = function(rt: PJSRuntime; opaque: Pointer): Integer; cdecl;

// ============================================
// Runtime functions
// ============================================
function JS_NewRuntime: PJSRuntime; cdecl; external QUICKJS_DLL;
procedure JS_FreeRuntime(rt: PJSRuntime); cdecl; external QUICKJS_DLL;
procedure JS_SetRuntimeInfo(rt: PJSRuntime; info: PAnsiChar); cdecl; external QUICKJS_DLL;
procedure JS_SetMemoryLimit(rt: PJSRuntime; limit: Cardinal); cdecl; external QUICKJS_DLL;
procedure JS_SetMaxStackSize(rt: PJSRuntime; stack_size: Cardinal); cdecl; external QUICKJS_DLL;
procedure JS_SetInterruptHandler(rt: PJSRuntime; cb: TJSInterruptHandler; opaque: Pointer); cdecl; external QUICKJS_DLL;
procedure JS_SetCanBlock(rt: PJSRuntime; can_block: Integer); cdecl; external QUICKJS_DLL;
procedure JS_RunGC(rt: PJSRuntime); cdecl; external QUICKJS_DLL;
function JS_IsLiveObject(rt: PJSRuntime; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;

// ============================================
// Context functions
// ============================================
function JS_NewContext(rt: PJSRuntime): PJSContext; cdecl; external QUICKJS_DLL;
procedure JS_FreeContext(ctx: PJSContext); cdecl; external QUICKJS_DLL;
function JS_GetRuntime(ctx: PJSContext): PJSRuntime; cdecl; external QUICKJS_DLL;
procedure JS_SetContextOpaque(ctx: PJSContext; opaque: Pointer); cdecl; external QUICKJS_DLL;
function JS_GetContextOpaque(ctx: PJSContext): Pointer; cdecl; external QUICKJS_DLL;

// ============================================
// Value creation (từ DLL) - với hidden return pointer cho struct 16 bytes
// Trong C 32-bit cdecl, struct > 8 bytes được return qua hidden pointer làm first param.
// Lưu ý: JS_NewString chỉ là inline trong quickjs.h, DLL thực tế chỉ export JS_NewStringLen.
// Vì vậy _JS_NewString sẽ được implement trong Delphi và gọi JS_NewStringLen.
// ============================================
procedure _JS_NewString(ret: PJSValue; ctx: PJSContext; str: PAnsiChar); cdecl;
procedure _JS_NewStringLen(ret: PJSValue; ctx: PJSContext; str: PAnsiChar; len: Cardinal); cdecl; external QUICKJS_DLL name 'JS_NewStringLen';
procedure _JS_NewObject(ret: PJSValue; ctx: PJSContext); cdecl; external QUICKJS_DLL name 'JS_NewObject';
procedure _JS_NewArray(ret: PJSValue; ctx: PJSContext); cdecl; external QUICKJS_DLL name 'JS_NewArray';
procedure _JS_NewCFunction2(ret: PJSValue; ctx: PJSContext; func: TJSCFunction;
  name: PAnsiChar; length: Integer; cproto: Integer; magic: Integer); cdecl; external QUICKJS_DLL name 'JS_NewCFunction2';
procedure _JS_NewBigInt64(ret: PJSValue; ctx: PJSContext; val: Int64); cdecl; external QUICKJS_DLL name 'JS_NewBigInt64';

// Wrappers
function JS_NewString(ctx: PJSContext; str: PAnsiChar): TJSValue;
function JS_NewStringLen(ctx: PJSContext; str: PAnsiChar; len: Cardinal): TJSValue;
function JS_NewObject(ctx: PJSContext): TJSValue;
function JS_NewArray(ctx: PJSContext): TJSValue;
function JS_NewBigInt64(ctx: PJSContext; val: Int64): TJSValue;

// ============================================
// Value creation (inline - implemented in Delphi)
// ============================================
function JS_NewBool(ctx: PJSContext; val: Integer): TJSValue;
function JS_NewInt32(ctx: PJSContext; val: Int32): TJSValue;
function JS_NewInt64(ctx: PJSContext; val: Int64): TJSValue;
function JS_NewFloat64(ctx: PJSContext; val: Double): TJSValue;
function JS_NewCFunction(ctx: PJSContext; func: TJSCFunction;
  name: PAnsiChar; length: Integer): TJSValue;
function JS_NewCFunction2(ctx: PJSContext; func: TJSCFunction;
  name: PAnsiChar; length: Integer; cproto: Integer; magic: Integer): TJSValue;

// ============================================
// Value conversion
// ============================================
// JS_ToCString không có, dùng JS_ToCStringLen2
function JS_ToCStringLen2(ctx: PJSContext; plen: PCardinal; val: TJSValue; cesu8: Integer): PAnsiChar; cdecl; external QUICKJS_DLL;
procedure JS_FreeCString(ctx: PJSContext; ptr: PAnsiChar); cdecl; external QUICKJS_DLL;
function JS_ToInt32(ctx: PJSContext; pres: PInt32; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;
function JS_ToInt64(ctx: PJSContext; pres: PInt64; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;
function JS_ToFloat64(ctx: PJSContext; pres: PDouble; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;
function JS_ToBool(ctx: PJSContext; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;
// Wrapper for JS_ToCString
function JS_ToCString(ctx: PJSContext; val: TJSValue): PAnsiChar;

// ============================================
// Value management
// ============================================
// __JS_FreeValue là tên thực trong DLL
procedure __JS_FreeValue(ctx: PJSContext; val: TJSValue); cdecl; external QUICKJS_DLL;
// Wrapper
procedure JS_FreeValue(ctx: PJSContext; val: TJSValue);
// DupValue - implement trong Delphi vì có thể không có trong DLL
function JS_DupValue(ctx: PJSContext; val: TJSValue): TJSValue;

// ============================================
// Evaluation - với hidden return pointer
// ============================================
procedure _JS_Eval(ret: PJSValue; ctx: PJSContext; input: PAnsiChar; input_len: Cardinal;
  filename: PAnsiChar; eval_flags: Integer); cdecl; external QUICKJS_DLL name 'JS_Eval';
procedure _JS_EvalFunction(ret: PJSValue; ctx: PJSContext; fun_obj: TJSValue); cdecl; external QUICKJS_DLL name 'JS_EvalFunction';
procedure _JS_Call(ret: PJSValue; ctx: PJSContext; func_obj, this_obj: TJSValue;
  argc: Integer; argv: PJSValue); cdecl; external QUICKJS_DLL name 'JS_Call';

function JS_Eval(ctx: PJSContext; input: PAnsiChar; input_len: Cardinal;
  filename: PAnsiChar; eval_flags: Integer): TJSValue;
function JS_EvalFunction(ctx: PJSContext; fun_obj: TJSValue): TJSValue;
function JS_Call(ctx: PJSContext; func_obj, this_obj: TJSValue;
  argc: Integer; argv: PJSValue): TJSValue;

// ============================================
// Object/Property operations - với hidden return pointer
// ============================================
procedure _JS_GetGlobalObject(ret: PJSValue; ctx: PJSContext); cdecl; external QUICKJS_DLL name 'JS_GetGlobalObject';
procedure _JS_GetPropertyStr(ret: PJSValue; ctx: PJSContext; this_obj: TJSValue;
  prop: PAnsiChar); cdecl; external QUICKJS_DLL name 'JS_GetPropertyStr';
function JS_SetPropertyStr(ctx: PJSContext; this_obj: TJSValue;
  prop: PAnsiChar; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;
procedure _JS_GetPropertyUint32(ret: PJSValue; ctx: PJSContext; this_obj: TJSValue;
  idx: Cardinal); cdecl; external QUICKJS_DLL name 'JS_GetPropertyUint32';
function JS_SetPropertyUint32(ctx: PJSContext; this_obj: TJSValue;
  idx: Cardinal; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;
function JS_DefinePropertyValueStr(ctx: PJSContext; this_obj: TJSValue;
  prop: PAnsiChar; val: TJSValue; flags: Integer): Integer; cdecl; external QUICKJS_DLL;
function JS_HasProperty(ctx: PJSContext; this_obj: TJSValue; prop: TJSValue): Integer; cdecl; external QUICKJS_DLL;
function JS_IsFunction(ctx: PJSContext; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;
function JS_IsArray(ctx: PJSContext; val: TJSValue): Integer; cdecl; external QUICKJS_DLL;

function JS_GetGlobalObject(ctx: PJSContext): TJSValue;
function JS_GetPropertyStr(ctx: PJSContext; this_obj: TJSValue; prop: PAnsiChar): TJSValue;
function JS_GetPropertyUint32(ctx: PJSContext; this_obj: TJSValue; idx: Cardinal): TJSValue;

procedure _JS_ParseJSON(ret: PJSValue; ctx: PJSContext; buf: PAnsiChar;
  buf_len: Cardinal; filename: PAnsiChar); cdecl; external QUICKJS_DLL name 'JS_ParseJSON';
function JS_ParseJSON(ctx: PJSContext; buf: PAnsiChar; buf_len: Cardinal;
  filename: PAnsiChar): TJSValue;

// ============================================
// Exceptions - với hidden return pointer
// ============================================
procedure _JS_GetException(ret: PJSValue; ctx: PJSContext); cdecl; external QUICKJS_DLL name 'JS_GetException';
procedure _JS_Throw(ret: PJSValue; ctx: PJSContext; obj: TJSValue); cdecl; external QUICKJS_DLL name 'JS_Throw';

function JS_GetException(ctx: PJSContext): TJSValue;
function JS_Throw(ctx: PJSContext; obj: TJSValue): TJSValue;

// JS_IsException là macro trong QuickJS, implement trong Delphi
function JS_IsException(val: TJSValue): Integer;

// ============================================
// Helper functions (Delphi)
// ============================================
function JS_VALUE_GET_TAG(v: TJSValue): Integer; inline;
function JS_VALUE_GET_INT(v: TJSValue): Int32; inline;
function JS_VALUE_GET_BOOL(v: TJSValue): Integer; inline;
function JS_VALUE_GET_FLOAT64(v: TJSValue): Double; inline;
function JS_VALUE_GET_PTR(v: TJSValue): Pointer; inline;

function JS_IsNull(v: TJSValue): Boolean; inline;
function JS_IsUndefined(v: TJSValue): Boolean; inline;
function JS_IsBool(v: TJSValue): Boolean; inline;
function JS_IsNumber(v: TJSValue): Boolean; inline;
function JS_IsString(v: TJSValue): Boolean; inline;
function JS_IsObject(v: TJSValue): Boolean; inline;
function JS_IsBigInt(v: TJSValue): Boolean; inline;
function JS_IsSymbol(v: TJSValue): Boolean; inline;

function JS_UNDEFINED: TJSValue; inline;
function JS_NULL: TJSValue; inline;
function JS_TRUE: TJSValue; inline;
function JS_FALSE: TJSValue; inline;
function JS_EXCEPTION: TJSValue; inline;

// Delphi string helpers
function JSValueToString(ctx: PJSContext; val: TJSValue): WideString;
function StringToJSValue(ctx: PJSContext; const s: WideString): TJSValue;
function JSValueToInt(ctx: PJSContext; val: TJSValue): Integer;
function JSValueToDouble(ctx: PJSContext; val: TJSValue): Double;
function JSValueToBool(ctx: PJSContext; val: TJSValue): Boolean;

// Exception helper
function GetJSException(ctx: PJSContext): WideString;

implementation

function JS_VALUE_GET_TAG(v: TJSValue): Integer;
begin
  Result := Integer(v.tag); // tag is Int64, cast to Integer for comparison
end;

function JS_VALUE_GET_INT(v: TJSValue): Int32;
begin
  Result := v.u.int32;
end;

function JS_VALUE_GET_BOOL(v: TJSValue): Integer;
begin
  Result := v.u.int32;
end;

function JS_VALUE_GET_FLOAT64(v: TJSValue): Double;
begin
  Result := v.u.float64;
end;

function JS_VALUE_GET_PTR(v: TJSValue): Pointer;
begin
  Result := v.u.ptr;
end;

function JS_IsException(val: TJSValue): Integer;
begin
  // JS_IsException is a macro in QuickJS: (JS_VALUE_GET_TAG(v) == JS_TAG_EXCEPTION)
  if Integer(val.tag) = JS_TAG_EXCEPTION then
    Result := 1
  else
    Result := 0;
end;

type
  // Ref count header - must match QuickJS internal structure
  PJSRefCountHeader = ^TJSRefCountHeader;
  TJSRefCountHeader = record
    ref_count: Integer;
  end;

procedure JS_FreeValue(ctx: PJSContext; val: TJSValue);
var
  p: PJSRefCountHeader;
begin
  // Only free if value has ref count (tag < JS_TAG_FIRST means it's a refcounted object)
  // JS_VALUE_HAS_REF_COUNT: (unsigned)tag >= (unsigned)JS_TAG_FIRST
  // Since JS_TAG_FIRST = -9, tags -9 to -1 have ref counts
  if Integer(val.tag) < 0 then
  begin
    p := PJSRefCountHeader(val.u.ptr);
    Dec(p^.ref_count);
    if p^.ref_count <= 0 then
      __JS_FreeValue(ctx, val);
  end;
end;

function JS_DupValue(ctx: PJSContext; val: TJSValue): TJSValue;
var
  p: PJSRefCountHeader;
begin
  Result := val;
  // Increment ref count for refcounted values
  if Integer(val.tag) < 0 then
  begin
    p := PJSRefCountHeader(val.u.ptr);
    Inc(p^.ref_count);
  end;
end;

function JS_NewBool(ctx: PJSContext; val: Integer): TJSValue;
begin
  Result.tag := JS_TAG_BOOL;
  if val <> 0 then
    Result.u.int32 := 1
  else
    Result.u.int32 := 0;
end;

function JS_NewInt32(ctx: PJSContext; val: Int32): TJSValue;
begin
  Result.tag := JS_TAG_INT;
  Result.u.int32 := val;
end;

function JS_NewInt64(ctx: PJSContext; val: Int64): TJSValue;
begin
  // Nếu val nằm trong range Int32, dùng INT tag
  if (val >= Low(Int32)) and (val <= High(Int32)) then
  begin
    Result.tag := JS_TAG_INT;
    Result.u.int32 := Int32(val);
  end
  else
  begin
    // Dùng BigInt64 cho giá trị lớn
    Result := JS_NewBigInt64(ctx, val);
  end;
end;

function JS_NewFloat64(ctx: PJSContext; val: Double): TJSValue;
begin
  Result.tag := JS_TAG_FLOAT64;
  Result.u.float64 := val;
end;

function JS_NewCFunction(ctx: PJSContext; func: TJSCFunction;
  name: PAnsiChar; length: Integer): TJSValue;
begin
  _JS_NewCFunction2(@Result, ctx, func, name, length, 0, 0);
end;

function JS_NewCFunction2(ctx: PJSContext; func: TJSCFunction;
  name: PAnsiChar; length: Integer; cproto: Integer; magic: Integer): TJSValue;
begin
  _JS_NewCFunction2(@Result, ctx, func, name, length, cproto, magic);
end;

procedure _JS_NewString(ret: PJSValue; ctx: PJSContext; str: PAnsiChar); cdecl;
var
  len: Cardinal;
begin
  if str = nil then
    len := 0
  else
    len := Cardinal(StrLen(str));
  _JS_NewStringLen(ret, ctx, str, len);
end;

function JS_NewString(ctx: PJSContext; str: PAnsiChar): TJSValue;
begin
  _JS_NewString(@Result, ctx, str);
end;

function JS_NewStringLen(ctx: PJSContext; str: PAnsiChar; len: Cardinal): TJSValue;
begin
  _JS_NewStringLen(@Result, ctx, str, len);
end;

function JS_NewObject(ctx: PJSContext): TJSValue;
begin
  _JS_NewObject(@Result, ctx);
end;

function JS_NewArray(ctx: PJSContext): TJSValue;
begin
  _JS_NewArray(@Result, ctx);
end;

function JS_NewBigInt64(ctx: PJSContext; val: Int64): TJSValue;
begin
  _JS_NewBigInt64(@Result, ctx, val);
end;

function JS_Eval(ctx: PJSContext; input: PAnsiChar; input_len: Cardinal;
  filename: PAnsiChar; eval_flags: Integer): TJSValue;
begin
  _JS_Eval(@Result, ctx, input, input_len, filename, eval_flags);
end;

function JS_EvalFunction(ctx: PJSContext; fun_obj: TJSValue): TJSValue;
begin
  _JS_EvalFunction(@Result, ctx, fun_obj);
end;

function JS_Call(ctx: PJSContext; func_obj, this_obj: TJSValue;
  argc: Integer; argv: PJSValue): TJSValue;
begin
  _JS_Call(@Result, ctx, func_obj, this_obj, argc, argv);
end;

function JS_GetGlobalObject(ctx: PJSContext): TJSValue;
begin
  _JS_GetGlobalObject(@Result, ctx);
end;

function JS_GetPropertyStr(ctx: PJSContext; this_obj: TJSValue; prop: PAnsiChar): TJSValue;
begin
  _JS_GetPropertyStr(@Result, ctx, this_obj, prop);
end;

function JS_GetPropertyUint32(ctx: PJSContext; this_obj: TJSValue; idx: Cardinal): TJSValue;
begin
  _JS_GetPropertyUint32(@Result, ctx, this_obj, idx);
end;

function JS_ParseJSON(ctx: PJSContext; buf: PAnsiChar; buf_len: Cardinal;
  filename: PAnsiChar): TJSValue;
begin
  _JS_ParseJSON(@Result, ctx, buf, buf_len, filename);
end;

function JS_GetException(ctx: PJSContext): TJSValue;
begin
  _JS_GetException(@Result, ctx);
end;

function JS_Throw(ctx: PJSContext; obj: TJSValue): TJSValue;
begin
  _JS_Throw(@Result, ctx, obj);
end;

function JS_ToCString(ctx: PJSContext; val: TJSValue): PAnsiChar;
begin
  // cesu8 = 0 (UTF-8)
  Result := JS_ToCStringLen2(ctx, nil, val, 0);
end;

function JS_IsNull(v: TJSValue): Boolean;
begin
  Result := Integer(v.tag) = JS_TAG_NULL;
end;

function JS_IsUndefined(v: TJSValue): Boolean;
begin
  Result := Integer(v.tag) = JS_TAG_UNDEFINED;
end;

function JS_IsBool(v: TJSValue): Boolean;
begin
  Result := Integer(v.tag) = JS_TAG_BOOL;
end;

function JS_IsNumber(v: TJSValue): Boolean;
var
  tag: Integer;
begin
  tag := Integer(v.tag);
  // JS_TAG_IS_FLOAT64(tag) = (tag >= JS_TAG_FLOAT64)
  Result := (tag = JS_TAG_INT) or (tag >= JS_TAG_FLOAT64);
end;

function JS_IsString(v: TJSValue): Boolean;
var
  tag: Integer;
begin
  tag := Integer(v.tag);
  // QuickJS 2025: String can be JS_TAG_STRING or JS_TAG_STRING_ROPE
  Result := (tag = JS_TAG_STRING) or (tag = JS_TAG_STRING_ROPE);
end;

function JS_IsObject(v: TJSValue): Boolean;
begin
  Result := Integer(v.tag) = JS_TAG_OBJECT;
end;

function JS_IsBigInt(v: TJSValue): Boolean;
var
  tag: Integer;
begin
  tag := Integer(v.tag);
  // BigInt can be JS_TAG_BIG_INT or JS_TAG_SHORT_BIG_INT
  Result := (tag = JS_TAG_BIG_INT) or (tag = JS_TAG_SHORT_BIG_INT);
end;

function JS_IsSymbol(v: TJSValue): Boolean;
begin
  Result := Integer(v.tag) = JS_TAG_SYMBOL;
end;

function JS_UNDEFINED: TJSValue;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_UNDEFINED;
end;

function JS_NULL: TJSValue;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_NULL;
end;

function JS_TRUE: TJSValue;
begin
  Result.u.int32 := 1;
  Result.tag := JS_TAG_BOOL;
end;

function JS_FALSE: TJSValue;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_BOOL;
end;

function JS_EXCEPTION: TJSValue;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_EXCEPTION;
end;

function JSValueToString(ctx: PJSContext; val: TJSValue): WideString;
var
  cstr: PAnsiChar;
  utf8Str: UTF8String;
begin
  Result := '';
  if JS_IsException(val) <> 0 then Exit;

  cstr := JS_ToCString(ctx, val);
  if cstr <> nil then
  begin
    // QuickJS returns UTF-8 encoded strings, decode properly to WideString
    utf8Str := UTF8String(cstr);
    Result := UTF8Decode(utf8Str);
    JS_FreeCString(ctx, cstr);
  end;
end;

function StringToJSValue(ctx: PJSContext; const s: WideString): TJSValue;
var
  utf8: AnsiString;
begin
  utf8 := AnsiString(UTF8Encode(s));
  Result := JS_NewStringLen(ctx, PAnsiChar(utf8), Length(utf8));
end;

function JSValueToInt(ctx: PJSContext; val: TJSValue): Integer;
var
  res: Int32;
begin
  Result := 0;
  if JS_ToInt32(ctx, @res, val) = 0 then
    Result := res;
end;

function JSValueToDouble(ctx: PJSContext; val: TJSValue): Double;
var
  res: Double;
begin
  Result := 0;
  if JS_ToFloat64(ctx, @res, val) = 0 then
    Result := res;
end;

function JSValueToBool(ctx: PJSContext; val: TJSValue): Boolean;
begin
  Result := JS_ToBool(ctx, val) <> 0;
end;

function GetJSException(ctx: PJSContext): WideString;
var
  exc, stack: TJSValue;
  excStr, stackStr: WideString;
begin
  Result := '';
  exc := JS_GetException(ctx);

  if JS_IsException(exc) = 0 then
  begin
    excStr := JSValueToString(ctx, exc);

    // Try to get stack trace
    if JS_IsObject(exc) then
    begin
      stack := JS_GetPropertyStr(ctx, exc, 'stack');
      if (JS_IsException(stack) = 0) and not JS_IsUndefined(stack) then
      begin
        stackStr := JSValueToString(ctx, stack);
        if stackStr <> '' then
          excStr := excStr + #13#10 + stackStr;
        JS_FreeValue(ctx, stack);
      end;
    end;

    JS_FreeValue(ctx, exc);
    Result := excStr;
  end;
end;

end.

