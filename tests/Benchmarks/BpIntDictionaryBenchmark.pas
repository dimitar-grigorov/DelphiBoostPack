unit BpIntDictionaryBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, BpBaseBenchmarkTestCase, BpIntDictionary;

type
  // TbpIntDictionary vs the classic D2007 integer-lookup options:
  // linear scan over a TList (the Locate-style pattern) and sorted binary search
  TBpIntDictionaryBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    FKeys: array of Int64;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInsertBpIntDictionary;
    procedure TestInsertSequentialBpIntDictionary;
    procedure TestLookupBpIntDictionary;
    procedure TestLookupListLinearScan;
    procedure TestLookupSortedBinarySearch;
  end;

implementation

const
  NUM_KEYS = 10000;

procedure TBpIntDictionaryBenchmark.SetUp;
var
  i: Integer;
begin
  inherited;
  // pseudo-random distinct 64-bit keys, deterministic across runs
  RandSeed := 20260708;
  SetLength(FKeys, NUM_KEYS);
  for i := 0 to NUM_KEYS - 1 do
    FKeys[i] := Int64(Random(MaxInt)) * 100000 + i;
end;

procedure TBpIntDictionaryBenchmark.TearDown;
begin
  FKeys := nil;
  inherited;
end;

procedure TBpIntDictionaryBenchmark.TestInsertBpIntDictionary;
var
  lvDict: TbpIntDictionary;
  i: Integer;
begin
  lvDict := TbpIntDictionary.Create;
  try
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvDict.Add(FKeys[i], i);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvDict.Count);
    LogStatusFmt('Insert %d random: TbpIntDictionary - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvDict.Free;
  end;
end;

procedure TBpIntDictionaryBenchmark.TestInsertSequentialBpIntDictionary;
var
  lvDict: TbpIntDictionary;
  i: Integer;
begin
  lvDict := TbpIntDictionary.Create;
  try
    StartBenchmark;
    for i := 1 to NUM_KEYS do
      lvDict.Add(i, i);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvDict.Count);
    LogStatusFmt('Insert %d sequential: TbpIntDictionary - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvDict.Free;
  end;
end;

procedure TBpIntDictionaryBenchmark.TestLookupBpIntDictionary;
var
  lvDict: TbpIntDictionary;
  lvFound, i: Integer;
begin
  lvDict := TbpIntDictionary.Create;
  try
    for i := 0 to NUM_KEYS - 1 do
      lvDict.SetInt(FKeys[i], i);
    lvFound := 0;
    StartBenchmark;
    for i := NUM_KEYS - 1 downto 0 do
      if lvDict.ContainsKey(FKeys[i]) then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('Lookup %d: TbpIntDictionary - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvDict.Free;
  end;
end;

procedure TBpIntDictionaryBenchmark.TestLookupListLinearScan;
var
  lvList: array of Int64;
  lvFound, i, j: Integer;
begin
  // the TDataSet.Locate access pattern: walk all rows until the id matches
  SetLength(lvList, NUM_KEYS);
  for i := 0 to NUM_KEYS - 1 do
    lvList[i] := FKeys[i];
  lvFound := 0;
  StartBenchmark;
  for i := NUM_KEYS - 1 downto 0 do
    for j := 0 to NUM_KEYS - 1 do
      if lvList[j] = FKeys[i] then
      begin
        Inc(lvFound);
        Break;
      end;
  StopBenchmark;
  CheckEquals(NUM_KEYS, lvFound);
  LogStatusFmt('Lookup %d: linear scan (Locate pattern) - %.3f ms', [NUM_KEYS, GetElapsedTime]);
end;

procedure TBpIntDictionaryBenchmark.TestLookupSortedBinarySearch;
var
  lvSorted: array of Int64;
  lvFound, i, lvLo, lvHi, lvMid: Integer;
  lvTmp: Int64;
  j, lvMinIdx: Integer;
begin
  // selection sort is fine here, it happens outside the timed section
  SetLength(lvSorted, NUM_KEYS);
  for i := 0 to NUM_KEYS - 1 do
    lvSorted[i] := FKeys[i];
  for i := 0 to NUM_KEYS - 2 do
  begin
    lvMinIdx := i;
    for j := i + 1 to NUM_KEYS - 1 do
      if lvSorted[j] < lvSorted[lvMinIdx] then
        lvMinIdx := j;
    if lvMinIdx <> i then
    begin
      lvTmp := lvSorted[i];
      lvSorted[i] := lvSorted[lvMinIdx];
      lvSorted[lvMinIdx] := lvTmp;
    end;
  end;
  lvFound := 0;
  StartBenchmark;
  for i := NUM_KEYS - 1 downto 0 do
  begin
    lvLo := 0;
    lvHi := NUM_KEYS - 1;
    while lvLo <= lvHi do
    begin
      lvMid := (lvLo + lvHi) shr 1;
      if lvSorted[lvMid] = FKeys[i] then
      begin
        Inc(lvFound);
        Break;
      end
      else if lvSorted[lvMid] < FKeys[i] then
        lvLo := lvMid + 1
      else
        lvHi := lvMid - 1;
    end;
  end;
  StopBenchmark;
  CheckEquals(NUM_KEYS, lvFound);
  LogStatusFmt('Lookup %d: sorted binary search - %.3f ms', [NUM_KEYS, GetElapsedTime]);
end;

initialization
  RegisterTest(TBpIntDictionaryBenchmark.Suite);

end.
