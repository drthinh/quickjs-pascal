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
- Tooling entrypoint: `qjsp` REPL (`.qar ...`).

**EN:**
- Build QAR from JS files/folders + assets.
- Compile JS into bytecode via QuickJS (`JS_Eval(..., COMPILE_ONLY)` + `JS_WriteObject`).
- Compress bytecode/source (miniz) and write a manifest.
- Tooling entrypoint: `qjsp` REPL (`.qar ...`).

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
│   │   └── (legacy cli)             # build/inspect/rebuild/code
│   └── std/
│       └── qar/
│           ├── qar.pas              # QAR format + build/inspect/rebuild
│           └── qar_helpers.pas      # QAR registry + JS bindings + loader wrapper
└── qdocs/
    └── 04_internals/implementation.md  # This document
```

## Cách sử dụng / Usage

### 1) Build QAR bằng CLI tool / Build QAR via CLI tool

**VI/EN:** (dùng `qjsp` REPL với lệnh `.qar ...`)

```bash
qjsp
js> .qar build out.qar path/to/file.js
js> .qar build out.qar path/to/folder/
js> .qar inspect out.qar
js> .qar rebuild in.qar out_new.qar
js> .qar code out.qar entry/path.js
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

- **VI:** Bytecode format phụ thuộc vào phiên bản QuickJS. Dùng `.qar inspect` để xem version/compatibility và `.qar rebuild` để rebuild.
- **EN:** Bytecode format depends on the QuickJS version. Use `.qar inspect` to view version/compatibility and `.qar rebuild` to rebuild.
- **VI:** Các file C `qjar.c`, `qar.c`, `qar.h` là legacy/không dùng trong luồng hiện tại.
- **EN:** The C files `qjar.c`, `qar.c`, `qar.h` are legacy/not used in the current flow.

## QAR Compatibility + Cache Strategy (Bytecode fallback)

### Mục tiêu / Goal

**VI:** QAR có thể chứa cả `bytecode` và `source` cho cùng một entry. Mục tiêu là:
- Chạy nhanh khi bytecode tương thích.
- Vẫn chạy được khi bytecode không tương thích (do QuickJS version/build khác nhau) bằng cách fallback sang `source`.

**EN:** A QAR entry may store both `bytecode` and `source`. The goal is:
- Fast startup when bytecode is compatible.
- Still runnable when bytecode is incompatible (different QuickJS version/build) by falling back to `source`.

### Fallback hành vi runtime / Runtime fallback behavior

**VI:** Runtime loader có thể áp dụng policy:
- Thử load bytecode bằng `JS_ReadObject(..., JS_READ_OBJ_BYTECODE ...)`.
- Nếu fail (exception), log lỗi (khi `DebugLevel > 0`), clear exception, rồi compile lại từ `source` bằng `JS_Eval(..., JS_EVAL_FLAG_COMPILE_ONLY ...)`.
- Sau khi compile thành công, có thể tạo bytecode mới bằng `JS_WriteObject(..., JS_WRITE_OBJ_BYTECODE ...)` để dùng cho lần load sau.

**EN:** A recommended runtime policy:
- Try bytecode via `JS_ReadObject(..., JS_READ_OBJ_BYTECODE ...)`.
- On failure (exception), log (when `DebugLevel > 0`), clear exception, then compile from `source` via `JS_Eval(..., JS_EVAL_FLAG_COMPILE_ONLY ...)`.
- After a successful compile, optionally regenerate bytecode via `JS_WriteObject(..., JS_WRITE_OBJ_BYTECODE ...)` for future loads.

### Cache theo “JIT-like” / JIT-like caching

#### 1) Cache trong một session (in-process)

**VI:** Nếu “dùng nhiều lần” nghĩa là nhiều `import` trong cùng một process, chỉ cần cache RAM:
- Sau lần fallback đầu tiên, bytecode mới được giữ trong bộ nhớ và các lần load sau không phải compile lại.

**EN:** If “used many times” means repeated imports within the same process, an in-memory cache is sufficient:
- After the first fallback, the regenerated bytecode is kept in RAM and subsequent loads do not recompile.

#### 2) Cache persist giữa các lần chạy (across sessions)

**VI:** Nếu chương trình thường xuyên khởi động lại (CLI chạy ngắn nhưng chạy lặp lại), cache persist có thể đáng giá. Có hai hướng:

- **(A) Per-entry bytecode cache files (khuyến nghị thực dụng):**
  - Lưu bytecode đã rebuild ra thư mục cache theo key gồm `quickjs_version` + hash của QAR/manifest + `entry_path`.
  - Lần sau chạy: thử load cache trước; nếu fail thì fallback từ source và cập nhật cache.
  - Ưu điểm: đơn giản, dễ invalidate, không cần build lại toàn bộ QAR.

- **(B) Build ra một cache `.qar` thứ hai (JIT-like QAR):**
  - Tạo một QAR mới chỉ chứa bytecode tương thích với runtime hiện tại.
  - Phù hợp khi muốn đóng gói 1 file duy nhất và I/O tuần tự tốt.
  - Cần cơ chế invalidate chặt (phụ thuộc QuickJS version/build flags) và atomic write để tránh hỏng cache khi crash.

**EN:** If the program restarts frequently (short-lived CLI executed repeatedly), persistent caching can help. Two approaches:

- **(A) Per-entry bytecode cache files (practical recommendation):**
  - Store regenerated bytecode to a cache directory keyed by `quickjs_version` + QAR/manifest hash + `entry_path`.
  - Next run: try cache first; on failure fallback to source and refresh cache.
  - Pros: simpler, easier invalidation, no need to rebuild the whole QAR.

- **(B) Generate a second cache `.qar` (JIT-like QAR):**
  - Produce a new QAR containing bytecode compatible with the current runtime.
  - Useful if you want a single cache artifact and sequential I/O.
  - Requires strict invalidation (QuickJS version/build flags) and atomic write to avoid corrupt caches.

### Khuyến nghị / Recommendation

**VI:**
- Ưu tiên cache RAM (in-process) trước.
- Nếu cần persist giữa runs: bắt đầu với per-entry cache (A). Chỉ chuyển sang cache `.qar` (B) khi thực sự cần 1 file duy nhất.

**EN:**
- Prefer in-process RAM caching first.
- If you need persistence across runs: start with per-entry cache (A). Move to a cache `.qar` (B) only when a single cache artifact is required.
