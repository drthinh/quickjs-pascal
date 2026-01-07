unit quickjs_types;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes;

const
  {$IFDEF WINDOWS}
  libqjs = 'libqjs.dll';
  {$ELSE}
  libqjs = 'libqjs.so';
  {$ENDIF}

  // Tags (non-NAN boxing layout)
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
  JS_PROP_C_W_E = 7; // configurable | writable | enumerable
  JS_PROP_LENGTH = 8;
  JS_PROP_TMASK = 48; // 3 shl 4
  JS_PROP_NORMAL = 0;
  JS_PROP_GETSET = 16; // 1 shl 4
  JS_PROP_VARREF = 32; // 2 shl 4
  JS_PROP_AUTOINIT = 48; // 3 shl 4
  JS_PROP_HAS_SHIFT = 8;
  JS_PROP_HAS_GET = 256; // 1 shl 8
  JS_PROP_HAS_SET = 512; // 1 shl 9
  JS_PROP_HAS_CONFIGURABLE = 1024; // 1 shl 10
  JS_PROP_HAS_ENUMERABLE = 2048; // 1 shl 11
  JS_PROP_HAS_WRITABLE = 4096; // 1 shl 12
  JS_PROP_HAS_VALUE = 8192; // 1 shl 13

  // Class flags (subset)
  JS_CLASS_HAS_PRIVATE = 1;
  JS_CLASS_HAS_BYTECODE_FUNCTION = 2;
  JS_CLASS_HAS_NAME = 4;
  JS_CLASS_IS_SCRIPTED = 8;
  JS_CLASS_IS_EXOTIC = 16;
  JS_CLASS_IS_GENERIC_FUNCTION = 32;
  JS_CLASS_IS_FUNCTION = 64;
  JS_CLASS_IS_CONSTRUCTOR = 128;

type
  // Basic opaque types
  JSRuntime = record end;
  JSContext = record end;
  JSObject = record end;
  JSClass = record end;
  JSModuleDef = record end;
  JSClassID = cuint32;
  JSAtom = cuint32;

  // Pointer aliases
  PJSRuntime = ^JSRuntime;
  PJSContext = ^JSContext;
  PJSObject = ^JSObject;
  PJSClass = ^JSClass;
  PJSModuleDef = ^JSModuleDef;

  // JSValue (non-NAN boxing layout)
  JSValueUnion = record
    case cint of
      0: (int32: cint32);
      1: (float64: cdouble);
      2: (ptr: pointer);
      3: (short_big_int: cint32);
  end;

  JSValue = record
    u: JSValueUnion; // 8 bytes
    tag: cint64;     // 8 bytes
  end;

  JSValueConst = JSValue;
  PJSValue = ^JSValue;
  PJSValueConst = ^JSValueConst;

  // Primitive pointer helpers
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

  // Property helpers
  JSPropertyEnum = record
    is_enumerable: cint;
    atom: JSAtom;
  end;
  PJSPropertyEnum = ^JSPropertyEnum;
  PPJSPropertyEnum = ^PJSPropertyEnum;

  JSPropertyDescriptor = record
    flags: cint;
    value: JSValue;
    getter: JSValue;
    setter: JSValue;
  end;
  PJSPropertyDescriptor = ^JSPropertyDescriptor;

  // Forward declarations of function pointer types
  JSFreeArrayBufferDataFunc = procedure(rt: PJSRuntime; opaque: pointer; ptr: pointer); cdecl;
  JSInterruptHandler = function(rt: PJSRuntime; opaque: pointer): cint; cdecl;
  JSModuleNormalizeFunc = function(ctx: PJSContext; module_base_name: PChar; module_name: PChar; opaque: pointer): PChar; cdecl;
  JSModuleLoaderFunc = function(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;
  JSModuleInitFunc = function(ctx: PJSContext; m: PJSModuleDef): cint; cdecl;
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

  // GC mark function used in class finalizers
  JS_MarkFunc = procedure(rt: PJSRuntime; gp: pointer); cdecl;

  // Class helpers
  JSClassExoticMethods = record
    get_own_property: function(ctx: PJSContext; desc: PJSPropertyDescriptor; obj: JSValueConst; atom: JSAtom): cint; cdecl;
    get_own_property_names: function(ctx: PJSContext; ptab: PPJSPropertyEnum; plen: Pcuint32; obj: JSValueConst): cint; cdecl;
    delete_property: function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom): cint; cdecl;
    define_own_property: function(ctx: PJSContext; this_obj: JSValueConst; atom: JSAtom; val: JSValueConst; getter: JSValueConst; setter: JSValueConst; flags: cint): cint; cdecl;
    has_property: function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom): cint; cdecl;
    get_property: function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom; receiver: JSValueConst): JSValue; cdecl;
    set_property: function(ctx: PJSContext; obj: JSValueConst; atom: JSAtom; value: JSValueConst; receiver: JSValueConst; flags: cint): cint; cdecl;
  end;
  PJSClassExoticMethods = ^JSClassExoticMethods;

  JSClassFinalizer = procedure(rt: PJSRuntime; val: JSValueConst); cdecl;
  JSClassGCMark = procedure(rt: PJSRuntime; val: JSValueConst; mark_func: JS_MarkFunc); cdecl;
  JSClassCall = function(ctx: PJSContext; func_obj: JSValueConst; this_val: JSValueConst; argc: cint; argv: PJSValueConst; flags: cint): JSValue; cdecl;

  JSClassDef = record
    class_name: PChar; // ASCII only
    finalizer: JSClassFinalizer;
    gc_mark: JSClassGCMark;
    call: JSClassCall;
    exotic: PJSClassExoticMethods;
  end;
  PJSClassDef = ^JSClassDef;

  // Promise helpers
  JSPromiseStateEnum = (
    JS_PROMISE_NOT_A_PROMISE = -1,
    JS_PROMISE_PENDING = 0,
    JS_PROMISE_FULFILLED,
    JS_PROMISE_REJECTED
  );

  JSPromiseHookType = (
    JS_PROMISE_HOOK_INIT,
    JS_PROMISE_HOOK_BEFORE,
    JS_PROMISE_HOOK_AFTER,
    JS_PROMISE_HOOK_RESOLVE
  );

  JSPromiseHook = procedure(ctx: PJSContext; hook_type: JSPromiseHookType; promise: JSValueConst; parent_promise: JSValueConst; opaque: pointer); cdecl;
  JSHostPromiseRejectionTracker = procedure(ctx: PJSContext; promise: JSValueConst; reason: JSValueConst; is_handled: cbool; opaque: pointer); cdecl;

// Inline helpers to match macros from quickjs.h
function JS_VALUE_GET_TAG(const v: JSValueConst): cint; inline;
function JS_VALUE_GET_INT(const v: JSValueConst): cint32; inline;
function JS_VALUE_GET_BOOL(const v: JSValueConst): cint32; inline;
function JS_VALUE_GET_FLOAT64(const v: JSValueConst): cdouble; inline;

implementation

function JS_VALUE_GET_TAG(const v: JSValueConst): cint; inline;
begin
  Result := cint(v.tag);
end;

function JS_VALUE_GET_INT(const v: JSValueConst): cint32; inline;
begin
  Result := v.u.int32;
end;

function JS_VALUE_GET_BOOL(const v: JSValueConst): cint32; inline;
begin
  Result := v.u.int32;
end;

function JS_VALUE_GET_FLOAT64(const v: JSValueConst): cdouble; inline;
begin
  Result := v.u.float64;
end;

end.



