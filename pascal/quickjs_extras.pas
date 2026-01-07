unit quickjs_extras;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, SysUtils, quickjs_types, quickjs_core;

function JS_IsNullOrUndefined(v: JSValueConst): boolean;
function JS_IsNullish(v: JSValueConst): boolean;
function JS_IsTruthy(ctx: PJSContext; v: JSValueConst): boolean;
function JS_IsFalsy(ctx: PJSContext; v: JSValueConst): boolean;

function JS_TryGetInt32(ctx: PJSContext; val: JSValueConst; out res: cint32): boolean;
function JS_TryGetInt64(ctx: PJSContext; val: JSValueConst; out res: cint64): boolean;
function JS_TryGetFloat64(ctx: PJSContext; val: JSValueConst; out res: cdouble): boolean;
function JS_TryGetBool(ctx: PJSContext; val: JSValueConst; out res: boolean): boolean;
function JS_TryGetString(ctx: PJSContext; val: JSValueConst; out s: string): boolean;

function JS_GetInt32Def(ctx: PJSContext; val: JSValueConst; default_value: cint32): cint32;
function JS_GetInt64Def(ctx: PJSContext; val: JSValueConst; default_value: cint64): cint64;
function JS_GetFloat64Def(ctx: PJSContext; val: JSValueConst; default_value: cdouble): cdouble;
function JS_GetBoolDef(ctx: PJSContext; val: JSValueConst; default_value: boolean): boolean;
function JS_GetStringDef(ctx: PJSContext; val: JSValueConst; const default_value: string): string;

implementation

function JS_IsNullOrUndefined(v: JSValueConst): boolean;
begin
  Result := (JS_IsNull(v) <> 0) or (JS_IsUndefined(v) <> 0);
end;

function JS_IsNullish(v: JSValueConst): boolean;
begin
  Result := JS_IsNullOrUndefined(v);
end;

function JS_IsTruthy(ctx: PJSContext; v: JSValueConst): boolean;
var
  b: cint;
begin
  b := JS_ToBool(ctx, v);
  if b < 0 then
    Result := False
  else
    Result := b <> 0;
end;

function JS_IsFalsy(ctx: PJSContext; v: JSValueConst): boolean;
begin
  Result := not JS_IsTruthy(ctx, v);
end;

function JS_TryGetInt32(ctx: PJSContext; val: JSValueConst; out res: cint32): boolean;
var
  tmp: cint32;
begin
  if JS_ToInt32(ctx, @tmp, val) = 0 then
  begin
    res := tmp;
    Result := True;
  end
  else
    Result := False;
end;

function JS_TryGetInt64(ctx: PJSContext; val: JSValueConst; out res: cint64): boolean;
var
  tmp: cint64;
begin
  if JS_ToInt64(ctx, @tmp, val) = 0 then
  begin
    res := tmp;
    Result := True;
  end
  else
    Result := False;
end;

function JS_TryGetFloat64(ctx: PJSContext; val: JSValueConst; out res: cdouble): boolean;
var
  tmp: cdouble;
begin
  if JS_ToFloat64(ctx, @tmp, val) = 0 then
  begin
    res := tmp;
    Result := True;
  end
  else
    Result := False;
end;

function JS_TryGetBool(ctx: PJSContext; val: JSValueConst; out res: boolean): boolean;
var
  tmp: cint;
begin
  tmp := JS_ToBool(ctx, val);
  if tmp < 0 then
  begin
    Result := False;
  end
  else
  begin
    res := tmp <> 0;
    Result := True;
  end;
end;

function JS_TryGetString(ctx: PJSContext; val: JSValueConst; out s: string): boolean;
var
  cstr: PChar;
begin
  s := '';
  cstr := JS_ToCString(ctx, val);
  if cstr = nil then
  begin
    Result := False;
    Exit;
  end;
  s := StrPas(cstr);
  JS_FreeCString(ctx, cstr);
  Result := True;
end;

function JS_GetInt32Def(ctx: PJSContext; val: JSValueConst; default_value: cint32): cint32;
var
  tmp: cint32;
begin
  if JS_TryGetInt32(ctx, val, tmp) then
    Result := tmp
  else
    Result := default_value;
end;

function JS_GetInt64Def(ctx: PJSContext; val: JSValueConst; default_value: cint64): cint64;
var
  tmp: cint64;
begin
  if JS_TryGetInt64(ctx, val, tmp) then
    Result := tmp
  else
    Result := default_value;
end;

function JS_GetFloat64Def(ctx: PJSContext; val: JSValueConst; default_value: cdouble): cdouble;
var
  tmp: cdouble;
begin
  if JS_TryGetFloat64(ctx, val, tmp) then
    Result := tmp
  else
    Result := default_value;
end;

function JS_GetBoolDef(ctx: PJSContext; val: JSValueConst; default_value: boolean): boolean;
var
  tmp: boolean;
begin
  if JS_TryGetBool(ctx, val, tmp) then
    Result := tmp
  else
    Result := default_value;
end;

function JS_GetStringDef(ctx: PJSContext; val: JSValueConst; const default_value: string): string;
var
  tmp: string;
begin
  if JS_TryGetString(ctx, val, tmp) then
    Result := tmp
  else
    Result := default_value;
end;

end.
