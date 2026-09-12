unit BpObjectComparerCollectionClasses;

interface

uses
  Windows, Classes, UniqueIdIntf, InterfacedCollectionItem;

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

  // created straight into a TSimpleTestCollection, so one collection can hold two item classes
  TSimpleTestItemSub = class(TSimpleTestItem)
  private
    FExtra: Integer;
  published
    property Extra: Integer read FExtra write FExtra;
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

  // a reference counted owner of interfaced items, so a test can see who keeps it alive
  TRefCountedOwner = class(TPersistent, IInterface)
  private
    FRefCount: Integer;
    FDestroyed: PBoolean;
    FItems: TOwnedCollection;
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(aDestroyed: PBoolean);
    destructor Destroy; override;
    property Items: TOwnedCollection read FItems;
    property RefCount: Integer read FRefCount;
  end;

  // Back publishes the item's own collection, so a walk that follows it never ends
  TSelfRefItem = class(TCollectionItem)
  private
    FValue: Integer;
    function GetBack: TCollection;
  published
    property Value: Integer read FValue write FValue;
    property Back: TCollection read GetBack;
  end;

  TTestClassWithSelfRefCollection = class(TPersistent)
  private
    FItems: TCollection;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Items: TCollection read FItems;
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

constructor TRefCountedOwner.Create(aDestroyed: PBoolean);
begin
  inherited Create;
  FDestroyed := aDestroyed;
  FItems := TOwnedCollection.Create(Self, TSimpleTestItemUnique);
end;

destructor TRefCountedOwner.Destroy;
begin
  FItems.Free;
  FDestroyed^ := True;
  inherited Destroy;
end;

function TRefCountedOwner.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TRefCountedOwner._AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TRefCountedOwner._Release: Integer;
begin
  Result := InterlockedDecrement(FRefCount);
  if Result = 0 then
    Destroy;
end;

function TSelfRefItem.GetBack: TCollection;
begin
  Result := Collection;
end;

constructor TTestClassWithSelfRefCollection.Create;
begin
  inherited Create;
  FItems := TCollection.Create(TSelfRefItem);
end;

destructor TTestClassWithSelfRefCollection.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

end.

