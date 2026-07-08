unit BpIntDictionary;

// Lightweight Int64-key dictionary for Delphi 7/2007 and later (no generics).
//
// Same engine as TbpStrDictionary (which follows Delphi XE6
// System.Generics.Collections.TDictionary): open addressing with linear
// probing over a single flat item array, power-of-two capacity, cached hash
// codes (EMPTY_HASH sentinel marks free slots), growth at 75% load and
// tombstone-free backward-shift deletion.
// Keys are hashed with the Thomas Wang 64-bit to 32-bit integer mix, which
// spreads sequential ids (the typical database key pattern) across buckets.
//
// Values are stored as Variant with the same strict typed accessors as
// TbpStrDictionary (GetInt, TryGetInt, GetIntDef, SetInt and friends).
//
// Typical use: an in-memory index over a TDataSet or an id-to-data cache,
//   lvIndex.SetInt(lvQuery.FieldByName('ID').AsInteger, lvQuery.RecNo);

interface

uses
  Windows, SysUtils, Classes, Variants;

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpIntDictionary = class(Exception);

  TbpInt64DynArray = array of Int64;

  // ForEach callback; set AStop to True to break the iteration
  TbpIntDictForEach = procedure(AKey: Int64; const AValue: Variant;
    var AStop: Boolean) of object;

  TbpIntDictItem = record
    HashCode: Integer;
    Key: Int64;
    Value: Variant;
  end;
  TbpIntDictItemArray = array of TbpIntDictItem;

  TbpIntDictionary = class
  private
    FItems: TbpIntDictItemArray;
    FCount: Integer;
    FGrowThreshold: Integer;
    // returns the slot index (>= 0) when found, otherwise the bitwise
    // complement of the first empty slot (always negative), XE6-style
    function GetBucketIndex(AKey: Int64; AHashCode: Integer): Integer;
    procedure DoAdd(AHashCode, AIndex: Integer; AKey: Int64; const AValue: Variant);
    procedure Grow;
    procedure Rehash(ANewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(AKey: Int64): Variant;
    procedure SetItem(AKey: Int64; const AValue: Variant);
  public
    constructor Create(AInitialCapacity: Integer = 0);
    // core operations
    procedure Add(AKey: Int64; const AValue: Variant);
    procedure AddOrSet(AKey: Int64; const AValue: Variant);
    function TryGetValue(AKey: Int64; out AValue: Variant): Boolean;
    function ContainsKey(AKey: Int64): Boolean;
    function Remove(AKey: Int64): Boolean;
    procedure Clear;
    procedure SetCapacity(ACapacity: Integer);
    procedure ForEach(ACallback: TbpIntDictForEach);
    function GetKeys: TbpInt64DynArray;
    // typed accessors with validation. GetX raises on a missing key or a
    // wrong stored type, GetXDef returns ADefault instead, TryGetX never
    // raises. Conversion is strict: no boolean-to-int, no numeric strings,
    // no float-to-int truncation
    procedure SetInt(AKey: Int64; AValue: Integer);
    function GetInt(AKey: Int64): Integer;
    function GetIntDef(AKey: Int64; ADefault: Integer): Integer;
    function TryGetInt(AKey: Int64; out AValue: Integer): Boolean;
    procedure SetInt64(AKey: Int64; AValue: Int64);
    function GetInt64(AKey: Int64): Int64;
    function GetInt64Def(AKey: Int64; ADefault: Int64): Int64;
    function TryGetInt64(AKey: Int64; out AValue: Int64): Boolean;
    procedure SetStr(AKey: Int64; const AValue: string);
    function GetStr(AKey: Int64): string;
    function GetStrDef(AKey: Int64; const ADefault: string): string;
    function TryGetStr(AKey: Int64; out AValue: string): Boolean;
    procedure SetBool(AKey: Int64; AValue: Boolean);
    function GetBool(AKey: Int64): Boolean;
    function GetBoolDef(AKey: Int64; ADefault: Boolean): Boolean;
    function TryGetBool(AKey: Int64; out AValue: Boolean): Boolean;
    procedure SetFloat(AKey: Int64; AValue: Double);
    function GetFloat(AKey: Int64): Double;
    function GetFloatDef(AKey: Int64; ADefault: Double): Double;
    function TryGetFloat(AKey: Int64; out AValue: Double): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    // raises EbpIntDictionary on read of a missing key; write acts as AddOrSet
    property Items[AKey: Int64]: Variant read GetItem write SetItem; default;
  end;

// Thomas Wang 64-bit to 32-bit hash, exposed for reuse and benchmarking
function BpHashInt64(AKey: Int64): Integer;

implementation

uses
  BpVariantUtils;

// per-unit names so amalgamated bundles can embed both dictionaries
const
  gcIntEmptyHash = -1;                         // sentinel: slot is free
  gcIntPositiveMask = not Integer($80000000);  // $7FFFFFFF

{$Q-} // the hash mix relies on wrapping 64-bit arithmetic
function BpHashInt64(AKey: Int64): Integer;
begin
  // Thomas Wang's hash64shift: avalanche mix of all 64 key bits.
  // masks guard against sign-fill quirks of shr on Int64 in older compilers
  AKey := (not AKey) + (AKey shl 18);
  AKey := AKey xor ((AKey shr 31) and $00000001FFFFFFFF);
  AKey := AKey * 21;
  AKey := AKey xor ((AKey shr 11) and $001FFFFFFFFFFFFF);
  AKey := AKey + (AKey shl 6);
  AKey := AKey xor ((AKey shr 22) and $000003FFFFFFFFFF);
  Result := Integer(AKey);
end;

// forces a hash into 0..MaxInt so it can never collide with gcIntEmptyHash
function PositiveHashOf(AKey: Int64): Integer;
begin
  Result := gcIntPositiveMask and ((gcIntPositiveMask and BpHashInt64(AKey)) + 1);
end;

constructor TbpIntDictionary.Create(AInitialCapacity: Integer);
begin
  inherited Create;
  if AInitialCapacity < 0 then
    raise EbpIntDictionary.Create('Initial capacity must not be negative');
  if AInitialCapacity > 0 then
    SetCapacity(AInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpIntDictionary.GetBucketIndex(AKey: Int64; AHashCode: Integer): Integer;
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
    if lvHC = gcIntEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, key compare only on hash match
    if (lvHC = AHashCode) and (FItems[lvIndex].Key = AKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpIntDictionary.DoAdd(AHashCode, AIndex: Integer; AKey: Int64; const AValue: Variant);
begin
  FItems[AIndex].HashCode := AHashCode;
  FItems[AIndex].Key := AKey;
  FItems[AIndex].Value := AValue;
  Inc(FCount);
end;

procedure TbpIntDictionary.Rehash(ANewCapacity: Integer);
var
  lvOldItems: TbpIntDictItemArray;
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
    FItems[i].HashCode := gcIntEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := ANewCapacity shr 1 + ANewCapacity shr 2;
  // reinsert using the cached hash codes, no rehashing of the keys
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcIntEmptyHash then
    begin
      lvIndex := not GetBucketIndex(lvOldItems[i].Key, lvOldItems[i].HashCode);
      FItems[lvIndex].HashCode := lvOldItems[i].HashCode;
      FItems[lvIndex].Key := lvOldItems[i].Key;
      FItems[lvIndex].Value := lvOldItems[i].Value;
    end;
end;

procedure TbpIntDictionary.Grow;
var
  lvNewCapacity: Integer;
begin
  lvNewCapacity := Length(FItems) * 2;
  if lvNewCapacity = 0 then
    lvNewCapacity := 4;
  Rehash(lvNewCapacity);
end;

procedure TbpIntDictionary.SetCapacity(ACapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  if ACapacity < FCount then
    raise EbpIntDictionary.Create('Capacity cannot be less than Count');
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

function TbpIntDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpIntDictionary.Add(AKey: Int64; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  if FCount >= FGrowThreshold then
    Grow;
  lvHashCode := PositiveHashOf(AKey);
  lvIndex := GetBucketIndex(AKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpIntDictionary.CreateFmt('Duplicate key: %d', [AKey]);
  DoAdd(lvHashCode, not lvIndex, AKey, AValue);
end;

procedure TbpIntDictionary.AddOrSet(AKey: Int64; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  lvHashCode := PositiveHashOf(AKey);
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

function TbpIntDictionary.TryGetValue(AKey: Int64; out AValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, PositiveHashOf(AKey));
  Result := lvIndex >= 0;
  if Result then
    AValue := FItems[lvIndex].Value
  else
    AValue := Unassigned;
end;

function TbpIntDictionary.ContainsKey(AKey: Int64): Boolean;
begin
  Result := GetBucketIndex(AKey, PositiveHashOf(AKey)) >= 0;
end;

function TbpIntDictionary.Remove(AKey: Int64): Boolean;
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
  lvIndex := GetBucketIndex(AKey, PositiveHashOf(AKey));
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
    if lvHC = gcIntEmptyHash then
      Break;
    lvBucket := lvHC and (lvLen - 1);
    if not InCircularRange(lvGap, lvBucket, lvIndex) then
    begin
      FItems[lvGap] := FItems[lvIndex];
      lvGap := lvIndex;
    end;
  end;
  FItems[lvGap].HashCode := gcIntEmptyHash;
  FItems[lvGap].Key := 0;
  FItems[lvGap].Value := Unassigned;
  Dec(FCount);
end;

procedure TbpIntDictionary.Clear;
begin
  FItems := nil;
  FCount := 0;
  FGrowThreshold := 0;
end;

procedure TbpIntDictionary.ForEach(ACallback: TbpIntDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(ACallback) then
    Exit;
  lvStop := False;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcIntEmptyHash then
    begin
      ACallback(FItems[i].Key, FItems[i].Value, lvStop);
      if lvStop then
        Exit;
    end;
end;

function TbpIntDictionary.GetKeys: TbpInt64DynArray;
var
  i, lvOut: Integer;
begin
  SetLength(Result, FCount);
  lvOut := 0;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcIntEmptyHash then
    begin
      Result[lvOut] := FItems[i].Key;
      Inc(lvOut);
    end;
end;

function TbpIntDictionary.GetItem(AKey: Int64): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, PositiveHashOf(AKey));
  if lvIndex < 0 then
    raise EbpIntDictionary.CreateFmt('Key not found: %d', [AKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpIntDictionary.SetItem(AKey: Int64; const AValue: Variant);
begin
  AddOrSet(AKey, AValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseTypeError(AKey: Int64; const AExpected: string; const AValue: Variant);
begin
  raise EbpIntDictionary.CreateFmt('Value for key %d is not %s (stored type: %s)',
    [AKey, AExpected, VarTypeAsText(VarType(AValue))]);
end;

procedure TbpIntDictionary.SetInt(AKey: Int64; AValue: Integer);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetInt(AKey: Int64): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseTypeError(AKey, 'an Integer', lvValue);
end;

function TbpIntDictionary.GetIntDef(AKey: Int64; ADefault: Integer): Integer;
begin
  if not TryGetInt(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetInt(AKey: Int64; out AValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpIntDictionary.SetInt64(AKey: Int64; AValue: Int64);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetInt64(AKey: Int64): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseTypeError(AKey, 'an Int64', lvValue);
end;

function TbpIntDictionary.GetInt64Def(AKey: Int64; ADefault: Int64): Int64;
begin
  if not TryGetInt64(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetInt64(AKey: Int64; out AValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt64(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpIntDictionary.SetStr(AKey: Int64; const AValue: string);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetStr(AKey: Int64): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseTypeError(AKey, 'a string', lvValue);
end;

function TbpIntDictionary.GetStrDef(AKey: Int64; const ADefault: string): string;
begin
  if not TryGetStr(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetStr(AKey: Int64; out AValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToStr(lvValue, AValue);
  if not Result then
    AValue := '';
end;

procedure TbpIntDictionary.SetBool(AKey: Int64; AValue: Boolean);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetBool(AKey: Int64): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseTypeError(AKey, 'a Boolean', lvValue);
end;

function TbpIntDictionary.GetBoolDef(AKey: Int64; ADefault: Boolean): Boolean;
begin
  if not TryGetBool(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetBool(AKey: Int64; out AValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToBool(lvValue, AValue);
  if not Result then
    AValue := False;
end;

procedure TbpIntDictionary.SetFloat(AKey: Int64; AValue: Double);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetFloat(AKey: Int64): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseTypeError(AKey, 'a Float', lvValue);
end;

function TbpIntDictionary.GetFloatDef(AKey: Int64; ADefault: Double): Double;
begin
  if not TryGetFloat(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetFloat(AKey: Int64; out AValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToFloat(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

end.
