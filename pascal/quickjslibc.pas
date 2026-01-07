unit quickjslibc;

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

// QuickJS libc functions
function js_init_module_std(ctx: PJSContext; module_name: PChar): PJSModuleDef; cdecl; external libqjs;
function js_init_module_os(ctx: PJSContext; module_name: PChar): PJSModuleDef; cdecl; external libqjs;
function js_init_module_bjson(ctx: PJSContext; module_name: PChar): PJSModuleDef; cdecl; external libqjs;
procedure js_std_add_helpers(ctx: PJSContext; argc: cint; argv: PPChar); cdecl; external libqjs;
function js_std_loop(ctx: PJSContext): cint; cdecl; external libqjs;
function js_std_await(ctx: PJSContext; obj: JSValueConst): JSValue; cdecl; external libqjs;
procedure js_std_init_handlers(rt: PJSRuntime); cdecl; external libqjs;
procedure js_std_free_handlers(rt: PJSRuntime); cdecl; external libqjs;
procedure js_std_dump_error(ctx: PJSContext); cdecl; external libqjs;
function js_load_file(ctx: PJSContext; pbuf_len: Pcsize_t; filename: PChar): Pcuint8; cdecl; external libqjs;
function js_module_set_import_meta(ctx: PJSContext; func_val: JSValueConst; use_realpath: cbool; is_main: cbool): cint; cdecl; external libqjs;
function js_module_loader(ctx: PJSContext; module_name: PChar; opaque: pointer): PJSModuleDef; cdecl; external libqjs;
procedure js_std_eval_binary(ctx: PJSContext; buf: Pcuint8; buf_len: csize_t; flags: cint); cdecl; external libqjs;
procedure js_std_promise_rejection_tracker(ctx: PJSContext; promise: JSValueConst; reason: JSValueConst; is_handled: cbool; opaque: pointer); cdecl; external libqjs;

// QAR support
function js_register_qar_file(ctx: PJSContext; qar_filename: PChar; prefix: PChar): cint; cdecl; external libqjs;
procedure js_unregister_all_qar_files(rt: PJSRuntime); cdecl; external libqjs;

implementation

end.

