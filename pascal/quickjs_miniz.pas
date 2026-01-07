unit quickjs_miniz;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes;

const
  {$IFDEF WINDOWS}
  libqjs = 'libqjs.dll';
  {$ELSE}
  libqjs = 'libqjs.so';
  {$ENDIF}

  // Status codes
  MZ_OK = 0;
  MZ_STREAM_END = 1;
  MZ_NEED_DICT = 2;
  MZ_ERRNO = -1;
  MZ_STREAM_ERROR = -2;
  MZ_DATA_ERROR = -3;
  MZ_MEM_ERROR = -4;
  MZ_BUF_ERROR = -5;
  MZ_VERSION_ERROR = -6;
  MZ_DEFAULT_LEVEL = 6;
  MZ_DEFAULT_WINDOW_BITS = 15;
  MZ_DEFLATED = 8;

type
  mz_ulong = cuint32;
  Pmz_ulong = ^mz_ulong;
  Pcuint8 = ^cuint8;

// Simple compression API (exported by libqjs.dll)
function mz_compress(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong): cint; cdecl; external libqjs;
function mz_compress2(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong; level: cint): cint; cdecl; external libqjs;
function mz_compressBound(source_len: mz_ulong): mz_ulong; cdecl; external libqjs;
function mz_uncompress(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong): cint; cdecl; external libqjs;
function mz_uncompress2(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; pSource_len: Pmz_ulong): cint; cdecl; external libqjs;

implementation

end.


