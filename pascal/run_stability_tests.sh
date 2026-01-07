#!/bin/bash
# Shell script to compile and run stability tests on Linux/Unix/macOS

echo "========================================"
echo "QuickJS Pascal Stability Test Runner"
echo "========================================"
echo

# Check if FPC is available
if ! command -v fpc &> /dev/null; then
    echo "Error: Free Pascal Compiler (fpc) not found in PATH"
    echo "Please install FPC or add it to your PATH"
    exit 1
fi

# Compile the test runner
echo "Compiling stability_test_runner.pas..."
fpc -Fu. stability_test_runner.pas
if [ $? -ne 0 ]; then
    echo
    echo "Compilation failed!"
    exit 1
fi

echo
echo "Compilation successful!"
echo
echo "Running stability tests..."
echo "========================================"
echo

# Run the tests
./stability_test_runner

echo
echo "========================================"
echo "Tests completed!"
echo "========================================"

