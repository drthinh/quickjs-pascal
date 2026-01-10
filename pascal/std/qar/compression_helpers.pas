unit compression_helpers;

{$mode objfpc}{$H+}

interface

uses
  ctypes, SysUtils, quickjs_types, quickjs_core, zlib;

// JavaScript bindings for compression functions
function js_compress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_uncompress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
function js_compressBound(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;

// Register compression helper functions to JavaScript global object
procedure RegisterCompressionHelpers(ctx: PJSContext);

implementation

// Compress data: compress(data: ArrayBuffer|Uint8Array, level?: number): ArrayBuffer
function js_compress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  input_buf: Pcuint8;
  input_size: csize_t;
  output_buf: Pcuint8;
  output_size: uLongf;
  level: cint;
  ret: cint;
begin
  try
    output_buf := nil;
    try
      if argc < 1 then
      begin
        Result := JS_ThrowTypeError(ctx, PChar('compress expects at least 1 argument: data'));
        Exit;
      end;

      // Get input buffer - support both ArrayBuffer and Uint8Array
      if JS_IsArrayBuffer(argv[0]) <> 0 then
      begin
        input_buf := JS_GetArrayBuffer(ctx, @input_size, argv[0]);
        if input_buf = nil then
        begin
          Result := JS_EXCEPTION;
          Exit;
        end;
      end
      else
      begin
        // Try to get as Uint8Array
        input_buf := JS_GetUint8Array(ctx, @input_size, argv[0]);
        if input_buf = nil then
        begin
          Result := JS_ThrowTypeError(ctx, PChar('compress expects ArrayBuffer or Uint8Array'));
          Exit;
        end;
      end;

      // Get compression level (optional, default to MZ_DEFAULT_LEVEL)
      level := 6;
      if argc >= 2 then
      begin
        if JS_ToInt32(ctx, @level, argv[1]) < 0 then
        begin
          Result := JS_EXCEPTION;
          Exit;
        end;
        // Clamp level to valid range (0-9)
        if level < 0 then level := 0;
        if level > 9 then level := 9;
      end;

      // Calculate output buffer size
      output_size := compressBound(uLong(input_size));
      output_buf := GetMem(output_size);
      if output_buf = nil then
      begin
        Result := JS_ThrowTypeError(ctx, PChar('compress: out of memory'));
        Exit;
      end;

      // Compress
      ret := compress2(PBytef(output_buf), @output_size, PBytef(input_buf), uLong(input_size), level);
      if ret <> Z_OK then
      begin
        Result := JS_ThrowTypeError(ctx, PChar('compress: compression failed'));
        Exit;
      end;

      // Create ArrayBuffer with compressed data
      Result := JS_NewArrayBufferCopy(ctx, output_buf, csize_t(output_size));
    finally
      if output_buf <> nil then
        FreeMem(output_buf);
    end;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('compress: ' + E.Message));
  end;
end;

// Uncompress data: uncompress(data: ArrayBuffer|Uint8Array, uncompressed_size?: number): ArrayBuffer
function js_uncompress(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  input_buf: Pcuint8;
  input_size: csize_t;
  output_buf: Pcuint8;
  output_size: uLongf;
  uncompressed_size: cint64;
  ret: cint;
begin
  try
    output_buf := nil;
    try
      if argc < 1 then
      begin
        Result := JS_ThrowTypeError(ctx, PChar('uncompress expects at least 1 argument: data'));
        Exit;
      end;

      // Get input buffer - support both ArrayBuffer and Uint8Array
      if JS_IsArrayBuffer(argv[0]) <> 0 then
      begin
        input_buf := JS_GetArrayBuffer(ctx, @input_size, argv[0]);
        if input_buf = nil then
        begin
          Result := JS_EXCEPTION;
          Exit;
        end;
      end
      else
      begin
        // Try to get as Uint8Array
        input_buf := JS_GetUint8Array(ctx, @input_size, argv[0]);
        if input_buf = nil then
        begin
          Result := JS_ThrowTypeError(ctx, PChar('uncompress expects ArrayBuffer or Uint8Array'));
          Exit;
        end;
      end;

      // Get uncompressed size (optional, but recommended for efficiency)
      if argc >= 2 then
      begin
        if JS_ToInt64(ctx, @uncompressed_size, argv[1]) < 0 then
        begin
          Result := JS_EXCEPTION;
          Exit;
        end;
        output_size := uLongf(uncompressed_size);
      end
      else
      begin
        // Estimate: compressed data is usually smaller, so start with input_size * 2
        // This is a heuristic and may need adjustment
        output_size := uLongf(input_size) * 2;
      end;

      // Allocate output buffer
      output_buf := GetMem(output_size);
      if output_buf = nil then
      begin
        Result := JS_ThrowTypeError(ctx, PChar('uncompress: out of memory'));
        Exit;
      end;

      // Uncompress
      ret := uncompress(PBytef(output_buf), @output_size, PBytef(input_buf), uLong(input_size));
      if ret <> Z_OK then
      begin
        // Try with larger buffer if size was not provided
        if argc < 2 then
        begin
          FreeMem(output_buf);
          output_buf := nil;
          output_size := uLongf(input_size) * 4;
          output_buf := GetMem(output_size);
          if output_buf = nil then
          begin
            Result := JS_ThrowTypeError(ctx, PChar('uncompress: out of memory'));
            Exit;
          end;
          ret := uncompress(PBytef(output_buf), @output_size, PBytef(input_buf), uLong(input_size));
          if ret <> Z_OK then
          begin
            Result := JS_ThrowTypeError(ctx, PChar('uncompress: decompression failed'));
            Exit;
          end;
        end
        else
        begin
          Result := JS_ThrowTypeError(ctx, PChar('uncompress: decompression failed'));
          Exit;
        end;
      end;

      // Create ArrayBuffer with uncompressed data
      Result := JS_NewArrayBufferCopy(ctx, output_buf, csize_t(output_size));
    finally
      if output_buf <> nil then
        FreeMem(output_buf);
    end;
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('uncompress: ' + E.Message));
  end;
end;

// Get compression bound: compressBound(source_size: number): number
function js_compressBound(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  source_size: cint64;
  bound: uLong;
begin
  try
    if argc < 1 then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('compressBound expects 1 argument: source_size'));
      Exit;
    end;

    if JS_ToInt64(ctx, @source_size, argv[0]) < 0 then
    begin
      Result := JS_EXCEPTION;
      Exit;
    end;

    if source_size < 0 then
    begin
      Result := JS_ThrowTypeError(ctx, PChar('compressBound: source_size must be non-negative'));
      Exit;
    end;

    bound := compressBound(uLong(source_size));
    Result := JS_NewInt64(ctx, cint64(bound));
  except
    on E: Exception do
      Result := JS_ThrowPlainError(ctx, PChar('compressBound: ' + E.Message));
  end;
end;

// Register compression helper functions to JavaScript global object
procedure RegisterCompressionHelpers(ctx: PJSContext);
var
  global_obj: JSValue;
begin
  global_obj := JS_GetGlobalObject(ctx);

  // Register compression functions
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('compress'),
    JS_NewCFunction(ctx, @js_compress, PChar('compress'), 2), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('uncompress'),
    JS_NewCFunction(ctx, @js_uncompress, PChar('uncompress'), 2), JS_PROP_C_W_E);
  
  JS_DefinePropertyValueStr(ctx, global_obj, PChar('compressBound'),
    JS_NewCFunction(ctx, @js_compressBound, PChar('compressBound'), 1), JS_PROP_C_W_E);

  JS_FreeValue(ctx, global_obj);
end;

end.

