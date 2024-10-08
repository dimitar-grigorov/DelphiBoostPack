unit BpIntListTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, Classes, BpIntList, SysUtils;

type
  // Test methods for class TBpIntList

  TBpIntListTests = class(TTestCase)
  private
    FBpIntList: TBpIntList;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    //Add
    procedure TestAdd;
    //Delete
    procedure TestDelete;
    procedure TestDeleteFirstItem;
    procedure TestDeleteLastItem;
    procedure TestDeleteWithInvalidIndex;
    //Clear
    procedure TestClear;
    //IndexOf
    procedure TestIndexOf;
    //BinarySearch
    procedure TestBinarySearchEmptyList;
    procedure TestBinarySearchSingleElement;
    procedure TestBinarySearchMultipleElements;
    //Exchange
    procedure TestExchangeValidIndices;
    procedure TestExchangeSameIndex;
    procedure TestExchangeInvalidIndex;
    procedure TestExchangeWithEmptyList;
    //Insert
    procedure TestInsert;
    procedure TestInsertAtBeginning;
    procedure TestInsertAtEnd;
    procedure TestInsertWithInvalidIndex;
    procedure TestInsertRandomPositions;
    procedure TestInsertIntoEmptyList;
    procedure TestSortedInsert;
    //Sorted
    procedure TestSortedPropertySetTrue;
    procedure TestSortedPropertySetFalse;
    procedure TestAddItemWhenSorted;
    procedure TestSetItemWhenSorted;
    //Items
    procedure TestSetItem;
    procedure TestGetItemWithInvalidIndex;
    procedure TestSetGetItem;
    //CommaText
    procedure TestSetCommaTextBasic;
    procedure TestGetCommaTextBasic;
    procedure TestSetCommaTextWithSpaces;
    procedure TestCommaTextWithQuotesRaisesException;
    //Count
    procedure TestCountAfterAdd;
    procedure TestCountAfterMultipleAdds;
    procedure TestCountAfterDelete;
    //DelimitedText
    procedure TestSetDelimitedText;
    procedure TestGetDelimitedTextWithDefaultDelimiter;
    procedure TestSetDelimiterAndDelimitedText;
    procedure TestClearAndResetDelimiter;
    procedure TestDelimitedTextEmptyString;
    procedure TestDelimitedTextEndsWithDelimiter;
    procedure TestDelimitedTextOnlyDelimiters;
    procedure TestLargeQuantities;
    procedure TestDelimitedTextWithConsecutiveDelimiters;
    //Sort
    procedure TestSortWithFewItems;
    procedure TestSortWithIdenticalItems;
    procedure TestSortWithNegativeItems;
    procedure TestSortAlreadySorted;
    //LoadFromFile
    procedure TestLoadFromFileBasic;
    procedure TestLoadFromFileNonExisting;
    procedure TestLoadFromFileWithInvalidFormat;
    //SaveToFile
    procedure TestSaveToFileBasic;
    procedure TestSaveToFileWithDelimiterChange;
    procedure TestSaveToFileEmptyList;
    //LoadFromStream
    procedure TestLoadFromStreamBasic;
    procedure TestLoadFromStreamEmpty;
    procedure TestLoadFromStreamWithInvalidFormat;
    //SaveToStream
    procedure TestSaveToStreamBasic;
    procedure TestSaveToStreamEmptyList;
  end;

implementation

uses
  Windows;

procedure TBpIntListTests.SetUp;
begin
  FBpIntList := TBpIntList.Create;
end;

procedure TBpIntListTests.TearDown;
begin
  FBpIntList.Free;
  FBpIntList := nil;
end;

procedure TBpIntListTests.TestAdd;
begin
  FBpIntList.Add(10);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after adding an item');
  CheckEquals(10, FBpIntList.Items[0], 'The item added should be 10');
end;

procedure TBpIntListTests.TestDelete;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(0);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting an item');
  CheckEquals(20, FBpIntList.Items[0], 'The remaining item should be 20');
end;

procedure TBpIntListTests.TestDeleteFirstItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(0); // Delete first item
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting first item');
  CheckEquals(20, FBpIntList.Items[0], 'The first item should now be 20');
end;

procedure TBpIntListTests.TestDeleteLastItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(FBpIntList.Count - 1); // Delete last item
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting last item');
  CheckEquals(10, FBpIntList.Items[0], 'The remaining item should be 10');
end;

procedure TBpIntListTests.TestDeleteWithInvalidIndex;
begin
  try
    FBpIntList.Delete(-1); // Attempt to delete with an invalid index
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // Pass the test
  end;
end;

procedure TBpIntListTests.TestClear;
begin
  FBpIntList.Add(10);
  FBpIntList.Clear;
  CheckEquals(0, FBpIntList.Count, 'Count should be 0 after clearing the list');
end;

procedure TBpIntListTests.TestIndexOf;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  CheckEquals(0, FBpIntList.IndexOf(10), 'IndexOf should return 0 for the first item');
  CheckEquals(1, FBpIntList.IndexOf(20), 'IndexOf should return 1 for the second item');
  CheckEquals(-1, FBpIntList.IndexOf(30), 'IndexOf should return -1 for a non-existent item');
end;

procedure TBpIntListTests.TestBinarySearchEmptyList;
var
  FoundIndex: Integer;
begin
  FBpIntList.Sorted := True;
  CheckFalse(FBpIntList.BinarySearch(10, FoundIndex), 'Search in an empty list should return False.');
end;

procedure TBpIntListTests.TestBinarySearchSingleElement;
var
  FoundIndex: Integer;
begin
  FBpIntList.Add(5);
  FBpIntList.Sorted := True;
  CheckTrue(FBpIntList.BinarySearch(5, FoundIndex), 'Item should be found.');
  CheckEquals(0, FoundIndex, 'FoundIndex should be 0.');

  CheckFalse(FBpIntList.BinarySearch(3, FoundIndex), 'Item should not be found.');
  CheckEquals(0, FoundIndex, 'Insertion index should be 0 for a smaller element.');
end;

procedure TBpIntListTests.TestBinarySearchMultipleElements;
var
  FoundIndex: Integer;
begin
  FBpIntList.Add(5);
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Sorted := True;

  CheckTrue(FBpIntList.BinarySearch(10, FoundIndex), 'Item should be found.');
  CheckEquals(1, FoundIndex, 'FoundIndex should be 1.');

  CheckFalse(FBpIntList.BinarySearch(15, FoundIndex), 'Item should not be found.');
  CheckEquals(2, FoundIndex, 'Insertion index should be 2.');

  CheckTrue(FBpIntList.BinarySearch(5, FoundIndex), 'First element should be found.');
  CheckEquals(0, FoundIndex, 'FoundIndex should be 0.');

  CheckTrue(FBpIntList.BinarySearch(20, FoundIndex), 'Last element should be found.');
  CheckEquals(2, FoundIndex, 'FoundIndex should be 2.');
end;

procedure TBpIntListTests.TestExchangeValidIndices;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Exchange(0, 1);
  CheckEquals(2, FBpIntList.Items[0], 'First item should be 2 after exchange');
  CheckEquals(1, FBpIntList.Items[1], 'Second item should be 1 after exchange');
end;

procedure TBpIntListTests.TestExchangeSameIndex;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Exchange(0, 0);
  CheckEquals(1, FBpIntList.Items[0], 'Item should remain unchanged when indices are the same');
end;

procedure TBpIntListTests.TestExchangeInvalidIndex;
begin
  FBpIntList.Add(1);
  try
    FBpIntList.Exchange(0, 2); // Invalid index
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // Pass the test
  end;
end;

procedure TBpIntListTests.TestExchangeWithEmptyList;
begin
  try
    FBpIntList.Exchange(0, 1); // Attempt to exchange in an empty list
    Fail('Expected EListError not raised for empty list');
  except
    on E: EListError do
      ; // Pass the test
  end;
end;

procedure TBpIntListTests.TestInsert;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(30);
  FBpIntList.Insert(1, 20); // Insert 20 at index 1
  CheckEquals(3, FBpIntList.Count, 'Count should be 3 after insert');
  CheckEquals(20, FBpIntList.Items[1], 'The inserted item should be at index 1');
end;

procedure TBpIntListTests.TestInsertAtBeginning;
begin
  FBpIntList.Add(10);
  FBpIntList.Insert(0, 5); // Insert at the beginning
  CheckEquals(5, FBpIntList.Items[0], 'The inserted item should be the first item');
end;

procedure TBpIntListTests.TestInsertAtEnd;
begin
  FBpIntList.Add(10);
  FBpIntList.Insert(1, 20); // Insert at the end
  CheckEquals(20, FBpIntList.Items[1], 'The inserted item should be the last item');
end;

procedure TBpIntListTests.TestInsertRandomPositions;
var
  I, Pos: Integer;
begin
  // Populate list with initial data
  for I := 1 to 100 do
    FBpIntList.Add(I * 10);

  // Insert at random positions
  for I := 1 to 20 do
  begin
    Pos := Random(FBpIntList.Count + 1);
    FBpIntList.Insert(Pos, 999);  // Insert a specific value to check later
  end;

  CheckEquals(120, FBpIntList.Count, 'Count should be 120 after inserts');
  // Further checks can be added to verify positions if necessary
end;

procedure TBpIntListTests.TestInsertIntoEmptyList;
begin
  FBpIntList.Insert(0, 10);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after insert into empty list');
  CheckEquals(10, FBpIntList.Items[0], 'The inserted item should be at index 0');
end;

procedure TBpIntListTests.TestSortedInsert;
begin
  FBpIntList.Sorted := True;
  FBpIntList.Add(30);
  FBpIntList.Add(10);
  FBpIntList.Add(20);  // Add should now insert in sorted order
  CheckEquals(10, FBpIntList.Items[0], 'First item should be 10');
  CheckEquals(20, FBpIntList.Items[1], 'Second item should be 20');
  CheckEquals(30, FBpIntList.Items[2], 'Third item should be 30');
end;

procedure TBpIntListTests.TestInsertWithInvalidIndex;
begin
  try
    FBpIntList.Insert(-1, 10); // Attempt to insert with an invalid index
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // Test passes
  end;
end;

procedure TBpIntListTests.TestSortedPropertySetTrue;
begin
  FBpIntList.Add(3);
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Sorted := True;
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1 after sorting');
  CheckEquals(True, FBpIntList.Sorted, 'Sorted property should be True after setting it to True');
end;

procedure TBpIntListTests.TestSortedPropertySetFalse;
begin
  FBpIntList.Sorted := False;
  CheckEquals(False, FBpIntList.Sorted, 'Sorted property should be False after setting it to False');
end;

procedure TBpIntListTests.TestAddItemWhenSorted;
begin
  FBpIntList.Sorted := True;
  FBpIntList.Add(3);
  FBpIntList.Add(1);
  CheckEquals(1, FBpIntList.Items[0], 'Items should be added in sorted order');
end;

procedure TBpIntListTests.TestSetItemWhenSorted;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(3);
  FBpIntList.Sorted := True;
  FBpIntList.Items[1] := 2; // This should either raise an exception or require a re-sort
  CheckEquals(2, FBpIntList.Items[1], 'Setting item in a sorted list should maintain order');
end;

procedure TBpIntListTests.TestSetItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Items[0] := 20; // Set item at index 0 to 20
  CheckEquals(20, FBpIntList.Items[0], 'Item at index 0 should be set to 20');
end;

procedure TBpIntListTests.TestGetItemWithInvalidIndex;
begin
  try
    FBpIntList.Items[-1]; // Attempt to access with an invalid index
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // Pass the test
  end;
end;

procedure TBpIntListTests.TestSetGetItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Items[0] := 20;
  CheckEquals(20, FBpIntList.Items[0], 'Item should be updated to 20');
end;

procedure TBpIntListTests.TestSetCommaTextBasic;
begin
  FBpIntList.CommaText := '1,2,3';
  CheckEquals(3, FBpIntList.Count, 'Count should be 3 after setting CommaText');
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1');
  CheckEquals(2, FBpIntList.Items[1], 'Second item should be 2');
  CheckEquals(3, FBpIntList.Items[2], 'Third item should be 3');
end;

procedure TBpIntListTests.TestGetCommaTextBasic;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Add(3);
  CheckEquals('1,2,3', FBpIntList.CommaText, 'CommaText should correctly represent the list');
end;

procedure TBpIntListTests.TestSetCommaTextWithSpaces;
begin
  FBpIntList.CommaText := '1, 2, 3';
  CheckEquals(3, FBpIntList.Count, 'Count should be 3 after setting CommaText with spaces');
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1');
  CheckEquals(2, FBpIntList.Items[1], 'Second item should be 2');
end;

procedure TBpIntListTests.TestCommaTextWithQuotesRaisesException;
begin
  try
    FBpIntList.CommaText := '"1,5",2,"3,4"';
    Fail('Expected exception not raised for CommaText with quotes');
  except
    on E: EConvertError do
      Check(True, 'Exception raised as expected for CommaText with quotes');
    else
      Check(False, 'Unexpected exception type raised');
  end;
end;

procedure TBpIntListTests.TestCountAfterAdd;
begin
  FBpIntList.Add(10);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after adding one item');
end;

procedure TBpIntListTests.TestCountAfterMultipleAdds;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  CheckEquals(2, FBpIntList.Count, 'Count should be 2 after adding two items');
end;

procedure TBpIntListTests.TestCountAfterDelete;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(0);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting one item');
end;

procedure TBpIntListTests.TestSetDelimitedText;
begin
  FBpIntList.DelimitedText := '1,2,3';
  CheckEquals(3, FBpIntList.Count, 'Count should be 3');
  CheckEquals(2, FBpIntList.Items[1], 'The second item should be 2');
end;

procedure TBpIntListTests.TestGetDelimitedTextWithDefaultDelimiter;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  CheckEquals('1,2', FBpIntList.DelimitedText, 'DelimitedText should be "1,2" with default delimiter');
end;

procedure TBpIntListTests.TestSetDelimiterAndDelimitedText;
begin
  FBpIntList.Delimiter := ';';
  FBpIntList.DelimitedText := '1;2';

  CheckEquals('1;2', FBpIntList.DelimitedText, 'DelimitedText should respect the set delimiter ";"');
end;

procedure TBpIntListTests.TestClearAndResetDelimiter;
begin
  FBpIntList.Delimiter := ';';
  FBpIntList.Clear;
  FBpIntList.Delimiter := ',';
  CheckEquals(',', FBpIntList.Delimiter, 'Delimiter should be reset to "," after clearing and setting');
end;

procedure TBpIntListTests.TestDelimitedTextEmptyString;
begin
  FBpIntList.DelimitedText := '';
  CheckEquals(0, FBpIntList.Count, 'Count should be 0 for empty DelimitedText');
end;

procedure TBpIntListTests.TestDelimitedTextEndsWithDelimiter;
begin
  FBpIntList.Delimiter := ',';
  FBpIntList.DelimitedText := '1,2,3,';
  CheckEquals(3, FBpIntList.Count, 'Count should be 3 even if DelimitedText ends with delimiter');
  CheckEquals(3, FBpIntList.Items[2], 'Last item should be 3');
end;

procedure TBpIntListTests.TestDelimitedTextOnlyDelimiters;
begin
  FBpIntList.Delimiter := ',';
  FBpIntList.DelimitedText := ',,,';
  CheckEquals(0, FBpIntList.Count, 'Count should be 0 if DelimitedText contains only delimiters');
end;

procedure TBpIntListTests.TestDelimitedTextWithConsecutiveDelimiters;
begin
  FBpIntList.Delimiter := ',';
  FBpIntList.DelimitedText := '1,,2';
  CheckEquals(2, FBpIntList.Count, 'Count should be 2 with consecutive delimiters treated as single delimiter');
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1');
  CheckEquals(2, FBpIntList.Items[1], 'Second item should be 2');
end;

procedure TBpIntListTests.TestSortWithFewItems;
begin
  FBpIntList.Add(2);
  FBpIntList.Add(3);
  FBpIntList.Add(1);
  FBpIntList.Sort;
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1 after sorting');
  CheckEquals(2, FBpIntList.Items[1], 'Second item should be 2 after sorting');
  CheckEquals(3, FBpIntList.Items[2], 'Third item should be 3 after sorting');
end;

procedure TBpIntListTests.TestSortWithIdenticalItems;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(1);
  FBpIntList.Add(1);
  FBpIntList.Sort;
  CheckEquals(1, FBpIntList.Items[0], 'First item should be 1 after sorting');
  CheckEquals(1, FBpIntList.Items[1], 'Second item should be 1 after sorting');
  CheckEquals(1, FBpIntList.Items[2], 'Third item should be 1 after sorting');
end;

procedure TBpIntListTests.TestSortWithNegativeItems;
begin
  FBpIntList.Add(-1);
  FBpIntList.Add(-3);
  FBpIntList.Add(-2);
  FBpIntList.Sort;
  CheckEquals(-3, FBpIntList.Items[0], 'First item should be -3 after sorting');
  CheckEquals(-2, FBpIntList.Items[1], 'Second item should be -2 after sorting');
  CheckEquals(-1, FBpIntList.Items[2], 'Third item should be -1 after sorting');
end;

procedure TBpIntListTests.TestSortAlreadySorted;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Add(3);
  FBpIntList.Sort;
  CheckEquals(1, FBpIntList.Items[0], 'First item should still be 1 after sorting');
  CheckEquals(2, FBpIntList.Items[1], 'Second item should still be 2 after sorting');
  CheckEquals(3, FBpIntList.Items[2], 'Third item should still be 3 after sorting');
end;

procedure TBpIntListTests.TestLoadFromFileBasic;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'testfile.txt';
  // Prepare the file with known content
  SavedText := TStringList.Create;
  try
    SavedText.Text := '1,2,3';
    SavedText.SaveToFile(FileName);
    
    FBpIntList.LoadFromFile(FileName);
    CheckEquals(3, FBpIntList.Count, 'Count should be 3 after loading from file');
  finally
    SysUtils.DeleteFile(FileName); // Delete the file after test
    SavedText.Free;
  end;
end;

procedure TBpIntListTests.TestLoadFromFileNonExisting;
begin
  try
    FBpIntList.LoadFromFile('nonexistingfile.txt');
    Fail('Expected exception for non-existing file');
  except
    on E: Exception do
      Check(True, 'Exception raised as expected');
  end;
end;

procedure TBpIntListTests.TestSaveToFileBasic;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'savetofiletest.txt';
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Add(3);

  FBpIntList.SaveToFile(FileName);

  // Verify the file content
  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('1,2,3', TrimRight(SavedText.Text), 'File content should match the list content');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName); // Delete the file after test
  end;
end;

procedure TBpIntListTests.TestSaveToFileWithDelimiterChange;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'delimitertest.txt';
  FBpIntList.Delimiter := ';';
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Add(3);

  FBpIntList.SaveToFile(FileName);

  // Verify the file content
  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('1;2;3', TrimRight(SavedText.Text), 'File content should respect the changed delimiter');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName); // Delete the file after test
  end;
end;

procedure TBpIntListTests.TestSaveToFileEmptyList;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'emptylisttest.txt';
  FBpIntList.SaveToFile(FileName);

  // Verify the file is empty
  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('', TrimRight(SavedText.Text), 'File content should be empty for an empty list');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName); // Delete the file after test
  end;
end;

procedure TBpIntListTests.TestLoadFromFileWithInvalidFormat;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'invalidformat.txt';
  // Prepare the file with invalid content
  SavedText := TStringList.Create;
  try
    SavedText.Text := 'not,a,number';
    SavedText.SaveToFile(FileName);

    try
      FBpIntList.LoadFromFile(FileName);
      Fail('Expected exception for invalid content');
    except
      on E: EConvertError do
        Check(True, 'Exception raised as expected for invalid content');
    end;
  finally
    SysUtils.DeleteFile(FileName); // Delete the file after test
    SavedText.Free;
  end;
end;

procedure TBpIntListTests.TestLoadFromStreamBasic;
var
  MemoryStream: TMemoryStream;
  InputText: string;
begin
  InputText := '1,2,3';
  MemoryStream := TMemoryStream.Create;
  try
    // Prepare the stream with known content
    with TStringList.Create do
    try
      Text := InputText;
      SaveToStream(MemoryStream);
    finally
      Free;
    end;
    MemoryStream.Position := 0; // Reset stream position for reading

    FBpIntList.LoadFromStream(MemoryStream);
  finally
    MemoryStream.Free;
  end;

  CheckEquals(3, FBpIntList.Count, 'Count should be 3 after loading from stream');
end;

procedure TBpIntListTests.TestLoadFromStreamEmpty;
var
  MemoryStream: TMemoryStream;
begin
  MemoryStream := TMemoryStream.Create;
  try
    FBpIntList.LoadFromStream(MemoryStream);
  finally
    MemoryStream.Free;
  end;

  CheckEquals(0, FBpIntList.Count, 'Count should be 0 after loading from an empty stream');
end;

procedure TBpIntListTests.TestLoadFromStreamWithInvalidFormat;
var
  MemoryStream: TMemoryStream;
  InputText: string;
begin
  InputText := 'invalid,data';
  MemoryStream := TMemoryStream.Create;
  try
    // Prepare the stream with invalid content
    with TStringList.Create do
    try
      Text := InputText;
      SaveToStream(MemoryStream);
    finally
      Free;
    end;
    MemoryStream.Position := 0; // Reset stream position for reading

    try
      FBpIntList.LoadFromStream(MemoryStream);
      Fail('Expected exception for invalid content');
    except
      on E: EConvertError do
        Check(True, 'Exception raised as expected for invalid content');
    end;
  finally
    MemoryStream.Free;
  end;
end;

procedure TBpIntListTests.TestSaveToStreamBasic;
var
  MemoryStream: TMemoryStream;
  OutputText: string;
begin
  MemoryStream := TMemoryStream.Create;
  try
    FBpIntList.Add(1);
    FBpIntList.Add(2);
    FBpIntList.Add(3);
    FBpIntList.SaveToStream(MemoryStream);

    // Verify the stream content
    SetString(OutputText, PAnsiChar(MemoryStream.Memory), MemoryStream.Size);
    CheckEquals('1,2,3', OutputText, 'Stream content should match the list content');
  finally
    MemoryStream.Free;
  end;
end;

procedure TBpIntListTests.TestSaveToStreamEmptyList;
var
  MemoryStream: TMemoryStream;
  OutputText: string;
begin
  MemoryStream := TMemoryStream.Create;
  try
    FBpIntList.SaveToStream(MemoryStream);

    // Verify the stream is empty
    SetString(OutputText, PAnsiChar(MemoryStream.Memory), MemoryStream.Size);
    CheckEquals('', OutputText, 'Stream content should be empty for an empty list');
  finally
    MemoryStream.Free;
  end;
end;

procedure TBpIntListTests.TestLargeQuantities;
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
  RegisterTest(TBpIntListTests.Suite);

end.

