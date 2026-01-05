# QuickJS Archive (QAR) - Tổng quan

## Trả lời nhanh

### ✅ QAR có chứa mã nguồn không?
**Có** - Mỗi entry chứa cả source code JavaScript gốc

### ✅ QAR có chứa bytecode không?
**Có** - Mỗi entry chứa bytecode đã được compile

### ❌ WinZip có thể đọc QAR không?
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

### 1. Tạo QAR file
```bash
qjar -o mylib.qar src/math.js src/utils.js
```

### 2. Đăng ký QAR từ JavaScript (Đơn giản nhất!)
```javascript
// Chỉ cần gọi registerQar() - tự động có sẵn khi dùng js_std_add_helpers()
registerQar('mylib.qar');
```

### 3. Import và sử dụng modules
```javascript
import * as math from './src/math.js';
import { greet } from './src/utils.js';

console.log(math.add(2, 3));
console.log(greet("World"));
```

### Hoặc đăng ký từ C code (nếu cần)
```c
js_register_qar_file(ctx, "mylib.qar", NULL);
JS_SetModuleLoaderFunc(rt, NULL, js_module_loader, NULL);
```

## Load nhiều QAR files

### Không dùng prefix (tìm trong tất cả)
```c
js_register_qar_file(ctx, "mathlib.qar", NULL);
js_register_qar_file(ctx, "utilslib.qar", NULL);

// Module loader sẽ tìm trong tất cả QAR files theo thứ tự đăng ký
```

### Dùng prefix để phân biệt
```c
js_register_qar_file(ctx, "mathlib.qar", "math:");
js_register_qar_file(ctx, "utilslib.qar", "utils:");

// Trong JavaScript:
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
qjar -o qar_test.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js

# Test load
test_qar_load qar_test.qar math.js

# Test với qjs
qjs --module tests/test_qar_usage.js
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

