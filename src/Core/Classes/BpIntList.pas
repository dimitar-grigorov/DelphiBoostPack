unit bpIntList;

interface

uses
  Classes;

type
  TBpIntList = class(TPersistent)
  private
    FList: array of Integer;
    FCount: Integer;
    function GetItem(Index: Integer): Integer;
    procedure SetItem(Index: Integer; const Value: Integer);
    procedure SetCapacity(NewCapacity: Integer);
    procedure Grow;
  public
    constructor Create;
    destructor Destroy; override;
    function Add(Item: Integer): Integer;
    procedure Delete(Index: Integer);
    procedure Clear;
    property Items[Index: Integer]: Integer read GetItem write SetItem; default;
    property Count: Integer read FCount;
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
  SetCapacity(0);
  inherited;
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

procedure TBpIntList.SetCapacity(NewCapacity: Integer);
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

function TBpIntList.Add(Item: Integer): Integer;
begin
  if FCount = Length(FList) then
    Grow;
  FList[FCount] := Item;
  Result := FCount;
  Inc(FCount);
end;

procedure TBpIntList.Delete(Index: Integer);
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


end.
