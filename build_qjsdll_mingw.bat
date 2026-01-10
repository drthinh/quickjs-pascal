@echo off
setlocal enableextensions

set "ROOT=%~dp0"
set "SRC=%ROOT%quickjs-orgin"
set "BUILD=%ROOT%build-qjsdll-mingw"

if not exist "%SRC%\CMakeLists.txt" (
  echo ERROR: Cannot find "%SRC%\CMakeLists.txt".
  exit /b 1
)

if "%CMAKE_GENERATOR%"=="" set "CMAKE_GENERATOR=MinGW Makefiles"
if "%CMAKE_BUILD_TYPE%"=="" set "CMAKE_BUILD_TYPE=Release"

set "CFLAGS_RELEASE=-Os -DNDEBUG -ffunction-sections -fdata-sections -fno-asynchronous-unwind-tables -fno-unwind-tables"
set "SHARED_LDFLAGS_RELEASE=-Wl,--gc-sections -Wl,--strip-all -Wl,--export-all-symbols -static-libgcc"

echo [1/2] Configuring...
cmake -S "%SRC%" -B "%BUILD%" -G "%CMAKE_GENERATOR%" ^
  -DCMAKE_BUILD_TYPE=%CMAKE_BUILD_TYPE% ^
  -DBUILD_SHARED_LIBS=ON ^
  -DQJS_BUILD_LIBC=ON ^
  -DCMAKE_C_FLAGS_RELEASE="%CFLAGS_RELEASE%" ^
  -DCMAKE_SHARED_LINKER_FLAGS_RELEASE="%SHARED_LDFLAGS_RELEASE%"
if errorlevel 1 exit /b 1

echo [2/2] Building...
cmake --build "%BUILD%" --config %CMAKE_BUILD_TYPE% -j
if errorlevel 1 exit /b 1

echo.
echo DONE. Output should be under:
echo   %BUILD%
endlocal
