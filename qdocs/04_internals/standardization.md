
# Những việc nên làm thêm để `stdjs` logic, thống nhất, “đẹp” hơn

Dưới đây là các cải tiến **có tác động rõ rệt** (và phù hợp hướng “Java-core-ish” mà bạn chọn), chia theo nhóm.

## 1) Chuẩn hoá “API surface” (tên, exports, phân tầng)
- **Một convention xuyên suốt**
  - Modules kiểu package: `qjsp:net/*`, `qjsp:io/*`, `qjsp:url/*`, `qjsp:sh/*`
  - Class-style (Java-like): [Files](cci:2://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/io/Files.js:2:0-38:1), [Paths](cci:2://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/io/Paths.js:2:0-30:1), `URL`, `URLSearchParams`
  - Function-style (Node/scripting): `io.fs.*`, `io.path.*`, `net.http.*`
- **Tách rõ 2 lớp**
  - **Low-level** (gần hệ thống): [io/fs.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/io/fs.js:0:0-0:0), [net/http.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/net/http.js:0:0-0:0) (có thể sync), `os/*`
  - **High-level** (user-facing): [net/fetch.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/net/fetch.js:0:0-0:0), [io/Files.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/io/Files.js:0:0-0:0), [io/Paths.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/io/Paths.js:0:0-0:0), `sh/*`
- **Re-export có chủ đích**
  - `qjsp:index.js` nên là “public API”: export những thứ bạn cam kết support dài hạn.
  - Những thứ experimental để dưới `qjsp:internal/*` hoặc không export từ index.

## 2) Thống nhất error handling + return shape
- **Một kiểu lỗi chung cho IO/NET**
  - Ví dụ: mọi API high-level throw `Error` với message chuẩn: `module:function: ...`
  - Low-level có thể trả `null`/`errno` nhưng high-level nên normalize.
- **HTTP response shape**
  - [net/http.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/net/http.js:0:0-0:0) và [net/fetch.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/net/fetch.js:0:0-0:0) hiện trả shape khác nhau (một cái `{text(), json()}`, một cái [Response](cci:2://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/net/fetch.js:16:0-37:1)).
  - Nên quyết định:
    - hoặc giữ khác nhau (http=sync low-level, fetch=web-like)
    - hoặc làm adapter để `http.request` trả gần giống [fetch](cci:1://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/net/fetch.js:66:0-115:1) (ít nhất `ok`, `statusText` nếu có)

## 3) Async model: “pump pattern” thành chuẩn của runtime
Bạn đang có 2 dạng:
- `fs_watch` dùng `PumpWatchEvents()` + `setInterval`
- `http_async` dùng `PumpHttpRequests()` + `setInterval`

Để **đẹp và nhất quán**, nên:
- Tạo **một module runtime** kiểu `qjsp:runtime/pump.js` quản lý:
  - đăng ký các pump callbacks
  - start/stop timer theo reference count
- Tất cả async-native (watch, http, sau này websocket…) đều đăng ký vào đó.
=> Tránh mỗi module tự tạo timer riêng và dễ gây “stuck”.

## 4) “Exit clean” và lifecycle (rất quan trọng)
Bạn vừa gặp case chương trình không thoát: đây là dấu hiệu thiếu lifecycle.
- Nên có:
  - `qjsp:runtime/shutdown()` hoặc `globalThis.__qjspShutdown()`
  - dừng pump timers
  - shutdown threadpool (http async workers)
- Và [qjsp.pas](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/app/qjsp.pas:0:0-0:0) gọi shutdown khi sắp thoát (hoặc trước `js_std_loop` kết thúc).

## 5) Docs + tests: chuẩn hoá như một “standard library” thật
Bạn đã có `qdocs/` khá tốt. Để “đẹp” hơn:
- **Bổ sung bảng mapping**
  - `net/fetch` ~ `curl/wget`
  - `io/Files` ~ Java NIO `Files.*`
  - `sh` ~ busybox-lite

| stdjs | Tương đương | Ghi chú / ví dụ |
|---|---|---|
| `qjsp:net/fetch.js` (`fetch(url, init)`) | `curl` / `wget` | Download text: `await fetch(url).then(r => r.text())` ~ `curl url` / `wget -qO- url` |
| `qjsp:sh/index.js` (`sh.download(url, outPath, opts)`) | `wget -O <file>` / `curl -o <file>` | Download file: `await sh.download(url, 'out.bin')` |
| `qjsp:io/Files.js` (`Files.readAllBytes(p)`) | Java NIO `Files.readAllBytes(Path)` | Đọc bytes từ file |
| `qjsp:io/Files.js` (`Files.readString(p)`) | Java NIO `Files.readString(Path)` | Đọc text từ file |
| `qjsp:io/Files.js` (`Files.write(p, data)`) | Java NIO `Files.write(Path, bytes)` | Ghi bytes |
| `qjsp:io/Files.js` (`Files.writeString(p, text)`) | Java NIO `Files.writeString(Path, text)` | Ghi text |
| `qjsp:io/Files.js` (`Files.createDirectories(p)`) | Java NIO `Files.createDirectories(Path)` | Tạo thư mục (mkdir -p) |
| `qjsp:sh/*` (builtins như `cat`, `grep`, `find`, `which`, `wget`, `curl`, ...) | busybox-lite | Mục tiêu: scripting tiện như busybox nhưng chạy trong JS, có thể gọi trực tiếp `sh.repl()` |
- **Mỗi module có 1 test file**
  - bạn đã có [stdjs_http_test.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/tests/stdjs_http_test.js:0:0-0:0), thêm [stdjs_fetch_test.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/tests/stdjs_fetch_test.js:0:0-0:0) (đã có)
  - thêm `stdjs_url_test.js` (URL parse/resolve/searchParams)
  - thêm `stdjs_sh_wget_curl_test.js` (chạy builtin trực tiếp qua [sh.repl()](cci:1://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/sh/index.js:1093:0-1493:1))

## 6) Code style (nhỏ nhưng tạo cảm giác “chuẩn”)
- Đặt helper nội bộ thống nhất: [_toStr](cci:1://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/sh/index.js:28:0-30:1), `_normalizeOptions`, `_assert*`
- Các module có [index.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/index.js:0:0-0:0) export rõ ràng
- Hạn chế “magic globals”, nếu cần globals thì gom vào [runtime/globals.js](cci:7://file:///d:/Projects/quickjs/quickjs-master/pascal/stdjs/runtime/globals.js:0:0-0:0) (bạn đang làm đúng hướng)
