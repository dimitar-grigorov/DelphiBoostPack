unit BpJsonBenchmark;

// The two shapes that decide how TbpJsonValue should store object members: one
// object with very many of them, and very many objects with a few each. Both
// documents are built here, so no large fixture has to be committed.

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpBaseBenchmarkTestCase, BpStringBuilder, BpJson;

type
  TBpJsonBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    FFlat: string;
    FSmall: string;
    FDeepBad: string;
  public
    procedure SetUp; override;
  published
    procedure TestParseFlatObject;
    procedure TestLookupInFlatObject;
    procedure TestParseManySmallObjects;
    procedure TestBuildFlatObject;
    procedure TestFailADeeplyNestedDocument;
  end;

implementation

const
  gcFlatMembers = 20000;  // one object, which is where a linear scan squares
  gcSmallObjects = 20000; // four members each, the shape of a real document
  gcRuns = 5;             // one reading is worth nothing on a boosting CPU
  gcDeepLevels = 500;     // just inside the parser's depth limit
  gcFailCount = 200;      // one failed parse is too quick to time

function MemberName(aIndex: Integer): string;
begin
  Result := 'member_' + IntToStr(aIndex);
end;

procedure TBpJsonBenchmark.SetUp;
var
  lvSb: TbpStringBuilder;
  i: Integer;
begin
  inherited;
  lvSb := TbpStringBuilder.Create;
  try
    lvSb.Append('{');
    for i := 0 to gcFlatMembers - 1 do
    begin
      if i > 0 then
        lvSb.Append(',');
      lvSb.Append('"').Append(MemberName(i)).Append('":').Append(IntToStr(i));
    end;
    lvSb.Append('}');
    FFlat := lvSb.ToString;

    lvSb.Clear;
    lvSb.Append('[');
    for i := 0 to gcSmallObjects - 1 do
    begin
      if i > 0 then
        lvSb.Append(',');
      lvSb.Append('{"id":').Append(IntToStr(i))
        .Append(',"name":"row","ok":true,"score":1.5}');
    end;
    lvSb.Append(']');
    FSmall := lvSb.ToString;

    // unwinding this costs whatever each nesting level charges
    FDeepBad := StringOfChar('[', gcDeepLevels) + 'x';
  finally
    lvSb.Free;
  end;
end;

procedure TBpJsonBenchmark.TestParseFlatObject;
var
  lvValue: TbpJsonValue;
  i: Integer;
begin
  for i := 1 to gcRuns do
  begin
    StartBenchmark;
    lvValue := TbpJsonValue.Parse(FFlat);
    StopBenchmark;
    try
      CheckEquals(gcFlatMembers, lvValue.Count);
    finally
      lvValue.Free;
    end;
  end;
  LogStatusFmt('Parse one object of %d members (%d KB) - %.3f ms median of %d',
    [gcFlatMembers, Length(FFlat) div 1024, MedianTime, SampleCount]);
end;

procedure TBpJsonBenchmark.TestLookupInFlatObject;
var
  lvValue: TbpJsonValue;
  i, j, lvSum: Integer;
begin
  lvValue := TbpJsonValue.Parse(FFlat);
  try
    for j := 1 to gcRuns do
    begin
      lvSum := 0;
      StartBenchmark;
      for i := 0 to gcFlatMembers - 1 do
        Inc(lvSum, lvValue.GetIntDef(MemberName(i), -1));
      StopBenchmark;
      CheckEquals(gcFlatMembers * (gcFlatMembers - 1) div 2, lvSum);
    end;
    LogStatusFmt('Look up all %d members by name - %.3f ms median of %d',
      [gcFlatMembers, MedianTime, SampleCount]);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonBenchmark.TestParseManySmallObjects;
var
  lvValue: TbpJsonValue;
  i: Integer;
begin
  for i := 1 to gcRuns do
  begin
    StartBenchmark;
    lvValue := TbpJsonValue.Parse(FSmall);
    StopBenchmark;
    try
      CheckEquals(gcSmallObjects, lvValue.Count);
    finally
      lvValue.Free;
    end;
  end;
  LogStatusFmt('Parse %d objects of 4 members (%d KB) - %.3f ms median of %d',
    [gcSmallObjects, Length(FSmall) div 1024, MedianTime, SampleCount]);
end;

procedure TBpJsonBenchmark.TestBuildFlatObject;
var
  lvValue: TbpJsonValue;
  i, j: Integer;
begin
  for j := 1 to gcRuns do
  begin
    lvValue := TbpJsonValue.CreateObject;
    try
      StartBenchmark;
      for i := 0 to gcFlatMembers - 1 do
        lvValue.SetInt(MemberName(i), i);
      StopBenchmark;
      CheckEquals(gcFlatMembers, lvValue.Count);
    finally
      lvValue.Free;
    end;
  end;
  LogStatusFmt('Build one object of %d members with SetInt - %.3f ms median of %d',
    [gcFlatMembers, MedianTime, SampleCount]);
end;

procedure TBpJsonBenchmark.TestFailADeeplyNestedDocument;
var
  lvValue: TbpJsonValue;
  i, j: Integer;
begin
  for i := 1 to gcRuns do
  begin
    StartBenchmark;
    for j := 1 to gcFailCount do
      if TbpJsonValue.TryParse(FDeepBad, lvValue) then
      begin
        lvValue.Free;
        Fail('the document is malformed');
      end;
    StopBenchmark;
  end;
  LogStatusFmt('Fail a %d level malformed document %d times - %.3f ms median of %d',
    [gcDeepLevels, gcFailCount, MedianTime, SampleCount]);
end;

initialization
  RegisterTest(TBpJsonBenchmark.Suite);


end.
