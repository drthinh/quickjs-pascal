unit qcrypto_ed25519_verify;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  SysUtils;

type
  TEd25519PublicKey = array[0..31] of Byte;
  TEd25519Signature = array[0..63] of Byte;

function Ed25519Verify(const msg: TBytes; const sig: TEd25519Signature; const pk: TEd25519PublicKey): boolean;

implementation

type
  u8 = Byte;
  u32 = Cardinal;
  u64 = QWord;
  i64 = Int64;
  gf = array[0..15] of i64;

const
  _0: array[0..15] of u8 = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
  _9: array[0..31] of u8 = (9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);

  gf0: gf = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
  gf1: gf = (1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);

  _121665: gf = ($DB41,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0);

  D: gf = ($78a3, $1359, $4dca, $75eb, $d8ab, $4141, $0a4d, $0070, $e898, $7779, $4079, $8cc7, $fe73, $2b6f, $6cee, $5203);
  D2: gf = ($f159, $26b2, $9b94, $ebd6, $b156, $8283, $149a, $00e0, $d130, $eef3, $80f2, $198e, $fce7, $56df, $d9dc, $2406);
  X: gf = ($d51a, $8f25, $2d60, $c956, $a7b2, $9525, $c760, $692c, $dc5c, $fdd6, $e231, $c0a4, $53fe, $cd6e, $36d3, $2169);
  Y: gf = ($6658, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666);
  I: gf = ($a0b0, $4a0e, $1b27, $c4ee, $e478, $ad2f, $1806, $2f43, $d7a7, $3dfb, $0099, $2b4d, $df0b, $4fc1, $2480, $2b83);

  L: array[0..31] of u8 = (
    $ed,$d3,$f5,$5c,$1a,$63,$12,$58,
    $d6,$9c,$f7,$a2,$de,$f9,$de,$14,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,$10
  );

function vn(const x, y: array of u8; n: Integer): Integer; inline;
var
  i: Integer;
  d: u32;
begin
  d := 0;
  for i := 0 to n - 1 do
    d := d or (x[i] xor y[i]);
  Result := (1 and ((d - 1) shr 8)) - 1;
end;

function crypto_verify_32(const x, y: array of u8): Integer; inline;
begin
  Result := vn(x, y, 32);
end;

procedure set25519(out r: gf; const a: gf); inline;
var i: Integer;
begin
  for i := 0 to 15 do r[i] := a[i];
end;

procedure car25519(var o: gf);
var
  i: Integer;
  c: i64;
begin
  for i := 0 to 15 do
  begin
    o[i] := o[i] + (1 shl 16);
    c := o[i] shr 16;
    if i < 15 then
      o[i + 1] := o[i + 1] + c - 1
    else
      o[0] := o[0] + (c - 1) * 38;
    o[i] := o[i] - (c shl 16);
  end;
end;

procedure sel25519(var p, q: gf; b: Integer);
var
  i: Integer;
  t: i64;
  c: i64;
begin
  c := -i64(b);
  for i := 0 to 15 do
  begin
    t := c and (p[i] xor q[i]);
    p[i] := p[i] xor t;
    q[i] := q[i] xor t;
  end;
end;

procedure pack25519(out o: array of u8; var n: gf);
var
  i, j: Integer;
  m: gf;
  t: gf;
  b: i64;
begin
  set25519(t, n);
  car25519(t);
  car25519(t);
  car25519(t);

  for j := 0 to 1 do
  begin
    m[0] := t[0] - $ffed;
    for i := 1 to 14 do
    begin
      m[i] := t[i] - $ffff - ((m[i - 1] shr 16) and 1);
      m[i - 1] := m[i - 1] and $ffff;
    end;
    m[15] := t[15] - $7fff - ((m[14] shr 16) and 1);
    b := (m[15] shr 16) and 1;
    m[14] := m[14] and $ffff;
    sel25519(t, m, 1 - Integer(b));
  end;

  for i := 0 to 15 do
  begin
    o[2 * i] := u8(t[i] and $ff);
    o[2 * i + 1] := u8((t[i] shr 8) and $ff);
  end;
end;

procedure unpack25519(out o: gf; const n: array of u8);
var i: Integer;
begin
  for i := 0 to 15 do
    o[i] := n[2 * i] + (i64(n[2 * i + 1]) shl 8);
  o[15] := o[15] and $7fff;
end;

procedure A(out o: gf; const a, b: gf); inline;
var i: Integer;
begin
  for i := 0 to 15 do o[i] := a[i] + b[i];
end;

procedure Z(out o: gf; const a, b: gf); inline;
var i: Integer;
begin
  for i := 0 to 15 do o[i] := a[i] - b[i];
end;

procedure M(out o: gf; const a, b: gf);
var
  i, j: Integer;
  t: array[0..31] of i64;
  c: i64;
begin
  for i := 0 to 31 do t[i] := 0;
  for i := 0 to 15 do
    for j := 0 to 15 do
      t[i + j] := t[i + j] + a[i] * b[j];

  for i := 0 to 15 do
    t[i] := t[i] + 38 * t[i + 16];

  for i := 0 to 15 do
  begin
    o[i] := t[i];
  end;

  for i := 0 to 15 do
  begin
    o[i] := o[i] + (1 shl 16);
    c := o[i] shr 16;
    if i < 15 then
      o[i + 1] := o[i + 1] + c - 1
    else
      o[0] := o[0] + (c - 1) * 38;
    o[i] := o[i] - (c shl 16);
  end;

  car25519(o);
  car25519(o);
end;

procedure S(out o: gf; const a: gf); inline;
begin
  M(o, a, a);
end;

procedure inv25519(out o: gf; const i_: gf);
var
  c: gf;
  a: Integer;
begin
  set25519(c, i_);
  for a := 253 downto 0 do
  begin
    S(c, c);
    if (a <> 2) and (a <> 4) then
      M(c, c, i_);
  end;
  set25519(o, c);
end;

procedure pow2523(out o: gf; const i_: gf);
var
  c: gf;
  a: Integer;
begin
  set25519(c, i_);
  for a := 250 downto 0 do
  begin
    S(c, c);
    if a <> 1 then
      M(c, c, i_);
  end;
  set25519(o, c);
end;

function neq25519(var a, b: gf): Integer;
var
  c, d: array[0..31] of u8;
  aa, bb: gf;
begin
  set25519(aa, a);
  set25519(bb, b);
  pack25519(c, aa);
  pack25519(d, bb);
  Result := crypto_verify_32(c, d);
end;

function par25519(var a: gf): u8;
var
  d: array[0..31] of u8;
  aa: gf;
begin
  set25519(aa, a);
  pack25519(d, aa);
  Result := d[0] and 1;
end;

procedure unpackneg(out r: array of gf; const p: array of u8);
var
  t, chk, num, den, den2, den4, den6: gf;
  i: Integer;
  rr: array[0..3] of gf;
  pNeg: Integer;
begin
  for i := 0 to 3 do set25519(rr[i], gf0);
  unpack25519(rr[1], p);
  S(num, rr[1]);
  M(den, num, D);
  Z(num, num, gf1);
  A(den, den, gf1);

  S(den2, den);
  S(den4, den2);
  M(den6, den4, den2);
  M(t, den6, num);
  M(t, t, den);

  pow2523(t, t);
  M(t, t, num);
  M(t, t, den);
  M(t, t, den);
  M(rr[0], t, den);

  S(chk, rr[0]);
  M(chk, chk, den);
  if neq25519(chk, num) <> 0 then
    M(rr[0], rr[0], I);

  S(chk, rr[0]);
  M(chk, chk, den);
  if neq25519(chk, num) <> 0 then
    raise Exception.Create('ed25519: bad public key');

  pNeg := (p[31] shr 7) and 1;
  if par25519(rr[0]) = u8(pNeg) then
    Z(rr[0], gf0, rr[0]);

  M(rr[3], rr[0], rr[1]);
  set25519(rr[2], gf1);

  for i := 0 to 3 do set25519(r[i], rr[i]);
end;

procedure scalarmult(out p: array of gf; const q: array of gf; const s: array of u8);
var
  i: Integer;
  b: Integer;
  a: Integer;
  x: array[0..3] of gf;
begin
  for i := 0 to 3 do set25519(p[i], gf0);
  set25519(p[0], gf0);
  set25519(p[1], gf1);
  set25519(p[2], gf1);
  set25519(p[3], gf0);

  for i := 255 downto 0 do
  begin
    b := (s[i shr 3] shr (i and 7)) and 1;
    sel25519(p[0], p[1], b);
    sel25519(p[2], p[3], b);

    A(x[0], p[0], p[2]);
    Z(x[1], p[0], p[2]);
    A(x[2], p[1], p[3]);
    Z(x[3], p[1], p[3]);

    M(p[0], x[0], x[3]);
    M(p[1], x[2], x[1]);
    A(x[0], p[0], p[1]);
    Z(x[1], p[0], p[1]);

    S(p[0], x[0]);
    S(p[1], x[1]);

    M(p[2], x[0], x[1]);
    S(x[0], p[2]);
    Z(x[1], p[0], x[0]);
    M(x[2], x[1], _121665);
    A(x[2], x[2], x[0]);
    M(p[3], x[1], x[2]);

    sel25519(p[0], p[1], b);
    sel25519(p[2], p[3], b);
  end;

  for i := 0 to 3 do set25519(x[i], p[i]);
  for i := 0 to 3 do set25519(p[i], x[i]);
end;

procedure scalarbase(out p: array of gf; const s: array of u8);
var
  q: array[0..3] of gf;
  i: Integer;
begin
  for i := 0 to 3 do set25519(q[i], gf0);
  set25519(q[0], X);
  set25519(q[1], Y);
  set25519(q[2], gf1);
  M(q[3], X, Y);
  scalarmult(p, q, s);
end;

procedure add(out p: array of gf; const q, r: array of gf);
var
  a, b, c, d, e, f, g, h_: gf;
  t: array[0..3] of gf;
  i: Integer;
begin
  for i := 0 to 3 do set25519(t[i], gf0);

  A(a, q[1], q[0]);
  Z(b, q[1], q[0]);
  A(c, r[1], r[0]);
  Z(d, r[1], r[0]);

  M(e, a, d);
  M(f, b, c);
  M(g, q[3], r[3]);
  M(g, g, D2);
  M(h_, q[2], r[2]);
  A(h_, h_, h_);

  A(t[0], e, f);
  Z(t[1], e, f);
  A(t[2], h_, g);
  Z(t[3], h_, g);

  M(p[0], t[0], t[3]);
  M(p[1], t[2], t[1]);
  M(p[2], t[2], t[3]);
  M(p[3], t[0], t[1]);
end;

procedure pack(out r: array of u8; const p: array of gf);
var
  tx, ty, zi: gf;
  outp: array[0..31] of u8;
  xx, yy: gf;
begin
  inv25519(zi, p[2]);
  M(tx, p[0], zi);
  M(ty, p[1], zi);
  xx := tx;
  yy := ty;
  pack25519(outp, yy);
  outp[31] := outp[31] xor (par25519(xx) shl 7);
  Move(outp[0], r[0], 32);
end;

procedure modL(out r: array of u8; const x: array of u8; xlen: Integer);
var
  i, j: Integer;
  carry: i64;
  c: i64;
  tmp: array[0..63] of i64;
  xr: array[0..63] of u8;
begin
  for i := 0 to 63 do
    tmp[i] := 0;

  for i := 0 to 63 do
  begin
    if i < xlen then
      xr[i] := x[i]
    else
      xr[i] := 0;
    tmp[i] := xr[i];
  end;

  for i := 63 downto 32 do
  begin
    carry := 0;
    for j := i - 32 to i - 1 do
    begin
      tmp[j] := tmp[j] + carry - 16 * tmp[i] * i64(L[j - (i - 32)]);
      carry := (tmp[j] + 128) shr 8;
      tmp[j] := tmp[j] - (carry shl 8);
    end;
    tmp[i - 32] := tmp[i - 32] + carry;
    tmp[i] := 0;
  end;

  carry := 0;
  for j := 0 to 31 do
  begin
    tmp[j] := tmp[j] + carry;
    carry := tmp[j] shr 8;
    tmp[j] := tmp[j] and 255;
  end;

  for j := 0 to 31 do
    r[j] := u8(tmp[j]);

  for i := 0 to 31 do
  begin
    c := 0;
    for j := 0 to 31 do
      c := c or (i64(r[j]) - i64(L[j]));
    if c >= 0 then
    begin
      carry := 0;
      for j := 0 to 31 do
      begin
        c := i64(r[j]) - i64(L[j]) + carry;
        r[j] := u8(c and 255);
        carry := c shr 8;
      end;
    end;
  end;
end;

procedure sha512(out outb: array of u8; const m: array of u8; mlen: u64);
const
  K512: array[0..79] of u64 = (
    $428a2f98d728ae22,$7137449123ef65cd,$b5c0fbcfec4d3b2f,$e9b5dba58189dbbc,
    $3956c25bf348b538,$59f111f1b605d019,$923f82a4af194f9b,$ab1c5ed5da6d8118,
    $d807aa98a3030242,$12835b0145706fbe,$243185be4ee4b28c,$550c7dc3d5ffb4e2,
    $72be5d74f27b896f,$80deb1fe3b1696b1,$9bdc06a725c71235,$c19bf174cf692694,
    $e49b69c19ef14ad2,$efbe4786384f25e3,$0fc19dc68b8cd5b5,$240ca1cc77ac9c65,
    $2de92c6f592b0275,$4a7484aa6ea6e483,$5cb0a9dcbd41fbd4,$76f988da831153b5,
    $983e5152ee66dfab,$a831c66d2db43210,$b00327c898fb213f,$bf597fc7beef0ee4,
    $c6e00bf33da88fc2,$d5a79147930aa725,$06ca6351e003826f,$142929670a0e6e70,
    $27b70a8546d22ffc,$2e1b21385c26c926,$4d2c6dfc5ac42aed,$53380d139d95b3df,
    $650a73548baf63de,$766a0abb3c77b2a8,$81c2c92e47edaee6,$92722c851482353b,
    $a2bfe8a14cf10364,$a81a664bbc423001,$c24b8b70d0f89791,$c76c51a30654be30,
    $d192e819d6ef5218,$d69906245565a910,$f40e35855771202a,$106aa07032bbd1b8,
    $19a4c116b8d2d0c8,$1e376c085141ab53,$2748774cdf8eeb99,$34b0bcb5e19b48a8,
    $391c0cb3c5c95a63,$4ed8aa4ae3418acb,$5b9cca4f7763e373,$682e6ff3d6b2b8a3,
    $748f82ee5defb2fc,$78a5636f43172f60,$84c87814a1f0ab72,$8cc702081a6439ec,
    $90befffa23631e28,$a4506cebde82bde9,$bef9a3f7b2c67915,$c67178f2e372532b,
    $ca273eceea26619c,$d186b8c721c0c207,$eada7dd6cde0eb1e,$f57d4f7fee6ed178,
    $06f067aa72176fba,$0a637dc5a2c898a6,$113f9804bef90dae,$1b710b35131c471b,
    $28db77f523047d84,$32caab7b40c72493,$3c9ebe0a15c9bebc,$431d67c49c100d4c,
    $4cc5d4becb3e42b6,$597f299cfc657e2a,$5fcb6fab3ad6faec,$6c44198c4a475817
  );
var
  h: array[0..7] of u64;
  w: array[0..79] of u64;
  a,b,c,d,e,f,g,hv: u64;
  t1,t2: u64;
  i,j: Integer;
  off: u64;
  block: array[0..127] of u8;
  bitlen: u64;
  rem: u64;
  p: PByte;

  function ROR64(x: u64; n: Integer): u64; inline;
  begin
    Result := (x shr n) or (x shl (64 - n));
  end;

  function Ch64(x,y,z: u64): u64; inline;
  begin
    Result := (x and y) xor ((not x) and z);
  end;

  function Maj64(x,y,z: u64): u64; inline;
  begin
    Result := (x and y) xor (x and z) xor (y and z);
  end;

  function S064(x: u64): u64; inline;
  begin
    Result := ROR64(x,28) xor ROR64(x,34) xor ROR64(x,39);
  end;

  function S164(x: u64): u64; inline;
  begin
    Result := ROR64(x,14) xor ROR64(x,18) xor ROR64(x,41);
  end;

  function s064(x: u64): u64; inline;
  begin
    Result := ROR64(x,1) xor ROR64(x,8) xor (x shr 7);
  end;

  function s164(x: u64): u64; inline;
  begin
    Result := ROR64(x,19) xor ROR64(x,61) xor (x shr 6);
  end;

  function ReadBE64(const pp: PByte): u64; inline;
  var k: Integer;
  begin
    Result := 0;
    for k := 0 to 7 do
      Result := (Result shl 8) or pp[k];
  end;

  procedure WriteBE64(var outarr: array of u8; idx: Integer; v: u64); inline;
  var k: Integer;
  begin
    for k := 0 to 7 do
      outarr[idx + k] := u8(v shr (56 - 8*k));
  end;

  procedure Compress(const blk: array of u8);
  var pp2: PByte;
  begin
    pp2 := @blk[0];
    for i := 0 to 15 do
    begin
      w[i] := ReadBE64(pp2);
      Inc(pp2, 8);
    end;
    for i := 16 to 79 do
      w[i] := s164(w[i-2]) + w[i-7] + s064(w[i-15]) + w[i-16];

    a := h[0]; b := h[1]; c := h[2]; d := h[3]; e := h[4]; f := h[5]; g := h[6]; hv := h[7];
    for i := 0 to 79 do
    begin
      t1 := hv + S164(e) + Ch64(e,f,g) + K512[i] + w[i];
      t2 := S064(a) + Maj64(a,b,c);
      hv := g;
      g := f;
      f := e;
      e := d + t1;
      d := c;
      c := b;
      b := a;
      a := t1 + t2;
    end;
    Inc(h[0], a);
    Inc(h[1], b);
    Inc(h[2], c);
    Inc(h[3], d);
    Inc(h[4], e);
    Inc(h[5], f);
    Inc(h[6], g);
    Inc(h[7], hv);
  end;

begin
  h[0] := $6a09e667f3bcc908;
  h[1] := $bb67ae8584caa73b;
  h[2] := $3c6ef372fe94f82b;
  h[3] := $a54ff53a5f1d36f1;
  h[4] := $510e527fade682d1;
  h[5] := $9b05688c2b3e6c1f;
  h[6] := $1f83d9abfb41bd6b;
  h[7] := $5be0cd19137e2179;

  off := 0;
  p := @m[0];
  while off + 128 <= mlen do
  begin
    Move(p^, block[0], 128);
    Compress(block);
    Inc(p, 128);
    Inc(off, 128);
  end;

  rem := mlen - off;
  FillChar(block, SizeOf(block), 0);
  if rem > 0 then
    Move(p^, block[0], rem);
  block[rem] := $80;

  if rem >= 112 then
  begin
    Compress(block);
    FillChar(block, SizeOf(block), 0);
  end;

  bitlen := mlen * 8;
  // high 64 bits are zero for our usage
  for j := 0 to 7 do
    block[127 - j] := u8(bitlen shr (j*8));

  Compress(block);

  for i := 0 to 7 do
    WriteBE64(outb, i*8, h[i]);
end;

procedure reduce(var r: array of u8);
var
  x: array[0..63] of u8;
  i: Integer;
begin
  for i := 0 to 63 do x[i] := r[i];
  modL(r, x, 64);
end;

procedure crypto_hash_sha512(out outb: array of u8; const m: array of u8; mlen: u64);
begin
  sha512(outb, m, mlen);
end;

procedure crypto_sign_open_prepare(out hram: array of u8; const sig: TEd25519Signature; const pk: TEd25519PublicKey; const msg: TBytes);
var
  buf: TBytes;
  hh: array[0..63] of u8;
  i: Integer;
begin
  SetLength(buf, 32 + 32 + Length(msg));
  Move(sig[0], buf[0], 32);
  Move(pk[0], buf[32], 32);
  if Length(msg) > 0 then
    Move(msg[0], buf[64], Length(msg));
  crypto_hash_sha512(hh, buf, u64(Length(buf)));
  for i := 0 to 63 do
    hram[i] := hh[i];
  reduce(hram);
end;

function check_ge(const p: array of gf): boolean;
var
  s: array[0..31] of u8;
  t: array[0..31] of u8;
  i: Integer;
  tt: array[0..31] of u8;
  tmp: gf;
  outp: array[0..31] of u8;
  q: array[0..3] of gf;
  u: gf;
  v: gf;
  w: gf;
  x: gf;
  y: gf;
begin
  pack(outp, p);
  for i := 0 to 31 do s[i] := outp[i];
  // reject non-canonical encodings: compare to itself after mask
  // tweetnacl does this via unpackneg failure or high bits; we do minimal: top bit ignored in unpack
  // Ensure point is on curve via unpackneg used by caller.
  Result := True;
end;

function Ed25519Verify(const msg: TBytes; const sig: TEd25519Signature; const pk: TEd25519PublicKey): boolean;
var
  q: array[0..3] of gf;
  p2: array[0..3] of gf;
  p3: array[0..3] of gf;
  sbuf: array[0..31] of u8;
  hram: array[0..63] of u8;
  rcheck: array[0..31] of u8;
  rcalc: array[0..31] of u8;
  i: Integer;
  sigR: array[0..31] of u8;
  sigS: array[0..31] of u8;
  Sbytes: array[0..31] of u8;
  Aneg: array[0..3] of gf;
  h32: array[0..31] of u8;
  a: array[0..31] of u8;
  t: array[0..3] of gf;
  p: array[0..3] of gf;
  s: array[0..31] of u8;
  htmp: array[0..63] of u8;
  small: array[0..63] of u8;
  pkbytes: array[0..31] of u8;
  sSig: array[0..31] of u8;
  bufmsg: TBytes;
  bad: boolean;
  Lcmp: Integer;
  carry: Integer;
  xcmp: i64;
  tmp64: array[0..63] of u8;
  sc: array[0..31] of u8;
  rr: array[0..31] of u8;
  hs: array[0..63] of u8;
  mul: array[0..3] of gf;
  base: array[0..3] of gf;
  Ap: array[0..3] of gf;
  h32red: array[0..31] of u8;
  hs32: array[0..31] of u8;
  Sred: array[0..31] of u8;
  Pb: array[0..3] of gf;
  left: array[0..3] of gf;
  right: array[0..3] of gf;
  Psum: array[0..3] of gf;
  outp: array[0..31] of u8;
  chk: Integer;
  Ss: array[0..63] of u8;
  Sred64: array[0..63] of u8;
  pkarr: array[0..31] of u8;
  rarr: array[0..31] of u8;
  msgarr: TBytes;
  hfull: array[0..63] of u8;
  hred: array[0..63] of u8;
  s32: array[0..31] of u8;
  Rcalc: array[0..31] of u8;
  Rsig: array[0..31] of u8;
  geA: array[0..3] of gf;
  geR: array[0..3] of gf;
  sbytes2: array[0..31] of u8;
  hsbytes: array[0..63] of u8;
  hsredbytes: array[0..63] of u8;
  hsred32: array[0..31] of u8;
  pleft: array[0..3] of gf;
  pright: array[0..3] of gf;
  sum: array[0..3] of gf;
  packed: array[0..31] of u8;
  sigRbytes: array[0..31] of u8;
  sigSbytes: array[0..31] of u8;
  Scheck: array[0..31] of u8;
  ok: boolean;

  function is_S_canonical(const s_: array of u8): boolean;
  var
    i2: Integer;
    carry2: Integer;
    c2: i64;
  begin
    // check s < L
    carry2 := 0;
    for i2 := 0 to 31 do
    begin
      c2 := i64(s_[i2]) - i64(L[i2]) - carry2;
      carry2 := 0;
      if c2 < 0 then
      begin
        c2 := c2 + 256;
        carry2 := 1;
      end;
    end;
    Result := carry2 <> 0; // borrow means s < L
  end;

var
  h: array[0..63] of u8;
  h32_: array[0..31] of u8;
  A: array[0..3] of gf;
  R: array[0..3] of gf;
  SB: array[0..3] of gf;
  hA: array[0..3] of gf;
  check: array[0..31] of u8;
  packedR: array[0..31] of u8;
  i2: Integer;
  tmpb: TBytes;
  hram64: array[0..63] of u8;
  hram32: array[0..31] of u8;
  sScalar: array[0..31] of u8;
  sbytes_: array[0..31] of u8;
  pSum: array[0..3] of gf;
  negA: array[0..3] of gf;
  pTmp: array[0..3] of gf;
  hh: array[0..63] of u8;
  buf: TBytes;
  Renc: array[0..31] of u8;
  i3: Integer;
  okSig: boolean;

begin
  // split sig
  for i2 := 0 to 31 do sigRbytes[i2] := sig[i2];
  for i2 := 0 to 31 do sigSbytes[i2] := sig[32 + i2];

  // S must be < L
  if not is_S_canonical(sigSbytes) then
    Exit(False);

  // decode public key
  try
    unpackneg(A, pk);
  except
    Exit(False);
  end;

  // compute h = H(R || A || M) reduced
  crypto_sign_open_prepare(h, sig, pk, msg);
  for i2 := 0 to 31 do h32_[i2] := h[i2];

  // compute SB = s * B
  for i2 := 0 to 31 do sScalar[i2] := sigSbytes[i2];
  scalarbase(SB, sScalar);

  // compute hA = h * A
  scalarmult(hA, A, h);

  // compute R' = SB + (-hA)
  // negate hA: (X,Y,Z,T) -> (-X,Y,Z,-T)
  set25519(negA[0], gf0); set25519(negA[1], gf0); set25519(negA[2], gf0); set25519(negA[3], gf0);
  Z(negA[0], gf0, hA[0]);
  set25519(negA[1], hA[1]);
  set25519(negA[2], hA[2]);
  Z(negA[3], gf0, hA[3]);

  add(pSum, SB, negA);
  pack(packedR, pSum);

  // compare packedR with sigR (with sign bit preserved)
  for i2 := 0 to 31 do Renc[i2] := sigRbytes[i2];
  okSig := crypto_verify_32(packedR, Renc) = 0;
  Result := okSig;
end;

end.
