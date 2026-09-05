unit BpIntListTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, Classes, BpIntList, SysUtils;

type
  TBpIntListTests = class(TTestCase)
  private
    FBpIntList: TbpIntList;
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
    procedure TestFindEmptyList;
    procedure TestFindSingleElement;
    procedure TestFindMultipleElements;
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
    procedure TestAddReturnsInsertionIndexWhenSorted;
    procedure TestAddReturnsTailIndexWhenNotSorted;
    procedure TestSortedAddReturnedIndexHoldsTheItem;
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
    procedure TestLoadFromStreamHonoursPosition;
    procedure TestLoadFromStreamWithInvalidFormat;
    procedure TestSaveToStreamBasic;
    procedure TestSaveToStreamEmptyList;
    procedure TestSortThenFind;
    procedure TestSortOrganPipe;
    procedure TestFileRoundTripBetweenLists;
    procedure TestExchangeWhenSortedRaises;
    procedure TestInsertWhenSortedRaises;
    procedure TestSortReSortsAfterUncheckedWrite;
    procedure TestDelimitedTextWhitespaceSeparated;
    procedure TestDelimitedTextTabSeparated;
    procedure TestDelimitedTextSpaceBeforeDelimiter;
    procedure TestDelimitedTextWhitespaceOnly;
    procedure TestFindOnUnsortedListUsesTheIndex;
    procedure TestIndexOfReturnsFirstOfDuplicates;
    procedure TestIndexOfSurvivesAnAppend;
    procedure TestIndexOfAfterDeleteRebuilds;
    procedure TestIndexOfOnSortedListFindsFirstOfRun;
    procedure TestDuplicatesIgnoreDropsOnSortedAdd;
    procedure TestDuplicatesErrorRaisesOnSortedAdd;
    procedure TestDuplicatesAcceptKeepsTheRun;
    procedure TestDeleteFromSortedList;
    procedure TestCapacityBelowCountRaises;
    procedure TestCapacityPresizesWithoutChangingCount;
    procedure TestAssignCopiesContentAndFlags;
    procedure TestSameAs;
    procedure TestLoadFromStreamSkipsUtf8Bom;
    procedure TestLoadFromStreamRejectsUtf16;
    procedure TestDelimitedTextLineSeparated;
  end;

implementation

uses
  Windows;

var
  gvFileCounter: Integer = 0;

// a fixture path nothing else can claim, so two runs at once do not collide
function TempFilePath(const aName: string): string;
var
  lvDir: array[0..MAX_PATH] of Char;
begin
  SetString(Result, lvDir, GetTempPath(Length(lvDir), lvDir));
  Inc(gvFileCounter);
  Result := Format('%sBpIntList_%d_%d_%s', [Result, GetCurrentProcessId,
    gvFileCounter, aName]);
end;

procedure TBpIntListTests.SetUp;
begin
  FBpIntList := TbpIntList.Create;
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
  FBpIntList.Delete(0);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting first item');
  CheckEquals(20, FBpIntList.Items[0], 'The first item should now be 20');
end;

procedure TBpIntListTests.TestDeleteLastItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Delete(FBpIntList.Count - 1);
  CheckEquals(1, FBpIntList.Count, 'Count should be 1 after deleting last item');
  CheckEquals(10, FBpIntList.Items[0], 'The remaining item should be 10');
end;

procedure TBpIntListTests.TestDeleteWithInvalidIndex;
begin
  try
    FBpIntList.Delete(-1);
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
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

procedure TBpIntListTests.TestFindEmptyList;
var
  FoundIndex: Integer;
begin
  FBpIntList.Sorted := True;
  CheckFalse(FBpIntList.Find(10, FoundIndex), 'Search in an empty list should return False.');
end;

procedure TBpIntListTests.TestFindSingleElement;
var
  FoundIndex: Integer;
begin
  FBpIntList.Add(5);
  FBpIntList.Sorted := True;
  CheckTrue(FBpIntList.Find(5, FoundIndex), 'Item should be found.');
  CheckEquals(0, FoundIndex, 'FoundIndex should be 0.');

  CheckFalse(FBpIntList.Find(3, FoundIndex), 'Item should not be found.');
  CheckEquals(0, FoundIndex, 'Insertion index should be 0 for a smaller element.');
end;

procedure TBpIntListTests.TestFindMultipleElements;
var
  FoundIndex: Integer;
begin
  FBpIntList.Add(5);
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Sorted := True;

  CheckTrue(FBpIntList.Find(10, FoundIndex), 'Item should be found.');
  CheckEquals(1, FoundIndex, 'FoundIndex should be 1.');

  CheckFalse(FBpIntList.Find(15, FoundIndex), 'Item should not be found.');
  CheckEquals(2, FoundIndex, 'Insertion index should be 2.');

  CheckTrue(FBpIntList.Find(5, FoundIndex), 'First element should be found.');
  CheckEquals(0, FoundIndex, 'FoundIndex should be 0.');

  CheckTrue(FBpIntList.Find(20, FoundIndex), 'Last element should be found.');
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
    FBpIntList.Exchange(0, 2);
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
  end;
end;

procedure TBpIntListTests.TestExchangeWithEmptyList;
begin
  try
    FBpIntList.Exchange(0, 1);
    Fail('Expected EListError not raised for empty list');
  except
    on E: EListError do
      ; // expected
  end;
end;

procedure TBpIntListTests.TestInsert;
begin
  FBpIntList.Add(10);
  FBpIntList.Add(30);
  FBpIntList.Insert(1, 20);
  CheckEquals(3, FBpIntList.Count, 'Count should be 3 after insert');
  CheckEquals(20, FBpIntList.Items[1], 'The inserted item should be at index 1');
end;

procedure TBpIntListTests.TestInsertAtBeginning;
begin
  FBpIntList.Add(10);
  FBpIntList.Insert(0, 5);
  CheckEquals(5, FBpIntList.Items[0], 'The inserted item should be the first item');
end;

procedure TBpIntListTests.TestInsertAtEnd;
begin
  FBpIntList.Add(10);
  FBpIntList.Insert(1, 20);
  CheckEquals(20, FBpIntList.Items[1], 'The inserted item should be the last item');
end;

procedure TBpIntListTests.TestInsertRandomPositions;
var
  I, Pos: Integer;
begin
  for I := 1 to 100 do
    FBpIntList.Add(I * 10);

  for I := 1 to 20 do
  begin
    Pos := Random(FBpIntList.Count + 1);
    FBpIntList.Insert(Pos, 999);
  end;

  CheckEquals(120, FBpIntList.Count, 'Count should be 120 after inserts');
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
    FBpIntList.Insert(-1, 10);
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
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

procedure TBpIntListTests.TestSetItem;
begin
  FBpIntList.Add(10);
  FBpIntList.Items[0] := 20;
  CheckEquals(20, FBpIntList.Items[0], 'Item at index 0 should be set to 20');
end;

procedure TBpIntListTests.TestGetItemWithInvalidIndex;
begin
  try
    FBpIntList.Items[-1];
    Fail('Expected EListError not raised for invalid index');
  except
    on E: EListError do
      ; // expected
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
  FileName := TempFilePath('testfile.txt');
  SavedText := TStringList.Create;
  try
    SavedText.Text := '1,2,3';
    SavedText.SaveToFile(FileName);

    FBpIntList.LoadFromFile(FileName);
    CheckEquals(3, FBpIntList.Count, 'Count should be 3 after loading from file');
  finally
    SysUtils.DeleteFile(FileName);
    SavedText.Free;
  end;
end;

procedure TBpIntListTests.TestLoadFromFileNonExisting;
begin
  try
    FBpIntList.LoadFromFile('nonexistingfile.txt');
    Fail('Expected exception for non-existing file');
  except
    // narrow, or Fail is caught by its own handler
    on E: EFOpenError do
      Check(True, 'Exception raised as expected');
  end;
end;

procedure TBpIntListTests.TestSaveToFileBasic;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := TempFilePath('savetofiletest.txt');
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Add(3);

  FBpIntList.SaveToFile(FileName);

  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('1,2,3', TrimRight(SavedText.Text), 'File content should match the list content');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

procedure TBpIntListTests.TestSaveToFileWithDelimiterChange;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := TempFilePath('delimitertest.txt');
  FBpIntList.Delimiter := ';';
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Add(3);

  FBpIntList.SaveToFile(FileName);

  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('1;2;3', TrimRight(SavedText.Text), 'File content should respect the changed delimiter');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

procedure TBpIntListTests.TestSaveToFileEmptyList;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := TempFilePath('emptylisttest.txt');
  FBpIntList.SaveToFile(FileName);

  SavedText := TStringList.Create;
  try
    SavedText.LoadFromFile(FileName);
    CheckEquals('', TrimRight(SavedText.Text), 'File content should be empty for an empty list');
  finally
    SavedText.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

procedure TBpIntListTests.TestLoadFromFileWithInvalidFormat;
var
  FileName: string;
  SavedText: TStringList;
begin
  FileName := TempFilePath('invalidformat.txt');
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
    SysUtils.DeleteFile(FileName);
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
    with TStringList.Create do
    try
      Text := InputText;
      SaveToStream(MemoryStream);
    finally
      Free;
    end;
    MemoryStream.Position := 0; // reading must start after the write left it at the end

    FBpIntList.LoadFromStream(MemoryStream);
  finally
    MemoryStream.Free;
  end;

  CheckEquals(3, FBpIntList.Count, 'Count should be 3 after loading from stream');
end;

procedure TBpIntListTests.TestLoadFromStreamHonoursPosition;
var
  MemoryStream: TMemoryStream;
  Payload: AnsiString;
begin
  // a header ahead of the payload, the way a container format writes it
  Payload := 'HDR' + '7,8,9';
  MemoryStream := TMemoryStream.Create;
  try
    MemoryStream.WriteBuffer(Payload[1], Length(Payload));
    MemoryStream.Position := 3;
    FBpIntList.LoadFromStream(MemoryStream);
  finally
    MemoryStream.Free;
  end;

  CheckEquals(3, FBpIntList.Count, 'reading must start at the caller position');
  CheckEquals(7, FBpIntList[0]);
  CheckEquals(9, FBpIntList[2]);
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
    with TStringList.Create do
    try
      Text := InputText;
      SaveToStream(MemoryStream);
    finally
      Free;
    end;
    MemoryStream.Position := 0; // reading must start after the write left it at the end

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

    // bytes, not UTF-16 elements
    CheckEquals(5, MemoryStream.Size, 'Stream should hold the text as bytes');
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

procedure TBpIntListTests.TestAddReturnsInsertionIndexWhenSorted;
begin
  FBpIntList.Sorted := True;
  CheckEquals(0, FBpIntList.Add(5), 'the first item lands at 0');
  CheckEquals(0, FBpIntList.Add(3), 'a smaller item lands at 0, not at the tail');
  CheckEquals(2, FBpIntList.Add(9), 'a larger item lands at the tail');
  CheckEquals(0, FBpIntList.Add(1), 'the smallest item lands at 0');
  CheckEquals('1,3,5,9', FBpIntList.CommaText, 'the list stays ordered');
end;

procedure TBpIntListTests.TestAddReturnsTailIndexWhenNotSorted;
begin
  CheckEquals(0, FBpIntList.Add(7), 'first');
  CheckEquals(1, FBpIntList.Add(2), 'second');
  CheckEquals(2, FBpIntList.Add(9), 'third');
end;

// the contract is Items[Add(x)] = x, duplicates included
procedure TBpIntListTests.TestSortedAddReturnedIndexHoldsTheItem;
var
  i, lvIndex: Integer;
  lvValue: Integer;
begin
  FBpIntList.Sorted := True;
  RandSeed := 42;
  for i := 1 to 200 do
  begin
    lvValue := Random(50);
    lvIndex := FBpIntList.Add(lvValue);
    CheckEquals(lvValue, FBpIntList.Items[lvIndex], 'Add must return the index the item landed at');
  end;
  for i := 1 to FBpIntList.Count - 1 do
    Check(FBpIntList.Items[i - 1] <= FBpIntList.Items[i], 'the list stays ordered');
end;



procedure TBpIntListTests.TestSortThenFind;
var
  lvFound: Integer;
begin
  // the FEATURES.md flow: Sorted := True, not a bare Sort, then search
  FBpIntList.Add(30);
  FBpIntList.Add(10);
  FBpIntList.Add(20);
  FBpIntList.Sorted := True;
  CheckTrue(FBpIntList.Find(20, lvFound), '20 is in the list');
  CheckEquals(1, lvFound);
  CheckFalse(FBpIntList.Find(25, lvFound), '25 is not');
  CheckEquals(2, lvFound, 'a miss reports where it would go');
end;

procedure TBpIntListTests.TestSortOrganPipe;
const
  lcCount = 200000;
var
  i: Integer;
begin
  // organ pipe: the shape that made the old recursion go quadratic and blow
  // the stack. Anything but introsort dies here rather than failing an assert.
  for i := 0 to lcCount - 1 do
    if i < lcCount div 2 then
      FBpIntList.Add(i)
    else
      FBpIntList.Add(lcCount - i);
  FBpIntList.Sort;
  CheckEquals(lcCount, FBpIntList.Count);
  for i := 1 to FBpIntList.Count - 1 do
    if FBpIntList.Items[i - 1] > FBpIntList.Items[i] then
      Fail(Format('out of order at %d', [i]));
end;

procedure TBpIntListTests.TestFileRoundTripBetweenLists;
var
  lvFileName: string;
  lvOther: TbpIntList;
  i: Integer;
begin
  lvFileName := TempFilePath('roundtrip.txt');
  for i := 1 to 50 do
    FBpIntList.Add(i * 7 - 100);
  lvOther := TbpIntList.Create;
  try
    FBpIntList.SaveToFile(lvFileName);
    lvOther.LoadFromFile(lvFileName);
    CheckEquals(FBpIntList.Count, lvOther.Count, 'same count after the round trip');
    CheckEquals(FBpIntList.CommaText, lvOther.CommaText, 'same values in the same order');
  finally
    lvOther.Free;
    SysUtils.DeleteFile(lvFileName);
  end;
end;

// Sorted is an invariant, not a hint: an unchecked write is refused
procedure TBpIntListTests.TestSetItemWhenSorted;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(3);
  FBpIntList.Sorted := True;
  try
    FBpIntList.Items[1] := 2;
    Fail('Expected EListError for Items[] on a sorted list');
  except
    on E: EListError do
      ;
  end;
  CheckEquals(3, FBpIntList.Items[1], 'the list must be untouched after the refusal');
end;

procedure TBpIntListTests.TestExchangeWhenSortedRaises;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Sorted := True;
  try
    FBpIntList.Exchange(0, 1);
    Fail('Expected EListError for Exchange on a sorted list');
  except
    on E: EListError do
      ;
  end;
  CheckEquals(1, FBpIntList.Items[0], 'the order must survive the refusal');
end;

procedure TBpIntListTests.TestInsertWhenSortedRaises;
begin
  FBpIntList.Sorted := True;
  FBpIntList.Add(10);
  try
    FBpIntList.Insert(0, 20);
    Fail('Expected EListError for Insert on a sorted list');
  except
    on E: EListError do
      ;
  end;
  CheckEquals(1, FBpIntList.Count, 'nothing may be inserted');
  // Add is still the sorted entry point
  FBpIntList.Add(5);
  CheckEquals(5, FBpIntList.Items[0], 'Add must still insert in order');
end;

// Sort is the repair path once Sorted goes back off, so it may not skip
procedure TBpIntListTests.TestSortReSortsAfterUncheckedWrite;
begin
  FBpIntList.Sorted := True;
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  FBpIntList.Add(3);
  FBpIntList.Sorted := False;
  FBpIntList.Items[0] := 99;
  FBpIntList.Sort;
  CheckEquals(2, FBpIntList.Items[0], 'Sort must re-sort, not exit early');
  CheckEquals(3, FBpIntList.Items[1], 'second item after the re-sort');
  CheckEquals(99, FBpIntList.Items[2], 'the written value ends up last');
end;


procedure TBpIntListTests.TestDelimitedTextWhitespaceSeparated;
begin
  FBpIntList.DelimitedText := '1 2 3';
  CheckEquals(3, FBpIntList.Count, 'whitespace separates values, as in TStringList');
  CheckEquals(1, FBpIntList.Items[0], 'first value');
  CheckEquals(3, FBpIntList.Items[2], 'last value');
end;

procedure TBpIntListTests.TestDelimitedTextTabSeparated;
begin
  FBpIntList.DelimitedText := '1'#9'2'#9#9'3';
  CheckEquals(3, FBpIntList.Count, 'tabs separate values too');
  CheckEquals(2, FBpIntList.Items[1], 'second value');
end;

procedure TBpIntListTests.TestDelimitedTextSpaceBeforeDelimiter;
begin
  FBpIntList.DelimitedText := '1 ,2, 3';
  CheckEquals(3, FBpIntList.Count, 'a space before the delimiter is not part of the value');
  CheckEquals(3, FBpIntList.Items[2], 'last value');
end;

procedure TBpIntListTests.TestDelimitedTextWhitespaceOnly;
begin
  FBpIntList.DelimitedText := '   '#9;
  CheckEquals(0, FBpIntList.Count, 'whitespace-only input is an empty list, not an error');
end;

// the hash index answers where the old linear scan did
procedure TBpIntListTests.TestFindOnUnsortedListUsesTheIndex;
var
  lvIndex: Integer;
begin
  FBpIntList.Add(30);
  FBpIntList.Add(10);
  CheckTrue(FBpIntList.Find(10, lvIndex), 'an unsorted list still answers Find');
  CheckEquals(1, lvIndex, 'the position of the item, not an insertion point');
  CheckFalse(FBpIntList.Find(99, lvIndex), 'a miss stays a miss');
  CheckEquals(2, lvIndex, 'a miss reports Count');
end;

procedure TBpIntListTests.TestIndexOfReturnsFirstOfDuplicates;
var
  i: Integer;
begin
  for i := 0 to 9 do
    FBpIntList.Add(7);
  FBpIntList.Add(8);
  CheckEquals(0, FBpIntList.IndexOf(7), 'the lowest position among equal items');
  CheckEquals(10, FBpIntList.IndexOf(8), 'and the only position of a unique one');
end;

// an append is the one mutation the index survives, so the answer must stay right
procedure TBpIntListTests.TestIndexOfSurvivesAnAppend;
var
  i: Integer;
begin
  for i := 0 to 99 do
    FBpIntList.Add(i);
  CheckEquals(50, FBpIntList.IndexOf(50), 'builds the index');
  for i := 100 to 999 do
    FBpIntList.Add(i);
  CheckEquals(50, FBpIntList.IndexOf(50), 'an item from before the appends');
  CheckEquals(999, FBpIntList.IndexOf(999), 'and one appended after the build');
  CheckEquals(-1, FBpIntList.IndexOf(1000), 'a value that was never added');
end;

procedure TBpIntListTests.TestIndexOfAfterDeleteRebuilds;
var
  i: Integer;
begin
  for i := 0 to 99 do
    FBpIntList.Add(i);
  CheckEquals(50, FBpIntList.IndexOf(50), 'builds the index');
  FBpIntList.Delete(0);
  CheckEquals(49, FBpIntList.IndexOf(50), 'every position above the gap moved by one');
  FBpIntList.Insert(0, 500);
  CheckEquals(50, FBpIntList.IndexOf(50), 'and back again after an insert at the head');
  CheckEquals(0, FBpIntList.IndexOf(500), 'the inserted value is findable too');
end;

procedure TBpIntListTests.TestIndexOfOnSortedListFindsFirstOfRun;
var
  i: Integer;
begin
  FBpIntList.Duplicates := dupAccept;
  FBpIntList.Sorted := True;
  FBpIntList.Add(1);
  for i := 0 to 4 do
    FBpIntList.Add(5);
  FBpIntList.Add(9);
  CheckEquals(7, FBpIntList.Count, 'the run is kept');
  CheckEquals(1, FBpIntList.IndexOf(5), 'the first of the equal run, not any of it');
  CheckEquals(0, FBpIntList.IndexOf(1), 'first');
  CheckEquals(6, FBpIntList.IndexOf(9), 'last');
  CheckEquals(-1, FBpIntList.IndexOf(4), 'a value between two present ones');
end;

procedure TBpIntListTests.TestDuplicatesIgnoreDropsOnSortedAdd;
begin
  FBpIntList.Sorted := True;
  CheckEquals(0, FBpIntList.Add(5), 'the first 5 lands at 0');
  CheckEquals(0, FBpIntList.Add(5), 'the second returns the position of the first');
  CheckEquals(1, FBpIntList.Count, 'dupIgnore is the default, as in TStringList');
end;

procedure TBpIntListTests.TestDuplicatesErrorRaisesOnSortedAdd;
begin
  FBpIntList.Duplicates := dupError;
  FBpIntList.Sorted := True;
  FBpIntList.Add(5);
  try
    FBpIntList.Add(5);
    Fail('dupError must refuse an equal item');
  except
    on E: EListError do
      ; // expected
  end;
  CheckEquals(1, FBpIntList.Count, 'and must not have added it');
end;

// Duplicates is read by Add on a Sorted list only, as in TStringList
procedure TBpIntListTests.TestDuplicatesAcceptKeepsTheRun;
begin
  FBpIntList.Duplicates := dupError;
  FBpIntList.Add(5);
  FBpIntList.Add(5);
  CheckEquals(2, FBpIntList.Count, 'an unsorted list ignores Duplicates entirely');
  FBpIntList.Clear;
  FBpIntList.Duplicates := dupAccept;
  FBpIntList.Sorted := True;
  FBpIntList.Add(5);
  FBpIntList.Add(5);
  CheckEquals(2, FBpIntList.Count, 'dupAccept keeps both');
end;

procedure TBpIntListTests.TestDeleteFromSortedList;
var
  lvIndex: Integer;
begin
  FBpIntList.CommaText := '5,3,9,1';
  FBpIntList.Sorted := True;
  CheckTrue(FBpIntList.Find(5, lvIndex), 'the value is there before the delete');
  FBpIntList.Delete(lvIndex);
  CheckEquals('1,3,9', FBpIntList.CommaText, 'the rest keeps its order');
  CheckFalse(FBpIntList.Find(5, lvIndex), 'and the value is gone');
  CheckEquals(2, lvIndex, 'a miss reports the insertion point');
end;

procedure TBpIntListTests.TestCapacityBelowCountRaises;
begin
  FBpIntList.Add(1);
  FBpIntList.Add(2);
  try
    FBpIntList.Capacity := 1;
    Fail('shrinking below Count would drop values in silence');
  except
    on E: EListError do
      ; // expected
  end;
  CheckEquals(2, FBpIntList.Count, 'and nothing was dropped');
end;

procedure TBpIntListTests.TestCapacityPresizesWithoutChangingCount;
begin
  FBpIntList.Capacity := 1000;
  CheckEquals(1000, FBpIntList.Capacity, 'a list of known size can be presized');
  CheckEquals(0, FBpIntList.Count, 'which adds no items');
  FBpIntList.Add(1);
  CheckEquals(1000, FBpIntList.Capacity, 'and the first Add does not grow');
end;

procedure TBpIntListTests.TestAssignCopiesContentAndFlags;
var
  lvOther: TbpIntList;
begin
  lvOther := TbpIntList.Create;
  try
    FBpIntList.Delimiter := ';';
    FBpIntList.Duplicates := dupError;
    FBpIntList.CommaText := '3,1,2';
    FBpIntList.Sorted := True;
    lvOther.Assign(FBpIntList);
    CheckEquals('1;2;3', lvOther.DelimitedText, 'the values and the delimiter come across');
    CheckTrue(lvOther.Sorted, 'and so does Sorted');
    Check(lvOther.Duplicates = dupError, 'and Duplicates');
    CheckTrue(lvOther.SameAs(FBpIntList), 'the copy has the same content');
  finally
    lvOther.Free;
  end;
end;

procedure TBpIntListTests.TestSameAs;
var
  lvOther: TbpIntList;
begin
  lvOther := TbpIntList.Create;
  try
    CheckTrue(FBpIntList.SameAs(lvOther), 'two empty lists');
    CheckFalse(FBpIntList.SameAs(nil), 'nil is never equal');
    FBpIntList.CommaText := '1,2,3';
    CheckFalse(FBpIntList.SameAs(lvOther), 'different counts');
    lvOther.CommaText := '1,2,4';
    CheckFalse(FBpIntList.SameAs(lvOther), 'same count, different values');
    lvOther.CommaText := '1,2,3';
    CheckTrue(FBpIntList.SameAs(lvOther), 'same content');
  finally
    lvOther.Free;
  end;
end;

procedure TBpIntListTests.TestLoadFromStreamSkipsUtf8Bom;
var
  lvStream: TMemoryStream;
  lvText: AnsiString;
begin
  lvText := #$EF#$BB#$BF + '1,2,3';
  lvStream := TMemoryStream.Create;
  try
    lvStream.WriteBuffer(lvText[1], Length(lvText));
    lvStream.Position := 0;
    FBpIntList.LoadFromStream(lvStream);
  finally
    lvStream.Free;
  end;
  CheckEquals('1,2,3', FBpIntList.CommaText, 'a BOM is not part of the first number');
end;

procedure TBpIntListTests.TestLoadFromStreamRejectsUtf16;
var
  lvStream: TMemoryStream;
  lvText: AnsiString;
begin
  // '1,2,3' as UTF-16LE: the NUL bytes used to end the parse after the first value
  lvText := '1'#0','#0'2'#0','#0'3'#0;
  lvStream := TMemoryStream.Create;
  try
    lvStream.WriteBuffer(lvText[1], Length(lvText));
    lvStream.Position := 0;
    try
      FBpIntList.LoadFromStream(lvStream);
      Fail('a NUL byte must be reported, not silently end the parse');
    except
      on E: EConvertError do
        ; // expected
    end;
  finally
    lvStream.Free;
  end;
end;

procedure TBpIntListTests.TestDelimitedTextLineSeparated;
begin
  FBpIntList.DelimitedText := '10'#13#10'20'#13#10'30';
  CheckEquals(3, FBpIntList.Count, 'one value per line loads without a delimiter in sight');
  CheckEquals('10,20,30', FBpIntList.CommaText, 'in file order');
end;

initialization
  RegisterTest(TBpIntListTests.Suite);

end.

