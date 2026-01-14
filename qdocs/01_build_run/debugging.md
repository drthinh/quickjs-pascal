# Debugging (qjsp / QuickJS Pascal)

Tài liệu này mô tả cách debug `qjsp` (host Pascal) và QuickJS engine (`libqjs`).

## 1. Hai tầng debug

### 1.1. Debug ở tầng ứng dụng (Pascal / qjsp)

Đây là các log/diagnostics do `qjsp` và các helper Pascal in ra.

- Điều khiển bằng `DebugLevel` (`--debug` hoặc lệnh REPL `.debug`).
- Log đi qua `qjs_log`.
- Hoạt động kể cả khi `libqjs` không build với `ENABLE_DUMPS`.

### 1.2. Debug ở tầng engine (QuickJS dumps)

QuickJS có hệ thống dump nội bộ, điều khiển bằng `JS_SetDumpFlags()` / `JS_GetDumpFlags()`.

- Điều khiển trong REPL bằng `.dump` (alias: `.dumpflags`).
- Chỉ có tác dụng khi `libqjs` được build với `-DENABLE_DUMPS`.

Xem thêm: `dump-flags.md`.

## 2. DebugLevel / log levels

### 2.1. Bật debug từ command line

- `qjsp --debug 0`:
  - Tắt debug (mặc định).
- `qjsp --debug 1`:
  - Bật debug mức cơ bản.
- `qjsp --debug 2`:
  - Bật debug verbose.
- `qjsp --debug 3`:
  - Bật debug verbose + tự bật một số QuickJS dumps cơ bản.
- `qjsp --debug 4`:
  - Bật debug verbose + tự bật tất cả QuickJS dumps.

### 2.2. Bật/tắt debug trong REPL

- `.debug`:
  - Hiển thị debug level hiện tại và cú pháp.
- `.debug on|off|0|1|2|3|4`:
  - Đổi debug level ngay khi đang chạy.

Gợi ý:

- `0-2`: chỉ bật log ở tầng Pascal (không tự bật QuickJS dumps).
- `3`: tự bật QuickJS dumps mức cơ bản (ví dụ bytecode final + GC + mem).
- `4`: tự bật tất cả QuickJS dumps.

Bạn vẫn có thể dùng `.dump` / `.dumpflags` để set dump flags thủ công khi cần.

### 2.3. Timestamp cho log

- `.ts`:
  - Xem trạng thái timestamp (mặc định: on).
- `.ts on|off`:
  - Bật/tắt timestamp cho log `qjs_log`.

## 3. REPL debug commands

Quy ước chung:

- Các lệnh "core" của REPL luôn bắt đầu bằng dấu `.` (ví dụ: `.help`, `.menu`, `.debug`, `.dump`, ...).
- Nếu bạn gõ thiếu dấu `.`, `qjsp` sẽ in gợi ý dạng `Hint: use ".<cmd>"` thay vì để bị `SyntaxError`.

Các lệnh dưới đây có sẵn khi đang ở `js>`.

### 3.1. Memory usage

- `.mem`
  - In thống kê memory usage của QuickJS runtime.

### 3.2. Garbage collector

- `.gc`
  - Chạy `JS_RunGC(rt)` để thu gom rác (giải phóng object JS không còn reachable).
  - Hữu ích khi bạn muốn:
    - ép GC chạy ngay để quan sát memory usage
    - kiểm tra nhanh xem có đang giữ reference ngoài ý muốn (memory leak) hay không

Output trong REPL:

- Khi chạy, `qjsp` sẽ in mô tả tác dụng:

  - `GC: Run QuickJS garbage collector to reclaim unused JS objects.`

- Sau đó báo kết quả:

  - Thành công:
    - `GC: success`
  - Thất bại (hiếm, ví dụ lỗi runtime/binding):
    - `GC: failed - <error message>`

Lưu ý:

- `.gc` chỉ đảm bảo QuickJS GC chạy; không có nghĩa là Windows/OS sẽ lập tức giảm RSS/Working Set.
- Muốn xem thống kê memory từ runtime, dùng thêm `.mem`.

### 3.3. QuickJS dump flags

- `.dump`
- `.dump on|off|<number>`

Alias:

- `.dumpflags`
- `.dumpflags on|off|<number>`

Lưu ý:

- Nếu bạn set `.dump` / `.dumpflags` khác 0 mà đọc lại vẫn ra 0, nhiều khả năng `libqjs` đang build không bật `-DENABLE_DUMPS`.

## 4. Promise rejection diagnostics

Khi debug level > 0, `qjsp` cài promise rejection tracker dạng logging.

- Unhandled Promise rejection sẽ được log qua `qjs_log` với tag `promise`.

## 5. Bật ENABLE_DUMPS cho libqjs (MinGW)

Trong repo này, script `build_qjsdll_mingw.bat` đã được cấu hình để build Release với `-DENABLE_DUMPS` thông qua `CFLAGS_RELEASE`.

Quy trình khuyến nghị:

1) Build:

- chạy `build_qjsdll_mingw.bat`

2) Đảm bảo `qjsp` load đúng DLL mới:

- `qjsp` thường load `pascal/bin/libqjs.dll` (tuỳ theo CWD/PATH).
- Copy `build-qjsdll-mingw/libqjs.dll` sang `pascal/bin/libqjs.dll` để chắc chắn dùng bản mới.

## 6. Có nên bật sanitizer flags?

Sanitizer hữu ích khi bạn nghi có bug ở tầng C/C++ (crash, memory corruption).

Khuyến nghị thực tế:

- Ưu tiên `QJS_ENABLE_ASAN` (AddressSanitizer) khi cần bắt lỗi out-of-bounds/use-after-free.
- `QJS_ENABLE_UBSAN` hữu ích để bắt undefined behavior.
- `QJS_ENABLE_TSAN` chỉ nên dùng nếu bạn có bài toán đa luồng.
- `QJS_ENABLE_MSAN` thường không thuận tiện trên Windows/MinGW.

Lưu ý:

- Sanitizer làm chương trình chậm hơn và thường không phù hợp cho build phát hành.
- Trên Windows/MinGW có thể cần runtime DLL của sanitizer.

## 7. REPL modes (ví dụ: `sh`)

`qjsp` hỗ trợ REPL modes để thay đổi prompt và map một số command sang helper JavaScript (ví dụ `sh>`).

- Bật mode:
  - `.mode sh`
  - `.mode sh on`

- Tắt mode:
  - `.mode sh off`

Quy tắc dispatch khi đang ở mode (ví dụ `sh>`):

- Nếu dòng input bắt đầu bằng `.` thì đó là lệnh core REPL (ví dụ: `.gc`, `.dump`, `.debug`, `.help`, `.menu`, `.reload`, ...).
- Nếu dòng input không bắt đầu bằng `.` thì sẽ được forward vào mode handler (ví dụ trong `sh`: `pwd`, `ls`, `cd <dir>`, `help`).

Thoát mode:

- Gõ `.js` để quay về prompt `js>`.

## 8. Shutdown hook khi thoát (rt.shutdown)

Khi `qjsp` chuẩn bị thoát, host Pascal có một bước cleanup ở tầng JavaScript: load module runtime và gọi hàm shutdown nếu có.

- `qjsp.pas` eval một module dạng:
  - `import * as rt from 'qjsp:runtime/index.js';`
  - `if (rt && typeof rt.shutdown === 'function') rt.shutdown();`

Mục đích:

- Cho các helper/runtime JS có cơ hội tự dọn dẹp (ví dụ: timers, event-loop integrations, singleton resources do runtime module quản lý).
- Cho phép các cleanup action ở JS schedule thêm microtasks/promises, sau đó `qjsp` sẽ chạy `JS_ExecutePendingJob()` để xử lý nốt trước khi `JS_FreeContext()` / `JS_FreeRuntime()`.

Chẩn đoán lỗi:

- Nếu shutdown script bị exception, `qjsp` chỉ dump error khi `DebugLevel > 0`.
- Nếu bạn nghi có leak/tài nguyên chưa đóng, bật `--debug 1` trở lên để thấy error trong giai đoạn shutdown (nếu có).
