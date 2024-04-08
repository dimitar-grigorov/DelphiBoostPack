unit CollectionClasses;

interface

uses
  Classes;

type
  TSimpleTestItem = class(TCollectionItem)
  private
    FID: Integer;
    FName: string;
  published
    property ID: Integer read FID write FID;
    property Name: string read FName write FName;
  end;

  TSimpleTestCollection = class(TCollection)
  private
    function GetItem(Index: Integer): TSimpleTestItem;
    procedure SetItem(Index: Integer; const Value: TSimpleTestItem);
  public
    constructor Create;
    function Add: TSimpleTestItem;
    property Items[Index: Integer]: TSimpleTestItem read GetItem write SetItem; default;
  end;

implementation

constructor TSimpleTestCollection.Create;
begin
  inherited Create(TSimpleTestItem);
end;

function TSimpleTestCollection.Add: TSimpleTestItem;
begin
  Result := TSimpleTestItem(inherited Add);
end;

function TSimpleTestCollection.GetItem(Index: Integer): TSimpleTestItem;
begin
  Result := TSimpleTestItem(inherited GetItem(Index));
end;

procedure TSimpleTestCollection.SetItem(Index: Integer; const Value: TSimpleTestItem);
begin
  Items[Index].Assign(Value);
end;

end.

