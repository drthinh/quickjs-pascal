# QAR File - Câu hỏi thường gặp

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

## 3. WinZip có thể đọc file QAR không?

**Không**, WinZip không thể đọc file QAR.

- QAR là định dạng binary tùy chỉnh, không phải ZIP format
- Magic header: `"QAR\x01"` (không phải ZIP signature `PK\x03\x04`)
- Cấu trúc file được thiết kế riêng cho QuickJS

### Các công cụ không thể đọc QAR:
- ❌ WinZip
- ❌ 7-Zip
- ❌ WinRAR
- ❌ Windows Explorer (như ZIP file)

### Công cụ có thể đọc QAR:
- ✅ `qjar` - Công cụ tạo QAR
- ✅ `qar` API trong QuickJS - Đọc QAR programmatically
- ✅ Custom tools sử dụng QAR API

## 4. Làm sao để xem nội dung QAR file?

Sử dụng QAR API trong C:

```c
#include "qar.h"

QarFile *qar = qar_open("mylib.qar");

// Liệt kê tất cả entries
int count = qar_get_entry_count(qar);
for (int i = 0; i < count; i++) {
    const QarEntry *entry = qar_get_entry(qar, i);
    printf("Entry: %s\n", qar_entry_get_path(entry));
    printf("Type: %s\n", qar_entry_get_type(entry) ? "module" : "script");
}

// Đọc manifest
size_t manifest_len;
const char *manifest = qar_get_manifest(qar, &manifest_len);
printf("Manifest:\n%s\n", manifest);

// Đọc source code của một entry
const QarEntry *entry = qar_find_entry(qar, "math.js");
qar_entry_load_data(qar, entry);
size_t source_len;
const uint8_t *source = qar_entry_get_source(entry, &source_len);
printf("Source code:\n%.*s\n", (int)source_len, source);

qar_close(qar);
```

## 5. So sánh QAR với các format khác

| Đặc điểm | QAR | JAR | ZIP |
|----------|-----|-----|-----|
| Bytecode | ✅ | ✅ | ❌ |
| Source code | ✅ | ✅ | ✅ |
| Compression | ❌ | ✅ | ✅ |
| Readable by ZIP tools | ❌ | ✅ | ✅ |
| QuickJS specific | ✅ | ❌ | ❌ |
| Module support | ✅ | ✅ | ❌ |

## 6. Tại sao QAR không dùng ZIP format?

- **Performance**: Không cần decompress, load trực tiếp
- **Simplicity**: Cấu trúc đơn giản, dễ implement
- **QuickJS specific**: Tối ưu cho QuickJS bytecode format
- **Size**: Thường nhỏ hơn ZIP vì không có overhead của compression

## 7. Có thể convert QAR sang ZIP không?

Có thể extract source code từ QAR và tạo ZIP:

```c
// Extract source code từ QAR
QarFile *qar = qar_open("mylib.qar");
const QarEntry *entry = qar_find_entry(qar, "math.js");
qar_entry_load_data(qar, entry);

size_t source_len;
const uint8_t *source = qar_entry_get_source(entry, &source_len);

// Ghi vào file
FILE *f = fopen("math.js", "wb");
fwrite(source, 1, source_len, f);
fclose(f);

qar_close(qar);
```

Sau đó có thể zip các file đã extract.

## 8. QAR file có thể được edit không?

Có thể edit bằng cách:
1. Extract source code từ QAR
2. Edit source code
3. Tạo lại QAR file bằng `qjar`

**Không thể** edit trực tiếp QAR file như text editor vì là binary format.

## 9. Kích thước QAR file so với source files?

- QAR file thường lớn hơn tổng size của source files vì:
  - Chứa cả bytecode và source code
  - Không có compression
  - Có metadata và manifest

- Ví dụ:
  - `math.js` (source): 200 bytes
  - Bytecode: 585 bytes
  - QAR entry: ~800 bytes (bao gồm header, metadata)

## 10. QAR có hỗ trợ compression trong tương lai không?

Có thể, nhưng hiện tại không có compression để:
- Tăng tốc độ load (không cần decompress)
- Giảm độ phức tạp implementation
- Tối ưu cho use case hiện tại

Nếu cần compression, có thể:
- Compress QAR file bằng gzip sau khi tạo
- Hoặc implement compression trong QAR format (future enhancement)

