# stdjs (qjsp:*) - Thư viện chuẩn cho QuickJS Pascal

`stdjs` là tập các module JavaScript chạy trong QuickJS (bản Pascal `qjsp.exe`).
Các module này được import qua prefix `qjsp:` (được map tới thư mục `pascal/stdjs/`).

## Quy ước import

- Import theo prefix tuyệt đối: `qjsp:...`
- Không dùng relative import `./...` trong `stdjs` để tránh vấn đề resolve path trên Windows.

Ví dụ:

```js
import { util, io, time, concurrent, log } from "qjsp:index.js";
```

## Nhóm thư viện

- `qjsp:util/*`: Optional + utilities cho collections.
- `qjsp:io/*`: path + fs wrappers dựa trên `qjs:std`/`qjs:os`.
- `qjsp:time/*`: Instant/Duration dựa trên `Date`.
- `qjsp:concurrent/*`: sleep/withTimeout/deferred dựa trên timers.
- `qjsp:log/*`: logger + sinks.

- `qjsp:net/*`: HTTP client (Pascal binding, không phụ thuộc curl).

## Tests

Các test mẫu nằm trong `pascal/tests/`:

- `stdjs_util_test.js`
- `stdjs_io_test.js`
- `stdjs_time_concurrent_test.js`
- `stdjs_log_test.js`

- `stdjs_http_test.js` (cần internet)
