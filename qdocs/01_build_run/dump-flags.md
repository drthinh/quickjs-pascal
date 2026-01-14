# QuickJS Dump Flags (qjsp: `.dump`)

QuickJS có một hệ thống "dump" để in debug trace ra stdout (thường là console). Trong `qjsp`, bạn điều khiển hệ thống này bằng lệnh REPL `.dump` (alias: `.dumpflags`).

Lưu ý:

- Các lệnh "core" của REPL luôn bắt đầu bằng dấu `.`.

## 1. Cú pháp

Lệnh chính:

- `.dump`
  - In ra giá trị dump flags hiện tại.

- `.dump on`
  - Bật tất cả dump flags.

- `.dump off`
  - Tắt toàn bộ dump flags.

- `.dump <number>`
  - Set dump flags theo dạng bitmask.

Alias tương thích:

- `.dumpflags`
  - In ra giá trị dump flags hiện tại.

- `.dumpflags on`
  - Bật tất cả dump flags.

- `.dumpflags off`
  - Tắt toàn bộ dump flags.

- `.dumpflags <number>`
  - Set dump flags theo dạng bitmask.

## 2. Dump flags là bitmask

Dump flags là một số nguyên, mỗi bit tương ứng một loại dump/trace. Bạn có thể bật nhiều loại dump bằng cách cộng/OR các giá trị.

Ví dụ:

- Dump bytecode final (1) + dump GC (32) => `33`.

## 3. Một số flag thường dùng

Các giá trị này lấy theo `quickjs.h` trong repo này (QuickJS engine):

- `1` = `JS_DUMP_BYTECODE_FINAL`
  - Dump bytecode "final" sau khi compile.

- `2` = `JS_DUMP_BYTECODE_PASS2`
  - Dump bytecode pass2.

- `4` = `JS_DUMP_BYTECODE_PASS3`
  - Dump bytecode pass3.

- `8` = `JS_DUMP_BYTECODE_SPECIAL`
  - Dump bytecode special.

- `16` = `JS_DUMP_FREE`
  - Dump các sự kiện free.

- `32` = `JS_DUMP_GC`
  - Dump các sự kiện GC.

- `64` = `JS_DUMP_REACHABLE`
  - Dump reachable objects.

- `128` = `JS_DUMP_MEM`
  - Dump memory diagnostics.

## 4. Ví dụ sử dụng

### 4.1 Dump bytecode khi chạy code

1) Bật flag:

- `.dump 1`

2) Chạy code:

- `js> function f(x){ return x + 1 }`
- `js> f(41)`

Dump output sẽ xuất hiện trên console khi QuickJS compile/eval.

### 4.2 Debug module resolution

QuickJS dump flags trong repo này không có flag riêng cho module resolve. Nếu bạn cần trace loader/resolve module, ưu tiên:

- `.debug 1` hoặc `.debug 2` để bật log ở tầng Pascal (module loader `qjsp:`/`lib:`).

### 4.3 Debug Promise/async

QuickJS dump flags trong repo này không có flag riêng cho Promise. Nếu bạn cần debug Promise/async, ưu tiên:

- `.debug 1` để bật logging promise rejection tracker (Unhandled Promise rejection sẽ được log).

## 5. Lưu ý: ENABLE_DUMPS

Nếu thư viện QuickJS (`libqjs`) được build mà không bật `ENABLE_DUMPS`, thì `JS_GetDumpFlags()` sẽ luôn trả về `0` và `.dump` / `.dumpflags` sẽ không có tác dụng.

Trong `qjsp`, nếu bạn set `.dump` / `.dumpflags` khác 0 mà đọc lại vẫn là 0, chương trình sẽ cảnh báo trường hợp này.

## 6. Phân biệt `.debug` và `.dump`

- `.debug` (DebugLevel của `qjsp`)
  - Điều khiển log/diagnostics ở tầng ứng dụng Pascal: REPL commands, QAR helpers, DLL loader, đường dẫn, fallback, các bước xử lý.
  - Có thể hoạt động ngay cả khi QuickJS không build `ENABLE_DUMPS`.

- `.dump` (Dump flags của QuickJS engine)
  - Điều khiển trace ở tầng engine: module resolve/link/eval, promise, bytecode, GC...
  - Output thường rất chi tiết và dùng để debug sâu khi cần.
