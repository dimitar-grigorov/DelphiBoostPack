program DelphiBoostPackTests;

// DUnit test project; CONSOLE_TESTRUNNER (set by Build_Tests_D2007.cmd)
// picks the console runner, otherwise the GUI runner is used.

{$IFDEF CONSOLE_TESTRUNNER}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  Forms,
  TestFramework,
  GUITestRunner,
  TextTestRunner,
{$IFDEF BENCHMARK}
  // performance benchmarks, opt-in: build with BENCHMARK defined to include them
  BpBaseBenchmarkTestCase in 'Benchmarks\BpBaseBenchmarkTestCase.pas',
  BpIntListBenchmark in 'Core\BpIntListBenchmark.pas',
  BpStringOperationsBenchmark in 'Benchmarks\BpStringOperationsBenchmark.pas',
  BpStrDictionaryBenchmark in 'Benchmarks\BpStrDictionaryBenchmark.pas',
  BpIntDictionaryBenchmark in 'Benchmarks\BpIntDictionaryBenchmark.pas',
  BpStringBuilderBenchmark in 'Benchmarks\BpStringBuilderBenchmark.pas',
  BpStrUtilsBenchmark in 'Benchmarks\BpStrUtilsBenchmark.pas',
  BpBase64Benchmark in 'Benchmarks\BpBase64Benchmark.pas',
  BpHashBenchmark in 'Benchmarks\BpHashBenchmark.pas',
  BpTypesOperationsBenchmark in 'Benchmarks\BpTypesOperationsBenchmark.pas',
{$ENDIF}
  BpIntListTests in 'Core\BpIntListTests.pas',
  BpIntList in '..\src\Core\Classes\BpIntList.pas',
  BpIntListIntf in '..\src\Core\Interfaces\BpIntListIntf.pas',
  BpIntListMemoryTests in 'Core\BpIntListMemoryTests.pas',
  BpInt64ListTests in 'Core\BpInt64ListTests.pas',
  BpInt64List in '..\src\Core\Classes\BpInt64List.pas',
  BpInt64ListIntf in '..\src\Core\Interfaces\BpInt64ListIntf.pas',
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
  BpDateUtilsTests in 'Core\BpDateUtilsTests.pas',
  BpDateUtils in '..\src\Core\Units\BpDateUtils.pas',
  BpHMACSHA256Tests in 'Core\BpHMACSHA256Tests.pas',
  BpHMACSHA256 in '..\src\Core\Classes\BpHMACSHA256.pas',
  BpCancellationTokenTests in 'Core\BpCancellationTokenTests.pas',
  BpCredentialsTests in 'Core\BpCredentialsTests.pas',
  BpCredentials in '..\src\Core\Classes\BpCredentials.pas',
  BpHttpClientTests in 'Core\BpHttpClientTests.pas',
  BpHttpClient in '..\src\Core\Classes\BpHttpClient.pas',
  BpHttpDownloadTests in 'Core\BpHttpDownloadTests.pas',
  BpHttpTraceTests in 'Core\BpHttpTraceTests.pas',
  BpHttpTrace in '..\src\Core\Classes\BpHttpTrace.pas',
  BpIntDictionaryTests in 'Core\BpIntDictionaryTests.pas',
  BpIntDictionary in '..\src\Core\Classes\BpIntDictionary.pas',
  BpJsonTests in 'Core\BpJsonTests.pas',
  BpJson in '..\src\Core\Classes\BpJson.pas',
  BpMD5Tests in 'Core\BpMD5Tests.pas',
  BpMD5 in '..\src\Core\Classes\BpMD5.pas',
  BpPasswordHashTests in 'Core\BpPasswordHashTests.pas',
  BpPasswordHash in '..\src\Core\Classes\BpPasswordHash.pas',
  BpSHA256Tests in 'Core\BpSHA256Tests.pas',
  BpSHA256 in '..\src\Core\Classes\BpSHA256.pas',
  BpCryptoApiHash in 'Core\BpCryptoApiHash.pas',
  BpStrUtilsTests in 'Core\BpStrUtilsTests.pas',
  BpStrUtils in '..\src\Core\Units\BpStrUtils.pas',
  BpSysUtilsTests in 'Core\BpSysUtilsTests.pas',
  BpSysUtils in '..\src\Core\Units\BpSysUtils.pas',
  BpTasksTests in 'Core\BpTasksTests.pas',
  BpTasks in '..\src\Core\Classes\BpTasks.pas',
  BpVariantUtilsTests in 'Core\BpVariantUtilsTests.pas',
  BpVariantUtils in '..\src\Core\Units\BpVariantUtils.pas',
  BpKeyFoldTests in 'Core\BpKeyFoldTests.pas',
  BpKeyFold in '..\src\Core\Units\BpKeyFold.pas',
  BpStringListTests in 'Core\BpStringListTests.pas',
  BpStringList in '..\src\Core\Classes\BpStringList.pas',
  BpCompat in '..\src\Core\Units\BpCompat.pas',
  BpStopWatchTests in 'Core\BpStopWatchTests.pas',
  StopWatch in '..\src\Core\Units\StopWatch.pas';

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

