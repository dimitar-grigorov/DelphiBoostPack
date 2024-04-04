unit BpIntListTests;

interface

uses
  TestFramework, Classes, bpIntList, SysUtils;

type
  // Test methods for class TBpIntList

  TestTBpIntList = class(TTestCase)
  strict private
    FBpIntList: TBpIntList;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAdd;

    procedure TestDelete;
    procedure TestDeleteFirstItem;
    procedure TestDeleteLastItem;
    procedure TestDeleteWithInvalidIndex;

    procedure TestClear;

    procedure TestSetItem;
    procedure TestGetItemWithInvalidIndex;
    procedure TestSetGetItem;

    procedure TestCountAfterAdd;
    procedure TestCountAfterMultipleAdds;
    procedure TestCountAfterDelete;

    procedure TestSetDelimitedText;
    procedure TestGetDelimitedTextWithDefaultDelimiter;
    procedure TestSetDelimiterAndDelimitedText;
    procedure TestClearAndResetDelimiter;
    procedure TestDelimitedTextEmptyString;
    procedure TestDelimitedTextEndsWithDelimiter;
    procedure TestDelimitedTextOnlyDelimiters;
    procedure TestLargeQuantities;
    procedure TestDelimitedTextWithConsecutiveDelimiters;
  end;

implementation

procedure TestTBpIntList.SetUp;
begin
  FBpIntList := TBpIntList.Create;
end;

procedure TestTBpIntList.TearDown;
begin
  FBpIntList.Free;
  FBpIntList := nil;
end;

procedure TestTBpIntList.TestAdd;
begin
  FBpIntList.Add(10);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after adding an item');
  CheckEquals(10, FBpIntList.Items[0], 'The item added should be 10');
end;

procedure TestTBpIntList.TestDelete;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(0);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting an item');
  CheckEquals(20, FBpIntList.Items[0], 'The remaining item should be 20');
end;

procedure TestTBpIntList.TestDeleteFirstItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(0); // Delete first item
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting first item');
  CheckEquals(20, FBpIntList.Items[0], 'The first item should now be 20');
end;

procedure TestTBpIntList.TestDeleteLastItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(FBpIntList.Count - 1); // Delete last item
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting last item');
  CheckEquals(10, FBpIntList.Items[0], 'The remaining item should be 10');
end;

procedure TestTBpIntList.TestDeleteWithInvalidIndex;
begin
  try
    FBpIntList.Delete(-1); // Attempt to delete with an invalid index
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // Pass the test
  end;
end;

procedure TestTBpIntList.TestClear;
begin
  FBpIntList.Add(10);
  FBpIntList.Clear;
  CheckEquals(0, FBpIntList.Count, 'Count should be 0 after clearing the list');
end;

procedure TestTBpIntList.TestSetItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Items[0] := 20; // Set item at index 0 to 20
  CheckEquals(20, FBpIntList.Items[0], 'Item at index 0 should be set to 20');
end;

procedure TestTBpIntList.TestGetItemWithInvalidIndex;
var
  Item: Integer;
begin
  try
    Item := FBpIntList.Items[-1]; // Attempt to access with an invalid index
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // Pass the test
  end;
end;

procedure TestTBpIntList.TestSetGetItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Items[0] := 20;
  CheckEquals(20, FBpIntList.Items[0], 'Item should be updated to 20');
end;

procedure TestTBpIntList.TestCountAfterAdd;
begin
  FBpIntList.Add(10);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after adding one item');
end;

procedure TestTBpIntList.TestCountAfterMultipleAdds;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  CheckEquals(2, FBpIntList.Count, 'Count should be 2 after adding two items');
end;

procedure TestTBpIntList.TestCountAfterDelete;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(0);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting one item');
end;

procedure TestTBpIntList.TestSetDelimitedText;
begin
  FBpIntList.DelimitedText := '1,2,3';
  CheckEquals(3, FBpIntList.Count, 'Count should be 3');
  CheckEquals(2, FBpIntList.Items[1], 'The second item should be 2');
end;

procedure TestTBpIntList.TestGetDelimitedTextWithDefaultDelimiter;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  CheckEquals('1,2', FBpIntList.DelimitedText, 'DelimitedText should be "1,2" with default delimiter');
end;

procedure TestTBpIntList.TestSetDelimiterAndDelimitedText;
begin
  FBpIntList.Delimiter := ';';
  FBpIntList.DelimitedText := '1;2';

  CheckEquals('1;2', FBpIntList.DelimitedText, 'DelimitedText should respect the set delimiter ";"');
end;

procedure TestTBpIntList.TestClearAndResetDelimiter;
begin
  FBpIntList.Delimiter := ';';
  FBpIntList.Clear;
  FBpIntList.Delimiter := ',';
  CheckEquals(',', FBpIntList.Delimiter, 'Delimiter should be reset to "," after clearing and setting');
end;

procedure TestTBpIntList.TestDelimitedTextEmptyString;
begin
  FBpIntList.DelimitedText := '';
  CheckEquals(0, FBpIntList.Count, 'Count should be 0 for empty DelimitedText');
end;

procedure TestTBpIntList.TestDelimitedTextEndsWithDelimiter;
begin
  FBpIntList.Delimiter := ',';
  FBpIntList.DelimitedText := '1,2,3,';
  CheckEquals(3, FBpIntList.Count, 'Count should be 3 even if DelimitedText ends with delimiter');
  CheckEquals(3, FBpIntList.Items[2], 'Last item should be 3');
end;

procedure TestTBpIntList.TestDelimitedTextOnlyDelimiters;
begin
  FBpIntList.Delimiter := ',';
  FBpIntList.DelimitedText := ',,,';
  CheckEquals(0, FBpIntList.Count, 'Count should be 0 if DelimitedText contains only delimiters');
end;

procedure TestTBpIntList.TestDelimitedTextWithConsecutiveDelimiters;
begin
  FBpIntList.Delimiter := ',';
  FBpIntList.DelimitedText := '1,,2';
  CheckEquals(2, FBpIntList.Count, 'Count should be 2 with consecutive delimiters treated as single delimiter');
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1');
  CheckEquals(2, FBpIntList.Items[1], 'Second item should be 2');
end;

procedure TestTBpIntList.TestLargeQuantities;
var
  I, N: Integer;
begin
  N := 1000000;
  for I := 1 to N do
    FBpIntList.Add(I);
  CheckEquals(N, FBpIntList.Count, Format('List should contain %d items', [N]));
  // Optionally, check a few items at specific positions to ensure they were added correctly
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1');
  CheckEquals(N div 2, FBpIntList.Items[N div 2 - 1], 'Middle item should be ' + IntToStr(N div 2));
  CheckEquals(N, FBpIntList.Items[N - 1], 'Last item should be ' + IntToStr(N));
end;

initialization
  RegisterTest(TestTBpIntList.Suite);

end.
