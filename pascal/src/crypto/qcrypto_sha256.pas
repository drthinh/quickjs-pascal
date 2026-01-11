unit qcrypto_sha256;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  SysUtils;

type
  TSHA256Digest = array[0..31] of Byte;

function Sha256Digest(const data; len: NativeUInt): TSHA256Digest;
function Sha256DigestHex(const data; len: NativeUInt): string;
function Sha256DigestHexBytes(const bytes: TBytes): string;

implementation

type
  TSHA256State = record
    h: array[0..7] of Cardinal;
    buf: array[0..63] of Byte;
    buf_len: Cardinal;
    total_len: QWord;
  end;

function ROR32(x: Cardinal; n: Byte): Cardinal; inline;
begin
  Result := (x shr n) or (x shl (32 - n));
end;

function Ch(x, y, z: Cardinal): Cardinal; inline;
begin
  Result := (x and y) xor ((not x) and z);
end;

function Maj(x, y, z: Cardinal): Cardinal; inline;
begin
  Result := (x and y) xor (x and z) xor (y and z);
end;

function Sigma0(x: Cardinal): Cardinal; inline;
begin
  Result := ROR32(x, 2) xor ROR32(x, 13) xor ROR32(x, 22);
end;

function Sigma1(x: Cardinal): Cardinal; inline;
begin
  Result := ROR32(x, 6) xor ROR32(x, 11) xor ROR32(x, 25);
end;

function SmallSigma0(x: Cardinal): Cardinal; inline;
begin
  Result := ROR32(x, 7) xor ROR32(x, 18) xor (x shr 3);
end;

function SmallSigma1(x: Cardinal): Cardinal; inline;
begin
  Result := ROR32(x, 17) xor ROR32(x, 19) xor (x shr 10);
end;

const
  K: array[0..63] of Cardinal = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2
  );

procedure Sha256Init(out s: TSHA256State);
begin
  FillChar(s, SizeOf(s), 0);
  s.h[0] := $6a09e667;
  s.h[1] := $bb67ae85;
  s.h[2] := $3c6ef372;
  s.h[3] := $a54ff53a;
  s.h[4] := $510e527f;
  s.h[5] := $9b05688c;
  s.h[6] := $1f83d9ab;
  s.h[7] := $5be0cd19;
end;

function ReadBE32(const p: PByte): Cardinal; inline;
begin
  Result := (Cardinal(p[0]) shl 24) or (Cardinal(p[1]) shl 16) or (Cardinal(p[2]) shl 8) or Cardinal(p[3]);
end;

procedure WriteBE32(var outb: TSHA256Digest; idx: Integer; v: Cardinal); inline;
begin
  outb[idx + 0] := Byte(v shr 24);
  outb[idx + 1] := Byte(v shr 16);
  outb[idx + 2] := Byte(v shr 8);
  outb[idx + 3] := Byte(v);
end;

procedure Sha256Compress(var s: TSHA256State; const block: array of Byte);
var
  w: array[0..63] of Cardinal;
  a, b, c, d, e, f, g, h: Cardinal;
  t1, t2: Cardinal;
  i: Integer;
  p: PByte;
begin
  p := @block[0];
  for i := 0 to 15 do
  begin
    w[i] := ReadBE32(p);
    Inc(p, 4);
  end;
  for i := 16 to 63 do
    w[i] := SmallSigma1(w[i - 2]) + w[i - 7] + SmallSigma0(w[i - 15]) + w[i - 16];

  a := s.h[0];
  b := s.h[1];
  c := s.h[2];
  d := s.h[3];
  e := s.h[4];
  f := s.h[5];
  g := s.h[6];
  h := s.h[7];

  for i := 0 to 63 do
  begin
    t1 := h + Sigma1(e) + Ch(e, f, g) + K[i] + w[i];
    t2 := Sigma0(a) + Maj(a, b, c);
    h := g;
    g := f;
    f := e;
    e := d + t1;
    d := c;
    c := b;
    b := a;
    a := t1 + t2;
  end;

  Inc(s.h[0], a);
  Inc(s.h[1], b);
  Inc(s.h[2], c);
  Inc(s.h[3], d);
  Inc(s.h[4], e);
  Inc(s.h[5], f);
  Inc(s.h[6], g);
  Inc(s.h[7], h);
end;

procedure Sha256Update(var s: TSHA256State; const data; len: NativeUInt);
var
  p: PByte;
  take: Cardinal;
  blk: array[0..63] of Byte;
  i: Integer;
begin
  if len = 0 then
    Exit;
  p := @data;
  s.total_len := s.total_len + len;

  while len > 0 do
  begin
    if s.buf_len = 0 then
    begin
      if len >= 64 then
      begin
        Move(p^, blk[0], 64);
        Sha256Compress(s, blk);
        Inc(p, 64);
        Dec(len, 64);
        Continue;
      end;
    end;

    take := 64 - s.buf_len;
    if take > len then
      take := len;
    Move(p^, s.buf[s.buf_len], take);
    Inc(s.buf_len, take);
    Inc(p, take);
    Dec(len, take);

    if s.buf_len = 64 then
    begin
      for i := 0 to 63 do
        blk[i] := s.buf[i];
      Sha256Compress(s, blk);
      s.buf_len := 0;
    end;
  end;
end;

procedure Sha256Final(var s: TSHA256State; out digest: TSHA256Digest);
var
  blk: array[0..63] of Byte;
  i: Integer;
  bit_len: QWord;
  pad_len: Cardinal;
begin
  for i := 0 to 63 do
    blk[i] := 0;

  // Copy remaining buffer
  if s.buf_len > 0 then
    Move(s.buf[0], blk[0], s.buf_len);

  // Append 0x80
  blk[s.buf_len] := $80;

  // If not enough space for length, compress and clear
  if s.buf_len >= 56 then
  begin
    Sha256Compress(s, blk);
    for i := 0 to 63 do
      blk[i] := 0;
  end;

  // Append length in bits (big endian)
  bit_len := s.total_len * 8;
  for i := 0 to 7 do
    blk[63 - i] := Byte(bit_len shr (i * 8));

  Sha256Compress(s, blk);

  for i := 0 to 7 do
    WriteBE32(digest, i * 4, s.h[i]);

  // clear
  FillChar(s, SizeOf(s), 0);
  pad_len := 0;
  pad_len := pad_len; // keep compiler quiet
end;

function Sha256Digest(const data; len: NativeUInt): TSHA256Digest;
var
  s: TSHA256State;
begin
  Sha256Init(s);
  Sha256Update(s, data, len);
  Sha256Final(s, Result);
end;

function BytesToHex(const b: array of Byte): string;
const
  HEX: PChar = '0123456789abcdef';
var
  i: Integer;
  p: PChar;
begin
  SetLength(Result, Length(b) * 2);
  p := PChar(Result);
  for i := 0 to High(b) do
  begin
    p[i * 2 + 0] := HEX[(b[i] shr 4) and $F];
    p[i * 2 + 1] := HEX[b[i] and $F];
  end;
end;

function Sha256DigestHex(const data; len: NativeUInt): string;
var
  d: TSHA256Digest;
  tmp: array[0..31] of Byte;
  i: Integer;
begin
  d := Sha256Digest(data, len);
  for i := 0 to 31 do
    tmp[i] := d[i];
  Result := BytesToHex(tmp);
end;

function Sha256DigestHexBytes(const bytes: TBytes): string;
var
  dummy: Byte;
begin
  if Length(bytes) = 0 then
  begin
    // Sha256Update exits early when len=0, so the data pointer is never dereferenced.
    // Still, we need a valid argument for the untyped const parameter.
    dummy := 0;
    Result := Sha256DigestHex(dummy, 0);
    Exit;
  end;
  Result := Sha256DigestHex(bytes[0], NativeUInt(Length(bytes)));
end;

end.
