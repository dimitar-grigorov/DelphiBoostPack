program DelphiBoostPackTests;

// Delphi DUnit test project.
// Define CONSOLE_TESTRUNNER (Build_Tests_D2007.cmd does) to get the console test runner,
// otherwise the GUI test runner is used.

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
  BpObjectComparer in '..\src\Core\Classes\BpObjectComparer.pas',
  UniqueIdIntf in '..\src\Core\Interfaces\UniqueIdIntf.pas',
  InterfacedCollectionItem in '..\src\Core\Classes\InterfacedCollectionItem.pas',
  BpHashBobJenkinsTests in 'Core\BpHashBobJenkinsTests.pas',
  BpHashBobJenkins in '..\src\Core\Classes\BpHashBobJenkins.pas',
  BpStrDictionaryTests in 'Core\BpStrDictionaryTests.pas',
  BpStrDictionary in '..\src\Core\Classes\BpStrDictionary.pas',
  BpStringBuilderTests in 'Core\BpStringBuilderTests.pas',
  BpStringBuilder in '..\src\Core\Classes\BpStringBuilder.pas',
  BpStrUtilsTests in 'Core\BpStrUtilsTests.pas',
  BpStrUtils in '..\src\Core\Units\BpStrUtils.pas',
  BpSysUtilsTests in 'Core\BpSysUtilsTests.pas',
  BpSysUtils in '..\src\Core\Units\BpSysUtils.pas',
  BpStringOperationsBenchmark in 'Benchmarks\BpStringOperationsBenchmark.pas',
  BpStrDictionaryBenchmark in 'Benchmarks\BpStrDictionaryBenchmark.pas',
  BpStringBuilderBenchmark in 'Benchmarks\BpStringBuilderBenchmark.pas',
  BpStrUtilsBenchmark in 'Benchmarks\BpStrUtilsBenchmark.pas',
  BpBaseBenchmarkTestCase in 'Benchmarks\BpBaseBenchmarkTestCase.pas',
  BpTypesOperationsBenchmark in 'Benchmarks\BpTypesOperationsBenchmark.pas';

{$R *.RES}

var
  lvResult: TTestResult;

begin
  {$IF CompilerVersion >= 18.0}
  System.ReportMemoryLeaksOnShutdown := True;
  {$IFEND}
  Application.Initialize;
  if IsConsole then
  begin
    // Nonzero exit code on red tests so build scripts and CI can gate on the result
    lvResult := TextTestRunner.RunRegisteredTests;
    try
      if not lvResult.WasSuccessful then
        System.ExitCode := 1;
    finally
      lvResult.Free;
    end;
  end
  else
    GUITestRunner.RunRegisteredTests;
end.

