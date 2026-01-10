unit qjsp_zip_shim;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, quickjs_types;

procedure RegisterZipModuleShims(ctx: PJSContext);

implementation

uses
  quickjs_core, zlib, qjs_log;

type
  TZipEntry = record
    Name: AnsiString;
    Method: cuint16;
    CRC32: cuint32;
    CompressedSize: cuint32;
    UncompressedSize: cuint32;
    LocalHeaderOfs: cuint32;
    DataOfs: cuint32;
  end;
  PZipArchiveRec = ^TZipArchiveRec;
  TZipArchiveRec = record
    Id: cint64;
    Buf: TBytes;
    Entries: array of TZipEntry;
  end;

var
  g_archives: TList;
  g_next_id: cint64 = 1;

function ReadLE16(const b: TBytes; ofs: SizeInt): cuint16; inline;
begin
  Result := cuint16(b[ofs]) or (cuint16(b[ofs + 1]) shl 8);
end;

function ReadLE32(const b: TBytes; ofs: SizeInt): cuint32; inline;
begin
  Result := cuint32(b[ofs]) or (cuint32(b[ofs + 1]) shl 8) or (cuint32(b[ofs + 2]) shl 16) or (cuint32(b[ofs + 3]) shl 24);
end;

function HasBytes(const b: TBytes; ofs: SizeInt; need: SizeInt): boolean; inline;
begin
  Result := (ofs >= 0) and (need >= 0) and (ofs + need <= Length(b));
end;

procedure WriteLE16(var b: TBytes; v: cuint16);
var
  n: SizeInt;
begin
  n := Length(b);
  SetLength(b, n + 2);
  b[n] := Byte(v and $FF);
  b[n + 1] := Byte((v shr 8) and $FF);
end;

procedure WriteLE32(var b: TBytes; v: cuint32);
var
  n: SizeInt;
begin
  n := Length(b);
  SetLength(b, n + 4);
  b[n] := Byte(v and $FF);
  b[n + 1] := Byte((v shr 8) and $FF);
  b[n + 2] := Byte((v shr 16) and $FF);
  b[n + 3] := Byte((v shr 24) and $FF);
end;

procedure WriteBytes(var b: TBytes; const src: TBytes);
var
  n: SizeInt;
begin
  if Length(src) = 0 then
    Exit;
  n := Length(b);
  SetLength(b, n + Length(src));
  Move(src[0], b[n], Length(src));
end;

procedure WriteRaw(var b: TBytes; p: pointer; len: SizeInt);
var
  n: SizeInt;
begin
  if (p = nil) or (len <= 0) then
    Exit;
  n := Length(b);
  SetLength(b, n + len);
  Move(p^, b[n], len);
end;

function BytesOfAnsi(const s: AnsiString): TBytes;
begin
  if s = '' then
    Exit(nil);
  SetLength(Result, Length(s));
  Move(s[1], Result[0], Length(s));
end;

function GetArchiveById(id: cint64): PZipArchiveRec;
var
  i: integer;
  p: PZipArchiveRec;
begin
  Result := nil;
  if g_archives = nil then
    Exit;
  for i := 0 to g_archives.Count - 1 do
  begin
    p := PZipArchiveRec(g_archives[i]);
    if (p <> nil) and (p^.Id = id) then
      Exit(p);
  end;
end;

procedure RemoveArchiveById(id: cint64);
var
  i: integer;
  p: PZipArchiveRec;
begin
  if g_archives = nil then
    Exit;
  for i := g_archives.Count - 1 downto 0 do
  begin
    p := PZipArchiveRec(g_archives[i]);
    if (p <> nil) and (p^.Id = id) then
    begin
      Dispose(p);
      g_archives.Delete(i);
      Exit;
    end;
  end;
end;

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

  // TypedArray view: JS_GetTypedArrayBuffer throws TypeError if not a TypedArray.
  // We must clear that exception before falling back to other conversions.
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

function JSGetStrProp(ctx: PJSContext; obj: JSValueConst; const name: AnsiString; out s: AnsiString): boolean;
var
  v: JSValue;
  p: PChar;
begin
  s := '';
  v := JS_GetPropertyStr(ctx, obj, PChar(name));
  if JS_IsException(v) <> 0 then
    Exit(False);
  try
    p := JS_ToCString(ctx, v);
    if p = nil then
      Exit(False);
    try
      s := AnsiString(p);
      Result := True;
    finally
      JS_FreeCString(ctx, p);
    end;
  finally
    JS_FreeValue(ctx, v);
  end;
end;

function FindEntryIndexByName(p: PZipArchiveRec; const name: AnsiString): integer;
var
  i: integer;
begin
  Result := -1;
  if p = nil then
    Exit;
  for i := 0 to High(p^.Entries) do
    if p^.Entries[i].Name = name then
      Exit(i);
end;

function zip_archive_numFiles(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  idv: JSValue;
  id: cint64;
  p: PZipArchiveRec;
begin
  idv := JS_GetPropertyStr(ctx, this_val, PChar('__zip_id'));
  if JS_IsException(idv) <> 0 then
    Exit(JS_EXCEPTION);
  try
    if JS_ToInt64(ctx, @id, idv) < 0 then
      Exit(JS_EXCEPTION);
  finally
    JS_FreeValue(ctx, idv);
  end;
  p := GetArchiveById(id);
  if p = nil then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: archive is closed')));
  Result := JS_NewInt32(ctx, Length(p^.Entries));
end;

function zip_archive_list(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  idv: JSValue;
  id: cint64;
  p: PZipArchiveRec;
  arr: JSValue;
  i: integer;
  o: JSValue;
begin
  idv := JS_GetPropertyStr(ctx, this_val, PChar('__zip_id'));
  if JS_IsException(idv) <> 0 then
    Exit(JS_EXCEPTION);
  try
    if JS_ToInt64(ctx, @id, idv) < 0 then
      Exit(JS_EXCEPTION);
  finally
    JS_FreeValue(ctx, idv);
  end;
  p := GetArchiveById(id);
  if p = nil then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: archive is closed')));

  arr := JS_NewArray(ctx);
  for i := 0 to High(p^.Entries) do
  begin
    o := JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, o, PChar('name'), JS_NewString(ctx, PChar(p^.Entries[i].Name)));
    JS_SetPropertyStr(ctx, o, PChar('compressedSize'), JS_NewInt64(ctx, p^.Entries[i].CompressedSize));
    JS_SetPropertyStr(ctx, o, PChar('uncompressedSize'), JS_NewInt64(ctx, p^.Entries[i].UncompressedSize));
    JS_SetPropertyUint32(ctx, arr, cuint32(i), o);
  end;
  Result := arr;
end;

function zip_archive_stat(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  idv: JSValue;
  id: cint64;
  p: PZipArchiveRec;
  name: PChar;
  idx: integer;
  o: JSValue;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.stat expects 1 argument')));

  idv := JS_GetPropertyStr(ctx, this_val, PChar('__zip_id'));
  if JS_IsException(idv) <> 0 then
    Exit(JS_EXCEPTION);
  try
    if JS_ToInt64(ctx, @id, idv) < 0 then
      Exit(JS_EXCEPTION);
  finally
    JS_FreeValue(ctx, idv);
  end;
  p := GetArchiveById(id);
  if p = nil then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: archive is closed')));

  name := JS_ToCString(ctx, argv[0]);
  if name = nil then
    Exit(JS_EXCEPTION);
  try
    idx := FindEntryIndexByName(p, AnsiString(name));
    if idx < 0 then
      Exit(JS_ThrowTypeError(ctx, PChar('zip: entry not found')));
  finally
    JS_FreeCString(ctx, name);
  end;

  o := JS_NewObject(ctx);
  JS_SetPropertyStr(ctx, o, PChar('name'), JS_NewString(ctx, PChar(p^.Entries[idx].Name)));
  JS_SetPropertyStr(ctx, o, PChar('compressedSize'), JS_NewInt64(ctx, p^.Entries[idx].CompressedSize));
  JS_SetPropertyStr(ctx, o, PChar('uncompressedSize'), JS_NewInt64(ctx, p^.Entries[idx].UncompressedSize));
  Result := o;
end;

function zip_archive_read(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  idv: JSValue;
  id: cint64;
  p: PZipArchiveRec;
  name: PChar;
  idx: integer;
  ofs: SizeInt;
  sz: SizeInt;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.read expects 1 argument')));

  idv := JS_GetPropertyStr(ctx, this_val, PChar('__zip_id'));
  if JS_IsException(idv) <> 0 then
    Exit(JS_EXCEPTION);
  try
    if JS_ToInt64(ctx, @id, idv) < 0 then
      Exit(JS_EXCEPTION);
  finally
    JS_FreeValue(ctx, idv);
  end;
  p := GetArchiveById(id);
  if p = nil then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: archive is closed')));

  name := JS_ToCString(ctx, argv[0]);
  if name = nil then
    Exit(JS_EXCEPTION);
  try
    idx := FindEntryIndexByName(p, AnsiString(name));
    if idx < 0 then
      Exit(JS_ThrowTypeError(ctx, PChar('zip: entry not found')));
  finally
    JS_FreeCString(ctx, name);
  end;

  if p^.Entries[idx].Method <> 0 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: only store method is supported in this build')));

  ofs := p^.Entries[idx].DataOfs;
  sz := p^.Entries[idx].UncompressedSize;
  if (ofs < 0) or (sz < 0) or (ofs + sz > Length(p^.Buf)) then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid entry bounds')));

  if sz = 0 then
    Exit(JS_NewArrayBufferCopy(ctx, nil, 0));

  Result := JS_NewArrayBufferCopy(ctx, @p^.Buf[ofs], sz);
end;

function zip_archive_close(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  idv: JSValue;
  id: cint64;
begin
  idv := JS_GetPropertyStr(ctx, this_val, PChar('__zip_id'));
  if JS_IsException(idv) <> 0 then
    Exit(JS_EXCEPTION);
  try
    if JS_ToInt64(ctx, @id, idv) < 0 then
      Exit(JS_EXCEPTION);
  finally
    JS_FreeValue(ctx, idv);
  end;

  RemoveArchiveById(id);
  Result := JS_UNDEFINED;
end;

function ParseZipBuffer(ctx: PJSContext; const buf: TBytes; out entries: array of TZipEntry): boolean;
begin
  Result := False;
end;

function zip_open(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  data: TBytes;
  eocdOfs: SizeInt;
  cdSize: cuint32;
  cdOfs: cuint32;
  total: cuint16;
  p: PZipArchiveRec;
  i: integer;
  ofs: SizeInt;
  sig: cuint32;
  fnLen, extraLen, commentLen: cuint16;
  lhOfs: cuint32;
  lfnLen: cuint16;
  lextraLen: cuint16;
  nameBytes: TBytes;
  obj: JSValue;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.open expects 1 argument')));
  if not JSValueToBytes(ctx, argv[0], data) then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.open expects ArrayBuffer/Uint8Array/string')));

  eocdOfs := -1;
  if Length(data) >= 22 then
  begin
    for ofs := Length(data) - 22 downto 0 do
    begin
      if not HasBytes(data, ofs, 4) then
        Break;
      if ReadLE32(data, ofs) = $06054B50 then
      begin
        eocdOfs := ofs;
        Break;
      end;
      if (Length(data) - ofs) > 65557 then
        Break;
    end;
  end;
  if eocdOfs < 0 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid zip buffer (no EOCD)')));

  if not HasBytes(data, eocdOfs, 22) then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid EOCD bounds')));

  total := ReadLE16(data, eocdOfs + 10);
  cdSize := ReadLE32(data, eocdOfs + 12);
  cdOfs := ReadLE32(data, eocdOfs + 16);
  if (cdOfs + cdSize > cuint32(Length(data))) then
    Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid central directory bounds')));

  New(p);
  FillChar(p^, SizeOf(p^), 0);
  p^.Id := g_next_id;
  Inc(g_next_id);
  p^.Buf := data;
  SetLength(p^.Entries, total);

  ofs := cdOfs;
  for i := 0 to total - 1 do
  begin
    if not HasBytes(p^.Buf, ofs, 46) then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: truncated central directory')));
    end;
    sig := ReadLE32(p^.Buf, ofs);
    if sig <> $02014B50 then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid central directory entry')));
    end;
    p^.Entries[i].Method := ReadLE16(p^.Buf, ofs + 10);
    p^.Entries[i].CRC32 := ReadLE32(p^.Buf, ofs + 16);
    p^.Entries[i].CompressedSize := ReadLE32(p^.Buf, ofs + 20);
    p^.Entries[i].UncompressedSize := ReadLE32(p^.Buf, ofs + 24);
    fnLen := ReadLE16(p^.Buf, ofs + 28);
    extraLen := ReadLE16(p^.Buf, ofs + 30);
    commentLen := ReadLE16(p^.Buf, ofs + 32);
    lhOfs := ReadLE32(p^.Buf, ofs + 42);
    p^.Entries[i].LocalHeaderOfs := lhOfs;

    if not HasBytes(p^.Buf, ofs + 46, fnLen + extraLen + commentLen) then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: truncated central directory name/extra/comment')));
    end;

    SetLength(nameBytes, fnLen);
    if fnLen > 0 then
      Move(p^.Buf[ofs + 46], nameBytes[0], fnLen);
    if fnLen > 0 then
      SetString(p^.Entries[i].Name, PAnsiChar(@nameBytes[0]), fnLen)
    else
      p^.Entries[i].Name := '';

    if (lhOfs + 30 > cuint32(Length(p^.Buf))) then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid local header offset')));
    end;

    if not HasBytes(p^.Buf, lhOfs, 30) then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: truncated local header')));
    end;

    if ReadLE32(p^.Buf, lhOfs) <> $04034B50 then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid local file header signature')));
    end;

    lfnLen := ReadLE16(p^.Buf, lhOfs + 26);
    lextraLen := ReadLE16(p^.Buf, lhOfs + 28);
    p^.Entries[i].DataOfs := lhOfs + 30 + lfnLen + lextraLen;

    if (p^.Entries[i].DataOfs > cuint32(Length(p^.Buf))) then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid data offset')));
    end;

    if (p^.Entries[i].DataOfs + p^.Entries[i].CompressedSize > cuint32(Length(p^.Buf))) then
    begin
      Dispose(p);
      Exit(JS_ThrowTypeError(ctx, PChar('zip: invalid data bounds')));
    end;

    ofs := ofs + 46 + fnLen + extraLen + commentLen;
  end;

  if g_archives = nil then
    g_archives := TList.Create;
  g_archives.Add(p);

  obj := JS_NewObject(ctx);
  JS_SetPropertyStr(ctx, obj, PChar('__zip_id'), JS_NewInt64(ctx, p^.Id));
  JS_SetPropertyStr(ctx, obj, PChar('numFiles'), JS_NewCFunction(ctx, @zip_archive_numFiles, PChar('numFiles'), 0));
  JS_SetPropertyStr(ctx, obj, PChar('list'), JS_NewCFunction(ctx, @zip_archive_list, PChar('list'), 0));
  JS_SetPropertyStr(ctx, obj, PChar('stat'), JS_NewCFunction(ctx, @zip_archive_stat, PChar('stat'), 1));
  JS_SetPropertyStr(ctx, obj, PChar('read'), JS_NewCFunction(ctx, @zip_archive_read, PChar('read'), 1));
  JS_SetPropertyStr(ctx, obj, PChar('close'), JS_NewCFunction(ctx, @zip_archive_close, PChar('close'), 0));
  Result := obj;
end;

function zip_openFile(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  fn: PChar;
  ms: TMemoryStream;
  buf: TBytes;
  ab: JSValue;
  args: array[0..0] of JSValueConst;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.openFile expects 1 argument')));
  fn := JS_ToCString(ctx, argv[0]);
  if fn = nil then
    Exit(JS_EXCEPTION);
  try
    if not FileExists(fn) then
      Exit(JS_ThrowTypeError(ctx, PChar('zip: file not found')));
    ms := TMemoryStream.Create;
    try
      ms.LoadFromFile(fn);
      SetLength(buf, ms.Size);
      if ms.Size > 0 then
      begin
        ms.Position := 0;
        ms.ReadBuffer(buf[0], ms.Size);
      end;
    finally
      ms.Free;
    end;
  finally
    JS_FreeCString(ctx, fn);
  end;

  if Length(buf) = 0 then
    ab := JS_NewArrayBufferCopy(ctx, nil, 0)
  else
    ab := JS_NewArrayBufferCopy(ctx, @buf[0], Length(buf));
  args[0] := ab;
  try
    Result := zip_open(ctx, this_val, 1, @args[0]);
  finally
    JS_FreeValue(ctx, ab);
  end;
end;

function zip_create(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  items: JSValue;
  len: cint;
  len64: cint64;
  i: integer;
  item: JSValue;
  vdata: JSValue;
  name: AnsiString;
  dataBytes: TBytes;
  outBuf: TBytes;
  central: TBytes;
  centralOfs: cuint32;
  crc: cuint32;
  localOfs: cuint32;
  fnBytes: TBytes;
begin
  if argc < 1 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.create expects 1 argument')));
  items := argv[0];
  len64 := 0;
  if JS_GetLength(ctx, items, @len64) <> 0 then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.create expects an array')));
  if (len64 < 0) or (len64 > High(cint)) then
    Exit(JS_ThrowTypeError(ctx, PChar('zip.create: invalid array length')));
  len := cint(len64);

  SetLength(outBuf, 0);
  SetLength(central, 0);

  for i := 0 to len - 1 do
  begin
    item := JS_GetPropertyUint32(ctx, items, cuint32(i));
    if JS_IsException(item) <> 0 then
      Exit(JS_EXCEPTION);
    try
      if not JSGetStrProp(ctx, item, 'name', name) then
        Exit(JS_ThrowTypeError(ctx, PChar('zip.create: missing name')));
      vdata := JS_GetPropertyStr(ctx, item, PChar('data'));
      if JS_IsException(vdata) <> 0 then
        Exit(JS_EXCEPTION);
      try
        if not JSValueToBytes(ctx, vdata, dataBytes) then
          Exit(JS_ThrowTypeError(ctx, PChar('zip.create: invalid data')));
      finally
        JS_FreeValue(ctx, vdata);
      end;
    finally
      JS_FreeValue(ctx, item);
    end;

    fnBytes := BytesOfAnsi(name);
    localOfs := cuint32(Length(outBuf));

    crc := crc32(0, nil, 0);
    if Length(dataBytes) > 0 then
      crc := crc32(crc, @dataBytes[0], Length(dataBytes));

    WriteLE32(outBuf, $04034B50);
    WriteLE16(outBuf, 20);
    WriteLE16(outBuf, 0);
    WriteLE16(outBuf, 0);
    WriteLE16(outBuf, 0);
    WriteLE16(outBuf, 0);
    WriteLE32(outBuf, crc);
    WriteLE32(outBuf, cuint32(Length(dataBytes)));
    WriteLE32(outBuf, cuint32(Length(dataBytes)));
    WriteLE16(outBuf, cuint16(Length(fnBytes)));
    WriteLE16(outBuf, 0);
    WriteBytes(outBuf, fnBytes);
    WriteBytes(outBuf, dataBytes);

    WriteLE32(central, $02014B50);
    WriteLE16(central, 20);
    WriteLE16(central, 20);
    WriteLE16(central, 0);
    WriteLE16(central, 0);
    WriteLE16(central, 0);
    WriteLE16(central, 0);
    WriteLE32(central, crc);
    WriteLE32(central, cuint32(Length(dataBytes)));
    WriteLE32(central, cuint32(Length(dataBytes)));
    WriteLE16(central, cuint16(Length(fnBytes)));
    WriteLE16(central, 0);
    WriteLE16(central, 0);
    WriteLE16(central, 0);
    WriteLE16(central, 0);
    WriteLE32(central, 0);
    WriteLE32(central, localOfs);
    WriteBytes(central, fnBytes);
  end;

  centralOfs := cuint32(Length(outBuf));
  WriteBytes(outBuf, central);

  WriteLE32(outBuf, $06054B50);
  WriteLE16(outBuf, 0);
  WriteLE16(outBuf, 0);
  WriteLE16(outBuf, cuint16(len));
  WriteLE16(outBuf, cuint16(len));
  WriteLE32(outBuf, cuint32(Length(central)));
  WriteLE32(outBuf, centralOfs);
  WriteLE16(outBuf, 0);

  if Length(outBuf) = 0 then
    Exit(JS_NewArrayBufferCopy(ctx, nil, 0));
  Result := JS_NewArrayBufferCopy(ctx, @outBuf[0], Length(outBuf));
end;

function zip_module_init(ctx: PJSContext; m: PJSModuleDef): cint; cdecl;
var
  fn_open: JSValue;
  fn_openFile: JSValue;
  fn_create: JSValue;
  rc: cint;
begin
  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: begin');
    Flush(Output);
  end;

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: creating functions');
    Flush(Output);
  end;
  fn_open := JS_NewCFunction(ctx, @zip_open, PChar('open'), 1);
  fn_openFile := JS_NewCFunction(ctx, @zip_openFile, PChar('openFile'), 1);
  fn_create := JS_NewCFunction(ctx, @zip_create, PChar('create'), 1);

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: adding exports');
    Flush(Output);
  end;
  JS_AddModuleExport(ctx, m, PChar('open'));
  JS_AddModuleExport(ctx, m, PChar('openFile'));
  JS_AddModuleExport(ctx, m, PChar('create'));

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: setting exports');
    Flush(Output);
  end;

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: JS_SetModuleExport(open) call');
    Flush(Output);
  end;
  rc := JS_SetModuleExport(ctx, m, PChar('open'), fn_open);
  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: JS_SetModuleExport(open) rc=', rc);
    Flush(Output);
  end;

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: JS_SetModuleExport(openFile) call');
    Flush(Output);
  end;
  rc := JS_SetModuleExport(ctx, m, PChar('openFile'), fn_openFile);
  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: JS_SetModuleExport(openFile) rc=', rc);
    Flush(Output);
  end;

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: JS_SetModuleExport(create) call');
    Flush(Output);
  end;
  rc := JS_SetModuleExport(ctx, m, PChar('create'), fn_create);
  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: JS_SetModuleExport(create) rc=', rc);
    Flush(Output);
  end;

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] zip_module_init: end');
    Flush(Output);
  end;
  Result := 0;
end;

procedure RegisterZipGlobals(ctx: PJSContext);
var
  global_obj: JSValue;
  native_obj: JSValue;
begin
  if ctx = nil then
    Exit;

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] RegisterZipGlobals: begin');
    Flush(Output);
  end;

  global_obj := JS_GetGlobalObject(ctx);
  native_obj := JS_NewObject(ctx);

  JS_DefinePropertyValueStr(ctx, native_obj, PChar('open'),
    JS_NewCFunction(ctx, @zip_open, PChar('open'), 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, native_obj, PChar('openFile'),
    JS_NewCFunction(ctx, @zip_openFile, PChar('openFile'), 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, native_obj, PChar('create'),
    JS_NewCFunction(ctx, @zip_create, PChar('create'), 1), JS_PROP_C_W_E);

  JS_DefinePropertyValueStr(ctx, global_obj, PChar('__qjsp_native_zip'), native_obj, JS_PROP_C_W_E);
  JS_FreeValue(ctx, global_obj);

  if qjs_log.DebugLevel > 0 then
  begin
    WriteLn('[DEBUG] RegisterZipGlobals: end');
    Flush(Output);
  end;
end;

procedure RegisterZipModuleShims(ctx: PJSContext);
begin
  if ctx = nil then
    Exit;

  // IMPORTANT: zip functions are provided by Pascal (not by libqjs.dll).
  // We register them on the global object (like fs_watch_helpers/http_helpers)
  // and provide a JS wrapper module via the module loader.
  RegisterZipGlobals(ctx);
end;

end.
