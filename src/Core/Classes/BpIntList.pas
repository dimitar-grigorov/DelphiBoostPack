{.$DEFINE BENCHMARK}

unit BpIntList;

// A list of integers that behaves like TStringList: sorting, delimited text, indexing.

interface

uses
  Classes, SysUtils, BpIntListIntf;

type
  TbpIntListDefined = set of (idDelimiter, idLineBreak, idStrictDelimiter);

  TbpIntList = class(TInterfacedObject, IBpIntList)
  private
    {$IFDEF BENCHMARK}
    FStepCount: Integer;
    {$ENDIF}
    FList: array of Integer;
    FDefined: TbpIntListDefined;
    FUpdateCount: Integer;
    FCount: Integer;
    FSorted: Boolean;
    FDelimiter: Char;
    function GetItem(aIndex: Integer): Integer;
    procedure SetItem(aIndex: Integer; const aValue: Integer);
    procedure SetCapacity(const aNewCapacity: Integer);
    procedure ExchangeItems(aIndex1, aIndex2: Integer);
    procedure Grow;
    procedure QuickSort(aL, aR, aDepthBudget: Integer);
    procedure HeapSortRange(aL, aR: Integer);
    function SortedInsertIndex(const aItem: Integer): Integer;
    function GetDelimitedText: string;
    procedure SetDelimitedText(const aValue: string);
    function GetDelimiter: Char;
    procedure SetDelimiter(const aValue: Char);
    function GetCount: Integer;
    function GetCommaText: string;
    procedure SetCommaText(const aValue: string);
    procedure SetSorted(const aValue: Boolean);
  protected
    property UpdateCount: Integer read FUpdateCount;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const aItem: Integer): Integer;
    procedure Delete(const aIndex: Integer);
    procedure Clear;
    procedure Exchange(aIndex1, aIndex2: Integer); virtual;
    function IndexOf(const aItem: Integer): Integer;
    function BinarySearch(const aItem: Integer; out aFoundIndex: Integer): Boolean;
    procedure Insert(aIndex: Integer; const aItem: Integer);
    procedure Sort; virtual;

    procedure LoadFromFile(const aFileName: string); virtual;
    procedure LoadFromStream(aStream: TStream); virtual;
    procedure SaveToFile(const aFileName: string); virtual;
    procedure SaveToStream(aStream: TStream); virtual;
    class function CompareInt(aI1, aI2: Integer): Integer;
  public
    property Items[aIndex: Integer]: Integer read GetItem write SetItem; default;
    property CommaText: string read GetCommaText write SetCommaText;
    property Count: Integer read GetCount;
    property Delimiter: Char read GetDelimiter write SetDelimiter;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
    property Sorted: Boolean read FSorted write SetSorted;

    {$IFDEF BENCHMARK}
    property StepCount: Integer read FStepCount;
    {$ENDIF}
  end;

{$IFNDEF NEXTGEN}
  TIntegerList = class(TbpIntList)
  end;
  TIntList = class(TbpIntList)
  end;
{$ENDIF}

implementation

{$IF not Declared(CharInSet)}
// Delphi 2007 and earlier lack CharInSet; there Char is single-byte, so a plain set test suffices.
function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;
{$IFEND}

resourcestring
  SListCapacityError = 'List capacity out of bounds (%d)';
  SListCountError = 'List count out of bounds (%d)';
  SListIndexError = 'List index out of bounds (%d)';
  SListMustBeSortedForBinarySearch = 'List must be sorted before performing binary search';

constructor TbpIntList.Create;
begin
  inherited;
  FCount := 0;
  FSorted := False;
  SetCapacity(0);
end;

destructor TbpIntList.Destroy;
begin
  inherited Destroy;
  FCount := 0;
  SetCapacity(0);
end;

function TbpIntList.GetItem(aIndex: Integer): Integer;
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EListError.Create('List index out of bounds');
  Result := FList[aIndex];
end;

procedure TbpIntList.SetItem(aIndex: Integer; const aValue: Integer);
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EListError.Create('List index out of bounds');
  FList[aIndex] := aValue;
end;

procedure TbpIntList.SetSorted(const aValue: Boolean);
begin
  if FSorted <> aValue then
  begin
    if aValue then
      Sort;
    FSorted := aValue;
  end;
end;

procedure TbpIntList.SetCapacity(const aNewCapacity: Integer);
begin
  if aNewCapacity < FCount then
    FCount := aNewCapacity; // Reduce count if reducing capacity below count
  if aNewCapacity <> Length(FList) then
    SetLength(FList, aNewCapacity);
end;

procedure TbpIntList.Exchange(aIndex1, aIndex2: Integer);
begin
  if (aIndex1 < 0) or (aIndex1 >= FCount) then
    raise EListError.CreateFmt(SListIndexError, [aIndex1]);
  if (aIndex2 < 0) or (aIndex2 >= FCount) then
    raise EListError.CreateFmt(SListIndexError, [aIndex2]);
  ExchangeItems(aIndex1, aIndex2);
end;

procedure TbpIntList.ExchangeItems(aIndex1, aIndex2: Integer);
var
  lvTemp: Integer;
begin
  lvTemp := FList[aIndex1];
  FList[aIndex1] := FList[aIndex2];
  FList[aIndex2] := lvTemp;
end;

procedure TbpIntList.Grow;
var
  lvNewCapacity: Integer;
begin
  if Length(FList) > 64 then
    lvNewCapacity := Length(FList) + (Length(FList) div 4)
  else if Length(FList) > 8 then
    lvNewCapacity := Length(FList) + 16
  else
    lvNewCapacity := Length(FList) + 4;
  SetCapacity(lvNewCapacity);
end;

// sifts the subtree rooted at aRoot, indices relative to aL
procedure TbpIntList.HeapSortRange(aL, aR: Integer);
var
  lvCount, lvIdx, lvRoot, lvChild, lvSwap: Integer;
begin
  lvCount := aR - aL + 1;
  for lvIdx := (lvCount - 2) div 2 downto 0 do
  begin
    lvRoot := lvIdx;
    while (lvRoot * 2 + 1) <= lvCount - 1 do
    begin
      lvChild := lvRoot * 2 + 1;
      lvSwap := lvRoot;
      if FList[aL + lvSwap] < FList[aL + lvChild] then
        lvSwap := lvChild;
      if (lvChild + 1 <= lvCount - 1) and (FList[aL + lvSwap] < FList[aL + lvChild + 1]) then
        lvSwap := lvChild + 1;
      if lvSwap = lvRoot then
        Break;
      ExchangeItems(aL + lvRoot, aL + lvSwap);
      lvRoot := lvSwap;
    end;
  end;
  for lvIdx := lvCount - 1 downto 1 do
  begin
    ExchangeItems(aL, aL + lvIdx);
    lvRoot := 0;
    while (lvRoot * 2 + 1) <= lvIdx - 1 do
    begin
      lvChild := lvRoot * 2 + 1;
      lvSwap := lvRoot;
      if FList[aL + lvSwap] < FList[aL + lvChild] then
        lvSwap := lvChild;
      if (lvChild + 1 <= lvIdx - 1) and (FList[aL + lvSwap] < FList[aL + lvChild + 1]) then
        lvSwap := lvChild + 1;
      if lvSwap = lvRoot then
        Break;
      ExchangeItems(aL + lvRoot, aL + lvSwap);
      lvRoot := lvSwap;
    end;
  end;
end;

// introsort: recurses into the smaller side, heapsort when the pivot splits badly
procedure TbpIntList.QuickSort(aL, aR, aDepthBudget: Integer);
var
  I, J, lvMid: Integer;
  lvPivot: Integer;
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
      ExchangeItems(lvMid, aL);
    if FList[aR] < FList[aL] then
      ExchangeItems(aR, aL);
    if FList[aR] < FList[lvMid] then
      ExchangeItems(aR, lvMid);
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
          ExchangeItems(I, J);
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

function TbpIntList.Add(const aItem: Integer): Integer;
begin
  // on a sorted list the item lands at its ordered position, not at the end
  if FSorted then
    Result := SortedInsertIndex(aItem)
  else
    Result := FCount;
  Insert(Result, aItem);
end;

// lowest index at which aItem keeps the list ordered
function TbpIntList.SortedInsertIndex(const aItem: Integer): Integer;
var
  lvLow, lvHigh, lvMid: Integer;
begin
  lvLow := 0;
  lvHigh := FCount - 1;
  while lvLow <= lvHigh do
  begin
    lvMid := lvLow + (lvHigh - lvLow) div 2;
    if FList[lvMid] < aItem then
      lvLow := lvMid + 1
    else
      lvHigh := lvMid - 1;
  end;
  Result := lvLow;
end;

procedure TbpIntList.Delete(const aIndex: Integer);
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EListError.Create('List index out of bounds');
  Dec(FCount);
  if (aIndex < FCount) then
    System.Move(FList[aIndex + 1], FList[aIndex], (FCount - aIndex) * SizeOf(Integer));
end;

procedure TbpIntList.Clear;
begin
  if FCount <> 0 then
  begin
    FCount := 0;
    SetCapacity(0);
  end;
end;

function TbpIntList.GetDelimiter: Char;
begin
  if not (idDelimiter in FDefined) then
    Delimiter := ',';
  Result := FDelimiter;
end;

procedure TbpIntList.SetDelimiter(const aValue: Char);
begin
  if (FDelimiter <> aValue) or not (idDelimiter in FDefined) then
  begin
    Include(FDefined, idDelimiter);
    FDelimiter := aValue;
  end
end;

function TbpIntList.GetCommaText: string;
var
  lvOldDefined: TbpIntListDefined;
  lvOldDelimiter: Char;
begin
  lvOldDefined := FDefined;
  lvOldDelimiter := Delimiter;
  Delimiter := ',';
  try
    Result := GetDelimitedText;
  finally
    Delimiter := lvOldDelimiter;
    FDefined := lvOldDefined;
  end;
end;

procedure TbpIntList.SetCommaText(const aValue: string);
begin
  Delimiter := ',';
  SetDelimitedText(aValue);
end;

function TbpIntList.GetCount: Integer;
begin
  Result := FCount;
end;

function TbpIntList.GetDelimitedText: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to Count - 1 do
  begin
    Result := Result + IntToStr(FList[i]);
    if i < Count - 1 then
      Result := Result + Delimiter;
  end;
end;

procedure TbpIntList.SetDelimitedText(const aValue: string);
var
  P, lvStart: PChar;
  lvS: string;
  lvNum: Integer;
begin
  Clear;
  P := PChar(aValue);
  while P^ <> #0 do
  begin
    lvStart := P;
    while (P^ <> #0) and (P^ <> Delimiter) and not CharInSet(P^, [#10, #13]) do
      Inc(P);

    SetString(lvS, lvStart, P - lvStart);
    if lvS <> '' then
    begin
      if TryStrToInt(lvS, lvNum) then
        Add(lvNum)
      else
        raise EConvertError.CreateFmt('Cannot convert string "%s" to integer', [lvS]);
    end;

    while (P^ = Delimiter) or CharInSet(P^, [#10, #13, ' ']) do
      Inc(P);
  end;
end;


procedure TbpIntList.LoadFromFile(const aFileName: string);
var
  lvFileStream: TFileStream;
begin
  lvFileStream := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(lvFileStream);
  finally
    lvFileStream.Free;
  end;
end;

procedure TbpIntList.LoadFromStream(aStream: TStream);
var
  lvS: string;
  lvBuffer: array of Byte;
begin
  Clear;
  if aStream.Size = 0 then
    Exit;
  SetLength(lvBuffer, aStream.Size);
  aStream.Position := 0;
  aStream.ReadBuffer(lvBuffer[0], aStream.Size);
  SetString(lvS, PAnsiChar(@lvBuffer[0]), Length(lvBuffer));
  SetDelimitedText(lvS);
end;

procedure TbpIntList.SaveToFile(const aFileName: string);
var
  lvFileStream: TFileStream;
begin
  lvFileStream := TFileStream.Create(aFileName, fmCreate);
  try
    SaveToStream(lvFileStream);
  finally
    lvFileStream.Free;
  end;
end;

procedure TbpIntList.SaveToStream(aStream: TStream);
var
  lvText: AnsiString;
begin
  // AnsiString, so Length counts bytes on Unicode compilers too
  lvText := AnsiString(GetDelimitedText);
  if Length(lvText) > 0 then
    aStream.WriteBuffer(lvText[1], Length(lvText));
end;

function TbpIntList.IndexOf(const aItem: Integer): Integer;
var
  lvFound: Boolean;
  lvFoundIndex: Integer;
begin
  Result := -1;
  {$IFDEF BENCHMARK}
  FStepCount := 0;
  {$ENDIF}
  if Sorted then
  begin
    lvFound := BinarySearch(aItem, lvFoundIndex);
    if lvFound then
      Result := lvFoundIndex
    else
      Result := -1;
  end
  else
  begin
    for lvFoundIndex := 0 to FCount - 1 do
    begin
      {$IFDEF BENCHMARK}
      Inc(FStepCount);
      {$ENDIF}
      if (FList[lvFoundIndex] = aItem) then
      begin
        Result := lvFoundIndex;
        Break;
      end;
    end;
  end;
end;

function TbpIntList.BinarySearch(const aItem: Integer; out aFoundIndex: Integer): Boolean;
var
  L, H, M: Integer;
  lvCompResult: Integer;
begin
  aFoundIndex := -1;
  if not Sorted then
    raise EListError.Create(SListMustBeSortedForBinarySearch);

  L := 0;
  H := FCount - 1;
  {$IFDEF BENCHMARK}
  FStepCount := 0;
  {$ENDIF}
  while L <= H do
  begin
    M := (L + H) shr 1;
    {$IFDEF BENCHMARK}
    Inc(FStepCount);
    {$ENDIF}
    lvCompResult := CompareInt(FList[M], aItem);
    if lvCompResult < 0 then
      L := M + 1
    else if lvCompResult > 0 then
      H := M - 1
    else
    begin
      aFoundIndex := M;
      Result := True;
      Exit;
    end;
  end;
  aFoundIndex := L; // Return the insertion point if not found
  Result := False;
end;

class function TbpIntList.CompareInt(aI1, aI2: Integer): Integer;
begin
  if aI1 < aI2 then
    Result := -1
  else if aI1 > aI2 then
    Result := 1
  else
    Result := 0;
end;

procedure TbpIntList.Insert(aIndex: Integer; const aItem: Integer);
begin
  if (aIndex < 0) or (aIndex > Count) then
    raise EListError.Create('List index out of bounds');

  if FSorted then
    aIndex := SortedInsertIndex(aItem);

  if Count = Length(FList) then
    Grow;

  if aIndex < Count then
    System.Move(FList[aIndex], FList[aIndex + 1], (Count - aIndex) * SizeOf(Integer));

  FList[aIndex] := aItem;
  Inc(FCount);
end;

procedure TbpIntList.Sort;
var
  lvBudget, lvSpan: Integer;
begin
  if Sorted or (FCount <= 1) then
    Exit;
  lvBudget := 0;
  lvSpan := FCount;
  while lvSpan > 1 do
  begin
    lvSpan := lvSpan shr 1;
    Inc(lvBudget);
  end;
  QuickSort(0, FCount - 1, lvBudget * 2);
end;

end.

