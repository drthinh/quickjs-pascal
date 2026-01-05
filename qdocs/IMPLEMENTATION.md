# QuickJS QAR Implementation Summary

## Đã triển khai

### 1. Công cụ QAR Packager (`qjar.c`)
- Biên dịch nhiều file/thư mục JavaScript thành bytecode
- Đóng gói bytecode và source code vào file QAR
- Tạo manifest JSON chứa thông tin về các entry
- Hỗ trợ cả ES modules và classic scripts

### 2. QAR Reader Library (`qar.c`, `qar.h`)
- Đọc và parse QAR files
- Lấy bytecode và source code từ entries
- Hỗ trợ tìm kiếm entry theo path
- Cache dữ liệu để tối ưu hiệu suất

### 3. Tích hợp vào QuickJS Module Loader
- Tự động load modules từ QAR files
- Hỗ trợ import/export ES6 modules
- Fallback về source code nếu bytecode không tương thích
- API để đăng ký QAR files: `js_register_qar_file()`

### 4. CMake Configuration
- Build tool `qjar` executable
- Build QAR reader library
- Static linking với GCC (không phụ thuộc DLL)
- Tối ưu kích thước binary với `-Os -ffunction-sections -fdata-sections`

### 5. Tests và Documentation
- Test files trong `tests/`
- Documentation trong `qdocs/qar_usage.md`
- Example code trong `tests/test_qar_load.c`

## Cấu trúc Files

```
quickjs-master/
├── qjar.c              # QAR packager tool
├── qar.c               # QAR reader implementation
├── qar.h               # QAR reader header
├── quickjs-libc.c      # Modified với QAR support
├── quickjs-libc.h      # Added QAR API exports
├── CMakeLists.txt      # Updated với QAR build config
├── tests/
│   ├── test_qar.js     # JavaScript test
│   ├── test_qar_load.c # C test
│   └── qar_test_lib/   # Test library files
└── qdocs/
    ├── readme.md       # Requirements
    └── qar_usage.md    # Usage guide
```

## Cách sử dụng

### 1. Build project

```bash
mkdir build
cd build
cmake ..
make qjar
make test_qar_load
```

### 2. Tạo QAR file

```bash
# Đóng gói thư mục
./qjar -o mylib.qar ../tests/qar_test_lib/

# Đóng gói file đơn lẻ
./qjar -o math.qar ../tests/qar_test_lib/math.js
```

### 3. Sử dụng QAR trong C code

```c
#include "quickjs-libc.h"

JSRuntime *rt = JS_NewRuntime();
JSContext *ctx = JS_NewContext(rt);
js_std_init_handlers(rt);
JS_SetModuleLoaderFunc(rt, NULL, js_module_loader, NULL);

// Đăng ký QAR file
js_register_qar_file(ctx, "mylib.qar", NULL);

// Load và chạy module
JSValue module = JS_LoadModule(ctx, "math", "math");
JS_ResolveModule(ctx, module);
JSValue result = JS_EvalFunction(ctx, module);
```

### 4. Sử dụng QAR trong JavaScript

```javascript
// Import từ QAR
import { add, multiply } from 'math.js';
console.log(add(2, 3));
```

## API Exports

### C API (quickjs-libc.h)

- `int js_register_qar_file(JSContext *ctx, const char *qar_filename, const char *prefix)`
- `void js_unregister_all_qar_files(JSRuntime *rt)`

### QAR Reader API (qar.h)

- `QarFile *qar_open(const char *filename)`
- `void qar_close(QarFile *qar)`
- `const QarEntry *qar_find_entry(QarFile *qar, const char *path)`
- `const uint8_t *qar_entry_get_bytecode(const QarEntry *entry, size_t *len)`
- `const uint8_t *qar_entry_get_source(const QarEntry *entry, size_t *len)`
- `int qar_entry_load_data(QarFile *qar, const QarEntry *entry)`

## QAR File Format

```
[Magic: "QAR\x01"] (4 bytes)
[Version: uint32] (4 bytes)
[Manifest Offset: uint64] (8 bytes)
[Manifest Size: uint64] (8 bytes)
[Entry Count: uint32] (4 bytes)
[Entries...]
  - [Path Length: uint32]
  - [Path: string]
  - [Flags: uint32] (1 = module, 0 = script)
  - [Bytecode Size: uint64]
  - [Bytecode: bytes]
  - [Source Size: uint64]
  - [Source: bytes]
[Manifest: JSON]
```

## Tính năng

✅ Biên dịch nhiều file/thư mục JS thành bytecode
✅ Đóng gói bytecode + source vào QAR
✅ Manifest JSON với thông tin đầy đủ
✅ Load QAR như thư viện với import/export
✅ Fallback về source nếu bytecode không tương thích
✅ Static build không phụ thuộc DLL
✅ Tests và documentation

## Notes

- Bytecode format phụ thuộc vào phiên bản QuickJS
- QAR files có thể được sử dụng như thư viện
- Module loader tự động tìm trong QAR files đã đăng ký
- Source code được lưu để có thể recompile khi cần

