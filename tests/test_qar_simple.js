/*
 * Ví dụ đơn giản nhất - Load QAR và sử dụng modules
 * 
 * Chạy:
 *   1. Tạo QAR: qjar -o qar_test.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js
 *   2. Chạy: qjs --module test_qar_simple.js
 */

// Bước 1: Đăng ký QAR file (tự động có sẵn trong JavaScript)
LoadLibrary('qar_test.qar');

// Bước 2: Import và sử dụng modules từ QAR
import * as math from './qar_test_lib/math.js';
import { greet } from './qar_test_lib/utils.js';

// Bước 3: Sử dụng
console.log("2 + 3 =", math.add(2, 3));
console.log("5 * 4 =", math.multiply(5, 4));
console.log(greet("QuickJS"));

console.log("✓ Tất cả đã hoạt động!");

