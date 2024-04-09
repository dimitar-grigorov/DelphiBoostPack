unit BpObjectComparerSimpleTests;

interface

uses
  TestFramework, BpObjectComparerUnit, BpObjectComparerSimpleClasses, Variants;

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

    procedure TestCompareWithSameCollectionData;
    procedure TestCompareWithDifferentCollectionData;
    procedure TestCompareWithEmptyAndPopulatedCollection;
    procedure TestCompareCollectionsWithDifferentNames;

    procedure TestCompareCollectionsWithDifferentCharProps;
    procedure TestCompareCollectionsWithDifferentFloatProps;
    procedure TestCompareCollectionsWithDifferentEnumProps;
    procedure TestCompareCollectionsWithMultipleDifferences;
  end;

implementation

uses
  StrUtils, BpObjectComparerCollectionClasses;

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

    CheckEquals('CharProp', Diffs[0].PropPath, 'First difference should be in CharProp');
    CheckEquals('A', VarToStr(Diffs[0].OldValue), 'Old value of CharProp should be A');
    CheckEquals('B', VarToStr(Diffs[0].NewValue), 'New value of CharProp should be B');

    CheckEquals('FloatProp', Diffs[1].PropPath, 'Second difference should be in FloatProp');
    CheckTrue(VarIsFloat(Diffs[1].OldValue) and VarIsFloat(Diffs[1].NewValue), 'Old and New values of FloatProp should be floats');
    CheckEquals(1.1, Diffs[1].OldValue, 0.001, 'Old value of FloatProp should be 1.1');
    CheckEquals(1.2, Diffs[1].NewValue, 0.001, 'New value of FloatProp should be 1.2');
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

    CheckTrue(AnsiContainsStr(DiffStr, 'EnumProp; OldValue: meFirst; NewValue: meSecond'), 'Difference in EnumProp should be correctly formatted in DiffStr');
    CheckTrue(AnsiContainsStr(DiffStr, 'VariantProp; OldValue: Variant1; NewValue: Variant2'), 'Difference in VariantProp should be correctly formatted in DiffStr');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareWithSameCollectionData;
var
  Obj1, Obj2: TTestClassWithCollection;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Obj1.MyCollection.Add.ID := 1;
    Obj2.MyCollection.Add.ID := 1;

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(0, Length(Diffs), 'Collections are identical, no differences should be found');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareWithDifferentCollectionData;
var
  Obj1, Obj2: TTestClassWithCollection;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Obj1.MyCollection.Add.ID := 1;
    Obj2.MyCollection.Add.ID := 2; // Different ID

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(2, Length(Diffs), 'Should find differences in collections for each item');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareWithEmptyAndPopulatedCollection;
var
  Obj1, Obj2: TTestClassWithCollection;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    // Obj1 has no items added to MyCollection
    Obj2.MyCollection.Add.ID := 1; // Obj2 has one item

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(2, Length(Diffs), 'Should find differences for count and the missing item');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentNames;
var
  Obj1, Obj2: TTestClassWithCollection;
  Item1, Item2: TSimpleTestItem;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 1;
    Item1.Name := 'Item1';

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 1;
    Item2.Name := 'Item2';

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[1].Name', Diffs[0].PropPath, 'Property path should match');
    CheckEquals('Item1', Diffs[0].OldValue, 'Old value should match');
    CheckEquals('Item2', Diffs[0].NewValue, 'New value should match');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;


procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentCharProps;
var
  Obj1, Obj2: TTestClassWithCollection;
  Item1, Item2: TSimpleTestItem;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 1;
    Item1.CharProp := 'A';

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 1;
    Item2.CharProp := 'B';

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'Should find differences in character properties');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentFloatProps;
var
  Obj1, Obj2: TTestClassWithCollection;
  Item1, Item2: TSimpleTestItem;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 1;
    Item1.FloatProp := 1.0;

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 1;
    Item2.FloatProp := 2.0;

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'Should find differences in float properties');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentEnumProps;
var
  Obj1, Obj2: TTestClassWithCollection;
  Item1, Item2: TSimpleTestItem;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 1;
    Item1.EnumProp := meValueOne;

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 1;
    Item2.EnumProp := meValueTwo;

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'Should find differences in enum properties');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithMultipleDifferences;
var
  Obj1, Obj2: TTestClassWithCollection;
  Item1, Item2: TSimpleTestItem;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 1;
    Item1.Name := 'Item1';
    Item1.CharProp := 'A';
    Item1.FloatProp := 1.0;
    Item1.EnumProp := meValueOne;

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 1;
    Item2.Name := 'Item2';
    Item2.CharProp := 'B';
    Item2.FloatProp := 2.0;
    Item2.EnumProp := meValueTwo;

    Diffs := FComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(4, Length(Diffs), 'Should find differences in multiple properties');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

initialization
  TestFramework.RegisterTest(TestTBpObjectComparer.Suite);

end.

