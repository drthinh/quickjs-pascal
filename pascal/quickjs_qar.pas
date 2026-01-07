unit quickjs_qar;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, quickjs_types;

const
  {$IFDEF WINDOWS}
  libqjs = 'libqjs.dll';
  {$ELSE}
  libqjs = 'libqjs.so';
  {$ENDIF}

type
  QarFile = record end;
  PQarFile = ^QarFile;
  QarEntry = record end;
  PQarEntry = ^QarEntry;

// QAR reading API (qar.h)
function qar_open(filename: PChar): PQarFile; cdecl; external libqjs;
procedure qar_close(qar: PQarFile); cdecl; external libqjs;
function qar_get_entry_count(qar: PQarFile): cint; cdecl; external libqjs;
function qar_get_entry(qar: PQarFile; index: cint): PQarEntry; cdecl; external libqjs;
function qar_find_entry(qar: PQarFile; path: PChar): PQarEntry; cdecl; external libqjs;
function qar_entry_get_path(entry: PQarEntry): PChar; cdecl; external libqjs;
function qar_entry_get_type(entry: PQarEntry): cint; cdecl; external libqjs;
function qar_entry_get_bytecode(entry: PQarEntry; len: Pcsize_t): Pcuint8; cdecl; external libqjs;
function qar_entry_get_source(entry: PQarEntry; len: Pcsize_t): Pcuint8; cdecl; external libqjs;
function qar_entry_load_data(qar: PQarFile; entry: PQarEntry): cint; cdecl; external libqjs;
function qar_get_manifest(qar: PQarFile; len: Pcsize_t): PChar; cdecl; external libqjs;
function qar_get_quickjs_version(qar: PQarFile): PChar; cdecl; external libqjs;

implementation

end.



