unit BpStrDictionary;

// Lightweight string-key dictionary for Delphi 7/2007 and later (no generics).
//
// Design follows Delphi XE6 System.Generics.Collections.TDictionary:
// open addressing with linear probing over a single flat item array,
// power-of-two capacity, cached hash codes (EMPTY_HASH sentinel marks free
// slots), growth at 75% load and tombstone-free backward-shift deletion.
// Keys are hashed with the Bob Jenkins lookup3 port in BpHashBobJenkins.
//
// Values are stored as Variant. Typed accessors with validation live in
// the same class (GetInt, TryGetInt, GetIntDef, SetInt and friends).
//
// Case sensitivity: keys are case-sensitive by default; pass True to the
// constructor for case-insensitive mode (keys are then hashed over their
// AnsiUpperCase form and compared with AnsiSameText, locale-aware).

interface

uses
  Windows, SysUtils, Classes, Variants, BpVariantUtils;

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpStrDictionary = class(Exception);

  // ForEach callback; set AStop to True to break the iteration
  TbpStrDictForEach = procedure(const AKey: string; const AValue: Variant;
    var AStop: Boolean) of object;

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
    function HashOf(const AKey: string): Integer;
    function KeysEqual(const AKey1, AKey2: string): Boolean;
    // returns the slot index (>= 0) when found, otherwise the bitwise
    // complement of the first empty slot (always negative), XE6-style
    function GetBucketIndex(const AKey: string; AHashCode: Integer): Integer;
    procedure DoAdd(AHashCode, AIndex: Integer; const AKey: string; const AValue: Variant);
    procedure Grow;
    procedure Rehash(ANewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(const AKey: string): Variant;
    procedure SetItem(const AKey: string; const AValue: Variant);
  public
    constructor Create(ACaseInsensitive: Boolean = False; AInitialCapacity: Integer = 0);
    // core operations
    procedure Add(const AKey: string; const AValue: Variant);
    procedure AddOrSet(const AKey: string; const AValue: Variant);
    function TryGetValue(const AKey: string; out AValue: Variant): Boolean;
    function ContainsKey(const AKey: string): Boolean;
    function Remove(const AKey: string): Boolean;
    procedure Clear;
    procedure SetCapacity(ACapacity: Integer);
    procedure ForEach(ACallback: TbpStrDictForEach);
    procedure GetKeys(AList: TStrings);
    // typed accessors with validation. GetX raises on a missing key or a
    // wrong stored type, GetXDef returns ADefault instead, TryGetX never
    // raises. Conversion is strict: no boolean-to-int, no numeric strings,
    // no float-to-int truncation
    procedure SetInt(const AKey: string; AValue: Integer);
    function GetInt(const AKey: string): Integer;
    function GetIntDef(const AKey: string; ADefault: Integer): Integer;
    function TryGetInt(const AKey: string; out AValue: Integer): Boolean;
    procedure SetInt64(const AKey: string; AValue: Int64);
    function GetInt64(const AKey: string): Int64;
    function GetInt64Def(const AKey: string; ADefault: Int64): Int64;
    function TryGetInt64(const AKey: string; out AValue: Int64): Boolean;
    procedure SetStr(const AKey, AValue: string);
    function GetStr(const AKey: string): string;
    function GetStrDef(const AKey, ADefault: string): string;
    function TryGetStr(const AKey: string; out AValue: string): Boolean;
    procedure SetBool(const AKey: string; AValue: Boolean);
    function GetBool(const AKey: string): Boolean;
    function GetBoolDef(const AKey: string; ADefault: Boolean): Boolean;
    function TryGetBool(const AKey: string; out AValue: Boolean): Boolean;
    procedure SetFloat(const AKey: string; AValue: Double);
    function GetFloat(const AKey: string): Double;
    function GetFloatDef(const AKey: string; ADefault: Double): Double;
    function TryGetFloat(const AKey: string; out AValue: Double): Boolean;
    procedure SetIntArray(const AKey: string; const AValues: array of Integer);
    function GetIntArray(const AKey: string): TbpIntegerDynArray;
    function TryGetIntArray(const AKey: string; out AValues: TbpIntegerDynArray): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    property CaseInsensitive: Boolean read FCaseInsensitive;
    // raises EbpStrDictionary on read of a missing key; write acts as AddOrSet
    property Items[const AKey: string]: Variant read GetItem write SetItem; default;
  end;

implementation

uses
  BpHashBobJenkins;

// per-unit names so amalgamated bundles can embed both dictionaries
const
  gcStrEmptyHash = -1;                         // sentinel: slot is free
  gcStrPositiveMask = not Integer($80000000);  // $7FFFFFFF

constructor TbpStrDictionary.Create(ACaseInsensitive: Boolean; AInitialCapacity: Integer);
begin
  inherited Create;
  FCaseInsensitive := ACaseInsensitive;
  if AInitialCapacity < 0 then
    raise EbpStrDictionary.Create('Initial capacity must not be negative');
  if AInitialCapacity > 0 then
    SetCapacity(AInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpStrDictionary.HashOf(const AKey: string): Integer;
var
  lvFolded: string;
begin
  if FCaseInsensitive then
  begin
    lvFolded := AnsiUpperCase(AKey);
    Result := TbpHashBobJenkins.GetHashValue(Pointer(lvFolded)^, Length(lvFolded) * SizeOf(Char), 0);
  end
  else
    Result := TbpHashBobJenkins.GetHashValue(Pointer(AKey)^, Length(AKey) * SizeOf(Char), 0);
  // force the hash into 0..MaxInt so it can never collide with gcStrEmptyHash
  Result := gcStrPositiveMask and ((gcStrPositiveMask and Result) + 1);
end;

function TbpStrDictionary.KeysEqual(const AKey1, AKey2: string): Boolean;
begin
  if FCaseInsensitive then
    Result := AnsiSameText(AKey1, AKey2)
  else
    Result := AKey1 = AKey2;
end;

function TbpStrDictionary.GetBucketIndex(const AKey: string; AHashCode: Integer): Integer;
var
  lvLen, lvIndex, lvHC: Integer;
begin
  lvLen := Length(FItems);
  if lvLen = 0 then
  begin
    Result := not High(Integer);
    Exit;
  end;
  lvIndex := AHashCode and (lvLen - 1);
  while True do
  begin
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcStrEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, string compare only on hash match
    if (lvHC = AHashCode) and KeysEqual(FItems[lvIndex].Key, AKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpStrDictionary.DoAdd(AHashCode, AIndex: Integer; const AKey: string; const AValue: Variant);
begin
  FItems[AIndex].HashCode := AHashCode;
  FItems[AIndex].Key := AKey;
  FItems[AIndex].Value := AValue;
  Inc(FCount);
end;

procedure TbpStrDictionary.Rehash(ANewCapacity: Integer);
var
  lvOldItems: TbpStrDictItemArray;
  lvIndex: Integer;
  i: Integer;
begin
  if ANewCapacity = Length(FItems) then
    Exit;
  if ANewCapacity < 0 then
    OutOfMemoryError;
  lvOldItems := FItems;
  FItems := nil;
  SetLength(FItems, ANewCapacity);
  for i := 0 to ANewCapacity - 1 do
    FItems[i].HashCode := gcStrEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := ANewCapacity shr 1 + ANewCapacity shr 2;
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

procedure TbpStrDictionary.SetCapacity(ACapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  if ACapacity < FCount then
    raise EbpStrDictionary.Create('Capacity cannot be less than Count');
  if ACapacity = 0 then
    Rehash(0)
  else
  begin
    // round up to a power of two, minimum 4
    lvNewCapacity := 4;
    while lvNewCapacity < ACapacity do
      lvNewCapacity := lvNewCapacity shl 1;
    Rehash(lvNewCapacity);
  end;
end;

function TbpStrDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpStrDictionary.Add(const AKey: string; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  if FCount >= FGrowThreshold then
    Grow;
  lvHashCode := HashOf(AKey);
  lvIndex := GetBucketIndex(AKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpStrDictionary.CreateFmt('Duplicate key: "%s"', [AKey]);
  DoAdd(lvHashCode, not lvIndex, AKey, AValue);
end;

procedure TbpStrDictionary.AddOrSet(const AKey: string; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  lvHashCode := HashOf(AKey);
  lvIndex := GetBucketIndex(AKey, lvHashCode);
  if lvIndex >= 0 then
  begin
    FItems[lvIndex].Value := AValue;
    Exit;
  end;
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(AKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, AKey, AValue);
end;

function TbpStrDictionary.TryGetValue(const AKey: string; out AValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, HashOf(AKey));
  Result := lvIndex >= 0;
  if Result then
    AValue := FItems[lvIndex].Value
  else
    AValue := Unassigned;
end;

function TbpStrDictionary.ContainsKey(const AKey: string): Boolean;
begin
  Result := GetBucketIndex(AKey, HashOf(AKey)) >= 0;
end;

function TbpStrDictionary.Remove(const AKey: string): Boolean;
var
  lvGap, lvIndex, lvHC, lvBucket, lvLen: Integer;

  // wrap-aware test whether AItem's home bucket lies in (ABottom, ATopInc],
  // decides if an entry may slide back into the gap; nested (not unit-level)
  // so amalgamated bundles can embed both dictionaries without a name clash
  function InCircularRange(ABottom, AItem, ATopInc: Integer): Boolean;
  begin
    Result := ((ABottom < AItem) and (AItem <= ATopInc)) or
      ((ATopInc < ABottom) and (AItem > ABottom)) or
      ((ATopInc < ABottom) and (AItem <= ATopInc));
  end;

begin
  lvIndex := GetBucketIndex(AKey, HashOf(AKey));
  Result := lvIndex >= 0;
  if not Result then
    Exit;
  // backward-shift deletion (Knuth 6.4 Algorithm R): slide the following
  // cluster entries into the gap unless that would pass their home bucket
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

procedure TbpStrDictionary.ForEach(ACallback: TbpStrDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(ACallback) then
    Exit;
  lvStop := False;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcStrEmptyHash then
    begin
      ACallback(FItems[i].Key, FItems[i].Value, lvStop);
      if lvStop then
        Exit;
    end;
end;

procedure TbpStrDictionary.GetKeys(AList: TStrings);
var
  i: Integer;
begin
  AList.BeginUpdate;
  try
    AList.Clear;
    for i := 0 to Length(FItems) - 1 do
      if FItems[i].HashCode <> gcStrEmptyHash then
        AList.Add(FItems[i].Key);
  finally
    AList.EndUpdate;
  end;
end;

function TbpStrDictionary.GetItem(const AKey: string): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, HashOf(AKey));
  if lvIndex < 0 then
    raise EbpStrDictionary.CreateFmt('Key not found: "%s"', [AKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpStrDictionary.SetItem(const AKey: string; const AValue: Variant);
begin
  AddOrSet(AKey, AValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseTypeError(const AKey, AExpected: string; const AValue: Variant);
begin
  raise EbpStrDictionary.CreateFmt('Value for key "%s" is not %s (stored type: %s)',
    [AKey, AExpected, VarTypeAsText(VarType(AValue))]);
end;

procedure TbpStrDictionary.SetInt(const AKey: string; AValue: Integer);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetInt(const AKey: string): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseTypeError(AKey, 'an Integer', lvValue);
end;

function TbpStrDictionary.GetIntDef(const AKey: string; ADefault: Integer): Integer;
begin
  if not TryGetInt(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetInt(const AKey: string; out AValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpStrDictionary.SetInt64(const AKey: string; AValue: Int64);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetInt64(const AKey: string): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseTypeError(AKey, 'an Int64', lvValue);
end;

function TbpStrDictionary.GetInt64Def(const AKey: string; ADefault: Int64): Int64;
begin
  if not TryGetInt64(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetInt64(const AKey: string; out AValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt64(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpStrDictionary.SetStr(const AKey, AValue: string);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetStr(const AKey: string): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseTypeError(AKey, 'a string', lvValue);
end;

function TbpStrDictionary.GetStrDef(const AKey, ADefault: string): string;
begin
  if not TryGetStr(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetStr(const AKey: string; out AValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToStr(lvValue, AValue);
  if not Result then
    AValue := '';
end;

procedure TbpStrDictionary.SetBool(const AKey: string; AValue: Boolean);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetBool(const AKey: string): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseTypeError(AKey, 'a Boolean', lvValue);
end;

function TbpStrDictionary.GetBoolDef(const AKey: string; ADefault: Boolean): Boolean;
begin
  if not TryGetBool(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetBool(const AKey: string; out AValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToBool(lvValue, AValue);
  if not Result then
    AValue := False;
end;

procedure TbpStrDictionary.SetFloat(const AKey: string; AValue: Double);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetFloat(const AKey: string): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseTypeError(AKey, 'a Float', lvValue);
end;

function TbpStrDictionary.GetFloatDef(const AKey: string; ADefault: Double): Double;
begin
  if not TryGetFloat(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetFloat(const AKey: string; out AValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToFloat(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpStrDictionary.SetIntArray(const AKey: string; const AValues: array of Integer);
var
  lvArray: Variant;
  i: Integer;
begin
  lvArray := VarArrayCreate([0, Length(AValues) - 1], varInteger);
  for i := 0 to Length(AValues) - 1 do
    lvArray[i] := AValues[i];
  AddOrSet(AKey, lvArray);
end;

function TbpStrDictionary.GetIntArray(const AKey: string): TbpIntegerDynArray;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToIntArray(lvValue, Result) then
    RaiseTypeError(AKey, 'an Integer array', lvValue);
end;

function TbpStrDictionary.TryGetIntArray(const AKey: string; out AValues: TbpIntegerDynArray): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToIntArray(lvValue, AValues);
  if not Result then
    AValues := nil;
end;

end.
