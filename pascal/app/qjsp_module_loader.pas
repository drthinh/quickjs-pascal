unit qjsp_module_loader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, quickjs_types, quickjs_core, quickjs_std;

function qjsp_module_loader(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;

implementation

uses
  qar_helpers, qjs_log;

var
  g_module_load_stack: TStringList;

function qjsp_module_loader(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;
var
  module_name_str: string;
  mapped_name_fs: string;
  mapped_name_qjs: string;
  mapped_rel: string;
  mapped_name_alt: string;
  exe_dir: string;
  pascal_root: string;
  old_dir: string;
  ex: JSValue;
  i: integer;
  stack_msg: string;
  tried_msg: string;
begin
  module_name_str := string(module_name);

  if g_module_load_stack = nil then
    g_module_load_stack := TStringList.Create;

  i := g_module_load_stack.IndexOf(module_name_str);
  if i >= 0 then
  begin
    stack_msg := '';
    while i < g_module_load_stack.Count do
    begin
      if stack_msg <> '' then
        stack_msg := stack_msg + ' -> ';
      stack_msg := stack_msg + g_module_load_stack[i];
      Inc(i);
    end;
    if stack_msg <> '' then
      stack_msg := stack_msg + ' -> ';
    stack_msg := stack_msg + module_name_str;

    JS_ThrowReferenceError(ctx, PChar('circular import detected: ' + stack_msg));
    Result := nil;
    Exit;
  end;

  g_module_load_stack.Add(module_name_str);
  try

  if Pos('qjsp:', module_name_str) = 1 then
  begin
    exe_dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
    pascal_root := ExpandFileName(IncludeTrailingPathDelimiter(exe_dir) + '..');
    mapped_rel := Copy(module_name_str, Length('qjsp:') + 1, Length(module_name_str));
    if (mapped_rel <> '') and ((mapped_rel[1] = '/') or (mapped_rel[1] = '\\')) then
      mapped_rel := Copy(mapped_rel, 2, Length(mapped_rel));
    mapped_rel := StringReplace(mapped_rel, '\\', '/', [rfReplaceAll]);

    // Normalize: allow both explicit files and package dirs.
    if (Length(mapped_rel) >= 3) and (LowerCase(Copy(mapped_rel, Length(mapped_rel) - 2, 3)) = '.js') then
      mapped_rel := Copy(mapped_rel, 1, Length(mapped_rel) - 3);

    // Safety/diagnostics: reject path traversal and suspicious names early.
    if (Pos('..', mapped_rel) > 0) or (Pos(':', mapped_rel) > 0) then
    begin
      JS_ThrowReferenceError(ctx, PChar('invalid qjsp module path: ' + mapped_rel));
      Result := nil;
      Exit;
    end;

    // Absolute filesystem path used only for existence checks.
    mapped_name_fs := StringReplace(mapped_rel, '/', PathDelim, [rfReplaceAll]);
    mapped_name_fs := IncludeTrailingPathDelimiter(pascal_root) + 'stdjs' + PathDelim + mapped_name_fs;

    // Relative POSIX path for QuickJS loader (avoid Windows drive-letter ':' in module specifiers).
    mapped_name_qjs := 'stdjs/' + mapped_rel;

    qjs_log.DebugMsg(0, 'qjsp: map "' + module_name_str + '" -> "' + mapped_name_fs + '"');

    // Ensure stdjs/ relative paths resolve regardless of caller's current directory.
    old_dir := GetCurrentDir;
    try
      try
        SetCurrentDir(pascal_root);
      except
        // ignore
      end;

      // Prefer explicit file if it exists.
      if FileExists(mapped_name_fs + '.js') then
      begin
        Result := js_module_loader(ctx, PChar(mapped_name_qjs + '.js'), opaque);
        Exit;
      end;

      // If a directory exists, try its index.js.
      if DirectoryExists(mapped_name_fs) then
      begin
        Result := js_module_loader(ctx, PChar(mapped_name_qjs + '/index.js'), opaque);
        Exit;
      end;

      // Fallback: let QuickJS loader attempt its own resolution.
      Result := js_module_loader(ctx, PChar(mapped_name_qjs), opaque);
      if Result = nil then
      begin
        ex := JS_GetException(ctx);
        JS_FreeValue(ctx, ex);
        mapped_name_alt := mapped_name_qjs + '.js';
        Result := js_module_loader(ctx, PChar(mapped_name_alt), opaque);
      end;
      if Result = nil then
      begin
        ex := JS_GetException(ctx);
        JS_FreeValue(ctx, ex);
        mapped_name_alt := mapped_name_qjs + '/index.js';
        Result := js_module_loader(ctx, PChar(mapped_name_alt), opaque);
      end;

      if Result = nil then
      begin
        ex := JS_GetException(ctx);
        JS_FreeValue(ctx, ex);

        tried_msg :=
          'tried:' + LineEnding +
          '  - ' + mapped_name_qjs + '.js' + LineEnding +
          '  - ' + mapped_name_qjs + '/index.js';

        JS_ThrowReferenceError(ctx, PChar('could not load qjsp module: ' + module_name_str + LineEnding + tried_msg));
      end;
    finally
      try
        SetCurrentDir(old_dir);
      except
        // ignore
      end;
    end;
    Exit;
  end;

  Result := qar_helpers.js_module_loader_wrapper(ctx, module_name, opaque);
  finally
    if (g_module_load_stack <> nil) and (g_module_load_stack.Count > 0) and (g_module_load_stack[g_module_load_stack.Count - 1] = module_name_str) then
      g_module_load_stack.Delete(g_module_load_stack.Count - 1)
    else if g_module_load_stack <> nil then
    begin
      i := g_module_load_stack.IndexOf(module_name_str);
      if i >= 0 then
        g_module_load_stack.Delete(i);
    end;
  end;
end;

end.
