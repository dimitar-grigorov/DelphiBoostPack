unit BpObjectComparerSimpleClasses;

interface

uses
  Classes;

type
  TMyEnum = (meFirst, meSecond, meThird);

  TTestClassA = class(TPersistent)
  private
    FIntegerProp: Integer;
    FStringProp: string;
  published
    property IntegerProp: Integer read FIntegerProp write FIntegerProp;
    property StringProp: string read FStringProp write FStringProp;
  end;

  TTestClassB = class(TPersistent)
  private
    FCharProp: Char;
    FFloatProp: Double;
  published
    property CharProp: Char read FCharProp write FCharProp;
    property FloatProp: Double read FFloatProp write FFloatProp;
  end;

  TTestClassC = class(TPersistent)
  private
    FEnumProp: TMyEnum;
    FVariantProp: Variant;
  published
    property EnumProp: TMyEnum read FEnumProp write FEnumProp;
    property VariantProp: Variant read FVariantProp write FVariantProp;
  end;

implementation

end.

