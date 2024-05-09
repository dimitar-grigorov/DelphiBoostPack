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
    procedure TestSearchPerformanceDistributed;
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
  lvStartTick, lvEndTick, lvFrequency, TotalStepsIndexOf, TotalStepsBinarySearch: Int64;
  I, J, FoundIndex: Integer;
  ElapsedTimeIndexOf, ElapsedTimeBinarySearch, SingleRunTime: Double;
const
  lcSearchValues: array[0..19] of Integer = (1, 50, 250, 500, 750, 1000, 2500, 5000,
    7500, 10000, 20000, 30000, 40000, 50000, 60000, 70000, 80000, 90000, 95000, 100000);
  lcRepeatCount = 50; // Number of times to repeat the search to average the timings
begin
  for I := 1 to 2000000 do
    FBpIntList.Add(I);
  FBpIntList.Sorted := True;

  QueryPerformanceFrequency(lvFrequency);
  ElapsedTimeIndexOf := 0;
  ElapsedTimeBinarySearch := 0;
  TotalStepsIndexOf := 0;
  TotalStepsBinarySearch := 0;

  // Testing IndexOf
  for J := 1 to lcRepeatCount do
  begin
    QueryPerformanceCounter(lvStartTick);
    for I := Low(lcSearchValues) to High(lcSearchValues) do
    begin
      FBpIntList.IndexOf(lcSearchValues[I]);
      TotalStepsIndexOf := TotalStepsIndexOf + FBpIntList.StepCount;
    end;
    QueryPerformanceCounter(lvEndTick);
    SingleRunTime := (lvEndTick - lvStartTick) * 1000.0 / lvFrequency;
    ElapsedTimeIndexOf := ElapsedTimeIndexOf + SingleRunTime;
  end;
  Status(Format('IndexOf Average Time: %f ms', [ElapsedTimeIndexOf / lcRepeatCount]));
  Status(Format('IndexOf Average Steps: %f', [TotalStepsIndexOf / (lcRepeatCount * Length(lcSearchValues))]));

  // Testing BinarySearch
  for J := 1 to lcRepeatCount do
  begin
    QueryPerformanceCounter(lvStartTick);
    for I := Low(lcSearchValues) to High(lcSearchValues) do
    begin
      FBpIntList.BinarySearch(lcSearchValues[I], FoundIndex);
      TotalStepsBinarySearch := TotalStepsBinarySearch + FBpIntList.StepCount;
    end;
    QueryPerformanceCounter(lvEndTick);
    SingleRunTime := (lvEndTick - lvStartTick) * 1000.0 / lvFrequency;
    ElapsedTimeBinarySearch := ElapsedTimeBinarySearch + SingleRunTime;
  end;
  Status(Format('BinarySearch Average Time: %f ms', [ElapsedTimeBinarySearch / lcRepeatCount]));
  Status(Format('BinarySearch Average Steps: %f', [TotalStepsBinarySearch / (lcRepeatCount * Length(lcSearchValues))]));
end;

procedure TbpIntListBenchmark.TestSearchPerformanceDistributed;
var
  lvStartTick, lvEndTick, lvFrequency, TotalStepsIndexOf, TotalStepsBinarySearch: Int64;
  I, J, FoundIndex: Integer;
  ElapsedTimeIndexOf, ElapsedTimeBinarySearch, SingleRunTime: Double;
  SearchValues: array of Integer;
const
  lcRepeatCount = 50; // Number of times to repeat the search to average the timings
  lcNumSearchValues = 50; // Total number of search values
begin
  Randomize;
  SetLength(SearchValues, lcNumSearchValues);
  FBpIntList.Clear;

  for I := 1 to 2000000 do
    if Random(10) > 2 then  // 80% chance to add the number, creating some gaps
      FBpIntList.Add(I);
  FBpIntList.Sorted := True;

  for I := 0 to High(SearchValues) do
  begin
    if Random(2) = 0 then  // 50% chance to pick from the list
      SearchValues[I] := FBpIntList.Items[Random(FBpIntList.Count)]
    else
      SearchValues[I] := Random(2000000) + 1;
  end;

  QueryPerformanceFrequency(lvFrequency);
  ElapsedTimeIndexOf := 0;
  ElapsedTimeBinarySearch := 0;
  TotalStepsIndexOf := 0;
  TotalStepsBinarySearch := 0;

  // Testing IndexOf
  for J := 1 to lcRepeatCount do
  begin
    QueryPerformanceCounter(lvStartTick);
    for I := Low(SearchValues) to High(SearchValues) do
    begin
      FBpIntList.IndexOf(SearchValues[I]);
      TotalStepsIndexOf := TotalStepsIndexOf + FBpIntList.StepCount;
    end;
    QueryPerformanceCounter(lvEndTick);
    SingleRunTime := (lvEndTick - lvStartTick) * 1000.0 / lvFrequency;
    ElapsedTimeIndexOf := ElapsedTimeIndexOf + SingleRunTime;
  end;
  Status(Format('IndexOf Average Time: %f ms', [ElapsedTimeIndexOf / lcRepeatCount]));
  Status(Format('IndexOf Average Steps: %f', [TotalStepsIndexOf / (lcRepeatCount * lcNumSearchValues)]));

  // Testing BinarySearch
  for J := 1 to lcRepeatCount do
  begin
    QueryPerformanceCounter(lvStartTick);
    for I := Low(SearchValues) to High(SearchValues) do
    begin
      FBpIntList.BinarySearch(SearchValues[I], FoundIndex);
      TotalStepsBinarySearch := TotalStepsBinarySearch + FBpIntList.StepCount;
    end;
    QueryPerformanceCounter(lvEndTick);
    SingleRunTime := (lvEndTick - lvStartTick) * 1000.0 / lvFrequency;
    ElapsedTimeBinarySearch := ElapsedTimeBinarySearch + SingleRunTime;
  end;
  Status(Format('BinarySearch Average Time: %f ms', [ElapsedTimeBinarySearch / lcRepeatCount]));
  Status(Format('BinarySearch Average Steps: %f', [TotalStepsBinarySearch / (lcRepeatCount * lcNumSearchValues)]));
end;

initialization
  RegisterTest(TbpIntListBenchmark.Suite);

end.

