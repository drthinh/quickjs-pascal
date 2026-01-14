# Daemon mode (job runner)

Tài liệu này mô tả chế độ `--daemon` của host `qjsp.exe` để chạy các job theo kiểu automation.

## 1. Mục tiêu

- Chạy nhiều job JavaScript theo batch (thường là automation/CI).
- Mỗi job chạy trong runtime/context riêng để tránh rò state giữa job.

## 2. CLI flags

- `--daemon`
  - Bật daemon mode.
- `--daemon-in <file>`
  - File input dạng **JSONL** (mỗi dòng là một JSON object cho 1 job).
- `--daemon-out <file>`
  - File output dạng **JSONL** (mỗi dòng là một JSON object kết quả).

Nếu không truyền `--daemon-in` / `--daemon-out`:

- input sẽ đọc từ `stdin`
- output sẽ ghi ra `stdout`

Ví dụ (Windows):

```text
qjsp.exe --config config\qjsp_config.json --daemon --daemon-in jobs.jsonl --daemon-out out.jsonl
```

## 3. Format job (JSONL)

Mỗi dòng là một object JSON. Các field phổ biến:

- `id` (string)
  - ID để correlate output.
- `code` (string)
  - JavaScript code sẽ chạy (eval).
- `script` (string)
  - (optional) đường dẫn file script; nếu có thì chạy file thay vì eval `code`.

Ví dụ:

```json
{"id":"job1","code":"globalThis.__job_result = 'hello'"}
{"id":"job2","code":"globalThis.__job_result = String(1+2)"}
```

## 4. Output format (JSONL)

Mỗi job sẽ emit một dòng output JSON.

Các field phổ biến:

- `ok` (boolean)
- `id` (string)
- `result` (string) (optional)
- `error` (string) (optional)

Ví dụ:

```json
{"ok":true,"id":"job1","result":"hello"}
{"ok":false,"id":"job2","error":"job_failed"}
```

## 5. Isolation guarantee

Daemon mode được thiết kế để job sau **không nhìn thấy** global state của job trước.

Ví dụ: job1 set `globalThis.x = 123`, job2 đọc `globalThis.x` phải ra `0` hoặc `undefined`.

## 6. Test tham chiếu

- `pascal/tests/daemon_isolation_test.js`
  - Test win32, dùng `spawn()` để chạy `qjsp.exe --daemon ...`.
  - Tạo `jobs.jsonl` gồm 2 job:
    - job1 set `globalThis.x=123` và set `globalThis.__job_result`.
    - job2 đọc `globalThis.x` và assert không thấy state từ job1.

## 7. Lưu ý về policy và cwd

Trong test, toàn bộ artifact được đặt dưới `tests/tmp/...` để phù hợp với:

- spawn cwd jail (`spawn.allowed_cwd_roots`)
- fs_watch allowed roots (`fs_watch.allowed_roots`)
- http policy (`http.allowed_hosts`) nếu job dùng network

Các policy này được cấu hình qua `config/qjsp_config.json`.
