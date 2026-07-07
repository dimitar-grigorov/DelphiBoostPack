unit BpStrDictionaryTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Variants, BpStrDictionary;

type
  TBpStrDictionaryTests = class(TTestCase)
  private
    FDict: TbpStrDictionary;
    FVisitCount: Integer;
    FStopAfter: Integer;
    FVisitedKeys: TStringList;
    procedure VisitCallback(const AKey: string; const AValue: Variant; var AStop: Boolean);
    procedure CallGetMissing;
    procedure CallAddDuplicate;
    procedure CallGetIntOnString;
    procedure CallGetIntOnTooBigInt64;
    procedure CallGetIntArrayOnInt;
    procedure CallSetCapacityBelowCount;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // core CRUD
    procedure TestAddAndGet;
    procedure TestAddDuplicateRaises;
    procedure TestAddOrSetOverwrites;
    procedure TestItemsPropertyReadWrite;
    procedure TestGetMissingKeyRaises;
    procedure TestTryGetValue;
    procedure TestContainsKey;
    procedure TestRemove;
    procedure TestRemoveMissingReturnsFalse;
    procedure TestClear;
    procedure TestEmptyKey;
    // hashing and probing
    procedure TestGrowthKeepsAllItems;
    procedure TestDeleteThenProbe;
    procedure TestRemoveAllOneByOne;
    procedure TestInitialCapacity;
    procedure TestSetCapacityBelowCountRaises;
    // case sensitivity
    procedure TestCaseSensitiveDefault;
    procedure TestCaseInsensitiveMode;
    procedure TestCaseInsensitiveNonAscii;
    // iteration
    procedure TestForEachVisitsAll;
    procedure TestForEachEarlyStop;
    procedure TestGetKeys;
    // typed accessors
    procedure TestIntAccessors;
    procedure TestInt64Accessors;
    procedure TestStrAccessors;
    procedure TestBoolAccessors;
    procedure TestFloatAccessors;
    procedure TestIntArrayAccessors;
    procedure TestTypeValidationErrors;
  end;

implementation

procedure TBpStrDictionaryTests.SetUp;
begin
  FDict := TbpStrDictionary.Create;
  FVisitCount := 0;
  FStopAfter := 0;
  FVisitedKeys := TStringList.Create;
end;

procedure TBpStrDictionaryTests.TearDown;
begin
  FreeAndNil(FVisitedKeys);
  FreeAndNil(FDict);
end;

procedure TBpStrDictionaryTests.VisitCallback(const AKey: string; const AValue: Variant; var AStop: Boolean);
begin
  Inc(FVisitCount);
  FVisitedKeys.Add(AKey);
  if (FStopAfter > 0) and (FVisitCount >= FStopAfter) then
    AStop := True;
end;

procedure TBpStrDictionaryTests.TestAddAndGet;
begin
  FDict.Add('alpha', 1);
  FDict.Add('beta', 'two');
  CheckEquals(2, FDict.Count);
  CheckEquals(1, Integer(FDict['alpha']));
  CheckEquals('two', string(FDict['beta']));
end;

procedure TBpStrDictionaryTests.CallAddDuplicate;
begin
  FDict.Add('dup', 2);
end;

procedure TBpStrDictionaryTests.TestAddDuplicateRaises;
begin
  FDict.Add('dup', 1);
  CheckException(CallAddDuplicate, EbpStrDictionary, 'Add of a duplicate key must raise');
  CheckEquals(1, FDict.Count);
end;

procedure TBpStrDictionaryTests.TestAddOrSetOverwrites;
begin
  FDict.AddOrSet('key', 1);
  FDict.AddOrSet('key', 2);
  CheckEquals(1, FDict.Count);
  CheckEquals(2, Integer(FDict['key']));
end;

procedure TBpStrDictionaryTests.TestItemsPropertyReadWrite;
begin
  FDict['host'] := 'localhost';
  FDict['host'] := 'example.com';  // write acts as AddOrSet
  CheckEquals(1, FDict.Count);
  CheckEquals('example.com', string(FDict['host']));
end;

procedure TBpStrDictionaryTests.CallGetMissing;
var
  lvValue: Variant;
begin
  lvValue := FDict['no such key'];
  if lvValue = 0 then;  // silence unused warning, never reached
end;

procedure TBpStrDictionaryTests.TestGetMissingKeyRaises;
begin
  FDict.Add('a', 1);
  CheckException(CallGetMissing, EbpStrDictionary, 'Read of a missing key must raise');
end;

procedure TBpStrDictionaryTests.TestTryGetValue;
var
  lvValue: Variant;
begin
  FDict.Add('found', 42);
  Check(FDict.TryGetValue('found', lvValue), 'TryGetValue must find existing key');
  CheckEquals(42, Integer(lvValue));
  Check(not FDict.TryGetValue('missing', lvValue), 'TryGetValue must not find missing key');
  Check(VarIsEmpty(lvValue), 'Out value must be Unassigned for missing key');
end;

procedure TBpStrDictionaryTests.TestContainsKey;
begin
  FDict.Add('present', Null);
  Check(FDict.ContainsKey('present'), 'ContainsKey must find key even with Null value');
  Check(not FDict.ContainsKey('absent'), 'ContainsKey must not find missing key');
end;

procedure TBpStrDictionaryTests.TestRemove;
begin
  FDict.Add('a', 1);
  FDict.Add('b', 2);
  Check(FDict.Remove('a'), 'Remove must return True for existing key');
  CheckEquals(1, FDict.Count);
  Check(not FDict.ContainsKey('a'), 'Removed key must be gone');
  Check(FDict.ContainsKey('b'), 'Other keys must survive Remove');
end;

procedure TBpStrDictionaryTests.TestRemoveMissingReturnsFalse;
begin
  FDict.Add('a', 1);
  Check(not FDict.Remove('b'), 'Remove of missing key must return False');
  CheckEquals(1, FDict.Count);
end;

procedure TBpStrDictionaryTests.TestClear;
begin
  FDict.Add('a', 1);
  FDict.Add('b', 2);
  FDict.Clear;
  CheckEquals(0, FDict.Count);
  Check(not FDict.ContainsKey('a'), 'Cleared dictionary must not contain old keys');
  FDict.Add('a', 3);  // must be usable again after Clear
  CheckEquals(3, FDict.GetInt('a'));
end;

procedure TBpStrDictionaryTests.TestEmptyKey;
begin
  FDict.Add('', 'empty');
  Check(FDict.ContainsKey(''), 'Empty string must be a valid key');
  CheckEquals('empty', string(FDict['']));
  Check(FDict.Remove(''), 'Empty key must be removable');
  CheckEquals(0, FDict.Count);
end;

procedure TBpStrDictionaryTests.TestGrowthKeepsAllItems;
var
  i: Integer;
begin
  // forces many grow/rehash cycles from the default zero capacity
  for i := 1 to 10000 do
    FDict.Add('key' + IntToStr(i), i);
  CheckEquals(10000, FDict.Count);
  for i := 1 to 10000 do
    CheckEquals(i, FDict.GetInt('key' + IntToStr(i)), 'Lost key' + IntToStr(i) + ' after growth');
end;

procedure TBpStrDictionaryTests.TestDeleteThenProbe;
var
  i: Integer;
begin
  // regression for backward-shift deletion: removing keys must not break
  // the probe chains of the remaining keys in the same cluster
  for i := 1 to 1000 do
    FDict.Add('key' + IntToStr(i), i);
  for i := 1 to 1000 do
    if i mod 2 = 0 then
      Check(FDict.Remove('key' + IntToStr(i)), 'Remove failed for key' + IntToStr(i));
  CheckEquals(500, FDict.Count);
  for i := 1 to 1000 do
    if i mod 2 = 0 then
      Check(not FDict.ContainsKey('key' + IntToStr(i)), 'key' + IntToStr(i) + ' must be gone')
    else
      CheckEquals(i, FDict.GetInt('key' + IntToStr(i)), 'key' + IntToStr(i) + ' lost after deletes');
end;

procedure TBpStrDictionaryTests.TestRemoveAllOneByOne;
var
  i: Integer;
begin
  for i := 1 to 100 do
    FDict.Add(IntToStr(i), i);
  for i := 100 downto 1 do
    Check(FDict.Remove(IntToStr(i)), 'Remove failed at ' + IntToStr(i));
  CheckEquals(0, FDict.Count);
end;

procedure TBpStrDictionaryTests.TestInitialCapacity;
var
  lvDict: TbpStrDictionary;
  i: Integer;
begin
  lvDict := TbpStrDictionary.Create(False, 1000);
  try
    Check(lvDict.Capacity >= 1000, 'Initial capacity must be honored');
    CheckEquals(1024, lvDict.Capacity, 'Capacity must round up to a power of two');
    for i := 1 to 700 do  // stays below the 75% threshold of 1024
      lvDict.Add(IntToStr(i), i);
    CheckEquals(1024, lvDict.Capacity, 'No rehash below the grow threshold');
  finally
    lvDict.Free;
  end;
end;

procedure TBpStrDictionaryTests.CallSetCapacityBelowCount;
begin
  FDict.SetCapacity(1);
end;

procedure TBpStrDictionaryTests.TestSetCapacityBelowCountRaises;
var
  i: Integer;
begin
  for i := 1 to 10 do
    FDict.Add(IntToStr(i), i);
  CheckException(CallSetCapacityBelowCount, EbpStrDictionary,
    'SetCapacity below Count must raise');
end;

procedure TBpStrDictionaryTests.TestCaseSensitiveDefault;
begin
  Check(not FDict.CaseInsensitive, 'Default mode must be case-sensitive');
  FDict.Add('Key', 1);
  FDict.Add('key', 2);  // different key in sensitive mode
  CheckEquals(2, FDict.Count);
  CheckEquals(1, FDict.GetInt('Key'));
  CheckEquals(2, FDict.GetInt('key'));
end;

procedure TBpStrDictionaryTests.TestCaseInsensitiveMode;
var
  lvDict: TbpStrDictionary;
begin
  lvDict := TbpStrDictionary.Create(True);
  try
    lvDict.Add('Timeout', 30);
    Check(lvDict.ContainsKey('TIMEOUT'), 'Upper spelling must match');
    Check(lvDict.ContainsKey('timeout'), 'Lower spelling must match');
    CheckEquals(30, lvDict.GetInt('tImEoUt'));
    lvDict.AddOrSet('TIMEOUT', 60);  // must overwrite, not add
    CheckEquals(1, lvDict.Count);
    CheckEquals(60, lvDict.GetInt('Timeout'));
    Check(lvDict.Remove('tIMEOUt'), 'Remove must match case-insensitively');
    CheckEquals(0, lvDict.Count);
  finally
    lvDict.Free;
  end;
end;

procedure TBpStrDictionaryTests.TestCaseInsensitiveNonAscii;
var
  lvDict: TbpStrDictionary;
  lvUpper, lvLower: string;
begin
  // #$C0/#$E0 are an upper/lower pair both in cp1251 (Cyrillic A) and in
  // Unicode (Latin A-grave), so this works on ANSI and Unicode compilers
  lvUpper := #$C0#$C1#$C2;
  lvLower := #$E0#$E1#$E2;
  lvDict := TbpStrDictionary.Create(True);
  try
    lvDict.Add(lvUpper, 1);
    Check(lvDict.ContainsKey(lvLower), 'Non-ASCII case folding must match (locale-aware)');
    CheckEquals(1, lvDict.GetInt(lvLower));
  finally
    lvDict.Free;
  end;
end;

procedure TBpStrDictionaryTests.TestForEachVisitsAll;
var
  i: Integer;
begin
  for i := 1 to 50 do
    FDict.Add('k' + IntToStr(i), i);
  FDict.ForEach(VisitCallback);
  CheckEquals(50, FVisitCount);
  FVisitedKeys.Sorted := True;
  for i := 1 to 50 do
    Check(FVisitedKeys.IndexOf('k' + IntToStr(i)) >= 0, 'ForEach missed k' + IntToStr(i));
end;

procedure TBpStrDictionaryTests.TestForEachEarlyStop;
var
  i: Integer;
begin
  for i := 1 to 50 do
    FDict.Add('k' + IntToStr(i), i);
  FStopAfter := 10;
  FDict.ForEach(VisitCallback);
  CheckEquals(10, FVisitCount, 'ForEach must stop when AStop is set');
end;

procedure TBpStrDictionaryTests.TestGetKeys;
var
  lvKeys: TStringList;
  i: Integer;
begin
  for i := 1 to 20 do
    FDict.Add('key' + IntToStr(i), i);
  lvKeys := TStringList.Create;
  try
    lvKeys.Add('stale entry');  // GetKeys must clear the target list
    FDict.GetKeys(lvKeys);
    CheckEquals(20, lvKeys.Count);
    lvKeys.Sorted := True;
    for i := 1 to 20 do
      Check(lvKeys.IndexOf('key' + IntToStr(i)) >= 0, 'GetKeys missed key' + IntToStr(i));
  finally
    lvKeys.Free;
  end;
end;

procedure TBpStrDictionaryTests.TestIntAccessors;
var
  lvValue: Integer;
begin
  FDict.SetInt('answer', 42);
  CheckEquals(42, FDict.GetInt('answer'));
  CheckEquals(42, FDict.GetIntDef('answer', -1));
  CheckEquals(-1, FDict.GetIntDef('missing', -1));
  Check(FDict.TryGetInt('answer', lvValue));
  CheckEquals(42, lvValue);
  Check(not FDict.TryGetInt('missing', lvValue));
  CheckEquals(0, lvValue, 'Failed TryGetInt must zero the out value');
end;

procedure TBpStrDictionaryTests.TestInt64Accessors;
var
  lvBig: Int64;
  lvValue: Int64;
begin
  lvBig := $1FFFFFFFF;  // does not fit in 32 bits
  FDict.SetInt64('big', lvBig);
  Check(FDict.GetInt64('big') = lvBig, 'Int64 round-trip failed');
  Check(FDict.GetInt64Def('missing', -5) = -5);
  Check(FDict.TryGetInt64('big', lvValue));
  Check(lvValue = lvBig);
  // an Integer value must also be readable as Int64
  FDict.SetInt('small', 7);
  Check(FDict.GetInt64('small') = 7, 'Integer must widen to Int64');
end;

procedure TBpStrDictionaryTests.TestStrAccessors;
var
  lvValue: string;
begin
  FDict.SetStr('name', 'Delphi');
  CheckEquals('Delphi', FDict.GetStr('name'));
  CheckEquals('def', FDict.GetStrDef('missing', 'def'));
  Check(FDict.TryGetStr('name', lvValue));
  CheckEquals('Delphi', lvValue);
  Check(not FDict.TryGetStr('missing', lvValue));
  CheckEquals('', lvValue);
end;

procedure TBpStrDictionaryTests.TestBoolAccessors;
var
  lvValue: Boolean;
begin
  FDict.SetBool('flag', True);
  Check(FDict.GetBool('flag'));
  Check(not FDict.GetBoolDef('missing', False));
  Check(FDict.GetBoolDef('missing', True));
  Check(FDict.TryGetBool('flag', lvValue));
  Check(lvValue);
  // strict mode: an Integer 1 is not a Boolean
  FDict.SetInt('one', 1);
  Check(not FDict.TryGetBool('one', lvValue), 'Integer must not convert to Boolean');
end;

procedure TBpStrDictionaryTests.TestFloatAccessors;
var
  lvValue: Double;
  lvInt: Integer;
begin
  FDict.SetFloat('pi', 3.5);
  CheckEquals(3.5, FDict.GetFloat('pi'), 0.0001);
  CheckEquals(1.5, FDict.GetFloatDef('missing', 1.5), 0.0001);
  Check(FDict.TryGetFloat('pi', lvValue));
  CheckEquals(3.5, lvValue, 0.0001);
  // integers are valid floats
  FDict.SetInt('three', 3);
  CheckEquals(3.0, FDict.GetFloat('three'), 0.0001);
  // but a float is not a valid Integer, even a whole one
  Check(not FDict.TryGetInt('pi', lvInt), 'Float must not convert to Integer');
end;

procedure TBpStrDictionaryTests.TestIntArrayAccessors;
var
  lvArray: TbpIntegerDynArray;
  i: Integer;
begin
  FDict.SetIntArray('values', [10, 20, 30]);
  lvArray := FDict.GetIntArray('values');
  CheckEquals(3, Length(lvArray));
  for i := 0 to 2 do
    CheckEquals((i + 1) * 10, lvArray[i]);
  // empty arrays round-trip too
  FDict.SetIntArray('empty', []);
  lvArray := FDict.GetIntArray('empty');
  CheckEquals(0, Length(lvArray));
  Check(FDict.TryGetIntArray('values', lvArray));
  CheckEquals(3, Length(lvArray));
  Check(not FDict.TryGetIntArray('missing', lvArray));
  CheckEquals(0, Length(lvArray));
end;

procedure TBpStrDictionaryTests.CallGetIntOnString;
begin
  FDict.GetInt('text');
end;

procedure TBpStrDictionaryTests.CallGetIntOnTooBigInt64;
begin
  FDict.GetInt('huge');
end;

procedure TBpStrDictionaryTests.CallGetIntArrayOnInt;
begin
  FDict.GetIntArray('scalar');
end;

procedure TBpStrDictionaryTests.TestTypeValidationErrors;
begin
  FDict.SetStr('text', 'not a number');
  CheckException(CallGetIntOnString, EbpStrDictionary, 'GetInt on a string must raise');
  FDict.SetInt64('huge', $100000000);
  CheckException(CallGetIntOnTooBigInt64, EbpStrDictionary, 'GetInt out of Integer range must raise');
  FDict.SetInt('scalar', 5);
  CheckException(CallGetIntArrayOnInt, EbpStrDictionary, 'GetIntArray on a scalar must raise');
end;

initialization
  RegisterTest(TBpStrDictionaryTests.Suite);

end.
