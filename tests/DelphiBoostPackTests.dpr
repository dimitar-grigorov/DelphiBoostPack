program DelphiBoostPackTests;
{

  Delphi DUnit Test Project
  -------------------------
  This project contains the DUnit test framework and the GUI/Console test runners.
  Add "CONSOLE_TESTRUNNER" to the conditional defines entry in the project options 
  to use the console test runner.  Otherwise the GUI test runner will be used by 
  default.

}

{$IFDEF CONSOLE_TESTRUNNER}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  Forms,
  TestFramework,
  GUITestRunner,
  TextTestRunner,
  BpIntListTests in 'Core\BpIntListTests.pas',
  BpIntList in '..\src\Core\Classes\BpIntList.pas',
  BpIntListInterface in '..\src\Core\Interfaces\BpIntListInterface.pas',
  BpIntListBenchmark in 'Core\BpIntListBenchmark.pas',
  BpIntListMemoryTests in 'Core\BpIntListMemoryTests.pas';

{$R *.RES}

begin
  System.ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  if IsConsole then
    TextTestRunner.RunRegisteredTests
  else
    GUITestRunner.RunRegisteredTests;
end.

