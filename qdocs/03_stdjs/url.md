# stdjs url

## Import

```js
import { url } from "qjsp:index.js";
const { URL, URLSearchParams } = url;
// hoặc
import { URL, URLSearchParams } from "qjsp:url";
```

## URLSearchParams

File: `qjsp:url/url.js`

- `new URLSearchParams(init?)`
  - `init` có thể là `string` (có/không có `?`), array of pairs, hoặc object.
- `append(name, value)`
- `delete(name)`
- `get(name) -> string|null`
- `getAll(name) -> string[]`
- `has(name) -> boolean`
- `set(name, value)`
- `sort()`
- `forEach(cb, thisArg?)`
- Iterators: `keys()`, `values()`, `entries()`, `[Symbol.iterator]()`
- `toString() -> string` (format query string; space encode bằng `+`)

## URL

File: `qjsp:url/url.js`

- `new URL(input, base?)`
  - Nếu `input` không có scheme (`http:`...) thì cần `base`.
- Fields:
  - `protocol`, `username`, `password`, `hostname`, `port`, `pathname`, `search`, `hash`
  - `searchParams: URLSearchParams`
- Getters/setters:
  - `host` (gồm `hostname[:port]`)
  - `origin`
  - `href` (get/set)
- `toString()`, `toJSON()`

## Ví dụ

```js
import "qjsp:runtime/globals.js";

const u = new URL("https://user:pass@example.com:443/a/b?x=1&y=2#h");
console.log(u.origin);
console.log(u.pathname);
console.log(u.searchParams.get("x"));

const rel = new URL("../c", u);
console.log(rel.toString());
```

## Ghi chú

- Đây là implement URL/URLSearchParams kiểu “lite”, đủ cho nhu cầu trong `stdjs` (ví dụ `fetch`).
