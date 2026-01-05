/*
 * Ví dụ load nhiều QAR files với prefix
 * 
 * Chạy:
 *   1. Tạo QAR files:
 *      qjar -o mathlib.qar tests/qar_test_lib/math.js
 *      qjar -o utilslib.qar tests/qar_test_lib/utils.js
 *   2. Chạy: qjs --module test_qar_multiple.js
 */

// Cách 1: Load nhiều QAR files không dùng prefix
registerQar('mathlib.qar');
registerQar('utilslib.qar');

// Import như bình thường (module loader sẽ tìm trong tất cả QAR files)
import * as math from './qar_test_lib/math.js';
import { greet } from './qar_test_lib/utils.js';

console.log("=== Test Multiple QAR Files ===");
console.log("Math:", math.add(2, 3));
console.log("Utils:", greet("World"));

// Cách 2: Load với prefix để phân biệt
// registerQar('mathlib.qar', 'math:');
// registerQar('utilslib.qar', 'utils:');
// 
// Sau đó import với prefix:
// import * as math from 'math:math.js';
// import { greet } from 'utils:utils.js';

console.log("✓ Hoàn thành!");

