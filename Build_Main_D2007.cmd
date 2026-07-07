@echo off
setlocal

rem Build_Main_D2007.cmd [Release|Debug] [/ci]  -  rebuilds src\!bin\DelphiBoostPack.exe.
rem Default config is Release. /ci skips the pause on failure (AI agent, CI runner).

if not defined BDS set "BDS=C:\Program Files (x86)\CodeGear\RAD Studio\5.0"
set "MSBUILD=%WINDIR%\Microsoft.NET\Framework\v2.0.50727\MSBuild.exe"

set "CFG=%~1"
if "%CFG%"=="" set "CFG=Release"

echo Building DelphiBoostPack (%CFG%)...
"%MSBUILD%" "%~dp0src\DelphiBoostPack.dproj" /p:Configuration=%CFG% /p:Platform=AnyCPU /t:Build /v:minimal /nologo
if errorlevel 1 goto :fail

echo Built %~dp0src\!bin\DelphiBoostPack.exe (%CFG%)
endlocal
exit /b 0

:fail
echo Build failed.
endlocal
rem Skip pause when invoked non-interactively (AI agent, CI runner).
if /I not "%~2"=="/ci" pause
exit /b 1
