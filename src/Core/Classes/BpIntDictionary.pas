unit BpIntDictionary;

// Int64-key dictionary for Delphi 7/2007+ (no generics), same open-addressing
// engine as TbpStrDictionary. Keys go through the Thomas Wang 64-bit mix;
// values are Variant with the same strict typed accessors.

interface

uses
  SysUtils, Classes, Variants;

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpIntDictionary = class(Exception);

  TbpInt64DynArray = array of Int64;

  // ForEach callback; set aStop to True to break the iteration
  TbpIntDictForEach = procedure(aKey: Int64; const aValue: Variant;
    var aStop: Boolean) of object;

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
    FIterating: Boolean;
    procedure CheckNotIterating;
    // the slot index when found, else the complement of the first empty slot
    function GetBucketIndex(aKey: Int64; aHashCode: Integer): Integer;
    procedure DoAdd(aHashCode, aIndex: Integer; aKey: Int64; const aValue: Variant);
    procedure Grow;
    procedure Rehash(aNewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(aKey: Int64): Variant;
    procedure SetItem(aKey: Int64; const aValue: Variant);
  public
    constructor Create(aInitialCapacity: Integer = 0);
    // core operations
    procedure Add(aKey: Int64; const aValue: Variant);
    procedure AddOrSet(aKey: Int64; const aValue: Variant);
    function TryGetValue(aKey: Int64; out aValue: Variant): Boolean;
    function ContainsKey(aKey: Int64): Boolean;
    function Remove(aKey: Int64): Boolean;
    procedure Clear;
    procedure SetCapacity(aCapacity: Integer);
    procedure ForEach(aCallback: TbpIntDictForEach);
    function GetKeys: TbpInt64DynArray;
    // GetX raises on a missing key or wrong type, GetXDef defaults, TryGetX never raises
    procedure SetInt(aKey: Int64; aValue: Integer);
    function GetInt(aKey: Int64): Integer;
    function GetIntDef(aKey: Int64; aDefault: Integer): Integer;
    function TryGetInt(aKey: Int64; out aValue: Integer): Boolean;
    procedure SetInt64(aKey: Int64; aValue: Int64);
    function GetInt64(aKey: Int64): Int64;
    function GetInt64Def(aKey: Int64; aDefault: Int64): Int64;
    function TryGetInt64(aKey: Int64; out aValue: Int64): Boolean;
    procedure SetStr(aKey: Int64; const aValue: string);
    function GetStr(aKey: Int64): string;
    function GetStrDef(aKey: Int64; const aDefault: string): string;
    function TryGetStr(aKey: Int64; out aValue: string): Boolean;
    procedure SetBool(aKey: Int64; aValue: Boolean);
    function GetBool(aKey: Int64): Boolean;
    function GetBoolDef(aKey: Int64; aDefault: Boolean): Boolean;
    function TryGetBool(aKey: Int64; out aValue: Boolean): Boolean;
    procedure SetFloat(aKey: Int64; aValue: Double);
    function GetFloat(aKey: Int64): Double;
    function GetFloatDef(aKey: Int64; aDefault: Double): Double;
    function TryGetFloat(aKey: Int64; out aValue: Double): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    // raises EbpIntDictionary on read of a missing key; write acts as AddOrSet
    property Items[aKey: Int64]: Variant read GetItem write SetItem; default;
  end;

// Thomas Wang 64-bit to 32-bit hash, exposed for reuse and benchmarking
function BpHashInt64(aKey: Int64): Integer;

implementation

uses
  BpVariantUtils;

// per-unit names so amalgamated bundles can embed both dictionaries
const
  gcIntEmptyHash = -1;                         // sentinel: slot is free
  gcIntPositiveMask = not Integer($80000000);  // $7FFFFFFF

{$Q-} // the hash mix relies on wrapping 64-bit arithmetic
function BpHashInt64(aKey: Int64): Integer;
begin
  // Thomas Wang hash64shift; the masks guard shr sign-fill on older compilers
  aKey := (not aKey) + (aKey shl 18);
  aKey := aKey xor ((aKey shr 31) and $00000001FFFFFFFF);
  aKey := aKey * 21;
  aKey := aKey xor ((aKey shr 11) and $001FFFFFFFFFFFFF);
  aKey := aKey + (aKey shl 6);
  aKey := aKey xor ((aKey shr 22) and $000003FFFFFFFFFF);
  Result := Integer(aKey);
end;

// forces a hash into 0..MaxInt so it can never collide with gcIntEmptyHash
function PositiveHashOf(aKey: Int64): Integer;
begin
  Result := gcIntPositiveMask and ((gcIntPositiveMask and BpHashInt64(aKey)) + 1);
end;

// a callback that adds or removes would make the scan skip or revisit entries
procedure TbpIntDictionary.CheckNotIterating;
begin
  if FIterating then
    raise EbpIntDictionary.Create('The dictionary cannot be changed while ForEach runs');
end;

constructor TbpIntDictionary.Create(aInitialCapacity: Integer);
begin
  inherited Create;
  if aInitialCapacity < 0 then
    raise EbpIntDictionary.Create('Initial capacity must not be negative');
  if aInitialCapacity > 0 then
    SetCapacity(aInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpIntDictionary.GetBucketIndex(aKey: Int64; aHashCode: Integer): Integer;
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
    if lvHC = gcIntEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, key compare only on hash match
    if (lvHC = aHashCode) and (FItems[lvIndex].Key = aKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpIntDictionary.DoAdd(aHashCode, aIndex: Integer; aKey: Int64; const aValue: Variant);
begin
  FItems[aIndex].HashCode := aHashCode;
  FItems[aIndex].Key := aKey;
  FItems[aIndex].Value := aValue;
  Inc(FCount);
end;

procedure TbpIntDictionary.Rehash(aNewCapacity: Integer);
var
  lvOldItems: TbpIntDictItemArray;
  lvIndex: Integer;
  i: Integer;
begin
  // above the early exits: Delphi 7 counts the implicit finalisation as a use
  lvOldItems := nil;
  if aNewCapacity = Length(FItems) then
    Exit;
  if aNewCapacity < 0 then
    OutOfMemoryError;
  lvOldItems := FItems;
  FItems := nil;
  SetLength(FItems, aNewCapacity);
  for i := 0 to aNewCapacity - 1 do
    FItems[i].HashCode := gcIntEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := aNewCapacity shr 1 + aNewCapacity shr 2;
  // reinsert on the cached hash codes, moving each entry as raw bits: a field
  // copy would pay a VarCopy per item and deep-copy every variant array
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcIntEmptyHash then
    begin
      lvIndex := not GetBucketIndex(lvOldItems[i].Key, lvOldItems[i].HashCode);
      System.Move(lvOldItems[i], FItems[lvIndex], SizeOf(TbpIntDictItem));
      // the old slot must forget what it no longer owns, or finalisation frees it
      FillChar(lvOldItems[i], SizeOf(TbpIntDictItem), 0);
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

procedure TbpIntDictionary.SetCapacity(aCapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  CheckNotIterating;
  if aCapacity < FCount then
    raise EbpIntDictionary.Create('Capacity cannot be less than Count');
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

function TbpIntDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpIntDictionary.Add(aKey: Int64; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  CheckNotIterating;
  lvHashCode := PositiveHashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpIntDictionary.CreateFmt('Duplicate key: %d', [aKey]);
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(aKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

procedure TbpIntDictionary.AddOrSet(aKey: Int64; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  CheckNotIterating;
  lvHashCode := PositiveHashOf(aKey);
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

function TbpIntDictionary.TryGetValue(aKey: Int64; out aValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, PositiveHashOf(aKey));
  Result := lvIndex >= 0;
  if Result then
    aValue := FItems[lvIndex].Value
  else
    aValue := Unassigned;
end;

function TbpIntDictionary.ContainsKey(aKey: Int64): Boolean;
begin
  Result := GetBucketIndex(aKey, PositiveHashOf(aKey)) >= 0;
end;

function TbpIntDictionary.Remove(aKey: Int64): Boolean;
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
  CheckNotIterating;
  lvIndex := GetBucketIndex(aKey, PositiveHashOf(aKey));
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
  CheckNotIterating;
  FItems := nil;
  FCount := 0;
  FGrowThreshold := 0;
end;

procedure TbpIntDictionary.ForEach(aCallback: TbpIntDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(aCallback) then
    Exit;
  lvStop := False;
  FIterating := True;
  try
    for i := 0 to Length(FItems) - 1 do
      if FItems[i].HashCode <> gcIntEmptyHash then
      begin
        aCallback(FItems[i].Key, FItems[i].Value, lvStop);
        if lvStop then
          Exit;
      end;
  finally
    FIterating := False;
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

function TbpIntDictionary.GetItem(aKey: Int64): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, PositiveHashOf(aKey));
  if lvIndex < 0 then
    raise EbpIntDictionary.CreateFmt('Key not found: %d', [aKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpIntDictionary.SetItem(aKey: Int64; const aValue: Variant);
begin
  AddOrSet(aKey, aValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseIntTypeError(aKey: Int64; const aExpected: string; const aValue: Variant);
begin
  raise EbpIntDictionary.CreateFmt('Value for key %d is not %s (stored type: %s)',
    [aKey, aExpected, VarTypeAsText(VarType(aValue))]);
end;

procedure TbpIntDictionary.SetInt(aKey: Int64; aValue: Integer);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetInt(aKey: Int64): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseIntTypeError(aKey, 'an Integer', lvValue);
end;

function TbpIntDictionary.GetIntDef(aKey: Int64; aDefault: Integer): Integer;
begin
  if not TryGetInt(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetInt(aKey: Int64; out aValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpIntDictionary.SetInt64(aKey: Int64; aValue: Int64);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetInt64(aKey: Int64): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseIntTypeError(aKey, 'an Int64', lvValue);
end;

function TbpIntDictionary.GetInt64Def(aKey: Int64; aDefault: Int64): Int64;
begin
  if not TryGetInt64(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetInt64(aKey: Int64; out aValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt64(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpIntDictionary.SetStr(aKey: Int64; const aValue: string);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetStr(aKey: Int64): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseIntTypeError(aKey, 'a string', lvValue);
end;

function TbpIntDictionary.GetStrDef(aKey: Int64; const aDefault: string): string;
begin
  if not TryGetStr(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetStr(aKey: Int64; out aValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToStr(lvValue, aValue);
  if not Result then
    aValue := '';
end;

procedure TbpIntDictionary.SetBool(aKey: Int64; aValue: Boolean);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetBool(aKey: Int64): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseIntTypeError(aKey, 'a Boolean', lvValue);
end;

function TbpIntDictionary.GetBoolDef(aKey: Int64; aDefault: Boolean): Boolean;
begin
  if not TryGetBool(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetBool(aKey: Int64; out aValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToBool(lvValue, aValue);
  if not Result then
    aValue := False;
end;

procedure TbpIntDictionary.SetFloat(aKey: Int64; aValue: Double);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetFloat(aKey: Int64): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseIntTypeError(aKey, 'a Float', lvValue);
end;

function TbpIntDictionary.GetFloatDef(aKey: Int64; aDefault: Double): Double;
begin
  if not TryGetFloat(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetFloat(aKey: Int64; out aValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToFloat(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

end.
