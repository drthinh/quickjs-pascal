# stdjs sh

## Mục tiêu

`qjsp:sh` cung cấp bộ helper kiểu “shell-lite”:
- Wrapper tiện dụng cho filesystem/path/process/env
- Một REPL shell mode (trong `qjsp.exe`) để gõ lệnh như `ls`, `cd`, `cat`...
- Một số builtin command xử lý text/pipeline đơn giản

## Import

```js
import * as sh from "qjsp:sh";
// hoặc
import { sh } from "qjsp:index.js";
```

## API chính (JS)

Các hàm export từ `qjsp:sh/index.js`:

- `platform`
- `fetch` (re-export từ `qjsp:net/fetch.js`)
- `download(url, outPath, opts?) -> Promise<string>`

Filesystem/Path helpers:
- `pwd() -> string`
- `cd(dir)`
- `ls(path=".", opts?) -> string[]`
  - `opts.all?: boolean` (hiện file bắt đầu bằng `.`)
  - `opts.fullPath?: boolean`
- `lsLong(path=".", opts?) -> Array<{ name, fullPath, type, size, mtime }>`
- `lsPretty(path?, opts?)` (in dạng columns)
- `lsLongPretty(path?, opts?)` (in dạng long)

- `mkdir(path, opts?)` (`opts.p|opts.parents`)
- `rm(path, opts?)` (`recursive|r|rmrf`, `force|f`, `interactive|i`)
- `mv(src, dst)`
- `cp(src, dst, opts?)` (`recursive|r|archive|a`, `force|f`, `preserve|p`)
- `touch(path)`

Text/file:
- `cat(file) -> string`
- `head(file, n=10) -> string`
- `tail(file, n=10) -> string`
- `grep(pattern, path, opts?) -> string|number`
  - `opts.recursive`, `opts.ignoreCase`, `opts.lineNumber`, `opts.count`

Search:
- `find(start=".", opts?) -> string[]`
  - `opts.maxDepth`, `opts.includeDirs`, `opts.includeFiles`, `opts.type`, `opts.name`
- `which(cmd, opts?) -> string | string[] | null`
  - `opts.all?: boolean`

Run commands:
- `run(command) -> { stdout, code }`
- `runp(command) -> number` (in stdout và trả exit code)
- `runFile(file, args?, opts?) -> { stdout, code }`

REPL adapter:
- `repl(line)`
  - Dùng trong `qjsp.exe` khi bật `.sh on`: map input line thành builtin/pipeline/system command.

## Editor (vi/nano/edit) trong sh mode

Trong `qjsp.exe`, khi đang ở `sh>` mode, các lệnh `vi <file>`, `nano <file>`, `edit <file>` sẽ được host intercept và chạy editor Pascal line-based (Unicode/IME-friendly).

Xem chi tiết:

- `qdocs/REPL_SH_EDITOR.md`

## Builtin commands hỗ trợ trong pipeline

Builtin router nằm ở `qjsp:sh/builtins.js` và được `repl()` dùng cho pipe/redirect.

Các builtin chính:
- `pwd`, `echo`
- `ls`, `cat`, `head`, `tail`
- `grep`, `find`
- `sed` (chỉ hỗ trợ `s///`)
- `awk` (chỉ hỗ trợ `{print ...}` dạng đơn giản)
- `wc`, `sort`, `uniq`, `cut`, `tr`, `tee`, `xargs`
- `which`, `run`
- `basename`, `dirname`, `realpath`, `stat`
- `env`, `export`, `unset`
- `sleep`, `date`, `clear`, `rmdir`, `mktemp`
- `ps`, `kill`, `ln`
- `wget`/`curl` (bản builtin dùng `qjsp:net/http.js` khi có; hỗ trợ rất tối thiểu)

## Ví dụ

```js
import * as sh from "qjsp:sh";

console.log(sh.pwd());
console.log(sh.ls(".").slice(0, 5));

const txt = sh.grep("TODO", "./qdocs", { recursive: true, lineNumber: true });
console.log(txt);

await sh.download("https://example.com", "./example.html");
```

## Lưu ý

- `repl()` có hỗ trợ pipe/redirect ở mức “lite”; không nhằm mục tiêu tương thích hoàn toàn bash/cmd.
- `touch()` trên `win32` có thể không update mtime (chỉ tạo file nếu chưa có).
