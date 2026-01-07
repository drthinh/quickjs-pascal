@echo off
REM Batch script to compile and run stability tests on Windows

echo ========================================
echo QuickJS Pascal Stability Test Runner
echo ========================================
echo.

REM Check if FPC is available
where fpc >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Error: Free Pascal Compiler (fpc) not found in PATH
    echo Please install FPC or add it to your PATH
    pause
    exit /b 1
)

REM Compile the test runner
echo Compiling stability_test_runner.pas...
fpc -Fu. stability_test_runner.pas
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Compilation failed!
    pause
    exit /b 1
)

echo.
echo Compilation successful!
echo.
echo Running stability tests...
echo ========================================
echo.

REM Run the tests
stability_test_runner.exe

echo.
echo ========================================
echo Tests completed!
echo ========================================
pause

