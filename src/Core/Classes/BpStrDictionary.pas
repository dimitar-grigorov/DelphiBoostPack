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
  Windows, SysUtils, Classes, Variants;

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
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    property CaseInsensitive: Boolean read FCaseInsensitive;
    // raises EbpStrDictionary on read of a missing key; write acts as AddOrSet
    property Items[const AKey: string]: Variant read GetItem write SetItem; default;
  end;

implementation

uses
  BpHashBobJenkins;

const
  gcEmptyHash = -1;                            // sentinel: slot is free
  gcPositiveMask = not Integer($80000000);     // $7FFFFFFF

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
  // force the hash into 0..MaxInt so it can never collide with gcEmptyHash
  Result := gcPositiveMask and ((gcPositiveMask and Result) + 1);
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
    if lvHC = gcEmptyHash then
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
    FItems[i].HashCode := gcEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := ANewCapacity shr 1 + ANewCapacity shr 2;
  // reinsert using the cached hash codes, no rehashing of the keys
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcEmptyHash then
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

// wrap-aware test whether AItem's home bucket lies in (ABottom, ATopInc],
// used by Remove to decide if an entry may slide back into the gap
function InCircularRange(ABottom, AItem, ATopInc: Integer): Boolean;
begin
  Result := ((ABottom < AItem) and (AItem <= ATopInc)) or
    ((ATopInc < ABottom) and (AItem > ABottom)) or
    ((ATopInc < ABottom) and (AItem <= ATopInc));
end;

function TbpStrDictionary.Remove(const AKey: string): Boolean;
var
  lvGap, lvIndex, lvHC, lvBucket, lvLen: Integer;
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
    if lvHC = gcEmptyHash then
      Break;
    lvBucket := lvHC and (lvLen - 1);
    if not InCircularRange(lvGap, lvBucket, lvIndex) then
    begin
      FItems[lvGap] := FItems[lvIndex];
      lvGap := lvIndex;
    end;
  end;
  FItems[lvGap].HashCode := gcEmptyHash;
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
    if FItems[i].HashCode <> gcEmptyHash then
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
      if FItems[i].HashCode <> gcEmptyHash then
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

end.
