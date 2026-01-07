# Stability Test Suite

Bộ test độ ổn định cho dự án QuickJS Pascal Integration.

## Tổng quan

Bộ test này được thiết kế để kiểm tra độ ổn định của dự án QuickJS Pascal Integration, bao gồm:

1. **Memory Leak Tests** - Kiểm tra rò rỉ bộ nhớ khi tạo/hủy context nhiều lần
2. **Stress Tests** - Kiểm tra hiệu năng với nhiều operations
3. **Error Handling** - Kiểm tra xử lý lỗi
4. **Resource Cleanup** - Kiểm tra cleanup tài nguyên
5. **Long-running Tests** - Kiểm tra độ ổn định trong thời gian dài

## Cấu trúc Files

- `stability_test.js` - JavaScript test suite với 15 test cases
- `stability_test_runner.pas` - Pascal program để chạy và đo lường tests

## Cách chạy Tests

### 1. Compile Test Runner

```bash
cd pascal
fpc -Fu. stability_test_runner.pas
```

Hoặc trên Windows:
```cmd
cd pascal
fpc -Fu. stability_test_runner.pas
```

### 2. Chạy Stability Tests

```bash
./stability_test_runner
```

Hoặc trên Windows:
```cmd
stability_test_runner.exe
```

### 3. Chạy JavaScript Test trực tiếp

Bạn cũng có thể chạy JavaScript test file trực tiếp với main program:

```bash
./main.exe tests/stability_test.js
```

## Test Cases

### JavaScript Test Suite (`stability_test.js`)

1. **Basic Functionality** - Kiểm tra các chức năng cơ bản
2. **Memory Stress Test** - Tạo array lớn với 1000 objects
3. **String Operations Stress** - String concatenation và operations
4. **Function Call Stress** - Recursive và iterative function calls
5. **Error Handling** - Try-catch, null access, division by zero
6. **Object Creation Stress** - Tạo 5000 objects
7. **Array Operations Stress** - Push, pop, map operations
8. **Closure and Scope** - Kiểm tra closure behavior
9. **Long-Running Loop** - 100,000 iterations
10. **Nested Structures** - Deeply nested objects (100 levels)
11. **Math Operations** - Math functions và stress test
12. **Date Operations** - Date creation và arithmetic
13. **JSON Operations** - JSON.stringify và JSON.parse
14. **Regular Expressions** - Regex matching và replacement
15. **Prototype and Inheritance** - Prototype chain và inheritance

### Pascal Test Runner (`stability_test_runner.pas`)

1. **Comprehensive JavaScript Stability Test** - Chạy toàn bộ JavaScript test suite
2. **Memory Leak Test (100 iterations)** - Tạo/hủy context 100 lần
3. **Stress Test** - 10,000 operations trong một context
4. **Aggressive Memory Leak Test (500 iterations)** - Tạo/hủy context 500 lần

## Kết quả mong đợi

Tất cả tests nên PASS. Nếu có test FAIL, có thể có vấn đề về:
- Memory leaks
- Resource cleanup
- Error handling
- Performance issues

## Performance Benchmarks

Test runner sẽ hiển thị:
- Thời gian thực thi của mỗi test (ms)
- Tổng thời gian
- Thời gian trung bình

## Troubleshooting

### Lỗi: "Failed to create JS runtime"
- Kiểm tra xem `libqjs.dll` (Windows) hoặc `libqjs.so` (Linux) có trong PATH không
- Đảm bảo các library files được compile đúng

### Lỗi: "Test execution failed"
- Kiểm tra xem file `tests/stability_test.js` có tồn tại không
- Kiểm tra console output để xem JavaScript errors

### Memory Issues
- Nếu memory leak tests fail, có thể có vấn đề với resource cleanup
- Kiểm tra xem tất cả JSValue có được JS_FreeValue không
- Kiểm tra xem context và runtime có được free đúng cách không

## Continuous Testing

Để chạy tests liên tục và monitor stability:

```bash
# Chạy 10 lần
for i in {1..10}; do
  echo "Run $i:"
  ./stability_test_runner
  sleep 1
done
```

Hoặc trên Windows PowerShell:
```powershell
for ($i=1; $i -le 10; $i++) {
  Write-Host "Run $i:"
  .\stability_test_runner.exe
  Start-Sleep -Seconds 1
}
```

## Thêm Test Cases

Để thêm test cases mới:

1. Thêm test function vào `stability_test.js`
2. Gọi test function trong main test suite
3. Sử dụng `assert()` để kiểm tra kết quả

Ví dụ:
```javascript
// ========== Test N: New Test ==========
console.log("\n--- Test N: New Test ---");
try {
    // Your test code here
    assert(condition, "Test description");
    assert(true, "New test completed");
} catch (e) {
    assert(false, "New test threw: " + e);
}
```

## Notes

- Tests được thiết kế để chạy độc lập
- Mỗi test tạo context riêng để đảm bảo isolation
- Memory leak tests tạo/hủy context nhiều lần để phát hiện leaks
- Stress tests kiểm tra performance và stability dưới tải cao

