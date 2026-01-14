# QuickJS Archive (QAR) Usage Guide
 
## Overview
 
**VI:** QAR (QuickJS Archive) là định dạng đóng gói tương tự Java JAR, cho phép:
- Đóng gói nhiều file JavaScript và asset thành một file QAR
- Lưu trữ bytecode (module/script) và source/payload
- Load và sử dụng như thư viện với import/export
 
**EN:** QAR (QuickJS Archive) is a packaging format (similar to Java JAR) that allows:
- Bundling multiple JavaScript files and assets into a single QAR file
- Storing bytecode (module/script) and source/payload
- Loading and using it as a library via ES module imports
 
**VI/EN (important):** Trong repo này, QAR được implement bằng **Pascal** (`pascal/std/qar/qar.pas`, `pascal/std/qar/qar_helpers.pas`). Các ví dụ/tooling kiểu C (`qjar`, `qar.c/qar.h`, `js_register_qar_file`) là **legacy / không dùng** trong luồng hiện tại.

**VI/EN (important):** Hãy dùng `qjsp` REPL với lệnh `.qar ...`.

## Quick start (không cần hardcode trong C)

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

## Tạo QAR file
 
**VI:** Dùng `qjsp` (REPL) với lệnh `.qar build` để tạo QAR file.
 
**EN:** Use `qjsp` (REPL) and `.qar build` to create QAR files.
 
```bash
# Single file
qjsp
js> .qar build mylib.qar src/math.js
 
# Multiple files
qjsp
js> .qar build mylib.qar src/math.js src/utils.js
 
# Whole directory
qjsp
js> .qar build mylib.qar src/
```

## QAR tooling trong REPL (`.qar` / `.tool` / `.verify`)

Trong `qjsp` REPL:

- `.qar` và `.tool` là cùng một toolchain.
- `.verify <file.qar>` là alias nhanh để in thông tin tương thích (inspect + compatibility message).

Các subcommand hiện có:

- `.qar info [file.qar] [--init-lib]`
- `.qar build <out.qar> [--v1|--v2|--format N] [--no-source|--omit-source] [--sign-key <file>] [--minify|--minify-safe] [--minify-script <file>] [--minify-flag <flag>] [--keep-temp] <inputs...>`
- `.qar inspect <file.qar>`
- `.qar ls <file.qar> [prefix]`
- `.qar cat <file.qar/entryPath>` hoặc `.qar cat <file.qar> <entryPath>`
- `.qar extract <file.qar> <out_dir>`
- `.qar rebuild <in.qar> <out.qar> [--sign-key <file>]`
- `.qar keygen [<out>] [--raw64 <file>] [--pem <file>]`

Lưu ý:

- `rebuild` hiện parse `--sign-key` theo dạng `... <in> <out> --sign-key <file>`.

## Signing (Ed25519)

QAR có thể nhúng chữ ký Ed25519 vào manifest, hỗ trợ key dạng:

- raw64: `seed32||pubkey32` (binary)
- PEM PKCS#8 (Ed25519)

```bash
qjsp
js> .qar keygen mykey
js> .qar build out.qar src/ --sign-key mykey.pem
js> .qar inspect out.qar
```

## JavaScript helper APIs (inside qjsp)

Trong `qjsp`, các helper sau có sẵn trong global JS environment:

- `BuildQar(outFile, inputs, opts?)`
- `RebuildQar(inFile, outFile, opts?)`
- `QarKeygen(opts)`

Ví dụ:

```javascript
// keygen
const key = QarKeygen({ pem: 'hello.pem' });

// build + sign
BuildQar('out.qar', ['src/'], { signKey: key.pem, createdBy: 'me', tool: 'qjsp', meta: { env: 'dev' } });

// rebuild + sign
RebuildQar('out.qar', 'out2.qar', { signKey: key.raw64 });
```

Options (BuildQar / RebuildQar):

- `signKey` (string)
- `createdBy` (string)
- `tool` (string)
- `meta` (object)
- `omitSource` (true/false)
- `format` (number as string)

## Cấu trúc QAR file

QAR file chứa:
- **Magic header**: "QAR\x01"
- **Version**: Phiên bản định dạng QAR
- **Manifest**: JSON chứa thông tin về các entry
- **Entries**: Mỗi entry chứa:
  - Path trong archive
  - Bytecode (đã compile)
  - Source code (để fallback)

## Sử dụng QAR trong runtime Pascal (`qjsp`) / Using QAR in the Pascal runtime (`qjsp`)
 
**VI:** `qjsp` cung cấp helper `LoadLibrary()` và module loader policy để import từ QAR.
 
**EN:** `qjsp` provides the `LoadLibrary()` helper and a module loader policy to import from QAR.

## Sử dụng QAR trong JavaScript
 
```javascript
// 1) Register a QAR container (prefix recommended)
LoadLibrary('mylib.qar', 'mylib:');
 
// 2) Import from QAR using prefix notation
import { add } from 'mylib:math.js';
import { greet } from 'mylib:utils.js';
 
console.log(add(2, 3));
console.log(greet("World"));
```

## API Reference
 
### Pascal APIs
 
**VI:** QAR APIs chính nằm trong Pascal units.
 
**EN:** The main QAR APIs live in Pascal units.
 
- `pascal/std/qar/qar.pas`
  - `BuildQar(...)`
  - `InspectQarFile(...)`
  - `RebuildQarFile(...)`
- `pascal/std/qar/qar_helpers.pas`
  - `RegisterQarFile(...)`
  - `RegisterQarHelpers(ctx)` (exposes `LoadLibrary`, `GetQarInfo`, ... to JS)

## Ví dụ

Xem `tests/test_qar.js` và `tests/qar_test_lib/` để biết ví dụ sử dụng.

## Notes
 
- **VI:** Bytecode phụ thuộc phiên bản QuickJS. Dùng `.qar inspect` để xem version/compatibility và `.qar rebuild` để rebuild.
- **EN:** Bytecode depends on the QuickJS version. Use `.qar inspect` to view version/compatibility and `.qar rebuild` to rebuild.
