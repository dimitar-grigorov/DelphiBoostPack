unit BpObjectComparerSimpleTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, BpObjectComparer, BpObjectComparerSimpleClasses, Variants;

type
  TestTBpObjectComparer = class(TTestCase)
  private
    FObjA: TTestClassA;
    FObjB: TTestClassB;
    // helpers passed to CheckException
    procedure CompareOldNil;
    procedure CompareNewNil;
    procedure CompareBothNil;
    procedure CompareDifferentClasses;
    procedure CompareAsStringNewNil;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCompareObjectsWithNoDifferences;
    procedure TestCompareObjectsWithDifferences;
    procedure TestNilArgumentsRaise;
    procedure TestMismatchedClassesRaise;
    procedure TestChangedItemClassIsOneDifference;
    procedure TestCompareWideCharProperties;
    procedure TestCompareInt64Properties;
    procedure TestNestedObjectPropertiesAreWalked;
    procedure TestNilNestedObjectIsOneDifference;
    procedure TestComponentReferenceComparesByIdentity;
    procedure TestObjectCycleTerminates;
    procedure TestCollectionReachableFromItsItemTerminates;
    procedure TestCompareObjectsAsString;

    procedure TestCompareWithSameCollectionData;
    procedure TestCompareWithDifferentCollectionData;
    procedure TestCompareWithEmptyAndPopulatedCollection;
    procedure TestAddedAndRemovedItemFields;
    procedure TestNilCollectionProperty;
    procedure TestIncomparableVariantProperties;
    procedure TestCompareCollectionsWithDifferentNames;

    procedure TestCompareCollectionsWithDifferentCharProps;
    procedure TestCompareCollectionsWithDifferentFloatProps;
    procedure TestCompareCollectionsWithDifferentEnumProps;
    procedure TestCompareCollectionsWithMultipleDifferences;
    procedure TestCompareCollectionsWithItemsInDifferentOrder;
    procedure TestDuplicateIdsPairUpInOrder;
    //Index based collection tests
    procedure TestCompareCollectionsWithSameIndexNoUniqueId;
    //procedure TestCompareCollectionsWithDifferentLengthsNoUniqueId;
    //procedure TestCompareEmptyAndPopulatedCollectionNoUniqueId;

    //StripIndexFromProperty Tests
    procedure TestStripIndexFromProperty_NoBrackets;
    procedure TestStripIndexFromProperty_WithBrackets;
    procedure TestStripIndexFromProperty_EmptyString;
    procedure TestStripIndexFromProperty_NestedBrackets;
    procedure TestStripIndexFromProperty_OnlyBrackets;
    procedure TestStripIndexFromProperty_BracketsAtEdges;    
  end;

implementation

uses
  SysUtils, Classes, StrUtils, BpObjectComparerCollectionClasses;

procedure TestTBpObjectComparer.SetUp;
begin
  inherited;
  FObjA := TTestClassA.Create;
  FObjB := TTestClassB.Create;
end;

procedure TestTBpObjectComparer.TearDown;
begin
  FObjA.Free;
  FObjB.Free;
  inherited;
end;

procedure TestTBpObjectComparer.CompareOldNil;
begin
  TbpObjectComparer.CompareObjects(nil, FObjA);
end;

procedure TestTBpObjectComparer.CompareNewNil;
begin
  TbpObjectComparer.CompareObjects(FObjA, nil);
end;

procedure TestTBpObjectComparer.CompareBothNil;
begin
  TbpObjectComparer.CompareObjects(nil, nil);
end;

procedure TestTBpObjectComparer.CompareDifferentClasses;
begin
  TbpObjectComparer.CompareObjects(FObjA, FObjB);
end;

procedure TestTBpObjectComparer.CompareAsStringNewNil;
begin
  TbpObjectComparer.CompareObjectsAsString(FObjA, nil);
end;

// nil used to be an access violation on aOld.ClassInfo or inside GetPropValue
procedure TestTBpObjectComparer.TestNilArgumentsRaise;
begin
  CheckException(CompareOldNil, EbpObjectComparer);
  CheckException(CompareNewNil, EbpObjectComparer);
  CheckException(CompareBothNil, EbpObjectComparer);
  CheckException(CompareAsStringNewNil, EbpObjectComparer);
end;

// aOld's property list read against aNew used to end in EPropertyError
procedure TestTBpObjectComparer.TestMismatchedClassesRaise;
begin
  CheckException(CompareDifferentClasses, EbpObjectComparer);
end;

// inside a collection a changed item class is data, so it is reported and not walked
procedure TestTBpObjectComparer.TestChangedItemClassIsOneDifference;
var
  Obj1, Obj2: TTestClassWithCollection;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Obj1.MyCollection.Add.Name := 'same';
    with TSimpleTestItemSub.Create(Obj2.MyCollection) do
    begin
      Name := 'changed';
      Extra := 5;
    end;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'the class change is the whole difference');
    CheckEquals('MyCollection[0]', Diffs[0].OldPropPath, 'old path');
    CheckEquals('MyCollection[0]', Diffs[0].NewPropPath, 'new path');
    CheckEquals('TSimpleTestItem', VarToStr(Diffs[0].OldValue), 'old class');
    CheckEquals('TSimpleTestItemSub', VarToStr(Diffs[0].NewValue), 'new class');
    CheckEquals('0', Diffs[0].Idx, 'the item index');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
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

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
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

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
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

// two WideChars sharing a low byte used to compare equal on a pre-2009 Char
procedure TestTBpObjectComparer.TestCompareWideCharProperties;
var
  Obj1, Obj2: TTestClassB;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassB.Create;
  Obj2 := TTestClassB.Create;
  try
    Obj1.WideCharProp := WideChar($0041);
    Obj2.WideCharProp := WideChar($0141);

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'the two wide chars differ');
    CheckEquals('WideCharProp', Diffs[0].OldPropPath, 'property path');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

// tkInt64 was missing from the handled kinds, so an Int64 property was never compared
procedure TestTBpObjectComparer.TestCompareInt64Properties;
var
  Obj2: TTestClassA;
  Diffs: TPropDifferences;
  OldValue, NewValue: Int64;
begin
  Obj2 := TTestClassA.Create;
  try
    FObjA.Int64Prop := $100000000;
    Obj2.Int64Prop := $100000000;
    Diffs := TbpObjectComparer.CompareObjects(FObjA, Obj2);
    CheckEquals(0, Length(Diffs), 'equal values');

    Obj2.Int64Prop := $200000000;
    Diffs := TbpObjectComparer.CompareObjects(FObjA, Obj2);
    CheckEquals(1, Length(Diffs), 'the values differ above the low 32 bits only');
    CheckEquals('Int64Prop', Diffs[0].OldPropPath, 'property path');
    OldValue := Diffs[0].OldValue;
    NewValue := Diffs[0].NewValue;
    CheckEquals($100000000, OldValue, 'old value');
    CheckEquals($200000000, NewValue, 'new value');
  finally
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestNestedObjectPropertiesAreWalked;
var
  Node1, Node2: TTestNode;
  Diffs: TPropDifferences;
begin
  Node1 := TTestNode.Create;
  Node2 := TTestNode.Create;
  try
    Node1.Inner.StringProp := 'before';
    Node2.Inner.StringProp := 'after';

    Diffs := TbpObjectComparer.CompareObjects(Node1, Node2);
    CheckEquals(1, Length(Diffs), 'the nested change is found');
    CheckEquals('Inner.StringProp', Diffs[0].OldPropPath, 'old path');
    CheckEquals('Inner.StringProp', Diffs[0].NewPropPath, 'new path');
    CheckEquals('before', VarToStr(Diffs[0].OldValue), 'old value');
    CheckEquals('after', VarToStr(Diffs[0].NewValue), 'new value');
  finally
    Node1.Free;
    Node2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestNilNestedObjectIsOneDifference;
var
  Node1, Node2: TTestNode;
  Diffs: TPropDifferences;
begin
  Node1 := TTestNode.Create;
  Node2 := TTestNode.Create;
  try
    Node1.Inner.StringProp := 'kept';
    Node2.Inner.Free;
    Node2.Inner := nil;

    Diffs := TbpObjectComparer.CompareObjects(Node1, Node2);
    CheckEquals(1, Length(Diffs), 'the vanished object is one difference, its properties are not walked');
    CheckEquals('Inner', Diffs[0].OldPropPath, 'property path');
    CheckEquals('Exists in old', VarToStr(Diffs[0].OldValue), 'old value');
    CheckEquals('Missing in new', VarToStr(Diffs[0].NewValue), 'new value');

    Diffs := TbpObjectComparer.CompareObjects(Node2, Node1);
    CheckEquals(1, Length(Diffs), 'and one the other way round');
    CheckEquals('Missing in old', VarToStr(Diffs[0].OldValue), 'old value');
    CheckEquals('Exists in new', VarToStr(Diffs[0].NewValue), 'new value');
  finally
    Node1.Free;
    Node2.Free;
  end;
end;

// a component is a reference, as in streaming, so its own properties are not diffed
procedure TestTBpObjectComparer.TestComponentReferenceComparesByIdentity;
var
  Node1, Node2: TTestNode;
  Shared, Other: TComponent;
  Diffs: TPropDifferences;
begin
  Node1 := TTestNode.Create;
  Node2 := TTestNode.Create;
  Shared := TComponent.Create(nil);
  Other := TComponent.Create(nil);
  try
    Shared.Name := 'Shared';
    Node1.Ref := Shared;
    Node2.Ref := Shared;
    Diffs := TbpObjectComparer.CompareObjects(Node1, Node2);
    CheckEquals(0, Length(Diffs), 'the same component on both sides');

    Node2.Ref := Other;
    Diffs := TbpObjectComparer.CompareObjects(Node1, Node2);
    CheckEquals(1, Length(Diffs), 'a different component is one difference');
    CheckEquals('Ref', Diffs[0].OldPropPath, 'property path');
    CheckEquals('Shared', VarToStr(Diffs[0].OldValue), 'the name when it has one');
    CheckEquals('TComponent', VarToStr(Diffs[0].NewValue), 'the class when it has none');
  finally
    Node1.Free;
    Node2.Free;
    Shared.Free;
    Other.Free;
  end;
end;

// a node whose Next points back at it used to be an unbounded descent
procedure TestTBpObjectComparer.TestObjectCycleTerminates;
var
  Head1, Tail1, Head2, Tail2: TTestNode;
  Diffs: TPropDifferences;
begin
  Head1 := TTestNode.Create;
  Tail1 := TTestNode.Create;
  Head2 := TTestNode.Create;
  Tail2 := TTestNode.Create;
  try
    Head1.Next := Tail1;
    Tail1.Next := Head1;
    Head2.Next := Tail2;
    Tail2.Next := Head2;
    Tail1.Value := 1;
    Tail2.Value := 2;

    Diffs := TbpObjectComparer.CompareObjects(Head1, Head2);
    CheckEquals(1, Length(Diffs), 'the tail is compared once, the way back is not followed');
    CheckEquals('Next.Value', Diffs[0].OldPropPath, 'property path');
  finally
    Head1.Free;
    Tail1.Free;
    Head2.Free;
    Tail2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCollectionReachableFromItsItemTerminates;
var
  Obj1, Obj2: TTestClassWithSelfRefCollection;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithSelfRefCollection.Create;
  Obj2 := TTestClassWithSelfRefCollection.Create;
  try
    TSelfRefItem(Obj1.Items.Add).Value := 1;
    TSelfRefItem(Obj2.Items.Add).Value := 2;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'the item is compared once');
    CheckEquals('Items[0].Value', Diffs[0].OldPropPath, 'property path');
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

    DiffStr := TbpObjectComparer.CompareObjectsAsString(Obj1, Obj2);
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
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Obj1.MyCollection.Add.ID := 2;
    Obj2.MyCollection.Add.ID := 2;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(0, Length(Diffs), 'Collections are identical, no differences should be found');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareWithDifferentCollectionData;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Obj1.MyCollection.Add.ID := 1;
    Obj2.MyCollection.Add.ID := 2; // Different ID

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(2, Length(Diffs), 'Should find differences in collections for each item');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareWithEmptyAndPopulatedCollection;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    // Obj1 has no items added to MyCollection
    Obj2.MyCollection.Add.ID := 1; // Obj2 has one item

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(2, Length(Diffs), 'Should find differences for count and the missing item');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

// a nil collection on one side used to be an access violation
procedure TestTBpObjectComparer.TestNilCollectionProperty;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Obj1.MyCollection.Add.ID := 1;
    Obj2.MyCollection.Free;
    Obj2.MyCollection := nil;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'the vanished collection is one difference');
    CheckEquals('MyCollection', Diffs[0].OldPropPath, 'property path');
    CheckEquals('Exists in old', VarToStr(Diffs[0].OldValue), 'old value');
    CheckEquals('Missing in new', VarToStr(Diffs[0].NewValue), 'new value');

    Diffs := TbpObjectComparer.CompareObjects(Obj2, Obj1);
    CheckEquals(1, Length(Diffs), 'and one the other way round');
    CheckEquals('Missing in old', VarToStr(Diffs[0].OldValue), 'old value');
    CheckEquals('Exists in new', VarToStr(Diffs[0].NewValue), 'new value');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

// a string against a number used to abort the whole comparison
procedure TestTBpObjectComparer.TestIncomparableVariantProperties;
var
  Obj1, Obj2: TTestClassC;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassC.Create;
  Obj2 := TTestClassC.Create;
  try
    Obj1.VariantProp := 'not a number';
    Obj2.VariantProp := 42;
    // the premise: this pair really is incomparable, or the test guards nothing
    try
      Check(Obj1.VariantProp <> Obj2.VariantProp);
      Fail('expected EVariantError from the bare comparison');
    except
      on E: ETestFailure do
        raise;
      on E: EVariantError do
        Check(True);
    end;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'the pair is reported, not raised');
    CheckEquals('VariantProp', Diffs[0].OldPropPath, 'property path');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

// the marker text used to land in NewPropPath and shift every later argument
procedure TestTBpObjectComparer.TestAddedAndRemovedItemFields;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Obj1.MyCollection.Add.ID := 7;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(2, Length(Diffs), 'count plus the removed item');
    CheckEquals('MyCollection[0]', Diffs[1].OldPropPath, 'old path');
    CheckEquals('MyCollection[0]', Diffs[1].NewPropPath, 'new path');
    CheckEquals('Exists in old', VarToStr(Diffs[1].OldValue), 'old value');
    CheckEquals('Missing in new', VarToStr(Diffs[1].NewValue), 'new value');
    CheckEquals('7', Diffs[1].Idx, 'the unique id is the index');

    Diffs := TbpObjectComparer.CompareObjects(Obj2, Obj1);
    CheckEquals(2, Length(Diffs), 'count plus the added item');
    CheckEquals('MyCollection[0]', Diffs[1].OldPropPath, 'old path');
    CheckEquals('MyCollection[0]', Diffs[1].NewPropPath, 'new path');
    CheckEquals('Missing in old', VarToStr(Diffs[1].OldValue), 'old value');
    CheckEquals('Exists in new', VarToStr(Diffs[1].NewValue), 'new value');
    CheckEquals('0', Diffs[1].Idx, 'the item index');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentNames;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Item1, Item2: TSimpleTestItemUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 5;
    Item1.Name := 'Item1';

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 5;
    Item2.Name := 'Item2';

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[0].Name', Diffs[0].OldPropPath, 'Property path should match');
    CheckEquals('Item1', Diffs[0].OldValue, 'Old value should match');
    CheckEquals('Item2', Diffs[0].NewValue, 'New value should match');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentCharProps;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Item1, Item2: TSimpleTestItemUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 5;
    Item1.CharProp := 'A';

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 5;
    Item2.CharProp := 'B';

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[0].CharProp', Diffs[0].OldPropPath, 'Property path should match');
    CheckEquals('A', Diffs[0].OldValue, 'Old value should match');
    CheckEquals('B', Diffs[0].NewValue, 'New value should match');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentFloatProps;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Item1, Item2: TSimpleTestItemUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 5;
    Item1.FloatProp := 1.0;

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 5;
    Item2.FloatProp := 2.0;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[0].FloatProp', Diffs[0].OldPropPath, 'Property path should match');
    CheckEquals(1.0, VarAsType(Diffs[0].OldValue, varDouble), 0.001, 'Old value should match');
    CheckEquals(2.0, VarAsType(Diffs[0].NewValue, varDouble), 0.001, 'New value should match');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithDifferentEnumProps;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Item1, Item2: TSimpleTestItemUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 5;
    Item1.EnumProp := meValueOne;

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 5;
    Item2.EnumProp := meValueTwo;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'One difference expected');
    CheckEquals('MyCollection[0].EnumProp', Diffs[0].OldPropPath, 'Property path should match');

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
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Item1, Item2: TSimpleTestItemUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 5;
    Item1.Name := 'Item1';
    Item1.CharProp := 'A';
    Item1.FloatProp := 1.0;
    Item1.EnumProp := meValueOne;

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 5;
    Item2.Name := 'Item2';
    Item2.CharProp := 'B';
    Item2.FloatProp := 2.0;
    Item2.EnumProp := meValueTwo;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(4, Length(Diffs), 'Four differences expected');

    CheckEquals('MyCollection[0].CharProp', Diffs[0].OldPropPath);
    CheckEquals('A', Diffs[0].OldValue);
    CheckEquals('B', Diffs[0].NewValue);

    CheckEquals('MyCollection[0].EnumProp', Diffs[1].OldPropPath);
    CheckEquals('meValueOne', Diffs[1].OldValue);
    CheckEquals('meValueTwo', Diffs[1].NewValue);

    CheckEquals('MyCollection[0].FloatProp', Diffs[2].OldPropPath);
    CheckEquals(1.0, VarAsType(Diffs[2].OldValue, varDouble), 0.001);
    CheckEquals(2.0, VarAsType(Diffs[2].NewValue, varDouble), 0.001);

    CheckEquals('MyCollection[0].Name', Diffs[3].OldPropPath);
    CheckEquals('Item1', Diffs[3].OldValue);
    CheckEquals('Item2', Diffs[3].NewValue);
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithItemsInDifferentOrder;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    with Obj1.MyCollection.Add do
    begin
      ID := 77;
      Name := 'Item1';
    end;
    with Obj1.MyCollection.Add do
    begin
      ID := 33;
      Name := 'Item2';
    end;

    with Obj2.MyCollection.Add do
    begin
      ID := 33; // Reverse order
      Name := 'Item2';
    end;
    with Obj2.MyCollection.Add do
    begin
      ID := 77;
      Name := 'Item1';
    end;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(0, Length(Diffs), 'No differences should be found if order is not considered');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

// the second item with a repeated id used to match the first one again, leaving the real twin unmatched
procedure TestTBpObjectComparer.TestDuplicateIdsPairUpInOrder;
var
  Obj1, Obj2: TTestClassWithCollectionUnique;
  Diffs: TPropDifferences;
begin
  Obj1 := TTestClassWithCollectionUnique.Create;
  Obj2 := TTestClassWithCollectionUnique.Create;
  try
    Obj1.MyCollection.Add.Name := 'A';
    Obj1.MyCollection.Add.Name := 'B';
    Obj2.MyCollection.Add.Name := 'A';
    Obj2.MyCollection.Add.Name := 'B';

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(0, Length(Diffs), 'two items sharing an id are still the same two items');

    Obj2.MyCollection[1].Name := 'C';
    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(1, Length(Diffs), 'the twins pair up in order');
    CheckEquals('MyCollection[1].Name', Diffs[0].OldPropPath, 'old path');
    CheckEquals('MyCollection[1].Name', Diffs[0].NewPropPath, 'new path');
    CheckEquals('B', VarToStr(Diffs[0].OldValue), 'old value');
    CheckEquals('C', VarToStr(Diffs[0].NewValue), 'new value');
    CheckEquals('0', Diffs[0].Idx, 'the shared id');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestCompareCollectionsWithSameIndexNoUniqueId;
var
  Obj1, Obj2: TTestClassWithCollection;
  Diffs: TPropDifferences;
  Item1, Item2: TSimpleTestItem;
begin
  Obj1 := TTestClassWithCollection.Create;
  Obj2 := TTestClassWithCollection.Create;
  try
    Item1 := Obj1.MyCollection.Add;
    Item1.ID := 1;
    Item1.Name := 'Item1';
    Item1.CharProp := 'A';
    Item1.FloatProp := 1.1;
    Item1.EnumProp := meValueOne;

    Item2 := Obj2.MyCollection.Add;
    Item2.ID := 1;
    Item2.Name := 'Item2';
    Item2.CharProp := 'B';
    Item2.FloatProp := 2.2;
    Item2.EnumProp := meValueTwo;

    Diffs := TbpObjectComparer.CompareObjects(Obj1, Obj2);
    CheckEquals(4, Length(Diffs), 'Four differences expected');

    CheckEquals('MyCollection[0].CharProp', Diffs[0].OldPropPath, 'Property path should match');
    CheckEquals('A', Diffs[0].OldValue, 'Old value should match');
    CheckEquals('B', Diffs[0].NewValue, 'New value should match');

    CheckEquals('MyCollection[0].EnumProp', Diffs[1].OldPropPath, 'Property path should match');
    CheckEquals('meValueOne', Diffs[1].OldValue, 'Old value should match');
    CheckEquals('meValueTwo', Diffs[1].NewValue, 'New value should match');

    CheckEquals('MyCollection[0].FloatProp', Diffs[2].OldPropPath, 'Property path should match');
    CheckEquals(1.1, Diffs[2].OldValue, 0.001, 'Old value should match');
    CheckEquals(2.2, Diffs[2].NewValue, 0.001, 'New value should match');

    CheckEquals('MyCollection[0].Name', Diffs[3].OldPropPath, 'Property path should match');
    CheckEquals('Item1', Diffs[3].OldValue, 'Old value should match');
    CheckEquals('Item2', Diffs[3].NewValue, 'New value should match');
  finally
    Obj1.Free;
    Obj2.Free;
  end;
end;

procedure TestTBpObjectComparer.TestStripIndexFromProperty_NoBrackets;
var
  lvResult: string;
begin
  lvResult := TbpObjectComparer.StripIndexFromProperty('SomeProperty');
  CheckEquals('SomeProperty', lvResult);
end;

procedure TestTBpObjectComparer.TestStripIndexFromProperty_WithBrackets;
var
  lvResult: string;
begin
  lvResult := TbpObjectComparer.StripIndexFromProperty('SomeProperty[Index]');
  CheckEquals('SomeProperty', lvResult);
end;

procedure TestTBpObjectComparer.TestStripIndexFromProperty_EmptyString;
var
  lvResult: string;
begin
  lvResult := TbpObjectComparer.StripIndexFromProperty('');
  CheckEquals('', lvResult);
end;

procedure TestTBpObjectComparer.TestStripIndexFromProperty_NestedBrackets;
var
  lvResult: string;
begin
  lvResult := TbpObjectComparer.StripIndexFromProperty('SomeProperty[Outer[Inner]]');
  CheckEquals('SomeProperty', lvResult);
end;

procedure TestTBpObjectComparer.TestStripIndexFromProperty_OnlyBrackets;
var
  lvResult: string;
begin
  lvResult := TbpObjectComparer.StripIndexFromProperty('[Index]');
  CheckEquals('', lvResult);
end;

procedure TestTBpObjectComparer.TestStripIndexFromProperty_BracketsAtEdges;
var
  lvResult: string;
begin
  lvResult := TbpObjectComparer.StripIndexFromProperty('[Start]Property[End]');
  CheckEquals('Property', lvResult);
end;

initialization
  TestFramework.RegisterTest(TestTBpObjectComparer.Suite);

end.

