# Hướng dẫn sử dụng QAR - Không cần hardcode trong C!

**VI/EN (important):** Trong repo này, QAR được implement bằng **Pascal**. Các ví dụ/tooling kiểu C (`qjar`, `qar.c/qar.h`, `js_register_qar_file`) là **legacy / không dùng** trong luồng hiện tại.

## Cách đơn giản nhất

### 1. Tạo QAR file
```bash
qjsp
js> .qar build qar_test.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js
```

Nếu cần ký (sign) QAR:

```bash
qjsp
js> .qar keygen mykey
js> .qar build qar_test.qar tests/qar_test_lib/ --sign-key mykey.pem
```

### 2. Viết JavaScript code
```javascript
// File: app.js

// Đăng ký QAR file (prefix recommended)
LoadLibrary('qar_test.qar', 'qar:');

// Import và sử dụng modules (prefix notation)
import * as math from 'qar:math.js';
import { greet } from 'qar:utils.js';

console.log(math.add(2, 3));
console.log(greet("QuickJS"));
```

### 3. Chạy với qjsp
```bash
qjsp app.js
```

**VI:** Không cần hardcode gì trong C. Chạy bằng `qjsp` là đủ.

**EN:** No C hardcoding is required. Running with `qjsp` is enough.

## Load nhiều QAR files

```javascript
// Load nhiều QAR files
LoadLibrary('mathlib.qar', 'math:');
LoadLibrary('utilslib.qar', 'utils:');

// Module loader sẽ tìm trong tất cả QAR files (first match wins)
// Prefer prefixes to avoid conflicts.
import * as math from 'math:math.js';
import { greet } from 'utils:utils.js';
```

## Load với prefix

```javascript
// Đăng ký với prefix
LoadLibrary('mathlib.qar', 'math:');
LoadLibrary('utilslib.qar', 'utils:');

// Import với prefix
import * as math from 'math:math.js';
import { greet } from 'utils:utils.js';
```

## Ví dụ files

- `test_qar_simple.js` - Ví dụ đơn giản nhất
- `test_qar_multiple.js` - Load nhiều QAR files
- `test_qar_usage.js` - Ví dụ đầy đủ

## Lưu ý

- `LoadLibrary()` tự động có sẵn khi dùng `js_std_add_helpers()` trong C code
- QAR files phải được tạo trước khi chạy JavaScript
- Module paths trong import phải khớp với paths trong QAR file

