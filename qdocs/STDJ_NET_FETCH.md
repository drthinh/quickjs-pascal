# stdjs net/fetch

## Mục tiêu

Cung cấp API `fetch()` kiểu browser/Node-lite cho QuickJS Pascal (`qjsp.exe`), dựa trên HTTP binding của Pascal.

## Import

```js
import { net } from "qjsp:index.js";
const { fetch } = net;
// hoặc
import { fetch } from "qjsp:net/fetch.js";
```

## API

### `fetch(input, init?) -> Promise<Response>`

- **input**: `string | URL` (với `URL` từ `qjsp:url/url.js`)
- **init** (optional): object
  - `method?: string` (default `"GET"`)
  - `headers?: object | Array<[name, value]>`
  - `body?: string | Uint8Array | ArrayBuffer`
  - `timeoutMs?: number`
  - `followRedirects?: boolean`

Ghi chú:
- `fetch()` luôn trả về `Promise`.
- Response body native luôn được yêu cầu dưới dạng `"arraybuffer"`.

### `class Response`

- `status: number`
- `ok: boolean` (`status` trong [200..299])
- `headers: object`
- `url: string`

Methods:
- `arrayBuffer() -> Promise<ArrayBuffer>`
- `text() -> Promise<string>` (dùng `TextDecoder`)
- `json() -> Promise<any>`

### `installFetch()`

- Nếu `globalThis.fetch` chưa có, gắn `globalThis.fetch = fetch`.
- Hàm này được gọi trong `qjsp:runtime/globals.js`.

## Cơ chế async (`HttpRequestAsync` + `PumpHttpRequests`)

Nếu runtime có các global native sau:
- `globalThis.HttpRequestAsync(method, url, headers, body, options) -> Promise<NativeResponse>`
- `globalThis.PumpHttpRequests()`

thì `fetch()` sẽ:
- Tăng bộ đếm pending
- Tạo interval ~10ms gọi `PumpHttpRequests()` để “bơm” event loop HTTP
- Giảm pending và tự clear interval khi không còn request

Nếu không có `HttpRequestAsync`, `fetch()` sẽ fallback sang `globalThis.HttpRequest(...)` (sync) và wrap bằng `Promise.resolve`.

## Ví dụ

```js
import "qjsp:runtime/globals.js";

const r = await fetch("https://example.com", { timeoutMs: 5000 });
console.log(r.status, r.ok);
console.log((await r.text()).slice(0, 80));
```

## Lỗi thường gặp

- `HttpRequest/HttpRequestAsync is not available (http_helpers not registered)`:
  - Runtime chưa register `http_helpers`/`http_async_helpers`.
  - Kiểm tra build/phiên bản `qjsp.exe` bạn đang chạy.
