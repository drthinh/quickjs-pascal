unit quickjs_memdebug;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  ctypes, SysUtils, quickjs_types;

const
  {$IFDEF WINDOWS}
  libqjs = 'libqjs.dll';
  {$ELSE}
  libqjs = 'libqjs.so';
  {$ENDIF}

// Debug dump flag bits (copied from quickjs.h)
const
  JS_DUMP_BYTECODE_FINAL   = $01;
  JS_DUMP_BYTECODE_PASS2   = $02;
  JS_DUMP_BYTECODE_PASS3   = $04;
  JS_DUMP_BYTECODE_SPECIAL = $08;
  JS_DUMP_FREE             = $10;
  JS_DUMP_GC               = $20;
  JS_DUMP_REACHABLE        = $40;
  JS_DUMP_MEM              = $80;

// JSMemoryUsage struct from quickjs.h
// Keep field order and types in sync with the C definition.
type
  PJSMemoryUsage = ^TJSMemoryUsage;
  TJSMemoryUsage = record
    // Same order and types as JSMemoryUsage in quickjs.h
    malloc_size: cint64;
    malloc_limit: cint64;
    memory_used_size: cint64;
    malloc_count: cint64;
    memory_used_count: cint64;
    atom_count: cint64;
    atom_size: cint64;
    str_count: cint64;
    str_size: cint64;
    obj_count: cint64;
    obj_size: cint64;
    prop_count: cint64;
    prop_size: cint64;
    shape_count: cint64;
    shape_size: cint64;
    js_func_count: cint64;
    js_func_size: cint64;
    js_func_code_size: cint64;
    js_func_pc2line_count: cint64;
    js_func_pc2line_size: cint64;
    c_func_count: cint64;
    array_count: cint64;
    fast_array_count: cint64;
    fast_array_elements: cint64;
    binary_object_count: cint64;
    binary_object_size: cint64;
  end;

procedure JS_ComputeMemoryUsage(rt: PJSRuntime; s: PJSMemoryUsage); cdecl; external libqjs;
procedure JS_DumpMemoryUsage(fp: pointer; const s: PJSMemoryUsage; rt: PJSRuntime); cdecl; external libqjs;
procedure JS_SetDumpFlags(rt: PJSRuntime; flags: cuint64); cdecl; external libqjs;
function JS_GetDumpFlags(rt: PJSRuntime): cuint64; cdecl; external libqjs;

procedure DumpRuntimeMemoryUsageToConsole(rt: PJSRuntime);
procedure EnableAllDebugDumps(rt: PJSRuntime);
procedure DisableAllDebugDumps(rt: PJSRuntime);

implementation

procedure DumpRuntimeMemoryUsageToConsole(rt: PJSRuntime);
var
  u: TJSMemoryUsage;
begin
  FillChar(u, SizeOf(u), 0);
  JS_ComputeMemoryUsage(rt, @u);
  WriteLn('QuickJS memory usage:');
  WriteLn('  malloc_size: ', Int64(u.malloc_size), ' bytes (limit ', Int64(u.malloc_limit), ')');
  WriteLn('  memory_used_size: ', Int64(u.memory_used_size), ' bytes');
  WriteLn('  objects: ', Int64(u.obj_count), ' (', Int64(u.obj_size), ' bytes)');
  WriteLn('  arrays: ', Int64(u.array_count), ', fast arrays: ', Int64(u.fast_array_count), ', elements: ', Int64(u.fast_array_elements));
  WriteLn('  strings: ', Int64(u.str_count), ' (', Int64(u.str_size), ' bytes)');
  WriteLn('  atoms: ', Int64(u.atom_count), ' (', Int64(u.atom_size), ' bytes)');
  WriteLn('  binary objects: ', Int64(u.binary_object_count), ' (', Int64(u.binary_object_size), ' bytes)');
end;

procedure EnableAllDebugDumps(rt: PJSRuntime);
var
  flags: cuint64;
begin
  flags := cuint64(JS_DUMP_BYTECODE_FINAL or JS_DUMP_BYTECODE_PASS2 or JS_DUMP_BYTECODE_PASS3 or JS_DUMP_BYTECODE_SPECIAL or JS_DUMP_FREE or JS_DUMP_GC or JS_DUMP_REACHABLE or JS_DUMP_MEM);
  JS_SetDumpFlags(rt, flags);
end;

procedure DisableAllDebugDumps(rt: PJSRuntime);
begin
  JS_SetDumpFlags(rt, 0);
end;

end.
