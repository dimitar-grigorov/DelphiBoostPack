@echo off
rem Build_Main_D2007.cmd [Release|Debug] [/ci]  -  rebuilds src\!bin\DelphiBoostPack.exe.
rem The project's own default config is Release. /ci skips the pause on failure (AI agent, CI runner).

call "%~dp0tools\Build_Delphi.cmd" "%~dp0src\DelphiBoostPack.dproj" %*
exit /b %ERRORLEVEL%
