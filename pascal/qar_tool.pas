{******************************************************************************
 * QAR Tool - Standalone QAR Utility
 *
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
 * Tác giả: QuickJS Pascal Binding
 * Ngày: 2024
 ******************************************************************************}

program qar_tool;

{$mode objfpc}{$H+}

uses
  SysUtils, ctypes, qar;

var
  init_default_lib: boolean = False;
  i: integer;
  cmd: string;
  output_file: string = '';
  input_file: string = '';
  input_files: array of string;
  j: integer;
  // Entry points cho manifest
  entry_main: string = '';
  entry_init: string = '';

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
  WriteLn('  version                 - Hiển thị phiên bản');
  WriteLn('  help                    - Hiển thị trợ giúp này');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  --init-lib              - Khởi tạo thư viện QuickJS mặc định khi hiển thị info');
  WriteLn;
  WriteLn('Ví dụ:');
  WriteLn('  qar_tool info');
  WriteLn('  qar_tool info --init-lib');
  WriteLn('  qar_tool build output.qar file1.js file2.js');
  WriteLn('  qar_tool build output.qar src/');
  WriteLn('  qar_tool inspect file.qar');
  WriteLn('  qar_tool rebuild old.qar new.qar');
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
  
  ret := BuildQar(output_file, input_files, entry_main, entry_init);
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

procedure RebuildQarFileCommand;
var
  ret: cint;
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
  
  ret := qar.RebuildQarFile(input_file, output_file, entry_main, entry_init);
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
  
  // Parse options and command
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '--init-lib') or (ParamStr(i) = '-i') then
    begin
      init_default_lib := True;
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
      end;
      Inc(i);
    end;
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

