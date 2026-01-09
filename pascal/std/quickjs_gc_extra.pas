unit quickjs_gc_extra;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, quickjs_types, quickjs_core;

function JS_RegisterOpaqueClass(rt: PJSRuntime; var class_id: JSClassID;
  class_name: PChar; finalizer: JSClassFinalizer; gc_mark: JSClassGCMark = nil;
  exotic: PJSClassExoticMethods = nil; call: JSClassCall = nil): cint;

function JS_NewOpaqueObject(ctx: PJSContext; class_id: JSClassID; opaque: pointer): JSValue;

implementation

function JS_RegisterOpaqueClass(rt: PJSRuntime; var class_id: JSClassID;
  class_name: PChar; finalizer: JSClassFinalizer; gc_mark: JSClassGCMark;
  exotic: PJSClassExoticMethods; call: JSClassCall): cint;
var
  def: JSClassDef;
begin
  if class_id = 0 then
    JS_NewClassID(@class_id);
  def.class_name := class_name;
  def.finalizer := finalizer;
  def.gc_mark := gc_mark;
  def.call := call;
  def.exotic := exotic;
  Result := JS_NewClass(rt, class_id, @def);
end;

function JS_NewOpaqueObject(ctx: PJSContext; class_id: JSClassID; opaque: pointer): JSValue;
var
  obj: JSValue;
  r: cint;
begin
  obj := JS_NewObjectClass(ctx, class_id);
  if JS_IsException(obj) <> 0 then
  begin
    Result := obj;
    Exit;
  end;
  r := JS_SetOpaque(obj, opaque);
  if r <> 0 then
  begin
    JS_FreeValue(ctx, obj);
    Result := JS_EXCEPTION;
    Exit;
  end;
  Result := obj;
end;

end.
