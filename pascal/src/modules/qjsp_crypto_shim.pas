unit qjsp_crypto_shim;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, quickjs_types;

procedure RegisterCryptoModuleShims(ctx: PJSContext);

implementation

uses
  quickjs_core, qcrypto_sha256, qcrypto_base64;

function JSValueToBytes(ctx: PJSContext; v: JSValueConst; out outBytes: TBytes): boolean;
var
  p: Pcuint8;
  n: csize_t;
  tab: JSValue;
  ab: JSValue;
  byte_offset: csize_t;
  byte_length: csize_t;
  bpe: csize_t;
  s: PChar;
  slen: csize_t;
  ex: JSValue;
begin
  SetLength(outBytes, 0);
  if JS_IsArrayBuffer(v) <> 0 then
  begin
    p := JS_GetArrayBuffer(ctx, @n, v);
    if p = nil then
      Exit(False);
    SetLength(outBytes, n);
    if n > 0 then
      Move(p^, outBytes[0], n);
    Exit(True);
  end;

  byte_offset := 0;
  byte_length := 0;
  bpe := 0;
  tab := JS_GetTypedArrayBuffer(ctx, v, @byte_offset, @byte_length, @bpe);
  if JS_IsException(tab) <> 0 then
  begin
    ex := JS_GetException(ctx);
    JS_FreeValue(ctx, ex);
  end
  else
  begin
    try
      ab := tab;
      p := JS_GetArrayBuffer(ctx, @n, ab);
      if (p <> nil) and (byte_offset + byte_length <= n) then
      begin
        SetLength(outBytes, byte_length);
        if byte_length > 0 then
          Move(p[byte_offset], outBytes[0], byte_length);
        Exit(True);
      end;
    finally
      JS_FreeValue(ctx, tab);
    end;
  end;

  s := JS_ToCStringLen(ctx, @slen, v);
  if s <> nil then
  begin
    try
      SetLength(outBytes, slen);
      if slen > 0 then
        Move(s^, outBytes[0], slen);
      Exit(True);
    finally
      JS_FreeCString(ctx, s);
    end;
  end;

  Result := False;
end;

function js_crypto_sha256Hex(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  data: TBytes;
  hex: string;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('crypto.sha256Hex expects 1 argument')));
  if not JSValueToBytes(ctx, argv[0], data) then
    Exit(JS_ThrowTypeError(ctx, PChar('crypto.sha256Hex expects ArrayBuffer/Uint8Array/string')));
  hex := Sha256DigestHexBytes(data);
  Result := JS_NewString(ctx, PChar(hex));
end;

function js_crypto_base64Encode(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  data: TBytes;
  s: string;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('crypto.base64Encode expects 1 argument')));
  if not JSValueToBytes(ctx, argv[0], data) then
    Exit(JS_ThrowTypeError(ctx, PChar('crypto.base64Encode expects ArrayBuffer/Uint8Array/string')));
  s := Base64Encode(data);
  Result := JS_NewString(ctx, PChar(s));
end;

function js_crypto_base64Decode(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  ps: PChar;
  bytes: TBytes;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('crypto.base64Decode expects 1 argument')));
  ps := JS_ToCString(ctx, argv[0]);
  if ps = nil then
    Exit(JS_EXCEPTION);
  try
    if not Base64Decode(string(ps), bytes) then
      Exit(JS_ThrowTypeError(ctx, PChar('crypto.base64Decode: invalid base64')));
  finally
    JS_FreeCString(ctx, ps);
  end;

  if Length(bytes) = 0 then
    Exit(JS_NewArrayBufferCopy(ctx, nil, 0));
  Result := JS_NewArrayBufferCopy(ctx, @bytes[0], Length(bytes));
end;

procedure RegisterCryptoGlobals(ctx: PJSContext);
var
  global_obj: JSValue;
  native_obj: JSValue;
begin
  if ctx = nil then
    Exit;

  global_obj := JS_GetGlobalObject(ctx);
  native_obj := JS_NewObject(ctx);

  JS_DefinePropertyValueStr(ctx, native_obj, PChar('sha256Hex'),
    JS_NewCFunction(ctx, @js_crypto_sha256Hex, PChar('sha256Hex'), 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, native_obj, PChar('base64Encode'),
    JS_NewCFunction(ctx, @js_crypto_base64Encode, PChar('base64Encode'), 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, native_obj, PChar('base64Decode'),
    JS_NewCFunction(ctx, @js_crypto_base64Decode, PChar('base64Decode'), 1), JS_PROP_C_W_E);

  JS_DefinePropertyValueStr(ctx, global_obj, PChar('__qjsp_native_crypto'), native_obj, JS_PROP_C_W_E);
  JS_FreeValue(ctx, global_obj);
end;

procedure RegisterCryptoModuleShims(ctx: PJSContext);
begin
  if ctx = nil then
    Exit;
  RegisterCryptoGlobals(ctx);
end;

end.
