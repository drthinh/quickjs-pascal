# Hướng dẫn sử dụng QAR (QuickJS Archive)

## 1. Tạo QAR Files

**VI/EN (important):** Trong repo này, QAR được implement bằng **Pascal** (`pascal/std/qar/qar.pas`, `pascal/std/qar/qar_helpers.pas`). Các ví dụ/tooling kiểu C (`qjar`, `qar.c/qar.h`, `js_register_qar_file`) là **legacy / không dùng** trong luồng hiện tại.

**VI/EN (important):** `qar_tool` đã **deprecated**. Hãy dùng `qjsp` REPL với lệnh `.qar ...`.

### Tạo QAR file đơn giản
```bash
# Tạo QAR từ một file
qjsp
js> .qar build mathlib.qar tests/qar_test_lib/math.js

# Tạo QAR từ nhiều files
qjsp
js> .qar build mylib.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js

# Tạo QAR từ cả thư mục
qjsp
js> .qar build mylib.qar tests/qar_test_lib/
```

### Kiểm tra QAR file đã tạo
```bash
# Inspect QAR
qjsp
js> .qar inspect mathlib.qar
```

## 1.1. Tạo key Ed25519 và ký (sign) QAR

QAR hỗ trợ nhúng chữ ký Ed25519 vào manifest.

### Tạo key (raw64 và PEM)

```bash
qjsp
js> .qar keygen mykey
Ed25519 key generated:
  raw64: mykey.bin
  pem:   mykey.pem
```

Hoặc chỉ định trực tiếp PEM (không cần `<out>`):

```bash
qjsp
js> .qar keygen --pem hello.pem
```

### Ký lúc build/rebuild

```bash
qjsp
js> .qar build out.qar src/ --sign-key mykey.pem
js> .qar rebuild in.qar out2.qar --sign-key mykey.bin
```

## 2. Sử dụng trong `qjsp` (Pascal runtime) / Using in `qjsp` (Pascal runtime)

**VI:** `qjsp` cung cấp helper `LoadLibrary()` và module loader policy để import module từ QAR.

**EN:** `qjsp` provides the `LoadLibrary()` helper and a module loader policy to import modules from QAR.

## 3. Sử dụng trong JavaScript

### Bước 1: Đăng ký QAR file

```javascript
// Register without prefix (searches all registered QARs)
LoadLibrary('qar_test.qar');

// Recommended: register with prefixes to avoid conflicts
LoadLibrary('mathlib.qar', 'math:');
LoadLibrary('utilslib.qar', 'utils:');
```

### Bước 2: Import và sử dụng modules

```javascript
// Import from QAR using prefix notation
import * as math from 'math:math.js';
import { greet } from 'utils:utils.js';

// Sử dụng
console.log(math.add(2, 3));
console.log(greet("QuickJS"));
```

### Ví dụ hoàn chỉnh đơn giản / Minimal complete example
```javascript
// File: app.js
LoadLibrary('mylib.qar', 'mylib:');

import * as math from 'mylib:math.js';
import { greet } from 'mylib:utils.js';

console.log(math.add(2, 3));
console.log(greet("World"));
```

## 4. Ví dụ hoàn chỉnh / Full example

### File JavaScript: `example.js`
```javascript
// Register QARs (recommended: prefixes)
LoadLibrary('mathlib.qar', 'math:');
LoadLibrary('utilslib.qar', 'utils:');

// Import modules from QAR using prefixes
import * as math from 'math:math.js';
import { greet } from 'utils:utils.js';

console.log("=== QAR Module Test ===");
console.log("2 + 3 =", math.add(2, 3));
console.log("5 * 4 =", math.multiply(5, 4));
console.log(greet("QuickJS"));
```

### Chạy ví dụ
```bash
# Tạo QAR files
qar_tool build mathlib.qar tests/qar_test_lib/math.js
qar_tool build utilslib.qar tests/qar_test_lib/utils.js

# Run with qjsp (Pascal runtime)
qjsp example.js
```

## 5. Module Resolution Order

Khi có nhiều QAR files đăng ký, module loader sẽ tìm theo thứ tự:

1. **QAR files đăng ký trước** được tìm trước
2. **Prefix matching**: Nếu module name có prefix, chỉ tìm trong QAR file có prefix tương ứng
3. **First match wins**: Module đầu tiên tìm thấy sẽ được sử dụng

### Ví dụ / Example:
```javascript
LoadLibrary('lib1.qar');  // searched first
LoadLibrary('lib2.qar');  // searched second
LoadLibrary('lib3.qar', 'app:'); // only used when importing "app:..."
```

Khi import `"math.js"`:
- Tìm trong `lib1.qar` trước
- Nếu không thấy, tìm trong `lib2.qar`
- Không tìm trong `lib3.qar` vì có prefix

Khi import `"app:math.js"`:
- Chỉ tìm trong `lib3.qar`

## 6. Debugging

Để debug module loading, kiểm tra output debug:
```
[QAR DEBUG] Looking for module: 'math.js'
[QAR DEBUG] Searching for entry 'math.js' in QAR file
[QAR DEBUG] Found entry for module 'math.js': math.js
[QAR DEBUG] Loading bytecode for entry: math.js, size: 585, offset: 59
[QAR DEBUG] Successfully read bytecode object for entry: math.js, tag=-3
```

Tag `-3` = `JS_TAG_MODULE` nghĩa là module đã được load thành công.

## 7. FAQ

### Q: QAR file có chứa source code không?
**A:** Có, QAR file chứa cả bytecode và source code gốc.

### Q: WinZip có thể đọc QAR file không?
**A:** Không, QAR là định dạng binary tùy chỉnh, không phải ZIP format.

### Q: Có thể load bao nhiêu QAR files?
**A:** Không giới hạn, có thể đăng ký nhiều QAR files.

### Q: Bytecode có tương thích giữa các phiên bản QuickJS không?
**A:** Không, bytecode phụ thuộc vào phiên bản QuickJS. Nếu không tương thích, hệ thống sẽ tự động compile lại từ source code.

### Q: Làm sao để biết module nào được load từ QAR nào?
**A:** Kiểm tra debug output hoặc sử dụng prefix để phân biệt.

