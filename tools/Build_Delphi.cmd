@echo off
setlocal

rem Build_Delphi.cmd <project.dpr|.dproj> [Config] [options]  -  the build core every
rem other script here calls: MSBuild for a .dproj, dcc32 for a .dpr, /d7 for Delphi 7.
rem Run it with no arguments for the option list. The compilers come from the
rem environment, then the registry, then the default path, so nothing is machine bound.

set "CFG="
set "CI="
set "VER=2007"
set "BACKEND="
set "DEFINES="
set "EXTRAUNITS="
set "OUTDIR="
set "DCUDIR="

rem Only a first argument that is not an option is the project: %~f1 would turn
rem a bare /ci into the path D:\ci and swallow the flag with it.
set "PROJFULL="
set "PROJDIR="
set "PROJNAME="
set "PROJEXT="
set "A=%~1"
if "%A%"=="" goto :args
if "%A:~0,1%"=="/" goto :args
set "PROJFULL=%~f1"
set "PROJDIR=%~dp1"
set "PROJNAME=%~n1"
set "PROJEXT=%~x1"
shift

:args
if "%~1"=="" goto :parsed
set "A=%~1"
if /I "%A%"=="/ci"          set "CI=1"
if /I "%A%"=="/d7"          set "VER=7"
if /I "%A%"=="/d2007"       set "VER=2007"
if /I "%A%"=="/dcc"         set "BACKEND=dcc"
if /I "%A:~0,8%"=="/define:" set "DEFINES=%A:~8%"
if /I "%A:~0,7%"=="/units:"  set "EXTRAUNITS=%A:~7%"
if /I "%A:~0,5%"=="/out:"    set "OUTDIR=%A:~5%"
if /I "%A:~0,5%"=="/dcu:"    set "DCUDIR=%A:~5%"
if not "%A:~0,1%"=="/"      set "CFG=%A%"
shift
goto :args
:parsed

if "%PROJFULL%"=="" goto :usage

rem Delphi 7 predates MSBuild and cannot read a .dproj, so take the sibling .dpr.
if not "%VER%"=="7" goto :haveproj
if /I not "%PROJEXT%"==".dproj" goto :haveproj
set "PROJFULL=%PROJDIR%%PROJNAME%.dpr"
set "PROJEXT=.dpr"
:haveproj
if not exist "%PROJFULL%" goto :noproj

if "%VER%"=="7" call :FindD7
if not "%VER%"=="7" call :FindD2007

if "%VER%"=="7" set "BACKEND=dcc"
if defined BACKEND goto :backend
if /I "%PROJEXT%"==".dproj" set "BACKEND=msbuild"
if not defined BACKEND set "BACKEND=dcc"
:backend
if "%BACKEND%"=="msbuild" goto :msbuild

rem --- dcc32 ---------------------------------------------------------------
set "DCC=%COMPROOT%\bin\dcc32.exe"
if not exist "%DCC%" goto :nodcc

if not defined CFG set "CFG=Release"
if not defined OUTDIR set "OUTDIR=%PROJDIR%"
if not defined DCUDIR set "DCUDIR=%TEMP%\BpDcu\%PROJNAME%_D%VER%"
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"
if "%DCUDIR:~-1%"=="\" set "DCUDIR=%DCUDIR:~0,-1%"
if not exist "%OUTDIR%" md "%OUTDIR%"
if not exist "%DCUDIR%" md "%DCUDIR%"

set "DCCDEF="
if /I "%CFG%"=="Release" set "DCCDEF=RELEASE"
if /I "%CFG%"=="Debug" set "DCCDEF=DEBUG"
if defined DEFINES call :JoinDefines
set "DOPT="
if defined DCCDEF set "DOPT=-D%DCCDEF%"

set "UPATH=%COMPLIB%"
if defined EXTRAUNITS set "UPATH=%UPATH%;%EXTRAUNITS%"

rem Delphi 7 spells the dcu output -N; 2007 renamed it -N0 and kept -N as an alias.
set "NOPT=-N0"
if "%VER%"=="7" set "NOPT=-N"

echo Building %PROJNAME% (%CFG%, Delphi %VER%)...
rem dcc32 resolves the "in '<file>.pas'" clauses relative to the current folder.
pushd "%PROJDIR%"
"%DCC%" -B -Q %DOPT% -E"%OUTDIR%" %NOPT%"%DCUDIR%" -U"%UPATH%" -I"%UPATH%" "%PROJNAME%%PROJEXT%"
set "RC=%ERRORLEVEL%"
popd
if not "%RC%"=="0" goto :fail
echo Built %OUTDIR%\%PROJNAME%.exe (%CFG%, Delphi %VER%)
goto :ok

rem --- MSBuild --------------------------------------------------------------
:msbuild
if not defined CFG call :DefaultCfg
call :FindMsBuild
if not exist "%MSBUILD%" goto :nomsbuild

set "MSPROPS="
if defined DEFINES call :EscapeDefines

echo Building %PROJNAME% (%CFG%, Delphi %VER%)...
"%MSBUILD%" "%PROJFULL%" /p:Configuration=%CFG% /p:Platform=AnyCPU %MSPROPS% /t:Build /v:minimal /nologo
if errorlevel 1 goto :fail
echo Built %PROJNAME% (%CFG%, Delphi %VER%)
goto :ok

:ok
endlocal
exit /b 0

:usage
echo Usage: Build_Delphi.cmd ^<project.dpr^|.dproj^> [Config] [/ci] [/d7] [/dcc] [/define:"A;B"] [/units:"A;B"] [/out:DIR] [/dcu:DIR]
goto :bail

:noproj
echo Project not found: %PROJFULL%
goto :bail

:nodcc
echo dcc32 not found at "%DCC%".
echo Set BDS (Delphi 2007) or DELPHI7 to the compiler root and retry.
goto :bail

:nomsbuild
echo MSBuild not found at "%MSBUILD%".
echo Delphi 2007 builds with the 32-bit .NET 2.0 framework, which carries its Borland.Delphi.Targets.
goto :bail

:fail
echo Build failed.
goto :bail

:bail
rem expand %CI% before endlocal drops it, or the pause fires even under /ci
endlocal & if not "%CI%"=="1" pause
exit /b 1

rem --- helpers --------------------------------------------------------------

:FindD2007
if defined BDS goto :bdsroot
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\CodeGear\BDS\5.0" /v RootDir 2^>nul') do set "BDS=%%B"
if not defined BDS for /f "tokens=2,*" %%A in ('reg query "HKLM\Software\CodeGear\BDS\5.0" /v RootDir /reg:32 2^>nul') do set "BDS=%%B"
if defined BDS goto :bdsroot
set "BDS=%ProgramFiles(x86)%\CodeGear\RAD Studio\5.0"
:bdsroot
if "%BDS:~-1%"=="\" set "BDS=%BDS:~0,-1%"
set "COMPROOT=%BDS%"
set "COMPLIB=%BDS%\lib"
goto :eof

:FindD7
if defined DELPHI7 goto :d7root
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Borland\Delphi\7.0" /v RootDir 2^>nul') do set "DELPHI7=%%B"
if not defined DELPHI7 for /f "tokens=2,*" %%A in ('reg query "HKLM\Software\Borland\Delphi\7.0" /v RootDir /reg:32 2^>nul') do set "DELPHI7=%%B"
if defined DELPHI7 goto :d7root
set "DELPHI7=%ProgramFiles(x86)%\Borland\Delphi7"
:d7root
if "%DELPHI7:~-1%"=="\" set "DELPHI7=%DELPHI7:~0,-1%"
set "COMPROOT=%DELPHI7%"
set "COMPLIB=%DELPHI7%\Lib"
goto :eof

rem rsvars.bat points FrameworkDir at Framework64, which has no Borland.Delphi.Targets
:FindMsBuild
set "FWVER=v2.0.50727"
if not exist "%BDS%\bin\rsvars.bat" goto :fwver
for /f "tokens=2 delims==" %%V in ('findstr /i /b /c:"@SET FrameworkVersion=" "%BDS%\bin\rsvars.bat" 2^>nul') do set "FWVER=%%V"
:fwver
set "MSBUILD=%WINDIR%\Microsoft.NET\Framework\%FWVER%\MSBuild.exe"
goto :eof

rem The project's own default configuration, the way the IDE would open it.
:DefaultCfg
for /f "tokens=2 delims=>" %%V in ('findstr /c:"<Configuration Condition=" "%PROJFULL%" 2^>nul') do (
  if not defined CFG for /f "tokens=1 delims=<" %%W in ("%%V") do set "CFG=%%W"
)
if not defined CFG set "CFG=Release"
goto :eof

:JoinDefines
if defined DCCDEF goto :appenddefines
set "DCCDEF=%DEFINES%"
goto :eof
:appenddefines
set "DCCDEF=%DCCDEF%;%DEFINES%"
goto :eof

rem MSBuild reads a ; in a /p: value as a property separator, so rewrite each as %3B
:EscapeDefines
set "MSDEFS="
for %%D in ("%DEFINES:;=" "%") do call :AddDefine %%D
set "MSPROPS=/p:DCC_Define=%MSDEFS%"
goto :eof

:AddDefine
if not defined MSDEFS (
  set "MSDEFS=%~1"
) else (
  set "MSDEFS=%MSDEFS%%%3B%~1"
)
goto :eof
