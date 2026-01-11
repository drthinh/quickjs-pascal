unit quickjs_debug;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, SysUtils, quickjs_types, quickjs_core, quickjs_std, qjs_log;

// Convert a JSValue to Pascal string (empty string if conversion fails)
function JSValueToString(ctx: PJSContext; v: JSValueConst): string;

// Get last exception's message/stack/info strings
function JS_GetErrorMessage(ctx: PJSContext): string;
function JS_GetErrorStack(ctx: PJSContext): string;
function JS_GetErrorInfo(ctx: PJSContext): string;
procedure JS_PrintError(ctx: PJSContext);

// Promise rejection tracking helpers
procedure JS_InstallStdPromiseRejectionTracker(rt: PJSRuntime);
procedure JS_InstallLoggingPromiseRejectionTracker(rt: PJSRuntime);

implementation

function GetMessageFromException(ctx: PJSContext; exc: JSValueConst): string;
var
  prop: JSValue;
begin
  Result := '';
  prop := JS_GetPropertyStr(ctx, exc, 'message');
  if JS_IsException(prop) = 0 then
  begin
    if JS_IsUndefined(prop) = 0 then
      Result := JSValueToString(ctx, prop)
    else
      Result := JSValueToString(ctx, exc);
    JS_FreeValue(ctx, prop);
  end;
end;

function GetStackFromException(ctx: PJSContext; exc: JSValueConst): string;
var
  stackVal: JSValue;
begin
  Result := '';
  stackVal := JS_GetPropertyStr(ctx, exc, 'stack');
  if JS_IsException(stackVal) = 0 then
  begin
    if JS_IsUndefined(stackVal) = 0 then
      Result := JSValueToString(ctx, stackVal);
    JS_FreeValue(ctx, stackVal);
  end;
end;

function JSValueToString(ctx: PJSContext; v: JSValueConst): string;
var
  cstr: PChar;
begin
  Result := '';
  cstr := JS_ToCString(ctx, v);
  if cstr <> nil then
  begin
    Result := StrPas(cstr);
    JS_FreeCString(ctx, cstr);
  end;
end;

function JS_GetErrorMessage(ctx: PJSContext): string;
var
  exc: JSValue;
begin
  Result := '';
  exc := JS_GetException(ctx);
  if JS_IsException(exc) <> 0 then
    Exit;

  Result := GetMessageFromException(ctx, exc);
  JS_FreeValue(ctx, exc);
end;

function JS_GetErrorStack(ctx: PJSContext): string;
var
  exc: JSValue;
begin
  Result := '';
  exc := JS_GetException(ctx);
  if JS_IsException(exc) <> 0 then
    Exit;

  Result := GetStackFromException(ctx, exc);
  JS_FreeValue(ctx, exc);
end;

function JS_GetErrorInfo(ctx: PJSContext): string;
var
  exc: JSValue;
  msg, st: string;
begin
  exc := JS_GetException(ctx);
  if JS_IsException(exc) <> 0 then
    Exit('');

  msg := GetMessageFromException(ctx, exc);
  st := GetStackFromException(ctx, exc);
  JS_FreeValue(ctx, exc);

  if (st <> '') and (Pos(msg, st) = 0) then
    Result := msg + LineEnding + st
  else if msg <> '' then
    Result := msg
  else
    Result := st;
end;

procedure JS_PrintError(ctx: PJSContext);
var
  info: string;
begin
  info := JS_GetErrorInfo(ctx);
  if info <> '' then
    WriteLn(info)
  else
    js_std_dump_error(ctx);
end;

// ==== Promise rejection trackers ====
procedure LoggingPromiseRejectionTracker(ctx: PJSContext; promise: JSValueConst; reason: JSValueConst; is_handled: cbool; opaque: pointer); cdecl;
var
  msg, st: string;
  stackVal: JSValue;
begin
  if Ord(is_handled) <> 0 then
    Exit; // ignore handled rejections

  msg := JSValueToString(ctx, reason);
  st := '';
  // try to read reason.stack if available
  if JS_IsObject(reason) <> 0 then
  begin
    stackVal := JS_GetPropertyStr(ctx, reason, 'stack');
    if JS_IsException(stackVal) = 0 then
    begin
      st := JSValueToString(ctx, stackVal);
      JS_FreeValue(ctx, stackVal);
    end;
  end;

  qjs_log.LogMsg(llError, 'promise', 'Unhandled Promise rejection: ' + msg);
  if st <> '' then
    qjs_log.LogMsg(llError, 'promise', st);
end;

procedure JS_InstallStdPromiseRejectionTracker(rt: PJSRuntime);
begin
  JS_SetHostPromiseRejectionTracker(rt, @js_std_promise_rejection_tracker, nil);
end;

procedure JS_InstallLoggingPromiseRejectionTracker(rt: PJSRuntime);
begin
  JS_SetHostPromiseRejectionTracker(rt, @LoggingPromiseRejectionTracker, nil);
end;

end.


