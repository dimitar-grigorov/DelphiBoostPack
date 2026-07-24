@echo off
setlocal

rem RunTests_D2007.cmd [/ci] [/bench] [/nointeg]  -  builds the Debug console test runner and executes the DUnit suite.
rem Exit code 0 = all tests green, 1 = build failure or red tests.
rem By default runs unit + integration tests; /bench adds benchmarks, /nointeg drops integration.
rem /ci skips the pause on failure (AI agent, CI runner).

set "CI="
for %%A in (%*) do if /I "%%A"=="/ci" set "CI=1"

call "%~dp0Build_Tests_D2007.cmd" Debug /ci %*
if errorlevel 1 goto :buildfail

"%~dp0tests\!bin\DelphiBoostPackTests.exe"
if errorlevel 1 goto :testfail

echo All tests passed.
endlocal
exit /b 0

:buildfail
echo Test build failed.
goto :fail

:testfail
echo Test run reported failures.

:fail
endlocal
rem Skip pause when invoked non-interactively (AI agent, CI runner).
if not "%CI%"=="1" pause
exit /b 1
