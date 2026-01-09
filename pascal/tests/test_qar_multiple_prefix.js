/*
 * Ví dụ: Load nhiều QAR files với prefix để tránh xung đột tên file
 * 
 * Giả sử bạn có:
 *   - lib1.qar chứa math.js và utils.js
 *   - lib2.qar cũng chứa math.js và utils.js (nhưng khác implementation)
 * 
 * Cách 1: Sử dụng prefix (KHUYẾN NGHỊ)
 *   LoadLibrary('lib1.qar', 'lib1:')  -> import từ 'lib1:math.js'
 *   LoadLibrary('lib2.qar', 'lib2:')  -> import từ 'lib2:math.js'
 */

// Đăng ký QAR files với prefix
LoadLibrary('lib1.qar', 'lib1:');
LoadLibrary('lib2.qar', 'lib2:');

// Import với prefix để chỉ định rõ QAR file nào
import * as math1 from 'lib1:math.js';
import * as math2 from 'lib2:math.js';
import { greet as greet1 } from 'lib1:utils.js';
import { greet as greet2 } from 'lib2:utils.js';

// Sử dụng
console.log('Math from lib1:', math1.add(2, 3));
console.log('Math from lib2:', math2.add(2, 3));
console.log('Greet from lib1:', greet1('User'));
console.log('Greet from lib2:', greet2('User'));

/*
 * Cách 2: Không dùng prefix (KHÔNG KHUYẾN NGHỊ khi có xung đột)
 *   LoadLibrary('lib1.qar')
 *   LoadLibrary('lib2.qar')
 *   import * as math from './math.js'  -> sẽ tìm thấy file đầu tiên (lib1)
 * 
 * Vấn đề: Nếu cả 2 QAR files đều có math.js, file đầu tiên được đăng ký
 *         sẽ được sử dụng, có thể không phải file bạn muốn.
 * 
 * Giải pháp: Luôn dùng prefix khi có khả năng xung đột tên file.
 */

