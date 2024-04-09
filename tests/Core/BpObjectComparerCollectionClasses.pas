unit BpObjectComparerCollectionClasses;

interface

uses
  Classes, IUniqueIdUnit, InterfacedCollectionItemUnit;

type
  TMyEnumCol = (meValueOne, meValueTwo);

  TSimpleTestItem = class(TInterfacedCollectionItem, IUniqueId)
  private
    FID: Integer;
    FName: string;
    FCharProp: Char;
    FFloatProp: Double;
    FEnumProp: TMyEnumCol;
  public
    function GetUniqueId: string;
  published
    property ID: Integer read FID write FID;
    property Name: string read FName write FName;
    property CharProp: Char read FCharProp write FCharProp;
    property FloatProp: Double read FFloatProp write FFloatProp;
    property EnumProp: TMyEnumCol read FEnumProp write FEnumProp;
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

uses
  SysUtils;

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

{ TSimpleTestItem }

function TSimpleTestItem.GetUniqueId: string;
begin
 Result := IntToStr(Self.ID)
end;

end.

