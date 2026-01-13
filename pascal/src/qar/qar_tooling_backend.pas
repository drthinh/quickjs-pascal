unit qar_tooling_backend;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes,
  qar,
  qcrypto_base64,
  qcrypto_ed25519_sign;

type
  TQarBuildOptions = record
    entry_main: string;
    entry_init: string;
    created_by: string;
    tool: string;
    sign_key_file: string;
    meta: TStrings; // optional, not owned
    omit_source: boolean;
    format_version: integer;
  end;

function QarBuildWithOptions(const output_file: string; const input_files: array of string; const opts: TQarBuildOptions): cint;
function QarRebuildWithOptions(const input_file: string; const output_file: string; const opts: TQarBuildOptions): cint;

function QarKeygenFiles(const raw64_file: string; const pem_file: string; out err: string): boolean;

implementation

{$IFDEF WINDOWS}
type
  NTSTATUS = LongInt;
  ULONG = Cardinal;

function BCryptGenRandom(hAlgorithm: pointer; pbBuffer: PByte; cbBuffer: ULONG; dwFlags: ULONG): NTSTATUS; stdcall; external 'bcrypt.dll';

const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = ULONG($00000002);
{$ENDIF}

function GetRandomBytes(out buf: TBytes; len: Integer; out err: string): boolean;
{$IFDEF WINDOWS}
var
  st: NTSTATUS;
{$ENDIF}
begin
  Result := False;
  err := '';
  SetLength(buf, 0);
  if len <= 0 then
    Exit(True);
  SetLength(buf, len);
{$IFDEF WINDOWS}
  st := BCryptGenRandom(nil, @buf[0], ULONG(len), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  Result := st = 0;
  if not Result then
    err := 'BCryptGenRandom failed: status=' + IntToStr(st);
{$ELSE}
  err := 'RNG not implemented on this platform';
  Result := False;
{$ENDIF}
end;

function WriteAllBytesToFile(const filename: string; const bytes: TBytes; out err: string): boolean;
var
  fs: TFileStream;
begin
  Result := False;
  err := '';
  try
    fs := TFileStream.Create(filename, fmCreate);
    try
      if Length(bytes) > 0 then
        fs.WriteBuffer(bytes[0], Length(bytes));
      Result := True;
    finally
      fs.Free;
    end;
  except
    on E: Exception do
      err := E.Message;
  end;
end;

function WriteAllTextToFile(const filename: string; const text: string; out err: string): boolean;
var
  fs: TFileStream;
  b: TBytes;
begin
  Result := False;
  err := '';
  try
    fs := TFileStream.Create(filename, fmCreate);
    try
      if text <> '' then
      begin
        b := BytesOf(AnsiString(text));
        if Length(b) > 0 then
          fs.WriteBuffer(b[0], Length(b));
      end;
      Result := True;
    finally
      fs.Free;
    end;
  except
    on E: Exception do
      err := E.Message;
  end;
end;

procedure AppendDerLen(var outb: TBytes; len: Integer);
var
  n: Integer;
  tmp: array[0..3] of Byte;
begin
  if len < 128 then
  begin
    SetLength(outb, Length(outb) + 1);
    outb[High(outb)] := Byte(len);
    Exit;
  end;
  n := 0;
  while (len > 0) and (n < 4) do
  begin
    tmp[3 - n] := Byte(len and $FF);
    len := len shr 8;
    Inc(n);
  end;
  SetLength(outb, Length(outb) + 1 + n);
  outb[Length(outb) - (1 + n)] := Byte($80 or n);
  Move(tmp[4 - n], outb[Length(outb) - n], n);
end;

function BuildPkcs8Ed25519Pem(const seed32: TBytes): string;
const
  OID_ED25519: array[0..4] of Byte = ($06, $03, $2B, $65, $70);
var
  der: TBytes;
  inner: TBytes;
  alg: TBytes;
  pk: TBytes;
  pkInner: TBytes;
  total: Integer;
  b64: string;
  i: Integer;
begin
  // AlgorithmIdentifier = SEQUENCE(OID)
  SetLength(alg, 0);
  SetLength(alg, 1);
  alg[0] := $30;
  AppendDerLen(alg, Length(OID_ED25519));
  total := Length(alg);
  SetLength(alg, total + Length(OID_ED25519));
  Move(OID_ED25519[0], alg[total], Length(OID_ED25519));

  // privateKey = OCTET STRING( OCTET STRING(seed32) )
  SetLength(pkInner, 0);
  SetLength(pkInner, 1);
  pkInner[0] := $04;
  AppendDerLen(pkInner, 32);
  total := Length(pkInner);
  SetLength(pkInner, total + 32);
  Move(seed32[0], pkInner[total], 32);

  SetLength(pk, 0);
  SetLength(pk, 1);
  pk[0] := $04;
  AppendDerLen(pk, Length(pkInner));
  total := Length(pk);
  SetLength(pk, total + Length(pkInner));
  Move(pkInner[0], pk[total], Length(pkInner));

  // inner = version + alg + pk
  SetLength(inner, 3);
  inner[0] := $02; inner[1] := $01; inner[2] := $00;

  total := Length(inner);
  SetLength(inner, total + Length(alg));
  Move(alg[0], inner[total], Length(alg));

  total := Length(inner);
  SetLength(inner, total + Length(pk));
  Move(pk[0], inner[total], Length(pk));

  // outer SEQUENCE
  SetLength(der, 1);
  der[0] := $30;
  AppendDerLen(der, Length(inner));
  total := Length(der);
  SetLength(der, total + Length(inner));
  Move(inner[0], der[total], Length(inner));

  b64 := Base64Encode(der);
  Result := '-----BEGIN PRIVATE KEY-----' + LineEnding;
  i := 1;
  while i <= Length(b64) do
  begin
    Result := Result + Copy(b64, i, 64) + LineEnding;
    Inc(i, 64);
  end;
  Result := Result + '-----END PRIVATE KEY-----' + LineEnding;
end;

function QarKeygenFiles(const raw64_file: string; const pem_file: string; out err: string): boolean;
var
  seedBytes: TBytes;
  raw64: TBytes;
  seed: TEd25519Seed;
  pk: TEd25519PublicKey;
  i: Integer;
  pem: string;
begin
  Result := False;
  err := '';

  if (raw64_file = '') and (pem_file = '') then
  begin
    err := 'No output file specified';
    Exit;
  end;

  if not GetRandomBytes(seedBytes, 32, err) then
    Exit;

  for i := 0 to 31 do
    seed[i] := seedBytes[i];

  if not Ed25519PublicKeyFromSeed(seed, pk) then
  begin
    err := 'Ed25519PublicKeyFromSeed failed';
    Exit;
  end;

  if raw64_file <> '' then
  begin
    SetLength(raw64, 64);
    for i := 0 to 31 do
      raw64[i] := seed[i];
    for i := 0 to 31 do
      raw64[32 + i] := pk[i];
    if not WriteAllBytesToFile(raw64_file, raw64, err) then
      Exit;
  end;

  if pem_file <> '' then
  begin
    SetLength(seedBytes, 32);
    for i := 0 to 31 do
      seedBytes[i] := seed[i];
    pem := BuildPkcs8Ed25519Pem(seedBytes);
    if not WriteAllTextToFile(pem_file, pem, err) then
      Exit;
  end;

  Result := True;
end;

function QarBuildWithOptions(const output_file: string; const input_files: array of string; const opts: TQarBuildOptions): cint;
begin
  Result := qar.BuildQar(output_file, input_files,
    opts.entry_main,
    opts.entry_init,
    opts.created_by,
    opts.tool,
    opts.meta,
    '',
    '',
    opts.sign_key_file,
    opts.omit_source,
    opts.format_version);
end;

function QarRebuildWithOptions(const input_file: string; const output_file: string; const opts: TQarBuildOptions): cint;
begin
  Result := qar.RebuildQarFile(input_file, output_file,
    opts.entry_main,
    opts.entry_init,
    opts.sign_key_file);
end;

end.
