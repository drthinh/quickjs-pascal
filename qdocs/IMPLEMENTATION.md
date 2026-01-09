# QuickJS QAR Implementation Summary (Pascal-owned)

## Tổng quan / Overview

**VI:** Trong repo này, toàn bộ QAR (QuickJS Archive) đã được chuyển sang **Pascal**. Các file C `qjar.c`, `qar.c`, `qar.h` được coi là **legacy / không còn dùng** trong luồng build/runtime hiện tại.

**EN:** In this repository, the QAR (QuickJS Archive) system is **implemented and owned by Pascal**. The C files `qjar.c`, `qar.c`, `qar.h` are considered **legacy / not used** by the current build/runtime flow.

## Đã triển khai / Implemented

### 1) QAR builder + CLI tooling (Pascal)

**VI:**
- Build QAR từ file/thư mục JS + asset.
- Compile JS thành bytecode bằng QuickJS (`JS_Eval(..., COMPILE_ONLY)` + `JS_WriteObject`).
- Nén bytecode/source (miniz) và ghi manifest.
- CLI tool: `pascal/app/qar_tool.pas`.

**EN:**
- Build QAR from JS files/folders + assets.
- Compile JS into bytecode via QuickJS (`JS_Eval(..., COMPILE_ONLY)` + `JS_WriteObject`).
- Compress bytecode/source (miniz) and write a manifest.
- CLI tool: `pascal/app/qar_tool.pas`.

**Source / Nguồn:** `pascal/std/qar/qar.pas` (`BuildQar`, `InspectQarFile`, `RebuildQarFile`).

### 2) QAR reader + runtime registry (Pascal)

**VI:**
- Đọc file QAR (open/find_entry/load_data/get_bytecode/get_source).
- Đăng ký QAR runtime bằng `LoadLibrary("file.qar", "prefix:")` hoặc `RegisterQarFile(...)`.
- Module loader wrapper ưu tiên QAR registry trước, sau đó filesystem.

**EN:**
- Read QAR files (open/find_entry/load_data/get_bytecode/get_source).
- Register QAR containers at runtime via `LoadLibrary("file.qar", "prefix:")` or `RegisterQarFile(...)`.
- Module loader wrapper tries QAR registry first, then filesystem.

**Source / Nguồn:**
- Reader/format API: `pascal/std/qar/qar.pas` (`qar_open`, `qar_find_entry`, ...)
- Runtime loader + JS APIs: `pascal/std/qar/qar_helpers.pas` (`RegisterQarHelpers`, `js_module_loader_wrapper`, ...)

### 3) Tích hợp module loader (Pascal host policy)

**VI:** Module loader được cài ở chương trình Pascal (`qjsp`) bằng `JS_SetModuleLoaderFunc` và policy như sau:
- `qjsp:` import -> map tới `pascal/stdjs/...` (filesystem).
- import còn lại -> `qar_helpers.js_module_loader_wrapper` (QAR registry -> filesystem fallback).

**EN:** The module loader is installed by the Pascal host (`qjsp`) via `JS_SetModuleLoaderFunc` and uses this policy:
- `qjsp:` imports map to `pascal/stdjs/...` (filesystem).
- all other imports go through `qar_helpers.js_module_loader_wrapper` (QAR registry -> filesystem fallback).

**Source / Nguồn:** `pascal/app/qjsp.pas`, `pascal/app/qjsp_module_loader.pas`.

## Cấu trúc files / File structure

```
quickjs-master/
├── pascal/
│   ├── app/
│   │   ├── qjsp.pas                 # Host runtime (REPL + run-script)
│   │   ├── qjsp_module_loader.pas   # Policy loader: qjsp: + QAR wrapper
│   │   └── qar_tool.pas             # CLI: build/inspect/rebuild/code
│   └── std/
│       └── qar/
│           ├── qar.pas              # QAR format + build/inspect/rebuild
│           └── qar_helpers.pas      # QAR registry + JS bindings + loader wrapper
└── qdocs/
    └── IMPLEMENTATION.md            # This document
```

## Cách sử dụng / Usage

### 1) Build QAR bằng CLI tool / Build QAR via CLI tool

**VI/EN:** (chạy executable `qar_tool` sau khi build Pascal app)

```bash
qar_tool build out.qar path/to/file.js
qar_tool build out.qar path/to/folder/
qar_tool inspect out.qar
qar_tool rebuild in.qar out_new.qar
qar_tool code out.qar entry/path.js
```

### 2) Dùng QAR trong `qjsp` (JavaScript) / Use QAR from `qjsp` (JavaScript)

```javascript
// Register a QAR container (optional prefix recommended)
LoadLibrary("mylib.qar", "mylib:");

// Import from QAR using prefix notation
import { add } from "mylib:math.js";
print(add(2, 3));
```

### 3) APIs (Pascal)

**VI:** API không còn nằm trong `quickjs-libc.h`. QAR APIs chính nằm trong Pascal units.

**EN:** APIs are no longer exported via `quickjs-libc.h`. The main QAR APIs live in Pascal units.

- `pascal/std/qar/qar.pas`
  - `function BuildQar(const output_file: string; const input_files: array of string; const entry_main: string = ''; const entry_init: string = ''): cint;`
  - `function InspectQarFile(const qar_filename: string): TQarInspectionResult;`
  - `function RebuildQarFile(const input_qar: string; const output_qar: string; const entry_main: string = ''; const entry_init: string = ''): cint;`
- `pascal/std/qar/qar_helpers.pas`
  - `function RegisterQarFile(const qar_filename: string; const prefix: string): cint;`
  - `function js_module_loader_wrapper(...): PJSModuleDef;`
  - `procedure RegisterQarHelpers(ctx: PJSContext);`

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

- **VI:** Bytecode format phụ thuộc vào phiên bản QuickJS. Dùng `qar_tool inspect` để xem version/compatibility và `qar_tool rebuild` để rebuild.
- **EN:** Bytecode format depends on the QuickJS version. Use `qar_tool inspect` to view version/compatibility and `qar_tool rebuild` to rebuild.
- **VI:** Các file C `qjar.c`, `qar.c`, `qar.h` là legacy/không dùng trong luồng hiện tại.
- **EN:** The C files `qjar.c`, `qar.c`, `qar.h` are legacy/not used in the current flow.
