@echo off
setlocal

rem RunTests_D2007.cmd [/ci]  -  builds the Debug console test runner and executes the DUnit suite.
rem Exit code 0 = all tests green, 1 = build failure or red tests.
rem /ci skips the pause on failure (AI agent, CI runner).

call "%~dp0Build_Tests_D2007.cmd" Debug /ci
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
if /I not "%~1"=="/ci" pause
exit /b 1
