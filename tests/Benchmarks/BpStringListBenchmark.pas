unit BpStringListBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, IniFiles, BpBaseBenchmarkTestCase, BpStringList;

type
  // every number docs/FEATURES.md publishes for TbpStringList, each against
  // the RTL class a caller would otherwise reach for
  TBpStringListBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    FKeys: TStringList;        // in insertion order
    FShuffled: TStringList;    // the same keys, shuffled once with a fixed seed
    procedure FillIndexed(aList: TStrings);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAdd;
    procedure TestIndexOf;
    procedure TestAddAndIndexOfInterleaved;
    procedure TestIndexOfName;
    procedure TestSortedAdd;
    procedure TestSort;
    procedure TestDeleteLoop;
    procedure TestMiddleInsertLoop;
  end;

implementation

const
  NUM_KEYS = 50000;
  NUM_INTERLEAVED = 10000;    // THashedStringList rebuilds its hash per write, so fewer
  NUM_MUTATED = 20000;        // the middle mutation loops move memory per step

procedure TBpStringListBenchmark.SetUp;
var
  i, j: Integer;
begin
  inherited;
  FKeys := TStringList.Create;
  FKeys.Capacity := NUM_KEYS;
  for i := 1 to NUM_KEYS do
    FKeys.Add('SomeSampleKey' + IntToStr(i));
  FShuffled := TStringList.Create;
  FShuffled.Assign(FKeys);
  RandSeed := 20260905;
  for i := NUM_KEYS - 1 downto 1 do
  begin
    j := Random(i + 1);
    FShuffled.Exchange(i, j);
  end;
end;

procedure TBpStringListBenchmark.TearDown;
begin
  FreeAndNil(FShuffled);
  FreeAndNil(FKeys);
  inherited;
end;

// fills the list and, for ours, warms the index so the timed loop measures
// maintenance rather than the one-off build
procedure TBpStringListBenchmark.FillIndexed(aList: TStrings);
begin
  aList.Assign(FKeys);
  aList.IndexOf(FKeys[0]);
end;

procedure TBpStringListBenchmark.TestAdd;
var
  lvRtl: TStringList;
  lvOurs: TbpStringList;
  i: Integer;
begin
  lvRtl := TStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvRtl.Add(FKeys[i]);
    StopBenchmark;
    LogStatusFmt('Add %d: TStringList - %.2f ms', [NUM_KEYS, GetElapsedTime]);
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvOurs.Add(FKeys[i]);
    StopBenchmark;
    LogStatusFmt('Add %d: TbpStringList - %.2f ms (no index yet)', [NUM_KEYS, GetElapsedTime]);
    lvOurs.Clear;
    lvOurs.Add(FKeys[0]);
    lvOurs.IndexOf(FKeys[0]);
    StartBenchmark;
    for i := 1 to NUM_KEYS - 1 do
      lvOurs.Add(FKeys[i]);
    StopBenchmark;
    LogStatusFmt('Add %d: TbpStringList - %.2f ms (index live)', [NUM_KEYS, GetElapsedTime]);
    CheckEquals(NUM_KEYS, lvOurs.Count);
  finally
    lvOurs.Free;
    lvRtl.Free;
  end;
end;

procedure TBpStringListBenchmark.TestIndexOf;
var
  lvHashed: THashedStringList;
  lvOurs: TbpStringList;
  i, lvFound: Integer;
begin
  lvHashed := THashedStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    FillIndexed(lvHashed);
    FillIndexed(lvOurs);
    lvFound := 0;
    StartBenchmark;
    for i := NUM_KEYS - 1 downto 0 do
      if lvHashed.IndexOf(FShuffled[i]) >= 0 then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('IndexOf %d: THashedStringList - %.2f ms', [NUM_KEYS, GetElapsedTime]);
    lvFound := 0;
    StartBenchmark;
    for i := NUM_KEYS - 1 downto 0 do
      if lvOurs.IndexOf(FShuffled[i]) >= 0 then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('IndexOf %d: TbpStringList - %.2f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvOurs.Free;
    lvHashed.Free;
  end;
end;

procedure TBpStringListBenchmark.TestAddAndIndexOfInterleaved;
var
  lvHashed: THashedStringList;
  lvOurs: TbpStringList;
  i, lvFound: Integer;
begin
  lvHashed := THashedStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    lvFound := 0;
    StartBenchmark;
    for i := 0 to NUM_INTERLEAVED - 1 do
    begin
      lvHashed.Add(FKeys[i]);
      if lvHashed.IndexOf(FKeys[i div 2]) >= 0 then
        Inc(lvFound);
    end;
    StopBenchmark;
    CheckEquals(NUM_INTERLEAVED, lvFound);
    LogStatusFmt('Add+IndexOf %d: THashedStringList - %.2f ms', [NUM_INTERLEAVED, GetElapsedTime]);
    lvFound := 0;
    StartBenchmark;
    for i := 0 to NUM_INTERLEAVED - 1 do
    begin
      lvOurs.Add(FKeys[i]);
      if lvOurs.IndexOf(FKeys[i div 2]) >= 0 then
        Inc(lvFound);
    end;
    StopBenchmark;
    CheckEquals(NUM_INTERLEAVED, lvFound);
    LogStatusFmt('Add+IndexOf %d: TbpStringList - %.2f ms', [NUM_INTERLEAVED, GetElapsedTime]);
  finally
    lvOurs.Free;
    lvHashed.Free;
  end;
end;

procedure TBpStringListBenchmark.TestIndexOfName;
var
  lvRtl: TStringList;
  lvOurs: TbpStringList;
  i, lvFound: Integer;
begin
  lvRtl := TStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    for i := 0 to NUM_KEYS - 1 do
    begin
      lvRtl.Add(FKeys[i] + '=' + IntToStr(i));
      lvOurs.Add(FKeys[i] + '=' + IntToStr(i));
    end;
    lvOurs.IndexOfName(FKeys[0]);
    lvFound := 0;
    StartBenchmark;
    // every 25th key, or the quadratic RTL scan takes a minute
    for i := 0 to NUM_KEYS div 25 - 1 do
      if lvRtl.IndexOfName(FShuffled[i]) >= 0 then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS div 25, lvFound);
    LogStatusFmt('IndexOfName %d of %d: TStringList - %.2f ms', [NUM_KEYS div 25, NUM_KEYS, GetElapsedTime]);
    lvFound := 0;
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      if lvOurs.IndexOfName(FShuffled[i]) >= 0 then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('IndexOfName %d of %d: TbpStringList - %.2f ms', [NUM_KEYS, NUM_KEYS, GetElapsedTime]);
  finally
    lvOurs.Free;
    lvRtl.Free;
  end;
end;

procedure TBpStringListBenchmark.TestSortedAdd;
var
  lvRtl: TStringList;
  lvOurs: TbpStringList;
  i: Integer;
begin
  lvRtl := TStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    lvRtl.Sorted := True;
    lvOurs.Sorted := True;
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvRtl.Add(FShuffled[i]);
    StopBenchmark;
    LogStatusFmt('Sorted Add %d: TStringList - %.2f ms', [NUM_KEYS, GetElapsedTime]);
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvOurs.Add(FShuffled[i]);
    StopBenchmark;
    LogStatusFmt('Sorted Add %d: TbpStringList - %.2f ms', [NUM_KEYS, GetElapsedTime]);
    CheckEquals(NUM_KEYS, lvOurs.Count);
  finally
    lvOurs.Free;
    lvRtl.Free;
  end;
end;

procedure TBpStringListBenchmark.TestSort;
var
  lvRtl: TStringList;
  lvOurs: TbpStringList;
begin
  lvRtl := TStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    lvRtl.Assign(FShuffled);
    lvOurs.Assign(FShuffled);
    StartBenchmark;
    lvRtl.Sort;
    StopBenchmark;
    LogStatusFmt('Sort %d: TStringList - %.2f ms', [NUM_KEYS, GetElapsedTime]);
    StartBenchmark;
    lvOurs.Sort;
    StopBenchmark;
    LogStatusFmt('Sort %d: TbpStringList - %.2f ms (stable)', [NUM_KEYS, GetElapsedTime]);
    CheckEquals(lvRtl[0], lvOurs[0]);
  finally
    lvOurs.Free;
    lvRtl.Free;
  end;
end;

// Delete from the middle until empty, with the index live on ours
procedure TBpStringListBenchmark.TestDeleteLoop;
var
  lvRtl: TStringList;
  lvOurs: TbpStringList;
  i: Integer;
begin
  lvRtl := TStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    for i := 0 to NUM_MUTATED - 1 do
    begin
      lvRtl.Add(FKeys[i]);
      lvOurs.Add(FKeys[i]);
    end;
    lvOurs.IndexOf(FKeys[0]);
    StartBenchmark;
    while lvRtl.Count > 0 do
      lvRtl.Delete(lvRtl.Count div 2);
    StopBenchmark;
    LogStatusFmt('Delete loop %d: TStringList - %.2f ms', [NUM_MUTATED, GetElapsedTime]);
    StartBenchmark;
    while lvOurs.Count > 0 do
      lvOurs.Delete(lvOurs.Count div 2);
    StopBenchmark;
    LogStatusFmt('Delete loop %d: TbpStringList - %.2f ms (index live)', [NUM_MUTATED, GetElapsedTime]);
  finally
    lvOurs.Free;
    lvRtl.Free;
  end;
end;

// Insert into the middle, with a lookup every 100 rows so the watermark refresh is paid
procedure TBpStringListBenchmark.TestMiddleInsertLoop;
var
  lvRtl: TStringList;
  lvOurs: TbpStringList;
  i, lvFound: Integer;
begin
  lvRtl := TStringList.Create;
  lvOurs := TbpStringList.Create;
  try
    lvFound := 0;
    StartBenchmark;
    for i := 0 to NUM_MUTATED - 1 do
    begin
      lvRtl.Insert(lvRtl.Count div 2, FKeys[i]);
      if (i mod 100 = 0) and (lvRtl.IndexOf(FKeys[i div 2]) >= 0) then
        Inc(lvFound);
    end;
    StopBenchmark;
    LogStatusFmt('Middle Insert %d + IndexOf every 100: TStringList - %.2f ms', [NUM_MUTATED, GetElapsedTime]);
    lvFound := 0;
    StartBenchmark;
    for i := 0 to NUM_MUTATED - 1 do
    begin
      lvOurs.Insert(lvOurs.Count div 2, FKeys[i]);
      if (i mod 100 = 0) and (lvOurs.IndexOf(FKeys[i div 2]) >= 0) then
        Inc(lvFound);
    end;
    StopBenchmark;
    LogStatusFmt('Middle Insert %d + IndexOf every 100: TbpStringList - %.2f ms', [NUM_MUTATED, GetElapsedTime]);
    CheckEquals(NUM_MUTATED div 100, lvFound);
  finally
    lvOurs.Free;
    lvRtl.Free;
  end;
end;

initialization
  RegisterTest(TBpStringListBenchmark.Suite);

end.
