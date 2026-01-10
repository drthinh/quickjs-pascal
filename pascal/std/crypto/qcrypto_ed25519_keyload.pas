unit qcrypto_ed25519_keyload;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, qcrypto_ed25519_sign;

type
  TEd25519KeyMaterial = record
    seed: TEd25519Seed;
    pubkey: TEd25519PublicKey;
  end;

function LoadEd25519KeyFromFile(const filename: string; out key: TEd25519KeyMaterial; out err: string): boolean;

implementation

uses
  qcrypto_base64;

function ReadAllBytes(const filename: string; out bytes: TBytes; out err: string): boolean;
var
  fs: TFileStream;
begin
  Result := False;
  err := '';
  SetLength(bytes, 0);
  if filename = '' then
  begin
    err := 'key filename is empty';
    Exit;
  end;
  if not FileExists(filename) then
  begin
    err := 'key file not found: ' + filename;
    Exit;
  end;
  try
    fs := TFileStream.Create(filename, fmOpenRead or fmShareDenyNone);
    try
      if fs.Size > 32 * 1024 * 1024 then
      begin
        err := 'key file too large';
        Exit;
      end;
      SetLength(bytes, fs.Size);
      if fs.Size > 0 then
        fs.ReadBuffer(bytes[0], fs.Size);
      Result := True;
    finally
      fs.Free;
    end;
  except
    on E: Exception do
    begin
      err := 'failed to read key file: ' + E.Message;
      Exit(False);
    end;
  end;
end;

function BytesStartsWith(const b: TBytes; const prefix: AnsiString): boolean;
var
  i: Integer;
begin
  if Length(b) < Length(prefix) then
    Exit(False);
  for i := 0 to Length(prefix) - 1 do
    if AnsiChar(b[i]) <> prefix[i + 1] then
      Exit(False);
  Result := True;
end;

function StripPem(const text: string; out der: TBytes; out err: string): boolean;
var
  lines: TStringList;
  i: Integer;
  b64: string;
  inBlock: boolean;
begin
  Result := False;
  err := '';
  SetLength(der, 0);

  lines := TStringList.Create;
  try
    lines.Text := text;
    b64 := '';
    inBlock := False;
    for i := 0 to lines.Count - 1 do
    begin
      if Pos('-----BEGIN ', lines[i]) = 1 then
      begin
        inBlock := True;
        Continue;
      end;
      if Pos('-----END ', lines[i]) = 1 then
      begin
        inBlock := False;
        Break;
      end;
      if inBlock then
        b64 := b64 + Trim(lines[i]);
    end;

    if b64 = '' then
    begin
      err := 'PEM has no base64 content';
      Exit;
    end;

    if not Base64Decode(b64, der) then
    begin
      err := 'PEM base64 decode failed';
      Exit;
    end;

    Result := True;
  finally
    lines.Free;
  end;
end;

function ReadAsn1Len(const der: TBytes; var pos: Integer; out len: Integer): boolean;
var
  b: Byte;
  n, i: Integer;
begin
  Result := False;
  len := 0;
  if (pos >= Length(der)) then
    Exit;
  b := der[pos];
  Inc(pos);
  if (b and $80) = 0 then
  begin
    len := b;
    Exit(True);
  end;
  n := b and $7F;
  if (n = 0) or (n > 4) then
    Exit;
  if pos + n > Length(der) then
    Exit;
  len := 0;
  for i := 0 to n - 1 do
  begin
    len := (len shl 8) or der[pos];
    Inc(pos);
  end;
  Result := True;
end;

function ReadAsn1TLV(const der: TBytes; var pos: Integer; out tag: Byte; out startPos: Integer; out len: Integer): boolean;
begin
  Result := False;
  tag := 0;
  startPos := 0;
  len := 0;
  if pos >= Length(der) then
    Exit;
  tag := der[pos];
  Inc(pos);
  if not ReadAsn1Len(der, pos, len) then
    Exit;
  startPos := pos;
  if startPos + len > Length(der) then
    Exit;
  pos := startPos + len;
  Result := True;
end;

function OidEqualsEd25519(const der: TBytes; startPos, len: Integer): boolean;
const
  // 1.3.101.112 => 06 03 2B 65 70
  ED: array[0..2] of Byte = ($2B, $65, $70);
var
  i: Integer;
begin
  Result := False;
  if len <> 3 then
    Exit;
  for i := 0 to 2 do
    if der[startPos + i] <> ED[i] then
      Exit;
  Result := True;
end;

function ParsePkcs8Ed25519Seed(const der: TBytes; out seed: TEd25519Seed; out err: string): boolean;
var
  pos, tagPos, tagLen: Integer;
  tag: Byte;
  seqStart, seqLen: Integer;
  innerPos: Integer;
  t2: Byte;
  s2, l2: Integer;
  algSeqStart, algSeqLen: Integer;
  algPos: Integer;
  oidTag: Byte;
  oidStart, oidLen: Integer;
  pkTag: Byte;
  pkStart, pkLen: Integer;
  pkInnerPos: Integer;
  octTag: Byte;
  octStart, octLen: Integer;
  i: Integer;
  okOid: boolean;
  tmpSeed: array[0..31] of Byte;
begin
  Result := False;
  err := '';
  FillChar(seed, SizeOf(seed), 0);

  pos := 0;
  if not ReadAsn1TLV(der, pos, tag, seqStart, seqLen) then
  begin
    err := 'PKCS#8 parse failed (outer)';
    Exit;
  end;
  if tag <> $30 then
  begin
    err := 'PKCS#8 outer is not SEQUENCE';
    Exit;
  end;

  innerPos := seqStart;
  // version INTEGER
  if not ReadAsn1TLV(der, innerPos, t2, s2, l2) then
  begin
    err := 'PKCS#8 parse failed (version)';
    Exit;
  end;
  if t2 <> $02 then
  begin
    err := 'PKCS#8 version is not INTEGER';
    Exit;
  end;

  // algorithm SEQUENCE
  if not ReadAsn1TLV(der, innerPos, t2, algSeqStart, algSeqLen) then
  begin
    err := 'PKCS#8 parse failed (algorithm)';
    Exit;
  end;
  if t2 <> $30 then
  begin
    err := 'PKCS#8 algorithm is not SEQUENCE';
    Exit;
  end;

  algPos := algSeqStart;
  if not ReadAsn1TLV(der, algPos, oidTag, oidStart, oidLen) then
  begin
    err := 'PKCS#8 parse failed (oid)';
    Exit;
  end;
  if oidTag <> $06 then
  begin
    err := 'PKCS#8 algorithm oid is not OID';
    Exit;
  end;
  okOid := OidEqualsEd25519(der, oidStart, oidLen);
  if not okOid then
  begin
    err := 'PKCS#8 algorithm is not Ed25519';
    Exit;
  end;

  // privateKey OCTET STRING
  if not ReadAsn1TLV(der, innerPos, pkTag, pkStart, pkLen) then
  begin
    err := 'PKCS#8 parse failed (privateKey)';
    Exit;
  end;
  if pkTag <> $04 then
  begin
    err := 'PKCS#8 privateKey is not OCTET STRING';
    Exit;
  end;

  // Per RFC 8410, privateKey field contains an OCTET STRING seed (32 bytes)
  // i.e. the OCTET STRING content is itself an ASN.1 OCTET STRING.
  pkInnerPos := pkStart;
  if (pkInnerPos < Length(der)) and (der[pkInnerPos] = $04) then
  begin
    // nested OCTET STRING
    if not ReadAsn1TLV(der, pkInnerPos, octTag, octStart, octLen) then
    begin
      err := 'PKCS#8 parse failed (nested seed)';
      Exit;
    end;
    if (octTag <> $04) or (octLen <> 32) then
    begin
      err := 'PKCS#8 nested seed invalid';
      Exit;
    end;
    Move(der[octStart], tmpSeed[0], 32);
  end
  else
  begin
    // some encoders store raw seed directly
    if pkLen <> 32 then
    begin
      err := 'PKCS#8 seed length invalid';
      Exit;
    end;
    Move(der[pkStart], tmpSeed[0], 32);
  end;

  for i := 0 to 31 do
    seed[i] := tmpSeed[i];

  Result := True;
end;

function TryLoadRawKey(const bytes: TBytes; out key: TEd25519KeyMaterial; out err: string): boolean;
var
  i: Integer;
  pkOk: boolean;
begin
  Result := False;
  err := '';
  FillChar(key, SizeOf(key), 0);

  if Length(bytes) = 64 then
  begin
    for i := 0 to 31 do
      key.seed[i] := bytes[i];
    for i := 0 to 31 do
      key.pubkey[i] := bytes[32 + i];
    Result := True;
    Exit;
  end;

  if Length(bytes) = 32 then
  begin
    for i := 0 to 31 do
      key.seed[i] := bytes[i];
    pkOk := Ed25519PublicKeyFromSeed(key.seed, key.pubkey);
    if not pkOk then
    begin
      err := 'failed to derive public key from seed';
      Exit(False);
    end;
    Result := True;
    Exit;
  end;

  err := 'raw key must be 32-byte seed or 64-byte seed||pubkey';
end;

function LoadEd25519KeyFromFile(const filename: string; out key: TEd25519KeyMaterial; out err: string): boolean;
var
  bytes: TBytes;
  text: AnsiString;
  der: TBytes;
  seed: TEd25519Seed;
  pkOk: boolean;
  i: Integer;
begin
  Result := False;
  err := '';
  FillChar(key, SizeOf(key), 0);

  if not ReadAllBytes(filename, bytes, err) then
    Exit(False);

  if BytesStartsWith(bytes, '-----BEGIN ') then
  begin
    SetString(text, PAnsiChar(@bytes[0]), Length(bytes));
    if not StripPem(string(text), der, err) then
      Exit(False);
    if not ParsePkcs8Ed25519Seed(der, seed, err) then
      Exit(False);
    for i := 0 to 31 do
      key.seed[i] := seed[i];
    pkOk := Ed25519PublicKeyFromSeed(key.seed, key.pubkey);
    if not pkOk then
    begin
      err := 'failed to derive public key from seed';
      Exit(False);
    end;
    Result := True;
    Exit;
  end;

  if not TryLoadRawKey(bytes, key, err) then
    Exit(False);

  Result := True;
end;

end.
