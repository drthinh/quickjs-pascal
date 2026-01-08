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
// Load dynamic library (cross-platform, auto tries .qar then platform lib)
var lib_id = LoadLib("test_dll"); // or LoadDLL("test_dll.dll"/".so"/".dylib")

// Call function with no arguments, returns int
var version = CallDllFunction(lib_id, "GetVersion", "i");

// Call function with ints (2 args here)
var sum = CallDllFunction(lib_id, "Add", "i", "ii", 1, 2);

// Call function with floats (2 args)
var calc = CallDllFunction(lib_id, "Scale", "f", "ff", 10.0, 2.5);

// Call void function
CallDllFunction(lib_id, "PrintHello", "v");

// Free dynamic library
FreeDLL(lib_id);
```

**Note:** The library will be automatically freed when the program exits or encounters an error.

## Return Types

- `"i"` or `"I"` - Integer (int32/int64)
- `"f"` - Float (double)
- `"v"` - Void (no return value)

## Argument and return type support

- Return types: `"i"`/`"I"`/`"p"` (int/pointer), `"f"` (float64), `"v"` (void), `"s"` (PChar -> JS string).
- Argument types: optional `argTypes` string, uniform kinds per call: `i/I/p`, `f`, `s`. If omitted, defaults to int.
- Up to 6 arguments supported.

