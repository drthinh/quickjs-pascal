# Hướng dẫn sử dụng QAR - Không cần hardcode trong C!

## Cách đơn giản nhất

### 1. Tạo QAR file
```bash
qjar -o qar_test.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js
```

### 2. Viết JavaScript code
```javascript
// File: app.js

// Đăng ký QAR file (tự động có sẵn!)
registerQar('qar_test.qar');

// Import và sử dụng modules
import * as math from './qar_test_lib/math.js';
import { greet } from './qar_test_lib/utils.js';

console.log(math.add(2, 3));
console.log(greet("QuickJS"));
```

### 3. Chạy với qjs
```bash
qjs --module app.js
```

**Không cần hardcode gì trong C code!** Chỉ cần đảm bảo `js_std_add_helpers()` được gọi.

## Load nhiều QAR files

```javascript
// Load nhiều QAR files
registerQar('mathlib.qar');
registerQar('utilslib.qar');

// Module loader sẽ tìm trong tất cả QAR files
import * as math from './lib/math.js';
import { greet } from './lib/utils.js';
```

## Load với prefix

```javascript
// Đăng ký với prefix
registerQar('mathlib.qar', 'math:');
registerQar('utilslib.qar', 'utils:');

// Import với prefix
import * as math from 'math:math.js';
import { greet } from 'utils:utils.js';
```

## Ví dụ files

- `test_qar_simple.js` - Ví dụ đơn giản nhất
- `test_qar_multiple.js` - Load nhiều QAR files
- `test_qar_usage.js` - Ví dụ đầy đủ

## Lưu ý

- `registerQar()` tự động có sẵn khi dùng `js_std_add_helpers()` trong C code
- QAR files phải được tạo trước khi chạy JavaScript
- Module paths trong import phải khớp với paths trong QAR file

