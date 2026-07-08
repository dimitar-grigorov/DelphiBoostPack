unit BpIntDictionaryTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Variants, BpIntDictionary;

type
  TBpIntDictionaryTests = class(TTestCase)
  private
    FDict: TbpIntDictionary;
    FForEachSum: Int64;
    FForEachCalls: Integer;
    FForEachStopAfter: Integer;
    procedure SumCallback(AKey: Int64; const AValue: Variant; var AStop: Boolean);
    procedure AddDuplicateKey;
    procedure GetMissingKey;
    procedure GetStrOnIntValue;
    procedure SetTooSmallCapacity;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddAndGet;
    procedure TestDuplicateAddRaises;
    procedure TestAddOrSet;
    procedure TestTryGetValueMissing;
    procedure TestRemove;
    procedure TestRemoveBackwardShiftParity;
    procedure TestNegativeAndExtremeKeys;
    procedure TestKeyZeroSurvivesNeighborRemoval;
    procedure TestSequentialIds;
    procedure TestGrowthKeepsAllKeys;
    procedure TestSetCapacity;
    procedure TestClearAndReuse;
    procedure TestGetKeys;
    procedure TestForEach;
    procedure TestTypedAccessors;
    procedure TestTypedAccessorStrictness;
    procedure TestItemsDefaultProperty;
    procedure TestHashDistribution;
  end;

implementation

procedure TBpIntDictionaryTests.SetUp;
begin
  inherited;
  FDict := TbpIntDictionary.Create;
end;

procedure TBpIntDictionaryTests.TearDown;
begin
  FreeAndNil(FDict);
  inherited;
end;

procedure TBpIntDictionaryTests.TestAddAndGet;
begin
  CheckEquals(0, FDict.Count);
  FDict.Add(1, 'one');
  FDict.Add(2, 'two');
  FDict.Add(1000000000000, 'big');
  CheckEquals(3, FDict.Count);
  CheckEquals('one', string(FDict[1]));
  CheckEquals('two', string(FDict[2]));
  CheckEquals('big', string(FDict[1000000000000]));
  CheckTrue(FDict.ContainsKey(2));
  CheckFalse(FDict.ContainsKey(3));
end;

procedure TBpIntDictionaryTests.AddDuplicateKey;
begin
  FDict.Add(42, 'again');
end;

procedure TBpIntDictionaryTests.TestDuplicateAddRaises;
begin
  FDict.Add(42, 'first');
  CheckException(AddDuplicateKey, EbpIntDictionary);
  CheckEquals(1, FDict.Count);
  CheckEquals('first', string(FDict[42]));
end;

procedure TBpIntDictionaryTests.TestAddOrSet;
begin
  FDict.AddOrSet(7, 'a');
  FDict.AddOrSet(7, 'b');
  CheckEquals(1, FDict.Count);
  CheckEquals('b', string(FDict[7]));
end;

procedure TBpIntDictionaryTests.TestTryGetValueMissing;
var
  lvValue: Variant;
begin
  CheckFalse(FDict.TryGetValue(5, lvValue));
  CheckTrue(VarIsEmpty(lvValue));
  FDict.Add(5, 55);
  CheckTrue(FDict.TryGetValue(5, lvValue));
  CheckEquals(55, Integer(lvValue));
end;

procedure TBpIntDictionaryTests.TestRemove;
begin
  FDict.Add(1, 'x');
  FDict.Add(2, 'y');
  CheckTrue(FDict.Remove(1));
  CheckEquals(1, FDict.Count);
  CheckFalse(FDict.ContainsKey(1));
  CheckFalse(FDict.Remove(1), 'second remove reports False');
  CheckTrue(FDict.ContainsKey(2));
  // removed key can be added again
  FDict.Add(1, 'z');
  CheckEquals('z', string(FDict[1]));
end;

procedure TBpIntDictionaryTests.TestRemoveBackwardShiftParity;
var
  lvKeys: array of Int64;
  lvAlive: array of Boolean;
  i, lvRound: Integer;
  lvKey: Int64;
begin
  // deterministic random insert/remove storm; after every round each alive
  // key must be findable with its value and each dead key must be missing.
  // this exercises cluster shifts and wraparound far better than fixed cases
  RandSeed := 20260708;
  SetLength(lvKeys, 400);
  SetLength(lvAlive, 400);
  for i := 0 to High(lvKeys) do
  begin
    // spread across positive and negative 64-bit space, keep them distinct
    lvKey := Int64(Random(MaxInt)) * 100000 + i;
    if Random(2) = 0 then
      lvKey := -lvKey;
    lvKeys[i] := lvKey;
    lvAlive[i] := True;
    FDict.Add(lvKey, i);
  end;
  for lvRound := 1 to 3 do
  begin
    // remove a random half, verify, add them back, verify
    for i := 0 to High(lvKeys) do
      if lvAlive[i] and (Random(2) = 0) then
      begin
        CheckTrue(FDict.Remove(lvKeys[i]));
        lvAlive[i] := False;
      end;
    for i := 0 to High(lvKeys) do
      if lvAlive[i] then
        CheckEquals(i, FDict.GetInt(lvKeys[i]), Format('round %d key %d', [lvRound, i]))
      else
        CheckFalse(FDict.ContainsKey(lvKeys[i]), Format('round %d dead key %d', [lvRound, i]));
    for i := 0 to High(lvKeys) do
      if not lvAlive[i] then
      begin
        FDict.Add(lvKeys[i], i);
        lvAlive[i] := True;
      end;
    CheckEquals(Length(lvKeys), FDict.Count);
  end;
end;

procedure TBpIntDictionaryTests.TestNegativeAndExtremeKeys;
begin
  FDict.Add(0, 'zero');
  FDict.Add(-1, 'minus one');
  FDict.Add(Low(Int64), 'lowest');
  FDict.Add(High(Int64), 'highest');
  CheckEquals(4, FDict.Count);
  CheckEquals('zero', string(FDict[0]));
  CheckEquals('minus one', string(FDict[-1]));
  CheckEquals('lowest', string(FDict[Low(Int64)]));
  CheckEquals('highest', string(FDict[High(Int64)]));
  CheckTrue(FDict.Remove(Low(Int64)));
  CheckFalse(FDict.ContainsKey(Low(Int64)));
  CheckEquals('highest', string(FDict[High(Int64)]));
end;

procedure TBpIntDictionaryTests.TestKeyZeroSurvivesNeighborRemoval;
var
  i: Integer;
begin
  // cleared slots get Key reset to 0; a real key 0 entry must stay reachable
  // through any amount of neighbor removal around it
  FDict.Add(0, 'real zero');
  for i := 1 to 100 do
    FDict.Add(i, i);
  for i := 1 to 100 do
    CheckTrue(FDict.Remove(i));
  CheckEquals(1, FDict.Count);
  CheckEquals('real zero', string(FDict[0]));
end;

procedure TBpIntDictionaryTests.TestSequentialIds;
var
  i: Integer;
begin
  // the TDataSet index pattern: dense sequential ids
  for i := 1 to 100000 do
    FDict.SetInt(i, i * 2);
  CheckEquals(100000, FDict.Count);
  for i := 1 to 100000 do
    if FDict.GetInt(i) <> i * 2 then
      Fail(Format('wrong value for key %d', [i]));
  CheckFalse(FDict.ContainsKey(100001));
end;

procedure TBpIntDictionaryTests.TestGrowthKeepsAllKeys;
var
  i: Integer;
begin
  // walk through several grow thresholds and re-verify everything each time
  for i := 1 to 200 do
  begin
    FDict.Add(i * 31, i);
    if (FDict.Count and (FDict.Count - 1)) = 0 then  // at powers of two
      CheckEquals(1, FDict.GetInt(31), 'first key alive after growth');
  end;
  for i := 1 to 200 do
    CheckEquals(i, FDict.GetInt(i * 31));
  CheckTrue(FDict.Capacity >= FDict.Count, 'capacity covers count');
  CheckEquals(0, FDict.Capacity and (FDict.Capacity - 1), 'capacity is a power of two');
end;

procedure TBpIntDictionaryTests.SetTooSmallCapacity;
begin
  FDict.SetCapacity(1);
end;

procedure TBpIntDictionaryTests.TestSetCapacity;
var
  i: Integer;
begin
  FDict.SetCapacity(1000);
  CheckEquals(1024, FDict.Capacity);
  for i := 1 to 700 do
    FDict.Add(i, i);
  CheckEquals(1024, FDict.Capacity, 'preallocation absorbed the inserts');
  CheckException(SetTooSmallCapacity, EbpIntDictionary);
end;

procedure TBpIntDictionaryTests.TestClearAndReuse;
begin
  FDict.Add(1, 'a');
  FDict.Add(2, 'b');
  FDict.Clear;
  CheckEquals(0, FDict.Count);
  CheckEquals(0, FDict.Capacity);
  CheckFalse(FDict.ContainsKey(1));
  FDict.Add(1, 'again');
  CheckEquals('again', string(FDict[1]));
end;

procedure TBpIntDictionaryTests.TestGetKeys;
var
  lvKeys: TbpInt64DynArray;
  i, j: Integer;
  lvTmp: Int64;
begin
  lvKeys := FDict.GetKeys;
  CheckEquals(0, Length(lvKeys));
  FDict.Add(30, 3);
  FDict.Add(-10, 1);
  FDict.Add(20, 2);
  lvKeys := FDict.GetKeys;
  CheckEquals(3, Length(lvKeys));
  // order is storage order; sort for a stable comparison
  for i := 0 to High(lvKeys) - 1 do
    for j := i + 1 to High(lvKeys) do
      if lvKeys[j] < lvKeys[i] then
      begin
        lvTmp := lvKeys[i];
        lvKeys[i] := lvKeys[j];
        lvKeys[j] := lvTmp;
      end;
  CheckEquals(-10, lvKeys[0]);
  CheckEquals(20, lvKeys[1]);
  CheckEquals(30, lvKeys[2]);
end;

procedure TBpIntDictionaryTests.SumCallback(AKey: Int64; const AValue: Variant;
  var AStop: Boolean);
begin
  FForEachSum := FForEachSum + AKey;
  Inc(FForEachCalls);
  AStop := FForEachCalls = FForEachStopAfter;
end;

procedure TBpIntDictionaryTests.TestForEach;
begin
  FDict.Add(1, 'a');
  FDict.Add(2, 'b');
  FDict.Add(3, 'c');
  FForEachSum := 0;
  FForEachCalls := 0;
  FForEachStopAfter := 0;  // never stop
  FDict.ForEach(SumCallback);
  CheckEquals(6, FForEachSum);
  CheckEquals(3, FForEachCalls);
  // early stop after the second visit
  FForEachSum := 0;
  FForEachCalls := 0;
  FForEachStopAfter := 2;
  FDict.ForEach(SumCallback);
  CheckEquals(2, FForEachCalls);
end;

procedure TBpIntDictionaryTests.TestTypedAccessors;
var
  lvInt: Integer;
  lvInt64: Int64;
  lvStr: string;
  lvBool: Boolean;
  lvFloat: Double;
begin
  FDict.SetInt(1, 123);
  FDict.SetInt64(2, 3000000000);
  FDict.SetStr(3, 'text');
  FDict.SetBool(4, True);
  FDict.SetFloat(5, 2.5);

  CheckEquals(123, FDict.GetInt(1));
  CheckTrue(FDict.GetInt64(2) = 3000000000);
  CheckEquals('text', FDict.GetStr(3));
  CheckEquals(True, FDict.GetBool(4));
  CheckEquals(2.5, FDict.GetFloat(5), 0.0001);
  // int widens to Int64 and to float, but never the other way
  CheckTrue(FDict.GetInt64(1) = 123);
  CheckEquals(123.0, FDict.GetFloat(1), 0.0001);

  CheckTrue(FDict.TryGetInt(1, lvInt) and (lvInt = 123));
  CheckTrue(FDict.TryGetInt64(2, lvInt64) and (lvInt64 = 3000000000));
  CheckTrue(FDict.TryGetStr(3, lvStr) and (lvStr = 'text'));
  CheckTrue(FDict.TryGetBool(4, lvBool) and lvBool);
  CheckTrue(FDict.TryGetFloat(5, lvFloat) and (Abs(lvFloat - 2.5) < 0.0001));

  CheckEquals(-1, FDict.GetIntDef(99, -1));
  CheckTrue(FDict.GetInt64Def(99, -2) = -2);
  CheckEquals('def', FDict.GetStrDef(99, 'def'));
  CheckEquals(True, FDict.GetBoolDef(99, True));
  CheckEquals(9.5, FDict.GetFloatDef(99, 9.5), 0.0001);
end;

procedure TBpIntDictionaryTests.GetMissingKey;
var
  lvValue: Variant;
begin
  lvValue := FDict[12345];
end;

procedure TBpIntDictionaryTests.GetStrOnIntValue;
begin
  FDict.GetStr(1);
end;

procedure TBpIntDictionaryTests.TestTypedAccessorStrictness;
var
  lvInt: Integer;
  lvBool: Boolean;
begin
  FDict.SetInt(1, 123);
  FDict.SetStr(2, '456');
  FDict.SetFloat(3, 1.5);
  FDict.SetBool(4, True);
  // numeric string is not an int, float is not an int, bool is not an int
  CheckFalse(FDict.TryGetInt(2, lvInt), 'no string parsing');
  CheckFalse(FDict.TryGetInt(3, lvInt), 'no float truncation');
  CheckFalse(FDict.TryGetInt(4, lvInt), 'no bool to int');
  // int is not a bool either
  CheckFalse(FDict.TryGetBool(1, lvBool), 'no int to bool');
  // Get raises with a descriptive exception on a type mismatch
  CheckException(GetStrOnIntValue, EbpIntDictionary);
end;

procedure TBpIntDictionaryTests.TestItemsDefaultProperty;
begin
  CheckException(GetMissingKey, EbpIntDictionary);
  FDict[10] := 'via property';       // write acts as AddOrSet
  CheckEquals('via property', string(FDict[10]));
  FDict[10] := 'overwritten';
  CheckEquals('overwritten', string(FDict[10]));
  CheckEquals(1, FDict.Count);
end;

procedure TBpIntDictionaryTests.TestHashDistribution;
const
  lcKeys = 65536;
var
  lvBuckets: array of Integer;
  lvMask, lvUsed, lvMax, i, lvSlot: Integer;
begin
  // sequential ids are the common real-world key pattern; the Wang mix must
  // spread them over a power-of-two table without pathological clustering
  lvMask := lcKeys - 1;
  SetLength(lvBuckets, lcKeys);
  for i := 1 to lcKeys do
  begin
    lvSlot := BpHashInt64(i) and lvMask;
    Inc(lvBuckets[lvSlot]);
  end;
  lvUsed := 0;
  lvMax := 0;
  for i := 0 to lvMask do
  begin
    if lvBuckets[i] > 0 then
      Inc(lvUsed);
    if lvBuckets[i] > lvMax then
      lvMax := lvBuckets[i];
  end;
  // ideal random occupancy for n balls in n bins is ~63%, max load ~8
  Check(lvUsed > (lcKeys * 55) div 100,
    Format('bucket occupancy too low: %d of %d', [lvUsed, lcKeys]));
  Check(lvMax <= 16, Format('worst bucket too crowded: %d entries', [lvMax]));
end;

initialization
  RegisterTest(TBpIntDictionaryTests.Suite);

end.
