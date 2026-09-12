unit BpObjectComparerSimpleClasses;

interface

uses
  Classes;

type
  TMyEnum = (meFirst, meSecond, meThird);

  TTestClassA = class(TPersistent)
  private
    FIntegerProp: Integer;
    FInt64Prop: Int64;
    FStringProp: string;
  published
    property IntegerProp: Integer read FIntegerProp write FIntegerProp;
    property Int64Prop: Int64 read FInt64Prop write FInt64Prop;
    property StringProp: string read FStringProp write FStringProp;
  end;

  TTestClassB = class(TPersistent)
  private
    FCharProp: Char;
    FFloatProp: Double;
    FWideCharProp: WideChar;
  published
    property CharProp: Char read FCharProp write FCharProp;
    property FloatProp: Double read FFloatProp write FFloatProp;
    property WideCharProp: WideChar read FWideCharProp write FWideCharProp;
  end;

  TTestClassC = class(TPersistent)
  private
    FEnumProp: TMyEnum;
    FVariantProp: Variant;
  published
    property EnumProp: TMyEnum read FEnumProp write FEnumProp;
    property VariantProp: Variant read FVariantProp write FVariantProp;
  end;

  // an owned sub-object, a link to another node that can close a cycle, and a component reference
  TTestNode = class(TPersistent)
  private
    FValue: Integer;
    FInner: TTestClassA;
    FNext: TTestNode;
    FRef: TComponent;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Value: Integer read FValue write FValue;
    property Inner: TTestClassA read FInner write FInner;
    property Next: TTestNode read FNext write FNext;
    property Ref: TComponent read FRef write FRef;
  end;

implementation

constructor TTestNode.Create;
begin
  inherited Create;
  FInner := TTestClassA.Create;
end;

destructor TTestNode.Destroy;
begin
  FInner.Free;
  inherited Destroy;
end;

end.

