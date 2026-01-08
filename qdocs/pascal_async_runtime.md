# Pascal QuickJS Async Runtime Notes

## Mục tiêu

Cập nhật này giải quyết lỗi `EAccessViolation` khi chạy `.load tests/async_test.js` trong REPL Pascal và tổng hợp kiến trúc mới để xử lý `async/await`, timers và module jobs đúng cách.

## Khởi tạo runtime

1. **Tạo runtime và context** – Vẫn dùng `JS_NewRuntime`/`JS_NewContext` như trước.
2. **Cho phép runtime block** – Gọi `JS_SetCanBlock(rt, True)` ngay sau khi khởi tạo để vòng lặp QuickJS có thể chờ `os.setTimeout`, I/O và worker events. `bool` ở đây cần truyền `LongBool` (Pascal `True/False`).
3. **Đăng ký handler chuẩn** – `js_std_init_handlers`, `js_init_module_*`, `js_std_add_helpers`, `ApplyDebugSettings` giữ nguyên, bảo đảm `ts->can_js_os_poll = true` và promise rejection tracker hoạt động.

## Luồng `.load`

Trước đây `.load` ép toàn bộ nội dung về `GLOBAL`, khiến module jobs và promise bị chạy trong trạng thái không chuẩn. Luồng mới như sau:

1. **Đọc nội dung file** và phát hiện module:
   - Nếu có `import`/`export` hoặc `JS_DetectModule(...) = 1` thì đặt `eval_flags := JS_EVAL_TYPE_MODULE`.
   - Giữ `GLOBAL` cho script thuần, vẫn hỗ trợ thêm `JS_EVAL_FLAG_ASYNC` khi người dùng nhập `await` trong REPL (@pascal/main.pas#659-733, @pascal/main.pas#1335-1358).
2. **Đánh giá nội dung** bằng `JS_Eval`. Kết quả giữ trong `result_val` để đảm bảo `JS_FreeValue` đúng thời điểm.
3. **Thực thi pending jobs cho module**:
   - Dùng `pending_ctx` tách biệt khi gọi `JS_ExecutePendingJob(JS_GetRuntime(ctx), @pending_ctx)` để tránh ghi đè `ctx` chính.
   - Nếu `job_result < 0`, dump lỗi trên `pending_ctx` (nếu có) rồi dừng vòng lặp (@pascal/main.pas#757-770).
4. **Chạy vòng lặp sự kiện** – `loop_result := js_std_loop(ctx);`
   - Thành công → in `File loaded successfully`.
   - Lỗi → `js_std_dump_error(ctx)` xử lý ngoại lệ.

## Tại sao cần `pending_ctx`

QuickJS có thể trả về context khác với context gọi khi xử lý module jobs (ví dụ khi module tự đăng ký môi trường riêng). Nếu tái sử dụng biến `ctx`, REPL Pascal sẽ bị trỏ sang vùng nhớ bất hợp lệ (dẫn đến AccessViolation). Việc lưu kết quả vào `pending_ctx` giữ nguyên con trỏ gốc để vòng lặp tiếp tục an toàn.

## Error handling & debug

- **Promise rejection tracker**: `ApplyDebugSettings` sẽ cài `JS_InstallStdPromiseRejectionTracker` mặc định, hoặc bản logging khi người dùng bật debug. Điều này giúp phát hiện promise bị reject sau khi `.load`.
- **`.debug on`**: Bật debug level ≥1 để thấy log từ luồng `.load` (đường dẫn script, QAR pre-registration...).
- **Dump lỗi module/job**: Bất kỳ lỗi nào trong module job hoặc vòng lặp sẽ đi qua `js_std_dump_error` với context chính xác.

## Kiểm thử

- `.load tests/async_test.js` – chạy thành công, in log async theo thứ tự: `Starting…`, `Operation completed`, `Finished.`
- `.load` với script module có `await` top-level khác cũng sẽ đợi module jobs và timers trước khi trả về prompt.

## Hướng phát triển

- Bao phủ thêm test tự động cho `.load` với async để tránh hồi quy (có thể dùng `tests/async_test.js` thông qua harness Pascal).
- Tách logic `.load` thành hàm riêng để tái sử dụng cho CLI và REPL gọi script.
- Xem xét mapping `pending_ctx` về kiểu bản ghi để dễ mở rộng khi hỗ trợ multi-context.
