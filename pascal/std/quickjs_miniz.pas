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
  mz_uint = cuint32;
  Pmz_zip_error = ^cint;

  mz_uint8 = cuint8;
  mz_uint16 = cuint16;
  mz_uint32 = cuint32;
  mz_uint64 = cuint64;
  mz_bool = cint;

  Pmz_uint32 = ^mz_uint32;
  Ppointer = ^pointer;

  Pmz_zip_archive = ^mz_zip_archive;
  Pmz_zip_archive_file_stat = ^mz_zip_archive_file_stat;

  MZ_FILE = pointer;

  Tmz_file_write_func = function(pOpaque: pointer; file_ofs: mz_uint64; pBuf: pointer; n: csize_t): csize_t; cdecl;
  Tmz_file_read_func = function(pOpaque: pointer; file_ofs: mz_uint64; pBuf: pointer; n: csize_t): csize_t; cdecl;
  Tmz_file_needs_keepalive = function(pOpaque: pointer): mz_bool; cdecl;

  Pmz_zip_internal_state = pointer;

  Tmz_alloc_func = function(opaque: pointer; items: csize_t; size: csize_t): pointer; cdecl;
  Tmz_free_func = procedure(opaque: pointer; address: pointer); cdecl;
  Tmz_realloc_func = function(opaque: pointer; address: pointer; items: csize_t; size: csize_t): pointer; cdecl;

  {$IFDEF CPU64}
  MZ_TIME_T = cint64;
  {$ELSE}
  MZ_TIME_T = clong;
  {$ENDIF}

  PMZ_TIME_T = ^MZ_TIME_T;

  mz_zip_archive_file_stat = packed record
    m_file_index: mz_uint32;
    m_central_dir_ofs: mz_uint64;
    m_version_made_by: mz_uint16;
    m_version_needed: mz_uint16;
    m_bit_flag: mz_uint16;
    m_method: mz_uint16;
    m_crc32: mz_uint32;
    m_comp_size: mz_uint64;
    m_uncomp_size: mz_uint64;
    m_internal_attr: mz_uint16;
    m_external_attr: mz_uint32;
    m_local_header_ofs: mz_uint64;
    m_comment_size: mz_uint32;
    m_is_directory: mz_bool;
    m_is_encrypted: mz_bool;
    m_is_supported: mz_bool;
    m_filename: array[0..511] of char;
    m_comment: array[0..511] of char;
    m_time: MZ_TIME_T;
  end;

  mz_zip_archive = packed record
    m_archive_size: mz_uint64;
    m_central_directory_file_ofs: mz_uint64;
    m_total_files: mz_uint32;
    m_zip_mode: cint;
    m_zip_type: cint;
    m_last_error: cint;
    m_file_offset_alignment: mz_uint64;
    m_pAlloc: Tmz_alloc_func;
    m_pFree: Tmz_free_func;
    m_pRealloc: Tmz_realloc_func;
    m_pAlloc_opaque: pointer;
    m_pRead: Tmz_file_read_func;
    m_pWrite: Tmz_file_write_func;
    m_pNeeds_keepalive: Tmz_file_needs_keepalive;
    m_pIO_opaque: pointer;
    m_pState: Pmz_zip_internal_state;
  end;

// Simple compression API (exported by libqjs.dll)
function mz_compress(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong): cint; cdecl; external libqjs;
function mz_compress2(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong; level: cint): cint; cdecl; external libqjs;
function mz_compressBound(source_len: mz_ulong): mz_ulong; cdecl; external libqjs;
function mz_uncompress(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; source_len: mz_ulong): cint; cdecl; external libqjs;
function mz_uncompress2(pDest: Pcuint8; pDest_len: Pmz_ulong; pSource: Pcuint8; pSource_len: Pmz_ulong): cint; cdecl; external libqjs;

// Memory free helper from miniz
procedure mz_free(p: pointer); cdecl; external libqjs;

// ZIP simple APIs (only available if libqjs is built/exported with miniz_zip)
function mz_zip_extract_archive_file_to_heap(pZip_filename: PChar; pArchive_name: PChar; pSize: Pcsize_t; flags: mz_uint): pointer; cdecl; external libqjs;
function mz_zip_extract_archive_file_to_heap_v2(pZip_filename: PChar; pArchive_name: PChar; pComment: PChar; pSize: Pcsize_t; flags: mz_uint; pErr: Pmz_zip_error): pointer; cdecl; external libqjs;

procedure mz_zip_zero_struct(pZip: Pmz_zip_archive); cdecl; external libqjs;
function mz_zip_get_mode(pZip: Pmz_zip_archive): cint; cdecl; external libqjs;
function mz_zip_get_type(pZip: Pmz_zip_archive): cint; cdecl; external libqjs;
function mz_zip_reader_get_num_files(pZip: Pmz_zip_archive): mz_uint; cdecl; external libqjs;
function mz_zip_get_archive_size(pZip: Pmz_zip_archive): mz_uint64; cdecl; external libqjs;
function mz_zip_get_archive_file_start_offset(pZip: Pmz_zip_archive): mz_uint64; cdecl; external libqjs;
function mz_zip_get_cfile(pZip: Pmz_zip_archive): MZ_FILE; cdecl; external libqjs;
function mz_zip_read_archive_data(pZip: Pmz_zip_archive; file_ofs: mz_uint64; pBuf: pointer; n: csize_t): csize_t; cdecl; external libqjs;
function mz_zip_set_last_error(pZip: Pmz_zip_archive; err_num: cint): cint; cdecl; external libqjs;
function mz_zip_peek_last_error(pZip: Pmz_zip_archive): cint; cdecl; external libqjs;
function mz_zip_clear_last_error(pZip: Pmz_zip_archive): cint; cdecl; external libqjs;
function mz_zip_get_last_error(pZip: Pmz_zip_archive): cint; cdecl; external libqjs;
function mz_zip_get_error_string(mz_err: cint): PChar; cdecl; external libqjs;

function mz_zip_reader_init(pZip: Pmz_zip_archive; size: mz_uint64; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_init_mem(pZip: Pmz_zip_archive; pMem: pointer; size: csize_t; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_init_file(pZip: Pmz_zip_archive; pFilename: PChar; flags: mz_uint32): mz_bool; cdecl; external libqjs;
function mz_zip_reader_init_file_v2(pZip: Pmz_zip_archive; pFilename: PChar; flags: mz_uint; file_start_ofs: mz_uint64; archive_size: mz_uint64): mz_bool; cdecl; external libqjs;
function mz_zip_reader_init_cfile(pZip: Pmz_zip_archive; pFile: MZ_FILE; archive_size: mz_uint64; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_end(pZip: Pmz_zip_archive): mz_bool; cdecl; external libqjs;

function mz_zip_reader_is_file_a_directory(pZip: Pmz_zip_archive; file_index: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_is_file_encrypted(pZip: Pmz_zip_archive; file_index: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_is_file_supported(pZip: Pmz_zip_archive; file_index: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_get_filename(pZip: Pmz_zip_archive; file_index: mz_uint; pFilename: PChar; filename_buf_size: mz_uint): mz_uint; cdecl; external libqjs;
function mz_zip_reader_locate_file(pZip: Pmz_zip_archive; pName: PChar; pComment: PChar; flags: mz_uint): cint; cdecl; external libqjs;
function mz_zip_reader_locate_file_v2(pZip: Pmz_zip_archive; pName: PChar; pComment: PChar; flags: mz_uint; file_index: Pmz_uint32): mz_bool; cdecl; external libqjs;
function mz_zip_reader_file_stat(pZip: Pmz_zip_archive; file_index: mz_uint; pStat: Pmz_zip_archive_file_stat): mz_bool; cdecl; external libqjs;
function mz_zip_is_zip64(pZip: Pmz_zip_archive): mz_bool; cdecl; external libqjs;
function mz_zip_get_central_dir_size(pZip: Pmz_zip_archive): csize_t; cdecl; external libqjs;

function mz_zip_reader_extract_to_mem_no_alloc(pZip: Pmz_zip_archive; file_index: mz_uint; pBuf: pointer; buf_size: csize_t; flags: mz_uint; pUser_read_buf: pointer; user_read_buf_size: csize_t): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_file_to_mem_no_alloc(pZip: Pmz_zip_archive; pFilename: PChar; pBuf: pointer; buf_size: csize_t; flags: mz_uint; pUser_read_buf: pointer; user_read_buf_size: csize_t): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_to_mem(pZip: Pmz_zip_archive; file_index: mz_uint; pBuf: pointer; buf_size: csize_t; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_file_to_mem(pZip: Pmz_zip_archive; pFilename: PChar; pBuf: pointer; buf_size: csize_t; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_to_heap(pZip: Pmz_zip_archive; file_index: mz_uint; pSize: Pcsize_t; flags: mz_uint): pointer; cdecl; external libqjs;
function mz_zip_reader_extract_file_to_heap(pZip: Pmz_zip_archive; pFilename: PChar; pSize: Pcsize_t; flags: mz_uint): pointer; cdecl; external libqjs;
function mz_zip_reader_extract_to_callback(pZip: Pmz_zip_archive; file_index: mz_uint; pCallback: Tmz_file_write_func; pOpaque: pointer; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_file_to_callback(pZip: Pmz_zip_archive; pFilename: PChar; pCallback: Tmz_file_write_func; pOpaque: pointer; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_to_file(pZip: Pmz_zip_archive; file_index: mz_uint; pDst_filename: PChar; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_file_to_file(pZip: Pmz_zip_archive; pArchive_filename: PChar; pDst_filename: PChar; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_to_cfile(pZip: Pmz_zip_archive; file_index: mz_uint; FileHandle: MZ_FILE; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_reader_extract_file_to_cfile(pZip: Pmz_zip_archive; pArchive_filename: PChar; pFile: MZ_FILE; flags: mz_uint): mz_bool; cdecl; external libqjs;

function mz_zip_validate_file(pZip: Pmz_zip_archive; file_index: mz_uint; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_validate_archive(pZip: Pmz_zip_archive; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_validate_mem_archive(pMem: pointer; size: csize_t; flags: mz_uint; pErr: Pmz_zip_error): mz_bool; cdecl; external libqjs;
function mz_zip_validate_file_archive(pFilename: PChar; flags: mz_uint; pErr: Pmz_zip_error): mz_bool; cdecl; external libqjs;
function mz_zip_end(pZip: Pmz_zip_archive): mz_bool; cdecl; external libqjs;

function mz_zip_writer_init(pZip: Pmz_zip_archive; existing_size: mz_uint64): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_v2(pZip: Pmz_zip_archive; existing_size: mz_uint64; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_heap(pZip: Pmz_zip_archive; size_to_reserve_at_beginning: csize_t; initial_allocation_size: csize_t): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_heap_v2(pZip: Pmz_zip_archive; size_to_reserve_at_beginning: csize_t; initial_allocation_size: csize_t; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_file(pZip: Pmz_zip_archive; pFilename: PChar; size_to_reserve_at_beginning: mz_uint64): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_file_v2(pZip: Pmz_zip_archive; pFilename: PChar; size_to_reserve_at_beginning: mz_uint64; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_cfile(pZip: Pmz_zip_archive; pFile: MZ_FILE; flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_from_reader(pZip: Pmz_zip_archive; pFilename: PChar): mz_bool; cdecl; external libqjs;
function mz_zip_writer_init_from_reader_v2(pZip: Pmz_zip_archive; pFilename: PChar; flags: mz_uint): mz_bool; cdecl; external libqjs;

function mz_zip_writer_add_mem(pZip: Pmz_zip_archive; pArchive_name: PChar; pBuf: pointer; buf_size: csize_t; level_and_flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_add_mem_ex(pZip: Pmz_zip_archive; pArchive_name: PChar; pBuf: pointer; buf_size: csize_t; pComment: pointer; comment_size: mz_uint16; level_and_flags: mz_uint; uncomp_size: mz_uint64; uncomp_crc32: mz_uint32): mz_bool; cdecl; external libqjs;
function mz_zip_writer_add_mem_ex_v2(pZip: Pmz_zip_archive; pArchive_name: PChar; pBuf: pointer; buf_size: csize_t; pComment: pointer; comment_size: mz_uint16; level_and_flags: mz_uint; uncomp_size: mz_uint64; uncomp_crc32: mz_uint32; last_modified: PMZ_TIME_T; user_extra_data_local: PChar; user_extra_data_local_len: mz_uint; user_extra_data_central: PChar; user_extra_data_central_len: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_add_read_buf_callback(pZip: Pmz_zip_archive; pArchive_name: PChar; read_callback: Tmz_file_read_func; callback_opaque: pointer; max_size: mz_uint64; pFile_time: PMZ_TIME_T; pComment: pointer; comment_size: mz_uint16; level_and_flags: mz_uint; user_extra_data_local: PChar; user_extra_data_local_len: mz_uint; user_extra_data_central: PChar; user_extra_data_central_len: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_add_file(pZip: Pmz_zip_archive; pArchive_name: PChar; pSrc_filename: PChar; pComment: pointer; comment_size: mz_uint16; level_and_flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_add_cfile(pZip: Pmz_zip_archive; pArchive_name: PChar; pSrc_file: MZ_FILE; max_size: mz_uint64; pFile_time: PMZ_TIME_T; pComment: pointer; comment_size: mz_uint16; level_and_flags: mz_uint; user_extra_data_local: PChar; user_extra_data_local_len: mz_uint; user_extra_data_central: PChar; user_extra_data_central_len: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_add_from_zip_reader(pZip: Pmz_zip_archive; pSource_zip: Pmz_zip_archive; src_file_index: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_writer_finalize_archive(pZip: Pmz_zip_archive): mz_bool; cdecl; external libqjs;
function mz_zip_writer_finalize_heap_archive(pZip: Pmz_zip_archive; ppBuf: Ppointer; pSize: Pcsize_t): mz_bool; cdecl; external libqjs;
function mz_zip_writer_end(pZip: Pmz_zip_archive): mz_bool; cdecl; external libqjs;

function mz_zip_add_mem_to_archive_file_in_place(pZip_filename: PChar; pArchive_name: PChar; pBuf: pointer; buf_size: csize_t; pComment: pointer; comment_size: mz_uint16; level_and_flags: mz_uint): mz_bool; cdecl; external libqjs;
function mz_zip_add_mem_to_archive_file_in_place_v2(pZip_filename: PChar; pArchive_name: PChar; pBuf: pointer; buf_size: csize_t; pComment: pointer; comment_size: mz_uint16; level_and_flags: mz_uint; pErr: Pmz_zip_error): mz_bool; cdecl; external libqjs;

implementation

end.


