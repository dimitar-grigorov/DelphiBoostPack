unit BpObjectComparerCollectionClasses;

interface

uses
  Classes, UniqueIdIntf, InterfacedCollectionItem;

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

type
  TSimpleTestItem = class(TCollectionItem)
  private
    FID: Integer;
    FName: string;
    FCharProp: Char;
    FFloatProp: Double;
    FEnumProp: TMyEnumCol;
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

  TTestClassWithCollection = class(TPersistent)
  private
    FMyCollection: TSimpleTestCollection;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property MyCollection: TSimpleTestCollection read FMyCollection write FMyCollection;
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


{ TSimpleTestItem }

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

{ TTestClassWithCollection }

constructor TTestClassWithCollection.Create;
begin
  inherited Create;
  FMyCollection := TSimpleTestCollection.Create;
end;

destructor TTestClassWithCollection.Destroy;
begin
  FMyCollection.Free;
  inherited Destroy;
end;

end.

