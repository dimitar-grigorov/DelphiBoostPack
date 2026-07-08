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
  BpBase64Tests in 'Core\BpBase64Tests.pas',
  BpBase64 in '..\src\Core\Units\BpBase64.pas',
  BpHMACSHA256Tests in 'Core\BpHMACSHA256Tests.pas',
  BpHMACSHA256 in '..\src\Core\Classes\BpHMACSHA256.pas',
  BpHttpClientTests in 'Core\BpHttpClientTests.pas',
  BpHttpClient in '..\src\Core\Classes\BpHttpClient.pas',
  BpIntDictionaryTests in 'Core\BpIntDictionaryTests.pas',
  BpIntDictionary in '..\src\Core\Classes\BpIntDictionary.pas',
  BpMD5Tests in 'Core\BpMD5Tests.pas',
  BpMD5 in '..\src\Core\Classes\BpMD5.pas',
  BpSHA256Tests in 'Core\BpSHA256Tests.pas',
  BpSHA256 in '..\src\Core\Classes\BpSHA256.pas',
  BpCryptoApiHash in 'Core\BpCryptoApiHash.pas',
  BpStrUtilsTests in 'Core\BpStrUtilsTests.pas',
  BpStrUtils in '..\src\Core\Units\BpStrUtils.pas',
  BpSysUtilsTests in 'Core\BpSysUtilsTests.pas',
  BpSysUtils in '..\src\Core\Units\BpSysUtils.pas',
  BpVariantUtils in '..\src\Core\Units\BpVariantUtils.pas',
  BpStringOperationsBenchmark in 'Benchmarks\BpStringOperationsBenchmark.pas',
  BpStrDictionaryBenchmark in 'Benchmarks\BpStrDictionaryBenchmark.pas',
  BpIntDictionaryBenchmark in 'Benchmarks\BpIntDictionaryBenchmark.pas',
  BpStringBuilderBenchmark in 'Benchmarks\BpStringBuilderBenchmark.pas',
  BpStrUtilsBenchmark in 'Benchmarks\BpStrUtilsBenchmark.pas',
  BpBase64Benchmark in 'Benchmarks\BpBase64Benchmark.pas',
  BpHashBenchmark in 'Benchmarks\BpHashBenchmark.pas',
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

