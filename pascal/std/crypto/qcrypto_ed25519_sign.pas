unit qcrypto_ed25519_sign;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  SysUtils;

type
  TEd25519PublicKey = array[0..31] of Byte;
  TEd25519Signature = array[0..63] of Byte;
  TEd25519Seed = array[0..31] of Byte;
  TEd25519PrivateKey64 = array[0..63] of Byte;

function Ed25519PublicKeyFromSeed(const seed: TEd25519Seed; out pk: TEd25519PublicKey): boolean;
function Ed25519Sign(const msg: TBytes; const seed: TEd25519Seed; const pk: TEd25519PublicKey; out sig: TEd25519Signature): boolean;

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
    o[i] := t[i];

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
  idx: Integer;
  rr: array[0..3] of gf;
  pNeg: Integer;
begin
  for idx := 0 to 3 do set25519(rr[idx], gf0);
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

  for idx := 0 to 3 do set25519(r[idx], rr[idx]);
end;

procedure scalarmult(out p: array of gf; const q: array of gf; const scalar: array of u8);
var
  i: Integer;
  b: Integer;
  x: array[0..3] of gf;
begin
  for i := 0 to 3 do set25519(p[i], gf0);
  set25519(p[0], gf0);
  set25519(p[1], gf1);
  set25519(p[2], gf1);
  set25519(p[3], gf0);

  for i := 255 downto 0 do
  begin
    b := (scalar[i shr 3] shr (i and 7)) and 1;
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
  a_, b_, c_, d_, e_, f_, g_, h_: gf;
  t: array[0..3] of gf;
  i: Integer;
begin
  for i := 0 to 3 do set25519(t[i], gf0);

  A(a_, q[1], q[0]);
  Z(b_, q[1], q[0]);
  A(c_, r[1], r[0]);
  Z(d_, r[1], r[0]);

  M(e_, a_, d_);
  M(f_, b_, c_);
  M(g_, q[3], r[3]);
  M(g_, g_, D2);
  M(h_, q[2], r[2]);
  A(h_, h_, h_);

  A(t[0], e_, f_);
  Z(t[1], e_, f_);
  A(t[2], h_, g_);
  Z(t[3], h_, g_);

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

  function s0(x: u64): u64; inline;
  begin
    Result := ROR64(x,1) xor ROR64(x,8) xor (x shr 7);
  end;

  function s1(x: u64): u64; inline;
  begin
    Result := ROR64(x,19) xor ROR64(x,61) xor (x shr 6);
  end;

  function ReadBE64(const bb: array of u8; idx: Integer): u64; inline;
  begin
    Result := (u64(bb[idx + 0]) shl 56) or (u64(bb[idx + 1]) shl 48) or (u64(bb[idx + 2]) shl 40) or (u64(bb[idx + 3]) shl 32) or
              (u64(bb[idx + 4]) shl 24) or (u64(bb[idx + 5]) shl 16) or (u64(bb[idx + 6]) shl 8) or u64(bb[idx + 7]);
  end;

  procedure WriteBE64(out bb: array of u8; idx: Integer; v: u64); inline;
  begin
    bb[idx + 0] := u8(v shr 56);
    bb[idx + 1] := u8(v shr 48);
    bb[idx + 2] := u8(v shr 40);
    bb[idx + 3] := u8(v shr 32);
    bb[idx + 4] := u8(v shr 24);
    bb[idx + 5] := u8(v shr 16);
    bb[idx + 6] := u8(v shr 8);
    bb[idx + 7] := u8(v);
  end;

  procedure Compress(const bblk: array of u8);
  var
    i2: Integer;
  begin
    for i2 := 0 to 15 do
      w[i2] := ReadBE64(bblk, i2 * 8);
    for i2 := 16 to 79 do
      w[i2] := s1(w[i2 - 2]) + w[i2 - 7] + s0(w[i2 - 15]) + w[i2 - 16];

    a := h[0]; b := h[1]; c := h[2]; d := h[3]; e := h[4]; f := h[5]; g := h[6]; hv := h[7];

    for i2 := 0 to 79 do
    begin
      t1 := hv + S164(e) + Ch64(e,f,g) + K512[i2] + w[i2];
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

    h[0] := h[0] + a;
    h[1] := h[1] + b;
    h[2] := h[2] + c;
    h[3] := h[3] + d;
    h[4] := h[4] + e;
    h[5] := h[5] + f;
    h[6] := h[6] + g;
    h[7] := h[7] + hv;
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
  while off + 128 <= mlen do
  begin
    p := @m[off];
    Move(p^, block[0], 128);
    Compress(block);
    Inc(off, 128);
  end;

  rem := mlen - off;
  FillChar(block, SizeOf(block), 0);
  if rem > 0 then
  begin
    p := @m[off];
    Move(p^, block[0], rem);
  end;
  block[rem] := $80;

  if rem >= 112 then
  begin
    Compress(block);
    FillChar(block, SizeOf(block), 0);
  end;

  bitlen := mlen * 8;
  for j := 0 to 7 do
    block[127 - j] := u8(bitlen shr (j*8));

  Compress(block);

  for i := 0 to 7 do
    WriteBE64(outb, i*8, h[i]);
end;

procedure reduce32(var s: array of u8);
var
  r: array[0..31] of u8;
  x: array[0..63] of u8;
  i: Integer;
begin
  for i := 0 to 63 do x[i] := 0;
  for i := 0 to 31 do x[i] := s[i];
  modL(r, x, 64);
  for i := 0 to 31 do s[i] := r[i];
end;

procedure reduce64(var s: array of u8);
var
  r: array[0..31] of u8;
  i: Integer;
begin
  modL(r, s, 64);
  for i := 0 to 31 do s[i] := r[i];
  for i := 32 to 63 do s[i] := 0;
end;

procedure sc_muladd(out s: array of u8; const a, b, c: array of u8);
var
  i: Integer;
  carry: i64;
  x: array[0..63] of i64;
  r: array[0..63] of u8;
  aa, bb, cc: array[0..31] of u8;
  j: Integer;
  t: i64;
  tmp: array[0..63] of u8;
begin
  for i := 0 to 63 do x[i] := 0;
  for i := 0 to 31 do
  begin
    aa[i] := a[i];
    bb[i] := b[i];
    cc[i] := c[i];
  end;

  for i := 0 to 31 do
  begin
    carry := 0;
    for j := 0 to 31 do
    begin
      t := x[i + j] + i64(aa[i]) * i64(bb[j]) + carry;
      x[i + j] := t and $FF;
      carry := t shr 8;
    end;
    x[i + 32] := x[i + 32] + carry;
  end;

  for i := 0 to 31 do
    x[i] := x[i] + i64(cc[i]);

  for i := 0 to 63 do
    tmp[i] := u8(x[i] and $FF);

  modL(r, tmp, 64);
  for i := 0 to 31 do
    s[i] := r[i];
end;

function Ed25519PublicKeyFromSeed(const seed: TEd25519Seed; out pk: TEd25519PublicKey): boolean;
var
  h: array[0..63] of u8;
  a: array[0..31] of u8;
  A_: array[0..3] of gf;
  enc: array[0..31] of u8;
  i: Integer;
  seedBytes: array[0..31] of u8;
begin
  Result := False;
  for i := 0 to 31 do seedBytes[i] := seed[i];
  sha512(h, seedBytes, 32);
  for i := 0 to 31 do a[i] := h[i];
  a[0] := a[0] and 248;
  a[31] := a[31] and 127;
  a[31] := a[31] or 64;

  scalarbase(A_, a);
  pack(enc, A_);
  for i := 0 to 31 do pk[i] := enc[i];
  Result := True;
end;

function Ed25519Sign(const msg: TBytes; const seed: TEd25519Seed; const pk: TEd25519PublicKey; out sig: TEd25519Signature): boolean;
var
  h: array[0..63] of u8;
  az: array[0..31] of u8;
  prefix: array[0..31] of u8;
  buf: TBytes;
  rh: array[0..63] of u8;
  rred: array[0..31] of u8;
  R_: array[0..3] of gf;
  Renc: array[0..31] of u8;
  hram: array[0..63] of u8;
  hram32: array[0..31] of u8;
  S: array[0..31] of u8;
  i: Integer;
  pkbytes: array[0..31] of u8;
  seedBytes: array[0..31] of u8;

  procedure crypto_hash_sha512_bytes(out outb: array of u8; const b: TBytes);
  begin
    if Length(b) = 0 then
      sha512(outb, _0, 0)
    else
      sha512(outb, b, u64(Length(b)));
  end;

begin
  Result := False;
  for i := 0 to 31 do
  begin
    seedBytes[i] := seed[i];
    pkbytes[i] := pk[i];
  end;

  sha512(h, seedBytes, 32);
  for i := 0 to 31 do az[i] := h[i];
  az[0] := az[0] and 248;
  az[31] := az[31] and 127;
  az[31] := az[31] or 64;
  for i := 0 to 31 do prefix[i] := h[32 + i];

  SetLength(buf, 32 + Length(msg));
  Move(prefix[0], buf[0], 32);
  if Length(msg) > 0 then
    Move(msg[0], buf[32], Length(msg));
  crypto_hash_sha512_bytes(rh, buf);
  for i := 0 to 31 do rred[i] := rh[i];
  modL(rred, rh, 64);

  scalarbase(R_, rred);
  pack(Renc, R_);

  SetLength(buf, 32 + 32 + Length(msg));
  Move(Renc[0], buf[0], 32);
  Move(pkbytes[0], buf[32], 32);
  if Length(msg) > 0 then
    Move(msg[0], buf[64], Length(msg));
  crypto_hash_sha512_bytes(hram, buf);
  for i := 0 to 31 do hram32[i] := hram[i];
  modL(hram32, hram, 64);

  sc_muladd(S, hram32, az, rred);

  for i := 0 to 31 do sig[i] := Renc[i];
  for i := 0 to 31 do sig[32 + i] := S[i];
  Result := True;
end;

end.
