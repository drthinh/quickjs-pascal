// Example 4: Test dynamic library functions from JavaScript
// This example demonstrates how to load and call functions from a dynamic library
// Cross-platform: supports .dll (Windows), .so (Linux/Unix), .dylib (macOS)

console.log("=== Example 4: Dynamic Library Function Calls ===");

// Check if dynamic library functions are available
if (typeof LoadDynamicLibrary === "undefined") {
  console.log("Dynamic library functions are not available");
  console.log("This example requires a compiled dynamic library:");
  console.log("  - Windows: test_dll.dll");
  console.log("  - Linux/Unix: test_dll.so");
  console.log("  - macOS: test_dll.dylib");
} else {
  console.log("Dynamic library functions are available!");
  
  try {
    // Load the dynamic library (cross-platform)
    console.log("\n1. Loading dynamic library...");
    var lib_filename;
    // Try platform-specific extensions
    // QuickJS doesn't have process object, so we need to detect platform differently
    // Try Windows first (.dll), then Unix (.so), then macOS (.dylib)
    // For now, we'll try to detect by attempting to load each extension
    // Or use a simple heuristic: if we're on Windows, use .dll
    // Since this is running in QuickJS Pascal on Windows, use .dll
    lib_filename = "test_dll.dll";  // Default to Windows .dll
    // Note: In a real cross-platform scenario, you might want to:
    // 1. Try loading test_dll.dll first (Windows)
    // 2. If that fails, try test_dll.so (Linux/Unix)
    // 3. If that fails, try test_dll.dylib (macOS)
    
    var lib_id = LoadDynamicLibrary(lib_filename);
    console.log("   Library loaded successfully, ID:", lib_id);
    
    // Test function: GetVersion() - returns int, no arguments
    console.log("\n2. Calling GetVersion()...");
    var version = CallDllFunction(lib_id, "GetVersion", "i");
    console.log("   Version:", version);
    
    // Test function: Add(a, b) - but we can only pass 1 arg, so let's test with Multiply
    // Note: Current implementation supports 0 or 1 argument only
    // For Add(a, b), we would need to extend the implementation
    
    // Test function: Calculate(x) - returns float, 1 argument
    console.log("\n3. Calling Calculate(10.0)...");
    var result = CallDllFunction(lib_id, "Calculate", "f", 10.0);
    console.log("   Calculate(10.0) =", result);
    
    // Test function: Double(x) - returns int, 1 argument
    console.log("\n4. Calling Double(42)...");
    var doubled = CallDllFunction(lib_id, "Double", "i", 42);
    console.log("   Double(42) =", doubled);
    
    // Test void function: PrintHello()
    console.log("\n5. Calling PrintHello() (void function)...");
    CallDllFunction(lib_id, "PrintHello", "v");
    console.log("   (void function called)");
    
    // Free the dynamic library
    console.log("\n6. Freeing dynamic library...");
    FreeDynamicLibrary(lib_id);
    console.log("   Library freed successfully");
    
    console.log("\n=== Dynamic Library Test Completed ===");
  } catch (e) {
    console.log("Error:", e);
    console.log("Make sure the dynamic library exists in the current directory or executable directory");
  }
}

