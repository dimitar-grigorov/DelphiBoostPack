@echo off
setlocal

rem Build_Tests_D2007.cmd [Debug|Release] [/ci] [/bench] [/nointeg]  -  rebuilds tests\!bin\DelphiBoostPackTests.exe.
rem Debug is the only config wired for the DUnit source paths, and CONSOLE_TESTRUNNER is forced so the exe runs on the console.
rem Kinds: unit always, integration unless /nointeg (NO_INTEGRATION), benchmarks only with /bench (BENCHMARK).
rem /ci skips the pause on failure (AI agent, CI runner).

if not defined BDS set "BDS=C:\Program Files (x86)\CodeGear\RAD Studio\5.0"
set "MSBUILD=%WINDIR%\Microsoft.NET\Framework\v2.0.50727\MSBuild.exe"

rem Capture the script dir now: the parseargs loop below uses shift, which also shifts %0.
set "HERE=%~dp0"

set "CFG=Debug"
set "CI="
set "BENCH="
set "NOINTEG="

:parseargs
if "%~1"=="" goto :parsed
if /I "%~1"=="Debug"    set "CFG=Debug"
if /I "%~1"=="Release"  set "CFG=Release"
if /I "%~1"=="/ci"      set "CI=1"
if /I "%~1"=="/bench"   set "BENCH=1"
if /I "%~1"=="/nointeg" set "NOINTEG=1"
shift
goto :parseargs
:parsed

rem %%3B is an escaped ;, which MSBuild would otherwise read as a property separator
set "DEFINES=DEBUG"
if /I "%CFG%"=="Release" set "DEFINES=RELEASE"
set "DEFINES=%DEFINES%%%3BCONSOLE_TESTRUNNER"
if defined BENCH set "DEFINES=%DEFINES%%%3BBENCHMARK"
if defined NOINTEG set "DEFINES=%DEFINES%%%3BNO_INTEGRATION"

set "KINDS=unit"
if not defined NOINTEG set "KINDS=%KINDS% + integration"
if defined BENCH set "KINDS=%KINDS% + benchmarks"
echo Building DelphiBoostPackTests (%CFG%; %KINDS%)...
"%MSBUILD%" "%HERE%tests\DelphiBoostPackTests.dproj" /p:Configuration=%CFG% /p:Platform=AnyCPU /p:DCC_Define=%DEFINES% /t:Build /v:minimal /nologo
if errorlevel 1 goto :fail

echo Built %HERE%tests\!bin\DelphiBoostPackTests.exe (%CFG%)
endlocal
exit /b 0

:fail
echo Build failed.
rem expand %CI% before endlocal drops it, or the pause fires even under /ci
endlocal & if not "%CI%"=="1" pause
exit /b 1
