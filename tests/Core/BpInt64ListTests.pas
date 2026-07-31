unit BpInt64ListTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, Classes, BpInt64ListIntf, BpInt64List, SysUtils;

type
  TBpInt64ListTests = class(TTestCase)
  private
    FBpInt64List: TbpInt64List;
    // DUnit has no Int64 overload of CheckEquals and the Integer one would truncate
    procedure CheckEqualsInt64(const aExpected, aActual: Int64; const aMsg: string);
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
    procedure TestIndexOf;
    procedure TestBinarySearchEmptyList;
    procedure TestBinarySearchSingleElement;
    procedure TestBinarySearchMultipleElements;
    procedure TestExchangeValidIndices;
    procedure TestExchangeSameIndex;
    procedure TestExchangeInvalidIndex;
    procedure TestExchangeWithEmptyList;
    procedure TestInsert;
    procedure TestInsertAtBeginning;
    procedure TestInsertAtEnd;
    procedure TestInsertWithInvalidIndex;
    procedure TestInsertRandomPositions;
    procedure TestInsertIntoEmptyList;
    procedure TestSortedInsert;
    procedure TestSortedPropertySetTrue;
    procedure TestSortedPropertySetFalse;
    procedure TestAddItemWhenSorted;
    procedure TestSetItemWhenSorted;
    procedure TestSetItem;
    procedure TestGetItemWithInvalidIndex;
    procedure TestSetGetItem;
    procedure TestSetCommaTextBasic;
    procedure TestGetCommaTextBasic;
    procedure TestSetCommaTextWithSpaces;
    procedure TestCommaTextWithQuotesRaisesException;
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
    procedure TestSortWithFewItems;
    procedure TestSortWithIdenticalItems;
    procedure TestSortWithNegativeItems;
    procedure TestSortAlreadySorted;
    procedure TestLoadFromFileBasic;
    procedure TestLoadFromFileNonExisting;
    procedure TestLoadFromFileWithInvalidFormat;
    procedure TestSaveToFileBasic;
    procedure TestSaveToFileWithDelimiterChange;
    procedure TestSaveToFileEmptyList;
    procedure TestLoadFromStreamBasic;
    procedure TestLoadFromStreamEmpty;
    procedure TestLoadFromStreamWithInvalidFormat;
    procedure TestSaveToStreamBasic;
    procedure TestSaveToStreamEmptyList;
    procedure TestAddBeyondInt32Range;
    procedure TestSetItemBeyondInt32Range;
    procedure TestExtremesDelimitedTextRoundTrip;
    procedure TestExtremesCommaTextRoundTrip;
    procedure TestExtremesStreamRoundTrip;
    procedure TestSortWithLargeMixedValues;
    procedure TestBinarySearchWithLargeMixedValues;
    procedure TestDelimitedTextAboveHighInt64Raises;
    procedure TestDelimitedTextBelowLowInt64Raises;
  end;

  // The list is a TInterfacedObject, so an IBpInt64List reference must free it
  TBpInt64ListMemoryTests = class(TTestCase)
  private
    procedure TestList(aList: IBpInt64List);
  public
    procedure SetUp; override;
  published
    procedure TestMemoryLeak;
  end;

implementation

uses
  Windows;

const
  cAboveHighInt32 = Int64(High(Integer)) + 1;  // 2147483648
  cBelowLowInt32 = Int64(Low(Integer)) - 1;    // -2147483649
  cHighInt64Text = '9223372036854775807';
  cLowInt64Text = '-9223372036854775808';

procedure TBpInt64ListTests.SetUp;
begin
  FBpInt64List := TbpInt64List.Create;
end;

procedure TBpInt64ListTests.TearDown;
begin
  FBpInt64List.Free;
  FBpInt64List := nil;
end;

procedure TBpInt64ListTests.CheckEqualsInt64(const aExpected, aActual: Int64; const aMsg: string);
begin
  CheckEquals(IntToStr(aExpected), IntToStr(aActual), aMsg);
end;

procedure TBpInt64ListTests.TestAdd;
begin
  FBpInt64List.Add(10);
  CheckEquals(1, FBpInt64List.Count, 'Count should be 1 after adding an item');
  CheckEqualsInt64(10, FBpInt64List.Items[0], 'The item added should be 10');
end;

procedure TBpInt64ListTests.TestDelete;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);
  FBpInt64List.Delete(0);
  CheckEquals(1, FBpInt64List.Count, 'Count should be 1 after deleting an item');
  CheckEqualsInt64(20, FBpInt64List.Items[0], 'The remaining item should be 20');
end;

procedure TBpInt64ListTests.TestDeleteFirstItem;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);
  FBpInt64List.Delete(0);
  CheckEquals(1, FBpInt64List.Count, 'Count should be 1 after deleting first item');
  CheckEqualsInt64(20, FBpInt64List.Items[0], 'The first item should now be 20');
end;

procedure TBpInt64ListTests.TestDeleteLastItem;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);
  FBpInt64List.Delete(FBpInt64List.Count - 1);
  CheckEquals(1, FBpInt64List.Count, 'Count should be 1 after deleting last item');
  CheckEqualsInt64(10, FBpInt64List.Items[0], 'The remaining item should be 10');
end;

procedure TBpInt64ListTests.TestDeleteWithInvalidIndex;
begin
  try
    FBpInt64List.Delete(-1);
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
  end;
end;

procedure TBpInt64ListTests.TestClear;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Clear;
  CheckEquals(0, FBpInt64List.Count, 'Count should be 0 after clearing the list');
end;

procedure TBpInt64ListTests.TestIndexOf;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);
  CheckEquals(0, FBpInt64List.IndexOf(10), 'IndexOf should return 0 for the first item');
  CheckEquals(1, FBpInt64List.IndexOf(20), 'IndexOf should return 1 for the second item');
  CheckEquals(-1, FBpInt64List.IndexOf(30), 'IndexOf should return -1 for a non-existent item');
end;

procedure TBpInt64ListTests.TestBinarySearchEmptyList;
var
  FoundIndex: Integer;
begin
  FBpInt64List.Sorted := True;
  CheckFalse(FBpInt64List.BinarySearch(10, FoundIndex), 'Search in an empty list should return False.');
end;

procedure TBpInt64ListTests.TestBinarySearchSingleElement;
var
  FoundIndex: Integer;
begin
  FBpInt64List.Add(5);
  FBpInt64List.Sorted := True;
  CheckTrue(FBpInt64List.BinarySearch(5, FoundIndex), 'Item should be found.');
  CheckEquals(0, FoundIndex, 'FoundIndex should be 0.');

  CheckFalse(FBpInt64List.BinarySearch(3, FoundIndex), 'Item should not be found.');
  CheckEquals(0, FoundIndex, 'Insertion index should be 0 for a smaller element.');
end;

procedure TBpInt64ListTests.TestBinarySearchMultipleElements;
var
  FoundIndex: Integer;
begin
  FBpInt64List.Add(5);
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);
  FBpInt64List.Sorted := True;

  CheckTrue(FBpInt64List.BinarySearch(10, FoundIndex), 'Item should be found.');
  CheckEquals(1, FoundIndex, 'FoundIndex should be 1.');

  CheckFalse(FBpInt64List.BinarySearch(15, FoundIndex), 'Item should not be found.');
  CheckEquals(2, FoundIndex, 'Insertion index should be 2.');

  CheckTrue(FBpInt64List.BinarySearch(5, FoundIndex), 'First element should be found.');
  CheckEquals(0, FoundIndex, 'FoundIndex should be 0.');

  CheckTrue(FBpInt64List.BinarySearch(20, FoundIndex), 'Last element should be found.');
  CheckEquals(2, FoundIndex, 'FoundIndex should be 2.');
end;

procedure TBpInt64ListTests.TestExchangeValidIndices;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  FBpInt64List.Exchange(0, 1);
  CheckEqualsInt64(2, FBpInt64List.Items[0], 'First item should be 2 after exchange');
  CheckEqualsInt64(1, FBpInt64List.Items[1], 'Second item should be 1 after exchange');
end;

procedure TBpInt64ListTests.TestExchangeSameIndex;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  FBpInt64List.Exchange(0, 0);
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'Item should remain unchanged when indices are the same');
end;

procedure TBpInt64ListTests.TestExchangeInvalidIndex;
begin
  FBpInt64List.Add(1);
  try
    FBpInt64List.Exchange(0, 2);
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
  end;
end;

procedure TBpInt64ListTests.TestExchangeWithEmptyList;
begin
  try
    FBpInt64List.Exchange(0, 1);
    Fail('Expected EListError not raised for empty list');
  except
    on E: EListError do
      ; // expected
  end;
end;

procedure TBpInt64ListTests.TestInsert;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Add(30);
  FBpInt64List.Insert(1, 20);
  CheckEquals(3, FBpInt64List.Count, 'Count should be 3 after insert');
  CheckEqualsInt64(20, FBpInt64List.Items[1], 'The inserted item should be at index 1');
end;

procedure TBpInt64ListTests.TestInsertAtBeginning;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Insert(0, 5);
  CheckEqualsInt64(5, FBpInt64List.Items[0], 'The inserted item should be the first item');
end;

procedure TBpInt64ListTests.TestInsertAtEnd;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Insert(1, 20);
  CheckEqualsInt64(20, FBpInt64List.Items[1], 'The inserted item should be the last item');
end;

procedure TBpInt64ListTests.TestInsertRandomPositions;
var
  I, Pos: Integer;
begin
  for I := 1 to 100 do
    FBpInt64List.Add(I * 10);

  for I := 1 to 20 do
  begin
    Pos := Random(FBpInt64List.Count + 1);
    FBpInt64List.Insert(Pos, 999);
  end;

  CheckEquals(120, FBpInt64List.Count, 'Count should be 120 after inserts');
end;

procedure TBpInt64ListTests.TestInsertIntoEmptyList;
begin
  FBpInt64List.Insert(0, 10);
  CheckEquals(1, FBpInt64List.Count, 'Count should be 1 after insert into empty list');
  CheckEqualsInt64(10, FBpInt64List.Items[0], 'The inserted item should be at index 0');
end;

procedure TBpInt64ListTests.TestSortedInsert;
begin
  FBpInt64List.Sorted := True;
  FBpInt64List.Add(30);
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);  // Add should now insert in sorted order
  CheckEqualsInt64(10, FBpInt64List.Items[0], 'First item should be 10');
  CheckEqualsInt64(20, FBpInt64List.Items[1], 'Second item should be 20');
  CheckEqualsInt64(30, FBpInt64List.Items[2], 'Third item should be 30');
end;

procedure TBpInt64ListTests.TestInsertWithInvalidIndex;
begin
  try
    FBpInt64List.Insert(-1, 10);
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
  end;
end;

procedure TBpInt64ListTests.TestSortedPropertySetTrue;
begin
  FBpInt64List.Add(3);
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  FBpInt64List.Sorted := True;
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should be 1 after sorting');
  CheckEquals(True, FBpInt64List.Sorted, 'Sorted property should be True after setting it to True');
end;

procedure TBpInt64ListTests.TestSortedPropertySetFalse;
begin
  FBpInt64List.Sorted := False;
  CheckEquals(False, FBpInt64List.Sorted, 'Sorted property should be False after setting it to False');
end;

procedure TBpInt64ListTests.TestAddItemWhenSorted;
begin
  FBpInt64List.Sorted := True;
  FBpInt64List.Add(3);
  FBpInt64List.Add(1);
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'Items should be added in sorted order');
end;

procedure TBpInt64ListTests.TestSetItemWhenSorted;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Add(3);
  FBpInt64List.Sorted := True;
  FBpInt64List.Items[1] := 2; // behavior is unspecified: may raise or force a re-sort
  CheckEqualsInt64(2, FBpInt64List.Items[1], 'Setting item in a sorted list should maintain order');
end;

procedure TBpInt64ListTests.TestSetItem;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Items[0] := 20;
  CheckEqualsInt64(20, FBpInt64List.Items[0], 'Item at index 0 should be set to 20');
end;

procedure TBpInt64ListTests.TestGetItemWithInvalidIndex;
begin
  try
    FBpInt64List.Items[-1];
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
  end;
end;

procedure TBpInt64ListTests.TestSetGetItem;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Items[0] := 20;
  CheckEqualsInt64(20, FBpInt64List.Items[0], 'Item should be updated to 20');
end;

procedure TBpInt64ListTests.TestSetCommaTextBasic;
begin
  FBpInt64List.CommaText := '1,2,3';
  CheckEquals(3, FBpInt64List.Count, 'Count should be 3 after setting CommaText');
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should be 1');
  CheckEqualsInt64(2, FBpInt64List.Items[1], 'Second item should be 2');
  CheckEqualsInt64(3, FBpInt64List.Items[2], 'Third item should be 3');
end;

procedure TBpInt64ListTests.TestGetCommaTextBasic;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  FBpInt64List.Add(3);
  CheckEquals('1,2,3', FBpInt64List.CommaText, 'CommaText should correctly represent the list');
end;

procedure TBpInt64ListTests.TestSetCommaTextWithSpaces;
begin
  FBpInt64List.CommaText := '1, 2, 3';
  CheckEquals(3, FBpInt64List.Count, 'Count should be 3 after setting CommaText with spaces');
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should be 1');
  CheckEqualsInt64(2, FBpInt64List.Items[1], 'Second item should be 2');
end;

procedure TBpInt64ListTests.TestCommaTextWithQuotesRaisesException;
begin
  try
    FBpInt64List.CommaText := '"1,5",2,"3,4"';
    Fail('Expected exception not raised for CommaText with quotes');
  except
    on E: EConvertError do
      Check(True, 'Exception raised as expected for CommaText with quotes');
    else
      Check(False, 'Unexpected exception type raised');
  end;
end;

procedure TBpInt64ListTests.TestCountAfterAdd;
begin
  FBpInt64List.Add(10);
  CheckEquals(1, FBpInt64List.Count, 'Count should be 1 after adding one item');
end;

procedure TBpInt64ListTests.TestCountAfterMultipleAdds;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);
  CheckEquals(2, FBpInt64List.Count, 'Count should be 2 after adding two items');
end;

procedure TBpInt64ListTests.TestCountAfterDelete;
begin
  FBpInt64List.Add(10);
  FBpInt64List.Add(20);
  FBpInt64List.Delete(0);
  CheckEquals(1, FBpInt64List.Count, 'Count should be 1 after deleting one item');
end;

procedure TBpInt64ListTests.TestSetDelimitedText;
begin
  FBpInt64List.DelimitedText := '1,2,3';
  CheckEquals(3, FBpInt64List.Count, 'Count should be 3');
  CheckEqualsInt64(2, FBpInt64List.Items[1], 'The second item should be 2');
end;

procedure TBpInt64ListTests.TestGetDelimitedTextWithDefaultDelimiter;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  CheckEquals('1,2', FBpInt64List.DelimitedText, 'DelimitedText should be "1,2" with default delimiter');
end;

procedure TBpInt64ListTests.TestSetDelimiterAndDelimitedText;
begin
  FBpInt64List.Delimiter := ';';
  FBpInt64List.DelimitedText := '1;2';

  CheckEquals('1;2', FBpInt64List.DelimitedText, 'DelimitedText should respect the set delimiter ";"');
end;

procedure TBpInt64ListTests.TestClearAndResetDelimiter;
begin
  FBpInt64List.Delimiter := ';';
  FBpInt64List.Clear;
  FBpInt64List.Delimiter := ',';
  CheckEquals(',', FBpInt64List.Delimiter, 'Delimiter should be reset to "," after clearing and setting');
end;

procedure TBpInt64ListTests.TestDelimitedTextEmptyString;
begin
  FBpInt64List.DelimitedText := '';
  CheckEquals(0, FBpInt64List.Count, 'Count should be 0 for empty DelimitedText');
end;

procedure TBpInt64ListTests.TestDelimitedTextEndsWithDelimiter;
begin
  FBpInt64List.Delimiter := ',';
  FBpInt64List.DelimitedText := '1,2,3,';
  CheckEquals(3, FBpInt64List.Count, 'Count should be 3 even if DelimitedText ends with delimiter');
  CheckEqualsInt64(3, FBpInt64List.Items[2], 'Last item should be 3');
end;

procedure TBpInt64ListTests.TestDelimitedTextOnlyDelimiters;
begin
  FBpInt64List.Delimiter := ',';
  FBpInt64List.DelimitedText := ',,,';
  CheckEquals(0, FBpInt64List.Count, 'Count should be 0 if DelimitedText contains only delimiters');
end;

procedure TBpInt64ListTests.TestDelimitedTextWithConsecutiveDelimiters;
begin
  FBpInt64List.Delimiter := ',';
  FBpInt64List.DelimitedText := '1,,2';
  CheckEquals(2, FBpInt64List.Count, 'Count should be 2 with consecutive delimiters treated as single delimiter');
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should be 1');
  CheckEqualsInt64(2, FBpInt64List.Items[1], 'Second item should be 2');
end;

procedure TBpInt64ListTests.TestSortWithFewItems;
begin
  FBpInt64List.Add(2);
  FBpInt64List.Add(3);
  FBpInt64List.Add(1);
  FBpInt64List.Sort;
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should be 1 after sorting');
  CheckEqualsInt64(2, FBpInt64List.Items[1], 'Second item should be 2 after sorting');
  CheckEqualsInt64(3, FBpInt64List.Items[2], 'Third item should be 3 after sorting');
end;

procedure TBpInt64ListTests.TestSortWithIdenticalItems;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Add(1);
  FBpInt64List.Add(1);
  FBpInt64List.Sort;
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should be 1 after sorting');
  CheckEqualsInt64(1, FBpInt64List.Items[1], 'Second item should be 1 after sorting');
  CheckEqualsInt64(1, FBpInt64List.Items[2], 'Third item should be 1 after sorting');
end;

procedure TBpInt64ListTests.TestSortWithNegativeItems;
begin
  FBpInt64List.Add(-1);
  FBpInt64List.Add(-3);
  FBpInt64List.Add(-2);
  FBpInt64List.Sort;
  CheckEqualsInt64(-3, FBpInt64List.Items[0], 'First item should be -3 after sorting');
  CheckEqualsInt64(-2, FBpInt64List.Items[1], 'Second item should be -2 after sorting');
  CheckEqualsInt64(-1, FBpInt64List.Items[2], 'Third item should be -1 after sorting');
end;

procedure TBpInt64ListTests.TestSortAlreadySorted;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  FBpInt64List.Add(3);
  FBpInt64List.Sort;
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should still be 1 after sorting');
  CheckEqualsInt64(2, FBpInt64List.Items[1], 'Second item should still be 2 after sorting');
  CheckEqualsInt64(3, FBpInt64List.Items[2], 'Third item should still be 3 after sorting');
end;

procedure TBpInt64ListTests.TestLoadFromFileBasic;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'testfile64.txt';
  SavedText := TStringList.Create;
  try
    SavedText.Text := '1,2,3';
    SavedText.SaveToFile(FileName);

    FBpInt64List.LoadFromFile(FileName);
    CheckEquals(3, FBpInt64List.Count, 'Count should be 3 after loading from file');
  finally
    SysUtils.DeleteFile(FileName);
    SavedText.Free;
  end;
end;

procedure TBpInt64ListTests.TestLoadFromFileNonExisting;
begin
  try
    FBpInt64List.LoadFromFile('nonexistingfile.txt');
    Fail('Expected exception for non-existing file');
  except
    on E: Exception do
      Check(True, 'Exception raised as expected');
  end;
end;

procedure TBpInt64ListTests.TestSaveToFileBasic;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'savetofiletest64.txt';
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  FBpInt64List.Add(3);

  FBpInt64List.SaveToFile(FileName);

  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('1,2,3', TrimRight(SavedText.Text), 'File content should match the list content');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

procedure TBpInt64ListTests.TestSaveToFileWithDelimiterChange;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'delimitertest64.txt';
  FBpInt64List.Delimiter := ';';
  FBpInt64List.Add(1);
  FBpInt64List.Add(2);
  FBpInt64List.Add(3);

  FBpInt64List.SaveToFile(FileName);

  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('1;2;3', TrimRight(SavedText.Text), 'File content should respect the changed delimiter');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

procedure TBpInt64ListTests.TestSaveToFileEmptyList;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'emptylisttest64.txt';
  FBpInt64List.SaveToFile(FileName);

  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('', TrimRight(SavedText.Text), 'File content should be empty for an empty list');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

procedure TBpInt64ListTests.TestLoadFromFileWithInvalidFormat;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := 'invalidformat64.txt';
  SavedText := TStringList.Create;
  try
    SavedText.Text := 'not,a,number';
    SavedText.SaveToFile(FileName);

    try
      FBpInt64List.LoadFromFile(FileName);
      Fail('Expected exception for invalid content');
    except
      on E: EConvertError do
        Check(True, 'Exception raised as expected for invalid content');
    end;
  finally
    SysUtils.DeleteFile(FileName);
    SavedText.Free;
  end;
end;

procedure TBpInt64ListTests.TestLoadFromStreamBasic;
var
  MemoryStream: TMemoryStream;
  InputText: string;
begin
  InputText := '1,2,3';
  MemoryStream := TMemoryStream.Create;
  try
    with TStringList.Create do
    try
      Text := InputText;
      SaveToStream(MemoryStream);
    finally
      Free;
    end;
    MemoryStream.Position := 0; // reading must start after the write left it at the end

    FBpInt64List.LoadFromStream(MemoryStream);
  finally
    MemoryStream.Free;
  end;

  CheckEquals(3, FBpInt64List.Count, 'Count should be 3 after loading from stream');
end;

procedure TBpInt64ListTests.TestLoadFromStreamEmpty;
var
  MemoryStream: TMemoryStream;
begin
  MemoryStream := TMemoryStream.Create;
  try
    FBpInt64List.LoadFromStream(MemoryStream);
  finally
    MemoryStream.Free;
  end;

  CheckEquals(0, FBpInt64List.Count, 'Count should be 0 after loading from an empty stream');
end;

procedure TBpInt64ListTests.TestLoadFromStreamWithInvalidFormat;
var
  MemoryStream: TMemoryStream;
  InputText: string;
begin
  InputText := 'invalid,data';
  MemoryStream := TMemoryStream.Create;
  try
    with TStringList.Create do
    try
      Text := InputText;
      SaveToStream(MemoryStream);
    finally
      Free;
    end;
    MemoryStream.Position := 0; // reading must start after the write left it at the end

    try
      FBpInt64List.LoadFromStream(MemoryStream);
      Fail('Expected exception for invalid content');
    except
      on E: EConvertError do
        Check(True, 'Exception raised as expected for invalid content');
    end;
  finally
    MemoryStream.Free;
  end;
end;

procedure TBpInt64ListTests.TestSaveToStreamBasic;
var
  MemoryStream: TMemoryStream;
  OutputText: string;
begin
  MemoryStream := TMemoryStream.Create;
  try
    FBpInt64List.Add(1);
    FBpInt64List.Add(2);
    FBpInt64List.Add(3);
    FBpInt64List.SaveToStream(MemoryStream);

    // Verify the stream content
    SetString(OutputText, PAnsiChar(MemoryStream.Memory), MemoryStream.Size);
    CheckEquals('1,2,3', OutputText, 'Stream content should match the list content');
  finally
    MemoryStream.Free;
  end;
end;

procedure TBpInt64ListTests.TestSaveToStreamEmptyList;
var
  MemoryStream: TMemoryStream;
  OutputText: string;
begin
  MemoryStream := TMemoryStream.Create;
  try
    FBpInt64List.SaveToStream(MemoryStream);

    // Verify the stream is empty
    SetString(OutputText, PAnsiChar(MemoryStream.Memory), MemoryStream.Size);
    CheckEquals('', OutputText, 'Stream content should be empty for an empty list');
  finally
    MemoryStream.Free;
  end;
end;

procedure TBpInt64ListTests.TestLargeQuantities;
var
  I, N: Integer;
begin
  N := 1000000;
  for I := 1 to N do
    FBpInt64List.Add(I);
  CheckEquals(N, FBpInt64List.Count, Format('List should contain %d items', [N]));
  CheckEqualsInt64(1, FBpInt64List.Items[0], 'First item should be 1');
  CheckEqualsInt64(N div 2, FBpInt64List.Items[N div 2 - 1], 'Middle item should be ' + IntToStr(N div 2));
  CheckEqualsInt64(N, FBpInt64List.Items[N - 1], 'Last item should be ' + IntToStr(N));
end;

procedure TBpInt64ListTests.TestAddBeyondInt32Range;
begin
  FBpInt64List.Add(cAboveHighInt32);
  FBpInt64List.Add(cBelowLowInt32);
  FBpInt64List.Add(High(Int64));
  FBpInt64List.Add(Low(Int64));

  CheckEqualsInt64(cAboveHighInt32, FBpInt64List.Items[0], 'High(Integer) + 1 should survive Add');
  CheckEqualsInt64(cBelowLowInt32, FBpInt64List.Items[1], 'Low(Integer) - 1 should survive Add');
  CheckEqualsInt64(High(Int64), FBpInt64List.Items[2], 'High(Int64) should survive Add');
  CheckEqualsInt64(Low(Int64), FBpInt64List.Items[3], 'Low(Int64) should survive Add');

  CheckEquals(0, FBpInt64List.IndexOf(cAboveHighInt32), 'IndexOf should find High(Integer) + 1');
  CheckEquals(3, FBpInt64List.IndexOf(Low(Int64)), 'IndexOf should find Low(Int64)');
  CheckEquals(-1, FBpInt64List.IndexOf(High(Int64) - 1), 'IndexOf should return -1 for a near miss');
end;

procedure TBpInt64ListTests.TestSetItemBeyondInt32Range;
begin
  FBpInt64List.Add(1);
  FBpInt64List.Items[0] := Low(Int64);
  CheckEqualsInt64(Low(Int64), FBpInt64List.Items[0], 'Items setter should keep the full 64-bit value');
end;

procedure TBpInt64ListTests.TestExtremesDelimitedTextRoundTrip;
var
  lvText: string;
begin
  FBpInt64List.Add(High(Int64));
  FBpInt64List.Add(cAboveHighInt32);
  FBpInt64List.Add(cBelowLowInt32);
  FBpInt64List.Add(Low(Int64));
  lvText := FBpInt64List.DelimitedText;
  CheckEquals(cHighInt64Text + ',2147483648,-2147483649,' + cLowInt64Text, lvText,
    'DelimitedText should print the full 64-bit values');

  FBpInt64List.Clear;
  FBpInt64List.DelimitedText := lvText;
  CheckEquals(4, FBpInt64List.Count, 'Count should be 4 after the round trip');
  CheckEqualsInt64(High(Int64), FBpInt64List.Items[0], 'High(Int64) should round trip');
  CheckEqualsInt64(cAboveHighInt32, FBpInt64List.Items[1], 'High(Integer) + 1 should round trip');
  CheckEqualsInt64(cBelowLowInt32, FBpInt64List.Items[2], 'Low(Integer) - 1 should round trip');
  CheckEqualsInt64(Low(Int64), FBpInt64List.Items[3], 'Low(Int64) should round trip');
end;

procedure TBpInt64ListTests.TestExtremesCommaTextRoundTrip;
var
  lvText: string;
begin
  FBpInt64List.Delimiter := ';'; // CommaText must ignore the delimiter in use
  FBpInt64List.Add(Low(Int64));
  FBpInt64List.Add(High(Int64));
  lvText := FBpInt64List.CommaText;
  CheckEquals(cLowInt64Text + ',' + cHighInt64Text, lvText, 'CommaText should print the full 64-bit values');

  FBpInt64List.Clear;
  FBpInt64List.CommaText := lvText;
  CheckEquals(2, FBpInt64List.Count, 'Count should be 2 after the round trip');
  CheckEqualsInt64(Low(Int64), FBpInt64List.Items[0], 'Low(Int64) should round trip');
  CheckEqualsInt64(High(Int64), FBpInt64List.Items[1], 'High(Int64) should round trip');
end;

procedure TBpInt64ListTests.TestExtremesStreamRoundTrip;
var
  MemoryStream: TMemoryStream;
begin
  MemoryStream := TMemoryStream.Create;
  try
    FBpInt64List.Add(Low(Int64));
    FBpInt64List.Add(cBelowLowInt32);
    FBpInt64List.Add(cAboveHighInt32);
    FBpInt64List.Add(High(Int64));
    FBpInt64List.SaveToStream(MemoryStream);

    FBpInt64List.Clear;
    MemoryStream.Position := 0;
    FBpInt64List.LoadFromStream(MemoryStream);
  finally
    MemoryStream.Free;
  end;

  CheckEquals(4, FBpInt64List.Count, 'Count should be 4 after the stream round trip');
  CheckEqualsInt64(Low(Int64), FBpInt64List.Items[0], 'Low(Int64) should survive the stream');
  CheckEqualsInt64(cBelowLowInt32, FBpInt64List.Items[1], 'Low(Integer) - 1 should survive the stream');
  CheckEqualsInt64(cAboveHighInt32, FBpInt64List.Items[2], 'High(Integer) + 1 should survive the stream');
  CheckEqualsInt64(High(Int64), FBpInt64List.Items[3], 'High(Int64) should survive the stream');
end;

procedure TBpInt64ListTests.TestSortWithLargeMixedValues;
begin
  FBpInt64List.Add(cAboveHighInt32);
  FBpInt64List.Add(Low(Int64));
  FBpInt64List.Add(0);
  FBpInt64List.Add(High(Int64));
  FBpInt64List.Add(cBelowLowInt32);
  FBpInt64List.Sort;

  CheckEqualsInt64(Low(Int64), FBpInt64List.Items[0], 'Low(Int64) should sort first');
  CheckEqualsInt64(cBelowLowInt32, FBpInt64List.Items[1], 'Low(Integer) - 1 should sort second');
  CheckEqualsInt64(0, FBpInt64List.Items[2], 'Zero should sort in the middle');
  CheckEqualsInt64(cAboveHighInt32, FBpInt64List.Items[3], 'High(Integer) + 1 should sort fourth');
  CheckEqualsInt64(High(Int64), FBpInt64List.Items[4], 'High(Int64) should sort last');
end;

procedure TBpInt64ListTests.TestBinarySearchWithLargeMixedValues;
var
  FoundIndex: Integer;
begin
  FBpInt64List.Add(cAboveHighInt32);
  FBpInt64List.Add(Low(Int64));
  FBpInt64List.Add(0);
  FBpInt64List.Add(High(Int64));
  FBpInt64List.Add(cBelowLowInt32);
  FBpInt64List.Sorted := True;

  CheckTrue(FBpInt64List.BinarySearch(Low(Int64), FoundIndex), 'Low(Int64) should be found.');
  CheckEquals(0, FoundIndex, 'FoundIndex should be 0.');

  CheckTrue(FBpInt64List.BinarySearch(cBelowLowInt32, FoundIndex), 'Low(Integer) - 1 should be found.');
  CheckEquals(1, FoundIndex, 'FoundIndex should be 1.');

  CheckTrue(FBpInt64List.BinarySearch(High(Int64), FoundIndex), 'High(Int64) should be found.');
  CheckEquals(4, FoundIndex, 'FoundIndex should be 4.');

  CheckFalse(FBpInt64List.BinarySearch(High(Int64) - 1, FoundIndex), 'High(Int64) - 1 should not be found.');
  CheckEquals(4, FoundIndex, 'Insertion index should be 4.');

  // A value only Int64 can tell apart from the one stored next to it
  CheckFalse(FBpInt64List.BinarySearch(cAboveHighInt32 + 1, FoundIndex), 'Item should not be found.');
  CheckEquals(4, FoundIndex, 'Insertion index should be 4.');
end;

procedure TBpInt64ListTests.TestDelimitedTextAboveHighInt64Raises;
begin
  try
    FBpInt64List.DelimitedText := '1,9223372036854775808'; // High(Int64) + 1
    Fail('Expected EConvertError not raised for a value above High(Int64)');
  except
    on E: EConvertError do
      Check(True, 'Exception raised as expected for Int64 overflow');
  end;
end;

procedure TBpInt64ListTests.TestDelimitedTextBelowLowInt64Raises;
begin
  try
    FBpInt64List.DelimitedText := '-9223372036854775809,1'; // Low(Int64) - 1
    Fail('Expected EConvertError not raised for a value below Low(Int64)');
  except
    on E: EConvertError do
      Check(True, 'Exception raised as expected for Int64 underflow');
  end;
end;

procedure TBpInt64ListMemoryTests.SetUp;
begin
  inherited;
  {$IF CompilerVersion >= 18.0}
  System.ReportMemoryLeaksOnShutdown := True;
  {$IFEND}
end;

procedure TBpInt64ListMemoryTests.TestMemoryLeak;
var
  il: IBpInt64List;
begin
  il := TbpInt64List.Create;
  il.Add(1);
  il.Add(High(Int64));
  TestList(il);
end;

procedure TBpInt64ListMemoryTests.TestList(aList: IBpInt64List);
begin
  Status(Format('IBpInt64List.Count: %d', [aList.Count]));
end;

initialization
  RegisterTest(TBpInt64ListTests.Suite);
  RegisterTest(TBpInt64ListMemoryTests.Suite);

end.
