/*
 * Test JavaScript sử dụng modules từ QAR files
 * 
 * Cách sử dụng:
 * 1. Tạo QAR file chứa tất cả modules:
 *    qjar -o qar_test.qar tests/qar_test_lib/math.js tests/qar_test_lib/utils.js
 * 
 * 2. Load QAR file từ JavaScript (không cần hardcode trong C):
 *    LoadLibrary('qar_test.qar');
 * 
 * 3. Import và sử dụng modules:
 *    import * as math from './qar_test_lib/math.js';
 *    import { greet, formatDate } from './qar_test_lib/utils.js';
 * 
 * Hoặc sử dụng helper module:
 *    import { loadQar } from './qar_loader.js';
 *    loadQar('qar_test.qar');
 */

// Cách 1: Load QAR file trực tiếp (đơn giản nhất)
// if (typeof LoadLibrary !== 'undefined') {
//     LoadLibrary('qar_test.qar');
// } else {
//     console.warn('LoadLibrary not available. Make sure js_std_add_helpers() is called in C code.');
// }

// Cách 2: Sử dụng helper module (nếu có)
// import { loadQar } from './qar_loader.js';
// loadQar('qar_test.qar');

// Import modules từ QAR files
import * as math from './qar_test_lib/math.js';
import { greet, formatDate } from './qar_test_lib/utils.js';

console.log("=== Test QAR Module Loading ===\n");

// Test math module
console.log("Math Module Tests:");
console.log("  add(2, 3) =", math.add(2, 3));
console.log("  multiply(5, 4) =", math.multiply(5, 4));
console.log("  subtract(10, 3) =", math.subtract(10, 3));
console.log("  divide(20, 4) =", math.divide(20, 4));
console.log();

// Test utils module
console.log("Utils Module Tests:");
console.log("  greet('QuickJS') =", greet("QuickJS"));
console.log("  formatDate() =", formatDate());
console.log();

console.log("All tests passed! ✓");

