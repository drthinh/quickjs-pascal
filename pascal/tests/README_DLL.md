# Dynamic Library Test Instructions

## Building the Test Dynamic Library

To build the test dynamic library from `test_dll.pas`, use Free Pascal Compiler:

### Windows:
```bash
fpc -XX test_dll.pas
```
This will create `test_dll.dll` in the same directory.

### Linux/Unix:
```bash
fpc -XX test_dll.pas
```
This will create `test_dll.so` in the same directory.

### macOS:
```bash
fpc -XX test_dll.pas
```
This will create `test_dll.dylib` in the same directory.

### Alternative build command (with more options):

```bash
fpc -XX -O2 test_dll.pas
```

## Dynamic Library Functions

The test dynamic library exports the following functions:

1. **GetVersion()** - Returns integer (100 = version 1.0.0)
   - No arguments
   - Return type: `i` (int)

2. **Double(x)** - Doubles an integer
   - 1 argument: integer
   - Return type: `i` (int)

3. **Calculate(x)** - Multiplies a number by 2.5
   - 1 argument: double
   - Return type: `f` (float)

4. **PrintHello()** - Prints a message
   - No arguments
   - Return type: `v` (void)

5. **Add(a, b)** - Adds two integers (for future use)
   - 2 arguments (not yet supported by CallDllFunction)

6. **Multiply(a, b)** - Multiplies two integers (for future use)
   - 2 arguments (not yet supported by CallDllFunction)

## Running the Test

1. Build the dynamic library: `fpc -XX test_dll.pas`
2. Copy the library file to the same directory as `main.exe` or the current working directory:
   - Windows: `test_dll.dll`
   - Linux/Unix: `test_dll.so`
   - macOS: `test_dll.dylib`
3. Run the main program: `main.exe`
4. Example 4 will automatically test the dynamic library functions

## JavaScript API

From JavaScript, you can use (cross-platform):

```javascript
// Load dynamic library (cross-platform)
// On Windows: LoadDynamicLibrary("test_dll.dll")
// On Linux/Unix: LoadDynamicLibrary("test_dll.so")
// On macOS: LoadDynamicLibrary("test_dll.dylib")
var lib_id = LoadDynamicLibrary("test_dll.dll");  // or .so or .dylib

// Call function with no arguments, returns int
var version = CallDllFunction(lib_id, "GetVersion", "i");

// Call function with 1 int argument, returns int
var result = CallDllFunction(lib_id, "Double", "i", 42);

// Call function with 1 float argument, returns float
var calc = CallDllFunction(lib_id, "Calculate", "f", 10.0);

// Call void function
CallDllFunction(lib_id, "PrintHello", "v");

// Free dynamic library
FreeDynamicLibrary(lib_id);
```

**Note:** The library will be automatically freed when the program exits or encounters an error.

## Return Types

- `"i"` or `"I"` - Integer (int32/int64)
- `"f"` - Float (double)
- `"v"` - Void (no return value)

## Limitations

The current implementation of `CallDllFunction` supports:
- Functions with 0 or 1 argument only
- Basic types: int, float, void
- stdcall calling convention

For more complex cases, you may need to extend the implementation.

