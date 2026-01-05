tôi muốn thiết kế chương trình quickjs có các tính năng sau:

- có thể biên dịch mã nguồn nhiều file/ thư mục javascript thành các bytecode 
- đóng gói bytecode này thành gói như file jar (ví dự qar): byte code + manifest json chứa tất cả thông tin và cấu trúc của gói tương tự với Java Jar/ class
- có thể lưu mã nguồn để sử dụng khi bytecode không tương thích với phiên bản quickjs trên máy khác => biên dịch ra bytecode thay thế
- có thể sử dụng tệp tin (qar) này như thư viện, load và gọi các hàm qua import/ exports
- thêm các test tương ứng
- thiết lập cmake để biên dịch GCC cho tùy chọn file nhỏ nhất nhưng không phụ thuộc DLL khác
- xuất bổ sung các hàm mới trong quickjs.dll