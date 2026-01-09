unit console_utf8;

{$mode objfpc}{$H+}

interface

procedure ConsoleInitUtf8;
procedure WriteLnUtf8(const p: PChar);
function ReadLnUtf8: string;

implementation

{$IFDEF WINDOWS}

uses
  Windows, SysUtils;

procedure ConsoleInitUtf8;
begin
  SetMultiByteConversionCodePage(CP_UTF8);
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  SetTextCodePage(StdErr, CP_UTF8);
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
end;

procedure WriteLnUtf8(const p: PChar);
var
  wide: UnicodeString;
  len: Integer;
  handle: THandle;
  written: DWORD;
  newlineWide: WideString;
begin
  if p = nil then Exit;
  len := MultiByteToWideChar(CP_UTF8, 0, p, -1, nil, 0);
  if len <= 0 then Exit;
  SetLength(wide, len);
  if len > 0 then
  begin
    MultiByteToWideChar(CP_UTF8, 0, p, -1, PWideChar(wide), len);
    SetLength(wide, len - 1);
  end;
  handle := GetStdHandle(STD_OUTPUT_HANDLE);
  if (handle <> INVALID_HANDLE_VALUE) and (GetFileType(handle) = FILE_TYPE_CHAR) then
  begin
    WriteConsoleW(handle, PWideChar(wide), Length(wide), @written, nil);
    newlineWide := WideString(LineEnding);
    WriteConsoleW(handle, PWideChar(newlineWide), Length(newlineWide), @written, nil);
  end
  else
    WriteLn(wide);
end;

function ReadLnUtf8: string;
var
  handle: THandle;
  buf: array[0..255] of WideChar;
  readCount: DWORD;
  ws: UnicodeString;
  i: Integer;
begin
  handle := GetStdHandle(STD_INPUT_HANDLE);
  if (handle <> INVALID_HANDLE_VALUE) and (GetFileType(handle) = FILE_TYPE_CHAR) then
  begin
    ws := '';
    while True do
    begin
      if not ReadConsoleW(handle, @buf[0], Length(buf), @readCount, nil) then
        Break;
      if readCount = 0 then
        Break;
      for i := 0 to readCount - 1 do
      begin
        case buf[i] of
          #10:
            begin
              Result := UTF8Encode(ws);
              Exit;
            end;
          #13:
            Continue;
        else
          ws := ws + buf[i];
        end;
      end;
    end;
    Result := UTF8Encode(ws);
    Exit;
  end;
  ReadLn(Result);
end;

{$ELSE}

procedure ConsoleInitUtf8;
begin
end;

procedure WriteLnUtf8(const p: PChar);
begin
  if p = nil then Exit;
  WriteLn(p);
end;

function ReadLnUtf8: string;
begin
  ReadLn(Result);
end;

{$ENDIF}

end.
