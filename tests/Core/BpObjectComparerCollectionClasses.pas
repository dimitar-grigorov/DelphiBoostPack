unit BpObjectComparerCollectionClasses;

interface

uses
  Classes, IUniqueIdUnit, InterfacedCollectionItemUnit;

type
  TMyEnumCol = (meValueOne, meValueTwo);

  TSimpleTestItemUnique = class(TInterfacedCollectionItem, IUniqueId)
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

  TSimpleTestCollectionUnique = class(TCollection)
  private
    function GetItem(Index: Integer): TSimpleTestItemUnique;
    procedure SetItem(Index: Integer; const Value: TSimpleTestItemUnique);
  public
    constructor Create;
    function Add: TSimpleTestItemUnique;
    property Items[Index: Integer]: TSimpleTestItemUnique read GetItem write SetItem; default;
  end;

  // Sample class with TSimpleTestCollection as a published property
  TTestClassWithCollectionUnique = class(TPersistent)
  private
    FMyCollection: TSimpleTestCollectionUnique;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property MyCollection: TSimpleTestCollectionUnique read FMyCollection write FMyCollection;
  end;

implementation

uses
  SysUtils;

constructor TSimpleTestCollectionUnique.Create;
begin
  inherited Create(TSimpleTestItemUnique);
end;

function TSimpleTestCollectionUnique.Add: TSimpleTestItemUnique;
begin
  Result := TSimpleTestItemUnique(inherited Add);
end;

function TSimpleTestCollectionUnique.GetItem(Index: Integer): TSimpleTestItemUnique;
begin
  Result := TSimpleTestItemUnique(inherited GetItem(Index));
end;

procedure TSimpleTestCollectionUnique.SetItem(Index: Integer; const Value: TSimpleTestItemUnique);
begin
  Items[Index].Assign(Value);
end;

{ TSimpleTestItem }

function TSimpleTestItemUnique.GetUniqueId: string;
begin
 Result := IntToStr(Self.ID)
end;

{ TTestClassWithCollection }

constructor TTestClassWithCollectionUnique.Create;
begin
  inherited Create;
  FMyCollection := TSimpleTestCollectionUnique.Create;
end;

destructor TTestClassWithCollectionUnique.Destroy;
begin
  FMyCollection.Free;
  inherited Destroy;
end;

end.

