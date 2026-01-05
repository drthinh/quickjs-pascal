# QAR File Structure

## Tổng quan

QAR (QuickJS Archive) là định dạng file binary chứa các module JavaScript đã được compile thành bytecode, cùng với source code gốc để fallback.

## Cấu trúc File

### Header (16 bytes)
```
Offset  Size  Description
------  ----  -----------
0       4     Magic: "QAR\x01"
4       4     Version (uint32_t)
8       8     Manifest offset (uint64_t)
16      8     Manifest size (uint64_t)
```

### Entry Count (4 bytes)
```
20      4     Entry count (uint32_t)
```

### Entries (mỗi entry)
```
Offset  Size  Description
------  ----  -----------
0       4     Path length (uint32_t)
4       N     Path string (N bytes, không có null terminator)
N+4     4     Flags (uint32_t): bit 0 = module (1) hoặc script (0)
N+8     8     Bytecode size (uint64_t)
N+16    8     Source size (uint64_t)
N+24    B     Bytecode data (B bytes)
N+24+B  S     Source code data (S bytes)
```

### Manifest (JSON)
```
{
  "format": "qar",
  "version": 1,
  "quickjs_version": "2024-01-13",
  "entries": [
    {
      "path": "math.js",
      "type": "module",
      "bytecode_size": 585,
      "source_size": 123
    }
  ]
}
```

## Nội dung QAR File

### ✅ Có chứa Bytecode
- Mỗi entry chứa bytecode đã được compile từ JavaScript source
- Bytecode được tạo bằng `JS_WriteObject()` với flags `JS_WRITE_OBJ_BYTECODE | JS_WRITE_OBJ_REFERENCE`
- Bytecode format phụ thuộc vào phiên bản QuickJS

### ✅ Có chứa Source Code
- Mỗi entry cũng chứa source code JavaScript gốc
- Source code được lưu để:
  - Fallback nếu bytecode không tương thích với phiên bản QuickJS hiện tại
  - Debug và development
  - Source maps

### ❌ WinZip/Không thể đọc được
- QAR là định dạng binary tùy chỉnh, không phải ZIP format
- WinZip, 7-Zip, hoặc các công cụ nén khác **KHÔNG THỂ** đọc được file QAR
- Cần sử dụng công cụ `qjar` để tạo và `qar` API để đọc

## So sánh với các format khác

| Format | Bytecode | Source | Compression | Readable by ZIP tools |
|--------|----------|--------|-------------|----------------------|
| QAR    | ✅       | ✅     | ❌          | ❌                    |
| JAR    | ✅       | ✅     | ✅          | ✅                    |
| ZIP    | ❌       | ✅     | ✅          | ✅                    |

## Ví dụ tạo và đọc QAR

### Tạo QAR file
```bash
qjar -o mylib.qar src/math.js src/utils.js
```

### Đọc QAR file trong C
```c
QarFile *qar = qar_open("mylib.qar");
const QarEntry *entry = qar_find_entry(qar, "math.js");
size_t bytecode_len;
const uint8_t *bytecode = qar_entry_get_bytecode(entry, &bytecode_len);
const uint8_t *source = qar_entry_get_source(entry, &source_len);
```

## Lưu ý

1. **Bytecode Compatibility**: Bytecode chỉ tương thích với cùng phiên bản QuickJS. Nếu không tương thích, hệ thống sẽ tự động compile lại từ source code.

2. **File Size**: QAR files không được nén, nên có thể lớn hơn ZIP files tương đương.

3. **Security**: QAR files chứa executable bytecode, cần kiểm tra tính toàn vẹn trước khi load.

4. **Manifest**: Manifest ở cuối file để có thể đọc metadata mà không cần parse toàn bộ file.

