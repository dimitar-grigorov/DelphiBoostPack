@echo off
rem Build_Main_D7.cmd [/ci]  -  compiles every library unit with Delphi 7.
rem src\DelphiBoostPack.dpr uses them all, so a green build here is the whole
rem D7 compatibility gate; the exe itself is a stub and goes to src\!bin\D7.
rem /ci skips the pause on failure (AI agent, CI runner).

call "%~dp0tools\Build_Delphi.cmd" "%~dp0src\DelphiBoostPack.dpr" Release /d7 "/out:%~dp0src\!bin\D7" %*
exit /b %ERRORLEVEL%
