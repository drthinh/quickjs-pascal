unit qcrypto_hex;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function BytesToHex(const bytes: TBytes): string;
function HexToBytes(const hex: string; out bytes: TBytes): boolean;

implementation

function Nibble(c: Char): Integer; inline;
begin
  case c of
    '0'..'9': Result := Ord(c) - Ord('0');
    'a'..'f': Result := Ord(c) - Ord('a') + 10;
    'A'..'F': Result := Ord(c) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function BytesToHex(const bytes: TBytes): string;
const
  HEX: PChar = '0123456789abcdef';
var
  i: Integer;
  p: PChar;
begin
  if Length(bytes) = 0 then
    Exit('');
  SetLength(Result, Length(bytes) * 2);
  p := PChar(Result);
  for i := 0 to High(bytes) do
  begin
    p[i * 2 + 0] := HEX[(bytes[i] shr 4) and $F];
    p[i * 2 + 1] := HEX[bytes[i] and $F];
  end;
end;

function HexToBytes(const hex: string; out bytes: TBytes): boolean;
var
  s: string;
  i, j: Integer;
  hi, lo: Integer;
  c: Char;
begin
  Result := False;
  SetLength(bytes, 0);

  // strip whitespace
  SetLength(s, 0);
  SetLength(s, Length(hex));
  j := 0;
  for i := 1 to Length(hex) do
  begin
    c := hex[i];
    if (c <> ' ') and (c <> #9) and (c <> #10) and (c <> #13) then
    begin
      Inc(j);
      s[j] := c;
    end;
  end;
  SetLength(s, j);

  if s = '' then
  begin
    Result := True;
    Exit;
  end;

  if (Length(s) mod 2) <> 0 then
    Exit;

  SetLength(bytes, Length(s) div 2);
  j := 0;
  for i := 1 to Length(s) div 2 do
  begin
    hi := Nibble(s[i * 2 - 1]);
    lo := Nibble(s[i * 2]);
    if (hi < 0) or (lo < 0) then
      Exit;
    bytes[j] := Byte((hi shl 4) or lo);
    Inc(j);
  end;

  Result := True;
end;

end.
