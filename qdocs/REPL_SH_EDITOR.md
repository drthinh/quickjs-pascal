# REPL sh editor (vi/nano/edit)

Tài liệu này mô tả editor dạng line-based được host `qjsp.exe` cung cấp khi bạn bật REPL mode `sh`.

Editor này được viết bằng Pascal và đọc input bằng `ReadLnUtf8` (từ `console_utf8`) để **tránh lỗi UniKey/IME** trong các console không hỗ trợ raw-key mode.

## 1. Khi nào editor được kích hoạt

Trong REPL:

- Bật `sh` mode:

```text
js> .mode sh on
sh>
```

- Dùng một trong các lệnh sau:

```text
sh> vi <file>
sh> nano <file>
sh> edit <file>
```

Host sẽ **intercept** 3 lệnh này và chạy editor Pascal trực tiếp (không đi qua JS).

## 2. Mô hình editor (P1)

Editor là dạng **line editor**, không phải fullscreen editor:

- Bạn nhập từng dòng và nhấn Enter.
- Những dòng bạn nhập (không bắt đầu bằng `:`) được coi là **nội dung file**.
- Các lệnh điều khiển editor đều bắt đầu bằng `:` để tránh xung đột với host dot-commands (`.help`, `.mode`, ...).

## 3. Lệnh hỗ trợ

### 3.1. Thoát / lưu

- `:w`
  - Ghi file ra disk (UTF-8).
- `:q`
  - Thoát editor.
- `:wq`
  - Ghi file và thoát.

### 3.2. Xem nội dung buffer

- `:p`
  - In toàn bộ buffer.
- `:p N`
  - In dòng `N`.
- `:p N M`
  - In range `N..M`.
- `:l N`
  - Alias tiện dụng để in riêng dòng `N`.

### 3.3. Chèn / xóa

- `:i N`
  - Đặt vị trí insert **trước** dòng `N`.
- `:a N`
  - Đặt vị trí insert **sau** dòng `N`.
- `:d N`
  - Xóa dòng `N`.

### 3.4. Sửa nội dung

- `:r N <text>`
  - Replace dòng `N` bằng `<text>`.

- `:r N`
  - Bật replace-mode cho dòng `N`.
  - Editor sẽ in lại nội dung dòng `N`, sau đó chờ bạn nhập **một dòng** replacement.

- `:s N FROM TO`
  - Thay substring `FROM` bằng `TO` trong dòng `N`.
  - Lưu ý: phiên bản P1 parse theo token (tách bằng space), nên `FROM`/`TO` không chứa space.

## 4. Hành vi insertAt sau khi replace

Sau khi bạn `:r N ...` (replace dòng), editor sẽ tự đặt `insertAt := N` (tức là ngay sau dòng vừa sửa). Điều này giúp bạn gõ tiếp nhiều dòng nội dung và chúng sẽ nằm ngay sau dòng vừa replace.

## 5. Các "gotcha" thường gặp

- **Command chỉ được nhận nếu dấu `:` nằm ở đầu dòng.**
  - Ví dụ: `viết nhiều dòng:wq` là nội dung text, không phải lệnh.
  - Muốn lưu/thoát phải gõ `:wq` ở đầu dòng.

- **Enter thừa tạo ra dòng trống.**
  - Nếu bạn nhấn Enter khi đang nhập text, editor sẽ coi đó là một dòng rỗng và sẽ lưu lại.

- **Trailing blank lines được giữ nguyên.**
  - Nếu file có nhiều dòng trống cuối file, editor sẽ in ra và lưu lại như cũ.
  - Nếu bạn muốn tự động trim trailing blanks khi lưu, cần bổ sung thêm lệnh/behavior (chưa có ở P1).

- **Line numbers thay đổi khi chèn/xóa.**
  - `:d`, `:i`, `:a` sẽ làm thay đổi số dòng; nên dùng `:p N M`/`:l N` để kiểm tra lại trước các thao tác tiếp theo.

## 6. Gợi ý workflow

### 6.1. Sửa một dòng và lưu

```text
:r 10 nguyễn đức thịnh
:wq
```

### 6.2. Replace-mode rồi lưu

```text
:r 10
nguyễn đức thịnh
:wq
```

### 6.3. Sửa nhỏ bằng thay substring

```text
:l 10
:s 10 thinh thịnh
:p 10
:wq
```
