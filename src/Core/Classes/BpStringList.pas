unit BpStringList;

// A TStrings with O(1) IndexOf and IndexOfName. Hash, equality and order all
// come from one ordinal relation (BpKeyFold), so a hash hit and a binary search
// cannot disagree. Rows live in stable slots and positions are a separate order
// array, so a mutation permutes ints and never touches a chain. Nothing is
// hashed until the first lookup.

interface

uses
  SysUtils, Classes, RTLConsts, BpKeyFold;

type
  TbpStringList = class;

  // like TStringListSortCompare, on the positions the list had when Sort began
  TbpStringListSortCompare = function(aList: TbpStringList; aIndex1, aIndex2: Integer): Integer;

  TbpStrSlot = record
    Str: string;
    Obj: TObject;
    Hash: Cardinal;         // of Str, meaningful while the value index exists
    NameHash: Cardinal;     // of the name part, meaningful while the name index exists
    Next: Integer;          // next slot in the value chain, or in the free list
    NameNext: Integer;      // next slot in the name chain, gcBpNoName when the row has no name
  end;

  TbpStringList = class(TStrings)
  private
    FSlots: array of TbpStrSlot;
    FOrder: array of Integer;         // slot id at each position
    FPos: array of Integer;           // position of each slot, trusted below FPosValid
    FPosValid: Integer;
    FCount: Integer;
    FSlotsUsed: Integer;              // slots ever handed out, the free list included
    FFree: Integer;                   // free slot list head, -1 when empty
    FBuckets: array of Integer;       // value chain heads, nil until the first IndexOf
    FNameBuckets: array of Integer;   // name chain heads, nil until the first IndexOfName
    FNameSeparator: Char;             // the separator the name index was built with
    FSorted: Boolean;
    FDuplicates: TDuplicates;
    FCaseSensitive: Boolean;
    FOnChange: TNotifyEvent;
    FOnChanging: TNotifyEvent;
    function AllocSlot: Integer;
    procedure Grow;
    procedure RefreshPositions;
    function NameLength(aSlot: Integer): Integer;
    procedure BuildValueIndex;
    procedure BuildNameIndex;
    procedure RechainValues(aBucketCount: Integer);
    procedure RechainNames(aBucketCount: Integer);
    procedure LinkValue(aSlot: Integer);
    procedure LinkName(aSlot: Integer);
    procedure UnlinkValue(aSlot: Integer);
    procedure UnlinkName(aSlot: Integer);
    function CompareSlot(aSlot: Integer; const aStr: string): Integer;
    procedure SortOrder(aCompare: TbpStringListSortCompare);
    procedure InsertItem(aIndex: Integer; const aStr: string; aObject: TObject);
    procedure CheckIndex(aIndex: Integer);
    procedure CheckNotSorted;
    procedure SetSorted(aValue: Boolean);
    procedure SetCaseSensitive(aValue: Boolean);
  protected
    procedure Changed; virtual;
    procedure Changing; virtual;
    function Get(aIndex: Integer): string; override;
    function GetCapacity: Integer; override;
    function GetCount: Integer; override;
    function GetObject(aIndex: Integer): TObject; override;
    procedure Put(aIndex: Integer; const aStr: string); override;
    procedure PutObject(aIndex: Integer; aObject: TObject); override;
    procedure SetCapacity(aNewCapacity: Integer); override;
    procedure SetUpdateState(aUpdating: Boolean); override;
    function CompareStrings(const aS1, aS2: string): Integer; override;
  public
    constructor Create;
    function Add(const aStr: string): Integer; override;
    function AddObject(const aStr: string; aObject: TObject): Integer; override;
    procedure Assign(aSource: TPersistent); override;
    procedure Clear; override;
    procedure Delete(aIndex: Integer); override;
    procedure Exchange(aIndex1, aIndex2: Integer); override;
    // Sorted: a binary search, aIndex the insertion point on a miss. First equal row.
    function Find(const aStr: string; var aIndex: Integer): Boolean;
    function IndexOf(const aStr: string): Integer; override;
    function IndexOfName(const aName: string): Integer; override;
    procedure Insert(aIndex: Integer; const aStr: string); override;
    procedure InsertObject(aIndex: Integer; const aStr: string; aObject: TObject); override;
    procedure Move(aCurIndex, aNewIndex: Integer); override;
    // stable, so sorting by a second key after a first gives a two-key sort
    procedure Sort; virtual;
    procedure CustomSort(aCompare: TbpStringListSortCompare); virtual;
    // consulted by Add on a Sorted list only, as in TStringList
    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
    property Sorted: Boolean read FSorted write SetSorted;
    property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnChanging: TNotifyEvent read FOnChanging write FOnChanging;
  end;

implementation

const
  gcBpNoName = -2;         // NameNext of a row with no separator: not in any chain
  gcBpMinBuckets = 16;
  gcBpMinCapacity = 16;

// buckets sized so the load never passes 3/4
function BucketCountFor(aCount: Integer): Integer;
begin
  Result := gcBpMinBuckets;
  while Result * 3 div 4 < aCount do
    Result := Result * 2;
end;

// storage

constructor TbpStringList.Create;
begin
  inherited Create;
  FFree := -1;
end;

procedure TbpStringList.Grow;
var
  lvCapacity: Integer;
begin
  lvCapacity := Length(FOrder);
  if lvCapacity < gcBpMinCapacity then
    lvCapacity := gcBpMinCapacity
  else
    lvCapacity := lvCapacity + lvCapacity div 2;
  SetCapacity(lvCapacity);
end;

// FCount <= FSlotsUsed <= Length(FSlots) = Length(FOrder), so FOrder always fits
function TbpStringList.AllocSlot: Integer;
begin
  if FFree >= 0 then
  begin
    Result := FFree;
    FFree := FSlots[Result].Next;
    Exit;
  end;
  if FSlotsUsed = Length(FSlots) then
    Grow;
  Result := FSlotsUsed;
  Inc(FSlotsUsed);
end;

procedure TbpStringList.RefreshPositions;
var
  i: Integer;
begin
  for i := FPosValid to FCount - 1 do
    FPos[FOrder[i]] := i;
  FPosValid := FCount;
end;

function TbpStringList.GetCapacity: Integer;
begin
  Result := Length(FOrder);
end;

procedure TbpStringList.SetCapacity(aNewCapacity: Integer);
begin
  // a slot above FSlotsUsed is never referenced, so the slot array may shrink to it
  if aNewCapacity < FSlotsUsed then
    aNewCapacity := FSlotsUsed;
  SetLength(FOrder, aNewCapacity);
  SetLength(FSlots, aNewCapacity);
  SetLength(FPos, aNewCapacity);
end;

function TbpStringList.GetCount: Integer;
begin
  Result := FCount;
end;

procedure TbpStringList.CheckIndex(aIndex: Integer);
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    Error(@SListIndexError, aIndex);
end;

procedure TbpStringList.CheckNotSorted;
begin
  if FSorted then
    Error(@SSortedListError, 0);
end;

function TbpStringList.Get(aIndex: Integer): string;
begin
  CheckIndex(aIndex);
  Result := FSlots[FOrder[aIndex]].Str;
end;

function TbpStringList.GetObject(aIndex: Integer): TObject;
begin
  CheckIndex(aIndex);
  Result := FSlots[FOrder[aIndex]].Obj;
end;

// the relation

function TbpStringList.CompareStrings(const aS1, aS2: string): Integer;
begin
  Result := BpKeyCompare(aS1, aS2, not FCaseSensitive);
end;

function TbpStringList.CompareSlot(aSlot: Integer; const aStr: string): Integer;
begin
  Result := BpKeyCompare(FSlots[aSlot].Str, aStr, not FCaseSensitive);
end;

// characters before the separator the name index was built with, -1 when none
function TbpStringList.NameLength(aSlot: Integer): Integer;
begin
  Result := AnsiPos(FNameSeparator, FSlots[aSlot].Str) - 1;
end;

// the value index

procedure TbpStringList.RechainValues(aBucketCount: Integer);
var
  i, lvSlot, lvBucket: Integer;
begin
  SetLength(FBuckets, aBucketCount);
  for i := 0 to aBucketCount - 1 do
    FBuckets[i] := -1;
  // linked from the last position down, so a chain runs in position order
  for i := FCount - 1 downto 0 do
  begin
    lvSlot := FOrder[i];
    lvBucket := Integer(FSlots[lvSlot].Hash and Cardinal(aBucketCount - 1));
    FSlots[lvSlot].Next := FBuckets[lvBucket];
    FBuckets[lvBucket] := lvSlot;
  end;
end;

procedure TbpStringList.BuildValueIndex;
var
  i, lvSlot: Integer;
begin
  for i := 0 to FCount - 1 do
  begin
    lvSlot := FOrder[i];
    FSlots[lvSlot].Hash := BpKeyHash(FSlots[lvSlot].Str, not FCaseSensitive);
  end;
  RechainValues(BucketCountFor(FCount));
end;

// the slot is already at its position in FOrder, so a rechain sees it too
procedure TbpStringList.LinkValue(aSlot: Integer);
var
  lvBucket: Integer;
begin
  FSlots[aSlot].Hash := BpKeyHash(FSlots[aSlot].Str, not FCaseSensitive);
  if FCount > Length(FBuckets) * 3 div 4 then
  begin
    RechainValues(Length(FBuckets) * 2);
    Exit;
  end;
  lvBucket := Integer(FSlots[aSlot].Hash and Cardinal(Length(FBuckets) - 1));
  FSlots[aSlot].Next := FBuckets[lvBucket];
  FBuckets[lvBucket] := aSlot;
end;

procedure TbpStringList.UnlinkValue(aSlot: Integer);
var
  lvBucket, lvCur: Integer;
begin
  lvBucket := Integer(FSlots[aSlot].Hash and Cardinal(Length(FBuckets) - 1));
  lvCur := FBuckets[lvBucket];
  if lvCur = aSlot then
  begin
    FBuckets[lvBucket] := FSlots[aSlot].Next;
    Exit;
  end;
  while FSlots[lvCur].Next <> aSlot do
    lvCur := FSlots[lvCur].Next;
  FSlots[lvCur].Next := FSlots[aSlot].Next;
end;

// the name index

procedure TbpStringList.RechainNames(aBucketCount: Integer);
var
  i, lvSlot, lvBucket: Integer;
begin
  SetLength(FNameBuckets, aBucketCount);
  for i := 0 to aBucketCount - 1 do
    FNameBuckets[i] := -1;
  for i := FCount - 1 downto 0 do
  begin
    lvSlot := FOrder[i];
    if FSlots[lvSlot].NameNext = gcBpNoName then
      Continue;
    lvBucket := Integer(FSlots[lvSlot].NameHash and Cardinal(aBucketCount - 1));
    FSlots[lvSlot].NameNext := FNameBuckets[lvBucket];
    FNameBuckets[lvBucket] := lvSlot;
  end;
end;

procedure TbpStringList.BuildNameIndex;
var
  i, lvSlot, lvLen: Integer;
begin
  FNameSeparator := NameValueSeparator;
  for i := 0 to FCount - 1 do
  begin
    lvSlot := FOrder[i];
    lvLen := NameLength(lvSlot);
    if lvLen < 0 then
      FSlots[lvSlot].NameNext := gcBpNoName
    else
    begin
      FSlots[lvSlot].NameNext := -1;
      FSlots[lvSlot].NameHash := BpKeyHashBuf(PChar(FSlots[lvSlot].Str), lvLen, not FCaseSensitive);
    end;
  end;
  RechainNames(BucketCountFor(FCount));
end;

procedure TbpStringList.LinkName(aSlot: Integer);
var
  lvLen, lvBucket: Integer;
begin
  lvLen := NameLength(aSlot);
  if lvLen < 0 then
  begin
    FSlots[aSlot].NameNext := gcBpNoName;
    Exit;
  end;
  FSlots[aSlot].NameHash := BpKeyHashBuf(PChar(FSlots[aSlot].Str), lvLen, not FCaseSensitive);
  FSlots[aSlot].NameNext := -1;
  if FCount > Length(FNameBuckets) * 3 div 4 then
  begin
    RechainNames(Length(FNameBuckets) * 2);
    Exit;
  end;
  lvBucket := Integer(FSlots[aSlot].NameHash and Cardinal(Length(FNameBuckets) - 1));
  FSlots[aSlot].NameNext := FNameBuckets[lvBucket];
  FNameBuckets[lvBucket] := aSlot;
end;

procedure TbpStringList.UnlinkName(aSlot: Integer);
var
  lvBucket, lvCur: Integer;
begin
  if FSlots[aSlot].NameNext = gcBpNoName then
    Exit;
  lvBucket := Integer(FSlots[aSlot].NameHash and Cardinal(Length(FNameBuckets) - 1));
  lvCur := FNameBuckets[lvBucket];
  if lvCur = aSlot then
  begin
    FNameBuckets[lvBucket] := FSlots[aSlot].NameNext;
    Exit;
  end;
  while FSlots[lvCur].NameNext <> aSlot do
    lvCur := FSlots[lvCur].NameNext;
  FSlots[lvCur].NameNext := FSlots[aSlot].NameNext;
end;

// lookups

function TbpStringList.IndexOf(const aStr: string): Integer;
var
  lvHash: Cardinal;
  lvSlot: Integer;
begin
  Result := -1;
  if FCount = 0 then
    Exit;
  if FBuckets = nil then
    BuildValueIndex;
  if FPosValid < FCount then
    RefreshPositions;
  lvHash := BpKeyHash(aStr, not FCaseSensitive);
  lvSlot := FBuckets[Integer(lvHash and Cardinal(Length(FBuckets) - 1))];
  // the whole chain, because the answer is the lowest position among duplicates
  while lvSlot >= 0 do
  begin
    if (FSlots[lvSlot].Hash = lvHash) and BpKeyEquals(FSlots[lvSlot].Str, aStr, not FCaseSensitive) then
      if (Result < 0) or (FPos[lvSlot] < Result) then
        Result := FPos[lvSlot];
    lvSlot := FSlots[lvSlot].Next;
  end;
end;

function TbpStringList.IndexOfName(const aName: string): Integer;
var
  lvHash: Cardinal;
  lvSlot: Integer;
begin
  Result := -1;
  if FCount = 0 then
    Exit;
  // NameValueSeparator is not virtual, so a change is noticed here
  if (FNameBuckets <> nil) and (FNameSeparator <> NameValueSeparator) then
    FNameBuckets := nil;
  if FNameBuckets = nil then
    BuildNameIndex;
  if FPosValid < FCount then
    RefreshPositions;
  lvHash := BpKeyHash(aName, not FCaseSensitive);
  lvSlot := FNameBuckets[Integer(lvHash and Cardinal(Length(FNameBuckets) - 1))];
  while lvSlot >= 0 do
  begin
    if (FSlots[lvSlot].NameHash = lvHash) and
      BpKeyEqualsBuf(aName, PChar(FSlots[lvSlot].Str), NameLength(lvSlot), not FCaseSensitive) then
      if (Result < 0) or (FPos[lvSlot] < Result) then
        Result := FPos[lvSlot];
    lvSlot := FSlots[lvSlot].NameNext;
  end;
end;

function TbpStringList.Find(const aStr: string; var aIndex: Integer): Boolean;
var
  lvLow, lvHigh, lvMid, lvCmp: Integer;
begin
  if not FSorted then
  begin
    aIndex := IndexOf(aStr);
    Result := aIndex >= 0;
    if not Result then
      aIndex := FCount;
    Exit;
  end;
  Result := False;
  lvLow := 0;
  lvHigh := FCount - 1;
  // keeps bisecting on a hit, so aIndex lands on the first equal row
  while lvLow <= lvHigh do
  begin
    lvMid := (lvLow + lvHigh) shr 1;
    lvCmp := CompareSlot(FOrder[lvMid], aStr);
    if lvCmp < 0 then
      lvLow := lvMid + 1
    else
    begin
      lvHigh := lvMid - 1;
      if lvCmp = 0 then
        Result := True;
    end;
  end;
  aIndex := lvLow;
end;

// mutation

procedure TbpStringList.Changed;
begin
  if (UpdateCount = 0) and Assigned(FOnChange) then
    FOnChange(Self);
end;

// a handler may mutate, so an index captured before this call is checked again after it
procedure TbpStringList.Changing;
begin
  if (UpdateCount = 0) and Assigned(FOnChanging) then
    FOnChanging(Self);
end;

procedure TbpStringList.SetUpdateState(aUpdating: Boolean);
begin
  if aUpdating then
    Changing
  else
    Changed;
end;

// the structure is complete before Changed runs, so a handler may look up or mutate
procedure TbpStringList.InsertItem(aIndex: Integer; const aStr: string; aObject: TObject);
var
  lvSlot: Integer;
begin
  Changing;
  if (aIndex < 0) or (aIndex > FCount) then
    Error(@SListIndexError, aIndex);
  lvSlot := AllocSlot;
  FSlots[lvSlot].Str := aStr;
  FSlots[lvSlot].Obj := aObject;
  if aIndex < FCount then
    System.Move(FOrder[aIndex], FOrder[aIndex + 1], (FCount - aIndex) * SizeOf(Integer));
  FOrder[aIndex] := lvSlot;
  Inc(FCount);
  if aIndex = FPosValid then
  begin
    // an append onto a fully trusted array stays fully trusted
    FPos[lvSlot] := aIndex;
    Inc(FPosValid);
  end
  else if aIndex < FPosValid then
    FPosValid := aIndex;
  if FBuckets <> nil then
    LinkValue(lvSlot);
  if FNameBuckets <> nil then
    LinkName(lvSlot);
  Changed;
end;

function TbpStringList.Add(const aStr: string): Integer;
begin
  Result := AddObject(aStr, nil);
end;

function TbpStringList.AddObject(const aStr: string; aObject: TObject): Integer;
begin
  if FSorted then
  begin
    if Find(aStr, Result) then
    begin
      case FDuplicates of
        dupIgnore: Exit;
        dupError: Error(@SDuplicateString, 0);
      end;
      // past the equal run, so equal keys stay in insertion order
      while (Result < FCount) and (CompareSlot(FOrder[Result], aStr) = 0) do
        Inc(Result);
    end;
  end
  else
    Result := FCount;
  InsertItem(Result, aStr, aObject);
end;

procedure TbpStringList.Insert(aIndex: Integer; const aStr: string);
begin
  InsertObject(aIndex, aStr, nil);
end;

procedure TbpStringList.InsertObject(aIndex: Integer; const aStr: string; aObject: TObject);
begin
  CheckNotSorted;
  if (aIndex < 0) or (aIndex > FCount) then
    Error(@SListIndexError, aIndex);
  InsertItem(aIndex, aStr, aObject);
end;

procedure TbpStringList.Put(aIndex: Integer; const aStr: string);
var
  lvSlot: Integer;
begin
  CheckNotSorted;
  CheckIndex(aIndex);
  Changing;
  CheckIndex(aIndex);
  lvSlot := FOrder[aIndex];
  if FBuckets <> nil then
    UnlinkValue(lvSlot);
  if FNameBuckets <> nil then
    UnlinkName(lvSlot);
  FSlots[lvSlot].Str := aStr;
  if FBuckets <> nil then
    LinkValue(lvSlot);
  if FNameBuckets <> nil then
    LinkName(lvSlot);
  Changed;
end;

procedure TbpStringList.PutObject(aIndex: Integer; aObject: TObject);
begin
  CheckIndex(aIndex);
  Changing;
  CheckIndex(aIndex);
  FSlots[FOrder[aIndex]].Obj := aObject;
  Changed;
end;

procedure TbpStringList.Delete(aIndex: Integer);
var
  lvSlot: Integer;
begin
  CheckIndex(aIndex);
  Changing;
  CheckIndex(aIndex);
  lvSlot := FOrder[aIndex];
  if FBuckets <> nil then
    UnlinkValue(lvSlot);
  if FNameBuckets <> nil then
    UnlinkName(lvSlot);
  FSlots[lvSlot].Str := '';
  FSlots[lvSlot].Obj := nil;
  FSlots[lvSlot].Next := FFree;
  FFree := lvSlot;
  Dec(FCount);
  if aIndex < FCount then
    System.Move(FOrder[aIndex + 1], FOrder[aIndex], (FCount - aIndex) * SizeOf(Integer));
  if FPosValid > aIndex then
    FPosValid := aIndex;
  Changed;
end;

procedure TbpStringList.Clear;
var
  lvHadRows: Boolean;
begin
  // rows deleted one at a time leave every slot free but the arrays at their peak
  if (FCount = 0) and (FSlotsUsed = 0) then
    Exit;
  lvHadRows := FCount > 0;
  if lvHadRows then
    Changing;
  FSlots := nil;
  FOrder := nil;
  FPos := nil;
  FBuckets := nil;
  FNameBuckets := nil;
  FCount := 0;
  FSlotsUsed := 0;
  FFree := -1;
  FPosValid := 0;
  if lvHadRows then
    Changed;
end;

procedure TbpStringList.Exchange(aIndex1, aIndex2: Integer);
var
  lvSlot: Integer;
begin
  CheckNotSorted;
  CheckIndex(aIndex1);
  CheckIndex(aIndex2);
  Changing;
  CheckIndex(aIndex1);
  CheckIndex(aIndex2);
  lvSlot := FOrder[aIndex1];
  FOrder[aIndex1] := FOrder[aIndex2];
  FOrder[aIndex2] := lvSlot;
  // only a position below the watermark has to be right
  if aIndex1 < FPosValid then
    FPos[FOrder[aIndex1]] := aIndex1;
  if aIndex2 < FPosValid then
    FPos[FOrder[aIndex2]] := aIndex2;
  Changed;
end;

// one rotation of the order array, where TStrings.Move is a Delete plus an Insert
procedure TbpStringList.Move(aCurIndex, aNewIndex: Integer);
var
  lvSlot: Integer;
begin
  CheckNotSorted;
  CheckIndex(aCurIndex);
  CheckIndex(aNewIndex);
  if aCurIndex = aNewIndex then
    Exit;
  Changing;
  CheckIndex(aCurIndex);
  CheckIndex(aNewIndex);
  lvSlot := FOrder[aCurIndex];
  if aCurIndex < aNewIndex then
  begin
    System.Move(FOrder[aCurIndex + 1], FOrder[aCurIndex], (aNewIndex - aCurIndex) * SizeOf(Integer));
    if FPosValid > aCurIndex then
      FPosValid := aCurIndex;
  end
  else
  begin
    System.Move(FOrder[aNewIndex], FOrder[aNewIndex + 1], (aCurIndex - aNewIndex) * SizeOf(Integer));
    if FPosValid > aNewIndex then
      FPosValid := aNewIndex;
  end;
  FOrder[aNewIndex] := lvSlot;
  Changed;
end;

// sorting

// bottom-up merge sort over positions; the callback sees pre-sort ones, nil means ours
procedure TbpStringList.SortOrder(aCompare: TbpStringListSortCompare);
var
  lvSrc, lvDst: array of Integer;
  i, lvWidth, lvLow, lvMid, lvHigh, lvLeft, lvRight, lvOut, lvCmp: Integer;
begin
  if FCount < 2 then
    Exit;
  SetLength(lvSrc, FCount);
  SetLength(lvDst, FCount);
  for i := 0 to FCount - 1 do
    lvSrc[i] := i;
  lvWidth := 1;
  while lvWidth < FCount do
  begin
    lvLow := 0;
    while lvLow < FCount do
    begin
      lvMid := lvLow + lvWidth;
      if lvMid > FCount then
        lvMid := FCount;
      lvHigh := lvMid + lvWidth;
      if lvHigh > FCount then
        lvHigh := FCount;
      lvLeft := lvLow;
      lvRight := lvMid;
      lvOut := lvLow;
      while (lvLeft < lvMid) and (lvRight < lvHigh) do
      begin
        if Assigned(aCompare) then
          lvCmp := aCompare(Self, lvSrc[lvLeft], lvSrc[lvRight])
        else
          lvCmp := CompareSlot(FOrder[lvSrc[lvLeft]], FSlots[FOrder[lvSrc[lvRight]]].Str);
        // the left run wins ties, which is what makes the sort stable
        if lvCmp <= 0 then
        begin
          lvDst[lvOut] := lvSrc[lvLeft];
          Inc(lvLeft);
        end
        else
        begin
          lvDst[lvOut] := lvSrc[lvRight];
          Inc(lvRight);
        end;
        Inc(lvOut);
      end;
      while lvLeft < lvMid do
      begin
        lvDst[lvOut] := lvSrc[lvLeft];
        Inc(lvLeft);
        Inc(lvOut);
      end;
      while lvRight < lvHigh do
      begin
        lvDst[lvOut] := lvSrc[lvRight];
        Inc(lvRight);
        Inc(lvOut);
      end;
      lvLow := lvHigh;
    end;
    // a copy back, not a swap: log n copies of n ints is nothing next to the compares
    System.Move(lvDst[0], lvSrc[0], FCount * SizeOf(Integer));
    lvWidth := lvWidth * 2;
  end;
  for i := 0 to FCount - 1 do
    lvDst[i] := FOrder[lvSrc[i]];
  System.Move(lvDst[0], FOrder[0], FCount * SizeOf(Integer));
  FPosValid := 0;
end;

procedure TbpStringList.Sort;
begin
  if FSorted or (FCount < 2) then
    Exit;
  Changing;
  SortOrder(nil);
  Changed;
end;

procedure TbpStringList.CustomSort(aCompare: TbpStringListSortCompare);
begin
  CheckNotSorted;
  if FCount < 2 then
    Exit;
  Changing;
  SortOrder(aCompare);
  Changed;
end;

procedure TbpStringList.SetSorted(aValue: Boolean);
begin
  if aValue = FSorted then
    Exit;
  if aValue then
    Sort;
  FSorted := aValue;
end;

// the fold changed, so every hash is stale and a sorted order may be too
procedure TbpStringList.SetCaseSensitive(aValue: Boolean);
begin
  if aValue = FCaseSensitive then
    Exit;
  FCaseSensitive := aValue;
  FBuckets := nil;
  FNameBuckets := nil;
  if FSorted and (FCount > 1) then
  begin
    Changing;
    SortOrder(nil);
    Changed;
  end;
end;

// the flags come across too, and a sorted source is re-sorted under our relation
procedure TbpStringList.Assign(aSource: TPersistent);
var
  lvSorted: Boolean;
begin
  lvSorted := False;
  if aSource is TStringList then
  begin
    FSorted := False;
    FCaseSensitive := TStringList(aSource).CaseSensitive;
    FDuplicates := TStringList(aSource).Duplicates;
    lvSorted := TStringList(aSource).Sorted;
  end
  else if aSource is TbpStringList then
  begin
    FSorted := False;
    FCaseSensitive := TbpStringList(aSource).CaseSensitive;
    FDuplicates := TbpStringList(aSource).Duplicates;
    lvSorted := TbpStringList(aSource).Sorted;
  end;
  FBuckets := nil;
  FNameBuckets := nil;
  inherited Assign(aSource);
  if lvSorted then
    Sorted := True;
end;

end.
