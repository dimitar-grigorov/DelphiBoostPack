@echo off
setlocal

rem Build_Tests_D2007.cmd [Debug|Release] [/ci] [/bench] [/nointeg]  -  rebuilds tests\!bin\DelphiBoostPackTests.exe.
rem Both configs carry the DUnit source paths, and CONSOLE_TESTRUNNER is forced so the exe runs on the console.
rem Kinds: unit always, integration unless /nointeg (NO_INTEGRATION), benchmarks only with /bench (BENCHMARK).
rem /ci skips the pause on failure (AI agent, CI runner).

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
if /I "%~1"=="/ci"      set "CI=/ci"
if /I "%~1"=="/bench"   set "BENCH=1"
if /I "%~1"=="/nointeg" set "NOINTEG=1"
shift
goto :parseargs
:parsed

set "DEFINES=DEBUG"
if /I "%CFG%"=="Release" set "DEFINES=RELEASE"
set "DEFINES=%DEFINES%;CONSOLE_TESTRUNNER"
if defined BENCH set "DEFINES=%DEFINES%;BENCHMARK"
if defined NOINTEG set "DEFINES=%DEFINES%;NO_INTEGRATION"

set "KINDS=unit"
if not defined NOINTEG set "KINDS=%KINDS% + integration"
if defined BENCH set "KINDS=%KINDS% + benchmarks"
echo Test kinds: %KINDS%

call "%HERE%tools\Build_Delphi.cmd" "%HERE%tests\DelphiBoostPackTests.dproj" %CFG% "/define:%DEFINES%" %CI%
if errorlevel 1 goto :fail

echo Built %HERE%tests\!bin\DelphiBoostPackTests.exe (%CFG%)
endlocal
exit /b 0

rem Build_Delphi.cmd has already reported and paused, so just carry the code out.
:fail
endlocal
exit /b 1
