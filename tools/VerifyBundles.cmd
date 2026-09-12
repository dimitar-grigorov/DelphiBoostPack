@echo off
setlocal

rem VerifyBundles.cmd [/ci] [/d7]  -  checks each dist bundle against the src
rem units it was generated from, then compiles it standalone and runs its smoke
rem test. The smoke programs see ONLY the dist folder, so a bundle that still
rem needs a modular unit fails to compile here. /d7 runs the same check with
rem Delphi 7, the compatibility floor the README claims.

set "HERE=%~dp0"
set "CI="
set "D7="
for %%A in (%*) do if /I "%%A"=="/ci" set "CI=1"
for %%A in (%*) do if /I "%%A"=="/d7" set "D7=/d7"

set "SCRATCH=%TEMP%\BpVerifyBundles"
if exist "%SCRATCH%" rd /s /q "%SCRATCH%"
md "%SCRATCH%"

rem compiling proves nothing about being current, so the drift check comes first
node "%HERE%Amalgamate.js" --check
if errorlevel 1 goto :fail

set "FAILED="
for %%B in (BpDictionaries BpHashes BpHttpClientStandalone BpJsonStandalone BundlesTogether) do call :Verify %%B
if defined FAILED goto :fail

echo All bundles verified.
endlocal
exit /b 0

rem Sets FAILED rather than exiting, so a red bundle still reports its log.
:Verify
echo Verifying %~1...
call "%HERE%Build_Delphi.cmd" "%HERE%smoke\Smoke%~1.dpr" Release %D7% /ci "/units:%HERE%..\dist" "/out:%SCRATCH%" "/dcu:%SCRATCH%" > "%SCRATCH%\%~1.log" 2>&1
if errorlevel 1 goto :verifyfail
"%SCRATCH%\Smoke%~1.exe"
if errorlevel 1 goto :verifyfail
goto :eof

:verifyfail
type "%SCRATCH%\%~1.log"
set "FAILED=1"
goto :eof

:fail
echo Bundle verification FAILED.
rem expand %CI% before endlocal drops it, or the pause fires even under /ci
endlocal & if not "%CI%"=="1" pause
exit /b 1
