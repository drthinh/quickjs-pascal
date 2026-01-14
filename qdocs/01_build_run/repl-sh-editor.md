# REPL sh editor (nano)

Tài liệu này mô tả cách dùng editor trong REPL mode `sh`.

Trong mode này, host `qjsp.exe` sẽ **intercept** lệnh `nano <file>` và chạy `nano.exe` (bundled cùng thư mục với `qjsp.exe`).

## 1. Khi nào editor được kích hoạt

Trong REPL:

- Bật `sh` mode:

```text
js> .mode sh on
sh>
```

- Dùng lệnh sau:

```text
sh> nano <file>
```

Host sẽ chạy editor trực tiếp (không đi qua JS).

## 2. Yêu cầu

- `nano.exe` phải tồn tại cùng thư mục với `qjsp.exe`.

Nếu không tìm thấy, host sẽ báo lỗi (ví dụ: `Error: nano.exe not found: ...`).
