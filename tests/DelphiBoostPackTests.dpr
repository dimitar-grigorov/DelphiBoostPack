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
  BpIntListUnit in '..\src\Core\Classes\BpIntListUnit.pas',
  IBpIntListUnit in '..\src\Core\Interfaces\IBpIntListUnit.pas',
  BpIntListBenchmark in 'Core\BpIntListBenchmark.pas',
  BpIntListMemoryTests in 'Core\BpIntListMemoryTests.pas',
  BpObjectComparerCollectionClasses in 'Core\BpObjectComparerCollectionClasses.pas',
  BpObjectComparerSimpleClasses in 'Core\BpObjectComparerSimpleClasses.pas',
  BpObjectComparerSimpleTests in 'Core\BpObjectComparerSimpleTests.pas',
  BpObjectComparerUnit in '..\src\Core\Classes\BpObjectComparerUnit.pas',
  IUniqueIdUnit in '..\src\Core\Interfaces\IUniqueIdUnit.pas';

{$R *.RES}

begin
  System.ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  if IsConsole then
    TextTestRunner.RunRegisteredTests
  else
    GUITestRunner.RunRegisteredTests;
end.

