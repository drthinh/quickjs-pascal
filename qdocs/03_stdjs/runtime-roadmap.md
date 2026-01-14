# STDJ Runtime Roadmap (qjsp:*) - Kế hoạch mở rộng runtime (single-author)

Tài liệu này mô tả kế hoạch mở rộng `stdjs` / runtime JavaScript chạy trong QuickJS Pascal (`qjsp.exe`).

Mục tiêu của roadmap này là phục vụ **duy nhất tác giả phần mềm** (single-author), không tối ưu cho ecosystem bên ngoài.
Tuy vậy, vẫn cần giữ các tiêu chí:

- logic chặt chẽ
- an toàn, dễ bảo trì
- hiệu quả
- có khả năng mở rộng (cho chính tác giả)

---

## 1) Bối cảnh kỹ thuật (hiện tại)

### 1.1 Prefix và nguồn module

- `qjsp:*`
  - Module loader map vào `pascal/js/libs/*` nếu tồn tại.
  - Nếu không có thì fallback sang `pascal/js/runtime/*`.
  - Mục đích: giữ một namespace ổn định để runtime import theo đường dẫn tuyệt đối.

- `lib:*`
  - Map theo cấu hình `pascal/config/qjsp_config.json` mục `"libraries"`.
  - Dùng để mount các thư viện/feature bổ sung mà vẫn giữ được cấu trúc runtime gọn.

- Fallback loader
  - Nếu không thuộc `qjsp:`/`lib:` thì loader sẽ đi theo `qar_helpers` (QAR/filesystem), tuỳ cấu hình/build.

### 1.2 Điểm khởi tạo runtime

- Runtime globals được nạp sớm bằng import module:
  - `import 'qjsp:runtime/globals.js'`

- `globals.js` làm nhiệm vụ:
  - install polyfills cần thiết (vd TextEncoding)
  - đặt `URL`, `URLSearchParams` nếu chưa có
  - cài `fetch`
  - cài timers (`setTimeout`, `setInterval`...) nếu chưa có
  - self-check khi debug

### 1.3 Native Pascal bindings (tận dụng tối đa)

Runtime tận dụng các native helpers đăng ký trong Pascal (ví dụ):

- HTTP helpers / async HTTP helpers
- compression / zip
- qar/dll helpers
- fs watch
- spawn policy

Nguyên tắc: native cung cấp "primitives" + enforce policy; JS runtime cung cấp façade API ổn định.

---

## 2) Định nghĩa "tính năng mức runtime"

Một tính năng nên đưa vào `qjsp:*` nếu thuộc nhóm:

- **System bridge**: IO, process/spawn, http, watch, crypto, zip...
- **Runtime polyfills**: URL/TextEncoding/fetch/timers...
- **Hạ tầng vận hành**: logging/diagnostics/config
- **Concurrency primitives**: sleep/timeout/deferred/cancellation

Không nên đưa vào `qjsp:*` nếu là:

- logic nghiệp vụ/app-specific
- workflow riêng của một dự án
- script tiện ích mang tính "application" (nên là `tests/`, `examples/`, hoặc `lib:<name>`)

---

## 3) Nguyên tắc kiến trúc (để mở rộng nhanh mà không nát)

### 3.1 Public API surface

- Chỉ coi các export từ `pascal/js/runtime/index.js` là **public API**.
- Các file khác được coi là internal và có thể refactor tuỳ ý.

Checklist:

- Public API phải có tên rõ ràng, ổn định.
- Khi đổi internal, chỉ cần đảm bảo `index.js` vẫn export đúng.

### 3.2 Pattern chuẩn: Native primitive -> JS façade

- **Native Pascal**:
  - expose các hàm low-level
  - enforce policy cứng (allowed roots, timeout, max body...)
  - trả lỗi có mã/chi tiết (host error)

- **JS façade**:
  - validate input
  - normalize options + defaults
  - map lỗi native thành error thống nhất (code/details)
  - cung cấp API ergonomic (dễ dùng cho tác giả)

### 3.3 Import rule trong runtime

- Ưu tiên import tuyệt đối `qjsp:*`.
- Hạn chế/không dùng relative import `./...` trong runtime để tránh vấn đề resolve path trên Windows.

### 3.4 Policy/config là một phần của runtime

Các feature rủi ro (spawn/http/fs_watch/...) phải có policy:

- Policy được load từ `pascal/config/qjsp_config.json`.
- Native enforce policy (defense-in-depth).
- JS façade có thể fail-fast + cải thiện UX, nhưng không thay native.

---

## 4) Roadmap (milestones)

Các milestone được thiết kế theo hướng: mỗi mốc đều có output cụ thể + test + đánh giá.

### Milestone M1 - Chuẩn hoá lỗi runtime (Error model)

Mục tiêu:

- Tất cả domain runtime dùng cùng một kiểu lỗi logic.

Việc cần làm:

- Chọn một format lỗi thống nhất ở JS (ví dụ `QjspError`):
  - `name`
  - `code`
  - `message`
  - `details` (object)
- Viết helper `toQjspError(e)` hoặc wrapper để normalize lỗi.
- Áp dụng dần cho các façade quan trọng (spawn/http/fs_watch).

Checklist hoàn thành:

- [x] Có 1 file/module lỗi chung trong `qjsp:runtime/*` hoặc `qjsp:util/*`.
- [x] Các domain chính (`net`, `os`/`spawn`, `io`/`watch`) trả lỗi có `code` nhất quán.
- [x] Test có assert `code` cho các case policy reject.

### Milestone M2 - Chuẩn hoá façade cho các native helpers hiện có

Mục tiêu:

- Native giữ "primitive"; JS cung cấp API ổn định/đẹp.

Việc cần làm:

- Rà các helper native đã có:
  - http/http_async
  - spawn
  - fs_watch
  - qar/dll
  - compression/zip
- Với mỗi domain:
  - xác định API public cần export
  - thêm/chuẩn hoá `index.js` trong domain
  - đảm bảo validate input + normalize options

Checklist hoàn thành:

- [x] Mỗi domain có `index.js` export rõ.
- [x] Public export chỉ đi qua `pascal/js/runtime/index.js`.
- [x] Có test smoke cho mỗi domain (ít nhất 1 happy path + 1 error path).

### Milestone M3 - Tối ưu hoá load (lazy load + giảm overhead)

Mục tiêu:

- Runtime phình nhưng không làm startup/import chậm đáng kể.

Việc cần làm:

- `globals.js` chỉ cài các thứ nền.
- Các module nặng chuyển sang lazy import.
- Tối ưu re-export tránh import sớm không cần thiết.

Checklist hoàn thành:

- [x] `globals.js` không import các module nặng không cần thiết.
- [x] Các domain nặng có entrypoint nhẹ, lazy khi gọi.
- [ ] Có benchmark thủ công: startup/repl import `qjsp:index.js` không tăng đáng kể so với baseline.

Benchmark thủ công (gợi ý):

- Đo thời gian import `qjsp:index.js`:
  - `const t0 = Date.now(); await import('qjsp:index.js'); const dt = Date.now() - t0; console.log('import qjsp:index.js ms=', dt);`
- Đo thời gian import `qjsp:runtime/globals.js`:
  - `const t0 = Date.now(); await import('qjsp:runtime/globals.js'); const dt = Date.now() - t0; console.log('import globals ms=', dt);`
- Kiểm tra lazy `fetch` (không gọi thì không load phần net/fetch):
  - `console.log('typeof fetch=', typeof fetch);`
  - `await fetch('https://example.com').then(r => r.status).catch(e => e && e.code);`

### Milestone M4 - QAR packaging strategy (tuỳ nhu cầu)

Mục tiêu:

- Khi runtime lớn: bundling vào QAR để giảm IO và deploy dễ.

Việc cần làm:

- Xác định: runtime sẽ chạy từ filesystem, hay thường xuyên từ QAR.
- Nếu ưu tiên QAR:
  - quy ước build/runtime asset
  - đảm bảo loader vẫn resolve đúng

Checklist hoàn thành:

- [ ] Có hướng dẫn build QAR cho runtime.
- [ ] Test chạy được ở cả 2 chế độ (fs và qar nếu dùng).

---

## 5) Checklist đánh giá tiến độ (Scorecard)

Bạn có thể dùng bảng này để tự chấm theo tuần/sprint.

### 5.1 Architecture & Maintainability

- [ ] `pascal/js/runtime/index.js` phản ánh đúng public API (không export nhầm internal).
- [ ] Mỗi domain có `index.js` rõ ràng, ít export lặt vặt.
- [ ] Không có import relative `./...` trong runtime (trừ trường hợp bất khả kháng).
- [ ] Có quy ước đặt tên file/class nhất quán theo domain.

### 5.2 Safety (policy + boundary)

- [ ] Feature rủi ro có policy trong `qjsp_config.json`.
- [ ] Native enforce policy (không chỉ JS).
- [ ] Error message đủ chẩn đoán nhưng không spam (theo DebugLevel).

### 5.3 Correctness (tests)

- [ ] Mỗi feature mới có ít nhất:
  - 1 test happy-path
  - 1 test policy reject / error mapping
- [ ] Test chạy ổn trên môi trường Windows.

### 5.4 Performance

- [ ] `globals.js` không kéo theo module nặng.
- [ ] Các module nặng lazy-load.
- [ ] Khi thêm feature: kiểm tra không tăng thời gian startup rõ rệt.

### 5.5 Documentation

- [ ] Có 1 trang doc cho domain lớn (net/spawn/io/crypto/zip...).
- [ ] Cập nhật `STDJ_OVERVIEW.md` khi thêm nhóm module mới.

---

## 6) Quy trình thêm một tính năng runtime mới (template)

Khi thêm feature mới, làm theo thứ tự:

1) Chọn domain (vd `net/`, `io/`, `os/`, `crypto/`, `zip/`, `events/`...).
2) Nếu cần native:
   - thêm helper Pascal (primitive + enforce policy).
3) Viết JS façade:
   - validate input
   - normalize options
   - map error -> error model chuẩn
4) Export qua domain `index.js` và root `pascal/js/runtime/index.js`.
5) Viết tests (happy-path + error path).
6) Nếu feature ảnh hưởng globals: cân nhắc có nên đưa vào `globals.js` hay không (mặc định là không).

---

## 7) Liên kết tài liệu liên quan

- `STDJ_OVERVIEW.md`
- `QJSP_CONFIG.md`
- `DAEMON_MODE.md`
- `pascal_async_runtime.md`
- `README_QAR.md`, `QAR_FAQ.md`
- `qar_v2_spec.md`
