unit qjs_log;

{$mode objfpc}{$H+}

interface

var
  DebugLevel: integer = 0;

procedure DebugMsg(const level: integer; const msg: string);
procedure WarnMsg(const msg: string);

implementation

procedure DebugMsg(const level: integer; const msg: string);
begin
  if DebugLevel > level then
  begin
    WriteLn('[DEBUG] ', msg);
    Flush(Output);
  end;
end;

procedure WarnMsg(const msg: string);
begin
  WriteLn('[WARNING] ', msg);
  Flush(Output);
end;

end.
