# QuickJS Archive (QAR) - Tổng quan

## Trả lời nhanh

### QAR có chứa mã nguồn không?
**Có** - Mỗi entry chứa cả source code JavaScript gốc

### QAR có chứa bytecode không?
**Có** - Mỗi entry chứa bytecode đã được compile

### WinZip có thể đọc QAR không?
**Không** - QAR là định dạng binary tùy chỉnh, không phải ZIP

## Cấu trúc QAR File

```
QAR File
├── Header (Magic: "QAR\x01", Version)
├── Entry Count
├── Entries[]
│   ├── Path (string)
│   ├── Flags (module/script)
│   ├── Bytecode Size
│   ├── Source Size
│   ├── Bytecode Data
│   └── Source Code Data
└── Manifest (JSON)
```

## Sử dụng nhanh (Không cần hardcode trong C!)

**VI/EN (important):** Trong repo này, QAR được implement bằng **Pascal**. Các ví dụ/tooling kiểu C (`qjar`, `qar.c/qar.h`, `js_register_qar_file`) là **legacy / không dùng** trong luồng hiện tại.

### 1. Tạo QAR file
```bash
# Build with Pascal tool
qar_tool build mylib.qar src/math.js src/utils.js
```

### 2. Đăng ký QAR từ JavaScript (Đơn giản nhất!)
```javascript
// Register a QAR container (prefix recommended)
LoadLibrary('mylib.qar', 'mylib:');
```

### 3. Import và sử dụng modules
```javascript
import * as math from 'mylib:math.js';
import { greet } from 'mylib:utils.js';

console.log(math.add(2, 3));
console.log(greet("World"));
```

### Legacy (C-based) / Di sản (C)

**VI:** Các ví dụ đăng ký QAR từ C bằng `js_register_qar_file(...)` và build bằng `qjar` là **legacy** trong repo này.

**EN:** C-based registration via `js_register_qar_file(...)` and building via `qjar` are **legacy** in this repo.

## Load nhiều QAR files

### Không dùng prefix (tìm trong tất cả) / No prefix (search all)

```javascript
LoadLibrary('mathlib.qar');
LoadLibrary('utilslib.qar');
// The first match wins; prefer prefixes to avoid conflicts.
```

### Dùng prefix để phân biệt / Use prefixes to avoid conflicts

```javascript
LoadLibrary('mathlib.qar', 'math:');
LoadLibrary('utilslib.qar', 'utils:');

import * as math from 'math:math.js';
import { greet } from 'utils:utils.js';
```

## Ví dụ hoàn chỉnh

Xem các file:
- `tests/test_qar_usage.js` - Ví dụ JavaScript
- `tests/test_multiple_qar.c` - Ví dụ C với nhiều QAR files
- `qdocs/qar_guide.md` - Hướng dẫn chi tiết
- `qdocs/qar_structure.md` - Cấu trúc file chi tiết
- `qdocs/QAR_FAQ.md` - Câu hỏi thường gặp

## Test

```bash
# Tạo QAR
qar_tool build qar_test.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js

# Inspect
qar_tool inspect qar_test.qar
```

## Module Resolution

Khi có nhiều QAR files:
1. Tìm theo thứ tự đăng ký (QAR đăng ký trước được tìm trước)
2. Prefix matching (nếu có prefix, chỉ tìm trong QAR có prefix tương ứng)
3. First match wins (module đầu tiên tìm thấy được sử dụng)

## Debug Output

Khi load module, bạn sẽ thấy:
```
[QAR DEBUG] Looking for module: 'math.js'
[QAR DEBUG] Searching for entry 'math.js' in QAR file
[QAR DEBUG] Found entry for module 'math.js': math.js
[QAR DEBUG] Loading bytecode for entry: math.js, size: 585, offset: 59
[QAR DEBUG] Successfully read bytecode object for entry: math.js, tag=-3
```

Tag `-3` = `JS_TAG_MODULE` nghĩa là thành công!

