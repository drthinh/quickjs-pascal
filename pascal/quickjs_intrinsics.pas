unit quickjs_intrinsics;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, quickjs_types;

const
  {$IFDEF WINDOWS}
  libqjs = 'libqjs.dll';
  {$ELSE}
  libqjs = 'libqjs.so';
  {$ENDIF}

// Intrinsic configuration API from quickjs.h
// These allow constructing a minimal JSContext and adding only the
// built-in objects you need.

// Create a JSContext without adding any intrinsics.
function JS_NewContextRaw(rt: PJSRuntime): PJSContext; cdecl; external libqjs;

// Add standard intrinsic objects to a context.
procedure JS_AddIntrinsicBaseObjects(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicDate(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicEval(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicRegExpCompiler(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicRegExp(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicJSON(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicProxy(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicMapSet(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicTypedArrays(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicPromise(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicBigInt(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicWeakRef(ctx: PJSContext); cdecl; external libqjs;
procedure JS_AddIntrinsicDOMException(ctx: PJSContext); cdecl; external libqjs;

// Performance API (performance.now etc.).
procedure JS_AddPerformance(ctx: PJSContext); cdecl; external libqjs;

implementation

end.
