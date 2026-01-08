@echo off
setlocal ENABLEDELAYEDEXPANSION

rem Build QuickJS (qjs library + tools) with MinGW using CMake
rem Requirements: cmake + MinGW (gcc/mingw32-make) in PATH

set SCRIPT_DIR=%~dp0
rem Remove trailing backslash to avoid escaping the closing quote in CMake args
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
rem Ensure build dir uses path separator
set BUILD_DIR=%SCRIPT_DIR%\build-mingw
set GENERATOR=MinGW Makefiles
set CONFIG=Release
set BUILD_SHARED=ON

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

rem Configure (compatible with older CMake: run from build dir, point to source dir)
pushd "%BUILD_DIR%"
cmake -G "MinGW Makefiles" "%SCRIPT_DIR%" -DQJS_BUILD_EXAMPLES=OFF -DQJS_BUILD_CLI_STATIC=OFF -DBUILD_SHARED_LIBS=%BUILD_SHARED%
popd
if errorlevel 1 goto :fail

rem Build (qjs lib + qjs/qjsc tools)
cmake --build "%BUILD_DIR%" --config %CONFIG% -- -j
if errorlevel 1 goto :fail

echo [OK] Built QuickJS to %BUILD_DIR%
exit /b 0

:fail
echo [ERROR] Build failed
exit /b 1
