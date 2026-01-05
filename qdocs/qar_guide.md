# Hướng dẫn sử dụng QAR (QuickJS Archive)

## 1. Tạo QAR Files

### Tạo QAR file đơn giản
```bash
# Tạo QAR từ một file
qjar -o mathlib.qar tests/qar_test_lib/math.js

# Tạo QAR từ nhiều files
qjar -o mylib.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js

# Tạo QAR từ cả thư mục
qjar -o mylib.qar tests/qar_test_lib/
```

### Kiểm tra QAR file đã tạo
```bash
# Test load module từ QAR
test_qar_load mathlib.qar math.js
```

## 2. Sử dụng trong Code C

### Cách 1: Đăng ký từ JavaScript (Đơn giản nhất - Khuyến nghị)

Chỉ cần gọi `js_std_add_helpers()` trong C code, sau đó đăng ký QAR từ JavaScript:

```c
#include "quickjs-libc.h"

JSRuntime *rt = JS_NewRuntime();
JSContext *ctx = JS_NewContext(rt);

js_std_init_handlers(rt);
js_std_add_helpers(ctx, argc, argv);  // Cung cấp LoadLibrary()
JS_SetModuleLoaderFunc(rt, NULL, js_module_loader, NULL);

// Sau đó trong JavaScript:
// LoadLibrary('mathlib.qar');
```

### Cách 2: Đăng ký từ C code (Nếu cần kiểm soát nhiều hơn)

```c
#include "quickjs-libc.h"

JSRuntime *rt = JS_NewRuntime();
JSContext *ctx = JS_NewContext(rt);

// Đăng ký QAR file
js_register_qar_file(ctx, "mathlib.qar", NULL);

// Module loader sẽ tự động tìm modules trong QAR
JS_SetModuleLoaderFunc(rt, NULL, js_module_loader, NULL);
```

### Đăng ký nhiều QAR files

#### Cách 1: Không dùng prefix (tìm trong tất cả QAR files)
```c
// Đăng ký nhiều QAR files
js_register_qar_file(ctx, "mathlib.qar", NULL);
js_register_qar_file(ctx, "utilslib.qar", NULL);

// Module loader sẽ tìm trong tất cả QAR files theo thứ tự đăng ký
// Khi import "math.js", nó sẽ tìm trong mathlib.qar trước, sau đó utilslib.qar
```

#### Cách 2: Dùng prefix để phân biệt
```c
// Đăng ký với prefix
js_register_qar_file(ctx, "mathlib.qar", "math:");
js_register_qar_file(ctx, "utilslib.qar", "utils:");

// Trong JavaScript, sử dụng prefix:
// import * as math from 'math:math.js';
// import { greet } from 'utils:utils.js';
```

### Load và evaluate module
```c
// Load module từ QAR
JSValue module_promise = JS_LoadModule(ctx, "math.js", "math.js");

if (JS_IsException(module_promise)) {
    js_std_dump_error(ctx);
    return;
}

// Await promise để lấy module
JSValue module = js_std_await(ctx, module_promise);
JS_FreeValue(ctx, module_promise);

// Resolve dependencies
if (JS_ResolveModule(ctx, module) < 0) {
    js_std_dump_error(ctx);
    JS_FreeValue(ctx, module);
    return;
}

// Evaluate module
JSValue result = JS_EvalFunction(ctx, module);
JS_FreeValue(ctx, module);

if (JS_IsException(result)) {
    js_std_dump_error(ctx);
} else {
    JS_FreeValue(ctx, result);
}

// Cleanup
js_unregister_all_qar_files(rt);
```

## 3. Sử dụng trong JavaScript

### Bước 1: Đăng ký QAR file

```javascript
// Đơn giản nhất - không cần hardcode trong C
LoadLibrary('qar_test.qar');

// Hoặc với prefix
LoadLibrary('mathlib.qar', 'math:');
LoadLibrary('utilslib.qar', 'utils:');
```

### Bước 2: Import và sử dụng modules

```javascript
// Import từ QAR (không dùng prefix)
import * as math from './qar_test_lib/math.js';
import { greet, formatDate } from './qar_test_lib/utils.js';

// Sử dụng
console.log(math.add(2, 3));
console.log(greet("QuickJS"));
```

### Import với prefix (nếu đăng ký với prefix)
```javascript
// Nếu đăng ký: registerQar('mathlib.qar', 'math:');
import * as math from 'math:math.js';

// Nếu đăng ký: registerQar('utilslib.qar', 'utils:');
import { greet } from 'utils:utils.js';
```

### Ví dụ hoàn chỉnh đơn giản
```javascript
// File: app.js
LoadLibrary('mylib.qar');

import * as math from './lib/math.js';
import { greet } from './lib/utils.js';

console.log(math.add(2, 3));
console.log(greet("World"));
```

## 4. Ví dụ hoàn chỉnh

### File C: `example.c`
```c
#include <stdio.h>
#include "quickjs.h"
#include "quickjs-libc.h"

int main() {
    JSRuntime *rt = JS_NewRuntime();
    JSContext *ctx = JS_NewContext(rt);
    
    js_std_init_handlers(rt);
    js_std_add_helpers(ctx, 0, NULL);
    JS_SetModuleLoaderFunc(rt, NULL, js_module_loader, NULL);
    
    // Đăng ký QAR files
    js_register_qar_file(ctx, "mathlib.qar", NULL);
    js_register_qar_file(ctx, "utilslib.qar", NULL);
    
    // Load và chạy JavaScript từ file
    const char *code = "import * as math from './qar_test_lib/math.js';\n"
                       "import { greet } from './qar_test_lib/utils.js';\n"
                       "console.log('2 + 3 =', math.add(2, 3));\n"
                       "console.log(greet('World'));\n";
    
    JSValue result = JS_Eval(ctx, code, strlen(code), "<eval>", JS_EVAL_TYPE_MODULE);
    
    if (JS_IsException(result)) {
        js_std_dump_error(ctx);
    } else {
        JS_FreeValue(ctx, result);
    }
    
    js_unregister_all_qar_files(rt);
    js_std_free_handlers(rt);
    JS_FreeContext(ctx);
    JS_FreeRuntime(rt);
    
    return 0;
}
```

### File JavaScript: `example.js`
```javascript
// Import modules từ QAR
import * as math from './qar_test_lib/math.js';
import { greet, formatDate, VERSION } from './qar_test_lib/utils.js';

console.log("=== QAR Module Test ===");
console.log("Version:", VERSION);
console.log("2 + 3 =", math.add(2, 3));
console.log("5 * 4 =", math.multiply(5, 4));
console.log(greet("QuickJS"));
console.log("Date:", formatDate());
```

### Chạy ví dụ
```bash
# Tạo QAR files
qjar -o mathlib.qar tests/qar_test_lib/math.js
qjar -o utilslib.qar tests/qar_test_lib/utils.js

# Chạy với qjs
qjs --module example.js

# Hoặc compile và chạy example.c
gcc -o example example.c -lquickjs
./example
```

## 5. Module Resolution Order

Khi có nhiều QAR files đăng ký, module loader sẽ tìm theo thứ tự:

1. **QAR files đăng ký trước** được tìm trước
2. **Prefix matching**: Nếu module name có prefix, chỉ tìm trong QAR file có prefix tương ứng
3. **First match wins**: Module đầu tiên tìm thấy sẽ được sử dụng

### Ví dụ:
```c
js_register_qar_file(ctx, "lib1.qar", NULL);  // Tìm đầu tiên
js_register_qar_file(ctx, "lib2.qar", NULL);  // Tìm thứ hai
js_register_qar_file(ctx, "lib3.qar", "app:"); // Chỉ tìm khi import "app:..."
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

