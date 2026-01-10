unit qjsp_module_loader;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, quickjs_types, quickjs_core, quickjs_std;

function qjsp_module_loader(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;
procedure qjsp_register_mount(const Prefix: string; const Folder: string);
procedure qjsp_clear_mounts;

implementation

uses
  qar_helpers, qjs_log, StrUtils;

var
  g_module_load_stack: TStringList;
  g_qjsp_mounts: TStringList;

procedure qjsp_register_mount(const Prefix: string; const Folder: string);
var
  p: string;
  f: string;
begin
  p := Trim(Prefix);
  f := Trim(Folder);
  if p = '' then
    Exit;
  if Pos('/', p) > 0 then
    Exit;
  if Pos('\\', p) > 0 then
    Exit;
  if (Pos('..', f) > 0) or (Pos(':', f) > 0) then
    Exit;
  p := StringReplace(p, '\\', '/', [rfReplaceAll]);
  f := StringReplace(f, '\\', '/', [rfReplaceAll]);
  while (Length(f) > 0) and ((f[1] = '/') or (f[1] = '\\')) do
    Delete(f, 1, 1);
  if g_qjsp_mounts = nil then
  begin
    g_qjsp_mounts := TStringList.Create;
    g_qjsp_mounts.NameValueSeparator := '=';
    g_qjsp_mounts.CaseSensitive := False;
  end;
  g_qjsp_mounts.Values[p] := f;
end;

procedure qjsp_clear_mounts;
begin
  if g_qjsp_mounts <> nil then
    g_qjsp_mounts.Clear;
end;

function TryLoadFromMount(ctx: PJSContext; opaque: pointer; const pascal_root: string; const mount_prefix: string; const mount_folder: string; const rel_after_prefix: string): PJSModuleDef;
var
  fs_base: string;
  qjs_base: string;
  rel_fs: string;
  ex: JSValue;
begin
  Result := nil;

  rel_fs := StringReplace(rel_after_prefix, '/', PathDelim, [rfReplaceAll]);
  fs_base := IncludeTrailingPathDelimiter(pascal_root) + StringReplace(mount_folder, '/', PathDelim, [rfReplaceAll]);
  if rel_fs <> '' then
    fs_base := IncludeTrailingPathDelimiter(fs_base) + rel_fs;

  if rel_after_prefix <> '' then
    qjs_base := mount_prefix + '/' + rel_after_prefix
  else
    qjs_base := mount_prefix;

  if FileExists(fs_base + '.js') then
  begin
    Result := js_module_loader(ctx, PChar(qjs_base + '.js'), opaque);
    Exit;
  end;
  if DirectoryExists(fs_base) then
  begin
    Result := js_module_loader(ctx, PChar(qjs_base + '/index.js'), opaque);
    Exit;
  end;

  Result := js_module_loader(ctx, PChar(qjs_base), opaque);
  if Result = nil then
  begin
    ex := JS_GetException(ctx);
    JS_FreeValue(ctx, ex);
  end;
  if Result = nil then
  begin
    Result := js_module_loader(ctx, PChar(qjs_base + '.js'), opaque);
    if Result = nil then
    begin
      ex := JS_GetException(ctx);
      JS_FreeValue(ctx, ex);
    end;
  end;
  if Result = nil then
  begin
    Result := js_module_loader(ctx, PChar(qjs_base + '/index.js'), opaque);
    if Result = nil then
    begin
      ex := JS_GetException(ctx);
      JS_FreeValue(ctx, ex);
    end;
  end;
end;

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
  mount_prefix: string;
  mount_folder: string;
  rel_after_prefix: string;
  slash_pos: integer;
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

  if Pos('lib:', module_name_str) = 1 then
  begin
    exe_dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
    pascal_root := ExpandFileName(IncludeTrailingPathDelimiter(exe_dir) + '..');

    mapped_rel := Copy(module_name_str, Length('lib:') + 1, Length(module_name_str));
    if (mapped_rel <> '') and ((mapped_rel[1] = '/') or (mapped_rel[1] = '\')) then
      mapped_rel := Copy(mapped_rel, 2, Length(mapped_rel));
    mapped_rel := StringReplace(mapped_rel, '\', '/', [rfReplaceAll]);

    // Normalize: allow both explicit files and package dirs.
    if (Length(mapped_rel) >= 3) and (LowerCase(Copy(mapped_rel, Length(mapped_rel) - 2, 3)) = '.js') then
      mapped_rel := Copy(mapped_rel, 1, Length(mapped_rel) - 3);

    // Safety/diagnostics: reject path traversal and suspicious names early.
    if (Pos('..', mapped_rel) > 0) or (Pos(':', mapped_rel) > 0) then
    begin
      JS_ThrowReferenceError(ctx, PChar('invalid lib module path: ' + mapped_rel));
      Result := nil;
      Exit;
    end;

    // lib:* must be configured via mounts (config "libraries" section).
    // lib:<name>/path maps to mount <name>=<folder>.
    if (g_qjsp_mounts = nil) then
    begin
      JS_ThrowReferenceError(ctx, PChar('no library mounts configured (missing config "libraries")'));
      Result := nil;
      Exit;
    end;

    slash_pos := Pos('/', mapped_rel);
    if slash_pos > 0 then
    begin
      mount_prefix := Copy(mapped_rel, 1, slash_pos - 1);
      rel_after_prefix := Copy(mapped_rel, slash_pos + 1, Length(mapped_rel));
    end
    else
    begin
      mount_prefix := mapped_rel;
      rel_after_prefix := '';
    end;

    mount_folder := g_qjsp_mounts.Values[mount_prefix];
    if mount_folder = '' then
    begin
      JS_ThrowReferenceError(ctx, PChar('missing library mount: ' + mount_prefix + '=... (configure in config JSON "libraries")'));
      Result := nil;
      Exit;
    end;

    qjs_log.DebugMsg(0, 'lib: map "' + module_name_str + '" -> mount "' + mount_prefix + '" folder "' + mount_folder + '" rel "' + mapped_rel + '"');

    // Ensure relative paths resolve regardless of caller's current directory.
    old_dir := GetCurrentDir;
    try
      try
        SetCurrentDir(pascal_root);
      except
        // ignore
      end;

      Result := TryLoadFromMount(ctx, opaque, pascal_root, mount_prefix, mount_folder, rel_after_prefix);
      if Result <> nil then
        Exit;

      ex := JS_GetException(ctx);
      JS_FreeValue(ctx, ex);

      if rel_after_prefix <> '' then
        tried_msg :=
          'tried:' + LineEnding +
          '  - ' + mount_prefix + '/' + rel_after_prefix + '.js' + LineEnding +
          '  - ' + mount_prefix + '/' + rel_after_prefix + '/index.js'
      else
        tried_msg :=
          'tried:' + LineEnding +
          '  - ' + mount_prefix + '.js' + LineEnding +
          '  - ' + mount_prefix + '/index.js';
      JS_ThrowReferenceError(ctx, PChar('could not load lib module: ' + module_name_str + LineEnding + tried_msg));
      Result := nil;
    finally
      try
        SetCurrentDir(old_dir);
      except
        // ignore
      end;
    end;
    Exit;
  end;

  if Pos('qjsp:', module_name_str) = 1 then
  begin
    exe_dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
    pascal_root := ExpandFileName(IncludeTrailingPathDelimiter(exe_dir) + '..');
    mapped_rel := Copy(module_name_str, Length('qjsp:') + 1, Length(module_name_str));
    if (mapped_rel <> '') and ((mapped_rel[1] = '/') or (mapped_rel[1] = '\')) then
      mapped_rel := Copy(mapped_rel, 2, Length(mapped_rel));
    mapped_rel := StringReplace(mapped_rel, '\', '/', [rfReplaceAll]);

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

      if (g_qjsp_mounts <> nil) then
      begin
        slash_pos := Pos('/', mapped_rel);
        if slash_pos > 0 then
        begin
          mount_prefix := Copy(mapped_rel, 1, slash_pos - 1);
          rel_after_prefix := Copy(mapped_rel, slash_pos + 1, Length(mapped_rel));
        end
        else
        begin
          mount_prefix := mapped_rel;
          rel_after_prefix := '';
        end;

        mount_folder := g_qjsp_mounts.Values[mount_prefix];
        if mount_folder <> '' then
        begin
          Result := TryLoadFromMount(ctx, opaque, pascal_root, mount_prefix, mount_folder, rel_after_prefix);
          if Result <> nil then
            Exit;
        end;
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
