unit qjsp_module_loader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ctypes, quickjs_types, quickjs_core, quickjs_std;

function qjsp_module_loader(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;

implementation

uses
  qar_helpers, qjs_log;

function qjsp_module_loader(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;
var
  module_name_str: string;
  mapped_name: string;
  mapped_name_alt: string;
  exe_dir: string;
  pascal_root: string;
  ex: JSValue;
begin
  module_name_str := string(module_name);

  if Pos('qjsp:', module_name_str) = 1 then
  begin
    exe_dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
    pascal_root := ExpandFileName(IncludeTrailingPathDelimiter(exe_dir) + '..');
    mapped_name := Copy(module_name_str, Length('qjsp:') + 1, Length(module_name_str));
    if (mapped_name <> '') and ((mapped_name[1] = '/') or (mapped_name[1] = '\\')) then
      mapped_name := Copy(mapped_name, 2, Length(mapped_name));
    mapped_name := StringReplace(mapped_name, '/', PathDelim, [rfReplaceAll]);
    mapped_name := StringReplace(mapped_name, '\\', PathDelim, [rfReplaceAll]);
    mapped_name := IncludeTrailingPathDelimiter(pascal_root) + 'stdjs' + PathDelim + mapped_name;

    qjs_log.DebugMsg(0, 'qjsp: map "' + module_name_str + '" -> "' + mapped_name + '"');

    Result := js_module_loader(ctx, PChar(mapped_name), opaque);
    if Result = nil then
    begin
      ex := JS_GetException(ctx);
      JS_FreeValue(ctx, ex);
      mapped_name_alt := mapped_name + '.js';
      Result := js_module_loader(ctx, PChar(mapped_name_alt), opaque);
    end;
    if Result = nil then
    begin
      ex := JS_GetException(ctx);
      JS_FreeValue(ctx, ex);
      mapped_name_alt := IncludeTrailingPathDelimiter(mapped_name) + 'index.js';
      Result := js_module_loader(ctx, PChar(mapped_name_alt), opaque);
    end;
    Exit;
  end;

  Result := qar_helpers.js_module_loader_wrapper(ctx, module_name, opaque);
end;

end.
