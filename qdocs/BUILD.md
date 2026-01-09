# Hướng dẫn Build QuickJS Pascal Project

## Yêu cầu

1. **Free Pascal Compiler (FPC)** - Phiên bản 3.0.0 trở lên
   - Download từ: https://www.freepascal.org/download.html
   - Hoặc sử dụng Lazarus IDE (bao gồm FPC)

2. **libqjs.dll** (Windows) hoặc **libqjs.so** (Linux)
   - Cần được build từ QuickJS source với QAR support
   - Đặt file DLL/SO trong cùng thư mục với executable hoặc trong PATH

## Build từ Command Line

### Windows:

```cmd
fpc -B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq -Fu. -Fu.\\std -Fu.\\std\\platform -Fu.\\std\\qar -Fu.\\app -o"qjsp.exe" app\\qjsp.pas
```

### Linux:

```bash
fpc -B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq -Fu. -Fu./std -Fu./std/platform -Fu./std/qar -Fu./app -oQuickJSPascal app/qjsp.pas
```

### Giải thích các tham số:

- `-B`: Build tất cả units
- `-Mobjfpc`: Mode Object Pascal
- `-Scghi`: Syntax options (classes, helpers, generics, interfaces)
- `-O2`: Optimization level 2
- `-Xs`: Strip symbols
- `-XX`: Maximum optimization
- `-l`: Link dynamically
- `-vewnhibq`: Verbose options
- `-Fu.`: Unit search path (current directory)
- `-Fu./std`: Unit search path for stable core units
- `-Fu./std/platform`: Unit search path for OS/platform abstractions
- `-Fu./std/qar`: Unit search path for QAR support and module loader
- `-Fu./app`: Unit search path for app entrypoints
- `-o`: Output filename

## Build từ Lazarus IDE

1. Mở Lazarus IDE
2. File → Open → Chọn file `QuickJSPascal.lpr`
3. Project → Compile (Ctrl+F9) hoặc Run (F9)

### Cấu hình Project Options:

- **Paths**: Đảm bảo thư mục `pascal` được thêm vào Unit search paths
- **Paths**: Đảm bảo các thư mục `pascal`, `pascal/std`, `pascal/std/platform`, `pascal/app` được thêm vào Unit search paths
- **Linking**: Chọn "Link Style" = "Dynamic"
- **Target**: Chọn platform phù hợp (Win32/Win64/Linux)

## Kiểm tra Build

Sau khi build thành công, bạn sẽ có file:
- Windows: `QuickJSPascal.exe`
- Linux: `QuickJSPascal`

Chạy thử:
```bash
./QuickJSPascal.exe
```

Nếu thiếu `libqjs.dll`, bạn sẽ thấy lỗi:
```
Error: Can't load library "libqjs.dll"
```

## Troubleshooting

### Lỗi: "Can't find unit quickjs_core" hoặc "quickjs_types"

**Giải pháp**: Đảm bảo tất cả các file `.pas` (đặc biệt là `quickjs_types.pas`, `quickjs_core.pas`, `quickjs_std.pas`) nằm trong cùng thư mục hoặc thêm thư mục `pascal` vào unit search path (`-Fu.`).

### Lỗi: "Can't load library libqjs.dll"

**Giải pháp**: 
1. Đảm bảo `libqjs.dll` nằm trong cùng thư mục với executable
2. Hoặc đặt trong PATH
3. Hoặc đặt trong thư mục system (Windows/System32)

### Lỗi: "Undefined symbol: JS_NewRuntime"

**Giải pháp**: 
1. Đảm bảo `libqjs.dll` được build với đầy đủ exports
2. Kiểm tra file `.def` hoặc exports trong DLL
3. Có thể cần rebuild QuickJS với đúng cấu hình

### Lỗi: "Access violation" hoặc crash

**Giải pháp**:
1. Kiểm tra phiên bản QuickJS - có thể không tương thích
2. Kiểm tra memory management - đảm bảo tất cả JSValue được free đúng cách
3. Sử dụng debugger để trace

## Build libqjs.dll từ Source

Nếu bạn cần build `libqjs.dll` từ source:

### Windows (MSVC):

```cmd
cd quickjs-master
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
cmake --build . --config Release
```

File DLL sẽ ở: `build/Release/libqjs.dll`

### Windows (MinGW):

```cmd
cd quickjs-master
mkdir build
cd build
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
cmake --build .
```

### Linux:

```bash
cd quickjs-master
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
make
```

File SO sẽ ở: `build/libqjs.so`

## Testing

Sau khi build thành công, test với:

1. **Basic test**:
```pascal
// Chạy chương trình và gõ:
console.log("Hello World");
```

2. **QAR test**:
```bash
# Tạo QAR file test
qjar -o test.qar test.js

# Chạy chương trình và gõ:
LoadLibrary('test.qar');
```

## Notes

- Đảm bảo FPC version tương thích với cú pháp được sử dụng
- Trên Windows, có thể cần Visual C++ Redistributable để chạy DLL
- Trên Linux, có thể cần cài đặt các thư viện phụ thuộc

