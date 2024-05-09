{.$DEFINE BENCHMARK}

unit BpIntListUnit;

interface

uses
  Classes, SysUtils, IBpIntListUnit;

type
  TbpIntListDefined = set of (idDelimiter, idLineBreak, idStrictDelimiter);

  TBpIntList = class(TInterfacedObject, IBpIntList)
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
    function GetItem(Index: Integer): Integer;
    procedure SetItem(Index: Integer; const Value: Integer);
    procedure SetCapacity(const NewCapacity: Integer);
    procedure ExchangeItems(Index1, Index2: Integer);
    procedure Grow;
    procedure QuickSort(L, R: Integer);
    function GetDelimitedText: string;
    procedure SetDelimitedText(const Value: string);
    function GetDelimiter: Char;
    procedure SetDelimiter(const Value: Char);
    function GetCount: Integer;
    function GetCommaText: string;
    procedure SetCommaText(const Value: string);
    procedure SetSorted(const Value: Boolean);
  protected
    property UpdateCount: Integer read FUpdateCount;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const Item: Integer): Integer;
    procedure Delete(const Index: Integer);
    procedure Clear;
    procedure Exchange(Index1, Index2: Integer); virtual;
    function IndexOf(const Item: Integer): Integer;
    function BinarySearch(const Item: Integer; out FoundIndex: Integer): Boolean;    
    procedure Insert(Index: Integer; const Item: Integer);
    procedure Sort; virtual;

    procedure LoadFromFile(const FileName: string); virtual;
    procedure LoadFromStream(Stream: TStream); virtual;
    procedure SaveToFile(const FileName: string); virtual;
    procedure SaveToStream(Stream: TStream); virtual;
    class function CompareInt(I1, I2: Integer): Integer;    
  public
    property Items[Index: Integer]: Integer read GetItem write SetItem; default;
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
  TIntegerList = class(TBpIntList)
  end;
  TIntList = class(TBpIntList)
  end;
{$ENDIF}

implementation

resourcestring
  SListCapacityError = 'List capacity out of bounds (%d)';
  SListCountError = 'List count out of bounds (%d)';
  SListIndexError = 'List index out of bounds (%d)';
  SListMustBeSortedForBinarySearch = 'List must be sorted before performing binary search';

constructor TBpIntList.Create;
begin
  inherited;
  FCount := 0;
  FSorted := False;
  SetCapacity(0);
end;

destructor TBpIntList.Destroy;
begin
  inherited Destroy;
  FCount := 0;
  SetCapacity(0);
end;

function TBpIntList.GetItem(Index: Integer): Integer;
begin
  if (Index < 0) or (Index >= FCount) then
    raise EListError.Create('List index out of bounds');
  Result := FList[Index];
end;

procedure TBpIntList.SetItem(Index: Integer; const Value: Integer);
begin
  if (Index < 0) or (Index >= FCount) then
    raise EListError.Create('List index out of bounds');
  FList[Index] := Value;
end;

procedure TBpIntList.SetSorted(const Value: Boolean);
begin
  if FSorted <> Value then
  begin
    if Value then
      Sort;
    FSorted := Value;
  end;
end;

procedure TBpIntList.SetCapacity(const NewCapacity: Integer);
begin
  if NewCapacity < FCount then
    FCount := NewCapacity; // Reduce count if reducing capacity below count
  if NewCapacity <> Length(FList) then
    SetLength(FList, NewCapacity);
end;

procedure TBpIntList.Exchange(Index1, Index2: Integer);
begin
  if (Index1 < 0) or (Index1 >= FCount) then
    raise EListError.CreateFmt(SListIndexError, [Index1]);
  if (Index2 < 0) or (Index2 >= FCount) then
    raise EListError.CreateFmt(SListIndexError, [Index2]);
  ExchangeItems(Index1, Index2);
end;

procedure TBpIntList.ExchangeItems(Index1, Index2: Integer);
var
  Temp: Integer;
begin
  Temp := FList[Index1];
  FList[Index1] := FList[Index2];
  FList[Index2] := Temp;
end;

procedure TBpIntList.Grow;
var
  NewCapacity: Integer;
begin
  if Length(FList) > 64 then
    NewCapacity := Length(FList) + (Length(FList) div 4)
  else if Length(FList) > 8 then
    NewCapacity := Length(FList) + 16
  else
    NewCapacity := Length(FList) + 4;
  SetCapacity(NewCapacity);
end;

procedure TBpIntList.QuickSort(L, R: Integer);
var
  I, J, Pivot: Integer;
begin
  if L < R then
  begin
    Pivot := FList[(L + R) div 2]; // Choose the pivot element
    I := L;
    J := R;
    repeat
      while FList[I] < Pivot do
        Inc(I);
      while FList[J] > Pivot do
        Dec(J);
      if I <= J then
      begin
        // Swap elements
        ExchangeItems(I, J);
        Inc(I);
        Dec(J);
      end;
    until I > J;
    // Recursively sort the partitions
    QuickSort(L, J);
    QuickSort(I, R);
  end;
end;

function TBpIntList.Add(const Item: Integer): Integer;
begin
  Result := GetCount;
  Insert(Result, Item);
end;

procedure TBpIntList.Delete(const Index: Integer);
begin
  if (Index < 0) or (Index >= FCount) then
    raise EListError.Create('List index out of bounds');
  Dec(FCount);
  if (Index < FCount) then
    System.Move(FList[Index + 1], FList[Index], (FCount - Index) * SizeOf(Integer));
end;

procedure TBpIntList.Clear;
begin
  if FCount <> 0 then
  begin
    FCount := 0;
    SetCapacity(0);
  end;
end;

function TBpIntList.GetDelimiter: Char;
begin
  if not (idDelimiter in FDefined) then
    Delimiter := ',';
  Result := FDelimiter;
end;

procedure TBpIntList.SetDelimiter(const Value: Char);
begin
  if (FDelimiter <> Value) or not (idDelimiter in FDefined) then
  begin
    Include(FDefined, idDelimiter);
    FDelimiter := Value;
  end
end;

function TBpIntList.GetCommaText: string;
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

procedure TBpIntList.SetCommaText(const Value: string);
begin
  Delimiter := ',';
  SetDelimitedText(Value);
end;

function TBpIntList.GetCount: Integer;
begin
  Result := FCount;
end;

function TBpIntList.GetDelimitedText: string;
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

procedure TBpIntList.SetDelimitedText(const Value: string);
var
  P, Start: PChar;
  S: string;
  Num: Integer;
begin
  Clear;
  P := PChar(Value);
  while P^ <> #0 do
  begin
    Start := P;
    // Search for the next delimiter, end of string, or newline character
    while (P^ <> #0) and (P^ <> Delimiter) and not (P^ in [#10, #13]) do
      Inc(P);

    // Extract the substring from the start of the number to the delimiter
    SetString(S, Start, P - Start);
    if S <> '' then
    begin
      // Try to convert the substring into a number and add it to the list
      if TryStrToInt(S, Num) then
        Add(Num)
      else
        raise EConvertError.CreateFmt('Cannot convert string "%s" to integer', [S]);
    end;

    // Skip the delimiter and any trailing newline characters or spaces
    while P^ in [Delimiter, #10, #13, ' '] do
      Inc(P);
  end;
end;


procedure TBpIntList.LoadFromFile(const FileName: string);
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadFromStream(FileStream);
  finally
    FileStream.Free;
  end;
end;

procedure TBpIntList.LoadFromStream(Stream: TStream);
var
  S: string;
  Buffer: array of Byte;
begin
  Clear;
  SetLength(Buffer, Stream.Size);
  Stream.Position := 0; // Ensure the stream's read pointer is at the beginning.
  Stream.Read(Buffer[0], Stream.Size);
  // Convert buffer into string
  SetString(S, PAnsiChar(@Buffer[0]), Length(Buffer));
  SetDelimitedText(S);
end;

procedure TBpIntList.SaveToFile(const FileName: string);
var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create(FileName, fmCreate);
  try
    SaveToStream(FileStream);
  finally
    FileStream.Free;
  end;
end;

procedure TBpIntList.SaveToStream(Stream: TStream);
var
  Text: string;
begin
  Text := GetDelimitedText; // Get the delimited text representation of the list
  if Length(Text) > 0 then
    Stream.WriteBuffer(Text[1], Length(Text));
end;

function TBpIntList.IndexOf(const Item: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  {$IFDEF BENCHMARK}
  FStepCount := 0;
  {$ENDIF}
  for I := 0 to FCount - 1 do
  begin
    {$IFDEF BENCHMARK}
    Inc(FStepCount);
    {$ENDIF}
    if (FList[I] = Item) then
    begin
      Result := I;
      Break;
    end;
  end;
end;

function TBpIntList.BinarySearch(const Item: Integer; out FoundIndex: Integer): Boolean;
var
  L, H, M, CmpResult: Integer;
begin
  if not Sorted then
    raise EListError.Create('List must be sorted for binary search');
  
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
    CmpResult := CompareInt(FList[M], Item);
    if CmpResult < 0 then
      L := M + 1
    else if CmpResult > 0 then
      H := M - 1
    else
    begin
      FoundIndex := M;
      Result := True;
      Exit;
    end;
  end;
  FoundIndex := L; // Return the insertion point if not found
  Result := False;
end;

class function TBpIntList.CompareInt(I1, I2: Integer): Integer;
begin
  if I1 < I2 then
    Result := -1
  else if I1 > I2 then
    Result := 1
  else
    Result := 0;
end;

procedure TBpIntList.Insert(Index: Integer; const Item: Integer);
var
  CorrectIndex, I: Integer;
begin
  if (Index < 0) or (Index > Count) then
    raise EListError.Create('List index out of bounds');

  if Sorted then
  begin
    // Find the correct index for the new item to maintain sort order
    CorrectIndex := 0;
    for I := 0 to Count - 1 do
    begin
      if FList[I] > Item then
        Break;
      Inc(CorrectIndex);
    end;
    Index := CorrectIndex; // Ignore the provided index since we are sorted
  end;

  if Count = Length(FList) then
    Grow;

  // Shift elements to make space for the new item.
  if Index < Count then
    System.Move(FList[Index], FList[Index + 1], (Count - Index) * SizeOf(Integer));

  FList[Index] := Item;
  Inc(FCount);
end;

procedure TBpIntList.Sort;
begin
  if not Sorted and (FCount > 1) then
    QuickSort(0, FCount - 1);
end;

end.

