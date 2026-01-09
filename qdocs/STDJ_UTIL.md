# stdjs util

## Import

```js
import { util } from "qjsp:index.js";
const { Optional, collections } = util;
```

## Optional

File: `qjsp:util/optional.js`

Tạo Optional:

- `Optional.of(value)` (ném lỗi nếu null/undefined)
- `Optional.ofNullable(value)`
- `Optional.empty()`

Đọc/biến đổi:

- `isPresent()`, `isEmpty()`, `get()`
- `map(fn)`, `flatMap(fn)`, `filter(fn)`
- `orElse(x)`, `orElseGet(fn)`, `orElseThrow(fn?)`

Ví dụ:

```js
const o = Optional.ofNullable("hello")
  .map(s => s.toUpperCase());
console.log(o.get());
```

## Collections

File: `qjsp:util/collections.js`

Một số hàm:

- `range(start, endExclusive?, step?)`
- `chunk(array, size)`
- `partition(array, predicate)`
- `groupBy(iterable, keyFn)` -> `Map`
- `indexBy(iterable, keyFn)` -> `Map`
- `distinct(iterable, keyFn?)` -> `Array`
- `first(iterable, predicate?)`, `last(iterable, predicate?)`
