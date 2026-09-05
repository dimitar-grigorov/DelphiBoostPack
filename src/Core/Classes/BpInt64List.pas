unit BpInt64List;

// TbpIntList with an Int64 element: O(1) IndexOf off a hash index that is built
// on the first lookup, kept across an append and dropped by any mutation that
// moves a position. The values stay dense in one array, so reading Items[] is a
// single memory access and a sort is in place, and a Sorted list builds no index
// at all because it bisects instead.

interface

uses
  SysUtils, Classes;

type
  TbpInt64List = class
  private
    FList: array of Int64;
    FCount: Integer;
    FBuckets: array of Integer;   // chain heads, nil until the first IndexOf
    FNext: array of Integer;      // next position in the chain, by position
    FSorted: Boolean;
    FDuplicates: TDuplicates;
    FDelimiter: Char;
    function GetItem(aIndex: Integer): Int64;
    procedure SetItem(aIndex: Integer; aValue: Int64);
    function GetCapacity: Integer;
    procedure SetCapacity(aValue: Integer);
    procedure SetSorted(aValue: Boolean);
    procedure Grow;
    procedure BuildIndex;
    procedure LinkAppend(aPos: Integer);
    procedure CheckIndex(aIndex: Integer);
    procedure CheckNotSorted;
    procedure InsertItem(aIndex: Integer; aItem: Int64);
    procedure Swap(aIndex1, aIndex2: Integer);
    procedure QuickSort(aL, aR, aDepthBudget: Integer);
    procedure HeapSortRange(aL, aR: Integer);
    procedure SiftDown(aL, aRoot, aLast: Integer);
    function TextWith(aDelimiter: Char): string;
    procedure ParseWith(const aText: string; aDelimiter: Char);
    function GetDelimitedText: string;
    procedure SetDelimitedText(const aValue: string);
    function GetCommaText: string;
    procedure SetCommaText(const aValue: string);
  public
    constructor Create;
    function Add(aItem: Int64): Integer;
    procedure Assign(aSource: TbpInt64List);
    procedure Clear;
    procedure Delete(aIndex: Integer);
    procedure Exchange(aIndex1, aIndex2: Integer);
    // Sorted: a binary search, aIndex the insertion point on a miss. First equal item.
    function Find(aItem: Int64; var aIndex: Integer): Boolean;
    function IndexOf(aItem: Int64): Integer;
    procedure Insert(aIndex: Integer; aItem: Int64);
    // content equality; Equals is left alone, it means identity from Delphi 2009 on
    function SameAs(aOther: TbpInt64List): Boolean;
    procedure Sort;
    procedure LoadFromFile(const aFileName: string);
    procedure LoadFromStream(aStream: TStream);
    procedure SaveToFile(const aFileName: string);
    procedure SaveToStream(aStream: TStream);
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Count: Integer read FCount;
    property Items[aIndex: Integer]: Int64 read GetItem write SetItem; default;
    property CommaText: string read GetCommaText write SetCommaText;
    // whitespace separates too, so a space or line separated file loads as it is
    property Delimiter: Char read FDelimiter write FDelimiter;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
    // consulted by Add on a Sorted list only, as in TStringList
    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
    property Sorted: Boolean read FSorted write SetSorted;
  end;

implementation

uses
  RTLConsts;

const
  gcBpMinBuckets = 16;
  gcBpMinCapacity = 16;

resourcestring
  SBpDuplicateItem = 'List does not allow duplicates';
  SBpNotSingleByteText = 'The stream is not single byte text: a NUL byte at offset %d';

// Thomas Wang hash64shift; the masks guard shr sign-fill on older compilers
{$IFOPT Q+}{$DEFINE BPINT64LIST_Q}{$Q-}{$ENDIF}
function Int64ListHash(aItem: Int64): Cardinal;
begin
  aItem := (not aItem) + (aItem shl 18);
  aItem := aItem xor ((aItem shr 31) and $00000001FFFFFFFF);
  aItem := aItem * 21;
  aItem := aItem xor ((aItem shr 11) and $001FFFFFFFFFFFFF);
  aItem := aItem + (aItem shl 6);
  aItem := aItem xor ((aItem shr 22) and $000003FFFFFFFFFF);
  Result := Cardinal(aItem);
end;
{$IFDEF BPINT64LIST_Q}{$Q+}{$UNDEF BPINT64LIST_Q}{$ENDIF}

function Int64ListIsSep(aCh: Char): Boolean;
begin
  Result := (aCh = ' ') or (aCh = #9) or (aCh = #10) or (aCh = #13);
end;

// storage

constructor TbpInt64List.Create;
begin
  inherited Create;
  FDelimiter := ',';
end;

function TbpInt64List.GetCapacity: Integer;
begin
  Result := Length(FList);
end;

procedure TbpInt64List.SetCapacity(aValue: Integer);
begin
  // shrinking below Count would drop values without saying so
  if aValue < FCount then
    raise EListError.CreateFmt(SListCapacityError, [aValue]);
  SetLength(FList, aValue);
  if FBuckets <> nil then
    SetLength(FNext, aValue);
end;

procedure TbpInt64List.Grow;
var
  lvCapacity: Integer;
begin
  lvCapacity := Length(FList);
  if lvCapacity < gcBpMinCapacity then
    lvCapacity := gcBpMinCapacity
  else
    lvCapacity := lvCapacity + lvCapacity div 2;
  SetCapacity(lvCapacity);
end;

procedure TbpInt64List.CheckIndex(aIndex: Integer);
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EListError.CreateFmt(SListIndexError, [aIndex]);
end;

procedure TbpInt64List.CheckNotSorted;
begin
  if FSorted then
    raise EListError.CreateFmt(SSortedListError, [0]);
end;

function TbpInt64List.GetItem(aIndex: Integer): Int64;
begin
  CheckIndex(aIndex);
  Result := FList[aIndex];
end;

// an unchecked write would leave the binary search on unordered data
procedure TbpInt64List.SetItem(aIndex: Integer; aValue: Int64);
begin
  CheckNotSorted;
  CheckIndex(aIndex);
  FList[aIndex] := aValue;
  FBuckets := nil;
end;

// the index

procedure TbpInt64List.BuildIndex;
var
  i, lvBuckets, lvBucket: Integer;
begin
  lvBuckets := gcBpMinBuckets;
  while lvBuckets * 3 div 4 < FCount do
    lvBuckets := lvBuckets * 2;
  SetLength(FBuckets, lvBuckets);
  for i := 0 to lvBuckets - 1 do
    FBuckets[i] := -1;
  SetLength(FNext, Length(FList));
  for i := 0 to FCount - 1 do
  begin
    lvBucket := Integer(Int64ListHash(FList[i]) and Cardinal(lvBuckets - 1));
    FNext[i] := FBuckets[lvBucket];
    FBuckets[lvBucket] := i;
  end;
end;

// only an append can keep the index: every other move renumbers positions
procedure TbpInt64List.LinkAppend(aPos: Integer);
var
  lvBucket: Integer;
begin
  if FCount > Length(FBuckets) * 3 div 4 then
  begin
    // a whole rebuild on the next lookup, amortised away by geometric growth
    FBuckets := nil;
    Exit;
  end;
  lvBucket := Integer(Int64ListHash(FList[aPos]) and Cardinal(Length(FBuckets) - 1));
  FNext[aPos] := FBuckets[lvBucket];
  FBuckets[lvBucket] := aPos;
end;

// lookups

function TbpInt64List.IndexOf(aItem: Int64): Integer;
var
  lvPos: Integer;
begin
  if FSorted then
  begin
    if not Find(aItem, Result) then
      Result := -1;
    Exit;
  end;
  Result := -1;
  if FCount = 0 then
    Exit;
  if FBuckets = nil then
    BuildIndex;
  lvPos := FBuckets[Integer(Int64ListHash(aItem) and Cardinal(Length(FBuckets) - 1))];
  // the whole chain, because the answer is the lowest position among duplicates
  while lvPos >= 0 do
  begin
    if (FList[lvPos] = aItem) and ((Result < 0) or (lvPos < Result)) then
      Result := lvPos;
    lvPos := FNext[lvPos];
  end;
end;

function TbpInt64List.Find(aItem: Int64; var aIndex: Integer): Boolean;
var
  lvLow, lvHigh, lvMid: Integer;
begin
  if not FSorted then
  begin
    aIndex := IndexOf(aItem);
    Result := aIndex >= 0;
    if not Result then
      aIndex := FCount;
    Exit;
  end;
  Result := False;
  lvLow := 0;
  lvHigh := FCount - 1;
  // keeps bisecting on a hit, so aIndex lands on the first equal item
  while lvLow <= lvHigh do
  begin
    lvMid := (lvLow + lvHigh) shr 1;
    if FList[lvMid] < aItem then
      lvLow := lvMid + 1
    else
    begin
      lvHigh := lvMid - 1;
      if FList[lvMid] = aItem then
        Result := True;
    end;
  end;
  aIndex := lvLow;
end;

// mutation

procedure TbpInt64List.InsertItem(aIndex: Integer; aItem: Int64);
begin
  if FCount = Length(FList) then
    Grow;
  if aIndex < FCount then
  begin
    System.Move(FList[aIndex], FList[aIndex + 1], (FCount - aIndex) * SizeOf(Int64));
    FBuckets := nil;
  end;
  FList[aIndex] := aItem;
  Inc(FCount);
  if FBuckets <> nil then
    LinkAppend(aIndex);   // only an append gets here, the branch above dropped the rest
end;

function TbpInt64List.Add(aItem: Int64): Integer;
begin
  if FSorted then
  begin
    if Find(aItem, Result) then
    begin
      case FDuplicates of
        dupIgnore: Exit;
        dupError: raise EListError.Create(SBpDuplicateItem);
      end;
      // past the equal run, so equal values stay in insertion order
      while (Result < FCount) and (FList[Result] = aItem) do
        Inc(Result);
    end;
  end
  else
    Result := FCount;
  InsertItem(Result, aItem);
end;

procedure TbpInt64List.Insert(aIndex: Integer; aItem: Int64);
begin
  CheckNotSorted;
  if (aIndex < 0) or (aIndex > FCount) then
    raise EListError.CreateFmt(SListIndexError, [aIndex]);
  InsertItem(aIndex, aItem);
end;

procedure TbpInt64List.Delete(aIndex: Integer);
begin
  CheckIndex(aIndex);
  Dec(FCount);
  if aIndex < FCount then
    System.Move(FList[aIndex + 1], FList[aIndex], (FCount - aIndex) * SizeOf(Int64));
  FBuckets := nil;
end;

procedure TbpInt64List.Clear;
begin
  FList := nil;
  FBuckets := nil;
  FNext := nil;
  FCount := 0;
end;

procedure TbpInt64List.Exchange(aIndex1, aIndex2: Integer);
var
  lvTemp: Integer;
begin
  CheckNotSorted;
  CheckIndex(aIndex1);
  CheckIndex(aIndex2);
  lvTemp := FList[aIndex1];
  FList[aIndex1] := FList[aIndex2];
  FList[aIndex2] := lvTemp;
  FBuckets := nil;
end;

procedure TbpInt64List.Assign(aSource: TbpInt64List);
begin
  if aSource = Self then
    Exit;
  Clear;
  FCount := aSource.FCount;
  SetLength(FList, FCount);
  if FCount > 0 then
    System.Move(aSource.FList[0], FList[0], FCount * SizeOf(Int64));
  FDelimiter := aSource.FDelimiter;
  FDuplicates := aSource.FDuplicates;
  FSorted := aSource.FSorted;
end;

function TbpInt64List.SameAs(aOther: TbpInt64List): Boolean;
begin
  Result := (aOther <> nil) and (aOther.FCount = FCount) and
    ((FCount = 0) or CompareMem(@FList[0], @aOther.FList[0], FCount * SizeOf(Int64)));
end;

// sorting

procedure TbpInt64List.Swap(aIndex1, aIndex2: Integer);
var
  lvTemp: Int64;
begin
  lvTemp := FList[aIndex1];
  FList[aIndex1] := FList[aIndex2];
  FList[aIndex2] := lvTemp;
end;

// sifts aRoot down to aLast, both relative to aL
procedure TbpInt64List.SiftDown(aL, aRoot, aLast: Integer);
var
  lvChild, lvSwap: Integer;
begin
  while (aRoot * 2 + 1) <= aLast do
  begin
    lvChild := aRoot * 2 + 1;
    lvSwap := aRoot;
    if FList[aL + lvSwap] < FList[aL + lvChild] then
      lvSwap := lvChild;
    if (lvChild + 1 <= aLast) and (FList[aL + lvSwap] < FList[aL + lvChild + 1]) then
      lvSwap := lvChild + 1;
    if lvSwap = aRoot then
      Exit;
    Swap(aL + aRoot, aL + lvSwap);
    aRoot := lvSwap;
  end;
end;

procedure TbpInt64List.HeapSortRange(aL, aR: Integer);
var
  lvCount, lvIdx: Integer;
begin
  lvCount := aR - aL + 1;
  for lvIdx := (lvCount - 2) div 2 downto 0 do
    SiftDown(aL, lvIdx, lvCount - 1);
  for lvIdx := lvCount - 1 downto 1 do
  begin
    Swap(aL, aL + lvIdx);
    SiftDown(aL, 0, lvIdx - 1);
  end;
end;

// introsort: recurses into the smaller side, heapsort when the pivot splits badly
procedure TbpInt64List.QuickSort(aL, aR, aDepthBudget: Integer);
var
  I, J, lvMid: Integer;
  lvPivot: Int64;
begin
  while aL < aR do
  begin
    if aDepthBudget <= 0 then
    begin
      HeapSortRange(aL, aR);
      Exit;
    end;
    Dec(aDepthBudget);
    lvMid := aL + (aR - aL) div 2;
    // median of three, so sorted and reverse sorted input split evenly
    if FList[lvMid] < FList[aL] then
      Swap(lvMid, aL);
    if FList[aR] < FList[aL] then
      Swap(aR, aL);
    if FList[aR] < FList[lvMid] then
      Swap(aR, lvMid);
    lvPivot := FList[lvMid];
    I := aL;
    J := aR;
    repeat
      while FList[I] < lvPivot do
        Inc(I);
      while FList[J] > lvPivot do
        Dec(J);
      if I <= J then
      begin
        if I <> J then
          Swap(I, J);
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if (J - aL) < (aR - I) then
    begin
      if aL < J then
        QuickSort(aL, J, aDepthBudget);
      aL := I;
    end
    else
    begin
      if I < aR then
        QuickSort(I, aR, aDepthBudget);
      aR := J;
    end;
  end;
end;

procedure TbpInt64List.Sort;
var
  lvBudget, lvSpan: Integer;
begin
  if FSorted or (FCount < 2) then
    Exit;
  // 2*log2(Count) partitions before heapsort takes over
  lvBudget := 0;
  lvSpan := FCount;
  while lvSpan > 1 do
  begin
    lvSpan := lvSpan shr 1;
    Inc(lvBudget);
  end;
  QuickSort(0, FCount - 1, lvBudget * 2);
  FBuckets := nil;
end;

procedure TbpInt64List.SetSorted(aValue: Boolean);
begin
  if aValue = FSorted then
    Exit;
  if aValue then
    Sort;
  FSorted := aValue;
end;

// text

function TbpInt64List.TextWith(aDelimiter: Char): string;
var
  i, lvLen: Integer;
  lvPart: string;
  lvOut: PChar;
begin
  Result := '';
  if FCount = 0 then
    Exit;
  // one pass to size, one to fill: no reallocation per item
  lvLen := FCount - 1;
  for i := 0 to FCount - 1 do
    Inc(lvLen, Length(IntToStr(FList[i])));
  SetLength(Result, lvLen);
  lvOut := PChar(Result);
  for i := 0 to FCount - 1 do
  begin
    if i > 0 then
    begin
      lvOut^ := aDelimiter;
      Inc(lvOut);
    end;
    lvPart := IntToStr(FList[i]);
    System.Move(PChar(lvPart)^, lvOut^, Length(lvPart) * SizeOf(Char));
    Inc(lvOut, Length(lvPart));
  end;
end;

procedure TbpInt64List.ParseWith(const aText: string; aDelimiter: Char);
var
  P, lvStart: PChar;
  lvPart: string;
  lvNum: Int64;
begin
  Clear;
  P := PChar(aText);
  while P^ <> #0 do
  begin
    lvStart := P;
    while (P^ <> #0) and (P^ <> aDelimiter) and not Int64ListIsSep(P^) do
      Inc(P);
    SetString(lvPart, lvStart, P - lvStart);
    if lvPart <> '' then
    begin
      if not TryStrToInt64(lvPart, lvNum) then
        raise EConvertError.CreateFmt('Cannot convert string "%s" to Int64', [lvPart]);
      Add(lvNum);
    end;
    while (P^ = aDelimiter) or Int64ListIsSep(P^) do
      Inc(P);
  end;
end;

function TbpInt64List.GetDelimitedText: string;
begin
  Result := TextWith(FDelimiter);
end;

procedure TbpInt64List.SetDelimitedText(const aValue: string);
begin
  ParseWith(aValue, FDelimiter);
end;

function TbpInt64List.GetCommaText: string;
begin
  Result := TextWith(',');
end;

procedure TbpInt64List.SetCommaText(const aValue: string);
begin
  ParseWith(aValue, ',');
end;

// streams

procedure TbpInt64List.LoadFromFile(const aFileName: string);
var
  lvStream: TFileStream;
begin
  lvStream := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(lvStream);
  finally
    lvStream.Free;
  end;
end;

// single byte text from the current position, the way TStrings reads a stream
procedure TbpInt64List.LoadFromStream(aStream: TStream);
var
  lvText: AnsiString;
  lvSize, lvFrom, i: Integer;
begin
  Clear;
  lvSize := aStream.Size - aStream.Position;
  if lvSize <= 0 then
    Exit;
  SetLength(lvText, lvSize);
  aStream.ReadBuffer(lvText[1], lvSize);
  lvFrom := 1;
  // a UTF-8 BOM would otherwise reach TryStrToInt as part of the first number
  if (lvSize >= 3) and (Ord(lvText[1]) = $EF) and (Ord(lvText[2]) = $BB) and
    (Ord(lvText[3]) = $BF) then
    lvFrom := 4;
  // and a NUL would end the parse in silence, which is what UTF-16 looks like here
  for i := lvFrom to lvSize do
    if Ord(lvText[i]) = 0 then
      raise EConvertError.CreateFmt(SBpNotSingleByteText, [i - 1]);
  ParseWith(string(Copy(lvText, lvFrom, lvSize - lvFrom + 1)), FDelimiter);
end;

procedure TbpInt64List.SaveToFile(const aFileName: string);
var
  lvStream: TFileStream;
begin
  lvStream := TFileStream.Create(aFileName, fmCreate);
  try
    SaveToStream(lvStream);
  finally
    lvStream.Free;
  end;
end;

procedure TbpInt64List.SaveToStream(aStream: TStream);
var
  lvText: AnsiString;
begin
  // AnsiString, so Length counts bytes on Unicode compilers too
  lvText := AnsiString(GetDelimitedText);
  if Length(lvText) > 0 then
    aStream.WriteBuffer(lvText[1], Length(lvText));
end;

end.
