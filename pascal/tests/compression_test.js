// Test compression/decompression functions exposed from libqjs

console.log('=== Compression Test ===');

// Verify functions are available
console.log('Checking function availability...');
console.log('typeof compress:', typeof compress);
console.log('typeof uncompress:', typeof uncompress);
console.log('typeof compressBound:', typeof compressBound);

if (typeof compress !== 'function') {
    console.error('ERROR: compress is not a function! It is:', typeof compress);
    if (compress !== undefined) {
        console.error('compress value:', compress);
    }
    throw new Error('compress function is not available');
}

if (typeof uncompress !== 'function') {
    console.error('ERROR: uncompress is not a function!');
    throw new Error('uncompress function is not available');
}

if (typeof compressBound !== 'function') {
    console.error('ERROR: compressBound is not a function!');
    throw new Error('compressBound function is not available');
}

console.log('All compression functions are available');
console.log();

// Helper functions for string/bytes conversion (QuickJS doesn't have TextEncoder/TextDecoder)
function stringToBytes(str) {
    const bytes = new Uint8Array(str.length);
    for (let i = 0; i < str.length; i++) {
        bytes[i] = str.charCodeAt(i) & 0xFF;
    }
    return bytes;
}

function bytesToString(bytes) {
    let str = '';
    for (let i = 0; i < bytes.length; i++) {
        str += String.fromCharCode(bytes[i]);
    }
    return str;
}

// Test 1: Basic compression
try {
    const originalText = 'Hello, World! This is a test string for compression.';
    const originalData = stringToBytes(originalText);
    console.log('Original size:', originalData.length, 'bytes');
    
    // Compress
    const compressed = compress(originalData.buffer);
    console.log('Compressed size:', compressed.byteLength, 'bytes');
    console.log('Compression ratio:', (compressed.byteLength / originalData.length * 100).toFixed(2) + '%');
    
    // Uncompress
    const uncompressed = uncompress(compressed, originalData.length);
    const restoredText = bytesToString(new Uint8Array(uncompressed));
    console.log('Restored text:', restoredText);
    console.log('Match:', restoredText === originalText ? '✓' : '✗');
} catch (e) {
    console.error('Test 1 failed:', e);
}

console.log();

// Test 2: Compression with different levels
try {
    const data = new Uint8Array(1000);
    for (let i = 0; i < data.length; i++) {
        data[i] = i % 256;
    }
    
    console.log('Test 2: Compression levels');
    for (let level = 0; level <= 9; level++) {
        const compressed = compress(data.buffer, level);
        console.log(`Level ${level}: ${compressed.byteLength} bytes`);
    }
} catch (e) {
    console.error('Test 2 failed:', e);
}

console.log();

// Test 3: compressBound function
try {
    const sizes = [100, 1000, 10000, 100000];
    console.log('Test 3: compressBound');
    for (const size of sizes) {
        const bound = compressBound(size);
        console.log(`Size ${size}: bound = ${bound} bytes`);
    }
} catch (e) {
    console.error('Test 3 failed:', e);
}

console.log();

// Test 4: Large data compression
try {
    const largeData = new Uint8Array(100000);
    for (let i = 0; i < largeData.length; i++) {
        largeData[i] = Math.floor(Math.random() * 256);
    }
    
    console.log('Test 4: Large data compression');
    console.log('Original size:', largeData.length, 'bytes');
    
    const compressed = compress(largeData.buffer);
    console.log('Compressed size:', compressed.byteLength, 'bytes');
    console.log('Compression ratio:', (compressed.byteLength / largeData.length * 100).toFixed(2) + '%');
    
    const uncompressed = uncompress(compressed, largeData.length);
    console.log('Uncompressed size:', uncompressed.byteLength, 'bytes');
    console.log('Match:', uncompressed.byteLength === largeData.length ? '✓' : '✗');
    
    // Verify data integrity
    const original = new Uint8Array(largeData.buffer);
    const restored = new Uint8Array(uncompressed);
    let match = true;
    for (let i = 0; i < Math.min(original.length, restored.length); i++) {
        if (original[i] !== restored[i]) {
            match = false;
            break;
        }
    }
    console.log('Data integrity:', match ? '✓' : '✗');
} catch (e) {
    console.error('Test 4 failed:', e);
}

console.log();
console.log('=== All tests completed ===');

