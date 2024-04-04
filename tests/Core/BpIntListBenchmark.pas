unit BpIntListBenchmark;

interface

uses
  TestFramework, Classes, bpIntList, SysUtils, BpIntListInterface;

type
  TbpIntListBenchmark = class(TTestCase)
  strict private
    FBpIntList: TBpIntList;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddPerformance;
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

  lvStartTick := 0;
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
  if (lvDurationRatio > 0) then
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

initialization
  RegisterTest(TbpIntListBenchmark.Suite);

end.

