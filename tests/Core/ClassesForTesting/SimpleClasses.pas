unit SimpleClasses;

interface

type
  TMyEnum = (meFirst, meSecond, meThird);

  TTestClassA = class
  private
    FIntegerProp: Integer;
    FStringProp: string;
  public
    property IntegerProp: Integer read FIntegerProp write FIntegerProp;
    property StringProp: string read FStringProp write FStringProp;
  end;

  TTestClassB = class
  private
    FCharProp: Char;
    FFloatProp: Double;
  public
    property CharProp: Char read FCharProp write FCharProp;
    property FloatProp: Double read FFloatProp write FFloatProp;
  end;

  TTestClassC = class
  private
    FEnumProp: TMyEnum;
    FVariantProp: Variant;
  public
    property EnumProp: TMyEnum read FEnumProp write FEnumProp;
    property VariantProp: Variant read FVariantProp write FVariantProp;
  end;

implementation

end.

