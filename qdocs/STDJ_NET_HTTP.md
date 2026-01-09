# stdjs net/http

## Mục tiêu

Cung cấp HTTP client **ổn định** không phụ thuộc `curl`, thông qua Pascal binding dùng `fphttpclient`.

## Kiến trúc

- Pascal expose global function: `HttpRequest(method, url, headers?, body?, options?)`
- JS wrapper: `qjsp:net/http.js`

## Import

```js
import { net } from "qjsp:index.js";
const { http } = net;
```

## API (JS)

- `http.request(method, url, options?)` -> `{ status, headers, body, text(), json() }`
- `http.get(url, options?)`
- `http.post(url, body, options?)`
- `http.getText(url, options?)`
- `http.getJson(url, options?)`
- `http.postJson(url, obj, options?)`

### options

- `headers`: object hoặc array `[[name, value], ...]`
- `body`: string | Uint8Array | ArrayBuffer
- `timeoutMs`: number
- `followRedirects`: boolean
- `responseType`: hiện có giá trị `"text"` để Pascal trả thêm `bodyText`

## Pascal API (native)

`HttpRequest(method, url, headers?, body?, options?)` trả về object:

- `status: number`
- `headers: object`
- `body: ArrayBuffer`
- `bodyText?: string` (khi `responseType === "text"`)

## Ví dụ

```js
import { net } from "qjsp:index.js";
const r = net.http.get("https://example.com", { responseType: "text" });
console.log(r.status);
console.log(r.text().slice(0, 60));
```

## Lưu ý

- Test HTTP cần máy có kết nối mạng.
- HTTPS có thể cần OpenSSL/SSL backend tùy môi trường FPC.
