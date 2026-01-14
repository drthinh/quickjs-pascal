# stdjs encoding

## Import

```js
import { encoding } from "qjsp:index.js";
// hoặc
import * as encoding from "qjsp:encoding/index.js";
```

## base64

File: `qjsp:encoding/base64.js`

- `base64EncodeBytes(input: Uint8Array|ArrayBuffer) -> string`
- `base64DecodeToBytes(b64: string) -> Uint8Array`
- `base64FromString(text: string) -> string` (TextEncoder UTF-8)
- `base64ToString(b64: string) -> string` (TextDecoder UTF-8)

## hex

File: `qjsp:encoding/hex.js`

- `hexEncode(input: Uint8Array|ArrayBuffer) -> string`
- `hexDecode(hex: string) -> Uint8Array`

## Ví dụ

```js
import { encoding } from "qjsp:index.js";

const b64 = encoding.base64FromString("hello");
console.log(b64);
console.log(encoding.base64ToString(b64));

const h = encoding.hexEncode(new TextEncoder().encode("hi"));
console.log(h);
console.log(new TextDecoder().decode(encoding.hexDecode(h)));
```
