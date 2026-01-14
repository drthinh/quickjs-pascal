# stdjs os

## Import

```js
import { os } from "qjsp:index.js";
const { path, env, process, system } = os;
// hoặc
import * as os2 from "qjsp:os/index.js";
```

## os/path

File: `qjsp:os/path.js`

- `sep` (hiện là `"\\"`)
- `split(p) -> string[]`
- `isUNC(p) -> boolean`
- `toPosix(p)`, `toWin(p)`
- `isAbsolute(p) -> boolean`
- `normalize(p)`
- `join(...parts)`
- `dirname(p)`, `basename(p, ext?)`, `extname(p)`
- `resolve(...parts)`
- `parse(p) -> { root, dir, base, ext, name }`
- `format(obj)`
- `relative(from, to)`

## os/env

File: `qjsp:os/env.js`

- `get(name, defaultValue?) -> string|any`
- `set(name, value, overwrite=true)`
- `unset(name)`

## os/process

File: `qjsp:os/process.js`

- `argv: any[]` (lấy từ `globalThis.scriptArgs` hoặc `globalThis.args`)
- `cwd() -> string`
- `chdir(path)`
- `exit(code?)`
- `sleep(ms)` (dùng `os.sleep` hoặc `os.usleep`)

## os/system

File: `qjsp:os/system.js`

- `platform: string` (từ `qjs:os.platform`)
- `arch: string` (từ env vars như `PROCESSOR_ARCHITECTURE`)
- `hostname: string` (từ env vars hoặc gọi `hostname` qua `std.popen`)
- `homedir() -> string`
- `tmpdir() -> string`

## os/exec

File: `qjsp:os/exec.js`

- `exec(command) -> { stdout: string, code: number }`
  - Ưu tiên `std.popen(command, "r")` để lấy stdout.
  - Nếu không có `std.popen` thì fallback `os.exec([command])` (không có stdout).
- `execFile(file, args?, opts?) -> { stdout, code }`
  - `opts.shell?: boolean` (nếu true: build command line + chạy qua `exec()`)
  - Nếu có `os.exec`: chạy dạng argv (không stdout).

## Ví dụ

```js
import { os } from "qjsp:index.js";

console.log(os.process.cwd());
console.log(os.system.platform, os.system.arch);

os.env.set("FOO", "bar");
console.log(os.env.get("FOO"));

const r = os.exec.exec("echo hello");
console.log(r.code, r.stdout);
```
