unit BpStrDictionaryBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, IniFiles, Variants, BpBaseBenchmarkTestCase,
  BpStrDictionary;

type
  // TbpStrDictionary vs the classic D2007 options: unsorted TStringList.IndexOf,
  // sorted TStringList.Find and IniFiles.THashedStringList.IndexOf
  TBpStrDictionaryBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    FKeys: TStringList;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInsertBpStrDictionary;
    procedure TestInsertStringList;
    procedure TestInsertSortedStringList;
    procedure TestInsertHashedStringList;
    procedure TestLookupBpStrDictionary;
    procedure TestLookupStringListIndexOf;
    procedure TestLookupSortedStringListFind;
    procedure TestLookupHashedStringList;
  end;

implementation

const
  NUM_KEYS = 10000;

procedure TBpStrDictionaryBenchmark.SetUp;
var
  i: Integer;
begin
  inherited;
  FKeys := TStringList.Create;
  FKeys.Capacity := NUM_KEYS;
  for i := 1 to NUM_KEYS do
    FKeys.Add('SomeSampleKey' + IntToStr(i));
end;

procedure TBpStrDictionaryBenchmark.TearDown;
begin
  FreeAndNil(FKeys);
  inherited;
end;

procedure TBpStrDictionaryBenchmark.TestInsertBpStrDictionary;
var
  lvDict: TbpStrDictionary;
  i: Integer;
begin
  lvDict := TbpStrDictionary.Create;
  try
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvDict.Add(FKeys[i], i);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvDict.Count);
    LogStatusFmt('Insert %d: TbpStrDictionary - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvDict.Free;
  end;
end;

procedure TBpStrDictionaryBenchmark.TestInsertStringList;
var
  lvList: TStringList;
  i: Integer;
begin
  lvList := TStringList.Create;
  try
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvList.AddObject(FKeys[i], TObject(i));
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvList.Count);
    LogStatusFmt('Insert %d: TStringList - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpStrDictionaryBenchmark.TestInsertSortedStringList;
var
  lvList: TStringList;
  i: Integer;
begin
  lvList := TStringList.Create;
  try
    lvList.Sorted := True;
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvList.AddObject(FKeys[i], TObject(i));
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvList.Count);
    LogStatusFmt('Insert %d: sorted TStringList - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpStrDictionaryBenchmark.TestInsertHashedStringList;
var
  lvList: THashedStringList;
  i: Integer;
begin
  lvList := THashedStringList.Create;
  try
    StartBenchmark;
    for i := 0 to NUM_KEYS - 1 do
      lvList.AddObject(FKeys[i], TObject(i));
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvList.Count);
    LogStatusFmt('Insert %d: THashedStringList - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpStrDictionaryBenchmark.TestLookupBpStrDictionary;
var
  lvDict: TbpStrDictionary;
  lvValue: Variant;
  lvFound, i: Integer;
begin
  lvDict := TbpStrDictionary.Create;
  try
    for i := 0 to NUM_KEYS - 1 do
      lvDict.Add(FKeys[i], i);
    lvFound := 0;
    StartBenchmark;
    for i := NUM_KEYS - 1 downto 0 do
      if lvDict.TryGetValue(FKeys[i], lvValue) then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('Lookup %d: TbpStrDictionary - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvDict.Free;
  end;
end;

procedure TBpStrDictionaryBenchmark.TestLookupStringListIndexOf;
var
  lvList: TStringList;
  lvFound, i: Integer;
begin
  lvList := TStringList.Create;
  try
    lvList.Assign(FKeys);
    lvFound := 0;
    StartBenchmark;
    for i := NUM_KEYS - 1 downto 0 do
      if lvList.IndexOf(FKeys[i]) >= 0 then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('Lookup %d: TStringList.IndexOf - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpStrDictionaryBenchmark.TestLookupSortedStringListFind;
var
  lvList: TStringList;
  lvFound, lvIndex, i: Integer;
begin
  lvList := TStringList.Create;
  try
    lvList.Assign(FKeys);
    lvList.Sorted := True;
    lvFound := 0;
    StartBenchmark;
    for i := NUM_KEYS - 1 downto 0 do
      if lvList.Find(FKeys[i], lvIndex) then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('Lookup %d: sorted TStringList.Find - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

procedure TBpStrDictionaryBenchmark.TestLookupHashedStringList;
var
  lvList: THashedStringList;
  lvFound, i: Integer;
begin
  lvList := THashedStringList.Create;
  try
    lvList.Assign(FKeys);
    lvFound := 0;
    StartBenchmark;
    for i := NUM_KEYS - 1 downto 0 do
      if lvList.IndexOf(FKeys[i]) >= 0 then
        Inc(lvFound);
    StopBenchmark;
    CheckEquals(NUM_KEYS, lvFound);
    LogStatusFmt('Lookup %d: THashedStringList.IndexOf - %.3f ms', [NUM_KEYS, GetElapsedTime]);
  finally
    lvList.Free;
  end;
end;

initialization
  RegisterTest(TBpStrDictionaryBenchmark.Suite);

end.
