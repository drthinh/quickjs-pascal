Error: Unknown command: --cat

QAR Tool - QuickJS Archive Utility

Sử dụng:
  qar_tool [options] [command] [arguments]

Commands:
  info                    - Hiển thị thông tin phiên bản QAR và QuickJS
  build <output> <files>  - Tạo file QAR từ các file JavaScript
  inspect <file.qar>      - Kiểm tra và hiển thị thông tin chi tiết file QAR
  rebuild <input> <output> - Biên dịch lại QAR để phù hợp phiên bản QuickJS mới
  code <file.qar> <entry> - Hiển thị mã nguồn của một entry trong file QAR
  version                 - Hiển thị phiên bản
  help                    - Hiển thị trợ giúp này

Options:
  --init-lib              - Khởi tạo thư viện QuickJS mặc định khi hiển thị info
  --minify                - Minify JS sources via qjsp + minify script before building QAR
  --minify-safe           - Shortcut: --minify + --safe-rename + --encode-strings
  --minify-script <file>  - Chỉ định script minify (mặc định: minify_qjsp.js).
                           Lưu ý: các flag nâng cao (safe-rename/encode-strings) nằm trong minify_qjsp.js
  --minify-flag <arg>     - Truyền thêm flag cho script minify (có thể lặp lại)
  --keep-temp             - Giữ thư mục staging tạm (hữu ích để debug minify)

Ví dụ:
  qar_tool info
  qar_tool info --init-lib
  qar_tool build output.qar file1.js file2.js
  qar_tool build output.qar src/
  qar_tool --minify build output.qar src/
  qar_tool --minify build out.qar src/ --minify-flag --minify-only
  qar_tool --minify-safe build out.qar src/
  qar_tool --minify build out.qar src/ --minify-flag --safe-rename --minify-flag --encode-strings
  qar_tool inspect file.qar
  qar_tool rebuild old.qar new.qar
  qar_tool code mylib.qar my_module.js
  qar_tool version

