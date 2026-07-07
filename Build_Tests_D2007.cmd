@echo off
setlocal

rem Build_Tests_D2007.cmd [Debug|Release] [/ci]  -  rebuilds tests\!bin\DelphiBoostPackTests.exe.
rem Default config is Debug, the only config wired for the DUnit source paths.
rem Forces CONSOLE_TESTRUNNER so the exe runs as a console test runner; IDE builds keep the GUI runner.
rem MSBuild treats ; in /p: values as a property separator, hence the escaped semicolons below.
rem /ci skips the pause on failure (AI agent, CI runner).

if not defined BDS set "BDS=C:\Program Files (x86)\CodeGear\RAD Studio\5.0"
set "MSBUILD=%WINDIR%\Microsoft.NET\Framework\v2.0.50727\MSBuild.exe"

set "CFG=%~1"
if "%CFG%"=="" set "CFG=Debug"

set "DEFINES=DEBUG%%3BCONSOLE_TESTRUNNER%%3BBENCHMARK"
if /I "%CFG%"=="Release" set "DEFINES=RELEASE%%3BCONSOLE_TESTRUNNER%%3BBENCHMARK"

echo Building DelphiBoostPackTests (%CFG%)...
"%MSBUILD%" "%~dp0tests\DelphiBoostPackTests.dproj" /p:Configuration=%CFG% /p:Platform=AnyCPU /p:DCC_Define=%DEFINES% /t:Build /v:minimal /nologo
if errorlevel 1 goto :fail

echo Built %~dp0tests\!bin\DelphiBoostPackTests.exe (%CFG%)
endlocal
exit /b 0

:fail
echo Build failed.
endlocal
rem Skip pause when invoked non-interactively (AI agent, CI runner).
if /I not "%~2"=="/ci" pause
exit /b 1
