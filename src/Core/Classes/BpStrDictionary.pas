unit BpStrDictionary;

// String-key dictionary for Delphi 7/2007+ (no generics), TDictionary-style API.
// Open addressing with linear probing, power-of-two capacity, backward-shift
// deletion, BpHashBobJenkins hashing and opt-in case-insensitive keys.

interface

uses
  Windows, SysUtils, Classes, Variants, BpVariantUtils;

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpStrDictionary = class(Exception);

  // ForEach callback; set aStop to True to break the iteration
  TbpStrDictForEach = procedure(const aKey: string; const aValue: Variant;
    var aStop: Boolean) of object;

  TbpStrDictItem = record
    HashCode: Integer;
    Key: string;
    Value: Variant;
  end;
  TbpStrDictItemArray = array of TbpStrDictItem;

  TbpStrDictionary = class
  private
    FItems: TbpStrDictItemArray;
    FCount: Integer;
    FGrowThreshold: Integer;
    FCaseInsensitive: Boolean;
    function HashOf(const aKey: string): Integer;
    function KeysEqual(const aKey1, aKey2: string): Boolean;
    // the slot index when found, else the complement of the first empty slot
    function GetBucketIndex(const aKey: string; aHashCode: Integer): Integer;
    procedure DoAdd(aHashCode, aIndex: Integer; const aKey: string; const aValue: Variant);
    procedure Grow;
    procedure Rehash(aNewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(const aKey: string): Variant;
    procedure SetItem(const aKey: string; const aValue: Variant);
  public
    constructor Create(aCaseInsensitive: Boolean = False; aInitialCapacity: Integer = 0);
    // core operations
    procedure Add(const aKey: string; const aValue: Variant);
    procedure AddOrSet(const aKey: string; const aValue: Variant);
    function TryGetValue(const aKey: string; out aValue: Variant): Boolean;
    function ContainsKey(const aKey: string): Boolean;
    function Remove(const aKey: string): Boolean;
    procedure Clear;
    procedure SetCapacity(aCapacity: Integer);
    procedure ForEach(aCallback: TbpStrDictForEach);
    procedure GetKeys(aList: TStrings);
    // GetX raises on a missing key or wrong type, GetXDef defaults, TryGetX never raises
    procedure SetInt(const aKey: string; aValue: Integer);
    function GetInt(const aKey: string): Integer;
    function GetIntDef(const aKey: string; aDefault: Integer): Integer;
    function TryGetInt(const aKey: string; out aValue: Integer): Boolean;
    procedure SetInt64(const aKey: string; aValue: Int64);
    function GetInt64(const aKey: string): Int64;
    function GetInt64Def(const aKey: string; aDefault: Int64): Int64;
    function TryGetInt64(const aKey: string; out aValue: Int64): Boolean;
    procedure SetStr(const aKey, aValue: string);
    function GetStr(const aKey: string): string;
    function GetStrDef(const aKey, aDefault: string): string;
    function TryGetStr(const aKey: string; out aValue: string): Boolean;
    procedure SetBool(const aKey: string; aValue: Boolean);
    function GetBool(const aKey: string): Boolean;
    function GetBoolDef(const aKey: string; aDefault: Boolean): Boolean;
    function TryGetBool(const aKey: string; out aValue: Boolean): Boolean;
    procedure SetFloat(const aKey: string; aValue: Double);
    function GetFloat(const aKey: string): Double;
    function GetFloatDef(const aKey: string; aDefault: Double): Double;
    function TryGetFloat(const aKey: string; out aValue: Double): Boolean;
    procedure SetIntArray(const aKey: string; const aValues: array of Integer);
    function GetIntArray(const aKey: string): TbpIntegerDynArray;
    function TryGetIntArray(const aKey: string; out aValues: TbpIntegerDynArray): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    property CaseInsensitive: Boolean read FCaseInsensitive;
    // raises EbpStrDictionary on read of a missing key; write acts as AddOrSet
    property Items[const aKey: string]: Variant read GetItem write SetItem; default;
  end;

implementation

uses
  BpHashBobJenkins;

// per-unit names so amalgamated bundles can embed both dictionaries
const
  gcStrEmptyHash = -1;                         // sentinel: slot is free
  gcStrPositiveMask = not Integer($80000000);  // $7FFFFFFF


constructor TbpStrDictionary.Create(aCaseInsensitive: Boolean; aInitialCapacity: Integer);
begin
  inherited Create;
  FCaseInsensitive := aCaseInsensitive;
  if aInitialCapacity < 0 then
    raise EbpStrDictionary.Create('Initial capacity must not be negative');
  if aInitialCapacity > 0 then
    SetCapacity(aInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpStrDictionary.HashOf(const aKey: string): Integer;
var
  lvFolded: string;
begin
  if FCaseInsensitive then
  begin
    lvFolded := AnsiUpperCase(aKey);
    Result := TbpHashBobJenkins.GetHashValue(Pointer(lvFolded)^, Length(lvFolded) * SizeOf(Char), 0);
  end
  else
    Result := TbpHashBobJenkins.GetHashValue(Pointer(aKey)^, Length(aKey) * SizeOf(Char), 0);
  // force the hash into 0..MaxInt so it can never collide with gcStrEmptyHash
  Result := gcStrPositiveMask and ((gcStrPositiveMask and Result) + 1);
end;

function TbpStrDictionary.KeysEqual(const aKey1, aKey2: string): Boolean;
begin
  if FCaseInsensitive then
    Result := AnsiSameText(aKey1, aKey2)
  else
    Result := aKey1 = aKey2;
end;

function TbpStrDictionary.GetBucketIndex(const aKey: string; aHashCode: Integer): Integer;
var
  lvLen, lvIndex, lvHC: Integer;
begin
  lvLen := Length(FItems);
  if lvLen = 0 then
  begin
    Result := not High(Integer);
    Exit;
  end;
  lvIndex := aHashCode and (lvLen - 1);
  while True do
  begin
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcStrEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, string compare only on hash match
    if (lvHC = aHashCode) and KeysEqual(FItems[lvIndex].Key, aKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpStrDictionary.DoAdd(aHashCode, aIndex: Integer; const aKey: string; const aValue: Variant);
begin
  FItems[aIndex].HashCode := aHashCode;
  FItems[aIndex].Key := aKey;
  FItems[aIndex].Value := aValue;
  Inc(FCount);
end;

procedure TbpStrDictionary.Rehash(aNewCapacity: Integer);
var
  lvOldItems: TbpStrDictItemArray;
  lvIndex: Integer;
  i: Integer;
begin
  if aNewCapacity = Length(FItems) then
    Exit;
  if aNewCapacity < 0 then
    OutOfMemoryError;
  lvOldItems := FItems;
  FItems := nil;
  SetLength(FItems, aNewCapacity);
  for i := 0 to aNewCapacity - 1 do
    FItems[i].HashCode := gcStrEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := aNewCapacity shr 1 + aNewCapacity shr 2;
  // reinsert using the cached hash codes, no rehashing of the keys
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcStrEmptyHash then
    begin
      lvIndex := not GetBucketIndex(lvOldItems[i].Key, lvOldItems[i].HashCode);
      FItems[lvIndex].HashCode := lvOldItems[i].HashCode;
      FItems[lvIndex].Key := lvOldItems[i].Key;
      FItems[lvIndex].Value := lvOldItems[i].Value;
    end;
end;

procedure TbpStrDictionary.Grow;
var
  lvNewCapacity: Integer;
begin
  lvNewCapacity := Length(FItems) * 2;
  if lvNewCapacity = 0 then
    lvNewCapacity := 4;
  Rehash(lvNewCapacity);
end;

procedure TbpStrDictionary.SetCapacity(aCapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  if aCapacity < FCount then
    raise EbpStrDictionary.Create('Capacity cannot be less than Count');
  if aCapacity = 0 then
    Rehash(0)
  else
  begin
    // a power of two, at least 4, and never full: the probe loop needs a free slot
    lvNewCapacity := 4;
    while (lvNewCapacity > 0) and ((lvNewCapacity < aCapacity) or
      (FCount > lvNewCapacity shr 1 + lvNewCapacity shr 2)) do
      lvNewCapacity := lvNewCapacity shl 1;
    if lvNewCapacity <= 0 then
      OutOfMemoryError;
    Rehash(lvNewCapacity);
  end;
end;

function TbpStrDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpStrDictionary.Add(const aKey: string; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  if FCount >= FGrowThreshold then
    Grow;
  lvHashCode := HashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpStrDictionary.CreateFmt('Duplicate key: "%s"', [aKey]);
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

procedure TbpStrDictionary.AddOrSet(const aKey: string; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  lvHashCode := HashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
  begin
    FItems[lvIndex].Value := aValue;
    Exit;
  end;
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(aKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

function TbpStrDictionary.TryGetValue(const aKey: string; out aValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, HashOf(aKey));
  Result := lvIndex >= 0;
  if Result then
    aValue := FItems[lvIndex].Value
  else
    aValue := Unassigned;
end;

function TbpStrDictionary.ContainsKey(const aKey: string): Boolean;
begin
  Result := GetBucketIndex(aKey, HashOf(aKey)) >= 0;
end;

function TbpStrDictionary.Remove(const aKey: string): Boolean;
var
  lvGap, lvIndex, lvHC, lvBucket, lvLen: Integer;

  // wrap-aware test for a home bucket in (aBottom, aTopInc]; nested to keep bundles clash free
  function InCircularRange(aBottom, aItem, aTopInc: Integer): Boolean;
  begin
    Result := ((aBottom < aItem) and (aItem <= aTopInc)) or
      ((aTopInc < aBottom) and (aItem > aBottom)) or
      ((aTopInc < aBottom) and (aItem <= aTopInc));
  end;

begin
  lvIndex := GetBucketIndex(aKey, HashOf(aKey));
  Result := lvIndex >= 0;
  if not Result then
    Exit;
  // backward-shift deletion (Knuth 6.4 R): slide cluster entries into the gap
  lvLen := Length(FItems);
  lvGap := lvIndex;
  while True do
  begin
    lvIndex := (lvIndex + 1) and (lvLen - 1);
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcStrEmptyHash then
      Break;
    lvBucket := lvHC and (lvLen - 1);
    if not InCircularRange(lvGap, lvBucket, lvIndex) then
    begin
      FItems[lvGap] := FItems[lvIndex];
      lvGap := lvIndex;
    end;
  end;
  FItems[lvGap].HashCode := gcStrEmptyHash;
  FItems[lvGap].Key := '';
  FItems[lvGap].Value := Unassigned;
  Dec(FCount);
end;

procedure TbpStrDictionary.Clear;
begin
  FItems := nil;
  FCount := 0;
  FGrowThreshold := 0;
end;

procedure TbpStrDictionary.ForEach(aCallback: TbpStrDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(aCallback) then
    Exit;
  lvStop := False;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcStrEmptyHash then
    begin
      aCallback(FItems[i].Key, FItems[i].Value, lvStop);
      if lvStop then
        Exit;
    end;
end;

procedure TbpStrDictionary.GetKeys(aList: TStrings);
var
  i: Integer;
begin
  aList.BeginUpdate;
  try
    aList.Clear;
    for i := 0 to Length(FItems) - 1 do
      if FItems[i].HashCode <> gcStrEmptyHash then
        aList.Add(FItems[i].Key);
  finally
    aList.EndUpdate;
  end;
end;

function TbpStrDictionary.GetItem(const aKey: string): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, HashOf(aKey));
  if lvIndex < 0 then
    raise EbpStrDictionary.CreateFmt('Key not found: "%s"', [aKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpStrDictionary.SetItem(const aKey: string; const aValue: Variant);
begin
  AddOrSet(aKey, aValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseStrTypeError(const aKey, aExpected: string; const aValue: Variant);
begin
  raise EbpStrDictionary.CreateFmt('Value for key "%s" is not %s (stored type: %s)',
    [aKey, aExpected, VarTypeAsText(VarType(aValue))]);
end;

procedure TbpStrDictionary.SetInt(const aKey: string; aValue: Integer);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetInt(const aKey: string): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseStrTypeError(aKey, 'an Integer', lvValue);
end;

function TbpStrDictionary.GetIntDef(const aKey: string; aDefault: Integer): Integer;
begin
  if not TryGetInt(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetInt(const aKey: string; out aValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpStrDictionary.SetInt64(const aKey: string; aValue: Int64);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetInt64(const aKey: string): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseStrTypeError(aKey, 'an Int64', lvValue);
end;

function TbpStrDictionary.GetInt64Def(const aKey: string; aDefault: Int64): Int64;
begin
  if not TryGetInt64(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetInt64(const aKey: string; out aValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt64(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpStrDictionary.SetStr(const aKey, aValue: string);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetStr(const aKey: string): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseStrTypeError(aKey, 'a string', lvValue);
end;

function TbpStrDictionary.GetStrDef(const aKey, aDefault: string): string;
begin
  if not TryGetStr(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetStr(const aKey: string; out aValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToStr(lvValue, aValue);
  if not Result then
    aValue := '';
end;

procedure TbpStrDictionary.SetBool(const aKey: string; aValue: Boolean);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetBool(const aKey: string): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseStrTypeError(aKey, 'a Boolean', lvValue);
end;

function TbpStrDictionary.GetBoolDef(const aKey: string; aDefault: Boolean): Boolean;
begin
  if not TryGetBool(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetBool(const aKey: string; out aValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToBool(lvValue, aValue);
  if not Result then
    aValue := False;
end;

procedure TbpStrDictionary.SetFloat(const aKey: string; aValue: Double);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetFloat(const aKey: string): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseStrTypeError(aKey, 'a Float', lvValue);
end;

function TbpStrDictionary.GetFloatDef(const aKey: string; aDefault: Double): Double;
begin
  if not TryGetFloat(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetFloat(const aKey: string; out aValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToFloat(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpStrDictionary.SetIntArray(const aKey: string; const aValues: array of Integer);
var
  lvArray: Variant;
  i: Integer;
begin
  lvArray := VarArrayCreate([0, Length(aValues) - 1], varInteger);
  for i := 0 to Length(aValues) - 1 do
    lvArray[i] := aValues[i];
  AddOrSet(aKey, lvArray);
end;

function TbpStrDictionary.GetIntArray(const aKey: string): TbpIntegerDynArray;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToIntArray(lvValue, Result) then
    RaiseStrTypeError(aKey, 'an Integer array', lvValue);
end;

function TbpStrDictionary.TryGetIntArray(const aKey: string; out aValues: TbpIntegerDynArray): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToIntArray(lvValue, aValues);
  if not Result then
    aValues := nil;
end;

end.
