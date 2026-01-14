# QuickJS Pascal Project

Dự án Free Pascal sử dụng libqjs.dll với đầy đủ tính năng QuickJS và hỗ trợ QAR (QuickJS Archive).

**VI/EN (important):** Trong repo này, QAR được implement ở tầng **Pascal**. Các file C `qjar.c/qar.c/qar.h` và API kiểu `js_register_qar_file(...)` là **legacy / không dùng** trong luồng hiện tại.

## Tính năng

- ✅ Sử dụng đầy đủ API của QuickJS
- ✅ Đọc và thực thi QAR files
- ✅ Sử dụng QAR như thư viện có thể gọi từ JavaScript
- ✅ Hỗ trợ ES6 modules
- ✅ Hỗ trợ bytecode execution
- ✅ Interactive JavaScript console

## Yêu cầu

- Free Pascal Compiler (FPC) 3.0.0 hoặc mới hơn
- libqjs.dll (hoặc libqjs.so trên Linux) - cần được build từ QuickJS source
- Windows hoặc Linux

## Cấu trúc dự án

```
pascal/
├── quickjs_types.pas    # Kiểu/const QuickJS chung (JSValue, flags, callback types)
├── quickjs_core.pas     # API QuickJS cốt lõi (libqjs.dll)
├── quickjs_std.pas      # Bindings quickjs-libc (console, std/os/bjson, worker hooks)
├── quickjs_miniz.pas    # Bindings miniz (mz_compress/mz_uncompress…)
├── std/qar/qar.pas              # QAR format + build/inspect/rebuild (Pascal)
├── std/qar/qar_helpers.pas      # QAR registry + JS bindings + loader wrapper
├── app/qjsp.pas                 # Host runtime (REPL + run-script)
├── app/qar_tool.pas             # CLI: build/inspect/rebuild/code
├── QuickJSPascal.lpr    # File project Lazarus
└── README.md            # File này
```

## Build

### Sử dụng FPC command line:

```bash
fpc -B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq -Fu. -oQuickJSPascal.exe main.pas
```

### Sử dụng Lazarus IDE:

1. Mở file `QuickJSPascal.lpr` trong Lazarus
2. Đảm bảo `libqjs.dll` nằm trong thư mục project hoặc trong PATH
3. Build project (F9)

## Sử dụng

### 1. Chạy chương trình:

```bash
./QuickJSPascal.exe
```

### 2. Tạo QAR file:

Trước tiên, bạn cần tạo QAR file từ JavaScript files:

```bash
# Tạo QAR file từ một file
qar_tool build mylib.qar math.js

# Tạo QAR file từ nhiều files
qar_tool build mylib.qar math.js utils.js

# Tạo QAR file từ thư mục
qar_tool build mylib.qar src/
```

### 3. Sử dụng QAR trong JavaScript:

```javascript
// Load QAR file
LoadLibrary('mylib.qar', 'mylib:');

// Import modules từ QAR
import { add, multiply } from 'mylib:math.js';
import { greet } from 'mylib:utils.js';

console.log(add(2, 3));
console.log(greet("World"));
```

### 4. API từ JavaScript:

#### LoadLibrary(filename, prefix?)
Đăng ký QAR file để module loader sử dụng.

```javascript
LoadLibrary('mylib.qar');
LoadLibrary('mylib.qar', 'mylib:'); // với prefix
```

#### GetQarInfo(filename)
Lấy thông tin về QAR file.

```javascript
var info = GetQarInfo('mylib.qar');
console.log('Entry count:', info.entryCount);
console.log('Entries:', info.entries);
console.log('Manifest:', info.manifest);
console.log('QuickJS version:', info.quickjsVersion);
```

#### ExecuteQarEntry(filename, entryPath)
Thực thi một entry cụ thể từ QAR file.

```javascript
ExecuteQarEntry('mylib.qar', 'math.js');
```

## Ví dụ

### Ví dụ 1: Thực thi JavaScript cơ bản

```pascal
var
  rt: ^JSRuntime;
  ctx: ^JSContext;
  script: string;
  result: JSValue;
begin
  rt := JS_NewRuntime;
  ctx := JS_NewContext(rt);
  
  script := 'console.log("Hello from QuickJS!");';
  result := JS_Eval(ctx, PChar(script), Length(script), 'test.js', JS_EVAL_TYPE_GLOBAL);
  
  JS_FreeValue(ctx, result);
  JS_FreeContext(ctx);
  JS_FreeRuntime(rt);
end;
```

### Ví dụ 2: Đọc QAR file

```pascal
var
  qar: PQarFile;
  entry_count: cint;
  i: cint;
  entry: PQarEntry;
begin
  qar := qar_open('mylib.qar');
  if qar <> nil then
  begin
    entry_count := qar_get_entry_count(qar);
    for i := 0 to entry_count - 1 do
    begin
      entry := qar_get_entry(qar, i);
      WriteLn('Entry: ', qar_entry_get_path(entry));
    end;
    qar_close(qar);
  end;
end;
```

### Ví dụ 3: Đăng ký và sử dụng QAR (Pascal runtime)

**VI:** Đăng ký QAR trong runtime được thực hiện qua helper JS `LoadLibrary()` (được `qjsp` cung cấp).

**EN:** QAR registration at runtime is done via the JS helper `LoadLibrary()` (provided by `qjsp`).

## API Reference

### QuickJS API

Xem `quickjs_core.pas` (các hàm) và `quickjs_types.pas` (kiểu/const) để biết đầy đủ QuickJS API khi link với `libqjs.dll`.

### QuickJS libc API

- `js_std_add_helpers(ctx: ^JSContext; argc: cint; argv: PPChar)` - Thêm helper functions (console, print, etc.)
- `js_std_dump_error(ctx: ^JSContext)` - In error ra console

## Ghi chú

- **VI:** QAR files được tạo bằng `qar_tool` (Pascal) và được load bằng `LoadLibrary()` trong `qjsp`.
- **EN:** QAR files are built with `qar_tool` (Pascal) and loaded via `LoadLibrary()` in `qjsp`.
- Bytecode format phụ thuộc vào phiên bản QuickJS
- Nếu bytecode không tương thích, hệ thống sẽ tự động compile lại từ source code

## License

Tương tự như QuickJS - MIT License

## Tác giả

Dự án này được tạo để tích hợp QuickJS vào Free Pascal với đầy đủ tính năng QAR.

