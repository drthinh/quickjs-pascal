# Tài liệu: Tái cấu trúc dự án QuickJS Pascal (QAR + Module Loader + Async Runtime)

## Mục tiêu

- Chuẩn hoá lại **kiến trúc runtime** của `qjsp` theo hướng “Pascal-owned” (thay vì phụ thuộc vào các phần legacy C).
- Tách bạch rõ:
  - **Host policy** (cách `qjsp` quyết định import/load gì, từ đâu).
  - **QAR runtime** (registry + load bytecode/source + JS APIs).
  - **Async runtime/job execution** (đảm bảo module jobs/promise/timers chạy ổn định, tránh crash).
- Giảm nhiễu log khi không bật debug, nhưng vẫn đủ chẩn đoán khi debug bật.

## Phạm vi

Tài liệu này mô tả các thay đổi tái cấu trúc đã thực hiện, trọng tâm ở:

- QAR (QuickJS Archive) chuyển ownership sang Pascal.
- Module loader policy cho `qjsp:` và `lib:`.
- Cải tiến xử lý async/module jobs trong REPL/`.load`.
- Chuẩn hoá config “libraries mounts” và hành vi chẩn đoán lỗi.

## Tổng quan kiến trúc sau tái cấu trúc

- `qjsp` là host thực thi QuickJS:
  - Khởi tạo runtime/context.
  - Cài module loader (`JS_SetModuleLoaderFunc`) bằng Pascal.
  - Cài helper JS APIs (LoadLibrary/QAR tooling, DLL helpers, stdjs, …).
  - Chạy loop + pending jobs theo đúng semantics.

- QAR được implement và vận hành trong Pascal:
  - Đọc/ghi QAR, registry QAR runtime.
  - Load module từ QAR (bytecode ưu tiên, fallback sang source khi cần).

## Thay đổi cấu trúc/ownership (Pascal-owned QAR)

### Trước đây

- Một số phần QAR/loader có thể xuất phát từ C (legacy) hoặc luồng build/runtime pha trộn.

### Hiện tại

- QAR được **sở hữu bởi Pascal**; luồng build/runtime hiện tại dựa trên Pascal units.

Các file/điểm bám:

- Runtime QAR helpers + JS bindings:
  - `pascal/src/qar/qar_helpers.pas`
- Host module loader policy:
  - `pascal/src/app/qjsp_module_loader.pas`
- Host chương trình `qjsp` (khởi tạo runtime, config, commands, wiring):
  - `pascal/src/app/qjsp.pas`

(Chi tiết tổng quan QAR: xem thêm `implementation.md`.)

## Module loader policy (host-side)

### 1) `qjsp:` namespace (std/runtime JS của host)

Mục tiêu: import theo dạng `qjsp:<path>` sẽ map về vùng JS runtime nằm trong repo, không phụ thuộc vào working directory.

Các hành vi chính:

- Chuẩn hoá đường dẫn:
  - loại bỏ prefix `/` hoặc `\` ở đầu.
  - chuẩn hoá `\` → `/`.
  - cho phép import dạng file hoặc package dir (normalize `.js`).
- Chặn path traversal và tên “đáng ngờ”:
  - từ chối nếu có `..` hoặc `:`.
- Khi resolve:
  - kiểm tra tồn tại file `.js` hoặc thư mục (thử `index.js`).
  - nếu không chắc chắn, fallback về `js_module_loader` của QuickJS.
- Bảo đảm resolve ổn định dù caller đang ở thư mục nào:
  - tạm `SetCurrentDir(pascal_root)` trước khi gọi loader.

Điểm bám:

- `pascal/src/app/qjsp_module_loader.pas` (nhánh `if Pos('qjsp:', module_name_str) = 1 then ...`).

### 2) `lib:` namespace (mount theo config)

Mục tiêu: cho phép map một prefix logical sang một folder tương đối trong repo (hoặc vùng project) thông qua config JSON `libraries`.

Luồng xử lý:

- `lib:<name>/path` → mount `<name>=<folder>`.
- Mounts được nạp từ config JSON:
  - `qjsp` đọc key `libraries` và gọi `qjsp_register_mount`.
- Loader:
  - resolve `.js` hoặc `index.js` tương tự.
  - nếu không tìm thấy, trả lỗi có “tried:” để dễ chẩn đoán.

Điểm bám:

- `pascal/src/app/qjsp.pas`:
  - `LoadQjspMountsFromFile(...)`
  - `ConfigLibraries*` (list/add, pretty output)
- `pascal/src/app/qjsp_module_loader.pas`:
  - nhánh `if Pos('lib:', module_name_str) = 1 then ...`
  - `TryLoadFromMount(...)`

### 3) Default module loader: QAR registry → filesystem fallback

Nếu không phải `qjsp:` hoặc `lib:` thì chuyển vào wrapper QAR.

Điểm bám:

- `pascal/src/app/qjsp_module_loader.pas`:
  - `Result := qar_helpers.js_module_loader_wrapper(ctx, module_name, opaque);`

## QAR runtime refactor (registry + bytecode fallback)

### 1) Registry QAR

- QAR containers được đăng ký vào một registry (`RegisteredQars`).
- Module resolver có thể:
  - tìm module theo prefix (`mylib:`) hoặc search across all registered QAR.

Điểm bám:

- `pascal/src/qar/qar_helpers.pas`:
  - `RegisteredQars`
  - `RegisterQarFile(...)`
  - `UnregisterAllQarFiles`
  - `TryLoadModuleFromRegisteredQars(...)`

### 2) Bytecode-first, fallback sang source

- Khi entry có bytecode:
  - thử `JS_ReadObject(... JS_READ_OBJ_BYTECODE ...)`.
  - nếu fail:
    - (khi debug bật) dump lỗi.
    - clear exception để tránh “leftover exception”.
    - rebuild từ source (`JS_Eval(..., JS_EVAL_FLAG_COMPILE_ONLY ...)`).
  - sau khi rebuild có thể cache bytecode mới trong memory (per-entry cache).

Điểm bám:

- `pascal/src/qar/qar_helpers.pas`:
  - `TryLoadModuleFromRegisteredQars(...)`
  - `QarRebuildBytecodeFromSource(...)`

### 3) JS APIs cho QAR

- Các hàm JS-facing (được register vào global) để:
  - load/register QAR: `LoadLibrary(...)` (Pascal implement).
  - inspect: `GetQarInfo(...)`.
  - execute entry hoặc lấy asset.
  - build/rebuild QAR từ JS.

Điểm bám:

- `pascal/src/qar/qar_helpers.pas`:
  - `js_load_qar_library`
  - `js_get_qar_info`
  - `js_execute_qar_entry`
  - `js_get_qar_asset`
  - `js_build_qar`
  - `js_rebuild_qar`

## Async runtime / module jobs refactor

Mục tiêu: sửa lỗi crash (AccessViolation) khi chạy `.load` với module async và đảm bảo jobs được drain đúng cách.

Tóm tắt thay đổi và kiến trúc:

- Bật khả năng runtime có thể block:
  - `JS_SetCanBlock(rt, True)`.
- Luồng `.load`:
  - detect module (import/export) → eval theo `JS_EVAL_TYPE_MODULE`.
  - thực thi pending jobs với **`pending_ctx` tách biệt** để tránh ghi đè context.
  - sau đó chạy `js_std_loop(ctx)`.

Tài liệu chi tiết:

- `pascal-async-runtime.md`

## Logging/Debug policy (giảm nhiễu, tăng chẩn đoán khi cần)

- Các log “noisy” (ví dụ QAR not found, bytecode mismatch) được giới hạn bởi `DebugLevel`.
- Khi debug bật, hệ thống in thêm:
  - mapping module specifier → đường dẫn.
  - các bước tìm QAR file (`FindQarFile`).
  - dump error khi bytecode load fail.

Điểm bám:

- `pascal/src/app/qjsp.pas`:
  - `ApplyDebugSettings(rt)` (promise rejection tracker theo debug level)
- `pascal/src/app/qjsp_module_loader.pas`:
  - `qjs_log.DebugMsg(...)` các mapping
- `pascal/src/qar/qar_helpers.pas`:
  - gated logging theo `qjs_log.DebugLevel`

## Tác động/migration

### 1) Import paths

- Dùng `qjsp:<path>` cho các module thuộc runtime JS của host.
- Dùng `lib:<prefix>/...` cho thư viện mount theo config.
- Import bình thường (không prefix) sẽ đi qua QAR wrapper (nếu đã `LoadLibrary(...)`) rồi fallback về filesystem.

### 2) Config libraries

- Cấu hình mounts trong config JSON:

```json
{
  "libraries": {
    "sh": "js/libs/sh"
  }
}
```

Điểm bám:

- `pascal/src/app/qjsp.pas`: `LoadQjspMountsFromFile(...)`

## Checklist kiểm thử sau tái cấu trúc

- `.load tests/async_test.js` trong REPL:
  - không còn `EAccessViolation`.
  - output theo thứ tự như tài liệu async.
- Import `qjsp:`:
  - `import ... from "qjsp:..."` resolve đúng dù CWD thay đổi.
- Import `lib:`:
  - mount có/không có → lỗi rõ ràng kèm `tried:`.
- QAR bytecode fallback:
  - bytecode mismatch → fallback sang source, không bị exception “kẹt” ảnh hưởng candidate tiếp theo.

## Tài liệu liên quan

- `implementation.md` (QAR implementation overview)
- `pascal-async-runtime.md` (async runtime refactor notes)
- `../02_qar/guide.md`, `../02_qar/structure_v1.md`, `../02_qar/signing.md` (QAR usage/format/signing)
