# stdjs config

## Import

```js
import { config } from "qjsp:index.js";
// hoặc
import * as config from "qjsp:config/index.js";
```

## merge

File: `qjsp:config/merge.js`

- `deepMerge(target, source) -> any`
  - Nếu cả `target` và `source` là plain object: merge đệ quy.
  - Trường hợp khác: trả về `source`.
- `deepMergeAll(...objects) -> object`
  - Merge nhiều object theo thứ tự.
  - Bỏ qua `null/undefined`.
  - Ném lỗi nếu gặp giá trị không phải plain object.

## load

File: `qjsp:config/load.js`

- `loadJsonFile(path, options?) -> object | null`
  - `options.optional?: boolean` (nếu file không tồn tại thì trả `null`)
  - `options.allowEmpty?: boolean` (file rỗng -> `{}` thay vì lỗi)
- `loadAndMergeJsonFiles(paths: string[], options?) -> object`
  - `options.optional?: boolean`
  - `options.allowEmpty?: boolean`
  - `options.merge?: "shallow" | "deep"` (default deep)

## Ví dụ

```js
import { config } from "qjsp:index.js";

const a = config.loadJsonFile("./a.json", { optional: true });
const b = config.loadJsonFile("./b.json", { optional: true });
const merged = config.deepMergeAll(a || {}, b || {});

const merged2 = config.loadAndMergeJsonFiles(["./a.json", "./b.json"], { optional: true });
console.log(merged2);
```
