unit BpObjectComparerSimpleTests;

interface
uses
  TestFramework, // Assuming use of DUnit or a similar testing framework
  BpObjectComparerUnit,
  BpObjectComparerSimpleClasses,
  Variants;

type
  TestTBpObjectComparer = class(TTestCase)
  private
    FComparer: TBpObjectComparer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCompareObjectsWithNoDifferences;
    procedure TestCompareObjectsWithDifferences;
    procedure TestCompareObjectsAsString;
  end;

implementation

procedure TestTBpObjectComparer.SetUp;
begin
  FComparer := TBpObjectComparer.Create;
end;

procedure TestTBpObjectComparer.TearDown;
begin
  FComparer.Free;
end;

procedure TestTBpObjectComparer.TestCompareObjectsWithNoDifferences;
var
  Obj1, Obj2: TTestClassA;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassA.Create;
  Obj2 := TTestClassA.Create;
  try
    Obj1.IntegerProp := 10;
    Obj2.IntegerProp := 10;
    Obj1.StringProp := 'Test';
    Obj2.StringProp := 'Test';

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(0, Length(Diffs), 'There should be no differences');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareObjectsWithDifferences;
var
  Obj1, Obj2: TTestClassB;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassB.Create;
  Obj2 := TTestClassB.Create;
  try
    Obj1.CharProp := 'A';
    Obj2.CharProp := 'B';
    Obj1.FloatProp := 1.1;
    Obj2.FloatProp := 1.2;

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(2, Length(Diffs), 'There should be two differences');

  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareObjectsAsString;
var
  Obj1, Obj2: TTestClassC;
  DiffStr: string;
begin
  Obj1 := TTestClassC.Create;
  Obj2 := TTestClassC.Create;
  try
    Obj1.EnumProp := meFirst;
    Obj2.EnumProp := meSecond;
    Obj1.VariantProp := 'Variant1';
    Obj2.VariantProp := 'Variant2';

    DiffStr := FComparer.CompareObjectsAsString(Obj1, Obj2);
    CheckNotEquals('', DiffStr, 'The difference string should not be empty');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

initialization
  TestFramework.RegisterTest(TestTBpObjectComparer.Suite);

end.
