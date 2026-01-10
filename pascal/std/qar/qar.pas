{******************************************************************************
 * QAR (QuickJS Archive) Unit
 *
 * Mô tả:
 *   Unit này cung cấp các chức năng để tạo và đọc các file QAR (QuickJS Archive).
 *   QAR là định dạng archive chứa các file JavaScript đã được biên dịch thành
 *   bytecode và nén, cùng với source code gốc.
 *
 * Tính năng chính:
 *   - Tạo file QAR từ các file JavaScript (.js, .mjs)
 *   - Đọc và truy cập nội dung file QAR
 *   - Hỗ trợ module và script
 *   - Nén dữ liệu để bảo mật và giảm kích thước
 *   - Tự động phát hiện và đăng ký QAR dependencies
 *
 * Phiên bản:
 *   QAR Format Version: 1
 *   Unit Version: 1.0.0
 *
 * Yêu cầu:
 *   - QuickJS library (libqjs.dll/libqjs.so)
 *   - Free Pascal Compiler (FPC) hoặc Lazarus
 *
 * Sử dụng:
 *   - BuildQar: Tạo file QAR từ danh sách file JavaScript
 *   - Các hàm qar_*: Đọc và truy cập nội dung QAR
 *
 * Ví dụ:
 *   BuildQar('output.qar', ['file1.js', 'file2.js']);
 *   BuildQar('output.qar', ['src/']);  // Từ thư mục
 *
 * Tác giả: QuickJS Pascal Binding
 * Ngày: 2024
 ******************************************************************************}

unit qar;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, SysUtils, Classes, quickjs_types, quickjs_core, quickjs_std, fpjson, quickjs_miniz,
  qcrypto_sha256, qcrypto_base64, qcrypto_ed25519_sign, qcrypto_ed25519_keyload;

const
  {$IFDEF WINDOWS}
  libqjs = 'libqjs.dll';
  {$ELSE}
  libqjs = 'libqjs.so';
  {$ENDIF}

  // QAR Version Information
  QAR_VERSION_MAJOR = 1;
  QAR_VERSION_MINOR = 0;
  QAR_VERSION_PATCH = 0;
  QAR_FORMAT_VERSION = 1;  // Format version trong file QAR
  QAR_VERSION_STRING = '1.0.0';

type
  // QAR reading types
  TQarEntry = record
    path: AnsiString;
    path_len: cuint32;
    offset: cuint64;
    bytecode_offset: cuint64;
    flags: cuint32;
    bytecode_size: cuint64;
    source_size: cuint64;
    bytecode_orig_size: cuint64;
    source_orig_size: cuint64;
    bytecode_cache: TBytes;
    source_cache: TBytes;
  end;
  PQarEntry = ^TQarEntry;

  TQarFile = record
    file_stream: TFileStream;
    version: cuint32;
    manifest_offset: cuint64;
    manifest_size: cuint64;
    manifest_json: UTF8String;
    quickjs_version: UTF8String;
    entries: array of TQarEntry;
    entry_count: cint;
    entries_offset: cuint64;
  end;
  PQarFile = ^TQarFile;

  Pcsize_t = ^csize_t;
  Pcuint8 = ^cuint8;

  // QAR building types
  TQarBuildEntry = record
    path: string;        // Path in archive (e.g., "lib/utils.js")
    filepath: string;    // Real file path
    bytecode: Pcuint8;
    bytecode_len: csize_t;
    source: Pcuint8;
    source_len: csize_t;
    sha256_bytecode: string;
    sha256_source: string;
    is_module: cint;     // 1 if ES module, 0 if script
    is_asset: cint;      // 1 if non-JS asset (stored in source)
    bytecode_compressed: Pcuint8;  // Compressed bytecode
    bytecode_compressed_len: csize_t;
    source_compressed: Pcuint8;     // Compressed source / asset payload
    source_compressed_len: csize_t;
    is_compressed: cint;  // 1 if compressed, 0 if not
  end;
  PQarBuildEntry = ^TQarBuildEntry;
  
  TQarEntryList = class
  private
    FEntries: array of TQarBuildEntry;
    FCount: integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const path, filepath: string; bytecode: Pcuint8; bytecode_len: csize_t;
                  source: Pcuint8; source_len: csize_t; is_module: cint; is_asset: cint);
    function GetEntry(index: integer): PQarBuildEntry;
    property Count: integer read FCount;
  end;

// QAR reading API functions
function qar_open(filename: PChar): PQarFile; cdecl;
procedure qar_close(qar: PQarFile); cdecl;
function qar_get_entry_count(qar: PQarFile): cint; cdecl;
function qar_get_entry(qar: PQarFile; index: cint): PQarEntry; cdecl;
function qar_find_entry(qar: PQarFile; path: PChar): PQarEntry; cdecl;
function qar_entry_get_path(entry: PQarEntry): PChar; cdecl;
function qar_entry_get_type(entry: PQarEntry): cint; cdecl;
function qar_entry_get_bytecode(entry: PQarEntry; len: Pcsize_t): Pcuint8; cdecl;
function qar_entry_get_source(entry: PQarEntry; len: Pcsize_t): Pcuint8; cdecl;
function qar_entry_load_data(qar: PQarFile; entry: PQarEntry): cint; cdecl;
function qar_get_manifest(qar: PQarFile; len: Pcsize_t): PChar; cdecl;
function qar_get_quickjs_version(qar: PQarFile): PChar; cdecl;

// QAR building API functions
// entry_main / entry_init cho phép chỉ định entry points giống "main"/"init" trong manifest.
// Có giá trị rỗng nếu không dùng.
function BuildQar(const output_file: string; const input_files: array of string;
  const entry_main: string = ''; const entry_init: string = '';
  const created_by: string = ''; const tool: string = ''; const meta: TStrings = nil;
  const sig_pubkey_b64: string = ''; const sig_b64: string = '';
  const sign_key_file: string = ''): cint;

// Version and information functions
function GetQarVersion: string;
function GetQuickJsVersion: string;
procedure PrintQarInfo(init_default_lib: boolean = False);
function GetQarInfoString(init_default_lib: boolean = False): string;

// QAR inspection / rebuild functions
type
  TQarInspectionResult = record
    qar_file: string;
    qar_format_version: integer;
    qar_version: string;
    quickjs_version: string;
    entry_count: integer;
    entries: array of record
      path: string;
      entry_type: string;  // 'module' or 'script'
      bytecode_size: csize_t;
      source_size: csize_t;
      is_compressed: boolean;  // Whether this entry is compressed
      compressed_bytecode_size: csize_t;  // Compressed size if compressed
      compressed_source_size: csize_t;    // Compressed size if compressed
    end;
    dependencies: TStringList;  // QAR files and DLL files referenced via LoadLibrary/LoadDynamicLibrary
    is_compatible: boolean;
    compatibility_message: string;
    has_compressed_entries: boolean;  // Whether any entry is compressed
  end;
  PQarInspectionResult = ^TQarInspectionResult;

function InspectQarFile(const qar_filename: string): TQarInspectionResult;
procedure PrintQarInspection(const result: TQarInspectionResult);
procedure PrintQarInspectionFiltered(const result: TQarInspectionResult; const prefix: string);
// entry_main / entry_init cho phép override entry_points khi rebuild (có thể rỗng để giữ nguyên).
function RebuildQarFile(const input_qar: string; const output_qar: string;
  const entry_main: string = ''; const entry_init: string = '';
  const sign_key_file: string = ''): cint;

implementation

const
  QAR_MAGIC: AnsiString = 'QAR' + #1;

function ReadU32(s: TStream; out v: cuint32): boolean;
begin
  Result := s.Read(v, SizeOf(v)) = SizeOf(v);
end;

function ReadU64(s: TStream; out v: cuint64): boolean;
begin
  Result := s.Read(v, SizeOf(v)) = SizeOf(v);
end;

function ReadBytes(s: TStream; var buf; len: NativeInt): boolean;
begin
  if len <= 0 then
    Exit(True);
  Result := s.Read(buf, len) = len;
end;

function SizeToNativeInt(sz: cuint64; out n: NativeInt): boolean;
begin
  if sz > cuint64(High(NativeInt)) then
    Exit(False);
  n := NativeInt(sz);
  Result := True;
end;

function ExtractQuickJsVersion(const manifest_json: UTF8String): UTF8String;
var
  keyPos: SizeInt;
  p: SizeInt;
  startQ: SizeInt;
  endQ: SizeInt;
  s: UTF8String;
begin
  Result := '';
  s := manifest_json;
  keyPos := Pos('"quickjs_version"', s);
  if keyPos <= 0 then
    Exit;
  p := keyPos + Length('"quickjs_version"');
  while (p <= Length(s)) and (s[p] <> ':') do
    Inc(p);
  if p > Length(s) then
    Exit;
  Inc(p);
  while (p <= Length(s)) and (s[p] <= ' ') do
    Inc(p);
  if (p > Length(s)) or (s[p] <> '"') then
    Exit;
  startQ := p + 1;
  endQ := startQ;
  while (endQ <= Length(s)) and (s[endQ] <> '"') do
    Inc(endQ);
  if endQ > Length(s) then
    Exit;
  Result := Copy(s, startQ, endQ - startQ);
end;

function qar_open(filename: PChar): PQarFile; cdecl;
var
  qar: PQarFile;
  magicBuf: array[0..3] of AnsiChar;
  magicStr: AnsiString;
  entryCountU32: cuint32;
  i: cint;
  pathLen: cuint32;
  flags: cuint32;
  bsz, ssz: cuint64;
  borig, sorig: cuint64;
  pathBytes: TBytes;
  n: NativeInt;
begin
  Result := nil;
  if filename = nil then
    Exit;

  New(qar);
  FillChar(qar^, SizeOf(qar^), 0);
  try
    qar^.file_stream := TFileStream.Create(string(filename), fmOpenRead or fmShareDenyNone);

    if not ReadBytes(qar^.file_stream, magicBuf[0], 4) then
      Exit;
    SetString(magicStr, PAnsiChar(@magicBuf[0]), 4);
    if magicStr <> QAR_MAGIC then
      Exit;

    if not ReadU32(qar^.file_stream, qar^.version) then
      Exit;
    if not ReadU64(qar^.file_stream, qar^.manifest_offset) then
      Exit;
    if not ReadU64(qar^.file_stream, qar^.manifest_size) then
      Exit;
    if not ReadU32(qar^.file_stream, entryCountU32) then
      Exit;

    if (entryCountU32 > 100000) then
      Exit;

    qar^.entry_count := cint(entryCountU32);
    qar^.entries_offset := cuint64(qar^.file_stream.Position);
    SetLength(qar^.entries, qar^.entry_count);

    for i := 0 to qar^.entry_count - 1 do
    begin
      if not ReadU32(qar^.file_stream, pathLen) then
        Exit;
      if (pathLen = 0) or (pathLen > 65536) then
        Exit;

      SetLength(pathBytes, pathLen);
      if not ReadBytes(qar^.file_stream, pathBytes[0], pathLen) then
        Exit;

      if not ReadU32(qar^.file_stream, flags) then
        Exit;
      if not ReadU64(qar^.file_stream, bsz) then
        Exit;
      if not ReadU64(qar^.file_stream, ssz) then
        Exit;
      if (flags and 2) <> 0 then
      begin
        if not ReadU64(qar^.file_stream, borig) then
          Exit;
        if not ReadU64(qar^.file_stream, sorig) then
          Exit;
      end
      else
      begin
        borig := bsz;
        sorig := ssz;
      end;

      qar^.entries[i].offset := 0;
      qar^.entries[i].path_len := pathLen;
      SetString(qar^.entries[i].path, PAnsiChar(@pathBytes[0]), pathLen);
      qar^.entries[i].flags := flags;
      qar^.entries[i].bytecode_size := bsz;
      qar^.entries[i].source_size := ssz;
      qar^.entries[i].bytecode_orig_size := borig;
      qar^.entries[i].source_orig_size := sorig;
      qar^.entries[i].bytecode_offset := cuint64(qar^.file_stream.Position);
      SetLength(qar^.entries[i].bytecode_cache, 0);
      SetLength(qar^.entries[i].source_cache, 0);

      qar^.file_stream.Seek(Int64(bsz + ssz), soCurrent);
    end;

    if qar^.manifest_size > 0 then
    begin
      qar^.file_stream.Position := Int64(qar^.manifest_offset);
      if not SizeToNativeInt(qar^.manifest_size, n) then
        Exit;
      SetLength(qar^.manifest_json, n);
      if qar^.file_stream.Read(qar^.manifest_json[1], n) <> n then
        Exit;
      qar^.quickjs_version := ExtractQuickJsVersion(qar^.manifest_json);
    end;

    Result := qar;
  finally
    if Result = nil then
    begin
      if Assigned(qar) then
      begin
        if Assigned(qar^.file_stream) then
          FreeAndNil(qar^.file_stream);
        Dispose(qar);
      end;
    end;
  end;
end;

procedure qar_close(qar: PQarFile); cdecl;
begin
  if qar = nil then
    Exit;
  if Assigned(qar^.file_stream) then
    FreeAndNil(qar^.file_stream);
  SetLength(qar^.entries, 0);
  qar^.manifest_json := '';
  qar^.quickjs_version := '';
  Dispose(qar);
end;

function qar_get_entry_count(qar: PQarFile): cint; cdecl;
begin
  if qar = nil then
    Exit(0);
  Result := qar^.entry_count;
end;

function qar_get_entry(qar: PQarFile; index: cint): PQarEntry; cdecl;
begin
  Result := nil;
  if (qar = nil) or (index < 0) or (index >= qar^.entry_count) then
    Exit;
  Result := @qar^.entries[index];
end;

function qar_find_entry(qar: PQarFile; path: PChar): PQarEntry; cdecl;
var
  i: cint;
  p: AnsiString;
begin
  Result := nil;
  if (qar = nil) or (path = nil) then
    Exit;
  p := AnsiString(path);
  for i := 0 to qar^.entry_count - 1 do
    if qar^.entries[i].path = p then
      Exit(@qar^.entries[i]);
end;

function qar_entry_get_path(entry: PQarEntry): PChar; cdecl;
begin
  if entry = nil then
    Exit(nil);
  Result := PChar(entry^.path);
end;

function qar_entry_get_type(entry: PQarEntry): cint; cdecl;
begin
  if entry = nil then
    Exit(0);
  if (entry^.flags and 4) <> 0 then
    Exit(2);
  if (entry^.flags and 1) <> 0 then
    Exit(1);
  Result := 0;
end;

function qar_entry_load_data(qar: PQarFile; entry: PQarEntry): cint; cdecl;
var
  comp: TBytes;
  destLen: mz_ulong;
  srcLen: mz_ulong;
  ret: cint;
  bcStart: Int64;
  n: NativeInt;
begin
  Result := -1;
  if (qar = nil) or (entry = nil) or (qar^.file_stream = nil) then
    Exit;

  bcStart := Int64(entry^.bytecode_offset);

  if (Length(entry^.bytecode_cache) = 0) and (entry^.bytecode_size > 0) then
  begin
    if not SizeToNativeInt(entry^.bytecode_size, n) then
      Exit;
    SetLength(comp, n);
    qar^.file_stream.Position := bcStart;
    if qar^.file_stream.Read(comp[0], n) <> n then
      Exit;
    if (entry^.flags and 2) <> 0 then
    begin
      destLen := mz_ulong(entry^.bytecode_orig_size);
      SetLength(entry^.bytecode_cache, destLen);
      srcLen := mz_ulong(entry^.bytecode_size);
      ret := mz_uncompress(@entry^.bytecode_cache[0], @destLen, @comp[0], srcLen);
      if ret <> MZ_OK then
      begin
        SetLength(entry^.bytecode_cache, 0);
        Exit;
      end;
      if destLen <> mz_ulong(entry^.bytecode_orig_size) then
        SetLength(entry^.bytecode_cache, destLen);
    end
    else
    begin
      entry^.bytecode_cache := comp;
    end;
  end;

  if (Length(entry^.source_cache) = 0) and (entry^.source_size > 0) then
  begin
    if not SizeToNativeInt(entry^.source_size, n) then
      Exit;
    SetLength(comp, n);
    qar^.file_stream.Position := bcStart + Int64(entry^.bytecode_size);
    if qar^.file_stream.Read(comp[0], n) <> n then
      Exit;
    if (entry^.flags and 2) <> 0 then
    begin
      destLen := mz_ulong(entry^.source_orig_size);
      SetLength(entry^.source_cache, destLen);
      srcLen := mz_ulong(entry^.source_size);
      ret := mz_uncompress(@entry^.source_cache[0], @destLen, @comp[0], srcLen);
      if ret <> MZ_OK then
      begin
        SetLength(entry^.source_cache, 0);
        Exit;
      end;
      if destLen <> mz_ulong(entry^.source_orig_size) then
        SetLength(entry^.source_cache, destLen);
    end
    else
    begin
      entry^.source_cache := comp;
    end;
  end;

  Result := 0;
end;

function qar_entry_get_bytecode(entry: PQarEntry; len: Pcsize_t): Pcuint8; cdecl;
begin
  if len <> nil then
    len^ := 0;
  if (entry = nil) or (Length(entry^.bytecode_cache) = 0) then
    Exit(nil);
  if len <> nil then
    len^ := Length(entry^.bytecode_cache);
  Result := @entry^.bytecode_cache[0];
end;

function qar_entry_get_source(entry: PQarEntry; len: Pcsize_t): Pcuint8; cdecl;
begin
  if len <> nil then
    len^ := 0;
  if (entry = nil) or (Length(entry^.source_cache) = 0) then
    Exit(nil);
  if len <> nil then
    len^ := Length(entry^.source_cache);
  Result := @entry^.source_cache[0];
end;

function qar_get_manifest(qar: PQarFile; len: Pcsize_t): PChar; cdecl;
begin
  if len <> nil then
    len^ := 0;
  if (qar = nil) or (qar^.manifest_json = '') then
    Exit(nil);
  if len <> nil then
    len^ := Length(qar^.manifest_json);
  Result := PChar(qar^.manifest_json);
end;

function qar_get_quickjs_version(qar: PQarFile): PChar; cdecl;
begin
  if (qar = nil) or (qar^.quickjs_version = '') then
    Exit(nil);
  Result := PChar(qar^.quickjs_version);
end;

// TQarEntryList implementation
constructor TQarEntryList.Create;
begin
  inherited;
  FCount := 0;
  SetLength(FEntries, 0);
end;

destructor TQarEntryList.Destroy;
var
  i: integer;
begin
  for i := 0 to FCount - 1 do
  begin
    // bytecode is allocated by JS_WriteObject, needs js_free_rt
    // But we don't have rt here, so we'll free it in BuildQar
    // source is allocated by GetMem, needs FreeMem
    if FEntries[i].source <> nil then
      FreeMem(FEntries[i].source);
    // compressed data is allocated by GetMem, needs FreeMem
    if FEntries[i].bytecode_compressed <> nil then
      FreeMem(FEntries[i].bytecode_compressed);
    if FEntries[i].source_compressed <> nil then
      FreeMem(FEntries[i].source_compressed);
  end;
  SetLength(FEntries, 0);
  inherited;
end;

procedure TQarEntryList.Add(const path, filepath: string; bytecode: Pcuint8; bytecode_len: csize_t;
                            source: Pcuint8; source_len: csize_t; is_module: cint; is_asset: cint);
var
  entry: PQarBuildEntry;
begin
  if FCount >= Length(FEntries) then
    SetLength(FEntries, Length(FEntries) + 10);
  
  FEntries[FCount].path := path;
  FEntries[FCount].filepath := filepath;
  FEntries[FCount].bytecode := bytecode;
  FEntries[FCount].bytecode_len := bytecode_len;
  FEntries[FCount].source := source;
  FEntries[FCount].source_len := source_len;
  FEntries[FCount].sha256_bytecode := '';
  FEntries[FCount].sha256_source := '';
  FEntries[FCount].is_module := is_module;
  FEntries[FCount].is_asset := is_asset;
  FEntries[FCount].bytecode_compressed := nil;
  FEntries[FCount].bytecode_compressed_len := 0;
  FEntries[FCount].source_compressed := nil;
  FEntries[FCount].source_compressed_len := 0;
  FEntries[FCount].is_compressed := 0;
  Inc(FCount);
end;

function TQarEntryList.GetEntry(index: integer): PQarBuildEntry;
begin
  if (index >= 0) and (index < FCount) then
    Result := @FEntries[index]
  else
    Result := nil;
end;

// Helper function to check if file is JS file
function IsJSFile(const filename: string): boolean;
begin
  Result := (LowerCase(ExtractFileExt(filename)) = '.js') or
            (LowerCase(ExtractFileExt(filename)) = '.mjs');
end;

// Forward declaration for dynamic library check
function IsDynamicLibraryFile(const filename: string): boolean; forward;

// Helper function to check if file is asset (non-JS) supported
function IsAssetFile(const filename: string): boolean;
var
  ext: string;
begin
  ext := LowerCase(ExtractFileExt(filename));
  // Treat anything that is not JS and not a dynamic library as asset.
  if IsJSFile(filename) or IsDynamicLibraryFile(filename) then
    Exit(False);
  // Known common asset extensions (non-exhaustive)
  if (ext = '.json') or (ext = '.png') or (ext = '.jpg') or (ext = '.jpeg') or
     (ext = '.gif') or (ext = '.mp3') or (ext = '.ogg') or (ext = '.wav') or
     (ext = '.mp4') or (ext = '.webp') or (ext = '.svg') or (ext = '.txt') or
     (ext = '.bin') or (ext = '.dat') or (ext = '.bmp') or (ext = '.ico') or
     (ext = '.csv') or (ext = '.yml') or (ext = '.yaml') or (ext = '.xml') or
     (ext = '.wasm') or (ext = '.ttf') or (ext = '.otf') or (ext = '.woff') or (ext = '.woff2') or
     (ext = '.mpg') or (ext = '.mpeg') or (ext = '.mov') or (ext = '.avi') or
     (ext = '.m4a') or (ext = '.flac') or (ext = '.ape') or (ext = '.alac') or
     (ext = '.jsonl') or (ext = '.md') or (ext = '.pdf') or (ext = '.zip') or (ext = '.rar') or
     (ext = '.7z') or (ext = '.tar') or (ext = '.gz') or (ext = '.bz2') or (ext = '.xz') or
     (ext = '.patch') or (ext = '.diff') or (ext = '.psd') or (ext = '.glb') or (ext = '.gltf') or
     (ext = '.obj') or (ext = '.fbx') or (ext = '.shader') or (ext = '.vert') or (ext = '.frag') or
     (ext = '.ini') or (ext = '.conf') or (ext = '.log') or (ext = '.cue') or
     (ext = '.wavpack') or (ext = '.rpf') or (ext = '.mp1') or (ext = '.mp2') or (ext = '.jsonc') or
     (ext = '.ts') or (ext = '.mts') or (ext = '.cts') then
    Exit(True);

  // Fallback: any non-JS, non-dynamic-library file is treated as asset
  Result := True;
end;

// Helper function to normalize path (convert \ to /)
procedure NormalizePath(var path: string);
var
  i: integer;
begin
  for i := 1 to Length(path) do
    if path[i] = '\' then
      path[i] := '/';
end;

// Compress data using miniz
function CompressData(const src: Pcuint8; src_len: csize_t; 
                     var dst: Pcuint8; var dst_len: csize_t): cint;
var
  dest_len: mz_ulong;
  compressed: Pcuint8;
  ret: cint;
begin
  Result := -1;
  
  dest_len := mz_compressBound(mz_ulong(src_len));
  compressed := GetMem(dest_len);
  if compressed = nil then
    Exit;
  
  ret := mz_compress2(compressed, @dest_len, src, mz_ulong(src_len), MZ_DEFAULT_LEVEL);
  if ret <> MZ_OK then
  begin
    FreeMem(compressed);
    Exit;
  end;
  
  dst := compressed;
  dst_len := csize_t(dest_len);
  Result := 0;
end;

// Compress entry data - always compress to prevent code modification/corruption/injection
procedure CompressEntry(entry: PQarBuildEntry);
var
  bytecode_compressed: Pcuint8;
  bytecode_compressed_len: csize_t;
  source_compressed: Pcuint8;
  source_compressed_len: csize_t;
begin
  bytecode_compressed := nil;
  bytecode_compressed_len := 0;
  source_compressed := nil;
  source_compressed_len := 0;
  
  // Compress bytecode - always compress
  if entry^.bytecode_len > 0 then
  begin
    if CompressData(entry^.bytecode, entry^.bytecode_len, 
                   bytecode_compressed, bytecode_compressed_len) = 0 then
    begin
      // Always use compressed version to prevent tampering
      entry^.bytecode_compressed := bytecode_compressed;
      entry^.bytecode_compressed_len := bytecode_compressed_len;
    end;
  end;
  
  // Compress source - always compress
  if entry^.source_len > 0 then
  begin
    if CompressData(entry^.source, entry^.source_len, 
                   source_compressed, source_compressed_len) = 0 then
    begin
      // Always use compressed version to prevent tampering
      entry^.source_compressed := source_compressed;
      entry^.source_compressed_len := source_compressed_len;
    end;
  end;
  
  // Mark as compressed if either is compressed (should always be true now)
  if (entry^.bytecode_compressed <> nil) or (entry^.source_compressed <> nil) then
    entry^.is_compressed := 1;
end;

// Helper function to check if a file is a dynamic library
function IsDynamicLibraryFile(const filename: string): boolean;
var
  ext: string;
begin
  ext := LowerCase(ExtractFileExt(filename));
  Result := (ext = '.dll') or (ext = '.so') or (ext = '.dylib');
end;

// Parse JavaScript file to find LoadLibrary and LoadDynamicLibrary calls
// Returns list of QAR filenames and DLL filenames that need to be loaded
procedure ParseLoadLibraryCalls(const filepath: string; var qar_files: TStringList);
var
  f: TextFile;
  line: string;
  pos_load, pos_start, pos_end: integer;
  lib_file: string;
  quote_char: char;
begin
  if not FileExists(filepath) then
    Exit;
  
  AssignFile(f, filepath);
  try
    Reset(f);
    while not EOF(f) do
    begin
      ReadLn(f, line);
      
      // Look for LoadLibrary('...') or LoadLibrary("...")
      pos_load := Pos('LoadLibrary', line);
      if pos_load > 0 then
      begin
        // Find opening parenthesis
        pos_start := pos_load;
        while (pos_start <= Length(line)) and (line[pos_start] <> '(') do
          Inc(pos_start);
        
        if pos_start <= Length(line) then
        begin
          Inc(pos_start); // Skip '('
          // Skip whitespace
          while (pos_start <= Length(line)) and (line[pos_start] in [' ', #9]) do
            Inc(pos_start);
          
          // Check for string literal
          if (pos_start <= Length(line)) and (line[pos_start] in ['''', '"']) then
          begin
            quote_char := line[pos_start];
            Inc(pos_start); // Skip opening quote
            pos_end := pos_start;
            
            // Find closing quote
            while (pos_end <= Length(line)) and (line[pos_end] <> quote_char) do
            begin
              // Handle escaped quotes
              if (line[pos_end] = '\') and (pos_end < Length(line)) then
                Inc(pos_end);
              Inc(pos_end);
            end;
            
            if pos_end <= Length(line) then
            begin
              lib_file := Copy(line, pos_start, pos_end - pos_start);
              // Remove escape sequences (simple version)
              lib_file := StringReplace(lib_file, '\''', '''', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\"', '"', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\\', '\', [rfReplaceAll]);
              
              if (lib_file <> '') and (qar_files.IndexOf(lib_file) < 0) then
                qar_files.Add(lib_file);
            end;
          end;
        end;
      end;
      
      // Look for LoadDynamicLibrary('...') or LoadDynamicLibrary("...")
      pos_load := Pos('LoadDynamicLibrary', line);
      if pos_load > 0 then
      begin
        // Find opening parenthesis
        pos_start := pos_load;
        while (pos_start <= Length(line)) and (line[pos_start] <> '(') do
          Inc(pos_start);
        
        if pos_start <= Length(line) then
        begin
          Inc(pos_start); // Skip '('
          // Skip whitespace
          while (pos_start <= Length(line)) and (line[pos_start] in [' ', #9]) do
            Inc(pos_start);
          
          // Check for string literal
          if (pos_start <= Length(line)) and (line[pos_start] in ['''', '"']) then
          begin
            quote_char := line[pos_start];
            Inc(pos_start); // Skip opening quote
            pos_end := pos_start;
            
            // Find closing quote
            while (pos_end <= Length(line)) and (line[pos_end] <> quote_char) do
            begin
              // Handle escaped quotes
              if (line[pos_end] = '\') and (pos_end < Length(line)) then
                Inc(pos_end);
              Inc(pos_end);
            end;
            
            if pos_end <= Length(line) then
            begin
              lib_file := Copy(line, pos_start, pos_end - pos_start);
              // Remove escape sequences
              lib_file := StringReplace(lib_file, '\''', '''', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\"', '"', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\\', '\', [rfReplaceAll]);
              
              // Add to dependencies if it's a dynamic library file
              if (lib_file <> '') and IsDynamicLibraryFile(lib_file) and (qar_files.IndexOf(lib_file) < 0) then
                qar_files.Add(lib_file);
            end;
          end;
        end;
      end;
    end;
  finally
    CloseFile(f);
  end;
end;

// Recursively add JS files from directory or single file
procedure AddFileToList(list: TQarEntryList; const base_dir, filepath: string);
var
  search_rec: TSearchRec;
  fullpath, rel_path: string;
  base_len: integer;
  basename: string;
  normalized_filepath: string;
  normalized_base_dir: string;
begin
  if DirectoryExists(filepath) then
  begin
    // Recursively add directory contents
    if FindFirst(IncludeTrailingPathDelimiter(filepath) + '*', faAnyFile, search_rec) = 0 then
    begin
      repeat
        if (search_rec.Name = '.') or (search_rec.Name = '..') then
          Continue;
        
        fullpath := IncludeTrailingPathDelimiter(filepath) + search_rec.Name;
        
        if (search_rec.Attr and faDirectory) <> 0 then
        begin
          // It's a directory, recurse
          AddFileToList(list, base_dir, fullpath);
        end
        else if IsJSFile(search_rec.Name) or IsAssetFile(search_rec.Name) then
        begin
          // It's a JS file, add it
          AddFileToList(list, base_dir, fullpath);
        end;
      until FindNext(search_rec) <> 0;
      FindClose(search_rec);
    end;
  end
  else if FileExists(filepath) and (IsJSFile(filepath) or IsAssetFile(filepath)) then
  begin
    // Add single file
    // Normalize both paths for comparison
    normalized_filepath := ExpandFileName(filepath);
    NormalizePath(normalized_filepath);
    
    if base_dir <> '' then
    begin
      normalized_base_dir := ExpandFileName(base_dir);
      NormalizePath(normalized_base_dir);
      // Ensure base_dir ends with path delimiter
      if not (normalized_base_dir[Length(normalized_base_dir)] in ['/', '\']) then
        normalized_base_dir := normalized_base_dir + '/';
    end
    else
      normalized_base_dir := '';
    
    base_len := Length(normalized_base_dir);
    if (base_len > 0) and (Copy(normalized_filepath, 1, base_len) = normalized_base_dir) then
    begin
      rel_path := Copy(normalized_filepath, base_len + 1, Length(normalized_filepath));
    end
    else
    begin
      // Use basename only
      basename := ExtractFileName(filepath);
      rel_path := basename;
    end;
    NormalizePath(rel_path);
    
    // Add entry with empty data (will be compiled later)
    if IsJSFile(filepath) then
      list.Add(rel_path, filepath, nil, 0, nil, 0, 1, 0)
    else
      list.Add(rel_path, filepath, nil, 0, nil, 0, 0, 1);
  end;
end;

// Compile JS file to bytecode
function CompileAndAddEntry(ctx: PJSContext; entry: PQarBuildEntry): cint;
var
  buf: Pcuint8;
  buf_len: csize_t;
  obj: JSValue;
  eval_flags: cint;
  is_module: cint;
  source_buf: Pcuint8;
begin
  Result := -1;
  
  // Load source or asset file
  buf := js_load_file(ctx, @buf_len, PChar(entry^.filepath));
  if buf = nil then
  begin
    WriteLn('Could not load file: ', entry^.filepath);
    Exit;
  end;
  
  // Save source/asset data - allocate regular memory and copy
  source_buf := GetMem(buf_len);
  if source_buf = nil then
  begin
    js_free(ctx, buf);
    Exit;
  end;
  Move(buf^, source_buf^, buf_len);
  entry^.source := source_buf;
  entry^.source_len := buf_len;
  
  // Asset: skip compilation, no bytecode
  if entry^.is_asset <> 0 then
  begin
    entry^.bytecode := nil;
    entry^.bytecode_len := 0;
    entry^.is_module := 0;
    js_free(ctx, buf);
    Result := 0;
    Exit;
  end;
  
  // Detect module type
  is_module := 0;
  if (LowerCase(ExtractFileExt(entry^.filepath)) = '.mjs') or
     (JS_DetectModule(PChar(buf), buf_len) <> 0) then
    is_module := 1;
  entry^.is_module := is_module;
  
  // Compile to bytecode
  eval_flags := JS_EVAL_FLAG_COMPILE_ONLY;
  if is_module <> 0 then
    eval_flags := eval_flags or JS_EVAL_TYPE_MODULE
  else
    eval_flags := eval_flags or JS_EVAL_TYPE_GLOBAL;
  
  obj := JS_Eval(ctx, PChar(buf), buf_len, PChar(entry^.filepath), eval_flags);
  js_free(ctx, buf);
  
  if JS_IsException(obj) <> 0 then
  begin
    WriteLn('Compilation error in ', entry^.filepath, ':');
    js_std_dump_error(ctx);
    FreeMem(source_buf);
    entry^.source := nil;
    Exit;
  end;
  
  // Write bytecode
  entry^.bytecode := JS_WriteObject(ctx, @entry^.bytecode_len, obj, 
                                    JS_WRITE_OBJ_BYTECODE or JS_WRITE_OBJ_REFERENCE);
  JS_FreeValue(ctx, obj);
  
  if entry^.bytecode = nil then
  begin
    WriteLn('Failed to write bytecode for ', entry^.filepath);
    FreeMem(source_buf);
    entry^.source := nil;
    Exit;
  end;
  
  Result := 0;
end;

// Write string to file (length + data)
procedure WriteString(var f: File; const str: string);
var
  len: uint32;
begin
  len := Length(str);
  BlockWrite(f, len, 4);
  if len > 0 then
    BlockWrite(f, str[1], len);
end;

// Write manifest as JSON
// entry_main / entry_init dùng để tạo trường "entry_points" trong manifest nếu được thiết lập.
procedure WriteManifest(var f: File; list: TQarEntryList; const qjs_version: string;
  const entry_main: string; const entry_init: string;
  const created_by: string; const tool: string; const meta: TStrings;
  const built_at: string;
  const sig_pubkey_b64: string; const sig_b64: string);
var
  root, entryPoints, entryObj, metaObj, sigObj: TJSONObject;
  entries: TJSONArray;
  i: integer;
  entry: PQarBuildEntry;
  manifestStr: string;
  payload: UTF8String;
  payloadBytes: TBytes;
  payloadB64: string;

  function EscapeLine(const s: string): string;
  begin
    Result := StringReplace(s, #13, '', [rfReplaceAll]);
    Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  end;

  function BuildSigPayload: UTF8String;
  var
    j: Integer;
    e: PQarBuildEntry;
    kind: string;
    sb: UTF8String;
  begin
    sb := 'QAR-SIG-PAYLOAD\n';
    sb := sb + 'format=qar\n';
    sb := sb + 'manifest_version=2\n';
    sb := sb + 'quickjs_version=' + EscapeLine(qjs_version) + '\n';
    sb := sb + 'built_at=' + EscapeLine(built_at) + '\n';
    sb := sb + 'created_by=' + EscapeLine(created_by) + '\n';
    sb := sb + 'tool=' + EscapeLine(tool) + '\n';
    if (meta <> nil) and (meta.Count > 0) then
    begin
      for j := 0 to meta.Count - 1 do
        if meta.Names[j] <> '' then
          sb := sb + 'meta.' + EscapeLine(meta.Names[j]) + '=' + EscapeLine(meta.ValueFromIndex[j]) + '\n';
    end;
    sb := sb + 'entries=' + IntToStr(list.Count) + '\n';
    for j := 0 to list.Count - 1 do
    begin
      e := list.GetEntry(j);
      sb := sb + 'entry.path=' + EscapeLine(e^.path) + '\n';
      if e^.is_asset <> 0 then
        kind := 'asset'
      else if e^.is_module <> 0 then
        kind := 'module'
      else
        kind := 'script';
      sb := sb + 'entry.type=' + kind + '\n';
      sb := sb + 'entry.sha256_source=' + EscapeLine(e^.sha256_source) + '\n';
      sb := sb + 'entry.sha256_bytecode=' + EscapeLine(e^.sha256_bytecode) + '\n';
    end;
    Result := sb;
  end;
begin
  root := TJSONObject.Create;
  try
    // Thông tin cơ bản của manifest
    root.Add('format', 'qar');
    // Tăng version manifest lên 2 khi có hỗ trợ entry_points
    root.Add('version', 2);
    root.Add('quickjs_version', qjs_version);

    // Optional build metadata
    if created_by <> '' then
      root.Add('created_by', created_by);
    if tool <> '' then
      root.Add('tool', tool);
    root.Add('built_at', built_at);

    if (meta <> nil) and (meta.Count > 0) then
    begin
      metaObj := TJSONObject.Create;
      for i := 0 to meta.Count - 1 do
      begin
        if meta.Names[i] <> '' then
          metaObj.Add(meta.Names[i], meta.ValueFromIndex[i]);
      end;
      if metaObj.Count > 0 then
        root.Add('meta', metaObj)
      else
        metaObj.Free;
    end;

    // Ghi thêm entry_points nếu có cấu hình
    if (entry_main <> '') or (entry_init <> '') then
    begin
      entryPoints := TJSONObject.Create;
      if entry_main <> '' then
        entryPoints.Add('main', entry_main);
      if entry_init <> '' then
        entryPoints.Add('init', entry_init);
      root.Add('entry_points', entryPoints);
    end;

    // Danh sách entries
    entries := TJSONArray.Create;
    for i := 0 to list.Count - 1 do
    begin
      entry := list.GetEntry(i);
      entryObj := TJSONObject.Create;
      entryObj.Add('path', entry^.path);
      if entry^.is_asset <> 0 then
        entryObj.Add('type', 'asset')
      else if entry^.is_module <> 0 then
        entryObj.Add('type', 'module')
      else
        entryObj.Add('type', 'script');
      entryObj.Add('bytecode_size', Int64(entry^.bytecode_len));
      entryObj.Add('source_size', Int64(entry^.source_len));
      if entry^.sha256_bytecode <> '' then
        entryObj.Add('sha256_bytecode', entry^.sha256_bytecode);
      if entry^.sha256_source <> '' then
        entryObj.Add('sha256_source', entry^.sha256_source);
      entries.Add(entryObj);
    end;
    root.Add('entries', entries);

    // Deterministic payload for signing/verifying (base64)
    payload := BuildSigPayload;
    SetLength(payloadBytes, Length(payload));
    if Length(payloadBytes) > 0 then
      Move(payload[1], payloadBytes[0], Length(payloadBytes));
    payloadB64 := Base64Encode(payloadBytes);
    if payloadB64 <> '' then
      root.Add('sig_payload_b64', payloadB64);

    // Optional signature block (verify-only in loader)
    if (sig_pubkey_b64 <> '') and (sig_b64 <> '') then
    begin
      sigObj := TJSONObject.Create;
      sigObj.Add('alg', 'ed25519');
      sigObj.Add('pubkey', sig_pubkey_b64);
      sigObj.Add('sig', sig_b64);
      root.Add('sig', sigObj);
    end;

    // Serialize JSON (pretty format để dễ debug, nhưng parser bên C vẫn đọc bình thường)
    manifestStr := root.FormatJSON([]);
    if manifestStr <> '' then
      BlockWrite(f, manifestStr[1], Length(manifestStr));
  finally
    root.Free;
  end;
end;

// Create QAR file
function CreateQar(const output_file: string; list: TQarEntryList; const qjs_version: string;
  const entry_main: string; const entry_init: string;
  const created_by: string; const tool: string; const meta: TStrings;
  const built_at: string;
  const sig_pubkey_b64: string; const sig_b64: string): cint;
var
  f: File;
  magic: array[0..3] of char = ('Q', 'A', 'R', #$01);
  version: uint32 = 1;
  manifest_offset, manifest_size: uint64;
  manifest_offset_pos: int64;
  entry_count: uint32;
  i: integer;
  flags: uint32;
  bytecode_size, source_size: uint64;
  entry: PQarBuildEntry;
begin
  Result := -1;
  
  AssignFile(f, output_file);
  try
    Rewrite(f, 1); // Binary mode
  except
    WriteLn('Cannot create output file: ', output_file);
    Exit;
  end;
  
  try
    // Write magic and version
    BlockWrite(f, magic, 4);
    BlockWrite(f, version, 4);
    
    // Write manifest offset placeholder (will update later)
    manifest_offset := 0;
    manifest_size := 0;
    manifest_offset_pos := FilePos(f);
    BlockWrite(f, manifest_offset, 8);
    BlockWrite(f, manifest_size, 8);
    
    // Write entries
    entry_count := list.Count;
    BlockWrite(f, entry_count, 4);
    
    for i := 0 to list.Count - 1 do
    begin
      entry := list.GetEntry(i);
      
      // Compress entry data
      CompressEntry(entry);
      
      // Write entry header
      WriteString(f, entry^.path);
      flags := 0;
      if entry^.is_module <> 0 then
        flags := flags or 1;  // Bit 0 = module
      if entry^.is_compressed <> 0 then
        flags := flags or 2;  // Bit 1 = compressed
      if entry^.is_asset <> 0 then
        flags := flags or 4;  // Bit 2 = asset
      BlockWrite(f, flags, 4);
      
      // Write sizes - use compressed sizes if available, otherwise original
      if entry^.bytecode_compressed <> nil then
        bytecode_size := entry^.bytecode_compressed_len
      else
        bytecode_size := entry^.bytecode_len;
      if entry^.source_compressed <> nil then
        source_size := entry^.source_compressed_len
      else
        source_size := entry^.source_len;
      BlockWrite(f, bytecode_size, 8);
      BlockWrite(f, source_size, 8);
      
      // Write original sizes if compressed
      if entry^.is_compressed <> 0 then
      begin
        BlockWrite(f, entry^.bytecode_len, 8);  // Original bytecode size
        BlockWrite(f, entry^.source_len, 8);   // Original source size
      end;
      
      // Write data - use compressed if available
      if entry^.bytecode_compressed <> nil then
        BlockWrite(f, entry^.bytecode_compressed^, entry^.bytecode_compressed_len)
      else if entry^.bytecode <> nil then
        BlockWrite(f, entry^.bytecode^, entry^.bytecode_len);
      if entry^.source_compressed <> nil then
        BlockWrite(f, entry^.source_compressed^, entry^.source_compressed_len)
      else if entry^.source <> nil then
        BlockWrite(f, entry^.source^, entry^.source_len);
    end;
    
    // Write manifest (kèm thông tin entry_points nếu có)
    manifest_offset := FilePos(f);
    WriteManifest(f, list, qjs_version, entry_main, entry_init, created_by, tool, meta, built_at, sig_pubkey_b64, sig_b64);
    manifest_size := FilePos(f) - manifest_offset;
    
    // Update manifest offset and size
    Seek(f, manifest_offset_pos);
    BlockWrite(f, manifest_offset, 8);
    BlockWrite(f, manifest_size, 8);
    
    Result := 0;
  finally
    CloseFile(f);
  end;
end;

function Sha256HexPtr(p: Pcuint8; len: csize_t): string;
begin
  if (p = nil) or (len = 0) then
    Exit('');
  Result := Sha256DigestHex(p^, NativeUInt(len));
end;

function TryLoadModuleFromOpaqueQars(ctx: PJSContext; const module_name: string; opaque: pointer): PJSModuleDef; forward;

// Custom module loader wrapper for BuildQar with fallback path resolution
// Tries multiple path variations to handle QAR files that store only basenames
function js_module_loader_build_wrapper(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl;
var
  m: PJSModuleDef;
  module_name_str: string;
  basename: string;
  last_slash: integer;
begin
  module_name_str := string(module_name);

  // First try QAR dependencies registered in opaque
  m := TryLoadModuleFromOpaqueQars(ctx, module_name_str, opaque);
  if m <> nil then
  begin
    Result := m;
    Exit;
  end;

  // Then try the exact path (standard behavior)
  m := js_module_loader(ctx, module_name, opaque);
  if m <> nil then
  begin
    Result := m;
    Exit;
  end;
  
  // If not found, try extracting basename (for QAR files that only store filenames)
  
  // Skip fallback if using prefix notation (e.g., "lib1:math.js")
  if Pos(':', module_name_str) > 0 then
  begin
    Result := nil;
    Exit;
  end;
  
  // NOTE: Code below is a workaround for path mismatch issues.
  // It handles specific test paths that may not match QAR entry paths.
  // 
  // WHY THIS EXISTS:
  // - When JS code imports 'qar_test_lib/math.js' but QAR stores 'math.js',
  //   the import fails. This code tries removing the prefix as a fallback.
  // 
  // WHEN TO REMOVE:
  // - If all QAR files are built with correct paths matching import statements,
  //   this code is NOT necessary and can be removed.
  // - This is a temporary workaround, not a permanent solution.
  // - Better solution: Build QAR files with paths that match import statements.
  //
  // Try removing common path prefixes first (more specific)
  // TODO: Consider removing this if QAR files are built with correct paths
  
  // if Pos('qar_test_lib/', module_name_str) > 0 then
  // begin
  //   basename := StringReplace(module_name_str, 'qar_test_lib/', '', []);
  //   m := js_module_loader(ctx, PChar(basename), opaque);
  //   if m <> nil then
  //   begin
  //     Result := m;
  //     Exit;
  //   end;
  // end;
  
  // if Pos('tests/qar_test_lib/', module_name_str) > 0 then
  // begin
  //   basename := StringReplace(module_name_str, 'tests/qar_test_lib/', '', []);
  //   m := js_module_loader(ctx, PChar(basename), opaque);
  //   if m <> nil then
  //   begin
  //     Result := m;
  //     Exit;
  //   end;
  // end;
  
  // Last resort: try extracting basename (filename only)
  last_slash := LastDelimiter('/\', module_name_str);
  if last_slash > 0 then
  begin
    basename := Copy(module_name_str, last_slash + 1, Length(module_name_str));
    m := TryLoadModuleFromOpaqueQars(ctx, basename, opaque);
    if m <> nil then
    begin
      Result := m;
      Exit;
    end;
    m := js_module_loader(ctx, PChar(basename), opaque);
    if m <> nil then
    begin
      Result := m;
      Exit;
    end;
  end;
  
  // Not found with any variation
  Result := nil;
end;

type
  TBuildQarOpaque = record
    qars: array of PQarFile;
  end;
  PBuildQarOpaque = ^TBuildQarOpaque;

function JSValuePtr(const v: JSValue): pointer; inline;
begin
  Result := v.u.ptr;
end;

function TryLoadModuleFromOpaqueQars(ctx: PJSContext; const module_name: string; opaque: pointer): PJSModuleDef;
var
  o: PBuildQarOpaque;
  i: integer;
  entry: PQarEntry;
  bytecode_len: csize_t;
  bytecode: Pcuint8;
  obj: JSValue;
  eval_flags: cint;
  m: PJSModuleDef;
begin
  Result := nil;
  if opaque = nil then
    Exit;
  o := PBuildQarOpaque(opaque);
  for i := 0 to High(o^.qars) do
  begin
    if o^.qars[i] = nil then
      Continue;
    entry := qar_find_entry(o^.qars[i], PChar(module_name));
    if entry = nil then
      Continue;
    if qar_entry_get_type(entry) = 0 then
      Continue;
    if qar_entry_load_data(o^.qars[i], entry) < 0 then
      Continue;
    bytecode_len := 0;
    bytecode := qar_entry_get_bytecode(entry, @bytecode_len);
    if bytecode = nil then
      Continue;
    eval_flags := JS_READ_OBJ_BYTECODE or JS_READ_OBJ_REFERENCE;
    obj := JS_ReadObject(ctx, bytecode, QWord(bytecode_len), LongInt(eval_flags));
    if JS_IsException(obj) <> 0 then
      Exit(nil);
    if js_module_set_import_meta(ctx, obj, cbool(1), cbool(0)) < 0 then
    begin
      JS_FreeValue(ctx, obj);
      Exit(nil);
    end;
    m := PJSModuleDef(JSValuePtr(obj));
    JS_FreeValue(ctx, obj);
    Result := m;
    Exit;
  end;
end;

// Helper function to find QAR file in multiple locations
function FindQarFileForBuild(const qar_filename, base_dir: string): string;
var
  test_path: string;
begin
  Result := '';
  
  // 1. Exact path (if absolute or relative to current dir)
  if FileExists(qar_filename) then
  begin
    Result := ExpandFileName(qar_filename);
    Exit;
  end;
  
  // 2. Relative to base directory
  if base_dir <> '' then
  begin
    test_path := IncludeTrailingPathDelimiter(base_dir) + qar_filename;
    if FileExists(test_path) then
    begin
      Result := ExpandFileName(test_path);
      Exit;
    end;
  end;
  
  // 3. Current working directory
  test_path := IncludeTrailingPathDelimiter(GetCurrentDir) + qar_filename;
  if FileExists(test_path) then
  begin
    Result := ExpandFileName(test_path);
    Exit;
  end;
end;

// Check for circular dependencies in QAR files
// Note: This is a simplified check that only validates direct dependencies
// Full circular dependency detection would require parsing QAR files recursively
// For now, we just check if output QAR name appears in dependencies (self-reference)
function CheckCircularDependency(const output_file: string; const qar_files: TStringList): boolean;
var
  output_basename: string;
  i: integer;
begin
  Result := False;
  
  // Extract basename of output file (without path and extension)
  output_basename := ChangeFileExt(ExtractFileName(output_file), '');
  
  // Check if output QAR is in dependency list (self-reference)
  for i := 0 to qar_files.Count - 1 do
  begin
    if (LowerCase(ChangeFileExt(ExtractFileName(qar_files[i]), '')) = LowerCase(output_basename)) or
       (LowerCase(qar_files[i]) = LowerCase(output_file)) then
    begin
      WriteLn('Error: Circular dependency detected!');
      WriteLn('  Output QAR file "', output_file, '" references itself via "', qar_files[i], '"');
      Result := True;
      Exit;
    end;
  end;
  
  // Note: Full circular dependency detection (A -> B -> A) would require:
  // 1. Opening each QAR file
  // 2. Extracting JS source code
  // 3. Parsing LoadLibrary calls recursively
  // 4. Building dependency graph
  // 5. Detecting cycles using DFS
  // This is complex and may not be necessary for most use cases
end;

// Build QAR from files/directories
// entry_main / entry_init cho phép ghi thêm entry_points vào manifest (có thể rỗng).
function BuildQar(const output_file: string; const input_files: array of string;
  const entry_main: string = ''; const entry_init: string = '';
  const created_by: string = ''; const tool: string = ''; const meta: TStrings = nil;
  const sig_pubkey_b64: string = ''; const sig_b64: string = '';
  const sign_key_file: string = ''): cint;
var
  list: TQarEntryList;
  rt: PJSRuntime;
  ctx: PJSContext;
  i, j: integer;
  base_dir: string;
  qjs_version: string;
  entry: PQarBuildEntry;
  qar_files: TStringList;
  qar_file, found_qar: string;
  opaque: PBuildQarOpaque;
  built_at: string;
  signErr: string;
  km: TEd25519KeyMaterial;
  sig: TEd25519Signature;
  payload: UTF8String;
  payloadBytes: TBytes;
  payloadB64: string;
  sigPubB64: string;
  sigB64: string;
  sigOk: boolean;
  // Debug variables for QAR entries
  qar_debug: PQarFile;
  entry_count_debug, i_debug: cint;
  entry_debug: PQarEntry;
  entry_path_debug: PChar;
begin
  Result := -1;
  
  list := TQarEntryList.Create;
  qar_files := TStringList.Create;
  qar_files.Sorted := True;
  qar_files.Duplicates := dupIgnore;
  try
    // Initialize QuickJS
    rt := JS_NewRuntime;
    if rt = nil then
    begin
      WriteLn('Failed to create JS runtime');
      Exit;
    end;
    
    ctx := JS_NewContext(rt);
    if ctx = nil then
    begin
      WriteLn('Failed to create JS context');
      JS_FreeRuntime(rt);
      Exit;
    end;

    // Register builtin std/os modules so imports like 'qjs:os' resolve during compile
    js_init_module_std(ctx, 'std');
    js_init_module_std(ctx, 'qjs:std');
    js_init_module_os(ctx, 'os');
    js_init_module_os(ctx, 'qjs:os');
    js_init_module_zip(ctx, 'zip');
    js_init_module_zip(ctx, 'qjs:zip');
    js_init_module_bjson(ctx, 'bjson');
    js_init_module_bjson(ctx, 'qjs:bjson');
    
    // Set up module loader with fallback (required for QAR module resolution)
    // Use wrapper to handle path mismatches (e.g., import 'qar_test_lib/math.js' but QAR has 'math.js')
    New(opaque);
    SetLength(opaque^.qars, 0);
    JS_SetModuleLoaderFunc(rt, nil, @js_module_loader_build_wrapper, opaque);
    
    try
      // Collect files
      for i := 0 to Length(input_files) - 1 do
      begin
        // Determine base directory
        if DirectoryExists(input_files[i]) then
          base_dir := input_files[i]
        else
          base_dir := ExtractFileDir(input_files[i]);
        
        if base_dir = '' then
          base_dir := '.';
        
        AddFileToList(list, base_dir, input_files[i]);
      end;
      
      if list.Count = 0 then
      begin
        WriteLn('No JavaScript files found');
        Exit;
      end;
      
      // Parse all JS files to find LoadLibrary calls
      for i := 0 to list.Count - 1 do
      begin
        entry := list.GetEntry(i);
        if IsJSFile(entry^.filepath) then
          ParseLoadLibraryCalls(entry^.filepath, qar_files);
      end;
      
      // Check for circular dependencies (simplified - only checks self-reference)
      if CheckCircularDependency(output_file, qar_files) then
      begin
        WriteLn('Error: Circular dependency detected. Build aborted.');
        Exit;
      end;
      
      // Register QAR dependencies before compilation
      if qar_files.Count > 0 then
      begin
        WriteLn('Found ', qar_files.Count, ' QAR dependency(ies):');
        for i := 0 to qar_files.Count - 1 do
        begin
          qar_file := qar_files[i];
          WriteLn('  ', qar_file);
          
          // Find QAR file in multiple locations
          found_qar := '';
          for j := 0 to list.Count - 1 do
          begin
            entry := list.GetEntry(j);
            if DirectoryExists(entry^.filepath) then
              base_dir := entry^.filepath
            else
              base_dir := ExtractFileDir(entry^.filepath);
            if base_dir = '' then
              base_dir := '.';
            
            found_qar := FindQarFileForBuild(qar_file, base_dir);
            if found_qar <> '' then
              Break;
          end;
          
          if found_qar = '' then
            found_qar := FindQarFileForBuild(qar_file, GetCurrentDir);
          
          if found_qar <> '' then
          begin
            WriteLn('    -> Found at: ', found_qar);
            qar_debug := qar_open(PChar(found_qar));
            if qar_debug = nil then
            begin
              WriteLn('    -> Warning: Failed to open QAR file: ', found_qar);
            end
            else
            begin
              WriteLn('    -> Successfully loaded');
              j := Length(opaque^.qars);
              SetLength(opaque^.qars, j + 1);
              opaque^.qars[j] := qar_debug;

              entry_count_debug := qar_get_entry_count(qar_debug);
              WriteLn('    -> QAR file contains ', entry_count_debug, ' entries:');
              for i_debug := 0 to entry_count_debug - 1 do
              begin
                entry_debug := qar_get_entry(qar_debug, i_debug);
                if entry_debug <> nil then
                begin
                  entry_path_debug := qar_entry_get_path(entry_debug);
                  WriteLn('      Entry ', i_debug, ': "', entry_path_debug, '"');
                end;
              end;
            end;
          end
          else
          begin
            WriteLn('    -> Warning: QAR file not found: ', qar_file);
            WriteLn('       Module resolution may fail during compilation');
          end;
        end;
      end;
      
      // Compile all files
      WriteLn('Compiling ', list.Count, ' files...');
      for i := 0 to list.Count - 1 do
      begin
        entry := list.GetEntry(i);
        WriteLn('  ', entry^.path);
        if CompileAndAddEntry(ctx, entry) < 0 then
        begin
          WriteLn('Failed to compile ', entry^.filepath);
          Exit;
        end;

        // Compute per-entry hashes (bytecode + source/asset payload)
        // Assets are stored in source/source_len, with bytecode_len = 0
        if (entry^.is_asset <> 0) then
        begin
          entry^.sha256_source := Sha256HexPtr(entry^.source, entry^.source_len);
          entry^.sha256_bytecode := '';
        end
        else
        begin
          entry^.sha256_source := Sha256HexPtr(entry^.source, entry^.source_len);
          entry^.sha256_bytecode := Sha256HexPtr(entry^.bytecode, entry^.bytecode_len);
        end;
      end;
      
      built_at := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now);

      sigPubB64 := sig_pubkey_b64;
      sigB64 := sig_b64;
      if (sign_key_file <> '') and (sigPubB64 = '') and (sigB64 = '') then
      begin
        signErr := '';
        if not LoadEd25519KeyFromFile(sign_key_file, km, signErr) then
        begin
          WriteLn('Failed to load Ed25519 key: ', signErr);
          Exit;
        end;

        // Build the exact same payload as will be embedded in manifest
        payload := 'QAR-SIG-PAYLOAD\n';
        payload := payload + 'format=qar\n';
        payload := payload + 'manifest_version=2\n';
        payload := payload + 'quickjs_version=' + UTF8String(qjs_version) + '\n';
        payload := payload + 'built_at=' + UTF8String(built_at) + '\n';
        payload := payload + 'created_by=' + UTF8String(created_by) + '\n';
        payload := payload + 'tool=' + UTF8String(tool) + '\n';
        if (meta <> nil) and (meta.Count > 0) then
        begin
          for j := 0 to meta.Count - 1 do
            if meta.Names[j] <> '' then
              payload := payload + 'meta.' + UTF8String(meta.Names[j]) + '=' + UTF8String(meta.ValueFromIndex[j]) + '\n';
        end;
        payload := payload + 'entries=' + UTF8String(IntToStr(list.Count)) + '\n';
        for j := 0 to list.Count - 1 do
        begin
          entry := list.GetEntry(j);
          payload := payload + 'entry.path=' + UTF8String(entry^.path) + '\n';
          if entry^.is_asset <> 0 then
            payload := payload + 'entry.type=asset\n'
          else if entry^.is_module <> 0 then
            payload := payload + 'entry.type=module\n'
          else
            payload := payload + 'entry.type=script\n';
          payload := payload + 'entry.sha256_source=' + UTF8String(entry^.sha256_source) + '\n';
          payload := payload + 'entry.sha256_bytecode=' + UTF8String(entry^.sha256_bytecode) + '\n';
        end;

        SetLength(payloadBytes, Length(payload));
        if Length(payloadBytes) > 0 then
          Move(payload[1], payloadBytes[0], Length(payloadBytes));
        payloadB64 := Base64Encode(payloadBytes);

        sigOk := Ed25519Sign(payloadBytes, km.seed, km.pubkey, sig);
        if not sigOk then
        begin
          WriteLn('Failed to sign Ed25519 payload');
          Exit;
        end;

        SetLength(payloadBytes, 32);
        Move(km.pubkey[0], payloadBytes[0], 32);
        sigPubB64 := Base64Encode(payloadBytes);

        SetLength(payloadBytes, 64);
        Move(sig[0], payloadBytes[0], 64);
        sigB64 := Base64Encode(payloadBytes);
      end;

      // Create QAR file
      WriteLn('Creating QAR file: ', output_file);
      qjs_version := string(JS_GetVersion);
      // Truyền thêm entry_main / entry_init vào manifest
      if CreateQar(output_file, list, qjs_version, entry_main, entry_init, created_by, tool, meta, built_at, sigPubB64, sigB64) < 0 then
      begin
        WriteLn('Failed to create QAR file');
        Exit;
      end;
      
      WriteLn('Done! Created ', output_file, ' with ', list.Count, ' entries');
      
      // Free bytecode (allocated by JS_WriteObject)
      for i := 0 to list.Count - 1 do
      begin
        entry := list.GetEntry(i);
        if entry^.bytecode <> nil then
          js_free_rt(rt, entry^.bytecode);
      end;
      
      Result := 0;
    finally
      JS_FreeContext(ctx);
      JS_FreeRuntime(rt);
    end;
  finally
    if Assigned(opaque) then
    begin
      for i := 0 to High(opaque^.qars) do
        if opaque^.qars[i] <> nil then
          qar_close(opaque^.qars[i]);
      Dispose(opaque);
    end;
    qar_files.Free;
    list.Free;
  end;
end;

// Get QAR version string
function GetQarVersion: string;
begin
  Result := QAR_VERSION_STRING;
end;

// Get QuickJS version string
function GetQuickJsVersion: string;
var
  rt: PJSRuntime;
begin
  Result := 'Unknown';
  rt := JS_NewRuntime;
  if rt <> nil then
  begin
    try
      Result := string(JS_GetVersion);
    finally
      JS_FreeRuntime(rt);
    end;
  end;
end;

// Get QAR information as string
function GetQarInfoString(init_default_lib: boolean = False): string;
var
  rt: PJSRuntime;
  ctx: PJSContext;
  qjs_version: string;
begin
  Result := '';
  
  // QAR Version
  Result := Result + 'QAR Version: ' + QAR_VERSION_STRING + LineEnding;
  Result := Result + 'QAR Format Version: ' + IntToStr(QAR_FORMAT_VERSION) + LineEnding;
  Result := Result + LineEnding;
  
  // QuickJS Version
  if init_default_lib then
  begin
    rt := JS_NewRuntime;
    if rt <> nil then
    begin
      try
        ctx := JS_NewContext(rt);
        if ctx <> nil then
        begin
          try
            qjs_version := string(JS_GetVersion);
            Result := Result + 'QuickJS Version: ' + qjs_version + LineEnding;
            Result := Result + 'QuickJS Runtime: Initialized' + LineEnding;
            Result := Result + 'QuickJS Context: Initialized' + LineEnding;
          finally
            JS_FreeContext(ctx);
          end;
        end
        else
        begin
          qjs_version := string(JS_GetVersion);
          Result := Result + 'QuickJS Version: ' + qjs_version + LineEnding;
          Result := Result + 'QuickJS Runtime: Initialized' + LineEnding;
          Result := Result + 'QuickJS Context: Failed to initialize' + LineEnding;
        end;
      finally
        JS_FreeRuntime(rt);
      end;
    end
    else
    begin
      qjs_version := GetQuickJsVersion;
      Result := Result + 'QuickJS Version: ' + qjs_version + LineEnding;
      Result := Result + 'QuickJS Runtime: Failed to initialize' + LineEnding;
    end;
  end
  else
  begin
    qjs_version := GetQuickJsVersion;
    Result := Result + 'QuickJS Version: ' + qjs_version + LineEnding;
    Result := Result + 'QuickJS Runtime: Not initialized' + LineEnding;
  end;
  
  Result := Result + LineEnding;
  
  // Library Information
  Result := Result + 'Library Information:' + LineEnding;
  {$IFDEF WINDOWS}
  Result := Result + '  Platform: Windows' + LineEnding;
  Result := Result + '  Library: ' + libqjs + LineEnding;
  {$ELSE}
  Result := Result + '  Platform: Linux/Unix' + LineEnding;
  Result := Result + '  Library: ' + libqjs + LineEnding;
  {$ENDIF}
  Result := Result + LineEnding;
  
  // Features
  Result := Result + 'Features:' + LineEnding;
  Result := Result + '  - JavaScript bytecode compilation' + LineEnding;
  Result := Result + '  - ES Module support' + LineEnding;
  Result := Result + '  - Data compression (miniz)' + LineEnding;
  Result := Result + '  - QAR dependency resolution' + LineEnding;
  Result := Result + '  - Cross-platform support' + LineEnding;
end;

// Print QAR information
procedure PrintQarInfo(init_default_lib: boolean = False);
begin
  Write(GetQarInfoString(init_default_lib));
end;

// Parse source code to find LoadLibrary and LoadDynamicLibrary calls
procedure ParseLoadLibraryFromSource(const source: Pcuint8; source_len: csize_t; var dependencies: TStringList);
var
  source_str: string;
  lines: TStringList;
  i: integer;
  line: string;
  pos_load, pos_start, pos_end: integer;
  lib_file: string;
  quote_char: char;
begin
  if (source = nil) or (source_len = 0) then
    Exit;
  
  SetString(source_str, PChar(source), source_len);
  lines := TStringList.Create;
  try
    lines.Text := source_str;
    
    for i := 0 to lines.Count - 1 do
    begin
      line := lines[i];
      
      // Look for LoadLibrary('...') or LoadLibrary("...")
      pos_load := Pos('LoadLibrary', line);
      if pos_load > 0 then
      begin
        // Find opening parenthesis
        pos_start := pos_load;
        while (pos_start <= Length(line)) and (line[pos_start] <> '(') do
          Inc(pos_start);
        
        if pos_start <= Length(line) then
        begin
          Inc(pos_start); // Skip '('
          // Skip whitespace
          while (pos_start <= Length(line)) and (line[pos_start] in [' ', #9]) do
            Inc(pos_start);
          
          // Check for string literal
          if (pos_start <= Length(line)) and (line[pos_start] in ['''', '"']) then
          begin
            quote_char := line[pos_start];
            Inc(pos_start); // Skip opening quote
            pos_end := pos_start;
            
            // Find closing quote
            while (pos_end <= Length(line)) and (line[pos_end] <> quote_char) do
            begin
              // Handle escaped quotes
              if (line[pos_end] = '\') and (pos_end < Length(line)) then
                Inc(pos_end);
              Inc(pos_end);
            end;
            
            if pos_end <= Length(line) then
            begin
              lib_file := Copy(line, pos_start, pos_end - pos_start);
              // Remove escape sequences
              lib_file := StringReplace(lib_file, '\''', '''', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\"', '"', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\\', '\', [rfReplaceAll]);
              
              if (lib_file <> '') and (dependencies.IndexOf(lib_file) < 0) then
                dependencies.Add(lib_file);
            end;
          end;
        end;
      end;
      
      // Look for LoadDynamicLibrary('...') or LoadDynamicLibrary("...")
      pos_load := Pos('LoadDynamicLibrary', line);
      if pos_load > 0 then
      begin
        // Find opening parenthesis
        pos_start := pos_load;
        while (pos_start <= Length(line)) and (line[pos_start] <> '(') do
          Inc(pos_start);
        
        if pos_start <= Length(line) then
        begin
          Inc(pos_start); // Skip '('
          // Skip whitespace
          while (pos_start <= Length(line)) and (line[pos_start] in [' ', #9]) do
            Inc(pos_start);
          
          // Check for string literal
          if (pos_start <= Length(line)) and (line[pos_start] in ['''', '"']) then
          begin
            quote_char := line[pos_start];
            Inc(pos_start); // Skip opening quote
            pos_end := pos_start;
            
            // Find closing quote
            while (pos_end <= Length(line)) and (line[pos_end] <> quote_char) do
            begin
              // Handle escaped quotes
              if (line[pos_end] = '\') and (pos_end < Length(line)) then
                Inc(pos_end);
              Inc(pos_end);
            end;
            
            if pos_end <= Length(line) then
            begin
              lib_file := Copy(line, pos_start, pos_end - pos_start);
              // Remove escape sequences
              lib_file := StringReplace(lib_file, '\''', '''', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\"', '"', [rfReplaceAll]);
              lib_file := StringReplace(lib_file, '\\', '\', [rfReplaceAll]);
              
              // Add to dependencies if it's a dynamic library file
              if (lib_file <> '') and IsDynamicLibraryFile(lib_file) and (dependencies.IndexOf(lib_file) < 0) then
                dependencies.Add(lib_file);
            end;
          end;
        end;
      end;
    end;
  finally
    lines.Free;
  end;
end;

// Check if QuickJS versions are compatible
function CheckQuickJsCompatibility(const qar_version, current_version: string): boolean;
begin
  // Simple compatibility check: if versions match exactly, they're compatible
  // For more sophisticated checking, we could parse version numbers
  Result := (qar_version = current_version);
end;

// Read entry flags from QAR file binary (to check compression status)
// This reads directly from the file since there's no API to get flags
function ReadEntryFlagsFromQarFile(const qar_filename: string; entry_index: integer; var is_compressed: boolean; 
                                   var compressed_bytecode_size, compressed_source_size: uint64;
                                   var is_asset: boolean;
                                   var bytecode_orig_size, source_orig_size: uint64): boolean;
var
  f: File;
  magic: array[0..3] of char;
  version: uint32;
  manifest_offset, manifest_size: uint64;
  entry_count: uint32;
  i: integer;
  path_len: uint32;
  path_str: string;
  flags: uint32;
  bytecode_size, source_size: uint64;
  bytecode_orig_size_local, source_orig_size_local: uint64;
begin
  Result := False;
  is_compressed := False;
  compressed_bytecode_size := 0;
  compressed_source_size := 0;
  
  if not FileExists(qar_filename) then
    Exit;
  
  AssignFile(f, qar_filename);
  try
    Reset(f, 1); // Binary mode
  except
    Exit;
  end;
  
  try
    // Read magic
    BlockRead(f, magic, 4);
    if (magic[0] <> 'Q') or (magic[1] <> 'A') or (magic[2] <> 'R') then
      Exit;
    
    // Read version
    BlockRead(f, version, 4);
    
    // Read manifest offset and size
    BlockRead(f, manifest_offset, 8);
    BlockRead(f, manifest_size, 8);
    
    // Read entry count
    BlockRead(f, entry_count, 4);
    
    if entry_index >= entry_count then
      Exit;
    
    // Skip to the requested entry
    for i := 0 to entry_index - 1 do
    begin
      // Read path length
      BlockRead(f, path_len, 4);
      // Skip path
      SetLength(path_str, path_len);
      if path_len > 0 then
        BlockRead(f, path_str[1], path_len);
      
      // Read flags
      BlockRead(f, flags, 4);
      
      // Read sizes
      BlockRead(f, bytecode_size, 8);
      BlockRead(f, source_size, 8);
      
      // If compressed, read original sizes
      if (flags and 2) <> 0 then
      begin
        BlockRead(f, bytecode_orig_size, 8);
        BlockRead(f, source_orig_size, 8);
      end;
      
      // Skip data
      Seek(f, FilePos(f) + int64(bytecode_size) + int64(source_size));
    end;
    
    // Now read the requested entry's flags
    // Read path length (skip it)
    BlockRead(f, path_len, 4);
    SetLength(path_str, path_len);
    if path_len > 0 then
      BlockRead(f, path_str[1], path_len);
    
    // Read flags
    BlockRead(f, flags, 4);
    is_compressed := (flags and 2) <> 0;
    is_asset := (flags and 4) <> 0;
    
    // Read sizes
    BlockRead(f, bytecode_size, 8);
    BlockRead(f, source_size, 8);
    
    if is_compressed then
    begin
      compressed_bytecode_size := bytecode_size;
      compressed_source_size := source_size;
      // Read original sizes
      BlockRead(f, bytecode_orig_size_local, 8);
      BlockRead(f, source_orig_size_local, 8);
    end
    else
    begin
      compressed_bytecode_size := bytecode_size;
      compressed_source_size := source_size;
      bytecode_orig_size_local := bytecode_size;
      source_orig_size_local := source_size;
    end;
    
    // Output original sizes
    bytecode_orig_size := bytecode_orig_size_local;
    source_orig_size := source_orig_size_local;
    
    Result := True;
  finally
    CloseFile(f);
  end;
end;

// Inspect QAR file and return detailed information
function InspectQarFile(const qar_filename: string): TQarInspectionResult;
var
  qar: PQarFile;
  entry_count, i: cint;
  entry: PQarEntry;
  entry_path: PChar;
  entry_type: cint;
  manifest: PChar;
  manifest_len: csize_t;
  version: PChar;
  bytecode_len, source_len: csize_t;
  source: Pcuint8;
  current_qjs_version: string;
  is_compressed: boolean;
  compressed_bytecode_size, compressed_source_size: uint64;
  is_asset_flag: boolean;
  bytecode_orig_size, source_orig_size: uint64;
begin
  // Initialize result
  Result.qar_file := qar_filename;
  Result.qar_format_version := 0;
  Result.qar_version := '';
  Result.quickjs_version := '';
  Result.entry_count := 0;
  SetLength(Result.entries, 0);
  Result.dependencies := TStringList.Create;
  Result.dependencies.Sorted := True;
  Result.dependencies.Duplicates := dupIgnore;
  Result.is_compatible := False;
  Result.compatibility_message := '';
  Result.has_compressed_entries := False;
  
  if not FileExists(qar_filename) then
  begin
    Result.compatibility_message := 'QAR file not found: ' + qar_filename;
    Exit;
  end;
  
  qar := qar_open(PChar(qar_filename));
  if qar = nil then
  begin
    Result.compatibility_message := 'Failed to open QAR file';
    Exit;
  end;
  
  try
    // Get entry count
    entry_count := qar_get_entry_count(qar);
    Result.entry_count := entry_count;
    SetLength(Result.entries, entry_count);
    
    // Get QuickJS version from QAR
    version := qar_get_quickjs_version(qar);
    if version <> nil then
      Result.quickjs_version := string(version);
    
    // Get manifest
    manifest := qar_get_manifest(qar, @manifest_len);
    if manifest <> nil then
    begin
      // Parse manifest to get format version (simple parsing)
      // Look for "version": number in JSON
      // This is a simple parser - for production, use a proper JSON parser
      Result.qar_format_version := QAR_FORMAT_VERSION; // Default
      // Try to extract version from manifest string
      // Format: "version": 1
      // We'll use a simple search for now
    end
    else
    begin
      Result.qar_format_version := QAR_FORMAT_VERSION; // Default if no manifest
    end;
    
    // Get current QuickJS version
    current_qjs_version := GetQuickJsVersion;
    
    // Check compatibility
    if Result.quickjs_version <> '' then
    begin
      Result.is_compatible := CheckQuickJsCompatibility(Result.quickjs_version, current_qjs_version);
      if Result.is_compatible then
        Result.compatibility_message := 'Compatible with current QuickJS version (' + current_qjs_version + ')'
      else
        Result.compatibility_message := 'QAR built with QuickJS ' + Result.quickjs_version + 
                                      ', current version is ' + current_qjs_version + ' (may be incompatible)';
    end
    else
    begin
      Result.compatibility_message := 'QuickJS version information not available in QAR';
    end;
    
    // Process each entry
    for i := 0 to entry_count - 1 do
    begin
      entry := qar_get_entry(qar, i);
      if entry <> nil then
      begin
        entry_path := qar_entry_get_path(entry);
        entry_type := qar_entry_get_type(entry);
        
        Result.entries[i].path := string(entry_path);
        if entry_type = 2 then
          Result.entries[i].entry_type := 'asset'
        else if entry_type <> 0 then
          Result.entries[i].entry_type := 'module'
        else
          Result.entries[i].entry_type := 'script';
        
        // Read compression status from file
        is_compressed := False;
        compressed_bytecode_size := 0;
        compressed_source_size := 0;
        is_asset_flag := False;
        bytecode_orig_size := 0;
        source_orig_size := 0;
        if ReadEntryFlagsFromQarFile(qar_filename, i, is_compressed, compressed_bytecode_size, compressed_source_size,
                                     is_asset_flag, bytecode_orig_size, source_orig_size) then
        begin
          Result.entries[i].is_compressed := is_compressed;
          Result.entries[i].compressed_bytecode_size := compressed_bytecode_size;
          Result.entries[i].compressed_source_size := compressed_source_size;
          if is_compressed then
            Result.has_compressed_entries := True;
        end
        else
        begin
          Result.entries[i].is_compressed := False;
          Result.entries[i].compressed_bytecode_size := 0;
          Result.entries[i].compressed_source_size := 0;
        end;
        
        // Load entry data to get sizes (uncompressed)
        if qar_entry_load_data(qar, entry) = 0 then
        begin
          bytecode_len := 0;
          source_len := 0;
          
          if qar_entry_get_bytecode(entry, @bytecode_len) <> nil then
            Result.entries[i].bytecode_size := bytecode_len;
          
          source := qar_entry_get_source(entry, @source_len);
          if (entry_type <> 2) and (source <> nil) then
          begin
            Result.entries[i].source_size := source_len;
            
            // Parse source for LoadLibrary calls
            ParseLoadLibraryFromSource(source, source_len, Result.dependencies);
          end
          else if source <> nil then
          begin
            // Asset: record source_size but skip parsing
            Result.entries[i].source_size := source_len;
          end;
        end;
      end;
    end;
  finally
    qar_close(qar);
  end;
end;

// Print QAR inspection results
procedure PrintQarInspectionFiltered(const result: TQarInspectionResult; const prefix: string);
var
  i: integer;
  shown_count: integer;
  pfx: string;
  has_compressed: boolean;
begin
  WriteLn('=== QAR File Inspection ===');
  WriteLn('File: ', result.qar_file);
  WriteLn;
  
  WriteLn('Version Information:');
  WriteLn('  QAR Format Version: ', result.qar_format_version);
  WriteLn('  QAR Version: ', result.qar_version);
  WriteLn('  QuickJS Version: ', result.quickjs_version);
  WriteLn('  Compatibility: ', result.compatibility_message);
  WriteLn;
  
  pfx := prefix;
  pfx := StringReplace(pfx, '\\', '/', [rfReplaceAll]);
  shown_count := 0;
  has_compressed := False;
  for i := 0 to result.entry_count - 1 do
  begin
    if (pfx <> '') and (Copy(result.entries[i].path, 1, Length(pfx)) <> pfx) then
      Continue;
    Inc(shown_count);
    if result.entries[i].is_compressed then
      has_compressed := True;
  end;

  WriteLn('Compression Status:');
  if has_compressed then
    WriteLn('  QAR contains compressed entries')
  else
    WriteLn('  QAR entries are not compressed');
  WriteLn;
  
  WriteLn('Entries (', shown_count, '):');
  shown_count := 0;
  for i := 0 to result.entry_count - 1 do
  begin
    if (pfx <> '') and (Copy(result.entries[i].path, 1, Length(pfx)) <> pfx) then
      Continue;
    Inc(shown_count);

    WriteLn('  [', shown_count, '] ', result.entries[i].path);
    WriteLn('      Type: ', result.entries[i].entry_type);
    if result.entries[i].is_compressed then
    begin
      WriteLn('      Compression: Yes');
      WriteLn('      Bytecode: ', result.entries[i].compressed_bytecode_size, ' bytes (compressed) -> ', 
                result.entries[i].bytecode_size, ' bytes (uncompressed)');
      WriteLn('      Source: ', result.entries[i].compressed_source_size, ' bytes (compressed) -> ', 
                result.entries[i].source_size, ' bytes (uncompressed)');
    end
    else
    begin
      WriteLn('      Compression: No');
      WriteLn('      Bytecode Size: ', result.entries[i].bytecode_size, ' bytes');
      WriteLn('      Source Size: ', result.entries[i].source_size, ' bytes');
    end;
  end;
  WriteLn;
  
  if result.dependencies.Count > 0 then
  begin
    WriteLn('Dependencies (', result.dependencies.Count, ' files):');
    for i := 0 to result.dependencies.Count - 1 do
    begin
      if IsDynamicLibraryFile(result.dependencies[i]) then
        WriteLn('  - ', result.dependencies[i], ' (dynamic library)')
      else
        WriteLn('  - ', result.dependencies[i], ' (QAR file)');
    end;
  end
  else
  begin
    WriteLn('Dependencies: None');
  end;
  WriteLn;
end;

procedure PrintQarInspection(const result: TQarInspectionResult);
begin
  PrintQarInspectionFiltered(result, '');
end;

// Rebuild QAR file to match current QuickJS version.
// entry_main / entry_init: nếu khác rỗng thì sẽ được ghi vào manifest mới.
// Nếu rỗng, caller có thể sau này mở rộng để giữ nguyên từ manifest cũ (hiện tại: không đọc lại manifest).
function RebuildQarFile(const input_qar: string; const output_qar: string;
  const entry_main: string; const entry_init: string;
  const sign_key_file: string): cint;
var
  inspection: TQarInspectionResult;
  input_files: array of string;
  i: integer;
  temp_dir: string;
  source: Pcuint8;
  source_len: csize_t;
  source_str: string;
  qar: PQarFile;
  entry: PQarEntry;
  temp_file: string;
  f: TextFile;
begin
  Result := -1;
  
  // Inspect input QAR
  inspection := InspectQarFile(input_qar);
  if inspection.entry_count = 0 then
  begin
    WriteLn('Error: Cannot rebuild - QAR file has no entries or cannot be read');
    inspection.dependencies.Free;
    Exit;
  end;
  
  // Create temporary directory for extracted sources
  temp_dir := GetTempDir + 'qar_rebuild_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + PathDelim;
  if not ForceDirectories(temp_dir) then
  begin
    WriteLn('Error: Cannot create temporary directory');
    inspection.dependencies.Free;
    Exit;
  end;
  
  try
    // Open QAR and extract source files
    qar := qar_open(PChar(input_qar));
    if qar = nil then
    begin
      WriteLn('Error: Cannot open input QAR file');
      inspection.dependencies.Free;
      Exit;
    end;
    
    try
      SetLength(input_files, inspection.entry_count);
      
      // Extract each entry's source to temporary files
      for i := 0 to inspection.entry_count - 1 do
      begin
        entry := qar_find_entry(qar, PChar(inspection.entries[i].path));
        if entry <> nil then
        begin
          if qar_entry_load_data(qar, entry) = 0 then
          begin
            source := qar_entry_get_source(entry, @source_len);
            if source <> nil then
            begin
              // Create temp file with same path structure
              temp_file := temp_dir + inspection.entries[i].path;
              ForceDirectories(ExtractFileDir(temp_file));
              
              // Write source to file
              SetString(source_str, PChar(source), source_len);
              AssignFile(f, temp_file);
              try
                Rewrite(f);
                Write(f, source_str);
              finally
                CloseFile(f);
              end;
              
              input_files[i] := temp_file;
            end;
          end;
        end;
      end;
    finally
      qar_close(qar);
    end;
    
    // Build new QAR with current QuickJS version
    WriteLn('Rebuilding QAR file with current QuickJS version...');
    // Ghi thêm entry_points nếu caller cung cấp
    Result := BuildQar(output_qar, input_files, entry_main, entry_init, '', '', nil, '', '', sign_key_file);
    
    if Result = 0 then
      WriteLn('Successfully rebuilt QAR file: ', output_qar)
    else
      WriteLn('Error: Failed to rebuild QAR file');
      
  finally
    // Clean up temporary files
    for i := 0 to Length(input_files) - 1 do
    begin
      if FileExists(input_files[i]) then
        DeleteFile(input_files[i]);
    end;
    // Remove temp directory (simplified - in production, use recursive delete)
    inspection.dependencies.Free;
  end;
end;

end.

