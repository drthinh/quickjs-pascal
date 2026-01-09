unit qjsp_qar_tooling;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, ctypes, qar;

function QarPrintInspection(const qar_file: string; const prefix: string; out err: string): boolean;
function QarCatSpecToStdout(const spec: string; out err: string): boolean;
function QarExtractToDir(const qar_file: string; const out_dir: string; out err: string): boolean;

implementation

function EnsureDirExists(const dir: string): boolean;
begin
  if dir = '' then
    Exit(False);
  if DirectoryExists(dir) then
    Exit(True);
  Result := ForceDirectories(dir);
end;

function WriteBytesToFile(const filename: string; const bytes: TBytes): boolean;
var
  fs: TFileStream;
begin
  Result := False;
  if not EnsureDirExists(ExtractFileDir(filename)) then
    Exit;
  try
    fs := TFileStream.Create(filename, fmCreate);
    try
      if Length(bytes) > 0 then
        fs.WriteBuffer(bytes[0], Length(bytes));
      Result := True;
    finally
      fs.Free;
    end;
  except
    Result := False;
  end;
end;

function ParseQarEntrySpecLoose(const spec: string; out qar_path: string; out entry_path: string): boolean;
var
  lower_spec: string;
  sep_pos: SizeInt;
begin
  Result := False;
  qar_path := '';
  entry_path := '';

  lower_spec := LowerCase(spec);
  sep_pos := Pos('.qar/', lower_spec);
  if sep_pos = 0 then
    sep_pos := Pos('.qar\\', lower_spec);
  if sep_pos <= 0 then
    Exit(False);

  qar_path := Copy(spec, 1, sep_pos + 3);
  entry_path := Copy(spec, sep_pos + 5, Length(spec));
  entry_path := StringReplace(entry_path, '\\', '/', [rfReplaceAll]);
  Result := (qar_path <> '') and (entry_path <> '');
end;

function QarPrintInspection(const qar_file: string; const prefix: string; out err: string): boolean;
var
  inspection: TQarInspectionResult;
begin
  Result := False;
  err := '';

  if qar_file = '' then
  begin
    err := 'Error: QAR file not specified';
    Exit;
  end;

  if not FileExists(qar_file) then
  begin
    err := 'Error: QAR file not found: ' + qar_file;
    Exit;
  end;

  inspection := qar.InspectQarFile(qar_file);
  try
    qar.PrintQarInspectionFiltered(inspection, prefix);
    Result := True;
  finally
    inspection.dependencies.Free;
  end;
end;

function QarCatSpecToStdout(const spec: string; out err: string): boolean;
var
  qar_path, entry_path: string;
  qar_file: PQarFile;
  entry: PQarEntry;
  entry_count: cint;
  i: integer;
  p: PChar;
  source_ptr: Pcuint8;
  source_len: csize_t;
  source_len_ni: NativeInt;
  s: AnsiString;
begin
  Result := False;
  err := '';

  if not ParseQarEntrySpecLoose(spec, qar_path, entry_path) then
  begin
    err := 'Error: Invalid QAR entry spec (expected file.qar/entryPath): ' + spec;
    Exit;
  end;

  if not FileExists(qar_path) then
  begin
    err := 'Error: QAR file not found: ' + qar_path;
    Exit;
  end;

  qar_file := qar_open(PChar(qar_path));
  if qar_file = nil then
  begin
    err := 'Error: Failed to open QAR file: ' + qar_path;
    Exit;
  end;

  try
    entry := qar_find_entry(qar_file, PChar(entry_path));
    if entry = nil then
    begin
      WriteLn('Error: Entry not found: ', entry_path);
      WriteLn;
      WriteLn('Available entries:');
      entry_count := qar_get_entry_count(qar_file);
      for i := 0 to integer(entry_count) - 1 do
      begin
        entry := qar_get_entry(qar_file, i);
        if entry <> nil then
        begin
          p := qar_entry_get_path(entry);
          if p <> nil then
            WriteLn('  ', p);
        end;
      end;
      err := 'Error: Entry not found: ' + entry_path;
      Exit;
    end;

    if qar_entry_load_data(qar_file, entry) < 0 then
    begin
      err := 'Error: Failed to load entry data: ' + entry_path;
      Exit;
    end;

    source_len := 0;
    source_ptr := qar_entry_get_source(entry, @source_len);
    if (source_ptr = nil) or (source_len = 0) then
    begin
      err := 'Error: Entry has no source/asset payload: ' + entry_path;
      Exit;
    end;

    source_len_ni := NativeInt(source_len);
    SetString(s, PAnsiChar(source_ptr), source_len_ni);
    Write(s);
    Result := True;
  finally
    qar_close(qar_file);
  end;
end;

function QarExtractToDir(const qar_file: string; const out_dir: string; out err: string): boolean;
var
  q: PQarFile;
  entry_count: cint;
  i: integer;
  entry: PQarEntry;
  p: PChar;
  src_len: csize_t;
  src_ptr: Pcuint8;
  bytes: TBytes;
  out_path: string;
  src_len_ni: NativeInt;
begin
  Result := False;
  err := '';

  if qar_file = '' then
  begin
    err := 'Error: QAR file not specified';
    Exit;
  end;
  if not FileExists(qar_file) then
  begin
    err := 'Error: QAR file not found: ' + qar_file;
    Exit;
  end;
  if not EnsureDirExists(out_dir) then
  begin
    err := 'Error: Cannot create output directory: ' + out_dir;
    Exit;
  end;

  q := qar_open(PChar(qar_file));
  if q = nil then
  begin
    err := 'Error: Failed to open QAR file: ' + qar_file;
    Exit;
  end;

  try
    entry_count := qar_get_entry_count(q);
    for i := 0 to integer(entry_count) - 1 do
    begin
      entry := qar_get_entry(q, i);
      if entry = nil then
        Continue;
      p := qar_entry_get_path(entry);
      if p = nil then
        Continue;
      if qar_entry_load_data(q, entry) < 0 then
        Continue;

      src_len := 0;
      src_ptr := qar_entry_get_source(entry, @src_len);
      if src_ptr = nil then
        Continue;

      src_len_ni := NativeInt(src_len);
      SetLength(bytes, src_len_ni);
      if src_len_ni > 0 then
        Move(src_ptr^, bytes[0], src_len_ni);

      out_path := IncludeTrailingPathDelimiter(out_dir) + string(p);
      out_path := StringReplace(out_path, '/', PathDelim, [rfReplaceAll]);
      if not WriteBytesToFile(out_path, bytes) then
      begin
        err := 'Error: Failed to write: ' + out_path;
        Exit;
      end;
    end;

    Result := True;
  finally
    qar_close(q);
  end;
end;

end.
