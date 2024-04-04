unit bpIntList;

interface

uses
  Classes, SysUtils, BpIntListInterface;

type
  TbpIntListDefined = set of (idDelimiter, idLineBreak, idStrictDelimiter);

  TBpIntList = class(TInterfacedPersistent, IBpIntList)
  private
    FList: array of Integer;
    FDefined: TbpIntListDefined;
    FUpdateCount: Integer;
    FCount: Integer;
    FDelimiter: Char;
    FOnChange: TNotifyEvent;
    FOnChanging: TNotifyEvent;
    function GetItem(Index: Integer): Integer;
    procedure SetItem(Index: Integer; const Value: Integer);
    procedure SetCapacity(const NewCapacity: Integer);
    procedure Grow;
    function GetDelimitedText: string;
    procedure SetDelimitedText(const Value: string);
    function GetDelimiter: Char;
    procedure SetDelimiter(const Value: Char);
    function GetCount: Integer;     
  protected
    procedure Changed; virtual;
    procedure Changing; virtual;
    procedure SetUpdateState(const Updating: Boolean); virtual;
    property UpdateCount: Integer read FUpdateCount;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const Item: Integer): Integer;
    procedure BeginUpdate;
    procedure Delete(const Index: Integer);
    procedure Clear;
    procedure EndUpdate;
    function IndexOf(const Item: Integer): Integer;
    procedure Insert(Index: Integer; const Item: Integer);
    property Items[Index: Integer]: Integer read GetItem write SetItem; default;
    property Count: Integer read FCount;
    property Delimiter: Char read GetDelimiter write SetDelimiter;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnChanging: TNotifyEvent read FOnChanging write FOnChanging;
  end;

implementation

constructor TBpIntList.Create;
begin
  inherited;
  FCount := 0;
  SetCapacity(0);
end;

destructor TBpIntList.Destroy;
begin
  FOnChange := nil;
  FOnChanging := nil;
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

procedure TBpIntList.SetCapacity(const NewCapacity: Integer);
begin
  if NewCapacity < FCount then
    FCount := NewCapacity; // Reduce count if reducing capacity below count
  if NewCapacity <> Length(FList) then
    SetLength(FList, NewCapacity);
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

function TBpIntList.Add(const Item: Integer): Integer;
begin
  if FCount = Length(FList) then
    Grow;
  FList[FCount] := Item;
  Result := FCount;
  Inc(FCount);
end;

procedure TBpIntList.Delete(const Index: Integer);
begin
  if (Index < 0) or (Index >= FCount) then
    raise EListError.Create('List index out of bounds');
  Dec(FCount);
  if Index < FCount then
    System.Move(FList[Index + 1], FList[Index], (FCount - Index) * SizeOf(Integer));
end;

procedure TBpIntList.Clear;
begin
  SetCapacity(0);
  FCount := 0;
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

function TBpIntList.GetCount: Integer;
begin
  Result := FCount;
end;

function TBpIntList.GetDelimitedText: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FCount - 1 do
  begin
    Result := Result + IntToStr(FList[i]);
    if i < FCount - 1 then
      Result := Result + Delimiter;
  end;
end;

procedure TBpIntList.SetDelimitedText(const Value: string);
var
  P, Start: PChar;
  S: string;
  Num: Integer;
begin
  BeginUpdate;
  try
    Clear;
    P := PChar(Value);
    while P^ <> #0 do
    begin
      Start := P;
      // Search for the next delimiter or end of string
      while (P^ <> #0) and (P^ <> Delimiter) do
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

      // Skip the delimiter
      if P^ = Delimiter then
        Inc(P);
    end;
  finally
    EndUpdate;
  end;
end;

procedure TBpIntList.BeginUpdate;
begin
  if FUpdateCount = 0 then
    SetUpdateState(True);
  Inc(FUpdateCount);
end;

procedure TBpIntList.EndUpdate;
begin
  Dec(FUpdateCount);
  if FUpdateCount = 0 then
    SetUpdateState(False);
end;

function TBpIntList.IndexOf(const Item: Integer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to Count - 1 do
    if (FList[I] = Item) then
    begin
      Result := I;
      Break;
    end;
end;

procedure TBpIntList.Insert(Index: Integer; const Item: Integer);
begin
  if (Index < 0) or (Index > Count) then
    raise EListError.Create('List index out of bounds');

  if Count = Length(FList) then
    Grow;
  // Shift elements to make space for the new item.
  if Index < Count then
    System.Move(FList[Index], FList[Index + 1], (Count - Index) * SizeOf(Integer));
    
  FList[Index] := Item;
  Inc(FCount);
end;

procedure TBpIntList.SetUpdateState(const Updating: Boolean);
begin
  if Updating then
    Changing
  else
    Changed;
end;

procedure TBpIntList.Changed;
begin
  if (FUpdateCount = 0) and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TBpIntList.Changing;
begin
  if (FUpdateCount = 0) and Assigned(FOnChanging) then
    FOnChanging(Self);
end;

end.

