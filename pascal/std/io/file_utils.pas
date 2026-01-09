unit file_utils;

{$mode objfpc}{$H+}

interface

function ReadTextFileToString(const FileName: string; out Content: string): boolean;
function ResolveScriptPath(const FileName: string; out ResolvedPath: string): boolean;

implementation

uses
  SysUtils;

function ReadTextFileToString(const FileName: string; out Content: string): boolean;
var
  f: TextFile;
  line: string;
begin
  Content := '';
  if not FileExists(FileName) then
  begin
    Result := False;
    Exit;
  end;

  AssignFile(f, FileName);
  Reset(f);
  try
    while not EOF(f) do
    begin
      ReadLn(f, line);
      if Content <> '' then
        Content := Content + LineEnding;
      Content := Content + line;
    end;
  finally
    CloseFile(f);
  end;

  Result := True;
end;

function ResolveScriptPath(const FileName: string; out ResolvedPath: string): boolean;
var
  exe_dir: string;
  test_path: string;
begin
  ResolvedPath := ExpandFileName(FileName);
  if FileExists(ResolvedPath) then
  begin
    Result := True;
    Exit;
  end;

  exe_dir := ExtractFileDir(ParamStr(0));
  if exe_dir <> '' then
  begin
    test_path := IncludeTrailingPathDelimiter(exe_dir) + FileName;
    if FileExists(test_path) then
    begin
      ResolvedPath := test_path;
      Result := True;
      Exit;
    end;

    test_path := IncludeTrailingPathDelimiter(exe_dir) + '..' + PathDelim + 'tests' + PathDelim + ExtractFileName(FileName);
    if FileExists(test_path) then
    begin
      ResolvedPath := test_path;
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

end.
