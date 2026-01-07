library test_dll;

{$mode objfpc}{$H+}

uses
  SysUtils;

// Export functions with stdcall convention (Windows default)
// These functions can be called from JavaScript via CallDllFunction

// Get version number (no arguments, returns int)
function GetVersion: Integer; stdcall;
begin
  Result := 100; // Version 1.0.0
end;
exports GetVersion;

// Double a number (1 argument, returns int)
function Double(x: Integer): Integer; stdcall;
begin
  Result := x * 2;
end;
exports Double;

// Calculate: multiply by 2.5 (1 argument, returns float)
function Calculate(x: Double): Double; stdcall;
begin
  Result := x * 2.5;
end;
exports Calculate;

// Print hello message (no arguments, returns void)
procedure PrintHello; stdcall;
begin
  WriteLn('Hello from DLL!');
end;
exports PrintHello;

// Add two numbers (for future extension - currently not supported by CallDllFunction)
// This would require 2 arguments which is not yet supported
function Add(a, b: Integer): Integer; stdcall;
begin
  Result := a + b;
end;
exports Add;

// Multiply two numbers (for future extension)
function Multiply(a, b: Integer): Integer; stdcall;
begin
  Result := a * b;
end;
exports Multiply;

begin
  // DLL initialization code (if needed)
end.

