{
  Ví dụ Implementation: Tích hợp SQLite qua QuickJS API
  
  File này minh họa cách tích hợp SQLite vào QuickJS Pascal
  sử dụng phương án 1 (Native Bindings qua QuickJS API).
  
  LƯU Ý: Đây là ví dụ, cần link với sqlite3 library thực tế.
  Compile với: fpc -Fu. sqlite_integration_example.pas -lsqlite3
}

unit SqliteIntegration;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, ctypes, quickjs_types, quickjs_core;

// SQLite types (giả định - cần thay bằng bindings thực tế)
type
  PSqlite3 = ^TSqlite3;
  TSqlite3 = record end;
  
  PSqlite3Stmt = ^TSqlite3Stmt;
  TSqlite3Stmt = record end;

// SQLite function declarations (cần link với sqlite3.dll/libsqlite3.so)
function sqlite3_open(filename: PChar; var ppDb: PSqlite3): cint; cdecl; external 'sqlite3';
function sqlite3_close(db: PSqlite3): cint; cdecl; external 'sqlite3';
function sqlite3_exec(db: PSqlite3; sql: PChar; callback: pointer; arg: pointer; errmsg: PPChar): cint; cdecl; external 'sqlite3';
function sqlite3_prepare_v2(db: PSqlite3; zSql: PChar; nByte: cint; var ppStmt: PSqlite3Stmt; var pzTail: PChar): cint; cdecl; external 'sqlite3';
function sqlite3_step(stmt: PSqlite3Stmt): cint; cdecl; external 'sqlite3';
function sqlite3_finalize(stmt: PSqlite3Stmt): cint; cdecl; external 'sqlite3';
function sqlite3_column_text(stmt: PSqlite3Stmt; iCol: cint): PChar; cdecl; external 'sqlite3';
function sqlite3_column_int(stmt: PSqlite3Stmt; iCol: cint): cint; cdecl; external 'sqlite3';
function sqlite3_column_count(stmt: PSqlite3Stmt): cint; cdecl; external 'sqlite3';
function sqlite3_column_name(stmt: PSqlite3Stmt; N: cint): PChar; cdecl; external 'sqlite3';
function sqlite3_errmsg(db: PSqlite3): PChar; cdecl; external 'sqlite3';
function sqlite3_errstr(code: cint): PChar; cdecl; external 'sqlite3';

const
  SQLITE_OK = 0;
  SQLITE_ROW = 100;
  SQLITE_DONE = 101;

// Đăng ký SQLite API vào QuickJS context
procedure RegisterSqliteModule(ctx: PJSContext);

implementation

var
  sqlite_class_id: JSClassID;
  sqlite_stmt_class_id: JSClassID;

// ========== SQLite Database Class ==========

// Finalizer: Đóng database khi object bị GC
procedure sqlite_finalizer(rt: PJSRuntime; val: JSValue); cdecl;
var
  db: PSqlite3;
begin
  db := PSqlite3(JS_GetOpaque(val, sqlite_class_id));
  if db <> nil then
  begin
    sqlite3_close(db);
  end;
end;

// sqlite.open(filename) -> Database object
function js_sqlite_open(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename: PChar;
  db: PSqlite3;
  db_obj: JSValue;
  class_def: JSClass;
  ret: cint;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('sqlite.open expects 1 argument: filename'));
    Exit;
  end;

  filename := JS_ToCString(ctx, argv[0]);
  if filename = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  // Mở database
  ret := sqlite3_open(filename, db);
  JS_FreeCString(ctx, filename);

  if ret <> SQLITE_OK then
  begin
    Result := JS_ThrowTypeError(ctx, PChar(sqlite3_errstr(ret)));
    Exit;
  end;

  // Tạo JavaScript object với class
  FillChar(class_def, SizeOf(class_def), 0);
  class_def.class_name := 'SQLiteDatabase';
  class_def.finalizer := @sqlite_finalizer;
  
  db_obj := JS_NewObjectClass(ctx, sqlite_class_id);
  JS_SetOpaque(db_obj, db);

  Result := db_obj;
end;

// db.exec(sql) -> number (rows affected)
function js_sqlite_exec(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  db: PSqlite3;
  sql: PChar;
  errmsg: PChar;
  ret: cint;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('exec expects 1 argument: sql'));
    Exit;
  end;

  db := PSqlite3(JS_GetOpaque2(ctx, this_val, sqlite_class_id));
  if db = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Invalid database object'));
    Exit;
  end;

  sql := JS_ToCString(ctx, argv[0]);
  if sql = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  errmsg := nil;
  ret := sqlite3_exec(db, sql, nil, nil, @errmsg);

  JS_FreeCString(ctx, sql);

  if ret <> SQLITE_OK then
  begin
    if errmsg <> nil then
    begin
      Result := JS_ThrowTypeError(ctx, errmsg);
      // sqlite3_free(errmsg); // Cần free errmsg nếu có hàm này
    end
    else
      Result := JS_ThrowTypeError(ctx, PChar(sqlite3_errstr(ret)));
    Exit;
  end;

  Result := JS_NewInt32(ctx, 0); // Return rows affected (simplified)
end;

// db.prepare(sql) -> Statement object
function js_sqlite_prepare(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  db: PSqlite3;
  sql: PChar;
  stmt: PSqlite3Stmt;
  stmt_obj: JSValue;
  ret: cint;
  tail: PChar;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('prepare expects 1 argument: sql'));
    Exit;
  end;

  db := PSqlite3(JS_GetOpaque2(ctx, this_val, sqlite_class_id));
  if db = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Invalid database object'));
    Exit;
  end;

  sql := JS_ToCString(ctx, argv[0]);
  if sql = nil then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  tail := nil;
  ret := sqlite3_prepare_v2(db, sql, -1, stmt, tail);
  JS_FreeCString(ctx, sql);

  if ret <> SQLITE_OK then
  begin
    Result := JS_ThrowTypeError(ctx, PChar(sqlite3_errmsg(db)));
    Exit;
  end;

  // Tạo statement object
  stmt_obj := JS_NewObjectClass(ctx, sqlite_stmt_class_id);
  JS_SetOpaque(stmt_obj, stmt);

  Result := stmt_obj;
end;

// ========== SQLite Statement Class ==========

// Finalizer: Finalize statement khi object bị GC
procedure sqlite_stmt_finalizer(rt: PJSRuntime; val: JSValue); cdecl;
var
  stmt: PSqlite3Stmt;
begin
  stmt := PSqlite3Stmt(JS_GetOpaque(val, sqlite_stmt_class_id));
  if stmt <> nil then
  begin
    sqlite3_finalize(stmt);
  end;
end;

// stmt.step() -> boolean (true if row available, false if done)
function js_sqlite_step(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  stmt: PSqlite3Stmt;
  ret: cint;
begin
  stmt := PSqlite3Stmt(JS_GetOpaque2(ctx, this_val, sqlite_stmt_class_id));
  if stmt = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Invalid statement object'));
    Exit;
  end;

  ret := sqlite3_step(stmt);
  
  if ret = SQLITE_ROW then
    Result := JS_TRUE
  else if ret = SQLITE_DONE then
    Result := JS_FALSE
  else
    Result := JS_ThrowTypeError(ctx, PChar(sqlite3_errstr(ret)));
end;

// stmt.getColumn(index) -> value
function js_sqlite_get_column(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  stmt: PSqlite3Stmt;
  col_index: cint32;
  col_text: PChar;
  col_int: cint;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('getColumn expects 1 argument: index'));
    Exit;
  end;

  stmt := PSqlite3Stmt(JS_GetOpaque2(ctx, this_val, sqlite_stmt_class_id));
  if stmt = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Invalid statement object'));
    Exit;
  end;

  if JS_ToInt32(ctx, @col_index, argv[0]) < 0 then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  // Đơn giản: lấy text (có thể mở rộng để detect type)
  col_text := sqlite3_column_text(stmt, col_index);
  if col_text <> nil then
    Result := JS_NewString(ctx, col_text)
  else
    Result := JS_NULL;
end;

// stmt.getColumnName(index) -> string
function js_sqlite_get_column_name(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  stmt: PSqlite3Stmt;
  col_index: cint32;
  col_name: PChar;
begin
  if argc < 1 then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('getColumnName expects 1 argument: index'));
    Exit;
  end;

  stmt := PSqlite3Stmt(JS_GetOpaque2(ctx, this_val, sqlite_stmt_class_id));
  if stmt = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Invalid statement object'));
    Exit;
  end;

  if JS_ToInt32(ctx, @col_index, argv[0]) < 0 then
  begin
    Result := JS_EXCEPTION;
    Exit;
  end;

  col_name := sqlite3_column_name(stmt, col_index);
  if col_name <> nil then
    Result := JS_NewString(ctx, col_name)
  else
    Result := JS_NULL;
end;

// stmt.getColumnCount() -> number
function js_sqlite_get_column_count(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  stmt: PSqlite3Stmt;
  count: cint;
begin
  stmt := PSqlite3Stmt(JS_GetOpaque2(ctx, this_val, sqlite_stmt_class_id));
  if stmt = nil then
  begin
    Result := JS_ThrowTypeError(ctx, PChar('Invalid statement object'));
    Exit;
  end;

  count := sqlite3_column_count(stmt);
  Result := JS_NewInt32(ctx, count);
end;

// ========== Module Registration ==========

procedure RegisterSqliteModule(ctx: PJSContext);
var
  global_obj, sqlite_obj, db_proto, stmt_proto: JSValue;
  class_def: JSClass;
begin
  // Tạo class IDs
  JS_NewClassID(@sqlite_class_id);
  JS_NewClassID(@sqlite_stmt_class_id);

  // Đăng ký SQLite Database class
  FillChar(class_def, SizeOf(class_def), 0);
  class_def.class_name := 'SQLiteDatabase';
  class_def.finalizer := @sqlite_finalizer;
  JS_NewClass(JS_GetRuntime(ctx), sqlite_class_id, @class_def);

  // Đăng ký SQLite Statement class
  FillChar(class_def, SizeOf(class_def), 0);
  class_def.class_name := 'SQLiteStatement';
  class_def.finalizer := @sqlite_stmt_finalizer;
  JS_NewClass(JS_GetRuntime(ctx), sqlite_stmt_class_id, @class_def);

  // Tạo prototype cho Database
  db_proto := JS_GetClassProto(ctx, sqlite_class_id);
  JS_DefinePropertyValueStr(ctx, db_proto, 'exec',
    JS_NewCFunction(ctx, @js_sqlite_exec, 'exec', 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, db_proto, 'prepare',
    JS_NewCFunction(ctx, @js_sqlite_prepare, 'prepare', 1), JS_PROP_C_W_E);

  // Tạo prototype cho Statement
  stmt_proto := JS_GetClassProto(ctx, sqlite_stmt_class_id);
  JS_DefinePropertyValueStr(ctx, stmt_proto, 'step',
    JS_NewCFunction(ctx, @js_sqlite_step, 'step', 0), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, stmt_proto, 'getColumn',
    JS_NewCFunction(ctx, @js_sqlite_get_column, 'getColumn', 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, stmt_proto, 'getColumnName',
    JS_NewCFunction(ctx, @js_sqlite_get_column_name, 'getColumnName', 1), JS_PROP_C_W_E);
  JS_DefinePropertyValueStr(ctx, stmt_proto, 'getColumnCount',
    JS_NewCFunction(ctx, @js_sqlite_get_column_count, 'getColumnCount', 0), JS_PROP_C_W_E);

  // Tạo sqlite object trong global
  global_obj := JS_GetGlobalObject(ctx);
  sqlite_obj := JS_NewObject(ctx);
  
  JS_DefinePropertyValueStr(ctx, sqlite_obj, 'open',
    JS_NewCFunction(ctx, @js_sqlite_open, 'open', 1), JS_PROP_C_W_E);

  JS_DefinePropertyValueStr(ctx, global_obj, 'sqlite', sqlite_obj, JS_PROP_C_W_E);

  JS_FreeValue(ctx, global_obj);
  JS_FreeValue(ctx, db_proto);
  JS_FreeValue(ctx, stmt_proto);
  JS_FreeValue(ctx, sqlite_obj);
end;

end.

