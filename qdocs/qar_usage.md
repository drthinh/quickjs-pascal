# QuickJS Archive (QAR) Usage Guide

## Overview

QAR (QuickJS Archive) là định dạng đóng gói tương tự Java JAR, cho phép:
- Đóng gói nhiều file JavaScript thành một file QAR
- Lưu trữ cả bytecode và source code
- Load và sử dụng như thư viện với import/export
- Tự động fallback về source code nếu bytecode không tương thích

## Tạo QAR file

Sử dụng công cụ `qjar` để tạo QAR file:

```bash
# Đóng gói một file
qjar -o mylib.qar src/math.js

# Đóng gói nhiều file
qjar -o mylib.qar src/math.js src/utils.js

# Đóng gói cả thư mục
qjar -o mylib.qar src/
```

## Cấu trúc QAR file

QAR file chứa:
- **Magic header**: "QAR\x01"
- **Version**: Phiên bản định dạng QAR
- **Manifest**: JSON chứa thông tin về các entry
- **Entries**: Mỗi entry chứa:
  - Path trong archive
  - Bytecode (đã compile)
  - Source code (để fallback)

## Sử dụng QAR trong code C

```c
#include "quickjs-libc.h"

// Đăng ký QAR file
js_register_qar_file(ctx, "mylib.qar", NULL);

// Module loader sẽ tự động tìm trong QAR files
// Khi import "math.js", nó sẽ load từ QAR
```

## Sử dụng QAR trong JavaScript

```javascript
// Import module từ QAR
import { add, multiply } from 'math.js';
import { greet } from 'utils.js';

console.log(add(2, 3));
console.log(greet("World"));
```

## API Reference

### C API

#### `js_register_qar_file(JSContext *ctx, const char *qar_filename, const char *prefix)`

Đăng ký một QAR file để module loader sử dụng.

- `ctx`: JSContext
- `qar_filename`: Đường dẫn đến file QAR
- `prefix`: Prefix cho module names (NULL nếu không dùng prefix)

Returns: 0 nếu thành công, -1 nếu lỗi

#### `js_unregister_all_qar_files(JSRuntime *rt)`

Xóa tất cả QAR files đã đăng ký.

- `rt`: JSRuntime

### QAR Reader API

#### `QarFile *qar_open(const char *filename)`

Mở một QAR file để đọc.

#### `void qar_close(QarFile *qar)`

Đóng QAR file.

#### `const QarEntry *qar_find_entry(QarFile *qar, const char *path)`

Tìm entry theo path.

#### `const uint8_t *qar_entry_get_bytecode(const QarEntry *entry, size_t *len)`

Lấy bytecode của entry.

#### `const uint8_t *qar_entry_get_source(const QarEntry *entry, size_t *len)`

Lấy source code của entry.

## Ví dụ

Xem `tests/test_qar.js` và `tests/qar_test_lib/` để biết ví dụ sử dụng.

## Build

```bash
mkdir build
cd build
cmake ..
make qjar
make test_qar_load
```

## Notes

- Bytecode format phụ thuộc vào phiên bản QuickJS
- Nếu bytecode không tương thích, hệ thống sẽ tự động compile lại từ source code
- QAR files có thể được sử dụng như thư viện với import/export ES6 modules

