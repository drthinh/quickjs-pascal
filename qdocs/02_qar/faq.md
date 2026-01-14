# QAR File - Câu hỏi thường gặp
 
 **VI/EN (important):** Trong repo này, QAR được implement bằng **Pascal**. Các ví dụ/tooling kiểu C (`qjar`, `qar.c/qar.h`, `js_register_qar_file`) là **legacy / không dùng** trong luồng hiện tại.

## 1. QAR file có chứa mã nguồn (source code) không?

**Có**, QAR file chứa cả mã nguồn JavaScript gốc.

- Mỗi entry trong QAR file chứa:
  - **Bytecode**: Code đã được compile thành bytecode QuickJS
  - **Source code**: Mã nguồn JavaScript gốc

- Source code được lưu để:
  - Fallback khi bytecode không tương thích với phiên bản QuickJS hiện tại
  - Debug và development
  - Source maps

## 2. QAR file có chứa bytecode không?

**Có**, QAR file chứa bytecode đã được compile.

- Bytecode được tạo bằng `JS_WriteObject()` với flags:
  - `JS_WRITE_OBJ_BYTECODE`
  - `JS_WRITE_OBJ_REFERENCE`

- Bytecode được load và execute trực tiếp, nhanh hơn so với compile từ source

- Nếu bytecode không tương thích, hệ thống tự động compile lại từ source code

## 3. QAR có chứa asset (ảnh/âm thanh/json...) không?

**Có**, mọi file không phải JS/dll/so/dylib được đóng gói như asset.

- Asset entry dùng `type: "asset"` trong manifest.
- `bytecode_size = 0`, dữ liệu gốc nằm ở trường `source` (payload raw bytes).
- Cờ flags: bit2 = 1 cho asset.
- JS có thể lấy payload bằng helper `GetQarAsset(filename, path)` → `ArrayBuffer`.

## 4. WinZip có thể đọc file QAR không?

**Không**, WinZip không thể đọc file QAR.

- QAR là định dạng binary tùy chỉnh, không phải ZIP format
- Magic header: `"QAR\x01"` (không phải ZIP signature `PK\x03\x04`)
- Cấu trúc file được thiết kế riêng cho QuickJS

### Công cụ không thể đọc QAR:
- ❌ WinZip
- ❌ 7-Zip
- ❌ WinRAR
- ❌ Windows Explorer (như ZIP file)

### Công cụ có thể đọc QAR:
- ✅ `qjsp` REPL (`.qar build/inspect/rebuild/code`)
- ✅ `qjsp` + helpers (`GetQarInfo`, `ExecuteQarEntry`, `GetQarAsset`) để đọc/inspect trong runtime
- ✅ Custom tools dùng Pascal units `pascal/std/qar/qar.pas` và `pascal/std/qar/qar_helpers.pas`

## 5. Làm sao để xem nội dung QAR file?

**VI:** Dùng `.qar inspect` hoặc helper trong `qjsp`.

**EN:** Use `.qar inspect` or the `qjsp` helpers.

### Cách 1: CLI (khuyến nghị) / CLI (recommended)

```bash
qjsp
js> .qar inspect mylib.qar
js> .qar code mylib.qar assets/logo.png
```

### Cách 2: Trong `qjsp` / Inside `qjsp`

```javascript
// Prints a JSON string with entries + manifest + quickjsVersion
print(GetQarInfo('mylib.qar'));

// Read asset payload as ArrayBuffer
const buf = GetQarAsset('mylib.qar', 'assets/logo.png');
print(buf.byteLength);
```

## 6. So sánh QAR với các format khác

| Đặc điểm | QAR | JAR | ZIP |
|----------|-----|-----|-----|
| Bytecode | ✅ | ✅ | ❌ |
| Source code | ✅ | ✅ | ✅ |
| Compression | ❌ | ✅ | ✅ |
| Readable by ZIP tools | ❌ | ✅ | ✅ |
| QuickJS specific | ✅ | ❌ | ❌ |
| Module support | ✅ | ✅ | ❌ |

## 7. Tại sao QAR không dùng ZIP format?

- **Performance**: Không cần decompress, load trực tiếp
- **Simplicity**: Cấu trúc đơn giản, dễ implement
- **QuickJS specific**: Tối ưu cho QuickJS bytecode format
- **Size**: Thường nhỏ hơn ZIP vì không có overhead của compression

## 8. Có thể convert QAR sang ZIP không?

**VI:** Có thể extract source/payload từ QAR rồi zip lại. Với repo này, dùng `.qar code` để lấy source entry.

**EN:** Yes. You can extract source/payload from QAR and then zip them. In this repo, use `.qar code` to print an entry's source.

Sau đó có thể zip các file đã extract.

## 9. QAR file có thể được edit không?

Có thể edit bằng cách:
1. Extract source code từ QAR
2. Edit source code
3. Tạo lại QAR file bằng `.qar build` (hoặc `.qar rebuild`)

**Không thể** edit trực tiếp QAR file như text editor vì là binary format.

## 10. Kích thước QAR file so với source files?

- QAR file thường lớn hơn tổng size của source files vì:
  - Chứa cả bytecode và source code
  - Không có compression
  - Có metadata và manifest

- Ví dụ:
  - `math.js` (source): 200 bytes
  - Bytecode: 585 bytes
  - QAR entry: ~800 bytes (bao gồm header, metadata)

## 11. QAR có hỗ trợ compression trong tương lai không?

Có thể, nhưng hiện tại không có compression để:
- Tăng tốc độ load (không cần decompress)
- Giảm độ phức tạp implementation
- Tối ưu cho use case hiện tại

Nếu cần compression, có thể:
- Compress QAR file bằng gzip sau khi tạo
- Hoặc implement compression trong QAR format (future enhancement)
