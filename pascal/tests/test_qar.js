/*
 * Test QAR file packaging and loading
 */

import * as math from './qar_test_lib/math.js';
import { greet } from './qar_test_lib/utils.js';

console.log("Testing QAR module loading...");

// Test math module
console.log("2 + 3 =", math.add(2, 3));
console.log("5 * 4 =", math.multiply(5, 4));

// Test utils module
console.log(greet("QuickJS"));

console.log("All tests passed!");

