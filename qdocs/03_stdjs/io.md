# stdjs io

## Import

```js
import { io } from "qjsp:index.js";
const { path, fs } = io;
```

## path

File: `qjsp:io/path.js`

- `join(...parts)`
- `normalize(p)`
- `resolve(...parts)`
- `dirname(p)`, `basename(p)`, `extname(p)`
- `isAbsolute(p)`

## fs

File: `qjsp:io/fs.js`

Wrapper dựa trên:

- `qjs:std` (`std.loadFile`, `std.writeFile`, `std.open`)
- `qjs:os` (`os.stat`, `os.readdir`, `os.mkdir`, `os.remove`, `os.rename`)

API:

- `exists(path): boolean`
- `stat(path): object|null`
- `readTextFile(path): string`
- `readFile(path): Uint8Array`
- `writeTextFile(path, text)`
- `writeFile(path, data)`
- `mkdir(path, mode?)`
- `mkdirp(path, mode?)`
- `readdir(path): string[]`
- `remove(path)`
- `rename(oldPath, newPath)`

- `walk(dir, { recursive=true, includeDirs=false, filter? })`: iterator (`for..of` / `Array.from`)
- `walkArray(dir, opts): string[]`
- `walkFiles(dir, opts)`: iterator
- `walkDirs(dir, opts)`: iterator

- `copyFile(src, dst)`
- `copyDir(srcDir, dstDir, { overwrite=false })`

- `removeTree(path)` / `rmrf(path)`

### Ghi chú Windows newline

`writeTextFile` được implement bằng binary mode (TextEncoder -> Uint8Array) để tránh Windows tự chuyển `\n` thành `\r\n`.
