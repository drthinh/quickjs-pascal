unit quickjs;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, SysUtils;

const
  {$IFDEF WINDOWS}
  libqjs = 'libqjs.dll';
  {$ELSE}
  libqjs = 'libqjs.so';
  {$ENDIF}

  // Tags
  JS_TAG_FIRST = -9;
  JS_TAG_BIG_INT = -9;
  JS_TAG_SYMBOL = -8;
  JS_TAG_STRING = -7;
  JS_TAG_MODULE = -3;
  JS_TAG_FUNCTION_BYTECODE = -2;
  JS_TAG_OBJECT = -1;
  JS_TAG_INT = 0;
  JS_TAG_BOOL = 1;
  JS_TAG_NULL = 2;
  JS_TAG_UNDEFINED = 3;
  JS_TAG_UNINITIALIZED = 4;
  JS_TAG_CATCH_OFFSET = 5;
  JS_TAG_EXCEPTION = 6;
  JS_TAG_SHORT_BIG_INT = 7;
  JS_TAG_FLOAT64 = 8;

  // Eval flags
  JS_EVAL_TYPE_GLOBAL = 0;
  JS_EVAL_TYPE_MODULE = 1;
  JS_EVAL_TYPE_DIRECT = 2;
  JS_EVAL_TYPE_INDIRECT = 3;
  JS_EVAL_TYPE_MASK = 3;
  JS_EVAL_FLAG_STRICT = 8;
  JS_EVAL_FLAG_STRIP = 16;
  JS_EVAL_FLAG_COMPILE_ONLY = 32;
  JS_EVAL_FLAG_BACKTRACE_BARRIER = 64;
  JS_EVAL_FLAG_ASYNC = 128;

  // Read object flags
  JS_READ_OBJ_BYTECODE = 1;
  JS_READ_OBJ_REFERENCE = 2;
  JS_READ_OBJ_ROM_DATA = 4;

  // Write object flags
  JS_WRITE_OBJ_BYTECODE = 1;
  JS_WRITE_OBJ_REFERENCE = 2;
  JS_WRITE_OBJ_BSWAP = 4;
  JS_WRITE_OBJ_SAB = 8;
  JS_WRITE_OBJ_DEBUG = 16;

  // Property flags
  JS_PROP_CONFIGURABLE = 1;
  JS_PROP_WRITABLE = 2;
  JS_PROP_ENUMERABLE = 4;
  JS_PROP_C_W_E = 7;  // JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE or JS_PROP_ENUMERABLE
  JS_PROP_LENGTH = 8;
  JS_PROP_TMASK = 48;  // 3 shl 4
  JS_PROP_NORMAL = 0;
  JS_PROP_GETSET = 16;  // 1 shl 4
  JS_PROP_VARREF = 32;  // 2 shl 4
  JS_PROP_AUTOINIT = 48;  // 3 shl 4
  JS_PROP_HAS_SHIFT = 8;
  JS_PROP_HAS_GET = 256;  // 1 shl 8
  JS_PROP_HAS_SET = 512;  // 1 shl 9
  JS_PROP_HAS_CONFIGURABLE = 1024;  // 1 shl 10
  JS_PROP_HAS_ENUMERABLE = 2048;  // 1 shl 11
  JS_PROP_HAS_WRITABLE = 4096;  // 1 shl 12
  JS_PROP_HAS_VALUE = 8192;  // 1 shl 13

  // Class flags (simplified - only common ones)
  JS_CLASS_HAS_PRIVATE = 1;
  JS_CLASS_HAS_BYTECODE_FUNCTION = 2;
  JS_CLASS_HAS_NAME = 4;
  JS_CLASS_IS_SCRIPTED = 8;
  JS_CLASS_IS_EXOTIC = 16;
  JS_CLASS_IS_GENERIC_FUNCTION = 32;
  JS_CLASS_IS_FUNCTION = 64;
  JS_CLASS_IS_CONSTRUCTOR = 128;

type
  // Basic types
  JSRuntime = record end;
  JSContext = record end;
  JSObject = record end;
  JSClass = record end;
  JSClassID = cuint32;
  JSAtom = cuint32;
  JSModuleDef = record end;

  // Pointer types
  PJSRuntime = ^JSRuntime;
  PJSContext = ^JSContext;
  PJSObject = ^JSObject;
  PJSClass = ^JSClass;
  PJSModuleDef = ^JSModuleDef;

  // JSValue - 16 bytes struct (non-NAN_BOXING, like C when JS_NAN_BOXING=0)
  JSValueUnion = record
    case cint of
      0: (int32: cint32);
      1: (float64: cdouble);
      2: (ptr: pointer);
  end;

  JSValue = record
    u: JSValueUnion; // 8 bytes
    tag: cint64;     // 8 bytes
  end;

  JSValueConst = JSValue;
  PJSValue = ^JSValue;
  PJSValueConst = ^JSValueConst;

  // Pointer types for primitive types (needed for callback types)
  Pcint = ^cint;
  Pcint32 = ^cint32;
  Pcint64 = ^cint64;
  Pcuint32 = ^cuint32;
  Pcuint64 = ^cuint64;
  Pcdouble = ^cdouble;
  Pcsize_t = ^csize_t;
  Pcuint8 = ^cuint8;
  PJSClassID = ^JSClassID;
  PPJSContext = ^PJSContext;

  // Forward declarations for types defined later
  JSPropertyEnum = record
    is_enumerable: cint;
    atom: JSAtom;
  end;
  PJSPropertyEnum = ^JSPropertyEnum;
  PPJSPropertyEnum = ^PJSPropertyEnum;

  JSModuleInitFunc = function(ctx: PJSContext; m: PJSModuleDef): cint; cdecl;

  // Callback types
  JSFreeArrayBufferDataFunc = procedure(rt: PJSRuntime; opaque: pointer; ptr: pointer); cdecl;
  JSInterruptHandler = function(rt: PJSRuntime; opaque: pointer): cint; cdecl;
  JSModuleNormalizeFunc = function(ctx: PJSContext; module_base_name: PChar; module_name: PChar; opaque: pointer): PChar; cdecl;
  JSModuleLoaderFunc = function(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;
  JSCFunction = function(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
  JSCFunctionMagic = function(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst; magic: cint): JSValue; cdecl;
  JSCFunctionData = function(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst; magic: cint; data: PJSValue): JSValue; cdecl;
  JSFinalizer = procedure(rt: PJSRuntime; val: JSValue); cdecl;
  JSGCMarkFunc = procedure(rt: PJSRuntime; val: JSValue; mark_func: pointer); cdecl;
  JSHasPropertyFunc = function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom): cint; cdecl;
  JSGetPropertyFunc = function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom; receiver: JSValueConst): JSValue; cdecl;
  JSSetPropertyFunc = function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom; val: JSValueConst; receiver: JSValueConst; flags: cint): cint; cdecl;
  JSDeletePropertyFunc = function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom): cint; cdecl;
  JSGetOwnPropertyNamesFunc = function(ctx: PJSContext; ptab: Pcint; plen: Pcuint32; obj: JSValueConst): cint; cdecl;
  JSGetOwnPropertyFunc = function(ctx: PJSContext; desc: pointer; obj: JSValueConst; atom: JSAtom): cint; cdecl;
  JSCallConstructorFunc = function(ctx: PJSContext; func_obj: JSValueConst; new_target: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
  JSHasInstanceFunc = function(ctx: PJSContext; func_obj: JSValueConst; val: JSValueConst): cint; cdecl;
  JSCallFunc = function(ctx: PJSContext; func_obj: JSValueConst; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
  JSGetArrayBufferFunc = function(ctx: PJSContext; opaque: pointer; psize: Pcsize_t): pointer; cdecl;
  JSIsHTMLDDA = function(ctx: PJSContext; obj: JSValueConst): cint; cdecl;

// Special value constructors (JS_UNDEFINED, JS_NULL, ...)
function JS_UNDEFINED: JSValue; inline;
function JS_NULL: JSValue; inline;
function JS_FALSE: JSValue; inline;
function JS_TRUE: JSValue; inline;
function JS_EXCEPTION: JSValue; inline;
function JS_UNINITIALIZED: JSValue; inline;

  // Runtime functions
function JS_NewRuntime: PJSRuntime; cdecl; external libqjs;
procedure JS_FreeRuntime(rt: PJSRuntime); cdecl; external libqjs;
function JS_NewContext(rt: PJSRuntime): PJSContext; cdecl; external libqjs;
procedure JS_FreeContext(ctx: PJSContext); cdecl; external libqjs;
function JS_GetRuntime(ctx: PJSContext): PJSRuntime; cdecl; external libqjs;

// Memory management
procedure JS_SetRuntimeOpaque(rt: PJSRuntime; opaque: pointer); cdecl; external libqjs;
function JS_GetRuntimeOpaque(rt: PJSRuntime): pointer; cdecl; external libqjs;
procedure JS_SetContextOpaque(ctx: PJSContext; opaque: pointer); cdecl; external libqjs;
function JS_GetContextOpaque(ctx: PJSContext): pointer; cdecl; external libqjs;

// Value operations
// JS_NewBool / JS_NewInt32 / JS_NewInt64 / JS_NewFloat64 là static inline trong quickjs.h,
// nên KHÔNG được export từ DLL. Ta tự implement trong Pascal cho đúng layout JSValue.
function JS_NewInt32(ctx: PJSContext; val: cint32): JSValue; cdecl;
function JS_NewInt64(ctx: PJSContext; val: cint64): JSValue; cdecl;
function JS_NewBool(ctx: PJSContext; val: cint): JSValue; cdecl;
function JS_NewFloat64(ctx: PJSContext; val: cdouble): JSValue; cdecl;
function JS_NewString(ctx: PJSContext; str: PChar): JSValue; cdecl;
function JS_NewStringLen(ctx: PJSContext; str: PChar; len: csize_t): JSValue; cdecl; external libqjs;
function JS_NewObject(ctx: PJSContext): JSValue; cdecl; external libqjs;
function JS_NewObjectProto(ctx: PJSContext; proto: JSValueConst): JSValue; cdecl; external libqjs;
function JS_NewObjectClass(ctx: PJSContext; class_id: JSClassID): JSValue; cdecl; external libqjs;
function JS_NewArray(ctx: PJSContext): JSValue; cdecl; external libqjs;
function JS_NewPromiseCapability(ctx: PJSContext; resolving_funcs: PJSValue): JSValue; cdecl; external libqjs;

procedure JS_FreeValue(ctx: PJSContext; v: JSValue); cdecl; external libqjs;
procedure JS_FreeValueRT(rt: PJSRuntime; v: JSValue); cdecl; external libqjs;

function JS_DupValue(ctx: PJSContext; v: JSValueConst): JSValue; cdecl; external libqjs;
function JS_DupValueRT(rt: PJSRuntime; v: JSValueConst): JSValue; cdecl; external libqjs;

// Value checks
  function JS_IsUndefined(v: JSValueConst): cint; cdecl;
  function JS_IsNull(v: JSValueConst): cint; cdecl;
  function JS_IsBool(v: JSValueConst): cint; cdecl;
  function JS_IsNumber(v: JSValueConst): cint; cdecl;
  function JS_IsBigInt(v: JSValueConst): cint; cdecl;
  function JS_IsString(v: JSValueConst): cint; cdecl;
  function JS_IsObject(v: JSValueConst): cint; cdecl;
  function JS_IsArray(ctx: PJSContext; v: JSValueConst): cint; cdecl; external libqjs;
  function JS_IsException(v: JSValueConst): cint; cdecl;
  function JS_IsUninitialized(v: JSValueConst): cint; cdecl;
function JS_IsFunction(ctx: PJSContext; v: JSValueConst): cint; cdecl; external libqjs;
function JS_IsConstructor(ctx: PJSContext; v: JSValueConst): cint; cdecl; external libqjs;

// Value conversions
function JS_ToBool(ctx: PJSContext; val: JSValueConst): cint; cdecl; external libqjs;
function JS_ToInt32(ctx: PJSContext; pres: Pcint32; val: JSValueConst): cint; cdecl; external libqjs;
function JS_ToInt64(ctx: PJSContext; pres: Pcint64; val: JSValueConst): cint; cdecl; external libqjs;
function JS_ToIndex(ctx: PJSContext; plen: Pcuint64; val: JSValueConst): cint; cdecl; external libqjs;
function JS_ToFloat64(ctx: PJSContext; pres: Pcdouble; val: JSValueConst): cint; cdecl; external libqjs;
// In quickjs.h only JS_ToCStringLen2 is exported; JS_ToCStringLen / JS_ToCString are inline wrappers.
function JS_ToCStringLen2(ctx: PJSContext; plen: Pcsize_t; val: JSValueConst; cesu8: cint): PChar; cdecl; external libqjs;
function JS_ToCStringLen(ctx: PJSContext; plen: Pcsize_t; val: JSValueConst): PChar; cdecl;
function JS_ToCString(ctx: PJSContext; val: JSValueConst): PChar; cdecl;
procedure JS_FreeCString(ctx: PJSContext; ptr: PChar); cdecl; external libqjs;

// Object operations
function JS_GetProperty(ctx: PJSContext; this_obj: JSValueConst; prop: JSAtom): JSValue; cdecl; external libqjs;
function JS_GetPropertyStr(ctx: PJSContext; this_obj: JSValueConst; prop: PChar): JSValue; cdecl; external libqjs;
function JS_GetPropertyUint32(ctx: PJSContext; this_obj: JSValueConst; idx: cuint32): JSValue; cdecl; external libqjs;
function JS_SetProperty(ctx: PJSContext; this_obj: JSValueConst; prop: JSAtom; val: JSValueConst): cint; cdecl; external libqjs;
function JS_SetPropertyStr(ctx: PJSContext; this_obj: JSValueConst; prop: PChar; val: JSValueConst): cint; cdecl; external libqjs;
function JS_SetPropertyUint32(ctx: PJSContext; this_obj: JSValueConst; idx: cuint32; val: JSValueConst): cint; cdecl; external libqjs;
function JS_DefineProperty(ctx: PJSContext; this_obj: JSValueConst; prop: JSAtom; val: JSValueConst; getter: JSValueConst; setter: JSValueConst; flags: cint): cint; cdecl; external libqjs;
function JS_DefinePropertyValue(ctx: PJSContext; this_obj: JSValueConst; prop: JSAtom; val: JSValueConst; flags: cint): cint; cdecl; external libqjs;
function JS_DefinePropertyValueStr(ctx: PJSContext; this_obj: JSValueConst; prop: PChar; val: JSValueConst; flags: cint): cint; cdecl; external libqjs;
function JS_DefinePropertyValueUint32(ctx: PJSContext; this_obj: JSValueConst; idx: cuint32; val: JSValueConst; flags: cint): cint; cdecl; external libqjs;
function JS_DeleteProperty(ctx: PJSContext; obj: JSValueConst; prop: JSAtom; flags: cint): cint; cdecl; external libqjs;
function JS_DeletePropertyStr(ctx: PJSContext; obj: JSValueConst; prop: PChar; flags: cint): cint; cdecl; external libqjs;
function JS_DeletePropertyUint32(ctx: PJSContext; obj: JSValueConst; idx: cuint32; flags: cint): cint; cdecl; external libqjs;
function JS_HasProperty(ctx: PJSContext; obj: JSValueConst; prop: JSAtom): cint; cdecl; external libqjs;
function JS_HasPropertyStr(ctx: PJSContext; obj: JSValueConst; prop: PChar): cint; cdecl; external libqjs;
function JS_HasPropertyUint32(ctx: PJSContext; obj: JSValueConst; idx: cuint32): cint; cdecl; external libqjs;
function JS_GetOwnPropertyNames(ctx: PJSContext; ptab: PPJSPropertyEnum; plen: Pcuint32; obj: JSValueConst; flags: cint): cint; cdecl; external libqjs;
function JS_GetOwnProperty(ctx: PJSContext; desc: pointer; obj: JSValueConst; prop: JSAtom): cint; cdecl; external libqjs;

// Array operations
function JS_GetLength(ctx: PJSContext; obj: JSValueConst): cint; cdecl; external libqjs;
function JS_SetLength(ctx: PJSContext; obj: JSValueConst; len: cuint32): cint; cdecl; external libqjs;

// ArrayBuffer operations
function JS_NewArrayBuffer(ctx: PJSContext; buf: Pcuint8; len: csize_t; free_func: JSFreeArrayBufferDataFunc; opaque: pointer; is_shared: cint): JSValue; cdecl; external libqjs;
function JS_NewArrayBufferCopy(ctx: PJSContext; buf: Pcuint8; len: csize_t): JSValue; cdecl; external libqjs;
function JS_GetArrayBuffer(ctx: PJSContext; psize: Pcsize_t; obj: JSValueConst): Pcuint8; cdecl; external libqjs;
function JS_IsArrayBuffer(obj: JSValueConst): cint; cdecl; external libqjs;
procedure JS_DetachArrayBuffer(ctx: PJSContext; obj: JSValueConst); cdecl; external libqjs;

// TypedArray operations
function JS_GetUint8Array(ctx: PJSContext; psize: Pcsize_t; obj: JSValueConst): Pcuint8; cdecl; external libqjs;
function JS_GetTypedArrayBuffer(ctx: PJSContext; obj: JSValueConst; pbyte_offset: Pcsize_t; pbyte_length: Pcsize_t; pbytes_per_element: Pcsize_t): JSValue; cdecl; external libqjs;

// Function operations
function JS_Call(ctx: PJSContext; func_obj: JSValueConst; this_obj: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl; external libqjs;
function JS_Invoke(ctx: PJSContext; this_val: JSValueConst; atom: JSAtom; argc: cint; argv: PJSValueConst): JSValue; cdecl; external libqjs;
function JS_CallConstructor(ctx: PJSContext; func_obj: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl; external libqjs;
function JS_CallConstructor2(ctx: PJSContext; func_obj: JSValueConst; new_target: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl; external libqjs;
function JS_DetectModule(const input: PChar; input_len: csize_t): cint; cdecl; external libqjs;

// Eval
function JS_Eval(ctx: PJSContext; input: PChar; input_len: csize_t; filename: PChar; eval_flags: cint): JSValue; cdecl; external libqjs;
function JS_EvalFunction(ctx: PJSContext; func_obj: JSValueConst): JSValue; cdecl; external libqjs;

// Exception handling
function JS_GetException(ctx: PJSContext): JSValue; cdecl; external libqjs;
function JS_IsError(ctx: PJSContext; val: JSValueConst): cint; cdecl; external libqjs;
procedure JS_ResetUncatchableException(ctx: PJSContext); cdecl; external libqjs;

// Atom operations
function JS_NewAtom(ctx: PJSContext; str: PChar): JSAtom; cdecl; external libqjs;
function JS_NewAtomLen(ctx: PJSContext; str: PChar; len: csize_t): JSAtom; cdecl; external libqjs;
function JS_NewAtomUInt32(ctx: PJSContext; n: cuint32): JSAtom; cdecl; external libqjs;
function JS_DupAtom(ctx: PJSContext; v: JSAtom): JSAtom; cdecl; external libqjs;
procedure JS_FreeAtom(ctx: PJSContext; v: JSAtom); cdecl; external libqjs;
procedure JS_FreeAtomRT(rt: PJSRuntime; v: JSAtom); cdecl; external libqjs;
function JS_AtomToValue(ctx: PJSContext; atom: JSAtom): JSValue; cdecl; external libqjs;
function JS_AtomToCString(ctx: PJSContext; atom: JSAtom): PChar; cdecl; external libqjs;

// Class operations
function JS_NewClassID(pclass_id: PJSClassID): JSClassID; cdecl; external libqjs;
function JS_NewClass(rt: PJSRuntime; class_id: JSClassID; class_def: PJSClass): cint; cdecl; external libqjs;
function JS_IsInstanceOf(ctx: PJSContext; obj: JSValueConst; class_id: JSClassID): cint; cdecl; external libqjs;
function JS_GetClassID(obj: JSValueConst; pclass_id: PJSClassID): cint; cdecl; external libqjs;
function JS_GetOpaque(obj: JSValueConst; class_id: JSClassID): pointer; cdecl; external libqjs;
function JS_GetOpaque2(ctx: PJSContext; obj: JSValueConst; class_id: JSClassID): pointer; cdecl; external libqjs;
function JS_SetOpaque(obj: JSValue; opaque: pointer): cint; cdecl; external libqjs;
function JS_GetClassProto(ctx: PJSContext; class_id: JSClassID): JSValue; cdecl; external libqjs;
function JS_SetClassProto(ctx: PJSContext; class_id: JSClassID; obj: JSValueConst): cint; cdecl; external libqjs;

// C function registration
// Chỉ JS_NewCFunction2 được export từ DLL; JS_NewCFunction là inline trong quickjs.h,
// nên ta tự wrap lại bằng Pascal.
function JS_NewCFunction(ctx: PJSContext; func: JSCFunction; name: PChar; length: cint): JSValue; cdecl;
function JS_NewCFunction2(ctx: PJSContext; func: JSCFunction; name: PChar; length: cint; cproto: cint; magic: cint): JSValue; cdecl; external libqjs;
function JS_NewCFunctionData(ctx: PJSContext; func: JSCFunctionData; length: cint; magic: cint; data_len: cint; data: PJSValue): JSValue; cdecl; external libqjs;
function JS_SetConstructor(ctx: PJSContext; func_obj: JSValueConst; proto: JSValueConst): cint; cdecl; external libqjs;
function JS_SetConstructorBit(ctx: PJSContext; func_obj: JSValueConst; val: cint): cint; cdecl; external libqjs;

// Module operations
function JS_NewCModule(ctx: PJSContext; name_str: PChar; func: JSModuleInitFunc): PJSModuleDef; cdecl; external libqjs;
function JS_AddModuleExport(ctx: PJSContext; m: PJSModuleDef; name_str: PChar): cint; cdecl; external libqjs;
function JS_AddModuleExportList(ctx: PJSContext; m: PJSModuleDef; tab: pointer; len: cint): cint; cdecl; external libqjs;
function JS_SetModuleLoaderFunc(rt: PJSRuntime; module_normalize: JSModuleNormalizeFunc; module_loader: JSModuleLoaderFunc; opaque: pointer): cint; cdecl; external libqjs;
function JS_GetImportMeta(ctx: PJSContext; m: PJSModuleDef): JSValue; cdecl; external libqjs;
function JS_GetModuleName(ctx: PJSContext; m: PJSModuleDef): JSValue; cdecl; external libqjs;

// Bytecode operations
function JS_ReadObject(ctx: PJSContext; buf: Pcuint8; buf_len: csize_t; flags: cint): JSValue; cdecl; external libqjs;
function JS_WriteObject(ctx: PJSContext; psize: Pcsize_t; obj: JSValueConst; flags: cint): Pcuint8; cdecl; external libqjs;

// Runtime configuration / Promise helpers
procedure JS_SetMaxStackSize(rt: PJSRuntime; stack_size: csize_t); cdecl; external libqjs;
procedure JS_SetMemoryLimit(rt: PJSRuntime; limit: csize_t); cdecl; external libqjs;
procedure JS_SetGCThreshold(rt: PJSRuntime; gc_threshold: csize_t); cdecl; external libqjs;
function JS_NewRuntime2(opaque_class: PJSClass; opaque: pointer): PJSRuntime; cdecl; external libqjs;
procedure JS_RunGC(rt: PJSRuntime); cdecl; external libqjs;
function JS_IsLiveObject(rt: PJSRuntime; obj: JSValueConst): cint; cdecl; external libqjs;
procedure JS_SetInterruptHandler(rt: PJSRuntime; interrupt_handler: JSInterruptHandler; opaque: pointer); cdecl; external libqjs;
procedure JS_UpdateStackTop(rt: PJSRuntime); cdecl; external libqjs;
function JS_ExecutePendingJob(rt: PJSRuntime; pctx: PPJSContext): cint; cdecl; external libqjs;

// Promise helpers
type
  JSPromiseStateEnum = (
    JS_PROMISE_NOT_A_PROMISE = -1,
    JS_PROMISE_PENDING       = 0,
    JS_PROMISE_FULFILLED,
    JS_PROMISE_REJECTED
  );

function JS_PromiseState(ctx: PJSContext; promise: JSValueConst): JSPromiseStateEnum; cdecl; external libqjs;
function JS_PromiseResult(ctx: PJSContext; promise: JSValueConst): JSValue; cdecl; external libqjs;
function JS_IsPromise(val: JSValueConst): cint; cdecl; external libqjs;

// String operations
function JS_ToString(ctx: PJSContext; val: JSValueConst): JSValue; cdecl; external libqjs;
function JS_ToPropertyKey(ctx: PJSContext; val: JSValueConst): JSValue; cdecl; external libqjs;
function JS_ParseJSON(ctx: PJSContext; buf: PChar; buf_len: csize_t; filename: PChar): JSValue; cdecl; external libqjs;
function JS_JSONStringify(ctx: PJSContext; obj: JSValueConst; replacer: JSValueConst; space0: JSValueConst): JSValue; cdecl; external libqjs;

// Global object
function JS_GetGlobalObject(ctx: PJSContext): JSValue; cdecl; external libqjs;

// Version
function JS_GetVersion: PChar; cdecl; external libqjs;

// Memory management
procedure js_free(ctx: PJSContext; ptr: pointer); cdecl; external libqjs;
procedure js_free_rt(rt: PJSRuntime; ptr: pointer); cdecl; external libqjs;

// Compression functions (miniz)
type
  mz_ulong = cuint32;
  Pmz_ulong = ^mz_ulong;
  mz_streamp = pointer;  // Opaque pointer for stream API

const
  MZ_OK = 0;
  MZ_STREAM_END = 1;
  MZ_NEED_DICT = 2;
  MZ_ERRNO = -1;
  MZ_STREAM_ERROR = -2;
  MZ_DATA_ERROR = -3;
  MZ_MEM_ERROR = -4;
  MZ_BUF_ERROR = -5;
  MZ_VERSION_ERROR = -6;
  MZ_DEFAULT_LEVEL = 6;
  MZ_DEFAULT_WINDOW_BITS = 15;
  MZ_DEFLATED = 8;

// Simple compression API
function mz_compress(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong): cint; cdecl; external libqjs;
function mz_compress2(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong; level: cint): cint; cdecl; external libqjs;
function mz_compressBound(source_len: mz_ulong): mz_ulong; cdecl; external libqjs;
function mz_uncompress(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong): cint; cdecl; external libqjs;
function mz_uncompress2(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; pSource_len: Pmz_ulong): cint; cdecl; external libqjs;

// Error throwing functions
function JS_ThrowTypeError(ctx: PJSContext; fmt: PChar): JSValue; cdecl; external libqjs;
function JS_ThrowReferenceError(ctx: PJSContext; fmt: PChar): JSValue; cdecl; external libqjs;
function JS_ThrowPlainError(ctx: PJSContext; fmt: PChar): JSValue; cdecl; external libqjs;

implementation

// ======== Helper functions for JSValue (non-NAN_BOXING, like quickjs.h) ========

function JS_VALUE_GET_TAG(const v: JSValueConst): cint; inline;
begin
  Result := cint(v.tag);
end;

// Special JSValue constructors (equivalents of JS_UNDEFINED, JS_NULL, ... macros)
function JS_UNDEFINED: JSValue; inline;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_UNDEFINED;
end;

function JS_NULL: JSValue; inline;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_NULL;
end;

function JS_FALSE: JSValue; inline;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_BOOL;
end;

function JS_TRUE: JSValue; inline;
begin
  Result.u.int32 := 1;
  Result.tag := JS_TAG_BOOL;
end;

function JS_EXCEPTION: JSValue; inline;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_EXCEPTION;
end;

function JS_UNINITIALIZED: JSValue; inline;
begin
  Result.u.int32 := 0;
  Result.tag := JS_TAG_UNINITIALIZED;
end;

// Value check helpers implemented in Pascal (these are inline in quickjs.h)
function JS_IsUndefined(v: JSValueConst): cint; cdecl;
begin
  if JS_VALUE_GET_TAG(v) = JS_TAG_UNDEFINED then
    Result := 1
  else
    Result := 0;
end;

function JS_IsNull(v: JSValueConst): cint; cdecl;
begin
  if JS_VALUE_GET_TAG(v) = JS_TAG_NULL then
    Result := 1
  else
    Result := 0;
end;

function JS_IsBool(v: JSValueConst): cint; cdecl;
begin
  if JS_VALUE_GET_TAG(v) = JS_TAG_BOOL then
    Result := 1
  else
    Result := 0;
end;

function JS_IsNumber(v: JSValueConst): cint; cdecl;
var
  tag: cint;
begin
  tag := JS_VALUE_GET_TAG(v);
  if (tag = JS_TAG_INT) or (tag >= JS_TAG_FLOAT64) then
    Result := 1
  else
    Result := 0;
end;

function JS_IsBigInt(v: JSValueConst): cint; cdecl;
var
  tag: cint;
begin
  tag := JS_VALUE_GET_TAG(v);
  if (tag = JS_TAG_BIG_INT) or (tag = JS_TAG_SHORT_BIG_INT) then
    Result := 1
  else
    Result := 0;
end;

function JS_IsString(v: JSValueConst): cint; cdecl;
begin
  if JS_VALUE_GET_TAG(v) = JS_TAG_STRING then
    Result := 1
  else
    Result := 0;
end;

function JS_IsObject(v: JSValueConst): cint; cdecl;
begin
  if JS_VALUE_GET_TAG(v) = JS_TAG_OBJECT then
    Result := 1
  else
    Result := 0;
end;

function JS_IsException(v: JSValueConst): cint; cdecl;
begin
  if JS_VALUE_GET_TAG(v) = JS_TAG_EXCEPTION then
    Result := 1
  else
    Result := 0;
end;

function JS_IsUninitialized(v: JSValueConst): cint; cdecl;
begin
  if JS_VALUE_GET_TAG(v) = JS_TAG_UNINITIALIZED then
    Result := 1
  else
    Result := 0;
end;

function JS_NewBool(ctx: PJSContext; val: cint): JSValue; cdecl;
begin
  // ctx is unused but kept for signature compatibility
  Result.tag := JS_TAG_BOOL;
  if val <> 0 then
    Result.u.int32 := 1
  else
    Result.u.int32 := 0;
end;

function JS_NewFloat64(ctx: PJSContext; val: cdouble): JSValue; cdecl;
begin
  // ctx is unused; matches non-NAN_BOXING layout: tag + float64
  Result.tag := JS_TAG_FLOAT64;
  Result.u.float64 := val;
end;

function JS_NewInt32(ctx: PJSContext; val: cint32): JSValue; cdecl;
begin
  // Dùng đúng tag INT như quickjs.h (non-NAN_BOXING)
  Result.tag := JS_TAG_INT;
  Result.u.int32 := val;
end;

function JS_NewInt64(ctx: PJSContext; val: cint64): JSValue; cdecl;
begin
  // Nếu trong khoảng Int32 thì dùng JS_TAG_INT, ngược lại dùng số thực 64-bit
  if (val >= Low(cint32)) and (val <= High(cint32)) then
  begin
    Result.tag := JS_TAG_INT;
    Result.u.int32 := cint32(val);
  end
  else
  begin
    Result := JS_NewFloat64(ctx, val);
  end;
end;

function JS_NewString(ctx: PJSContext; str: PChar): JSValue; cdecl;
var
  len: csize_t;
begin
  if str = nil then
    len := 0
  else
    len := csize_t(StrLen(str));
  Result := JS_NewStringLen(ctx, str, len);
end;

function JS_ToCStringLen(ctx: PJSContext; plen: Pcsize_t; val: JSValueConst): PChar; cdecl;
begin
  Result := JS_ToCStringLen2(ctx, plen, val, 0);
end;

function JS_ToCString(ctx: PJSContext; val: JSValueConst): PChar; cdecl;
begin
  Result := JS_ToCStringLen2(ctx, nil, val, 0);
end;

function JS_NewCFunction(ctx: PJSContext; func: JSCFunction; name: PChar; length: cint): JSValue; cdecl;
begin
  // cproto = 0 tương ứng JS_CFUNC_generic trong quickjs.h, magic = 0
  Result := JS_NewCFunction2(ctx, func, name, length, 0, 0);
end;

end.

