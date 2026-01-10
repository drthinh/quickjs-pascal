{******************************************************************************
 * QAR Tool - Standalone QAR Utility
 * Deprecated => removed
 * Chương trình độc lập để làm việc với file QAR (QuickJS Archive)
 *
 * Sử dụng:
 *   qar_tool [options] [command] [arguments]
 *
 * Commands:
 *   info                    - Hiển thị thông tin phiên bản QAR và QuickJS
 *   build <output> <files>  - Tạo file QAR từ các file JavaScript
 *   inspect <file.qar>      - Kiểm tra và hiển thị thông tin chi tiết file QAR
 *   rebuild <input> <output> - Biên dịch lại QAR để phù hợp phiên bản QuickJS mới
 *   version                 - Hiển thị phiên bản
 *   help                    - Hiển thị trợ giúp
 *
 * Options:
 *   --init-lib              - Khởi tạo thư viện QuickJS mặc định khi hiển thị info
 *
 * Ví dụ:
 *   qar_tool info
 *   qar_tool info --init-lib
 *   qar_tool build output.qar file1.js file2.js
 *   qar_tool build output.qar src/
 *   qar_tool inspect file.qar
 *   qar_tool rebuild old.qar new.qar
 *   qar_tool version
 *
 * Tác giả: Nguyễn Đức Thịnh (dr.nguyenducthinh@gmail.com)
 * Ngày: 2026
 ******************************************************************************}

program qar_tool;

{$mode objfpc}{$H+}

uses
  SysUtils, ctypes, qar, process, Classes;

var
  init_default_lib: boolean = False;
  do_minify: boolean = False;
  keep_temp: boolean = False;
  minify_safe: boolean = False;
  minify_script: string = '';
  minify_flags: array of string;
  temp_stage_dir: string = '';
  sign_key_file: string = '';
  i: integer;
  cmd: string;
  output_file: string = '';
  input_file: string = '';
  input_files: array of string;
  j: integer;
  // Entry points cho manifest
  entry_main: string = '';
  entry_init: string = '';
  entry_name_code: string = '';

function EnsureDirExists(const dir: string): boolean;
begin
  if dir = '' then
    Exit(False);
  if DirectoryExists(dir) then
    Exit(True);
  Result := ForceDirectories(dir);
end;

function CopyFileTo(const src, dst: string): boolean;
var
  inS, outS: TFileStream;
begin
  Result := False;
  if not FileExists(src) then
    Exit;
  if not EnsureDirExists(ExtractFileDir(dst)) then
    Exit;
  try
    inS := TFileStream.Create(src, fmOpenRead or fmShareDenyNone);
    try
      outS := TFileStream.Create(dst, fmCreate);
      try
        outS.CopyFrom(inS, 0);
        Result := True;
      finally
        outS.Free;
      end;
    finally
      inS.Free;
    end;
  except
    Result := False;
  end;
end;

function DeleteDirRecursive(const dir: string): boolean;
var
  sr: TSearchRec;
  p: string;
begin
  Result := True;
  if (dir = '') or (not DirectoryExists(dir)) then
    Exit(True);

  if FindFirst(IncludeTrailingPathDelimiter(dir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        Continue;
      p := IncludeTrailingPathDelimiter(dir) + sr.Name;
      if (sr.Attr and faDirectory) <> 0 then
      begin
        if not DeleteDirRecursive(p) then
          Result := False;
      end
      else
      begin
        try
          if not DeleteFile(p) then
            Result := False;
        except
          Result := False;
        end;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;

  try
    if not RemoveDir(dir) then
      Result := False;
  except
    Result := False;
  end;
end;

function RunMinifyScript(const input_js, output_js: string): boolean;
var
  p: TProcess;
  qjsp_path: string;
  k: integer;
  exe_dir: string;
begin
  Result := False;
  exe_dir := ExtractFilePath(ParamStr(0));
  qjsp_path := ExpandFileName(exe_dir + 'qjsp.exe');
  if not FileExists(qjsp_path) then
  begin
    qjsp_path := ExpandFileName('qjsp.exe');
  end;
  if not FileExists(qjsp_path) then
  begin
    WriteLn('Error: qjsp.exe not found (needed for --minify). Expected next to qar_tool.exe or in current directory.');
    Exit;
  end;

  if minify_script = '' then
    minify_script := ExpandFileName(exe_dir + 'minify_qjsp.js');
  if not FileExists(minify_script) then
    minify_script := ExpandFileName('minify_qjsp.js');
  if not FileExists(minify_script) then
    minify_script := ExpandFileName(exe_dir + 'minify.js');
  if not FileExists(minify_script) then
  begin
    minify_script := ExpandFileName('minify.js');
  end;
  if not FileExists(minify_script) then
  begin
    WriteLn('Error: minify script not found: ', minify_script);
    Exit;
  end;

  if not EnsureDirExists(ExtractFileDir(output_js)) then
    Exit;

  p := TProcess.Create(nil);
  try
    p.Executable := qjsp_path;
    p.Options := [poWaitOnExit, poUsePipes];
    p.Parameters.Add(minify_script);
    p.Parameters.Add(input_js);
    p.Parameters.Add(output_js);
    for k := 0 to Length(minify_flags) - 1 do
      p.Parameters.Add(minify_flags[k]);
    try
      p.Execute;
    except
      Exit;
    end;
    Result := p.ExitStatus = 0;
    if not Result then
      WriteLn('Error: minify failed for ', input_js, ' (exit=', p.ExitStatus, ')');
  finally
    p.Free;
  end;
end;

function CopyDirRecursive(const src_dir, dst_dir: string): boolean;
var
  sr: TSearchRec;
  src_path, dst_path: string;
  ext: string;
begin
  Result := False;
  if not DirectoryExists(src_dir) then
    Exit;
  if not EnsureDirExists(dst_dir) then
    Exit;

  if FindFirst(IncludeTrailingPathDelimiter(src_dir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        Continue;
      src_path := IncludeTrailingPathDelimiter(src_dir) + sr.Name;
      dst_path := IncludeTrailingPathDelimiter(dst_dir) + sr.Name;
      if (sr.Attr and faDirectory) <> 0 then
      begin
        if not CopyDirRecursive(src_path, dst_path) then
        begin
          FindClose(sr);
          Exit;
        end;
      end
      else
      begin
        ext := LowerCase(ExtractFileExt(sr.Name));
        if (do_minify) and ((ext = '.js') or (ext = '.mjs')) then
        begin
          if not RunMinifyScript(src_path, dst_path) then
          begin
            FindClose(sr);
            Exit;
          end;
        end
        else
        begin
          if not CopyFileTo(src_path, dst_path) then
          begin
            FindClose(sr);
            Exit;
          end;
        end;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  Result := True;
end;

function PrepareStagedInputs(const in_files: array of string; out staged_files: array of string): boolean;
var
  t: string;
  src, dst: string;
  idx: integer;
  ext: string;
begin
  Result := False;
  if Length(in_files) <> Length(staged_files) then
    Exit;

  t := GetTempDir(False);
  temp_stage_dir := IncludeTrailingPathDelimiter(t) + 'qar_tool_stage_' + IntToStr(GetTickCount64);
  if not EnsureDirExists(temp_stage_dir) then
  begin
    WriteLn('Error: cannot create temp dir: ', temp_stage_dir);
    Exit;
  end;

  for idx := 0 to Length(in_files) - 1 do
  begin
    src := in_files[idx];
    if DirectoryExists(src) then
    begin
      dst := IncludeTrailingPathDelimiter(temp_stage_dir) + 'dir_' + IntToStr(idx);
      if not CopyDirRecursive(src, dst) then
        Exit;
      staged_files[idx] := dst;
    end
    else
    begin
      dst := IncludeTrailingPathDelimiter(temp_stage_dir) + ExtractFileName(src);
      ext := LowerCase(ExtractFileExt(src));
      if (do_minify) and ((ext = '.js') or (ext = '.mjs')) then
      begin
        if not RunMinifyScript(src, dst) then
          Exit;
      end
      else
      begin
        if not CopyFileTo(src, dst) then
          Exit;
      end;
      staged_files[idx] := dst;
    end;
  end;
  Result := True;
end;

procedure PrintUsage;
begin
  WriteLn('QAR Tool - QuickJS Archive Utility');
  WriteLn;
  WriteLn('Sử dụng:');
  WriteLn('  qar_tool [options] [command] [arguments]');
  WriteLn;
  WriteLn('Commands:');
  WriteLn('  info                    - Hiển thị thông tin phiên bản QAR và QuickJS');
  WriteLn('  build <output> <files>  - Tạo file QAR từ các file JavaScript');
  WriteLn('  inspect <file.qar>      - Kiểm tra và hiển thị thông tin chi tiết file QAR');
  WriteLn('  rebuild <input> <output> - Biên dịch lại QAR để phù hợp phiên bản QuickJS mới');
  WriteLn('  code <file.qar> <entry> - Hiển thị mã nguồn của một entry trong file QAR');
  WriteLn('  version                 - Hiển thị phiên bản');
  WriteLn('  help                    - Hiển thị trợ giúp này');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  --init-lib              - Khởi tạo thư viện QuickJS mặc định khi hiển thị info');
  WriteLn('  --minify                - Minify JS sources via qjsp + minify script before building QAR');
  WriteLn('  --minify-safe           - Shortcut: --minify + --safe-rename + --encode-strings');
  WriteLn('  --minify-script <file>  - Chỉ định script minify (mặc định: minify_qjsp.js).');
  WriteLn('                           Lưu ý: các flag nâng cao (safe-rename/encode-strings) nằm trong minify_qjsp.js');
  WriteLn('  --minify-flag <arg>     - Truyền thêm flag cho script minify (có thể lặp lại)');
  WriteLn('  --keep-temp             - Giữ thư mục staging tạm (hữu ích để debug minify)');
  WriteLn;
  WriteLn('Ví dụ:');
  WriteLn('  qar_tool info');
  WriteLn('  qar_tool info --init-lib');
  WriteLn('  qar_tool build output.qar file1.js file2.js');
  WriteLn('  qar_tool build output.qar src/');
  WriteLn('  qar_tool --minify build output.qar src/');
  WriteLn('  qar_tool --minify build out.qar src/ --minify-flag --minify-only');
  WriteLn('  qar_tool --minify-safe build out.qar src/');
  WriteLn('  qar_tool --minify build out.qar src/ --minify-flag --safe-rename --minify-flag --encode-strings');
  WriteLn('  qar_tool inspect file.qar');
  WriteLn('  qar_tool rebuild old.qar new.qar');
  WriteLn('  qar_tool code mylib.qar my_module.js');
  WriteLn('  qar_tool version');
  WriteLn;
end;

procedure PrintVersion;
begin
  WriteLn('QAR Tool Version: ', GetQarVersion);
  WriteLn('QAR Format Version: ', QAR_FORMAT_VERSION);
  WriteLn('QuickJS Version: ', GetQuickJsVersion);
end;

procedure PrintInfo;
begin
  PrintQarInfo(init_default_lib);
end;

procedure BuildQarFile;
var
  ret: cint;
  staged: array of string;
  build_inputs: array of string;
begin
  if Length(input_files) = 0 then
  begin
    WriteLn('Error: No input files specified');
    WriteLn('Usage: qar_tool build <output.qar> <file1.js> [file2.js ...]');
    WriteLn('   or: qar_tool build <output.qar> <directory/>');
    Halt(1);
  end;
  
  WriteLn('Building QAR file: ', output_file);
  WriteLn('Input files:');
  for j := 0 to Length(input_files) - 1 do
    WriteLn('  - ', input_files[j]);
  WriteLn;
  
  if (entry_main <> '') then
    WriteLn('Entry main: ', entry_main);
  if (entry_init <> '') then
    WriteLn('Entry init: ', entry_init);
  if (entry_main <> '') or (entry_init <> '') then
    WriteLn;
  
  build_inputs := input_files;
  if do_minify then
  begin
    SetLength(staged, Length(input_files));
    if not PrepareStagedInputs(input_files, staged) then
    begin
      WriteLn('Error: Failed to prepare minified inputs');
      Halt(1);
    end;
    build_inputs := staged;
  end;

  try
    ret := BuildQar(output_file, build_inputs, entry_main, entry_init, '', '', nil, '', '', sign_key_file);
  finally
    if (do_minify) and (temp_stage_dir <> '') then
    begin
      if keep_temp or (ret < 0) then
        WriteLn('Keeping temp staging dir: ', temp_stage_dir)
      else
        DeleteDirRecursive(temp_stage_dir);
    end;
    temp_stage_dir := '';
  end;
  if ret < 0 then
  begin
    WriteLn('Error: Failed to build QAR file');
    Halt(1);
  end;
  
  WriteLn('Success! QAR file created: ', output_file);
end;

procedure InspectQarFileCommand;
var
  inspection: TQarInspectionResult;
begin
  if input_file = '' then
  begin
    WriteLn('Error: QAR file not specified');
    WriteLn('Usage: qar_tool inspect <file.qar>');
    Halt(1);
  end;
  
  if not FileExists(input_file) then
  begin
    WriteLn('Error: QAR file not found: ', input_file);
    Halt(1);
  end;
  
  inspection := qar.InspectQarFile(input_file);
  try
    PrintQarInspection(inspection);
  finally
    inspection.dependencies.Free;
  end;
end;

procedure ViewQarEntryCodeCommand;
var
  qar_file: PQarFile;
  entry: PQarEntry;
  source_ptr: Pcuint8;
  source_len: csize_t;
  source_str: AnsiString;
begin
  if input_file = '' then
  begin
    WriteLn('Error: QAR file not specified');
    WriteLn('Usage: qar_tool code <file.qar> <entry>');
    Halt(1);
  end;

  if entry_name_code = '' then
  begin
    WriteLn('Error: Entry name not specified');
    WriteLn('Usage: qar_tool code <file.qar> <entry>');
    Halt(1);
  end;

  if not FileExists(input_file) then
  begin
    WriteLn('Error: QAR file not found: ', input_file);
    Halt(1);
  end;

  qar_file := qar_open(PChar(input_file));
  if qar_file = nil then
  begin
    WriteLn('Error: Failed to open QAR file: ', input_file);
    Halt(1);
  end;

  try
    entry := qar_find_entry(qar_file, PAnsiChar(entry_name_code));
    if entry = nil then
    begin
      WriteLn('Error: Entry not found: ', entry_name_code);
      Halt(1);
    end;

    if qar_entry_load_data(qar_file, entry) < 0 then
    begin
      WriteLn('Error: Failed to load data for entry: ', entry_name_code);
      Halt(1);
    end;

    source_ptr := qar_entry_get_source(entry, @source_len);
    if source_ptr = nil then
    begin
      WriteLn('Error: Failed to get source for entry: ', entry_name_code);
      Halt(1);
    end;

    SetString(source_str, PAnsiChar(source_ptr), source_len);
    WriteLn(source_str);

  finally
    qar_close(qar_file);
  end;
end;

procedure RebuildQarFileCommand;
var
  ret: cint;
  staged: array of string;
begin
  if input_file = '' then
  begin
    WriteLn('Error: Input QAR file not specified');
    WriteLn('Usage: qar_tool rebuild <input.qar> <output.qar>');
    Halt(1);
  end;
  
  if output_file = '' then
  begin
    WriteLn('Error: Output QAR file not specified');
    WriteLn('Usage: qar_tool rebuild <input.qar> <output.qar>');
    Halt(1);
  end;
  
  if not FileExists(input_file) then
  begin
    WriteLn('Error: Input QAR file not found: ', input_file);
    Halt(1);
  end;
  
  if (entry_main <> '') then
    WriteLn('Override entry main: ', entry_main);
  if (entry_init <> '') then
    WriteLn('Override entry init: ', entry_init);
  if (entry_main <> '') or (entry_init <> '') then
    WriteLn;
  
  if do_minify then
  begin
    SetLength(staged, 1);
    if not PrepareStagedInputs([input_file], staged) then
    begin
      WriteLn('Error: Failed to prepare minified inputs');
      Halt(1);
    end;
    input_file := staged[0];
  end;

  try
    ret := qar.RebuildQarFile(input_file, output_file, entry_main, entry_init, sign_key_file);
  finally
    if (do_minify) and (temp_stage_dir <> '') then
    begin
      if keep_temp or (ret < 0) then
        WriteLn('Keeping temp staging dir: ', temp_stage_dir)
      else
        DeleteDirRecursive(temp_stage_dir);
    end;
    temp_stage_dir := '';
  end;
  if ret < 0 then
  begin
    WriteLn('Error: Failed to rebuild QAR file');
    Halt(1);
  end;
end;

begin
  // Parse command line arguments
  if ParamCount = 0 then
  begin
    PrintUsage;
    Halt(0);
  end;
  
  i := 1;
  cmd := '';
  output_file := '';
  input_file := '';
  SetLength(input_files, 0);
  SetLength(minify_flags, 0);

  // If --minify-safe is set, we add flags before running commands.
  // Implemented by toggling minify_safe here, and expanding after parsing.
  
  // Parse options and command
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '--init-lib') or (ParamStr(i) = '-i') then
    begin
      init_default_lib := True;
      Inc(i);
    end
    else if (ParamStr(i) = '--minify') then
    begin
      do_minify := True;
      Inc(i);
    end
    else if (ParamStr(i) = '--minify-safe') then
    begin
      do_minify := True;
      minify_safe := True;
      Inc(i);
    end
    else if (ParamStr(i) = '--keep-temp') then
    begin
      keep_temp := True;
      Inc(i);
    end
    else if (ParamStr(i) = '--minify-script') and (i < ParamCount) then
    begin
      Inc(i);
      minify_script := ParamStr(i);
      Inc(i);
    end
    else if (ParamStr(i) = '--minify-flag') and (i < ParamCount) then
    begin
      Inc(i);
      SetLength(minify_flags, Length(minify_flags) + 1);
      minify_flags[Length(minify_flags) - 1] := ParamStr(i);
      Inc(i);
    end
    else if (ParamStr(i) = '--sign-key') and (i < ParamCount) then
    begin
      Inc(i);
      sign_key_file := ParamStr(i);
      Inc(i);
    end
    // Thiết lập entry main cho manifest khi build/rebuild
    else if (ParamStr(i) = '--main') and (i < ParamCount) then
    begin
      Inc(i);
      entry_main := ParamStr(i);
      Inc(i);
    end
    // Thiết lập entry init cho manifest khi build/rebuild
    else if (ParamStr(i) = '--init') and (i < ParamCount) then
    begin
      Inc(i);
      entry_init := ParamStr(i);
      Inc(i);
    end
    else if (ParamStr(i) = '--help') or (ParamStr(i) = '-h') or (ParamStr(i) = 'help') then
    begin
      PrintUsage;
      Halt(0);
    end
    else if (ParamStr(i) = '--version') or (ParamStr(i) = '-v') or (ParamStr(i) = 'version') then
    begin
      PrintVersion;
      Halt(0);
    end
    else if cmd = '' then
    begin
      cmd := LowerCase(ParamStr(i));
      Inc(i);
    end
    else
    begin
      // Allow known options after the command/arguments (e.g. "qar_tool rebuild in out --minify")
      if (ParamStr(i) = '--minify') then
      begin
        do_minify := True;
        Inc(i);
        Continue;
      end
      else if (ParamStr(i) = '--minify-safe') then
      begin
        do_minify := True;
        minify_safe := True;
        Inc(i);
        Continue;
      end
      else if (ParamStr(i) = '--keep-temp') then
      begin
        keep_temp := True;
        Inc(i);
        Continue;
      end
      else if (ParamStr(i) = '--minify-script') and (i < ParamCount) then
      begin
        Inc(i);
        minify_script := ParamStr(i);
        Inc(i);
        Continue;
      end
      else if (ParamStr(i) = '--minify-flag') and (i < ParamCount) then
      begin
        Inc(i);
        SetLength(minify_flags, Length(minify_flags) + 1);
        minify_flags[Length(minify_flags) - 1] := ParamStr(i);
        Inc(i);
        Continue;
      end
      else if (ParamStr(i) = '--main') and (i < ParamCount) then
      begin
        Inc(i);
        entry_main := ParamStr(i);
        Inc(i);
        Continue;
      end
      else if (ParamStr(i) = '--init') and (i < ParamCount) then
      begin
        Inc(i);
        entry_init := ParamStr(i);
        Inc(i);
        Continue;
      end;

      if (ParamStr(i) = '--sign-key') and (i < ParamCount) then
      begin
        Inc(i);
        sign_key_file := ParamStr(i);
        Inc(i);
        Continue;
      end;

      // Arguments for command
      if cmd = 'build' then
      begin
        if output_file = '' then
          output_file := ParamStr(i)
        else
        begin
          SetLength(input_files, Length(input_files) + 1);
          input_files[Length(input_files) - 1] := ParamStr(i);
        end;
      end
      else if cmd = 'inspect' then
      begin
        if input_file = '' then
          input_file := ParamStr(i);
      end
      else if cmd = 'rebuild' then
      begin
        if input_file = '' then
          input_file := ParamStr(i)
        else if output_file = '' then
          output_file := ParamStr(i);
      end
      else if cmd = 'code' then
      begin
        if input_file = '' then
          input_file := ParamStr(i)
        else if entry_name_code = '' then
          entry_name_code := ParamStr(i);
      end;
      Inc(i);
    end;
  end;

  if minify_safe then
  begin
    // Expand shorthand only if user did not explicitly specify these flags already.
    // (We don't try to dedupe: duplicates are harmless.)
    SetLength(minify_flags, Length(minify_flags) + 2);
    minify_flags[Length(minify_flags) - 2] := '--safe-rename';
    minify_flags[Length(minify_flags) - 1] := '--encode-strings';
  end;

  // Execute command
  if cmd = 'info' then
  begin
    PrintInfo;
  end
  else if cmd = 'version' then
  begin
    PrintVersion;
  end
  else if cmd = 'build' then
  begin
    if output_file = '' then
    begin
      WriteLn('Error: Output file not specified');
      WriteLn('Usage: qar_tool build <output.qar> <file1.js> [file2.js ...]');
      Halt(1);
    end;
    BuildQarFile;
  end
  else if cmd = 'inspect' then
  begin
    InspectQarFileCommand;
  end
  else if cmd = 'rebuild' then
  begin
    RebuildQarFileCommand;
  end
  else if cmd = 'code' then
  begin
    ViewQarEntryCodeCommand;
  end
  else if cmd = '' then
  begin
    // No command specified, show usage
    PrintUsage;
  end
  else
  begin
    WriteLn('Error: Unknown command: ', cmd);
    WriteLn;
    PrintUsage;
    Halt(1);
  end;
end.

