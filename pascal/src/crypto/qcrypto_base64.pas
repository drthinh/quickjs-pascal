unit qcrypto_base64;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function Base64Decode(const s: string; out bytes: TBytes): boolean;
function Base64Encode(const bytes: TBytes): string;

implementation

function IsWhitespace(c: Char): boolean; inline;
begin
  Result := (c = ' ') or (c = #9) or (c = #10) or (c = #13);
end;

function Base64Index(c: Char): Integer; inline;
begin
  case c of
    'A'..'Z': Result := Ord(c) - Ord('A');
    'a'..'z': Result := Ord(c) - Ord('a') + 26;
    '0'..'9': Result := Ord(c) - Ord('0') + 52;
    '+': Result := 62;
    '/': Result := 63;
  else
    Result := -1;
  end;
end;

function Base64Decode(const s: string; out bytes: TBytes): boolean;
var
  clean: string;
  i, j: Integer;
  c: Char;
  v: Integer;
  buf: array[0..3] of Integer;
  pad: Integer;
  outLen: Integer;
  outPos: Integer;
begin
  Result := False;
  clean := '';
  bytes := nil;

  // strip whitespace
  SetLength(clean, 0);
  SetLength(clean, Length(s));
  j := 0;
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if not IsWhitespace(c) then
    begin
      Inc(j);
      clean[j] := c;
    end;
  end;
  SetLength(clean, j);

  if (Length(clean) = 0) then
  begin
    Result := True;
    Exit;
  end;

  if (Length(clean) mod 4) <> 0 then
    Exit;

  // compute output length
  pad := 0;
  if (Length(clean) >= 1) and (clean[Length(clean)] = '=') then
    Inc(pad);
  if (Length(clean) >= 2) and (clean[Length(clean) - 1] = '=') then
    Inc(pad);

  outLen := (Length(clean) div 4) * 3 - pad;
  if outLen < 0 then
    Exit;

  SetLength(bytes, outLen);
  outPos := 0;

  i := 1;
  while i <= Length(clean) do
  begin
    for j := 0 to 3 do
    begin
      c := clean[i + j];
      if c = '=' then
        buf[j] := -2
      else
      begin
        v := Base64Index(c);
        if v < 0 then
          Exit;
        buf[j] := v;
      end;
    end;

    // first byte
    if (buf[0] < 0) or (buf[1] < 0) then
      Exit;
    if outPos < outLen then
    begin
      bytes[outPos] := Byte((buf[0] shl 2) or (buf[1] shr 4));
      Inc(outPos);
    end;

    // second byte
    if buf[2] <> -2 then
    begin
      if buf[2] < 0 then
        Exit;
      if outPos < outLen then
      begin
        bytes[outPos] := Byte(((buf[1] and $F) shl 4) or (buf[2] shr 2));
        Inc(outPos);
      end;
    end
    else
    begin
      // padding implies buf[3] must also be padding
      if buf[3] <> -2 then
        Exit;
      Break;
    end;

    // third byte
    if buf[3] <> -2 then
    begin
      if buf[3] < 0 then
        Exit;
      if outPos < outLen then
      begin
        bytes[outPos] := Byte(((buf[2] and 3) shl 6) or buf[3]);
        Inc(outPos);
      end;
    end
    else
      Break;

    Inc(i, 4);
  end;

  Result := outPos = outLen;
end;

function Base64Encode(const bytes: TBytes): string;
const
  ENC: PChar = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  i: Integer;
  b0, b1, b2: Byte;
  remain: Integer;
  outLen: Integer;
  n: Integer;
  p: PChar;
begin
  if Length(bytes) = 0 then
    Exit('');

  outLen := ((Length(bytes) + 2) div 3) * 4;
  SetLength(Result, outLen);
  p := PChar(Result);

  i := 0;
  n := 0;
  while i < Length(bytes) do
  begin
    remain := Length(bytes) - i;
    b0 := bytes[i];
    if remain > 1 then
      b1 := bytes[i + 1]
    else
      b1 := 0;
    if remain > 2 then
      b2 := bytes[i + 2]
    else
      b2 := 0;

    p[n + 0] := ENC[(b0 shr 2) and $3F];
    p[n + 1] := ENC[((b0 and 3) shl 4) or ((b1 shr 4) and $0F)];

    if remain > 1 then
      p[n + 2] := ENC[((b1 and $0F) shl 2) or ((b2 shr 6) and 3)]
    else
      p[n + 2] := '=';

    if remain > 2 then
      p[n + 3] := ENC[b2 and $3F]
    else
      p[n + 3] := '=';

    Inc(i, 3);
    Inc(n, 4);
  end;
end;

end.
