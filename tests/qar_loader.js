/*
 * QAR Loader Helper Module
 * 
 * Tự động load QAR files từ thư mục hoặc danh sách files
 * Sử dụng: import { loadQar, loadQarDir } from './qar_loader.js';
 */

/**
 * Load một QAR file
 * @param {string} filename - Đường dẫn đến QAR file
 * @param {string} [prefix] - Optional prefix cho module names
 * @returns {boolean} true nếu thành công
 */
export function loadQar(filename, prefix) {
    if (typeof registerQar === 'undefined') {
        throw new Error('registerQar is not available. Make sure js_std_add_helpers() is called.');
    }
    
    try {
        if (prefix) {
            registerQar(filename, prefix);
        } else {
            registerQar(filename);
        }
        return true;
    } catch (e) {
        console.error(`Failed to load QAR file: ${filename}`, e);
        return false;
    }
}

/**
 * Load nhiều QAR files từ một mảng
 * @param {Array<string>} files - Mảng các đường dẫn QAR files
 * @param {string} [prefix] - Optional prefix chung cho tất cả
 * @returns {number} Số lượng files đã load thành công
 */
export function loadQars(files, prefix) {
    let count = 0;
    for (const file of files) {
        if (loadQar(file, prefix)) {
            count++;
        }
    }
    return count;
}

/**
 * Load QAR files từ một object với prefix
 * @param {Object<string, string>} qarMap - Object với key là prefix, value là filename
 * @returns {number} Số lượng files đã load thành công
 * 
 * @example
 * loadQarWithPrefix({
 *   'math:': 'mathlib.qar',
 *   'utils:': 'utilslib.qar'
 * });
 */
export function loadQarWithPrefix(qarMap) {
    let count = 0;
    for (const [prefix, filename] of Object.entries(qarMap)) {
        if (loadQar(filename, prefix)) {
            count++;
        }
    }
    return count;
}

/**
 * Auto-load QAR files từ một thư mục (cần implement file system access)
 * @param {string} dir - Thư mục chứa QAR files
 * @returns {Promise<number>} Số lượng files đã load
 */
export async function loadQarDir(dir) {
    // Note: Cần implement file system scanning
    // Hiện tại chỉ là placeholder
    throw new Error('loadQarDir not yet implemented. Use loadQar or loadQars instead.');
}

