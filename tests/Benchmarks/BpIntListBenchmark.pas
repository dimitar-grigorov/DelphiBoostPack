unit BpIntListBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, BpBaseBenchmarkTestCase, BpIntList;

type
  // TbpIntList vs a linear TList scan and a sorted TStringList of IntToStr keys
  TBpIntListBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    FValues: array of Integer;
    FProbes: array of Integer;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBuildBpIntList;
    procedure TestLookupBpIntList;
    procedure TestLookupBpIntListSorted;
    procedure TestLookupTListLinearScan;
    procedure TestLookupSortedStringList;
    procedure TestSortOrganPipe;
  end;

implementation

const
  gcCount = 20000;
  gcProbes = 2000;

procedure TBpIntListBenchmark.SetUp;
var
  i: Integer;
begin
  inherited;
  // distinct values with a stride, so an identity hash would show up as collisions
  RandSeed := 20260905;
  SetLength(FValues, gcCount);
  for i := 0 to gcCount - 1 do
    FValues[i] := i * 7 + 3;
  // probes in random order, deterministic across runs
  SetLength(FProbes, gcProbes);
  for i := 0 to gcProbes - 1 do
    FProbes[i] := FValues[Random(gcCount)];
end;

procedure TBpIntListBenchmark.TearDown;
begin
  FValues := nil;
  FProbes := nil;
  inherited;
end;

procedure TBpIntListBenchmark.TestBuildBpIntList;
var
  lvList: TbpIntList;
  i: Integer;
begin
  lvList := TbpIntList.Create;
  try
    StartBenchmark;
    for i := 0 to gcCount - 1 do
      lvList.Add(FValues[i]);
    StopBenchmark;
    CheckEquals(gcCount, lvList.Count, 'every value was added');
    LogStatusFmt('Build %d values: %.2f ms', [gcCount, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

// the first lookup pays for the index, the rest are chain walks
procedure TBpIntListBenchmark.TestLookupBpIntList;
var
  lvList: TbpIntList;
  i, lvHits: Integer;
begin
  lvList := TbpIntList.Create;
  try
    for i := 0 to gcCount - 1 do
      lvList.Add(FValues[i]);
    lvHits := 0;
    StartBenchmark;
    for i := 0 to gcProbes - 1 do
      if lvList.IndexOf(FProbes[i]) >= 0 then
        Inc(lvHits);
    StopBenchmark;
    CheckEquals(gcProbes, lvHits, 'every probe is a value that is in the list');
    LogStatusFmt('TbpIntList.IndexOf, %d probes over %d values: %.2f ms',
      [gcProbes, gcCount, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpIntListBenchmark.TestLookupBpIntListSorted;
var
  lvList: TbpIntList;
  i, lvHits: Integer;
begin
  lvList := TbpIntList.Create;
  try
    for i := 0 to gcCount - 1 do
      lvList.Add(FValues[i]);
    lvList.Sorted := True;
    lvHits := 0;
    StartBenchmark;
    for i := 0 to gcProbes - 1 do
      if lvList.IndexOf(FProbes[i]) >= 0 then
        Inc(lvHits);
    StopBenchmark;
    CheckEquals(gcProbes, lvHits, 'every probe is a value that is in the list');
    LogStatusFmt('TbpIntList.IndexOf while Sorted (bisects), %d probes: %.2f ms',
      [gcProbes, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpIntListBenchmark.TestLookupTListLinearScan;
var
  lvList: TList;
  i, j, lvHits: Integer;
begin
  lvList := TList.Create;
  try
    for i := 0 to gcCount - 1 do
      lvList.Add(Pointer(FValues[i]));
    lvHits := 0;
    StartBenchmark;
    for i := 0 to gcProbes - 1 do
      for j := 0 to lvList.Count - 1 do
        if Integer(lvList[j]) = FProbes[i] then
        begin
          Inc(lvHits);
          Break;
        end;
    StopBenchmark;
    CheckEquals(gcProbes, lvHits, 'every probe is a value that is in the list');
    LogStatusFmt('TList linear scan, %d probes: %.2f ms', [gcProbes, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpIntListBenchmark.TestLookupSortedStringList;
var
  lvList: TStringList;
  i, lvHits: Integer;
begin
  lvList := TStringList.Create;
  try
    for i := 0 to gcCount - 1 do
      lvList.Add(IntToStr(FValues[i]));
    lvList.Sorted := True;
    lvHits := 0;
    StartBenchmark;
    for i := 0 to gcProbes - 1 do
      if lvList.IndexOf(IntToStr(FProbes[i])) >= 0 then
        Inc(lvHits);
    StopBenchmark;
    CheckEquals(gcProbes, lvHits, 'every probe is a value that is in the list');
    LogStatusFmt('sorted TStringList of IntToStr keys, %d probes: %.2f ms',
      [gcProbes, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

// the input that makes a middle-pivot quicksort recurse Count/2 deep
procedure TBpIntListBenchmark.TestSortOrganPipe;
const
  lcCount = 400000;
var
  lvList: TbpIntList;
  i: Integer;
begin
  lvList := TbpIntList.Create;
  try
    for i := 0 to lcCount - 1 do
      if i < lcCount div 2 then
        lvList.Add(i)
      else
        lvList.Add(lcCount - i);
    StartBenchmark;
    lvList.Sort;
    StopBenchmark;
    for i := 1 to lvList.Count - 1 do
      if lvList[i - 1] > lvList[i] then
        Fail(Format('out of order at %d', [i]));
    LogStatusFmt('sort %d organ-pipe values: %.2f ms', [lcCount, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

initialization
  RegisterTest(TBpIntListBenchmark.Suite);

end.
