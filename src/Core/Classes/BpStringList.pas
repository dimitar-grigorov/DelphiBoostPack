unit BpStringList;

// A TStringList with O(1) IndexOf and IndexOfName. It descends from TStringList,
// so anything taking a TStrings takes it unchanged, and the index is maintained
// on each mutation instead of rebuilt wholesale the way THashedStringList is.

interface

uses
  SysUtils, Classes, BpKeyFold;

type
  // one chained hash index over the list, addressed by list position: Buckets
  // holds each chain head, Next the following position, Hash the cached hash
  TbpStrListIndex = record
    Buckets: array of Integer;
    Next: array of Integer;
    Hash: array of Integer;
    Mask: Integer;
    Valid: Boolean;
  end;

  TbpStringList = class(TStringList)
  private
    FValueIndex: TbpStrListIndex;
    FNameIndex: TbpStrListIndex;
    FIndexedCaseSensitive: Boolean;
    FIndexedSeparator: Char;
    function KeyHash(const aKey: string): Integer;
    function KeysEqual(const aKey1, aKey2: string): Boolean;
    function NameHashAt(aIndex: Integer): Integer;
    function NameOf(aIndex: Integer): string;
    procedure IndexReset(var aIdx: TbpStrListIndex);
    procedure IndexRechain(var aIdx: TbpStrListIndex; aBucketCount: Integer);
    procedure IndexRebuild(var aIdx: TbpStrListIndex; aNames: Boolean);
    procedure ChainAdd(var aIdx: TbpStrListIndex; aPos, aHash: Integer);
    procedure ChainRemove(var aIdx: TbpStrListIndex; aPos: Integer);
    procedure ShiftPositions(var aIdx: TbpStrListIndex; aFrom, aDelta, aCount: Integer);
    procedure IndexInsertAt(var aIdx: TbpStrListIndex; aPos, aHash: Integer);
    procedure IndexDeleteAt(var aIdx: TbpStrListIndex; aPos: Integer);
    function IndexLookup(var aIdx: TbpStrListIndex; const aKey: string; aNames: Boolean): Integer;
    procedure DropIndexesIfSettingsChanged;
  protected
    procedure InsertItem(aIndex: Integer; const aStr: string; aObject: TObject); override;
    procedure Put(aIndex: Integer; const aStr: string); override;
  public
    procedure Clear; override;
    procedure Delete(aIndex: Integer); override;
    procedure Exchange(aIndex1, aIndex2: Integer); override;
    procedure Sort; override;
    procedure CustomSort(aCompare: TStringListSortCompare); override;
    function IndexOf(const aStr: string): Integer; override;
    function IndexOfName(const aName: string): Integer; override;
    // False after an operation that reorders the list; the next lookup rebuilds
    function IndexIsCurrent: Boolean;
  end;

implementation

const
  gcBpMinBuckets = 16;
  gcBpNoKey = -1;        // this row takes no part in the index
  gcBpSpare = 16;        // slack kept in the parallel arrays

// FNV-1a over the key, folded when the list is case-insensitive
function TbpStringList.KeyHash(const aKey: string): Integer;
var
  i: Integer;
  lvH: Cardinal;
begin
  if not CaseSensitive then
  begin
    // BpKeyFold folds the way CompareStrings compares, so hash and equality agree
    Result := BpFoldedHash(aKey);
    Exit;
  end;
  lvH := 2166136261;
  for i := 1 to Length(aKey) do
    lvH := (lvH xor Cardinal(Ord(aKey[i]))) * 16777619;
  Result := Integer(lvH and $7FFFFFFF);
end;

// must agree with TStringList.CompareStrings, which is what the list searches with
function TbpStringList.KeysEqual(const aKey1, aKey2: string): Boolean;
begin
  Result := CompareStrings(aKey1, aKey2) = 0;
end;

// the part before NameValueSeparator, '' when the row has no separator
function TbpStringList.NameOf(aIndex: Integer): string;
var
  lvLine: string;
  lvPos: Integer;
begin
  lvLine := Get(aIndex);
  lvPos := AnsiPos(NameValueSeparator, lvLine);
  if lvPos > 0 then
    Result := Copy(lvLine, 1, lvPos - 1)
  else
    Result := '';
end;

function TbpStringList.NameHashAt(aIndex: Integer): Integer;
var
  lvLine: string;
  lvPos: Integer;
begin
  lvLine := Get(aIndex);
  lvPos := AnsiPos(NameValueSeparator, lvLine);
  if lvPos > 0 then
    Result := KeyHash(Copy(lvLine, 1, lvPos - 1))
  else
    Result := gcBpNoKey;
end;

procedure TbpStringList.IndexReset(var aIdx: TbpStrListIndex);
begin
  aIdx.Buckets := nil;
  aIdx.Next := nil;
  aIdx.Hash := nil;
  aIdx.Mask := -1;
  aIdx.Valid := False;
end;

// sizes the bucket array for aBucketCount and rebuilds every chain from Hash[]
procedure TbpStringList.IndexRechain(var aIdx: TbpStrListIndex; aBucketCount: Integer);
var
  i, lvBucket: Integer;
begin
  SetLength(aIdx.Buckets, aBucketCount);
  aIdx.Mask := aBucketCount - 1;
  for i := 0 to aBucketCount - 1 do
    aIdx.Buckets[i] := -1;
  for i := 0 to Count - 1 do
  begin
    aIdx.Next[i] := -1;
    if aIdx.Hash[i] <> gcBpNoKey then
    begin
      lvBucket := aIdx.Hash[i] and aIdx.Mask;
      aIdx.Next[i] := aIdx.Buckets[lvBucket];
      aIdx.Buckets[lvBucket] := i;
    end;
  end;
end;

procedure TbpStringList.IndexRebuild(var aIdx: TbpStrListIndex; aNames: Boolean);
var
  i, lvBuckets: Integer;
begin
  SetLength(aIdx.Hash, Count + gcBpSpare);
  SetLength(aIdx.Next, Count + gcBpSpare);
  for i := 0 to Count - 1 do
    if aNames then
      aIdx.Hash[i] := NameHashAt(i)
    else
      aIdx.Hash[i] := KeyHash(Get(i));
  lvBuckets := gcBpMinBuckets;
  while lvBuckets * 3 div 4 < Count do
    lvBuckets := lvBuckets * 2;
  IndexRechain(aIdx, lvBuckets);
  aIdx.Valid := True;
end;

procedure TbpStringList.ChainAdd(var aIdx: TbpStrListIndex; aPos, aHash: Integer);
var
  lvBucket: Integer;
begin
  aIdx.Hash[aPos] := aHash;
  aIdx.Next[aPos] := -1;
  if aHash = gcBpNoKey then
    Exit;
  lvBucket := aHash and aIdx.Mask;
  aIdx.Next[aPos] := aIdx.Buckets[lvBucket];
  aIdx.Buckets[lvBucket] := aPos;
end;

procedure TbpStringList.ChainRemove(var aIdx: TbpStrListIndex; aPos: Integer);
var
  lvBucket, lvCur: Integer;
begin
  if aIdx.Hash[aPos] = gcBpNoKey then
    Exit;
  lvBucket := aIdx.Hash[aPos] and aIdx.Mask;
  lvCur := aIdx.Buckets[lvBucket];
  if lvCur = aPos then
  begin
    aIdx.Buckets[lvBucket] := aIdx.Next[aPos];
    Exit;
  end;
  while (lvCur <> -1) and (aIdx.Next[lvCur] <> aPos) do
    lvCur := aIdx.Next[lvCur];
  if lvCur <> -1 then
    aIdx.Next[lvCur] := aIdx.Next[aPos];
end;

// every stored position at or above aFrom moves by aDelta
procedure TbpStringList.ShiftPositions(var aIdx: TbpStrListIndex; aFrom, aDelta, aCount: Integer);
var
  i: Integer;
begin
  for i := 0 to aIdx.Mask do
    if aIdx.Buckets[i] >= aFrom then
      aIdx.Buckets[i] := aIdx.Buckets[i] + aDelta;
  for i := 0 to aCount - 1 do
    if aIdx.Next[i] >= aFrom then
      aIdx.Next[i] := aIdx.Next[i] + aDelta;
end;

// called after the row is already in the list, so Count includes it
procedure TbpStringList.IndexInsertAt(var aIdx: TbpStrListIndex; aPos, aHash: Integer);
var
  i, lvBuckets: Integer;
begin
  if not aIdx.Valid then
    Exit;
  if Length(aIdx.Hash) < Count then
  begin
    SetLength(aIdx.Hash, Count + gcBpSpare);
    SetLength(aIdx.Next, Count + gcBpSpare);
  end;
  if aPos < Count - 1 then
  begin
    ShiftPositions(aIdx, aPos, 1, Count - 1);
    for i := Count - 1 downto aPos + 1 do
    begin
      aIdx.Hash[i] := aIdx.Hash[i - 1];
      aIdx.Next[i] := aIdx.Next[i - 1];
    end;
  end;
  aIdx.Hash[aPos] := aHash;
  aIdx.Next[aPos] := -1;
  if Count > (aIdx.Mask + 1) * 3 div 4 then
  begin
    lvBuckets := aIdx.Mask + 1;
    while lvBuckets * 3 div 4 < Count do
      lvBuckets := lvBuckets * 2;
    IndexRechain(aIdx, lvBuckets);
  end
  else
    ChainAdd(aIdx, aPos, aHash);
end;

// called after the row is already gone, so Count excludes it
procedure TbpStringList.IndexDeleteAt(var aIdx: TbpStrListIndex; aPos: Integer);
var
  i: Integer;
begin
  if not aIdx.Valid then
    Exit;
  ChainRemove(aIdx, aPos);
  for i := aPos to Count - 1 do
  begin
    aIdx.Hash[i] := aIdx.Hash[i + 1];
    aIdx.Next[i] := aIdx.Next[i + 1];
  end;
  ShiftPositions(aIdx, aPos + 1, -1, Count);
end;

function TbpStringList.IndexLookup(var aIdx: TbpStrListIndex; const aKey: string; aNames: Boolean): Integer;
var
  lvHash, lvPos: Integer;
begin
  Result := -1;
  if Count = 0 then
    Exit;
  if not aIdx.Valid then
    IndexRebuild(aIdx, aNames);
  lvHash := KeyHash(aKey);
  lvPos := aIdx.Buckets[lvHash and aIdx.Mask];
  // the whole chain is walked: IndexOf answers with the lowest matching row
  while lvPos <> -1 do
  begin
    if (aIdx.Hash[lvPos] = lvHash) and ((Result = -1) or (lvPos < Result)) then
    begin
      if aNames then
      begin
        if KeysEqual(NameOf(lvPos), aKey) then
          Result := lvPos;
      end
      else if KeysEqual(Get(lvPos), aKey) then
        Result := lvPos;
    end;
    lvPos := aIdx.Next[lvPos];
  end;
end;

// neither CaseSensitive nor NameValueSeparator is virtual, so both are checked here
procedure TbpStringList.DropIndexesIfSettingsChanged;
begin
  if (FIndexedCaseSensitive <> CaseSensitive) or (FIndexedSeparator <> NameValueSeparator) then
  begin
    IndexReset(FValueIndex);
    IndexReset(FNameIndex);
    FIndexedCaseSensitive := CaseSensitive;
    FIndexedSeparator := NameValueSeparator;
  end;
end;

procedure TbpStringList.InsertItem(aIndex: Integer; const aStr: string; aObject: TObject);
begin
  inherited InsertItem(aIndex, aStr, aObject);
  DropIndexesIfSettingsChanged;
  IndexInsertAt(FValueIndex, aIndex, KeyHash(aStr));
  if FNameIndex.Valid then
    IndexInsertAt(FNameIndex, aIndex, NameHashAt(aIndex));
end;

procedure TbpStringList.Put(aIndex: Integer; const aStr: string);
begin
  inherited Put(aIndex, aStr);
  DropIndexesIfSettingsChanged;
  if FValueIndex.Valid then
  begin
    ChainRemove(FValueIndex, aIndex);
    ChainAdd(FValueIndex, aIndex, KeyHash(aStr));
  end;
  if FNameIndex.Valid then
  begin
    ChainRemove(FNameIndex, aIndex);
    ChainAdd(FNameIndex, aIndex, NameHashAt(aIndex));
  end;
end;

procedure TbpStringList.Clear;
begin
  inherited Clear;
  IndexReset(FValueIndex);
  IndexReset(FNameIndex);
end;

procedure TbpStringList.Delete(aIndex: Integer);
begin
  inherited Delete(aIndex);
  IndexDeleteAt(FValueIndex, aIndex);
  IndexDeleteAt(FNameIndex, aIndex);
end;

procedure TbpStringList.Exchange(aIndex1, aIndex2: Integer);
begin
  inherited Exchange(aIndex1, aIndex2);
  // rare enough that a lazy rebuild beats the bookkeeping
  FValueIndex.Valid := False;
  FNameIndex.Valid := False;
end;

procedure TbpStringList.Sort;
begin
  inherited Sort;
  FValueIndex.Valid := False;
  FNameIndex.Valid := False;
end;

procedure TbpStringList.CustomSort(aCompare: TStringListSortCompare);
begin
  inherited CustomSort(aCompare);
  FValueIndex.Valid := False;
  FNameIndex.Valid := False;
end;

function TbpStringList.IndexOf(const aStr: string): Integer;
begin
  DropIndexesIfSettingsChanged;
  Result := IndexLookup(FValueIndex, aStr, False);
end;

function TbpStringList.IndexOfName(const aName: string): Integer;
begin
  DropIndexesIfSettingsChanged;
  Result := IndexLookup(FNameIndex, aName, True);
end;

function TbpStringList.IndexIsCurrent: Boolean;
begin
  Result := FValueIndex.Valid;
end;

end.
