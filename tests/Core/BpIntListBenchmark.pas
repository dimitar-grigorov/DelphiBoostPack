unit BpIntListBenchmark;

interface

uses
  TestFramework, Classes, BpIntListUnit, SysUtils, IBpIntListUnit;

type
  TbpIntListBenchmark = class(TTestCase)
  strict private
    FBpIntList: TBpIntList;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddPerformance;
    procedure TestSearchPerformance;
  end;

implementation

uses
  Windows, PsAPI;

procedure TbpIntListBenchmark.SetUp;
begin
  FBpIntList := TBpIntList.Create;
end;

procedure TbpIntListBenchmark.TearDown;
begin
  FBpIntList.Free;
  FBpIntList := nil;
end;

procedure TbpIntListBenchmark.TestAddPerformance;
var
  lvIntList: TBpIntList;
  lvStrList: TStringList;
  lvStartTick, lvEndTick: Cardinal;
  lvDurationIntList, lvDurationStrList, lvMemoryIntList, lvMemoryStrList: Cardinal;
  lvDurationRatio, lvMemoryRatio: Double;
  lvProcessMemoryBefore, lvProcessMemoryAfter: PROCESS_MEMORY_COUNTERS;
  lvMemStatus: TMemoryStatus;
  I: Integer;
const
  lcIntegersToAdd = 45000000; // 45 million
  lcTwoGB: Cardinal = 2147483648; // 2GB in bytes
begin
  lvDurationRatio := 0;
  lvMemoryRatio := 0;
  lvMemStatus.dwLength := SizeOf(TMemoryStatus);
  GlobalMemoryStatus(lvMemStatus); // Retrieve the memory status
  if (lvMemStatus.dwAvailPhys < lcTwoGB) then
    Fail('Insufficient memory available to run test: less than 2 GB RAM free');

  lvProcessMemoryBefore.cb := SizeOf(lvProcessMemoryBefore);
  lvProcessMemoryAfter.cb := SizeOf(lvProcessMemoryAfter);

  // Test TBpIntList
  lvIntList := TBpIntList.Create;
  try
    GetProcessMemoryInfo(GetCurrentProcess(), @lvProcessMemoryBefore, SizeOf(lvProcessMemoryBefore));
    lvStartTick := GetTickCount;
    for I := 1 to lcIntegersToAdd do
      lvIntList.Add(I);
    lvEndTick := GetTickCount;
    GetProcessMemoryInfo(GetCurrentProcess(), @lvProcessMemoryAfter, SizeOf(lvProcessMemoryAfter));
    lvDurationIntList := lvEndTick - lvStartTick;
    lvMemoryIntList := (lvProcessMemoryAfter.WorkingSetSize - lvProcessMemoryBefore.WorkingSetSize) div 1024;
  finally
    lvIntList.Free;
  end;

  // Reset memory measurement for TStringList
  FillChar(lvProcessMemoryBefore, SizeOf(lvProcessMemoryBefore), 0);
  FillChar(lvProcessMemoryAfter, SizeOf(lvProcessMemoryAfter), 0);
  lvProcessMemoryBefore.cb := SizeOf(lvProcessMemoryBefore);
  lvProcessMemoryAfter.cb := SizeOf(lvProcessMemoryAfter);

  // Test TStringList
  lvStrList := TStringList.Create;
  try
    GetProcessMemoryInfo(GetCurrentProcess(), @lvProcessMemoryBefore, SizeOf(lvProcessMemoryBefore));
    lvStartTick := GetTickCount;
    for I := 1 to lcIntegersToAdd do
      lvStrList.Add(IntToStr(I));
    lvEndTick := GetTickCount;
    GetProcessMemoryInfo(GetCurrentProcess(), @lvProcessMemoryAfter, SizeOf(lvProcessMemoryAfter));
    lvDurationStrList := lvEndTick - lvStartTick;
    lvMemoryStrList := (lvProcessMemoryAfter.WorkingSetSize - lvProcessMemoryBefore.WorkingSetSize) div 1024;
  finally
    lvStrList.Free;
  end;

  // Calculate the ratios
  if (lvDurationIntList > 0) then
    lvDurationRatio := lvDurationStrList / lvDurationIntList;
  if (lvMemoryIntList > 0) then
    lvMemoryRatio := lvMemoryStrList / lvMemoryIntList;

  // Output results
  Status(Format('Integers count: %d', [lcIntegersToAdd]));
  Status(EmptyStr);
  Status(Format('TBpIntList Duration: %d ms', [lvDurationIntList]));
  Status(Format('TStringList Duration: %d ms', [lvDurationStrList]));
  Status(Format('Duration Ratio (String/Int List): %.2f', [lvDurationRatio]));
  Status(EmptyStr);
  Status(Format('TBpIntList Memory Usage: %d KB', [lvMemoryIntList]));
  Status(Format('TStringList Memory Usage: %d KB', [lvMemoryStrList]));
  Status(Format('Memory Usage Ratio (String/Int List): %.2f', [lvMemoryRatio]));
end;

procedure TbpIntListBenchmark.TestSearchPerformance;
var
  lvStartTick, lvEndTick, Frequency: Int64;
  I, J: Integer;
  FoundIndex: Integer;
  ElapsedTimeIndexOf, ElapsedTimeBinarySearch, SingleRunTime: Double;
  TotalStepsIndexOf, TotalStepsBinarySearch: Int64;
const
  SearchValues: array[0..9] of Integer = (1, 250, 500, 750, 1000, 5000, 7500, 10000, 50000, 100000);
  RepeatCount = 100; // Number of times to repeat the search to average the timings
begin
  FBpIntList.Sorted := True;
  for I := 1 to 100000 do
    FBpIntList.Add(I);

  QueryPerformanceFrequency(Frequency);
  ElapsedTimeIndexOf := 0;
  ElapsedTimeBinarySearch := 0;
  TotalStepsIndexOf := 0;
  TotalStepsBinarySearch := 0;

  // Testing IndexOf
  for J := 1 to RepeatCount do
  begin
    QueryPerformanceCounter(lvStartTick);
    for I := Low(SearchValues) to High(SearchValues) do
    begin
      FBpIntList.IndexOf(SearchValues[I]);
      TotalStepsIndexOf := TotalStepsIndexOf + FBpIntList.StepCount;
    end;
    QueryPerformanceCounter(lvEndTick);
    SingleRunTime := (lvEndTick - lvStartTick) * 1000.0 / Frequency;
    ElapsedTimeIndexOf := ElapsedTimeIndexOf + SingleRunTime;
  end;
  Status(Format('IndexOf Average Time: %f ms', [ElapsedTimeIndexOf / RepeatCount]));
  Status(Format('IndexOf Average Steps: %f', [TotalStepsIndexOf / (RepeatCount * Length(SearchValues))]));

  // Testing BinarySearch
  for J := 1 to RepeatCount do
  begin
    QueryPerformanceCounter(lvStartTick);
    for I := Low(SearchValues) to High(SearchValues) do
    begin
      FBpIntList.BinarySearch(SearchValues[I], FoundIndex);
      TotalStepsBinarySearch := TotalStepsBinarySearch + FBpIntList.StepCount;
    end;
    QueryPerformanceCounter(lvEndTick);
    SingleRunTime := (lvEndTick - lvStartTick) * 1000.0 / Frequency;
    ElapsedTimeBinarySearch := ElapsedTimeBinarySearch + SingleRunTime;
  end;
  Status(Format('BinarySearch Average Time: %f ms', [ElapsedTimeBinarySearch / RepeatCount]));
  Status(Format('BinarySearch Average Steps: %f', [TotalStepsBinarySearch / (RepeatCount * Length(SearchValues))]));
end;




initialization
  RegisterTest(TbpIntListBenchmark.Suite);

end.

