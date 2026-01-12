unit qjs_log;

{$mode objfpc}{$H+}

interface

var
  DebugLevel: integer = 0;

type
  TLogLevel = (llOff, llError, llWarn, llInfo, llDebug, llTrace);

var
  LogLevel: TLogLevel = llWarn;
  LogShowTimestamp: boolean = True;

procedure SetLogLevel(const ALevel: TLogLevel);
procedure SetLogLevelFromDebugLevel(const ADebugLevel: integer);

procedure DebugMsg(const level: integer; const msg: string);
procedure WarnMsg(const msg: string);

procedure ErrorMsg(const msg: string);
procedure InfoMsg(const msg: string);
procedure LogMsg(const level: TLogLevel; const tag: string; const msg: string);

implementation

uses
  SysUtils;

function LogLevelToString(const level: TLogLevel): string;
begin
  case level of
    llError: Result := 'ERROR';
    llWarn: Result := 'WARNING';
    llInfo: Result := 'INFO';
    llDebug: Result := 'DEBUG';
    llTrace: Result := 'TRACE';
  else
    Result := 'OFF';
  end;
end;

procedure SetLogLevel(const ALevel: TLogLevel);
begin
  LogLevel := ALevel;
end;

procedure SetLogLevelFromDebugLevel(const ADebugLevel: integer);
begin
  DebugLevel := ADebugLevel;
  if ADebugLevel <= 0 then
    LogLevel := llWarn
  else if ADebugLevel = 1 then
    LogLevel := llDebug
  else
    LogLevel := llTrace;
end;

procedure LogMsg(const level: TLogLevel; const tag: string; const msg: string);
var
  prefix: string;
  ts: string;
begin
  if Ord(level) > Ord(LogLevel) then
    Exit;

  if LogShowTimestamp then
    ts := FormatDateTime('hh:nn:ss.zzz', Now) + ' '
  else
    ts := '';

  if tag <> '' then
    prefix := '[' + LogLevelToString(level) + '][' + tag + '] '
  else
    prefix := '[' + LogLevelToString(level) + '] ';

  WriteLn(ts + prefix + msg);
  Flush(Output);
end;

procedure DebugMsg(const level: integer; const msg: string);
begin
  if DebugLevel > level then
  begin
    if level <= 0 then
      LogMsg(llDebug, '', msg)
    else
      LogMsg(llTrace, '', msg);
  end;
end;

procedure WarnMsg(const msg: string);
begin
  LogMsg(llWarn, '', msg);
end;

procedure ErrorMsg(const msg: string);
begin
  LogMsg(llError, '', msg);
end;

procedure InfoMsg(const msg: string);
begin
  LogMsg(llInfo, '', msg);
end;

end.
