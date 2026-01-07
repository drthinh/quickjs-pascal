# Phân tích Tích hợp Thư viện Native vào QuickJS

Tài liệu này phân tích các phương án tích hợp các thư viện native như **libuv**, **sqlite**, **curl** vào chương trình QuickJS Pascal.

## Tổng quan các Phương án

### 1. Tích hợp qua QuickJS API (Native Bindings)

**Cách thức:**
- Viết wrapper functions trong Pascal sử dụng `JS_NewCFunction`
- Đăng ký các hàm C/Pascal trực tiếp vào global object của QuickJS
- Tạo các class/object JavaScript để đóng gói API

**Ví dụ:**
```pascal
// Đăng ký hàm SQLite
function js_sqlite_open(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  db_path: PChar;
  db: PSqlite3;
  db_obj: JSValue;
begin
  db_path := JS_ToCString(ctx, argv[0]);
  sqlite3_open(db_path, @db);
  // Tạo object JavaScript chứa handle
  db_obj := JS_NewObject(ctx);
  JS_SetOpaque(db_obj, db);
  Result := db_obj;
end;

// Đăng ký vào global
JS_DefinePropertyValueStr(ctx, global_obj, 'sqlite_open',
  JS_NewCFunction(ctx, @js_sqlite_open, 'sqlite_open', 1), JS_PROP_C_W_E);
```

**Ưu điểm:**
- ✅ **Hiệu năng cao nhất**: Gọi trực tiếp từ JavaScript → Pascal → Native library, không có overhead
- ✅ **Type safety**: Kiểm tra kiểu dữ liệu tại compile-time trong Pascal
- ✅ **Error handling tốt**: Có thể xử lý lỗi và throw JavaScript exceptions một cách chính xác
- ✅ **Memory management**: Quản lý bộ nhớ tốt với JS_FreeValue, JS_SetOpaque
- ✅ **API design linh hoạt**: Có thể tạo object-oriented API, async/await, promises
- ✅ **Tích hợp sâu**: Có thể tạo custom classes với finalizers, getters/setters
- ✅ **Debugging dễ**: Stack trace rõ ràng, lỗi dễ trace

**Nhược điểm:**
- ❌ **Phải viết code Pascal**: Cần hiểu cả QuickJS API và thư viện native
- ❌ **Rebuild khi thay đổi**: Mỗi lần thêm API mới phải recompile chương trình chính
- ❌ **Code dài hơn**: Phải viết wrapper cho mỗi hàm
- ❌ **Phụ thuộc vào compiler**: Phải có source code Pascal để build

**Phù hợp với:**
- Thư viện cần hiệu năng cao (SQLite queries, file I/O)
- API phức tạp cần error handling tốt
- Cần tích hợp sâu với QuickJS (async operations, promises)
- Dự án dài hạn, có thời gian phát triển

---

### 2. Gọi hàm qua DLL từ JavaScript

**Cách thức:**
- Build các thư viện native thành DLL/SO
- Sử dụng `LoadDynamicLibrary` và `CallDllFunction` hiện có
- Gọi trực tiếp từ JavaScript

**Ví dụ:**
```javascript
// Load SQLite DLL
var sqlite = LoadDynamicLibrary("sqlite3.dll");

// Gọi hàm sqlite3_open
var db_handle = CallDllFunction(sqlite, "sqlite3_open", "i", "test.db");

// Gọi hàm sqlite3_exec
CallDllFunction(sqlite, "sqlite3_exec", "v", db_handle, "SELECT * FROM users", callback);
```

**Ưu điểm:**
- ✅ **Không cần rebuild main program**: Chỉ cần có DLL và gọi từ JavaScript
- ✅ **Linh hoạt**: Có thể thay đổi DLL mà không cần rebuild
- ✅ **Tách biệt**: Logic native tách riêng khỏi main program
- ✅ **Dễ phân phối**: Có thể phân phối DLL riêng
- ✅ **Đã có sẵn**: Dự án đã implement `LoadDynamicLibrary` và `CallDllFunction`

**Nhược điểm:**
- ❌ **Hạn chế về signature**: Hiện tại chỉ hỗ trợ 0-1 argument, basic types
- ❌ **Không type-safe**: Không kiểm tra kiểu tại compile-time
- ❌ **Error handling khó**: Khó xử lý lỗi từ native code
- ❌ **Memory management phức tạp**: Phải tự quản lý handles, không tích hợp với GC
- ❌ **Không hỗ trợ callbacks phức tạp**: Khó truyền JavaScript functions làm callbacks
- ❌ **Performance overhead**: Qua nhiều lớp indirection
- ❌ **Không hỗ trợ structs/pointers phức tạp**: Chỉ hỗ trợ int, float, void
- ❌ **Calling convention**: Phải match calling convention (stdcall/cdecl)

**Phù hợp với:**
- Thư viện đơn giản với API ít tham số
- Prototyping nhanh
- Khi không muốn rebuild main program
- Thư viện đã có sẵn DLL

---

### 3. Giải pháp Hybrid (Kết hợp)

**Cách thức:**
- Core functions tích hợp qua QuickJS API (hiệu năng cao)
- Optional/advanced features qua DLL (linh hoạt)
- Tạo wrapper JavaScript để thống nhất API

**Ví dụ:**
```pascal
// Core SQLite functions qua QuickJS API
JS_DefinePropertyValueStr(ctx, global_obj, 'sqlite_open',
  JS_NewCFunction(ctx, @js_sqlite_open, 'sqlite_open', 1), JS_PROP_C_W_E);

// Advanced features có thể load từ DLL nếu cần
```

```javascript
// JavaScript wrapper thống nhất API
const sqlite = {
  open: sqlite_open,  // từ QuickJS API
  exec: function(db, sql) {
    // Có thể dùng CallDllFunction cho advanced features
    return CallDllFunction(sqlite_dll, "sqlite3_exec", "i", db, sql);
  }
};
```

**Ưu điểm:**
- ✅ **Tối ưu cả hai**: Core functions hiệu năng cao, advanced features linh hoạt
- ✅ **Linh hoạt**: Có thể mở rộng mà không rebuild
- ✅ **API nhất quán**: JavaScript wrapper che giấu implementation details

**Nhược điểm:**
- ❌ **Phức tạp hơn**: Phải maintain cả hai phương thức
- ❌ **Có thể gây confusion**: Developer không biết function nào dùng cách nào

---

## Phân tích chi tiết theo từng thư viện

### SQLite

**Đặc điểm:**
- API phức tạp với nhiều hàm (sqlite3_open, sqlite3_exec, sqlite3_prepare, ...)
- Cần quản lý handles (sqlite3*)
- Callbacks cho queries
- Error handling quan trọng

**Khuyến nghị: Phương án 1 (QuickJS API)**

**Lý do:**
1. **Quản lý handles**: Cần lưu `sqlite3*` trong JS objects với finalizers
2. **Callbacks**: Cần truyền JavaScript functions làm callbacks cho sqlite3_exec
3. **Error handling**: SQLite trả về error codes, cần convert sang JS exceptions
4. **Performance**: Database queries cần hiệu năng cao

**Implementation gợi ý:**
```pascal
// Tạo class cho SQLite database
var sqlite_class_id: JSClassID;

// Finalizer để đóng database khi GC
procedure sqlite_finalizer(rt: PJSRuntime; val: JSValue); cdecl;
var
  db: PSqlite3;
begin
  db := PSqlite3(JS_GetOpaque(val, sqlite_class_id));
  if db <> nil then
    sqlite3_close(db);
end;

// Đăng ký các methods
JS_DefinePropertyValueStr(ctx, sqlite_proto, 'exec',
  JS_NewCFunction(ctx, @js_sqlite_exec, 'exec', 2), JS_PROP_C_W_E);
```

---

### libuv (Async I/O)

**Đặc điểm:**
- Event loop based
- Callbacks cho async operations
- Cần tích hợp với QuickJS event loop
- Promises/async-await support

**Khuyến nghị: Phương án 1 (QuickJS API)**

**Lý do:**
1. **Event loop integration**: Cần tích hợp libuv loop với QuickJS
2. **Promises**: Cần tạo promises từ async operations
3. **Callbacks**: Truyền JS functions làm callbacks
4. **Memory management**: Quản lý handles với GC

**Implementation gợi ý:**
```pascal
// Tích hợp event loop
procedure js_uv_run(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
begin
  // Run libuv loop và xử lý pending jobs của QuickJS
  while uv_run(loop, UV_RUN_NOWAIT) <> 0 do
  begin
    JS_ExecutePendingJob(rt, @ctx);
  end;
end;

// Tạo promise từ async operation
function js_uv_read_file(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  filename: PChar;
  promise, resolve_func, reject_func: JSValue;
begin
  promise := JS_NewPromiseCapability(ctx, @resolve_func);
  // ... setup async operation với callback
  Result := promise;
end;
```

---

### libcurl (HTTP Client)

**Đặc điểm:**
- API tương đối đơn giản
- Có thể dùng sync hoặc async
- Cần quản lý handles (CURL*)
- Headers, body, callbacks

**Khuyến nghị: Phương án 1 (QuickJS API) hoặc Hybrid**

**Lý do:**
- Nếu chỉ cần basic HTTP requests → có thể dùng DLL với wrapper
- Nếu cần async, progress callbacks → nên dùng QuickJS API
- libcurl handles cần quản lý với GC

**Implementation gợi ý (QuickJS API):**
```pascal
// Tạo class cho CURL handle
var curl_class_id: JSClassID;

function js_curl_easy_init(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  curl: PCURL;
  curl_obj: JSValue;
begin
  curl := curl_easy_init();
  curl_obj := JS_NewObjectClass(ctx, curl_class_id);
  JS_SetOpaque(curl_obj, curl);
  Result := curl_obj;
end;

function js_curl_easy_perform(ctx: PJSContext; this_val: JSValueConst; argc: cint; argv: PJSValueConst): JSValue; cdecl;
var
  curl: PCURL;
  res: CURLcode;
begin
  curl := PCURL(JS_GetOpaque2(ctx, this_val, curl_class_id));
  res := curl_easy_perform(curl);
  if res <> CURLE_OK then
    Result := JS_ThrowTypeError(ctx, PChar(curl_easy_strerror(res)))
  else
    Result := JS_UNDEFINED;
end;
```

---

## So sánh tổng quan

| Tiêu chí | QuickJS API | DLL Calls | Hybrid |
|----------|-------------|-----------|--------|
| **Performance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Type Safety** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Error Handling** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Memory Management** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Development Speed** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Flexibility** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Maintainability** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **API Design** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |

---

## Khuyến nghị cuối cùng

### Cho dự án này (QuickJS Pascal):

**Ưu tiên: Phương án 1 (QuickJS API) cho tất cả thư viện**

**Lý do:**
1. **Dự án đã có infrastructure**: Đã có `JS_NewCFunction`, class system, finalizers
2. **Performance quan trọng**: Các thư viện như SQLite, libuv cần hiệu năng cao
3. **Tích hợp sâu**: Cần async/await, promises, callbacks
4. **Long-term**: Dự án có vẻ là long-term, nên đầu tư vào native bindings

**Roadmap đề xuất:**

1. **Phase 1: SQLite** (Ưu tiên cao)
   - Core functions: open, close, exec, prepare, step
   - Error handling
   - Result sets

2. **Phase 2: libcurl** (Ưu tiên trung bình)
   - Basic HTTP requests
   - Headers, body
   - Async support với promises

3. **Phase 3: libuv** (Ưu tiên thấp, phức tạp)
   - Event loop integration
   - File I/O
   - Network I/O
   - Timers

**Cải thiện CallDllFunction (nếu cần):**
- Nếu vẫn muốn dùng DLL cho một số cases, có thể mở rộng `CallDllFunction`:
  - Hỗ trợ nhiều arguments hơn
  - Hỗ trợ structs/pointers
  - Hỗ trợ callbacks (phức tạp)

---

## Ví dụ Implementation: SQLite Integration

Xem file `sqlite_integration_example.pas` (sẽ tạo) để có ví dụ đầy đủ về cách tích hợp SQLite qua QuickJS API.


