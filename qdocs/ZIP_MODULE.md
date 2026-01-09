# qjs:zip built-in module

## Tổng quan

`qjs:zip` là built-in native module (C) cung cấp khả năng đọc/ghi ZIP trong JavaScript, dựa trên `miniz`.

Bạn có thể import như sau:

```js
import * as zip from 'qjs:zip';
```

## API

### 1) zip.openFile(path) -> ZipArchive

Mở một file zip từ filesystem.

- `path`: string
- Trả về: `ZipArchive`

### 2) zip.open(buffer) -> ZipArchive

Mở zip từ dữ liệu trong memory.

- `buffer`: `ArrayBuffer`
- Trả về: `ZipArchive`

### 3) zip.create(entries[, level]) -> ArrayBuffer

Tạo zip trong memory từ danh sách entry.

- `entries`: Array các object `{ name, data }`
  - `name`: string
  - `data`: `ArrayBuffer` hoặc string
- `level` (optional): compression level (int). Mặc định dùng `MZ_DEFAULT_LEVEL`.
- Trả về: `ArrayBuffer` chứa zip.

## ZipArchive

`ZipArchive` là một object handle-based đại diện cho một zip đã mở.

### za.numFiles() -> number

Trả về số entry trong zip.

### za.list() -> Array

Trả về danh sách entry stat objects.

Mỗi entry có các field:

- `index`: number
- `name`: string
- `isDirectory`: boolean
- `isEncrypted`: boolean
- `isSupported`: boolean
- `method`: number
- `crc32`: number
- `compressedSize`: number
- `uncompressedSize`: number

### za.stat(indexOrName) -> Object

Lấy thông tin entry theo `index` hoặc theo `name`.

### za.read(indexOrName) -> ArrayBuffer

Giải nén và đọc nội dung entry.

### za.close() -> void

Đóng zip và giải phóng tài nguyên.

## Ví dụ

### Đọc zip từ memory

```js
import * as zip from 'qjs:zip';

const payload = 'hello from zip\n';
const zipBuf = zip.create([
  { name: 'hello.txt', data: payload },
  { name: 'dir/', data: '' },
  { name: 'dir/nested.txt', data: 'nested\n' },
]);

const za = zip.open(zipBuf);
const st = za.stat('hello.txt');
const data = za.read('hello.txt');
za.close();
```

### Đọc zip từ file

```js
import * as zip from 'qjs:zip';

const za = zip.openFile('assets.zip');
for (const e of za.list()) {
  if (!e.isDirectory) {
    const bytes = za.read(e.name);
    // bytes là ArrayBuffer
  }
}
za.close();
```

## Notes / Limitations

- `qjs:zip` hiện tập trung vào các thao tác cơ bản: list/stat/read và create zip in-memory.
- `za.read()` luôn giải nén ra memory (ArrayBuffer) nên cần cẩn thận với file rất lớn.
- Entry encrypted sẽ có `isEncrypted=true` và có thể không đọc được (miniz không hỗ trợ decrypt).
- `zip.create()` hiện là helper đơn giản để tạo zip cho use-case tooling/test.
