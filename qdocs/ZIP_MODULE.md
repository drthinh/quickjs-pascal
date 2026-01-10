# ZIP module (Pascal shim)

## Tổng quan

Upstream QuickJS đã loại bỏ `js_init_module_zip`/`qjs:zip` (miniz). Trong project này, `zip` được cung cấp lại bằng shim Pascal để các script vẫn có thể dùng ZIP.

Thiết kế hiện tại:

- **Native implementation:** Pascal (`pascal/std/qjsp_zip_shim.pas`) inject functions vào `globalThis.__qjsp_native_zip`.
- **JS wrapper module:** `qjsp:zip` (tương ứng `pascal/stdjs/zip/index.js`) re-export API từ `qjsp:zip/native`.
- **Module specifier:** dùng `qjsp:zip` (không hardcode mapping trong module loader).

Bạn có thể import như sau:

```js
import * as zip from 'qjsp:zip';
```

`qjsp:` sẽ được `qjsp_module_loader` map vào thư mục `pascal/stdjs/`.

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
- `level` (optional): hiện chưa dùng (shim đang tạo ZIP kiểu store/không nén).
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
import * as zip from 'qjsp:zip';

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
import * as zip from 'qjsp:zip';

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

- Shim hiện tập trung vào các thao tác cơ bản: list/stat/read và create zip in-memory.
- `za.read()` luôn giải nén ra memory (ArrayBuffer) nên cần cẩn thận với file rất lớn.
- `zip.create()` hiện là helper đơn giản để tạo zip cho use-case tooling/test.

## Files liên quan

- `pascal/std/qjsp_zip_shim.pas`
  - Implement `open/openFile/create` + `ZipArchive` methods.
  - Inject `globalThis.__qjsp_native_zip`.
- `pascal/stdjs/zip/index.js`
  - Public wrapper module `qjsp:zip`.
- `pascal/stdjs/zip/native.js`
  - Bridge module `qjsp:zip/native` -> `globalThis.__qjsp_native_zip`.
- `pascal/tests/zip_test.js`
  - Test script (đã đổi sang `import 'qjsp:zip'`).

## Các bug quan trọng đã fix (post-mortem)

### 1) Sai ABI của `JS_GetLength`/`JS_SetLength`

Trong `quickjs.h`, chữ ký đúng:

```c
int JS_GetLength(JSContext *ctx, JSValueConst obj, int64_t *pres);
int JS_SetLength(JSContext *ctx, JSValueConst obj, int64_t len);
```

Ban đầu Pascal binding khai báo sai (trả về length trực tiếp), dẫn đến:

- `zip.create` tạo zip buffer sai (rất nhỏ)
- `zip.open` đọc sai số entry

Fix:

- `pascal/std/quickjs_core.pas` + `pascal/std/quickjs.pas`: sửa chữ ký
- Update call sites để dùng `len64` out-param (không dùng giá trị return như length).

Các vị trí bị ảnh hưởng trực tiếp bởi semantics mới:

- `pascal/std/qjsp_zip_shim.pas`: dùng `JS_GetLength` để duyệt `entries` trong `zip.create`.
- `pascal/std/net/http_helpers.pas`: parse headers dạng mảng `[[k,v], ...]`.
- `pascal/std/net/http_async_helpers.pas`: tương tự cho async.

Lưu ý:

- Return value của `JS_GetLength`/`JS_SetLength` là **mã lỗi** (`0` là OK). Giá trị length nằm trong tham số `pres`.
- Nếu binding sai chữ ký, các module dùng length sẽ có hành vi “ngẫu nhiên” (đặc biệt khi iterate mảng).

### 2) Sai `cdOfs` khi ghi EOCD trong `zip.create`

EOCD cần ghi `cdOfs` = offset của central directory.

Fix:

- Lưu `centralOfs := Length(outBuf)` **trước** khi append `central`.
- Ghi đúng `cdOfs` vào EOCD để các zip tool có thể locate central directory.

### 3) Leak exception khi probe TypedArray

`JS_GetTypedArrayBuffer` có thể throw `TypeError: not a TypedArray` nếu giá trị không phải TypedArray.

Triệu chứng:

- Test logic chạy đúng nhưng cuối cùng vẫn thấy exception bị in ra (do exception “kẹt” trong context).

Fix:

- Nếu probe TypedArray trả `JS_EXCEPTION`, cần consume exception (lấy và free) trước khi fallback sang đường parse khác (string/ArrayBuffer).

## Test

Trong `qjsp`:

```js
.debug 2
.load ../tests/zip_test.js
```

Kết quả mong muốn:

- In `zip_test OK`
- Không có exception nào sau đó.
