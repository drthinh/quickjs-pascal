@echo off
setlocal

set "FPC_COMMON=-B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq"
set "FPC_UNITS=-Fu.\src -Fu.\src\quickjs -Fu.\src\modules -Fu.\src\qar -Fu.\src\crypto -Fu.\src\platform -Fu.\src\config -Fu.\src\io -Fu.\src\log -Fu.\src\net -Fu.\src\app"
set "FPC_OUT=-FE.\bin -FU.\build\units"

set "TARGET=%~1"
if "%TARGET%"=="" goto :menu

if /I "%TARGET%"=="help" goto :usage
if /I "%TARGET%"=="-h" goto :usage
if /I "%TARGET%"=="--help" goto :usage

if /I "%TARGET%"=="all" goto :build_all

if /I "%TARGET%"=="qjsp" goto :build_qjsp

echo Unknown target: %TARGET%
echo.
goto :usage

:menu
echo Select app to build:
echo   1) qjsp
echo   2) all
echo.
set "SEL="
set /p "SEL=Choice [1]: "
if "%SEL%"=="" set "SEL=1"

if "%SEL%"=="1" set "TARGET=qjsp"
if "%SEL%"=="2" set "TARGET=all"

if "%TARGET%"=="" goto :usage
goto :start

:start
if /I "%TARGET%"=="all" goto :build_all

if /I "%TARGET%"=="qjsp" goto :build_qjsp

echo Unknown target: %TARGET%
echo.
goto :usage

:build_all
call :build_qjsp || exit /b 1
goto :eof

:build_qjsp
fpc %FPC_COMMON% ^
  %FPC_UNITS% ^
  %FPC_OUT% -oqjsp.exe ^
  src\app\qjsp.pas
goto :eof

:usage
echo Usage:
echo   build_app.bat [all^|qjsp]
echo.
echo Examples:
echo   build_app.bat all
echo   build_app.bat qjsp
exit /b 2