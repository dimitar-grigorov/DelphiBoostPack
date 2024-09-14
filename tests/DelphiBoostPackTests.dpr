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
  BpIntListIntf in '..\src\Core\Interfaces\BpIntListIntf.pas',
  BpIntListBenchmark in 'Core\BpIntListBenchmark.pas',
  BpIntListMemoryTests in 'Core\BpIntListMemoryTests.pas',
  BpObjectComparerCollectionClasses in 'Core\BpObjectComparerCollectionClasses.pas',
  BpObjectComparerSimpleClasses in 'Core\BpObjectComparerSimpleClasses.pas',
  BpObjectComparerSimpleTests in 'Core\BpObjectComparerSimpleTests.pas',
  BpObjectComparerUnit in '..\src\Core\Classes\BpObjectComparerUnit.pas',
  UniqueIdIntf in '..\src\Core\Interfaces\UniqueIdIntf.pas',
  InterfacedCollectionItemUnit in '..\src\Core\Classes\InterfacedCollectionItemUnit.pas',
  BpHashBobJenkinsTests in 'Core\BpHashBobJenkinsTests.pas',
  BpHashBobJenkinsUnit in '..\src\Core\Classes\BpHashBobJenkinsUnit.pas',
  BpSysUtilsTests in 'Core\BpSysUtilsTests.pas',
  BpSysUtils in '..\src\Core\Units\BpSysUtils.pas',
  BpStringOperationsBenchmark in 'Benchmarks\BpStringOperationsBenchmark.pas',
  BpBaseBenchmarkTestCase in 'Benchmarks\BpBaseBenchmarkTestCase.pas',
  BpTypesOperationsBenchmark in 'Benchmarks\BpTypesOperationsBenchmark.pas';

{$R *.RES}

begin
  {$IF CompilerVersion >= 18.0}
  System.ReportMemoryLeaksOnShutdown := True;
  {$IFEND}
  Application.Initialize;
  if IsConsole then
    TextTestRunner.RunRegisteredTests
  else
    GUITestRunner.RunRegisteredTests;
end.

