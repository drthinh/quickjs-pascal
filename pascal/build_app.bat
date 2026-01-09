@echo off
setlocal

set "FPC_COMMON=-B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq"
set "FPC_UNITS=-Fu.\std -Fu.\std\qar -Fu.\std\platform -Fu.\std\config -Fu.\std\io -Fu.\std\log -Fu.\std\net -Fu.\app"
set "FPC_OUT=-FE.\app"

set "TARGET=%~1"
if "%TARGET%"=="" goto :menu

if /I "%TARGET%"=="help" goto :usage
if /I "%TARGET%"=="-h" goto :usage
if /I "%TARGET%"=="--help" goto :usage

if /I "%TARGET%"=="all" goto :build_all

if /I "%TARGET%"=="qjsp" goto :build_qjsp
if /I "%TARGET%"=="qar_tool" goto :build_qar_tool
if /I "%TARGET%"=="stability_test_runner" goto :build_stability_test_runner
if /I "%TARGET%"=="qstability_test_runner" goto :build_stability_test_runner

echo Unknown target: %TARGET%
echo.
goto :usage

:menu
echo Select app to build:
echo   1) qjsp
echo   2) qar_tool
echo   3) qstability_test_runner
echo   4) all
echo.
set "SEL="
set /p "SEL=Choice [1]: "
if "%SEL%"=="" set "SEL=1"

if "%SEL%"=="1" set "TARGET=qjsp"
if "%SEL%"=="2" set "TARGET=qar_tool"
if "%SEL%"=="3" set "TARGET=qstability_test_runner"
if "%SEL%"=="4" set "TARGET=all"

if "%TARGET%"=="" goto :usage
goto :start

:start
if /I "%TARGET%"=="all" goto :build_all

if /I "%TARGET%"=="qjsp" goto :build_qjsp
if /I "%TARGET%"=="qar_tool" goto :build_qar_tool
if /I "%TARGET%"=="stability_test_runner" goto :build_stability_test_runner
if /I "%TARGET%"=="qstability_test_runner" goto :build_stability_test_runner

echo Unknown target: %TARGET%
echo.
goto :usage

:build_all
call :build_qjsp || exit /b 1
call :build_qar_tool || exit /b 1
call :build_stability_test_runner || exit /b 1
goto :eof

:build_qjsp
fpc %FPC_COMMON% ^
  %FPC_UNITS% ^
  %FPC_OUT% -oqjsp.exe ^
  app\qjsp.pas
goto :eof

:build_qar_tool
fpc %FPC_COMMON% ^
  %FPC_UNITS% ^
  %FPC_OUT% -oqar_tool.exe ^
  app\qar_tool.pas
goto :eof

:build_stability_test_runner
fpc %FPC_COMMON% ^
  %FPC_UNITS% ^
  %FPC_OUT% -oqstability_test_runner.exe ^
  app\stability_test_runner.pas
goto :eof

:usage
echo Usage:
echo   build_app.bat [all^|qjsp^|qar_tool^|stability_test_runner]
echo.
echo Examples:
echo   build_app.bat all
echo   build_app.bat qjsp
echo   build_app.bat qar_tool
exit /b 2