# Crypto module (Pascal shim)

## Tổng quan

Project này cung cấp một module `qjsp:crypto` để dùng một số primitive crypto cơ bản trực tiếp từ JS trong `qjsp.exe`.

Thiết kế hiện tại:

- **Native implementation:** Pascal (`pascal/src/modules/qjsp_crypto_shim.pas`) inject functions vào `globalThis.__qjsp_native_crypto`.
- **JS wrapper module:** `qjsp:crypto` (tương ứng `pascal/js/runtime/crypto/index.js`) re-export API từ `qjsp:crypto/native.js`.
- **Module specifier:** dùng `qjsp:crypto`.

Bạn có thể import như sau:

```js
import * as crypto from "qjsp:crypto/index.js";
```

Hoặc qua runtime tổng:

```js
import { crypto } from "qjsp:runtime/index.js";
```

## API

### 1) crypto.sha256Hex(data) -> string

Tính SHA-256 của `data` và trả về chuỗi hex lowercase.

- `data`: `ArrayBuffer` | `TypedArray` (`Uint8Array`...) | `string`
- Trả về: `string` (hex)

Notes:

- `sha256Hex("")` trả về digest chuẩn của empty input.

### 2) crypto.base64Encode(data) -> string

Encode `data` sang Base64.

- `data`: `ArrayBuffer` | `TypedArray` | `string`
- Trả về: `string` (base64)

### 3) crypto.base64Decode(str) -> ArrayBuffer

Decode Base64 string sang bytes.

- `str`: `string`
- Trả về: `ArrayBuffer`

## Ví dụ

```js
import * as crypto from "qjsp:crypto/index.js";

const h = crypto.sha256Hex("");
// e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

const b64 = crypto.base64Encode(new Uint8Array([0, 1, 2, 3]));
const out = new Uint8Array(crypto.base64Decode(b64));
```

## Files liên quan

- `pascal/src/modules/qjsp_crypto_shim.pas`
  - Implement `sha256Hex/base64Encode/base64Decode`.
  - Inject `globalThis.__qjsp_native_crypto`.
- `pascal/js/runtime/crypto/index.js`
  - Public wrapper module `qjsp:crypto`.
- `pascal/js/runtime/crypto/native.js`
  - Bridge module -> `globalThis.__qjsp_native_crypto`.
- `pascal/tests/qjsp_crypto_test.js`
  - Test script.

## Test

Trong `qjsp`:

```js
.load ../tests/qjsp_crypto_test.js
```

Kết quả mong muốn:

- In `qjsp_crypto_test.js OK`
- Không có exception nào sau đó.
