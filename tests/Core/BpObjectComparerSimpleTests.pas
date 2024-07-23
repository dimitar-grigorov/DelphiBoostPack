unit BpObjectComparerSimpleTests;

interface

uses
  TestFramework, BpObjectComparerUnit, BpObjectComparerSimpleClasses, Variants;

type
  TestTBpObjectComparer = class(TTestCase)
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
    procedure TestCompareCollectionsWithItemsInDifferentOrder;
  end;

implementation

uses
  StrUtils, BpObjectComparerCollectionClasses;

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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(2, Length(Diffs), 'There should be two differences');

    CheckEquals('CharProp', Diffs[0].OldPropPath, 'First difference should be in CharProp');
    CheckEquals('A', VarToStr(Diffs[0].OldValue), 'Old value of CharProp should be A');
    CheckEquals('B', VarToStr(Diffs[0].NewValue), 'New value of CharProp should be B');

    CheckEquals('FloatProp', Diffs[1].OldPropPath, 'Second difference should be in FloatProp');
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

    DiffStr := TBpObjectComparer.CompareObjectsAsString(Obj1, Obj2);
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[1].Name', Diffs[0].OldPropPath, 'Property path should match');
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[1].CharProp', Diffs[0].OldPropPath, 'Property path should match');
    CheckEquals('A', Diffs[0].OldValue, 'Old value should match');
    CheckEquals('B', Diffs[0].NewValue, 'New value should match');
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[1].FloatProp', Diffs[0].OldPropPath, 'Property path should match');
    CheckEquals(1.0, VarAsType(Diffs[0].OldValue, varDouble), 0.001, 'Old value should match');
    CheckEquals(2.0, VarAsType(Diffs[0].NewValue, varDouble), 0.001, 'New value should match');
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[1].EnumProp', Diffs[0].OldPropPath, 'Property path should match');

    // Compare the string representations of the enum values
    CheckEquals('meValueOne', Diffs[0].OldValue, 'Old value should match');
    CheckEquals('meValueTwo', Diffs[0].NewValue, 'New value should match');
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

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(4, Length(Diffs), 'Four differences expected');

    CheckEquals('MyCollection[1].CharProp', Diffs[0].OldPropPath);
    CheckEquals('A', Diffs[0].OldValue);
    CheckEquals('B', Diffs[0].NewValue);

    CheckEquals('MyCollection[1].EnumProp', Diffs[1].OldPropPath);
    CheckEquals('meValueOne', Diffs[1].OldValue);
    CheckEquals('meValueTwo', Diffs[1].NewValue);

    CheckEquals('MyCollection[1].FloatProp', Diffs[2].OldPropPath);
    CheckEquals(1.0, VarAsType(Diffs[2].OldValue, varDouble), 0.001);
    CheckEquals(2.0, VarAsType(Diffs[2].NewValue, varDouble), 0.001);

    CheckEquals('MyCollection[1].Name', Diffs[3].OldPropPath);
    CheckEquals('Item1', Diffs[3].OldValue);
    CheckEquals('Item2', Diffs[3].NewValue);
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithItemsInDifferentOrder;
var
  Obj1, Obj2: TTestClassWithCollection;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    with Obj1.MyCollection.Add do
    begin
      ID := 1;
      Name := 'Item1';
    end;
    with Obj1.MyCollection.Add do
    begin
      ID := 2;
      Name := 'Item2';
    end;

    with Obj2.MyCollection.Add do
    begin
      ID := 2; // Reverse order
      Name := 'Item2';
    end;
    with Obj2.MyCollection.Add do
    begin
      ID := 1;
      Name := 'Item1';
    end;

    Diffs := TBpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(0, Length(Diffs), 'No differences should be found if order is not considered');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

initialization
  TestFramework.RegisterTest(TestTBpObjectComparer.Suite);

end.

