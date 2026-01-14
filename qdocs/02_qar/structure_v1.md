# QAR File Structure
 
 **VI/EN (important):** Trong repo này, QAR được implement bằng **Pascal**. Các ví dụ/tooling kiểu C (`qjar`, `qar.c/qar.h`, `js_register_qar_file`) là **legacy / không dùng** trong luồng hiện tại.

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
Offset        Size  Description
------        ----  -----------
0             4     Path length (uint32_t)
4             N     Path string (N bytes, không có null terminator)
N+4           4     Flags (uint32_t)
                  - bit0: 1 = module, 0 = script
                  - bit1: 1 = entry compressed (per-entry)
                  - bit2: 1 = asset (payload lưu ở "source")
N+8           8     Bytecode size (uint64_t) - nếu nén: kích thước đã nén
N+16          8     Source size (uint64_t)   - nếu nén: kích thước đã nén
N+24          8?    (chỉ khi nén) Original bytecode size (uint64_t)
N+32          8?    (chỉ khi nén) Original source size (uint64_t)
...           B     Bytecode data (B bytes, có thể 0 nếu asset)
...+B         S     Source/payload data (S bytes; với asset đây là dữ liệu gốc)
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
    },
    {
      "path": "assets/logo.png",
      "type": "asset",
      "bytecode_size": 0,
      "source_size": 4096
    }
  ]
}
```

## Nội dung QAR File

### Có chứa Bytecode (cho script/module)
- Mỗi entry JS chứa bytecode được compile với `JS_WriteObject()` (`JS_WRITE_OBJ_BYTECODE | JS_WRITE_OBJ_REFERENCE`)
- Bytecode format phụ thuộc vào phiên bản QuickJS

### Có chứa Source Code hoặc Asset Payload
- JS entries: chứa source code JavaScript gốc (fallback, debug, sourcemap)
- Asset entries: bytecode_size = 0, payload được lưu ở phần `source` (raw bytes)

### Hỗ trợ nén theo entry
- Bit1 trong flags bật khi entry được nén.
- Khi nén, hai trường kích thước thêm (original bytecode/source) được ghi để biết kích thước thật trước nén.

### ❌ WinZip/Không thể đọc được
- QAR là định dạng binary tùy chỉnh, không phải ZIP format
- WinZip, 7-Zip, hoặc các công cụ nén khác **KHÔNG THỂ** đọc được file QAR
 - **VI:** Cần sử dụng `qjsp` REPL (`.qar build/inspect/rebuild/code`) hoặc dùng `qjsp` helpers (`GetQarInfo`, `GetQarAsset`, ...).
 - **EN:** Use the `qjsp` REPL (`.qar build/inspect/rebuild/code`) or the `qjsp` helpers (`GetQarInfo`, `GetQarAsset`, ...).

## So sánh với các format khác

| Format | Bytecode | Source | Compression | Readable by ZIP tools |
|--------|----------|--------|-------------|----------------------|
| QAR    | ✅       | ✅     | ❌          | ❌                    |
| JAR    | ✅       | ✅     | ✅          | ✅                    |
| ZIP    | ❌       | ✅     | ✅          | ✅                    |

## Ví dụ tạo và đọc QAR

### Tạo QAR file
```bash
qjsp
js> .qar build mylib.qar src/math.js src/utils.js
```

### Đọc/inspect QAR (khuyến nghị) / Read/inspect QAR (recommended)
```bash
qjsp
js> .qar inspect mylib.qar
js> .qar code mylib.qar math.js
```

```javascript
// inside qjsp
print(GetQarInfo('mylib.qar'));
```

## Lưu ý

1. **Bytecode Compatibility**: Bytecode chỉ tương thích với cùng phiên bản QuickJS. Nếu không tương thích, hệ thống sẽ tự động compile lại từ source code.

2. **File Size**: QAR files không được nén, nên có thể lớn hơn ZIP files tương đương.

3. **Security**: QAR files chứa executable bytecode, cần kiểm tra tính toàn vẹn trước khi load.

4. **Manifest**: Manifest ở cuối file để có thể đọc metadata mà không cần parse toàn bộ file.

