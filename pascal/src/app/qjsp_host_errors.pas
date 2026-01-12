unit qjsp_host_errors;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, quickjs_types, quickjs_core, qjs_log;

const
  QJSP_E_SPAWN_DISABLED = 'QJSP_E_SPAWN_DISABLED';
  QJSP_E_SPAWN_CWD_DENIED = 'QJSP_E_SPAWN_CWD_DENIED';
  QJSP_E_SPAWN_CONCURRENCY_LIMIT = 'QJSP_E_SPAWN_CONCURRENCY_LIMIT';
  QJSP_E_HTTP_DISABLED = 'QJSP_E_HTTP_DISABLED';
  QJSP_E_HTTP_HOST_DENIED = 'QJSP_E_HTTP_HOST_DENIED';
  QJSP_E_HTTP_LIMIT_DENIED = 'QJSP_E_HTTP_LIMIT_DENIED';
  QJSP_E_FSWATCH_DISABLED = 'QJSP_E_FSWATCH_DISABLED';
  QJSP_E_FSWATCH_ROOT_DENIED = 'QJSP_E_FSWATCH_ROOT_DENIED';
  QJSP_E_FSWATCH_LIMIT = 'QJSP_E_FSWATCH_LIMIT';
  QJSP_E_MODULE_LOAD_FAILED = 'QJSP_E_MODULE_LOAD_FAILED';
  QJSP_E_MODULE_CIRCULAR_IMPORT = 'QJSP_E_MODULE_CIRCULAR_IMPORT';
  QJSP_E_MODULE_INVALID_PATH = 'QJSP_E_MODULE_INVALID_PATH';
  QJSP_E_MODULE_MISSING_LIBRARY_MOUNT = 'QJSP_E_MODULE_MISSING_LIBRARY_MOUNT';

function QjspCreateHostError(ctx: PJSContext; const code: string; const msg: string): JSValue;
function QjspThrowHostError(ctx: PJSContext; const code: string; const msg: string;
  const logTag: string = 'boundary'; const logLevel: TLogLevel = llWarn): JSValue;
procedure QjspSetHostException(ctx: PJSContext; const code: string; const msg: string;
  const logTag: string = 'boundary'; const logLevel: TLogLevel = llWarn);

implementation

function QjspCreateHostError(ctx: PJSContext; const code: string; const msg: string): JSValue;
var
  globalObj: JSValue;
  errCtor: JSValue;
  errArgs: array[0..0] of JSValue;
  errVal: JSValue;
begin
  Result := JS_EXCEPTION;
  if ctx = nil then
    Exit;

  globalObj := JS_GetGlobalObject(ctx);
  errCtor := JS_GetPropertyStr(ctx, globalObj, PChar('Error'));
  JS_FreeValue(ctx, globalObj);

  errArgs[0] := JS_NewString(ctx, PChar(msg));
  errVal := JS_CallConstructor(ctx, errCtor, 1, @errArgs[0]);
  JS_FreeValue(ctx, errArgs[0]);
  JS_FreeValue(ctx, errCtor);

  if JS_IsException(errVal) <> 0 then
  begin
    Result := errVal;
    Exit;
  end;

  JS_DefinePropertyValueStr(ctx, errVal, PChar('code'), JS_NewString(ctx, PChar(code)), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, errVal, PChar('name'), JS_NewString(ctx, PChar('HostError')), JS_PROP_C_W_E);

  Result := errVal;
end;

function QjspThrowHostError(ctx: PJSContext; const code: string; const msg: string;
  const logTag: string; const logLevel: TLogLevel): JSValue;
var
  errVal: JSValue;
begin
  if (logTag <> '') and (logLevel <> llOff) then
    qjs_log.LogMsg(logLevel, logTag, code + ': ' + msg);

  errVal := QjspCreateHostError(ctx, code, msg);
  if JS_IsException(errVal) <> 0 then
    Exit(errVal);

  Result := JS_Throw(ctx, errVal);
end;

procedure QjspSetHostException(ctx: PJSContext; const code: string; const msg: string;
  const logTag: string; const logLevel: TLogLevel);
begin
  QjspThrowHostError(ctx, code, msg, logTag, logLevel);
end;

end.
