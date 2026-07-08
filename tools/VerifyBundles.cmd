@echo off
setlocal enabledelayedexpansion

rem VerifyBundles.cmd [/ci]  -  compiles each dist bundle standalone with the
rem D2007 command-line compiler and runs its smoke test. The smoke programs
rem see ONLY the dist folder, so a bundle that still needs a modular unit
rem fails to compile here.

if not defined BDS set "BDS=C:\Program Files (x86)\CodeGear\RAD Studio\5.0"
set "DCC=%BDS%\bin\dcc32.exe"
set "SCRATCH=%TEMP%\BpVerifyBundles"
if exist "%SCRATCH%" rd /s /q "%SCRATCH%"
md "%SCRATCH%"

for %%B in (BpDictionaries BpHashes BpHttpClientStandalone) do (
  echo Verifying %%B...
  "%DCC%" -B -Q -E"%SCRATCH%" -N0"%SCRATCH%" -U"%~dp0..\dist" "%~dp0smoke\Smoke%%B.dpr" > "%SCRATCH%\%%B.log" 2>&1
  if errorlevel 1 (
    type "%SCRATCH%\%%B.log"
    goto :fail
  )
  "%SCRATCH%\Smoke%%B.exe"
  if errorlevel 1 goto :fail
)

echo All bundles verified.
endlocal
exit /b 0

:fail
echo Bundle verification FAILED.
endlocal
rem Skip pause when invoked non-interactively (AI agent, CI runner).
if /I not "%~1"=="/ci" pause
exit /b 1
