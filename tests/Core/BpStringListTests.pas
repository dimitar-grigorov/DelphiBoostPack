unit BpStringListTests;

interface

uses
  TestFramework, Windows, Classes, SysUtils, BpKeyFold, BpStringList;

type
  TBpStringListTests = class(TTestCase)
  private
    FList: TbpStringList;
    FRef: TStringList;
    FChangingHits: Integer;
    FChangeHits: Integer;
    FHandlerValue: string;
    procedure CountChanging(Sender: TObject);
    procedure CountChange(Sender: TObject);
    procedure LookupOnChange(Sender: TObject);
    procedure AppendOnChange(Sender: TObject);
    procedure DeleteOnChanging(Sender: TObject);
    // every mutation goes to both, so TStringList is the oracle where the two agree
    procedure BothAdd(const aStr: string);
    procedure BothInsert(aIndex: Integer; const aStr: string);
    procedure BothDelete(aIndex: Integer);
    procedure BothPut(aIndex: Integer; const aStr: string);
    procedure CheckSameAnswers(const aWhat: string; aUseNames: Boolean);
    procedure CheckEveryLookup(const aWhat: string);
    function MakeKey(aIndex: Integer): string;
    procedure ExpectSortedError(const aWhat: string);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // against the oracle
    procedure TestIndexOfMatchesStringList;
    procedure TestIndexOfNameMatchesStringList;
    procedure TestCaseSensitiveMatchesStringList;
    procedure TestRandomOperationsMatchStringList;
    procedure TestSortedListMatchesStringList;
    procedure TestSortedRandomOperationsMatchStringList;
    procedure TestValuesReadAndWrite;
    procedure TestAssignFromStringList;
    procedure TestAssignCopiesTheFlagsAndResorts;
    procedure TestTextRoundTrip;
    procedure TestAddStringsKeepsTheIndexCorrect;
    procedure TestSaveAndLoadRoundTrip;
    procedure TestNonAsciiCaseFolding;
    procedure TestUsableThroughATStringsParameter;
    // the index
    procedure TestIndexOfEmptyList;
    procedure TestEmptyStringIsAKey;
    procedure TestRowWithoutSeparatorIsNotAName;
    procedure TestDuplicatesAnswerWithTheFirst;
    procedure TestDeleteKeepsTheIndexCorrect;
    procedure TestInsertInTheMiddleKeepsTheIndexCorrect;
    procedure TestExchangeKeepsTheIndexCorrect;
    procedure TestMoveKeepsTheIndexCorrect;
    procedure TestManyCollisions;
    procedure TestFreedSlotsAreReused;
    procedure TestCaseSensitiveFlipRebuilds;
    procedure TestNameValueSeparatorChangeRebuilds;
    procedure TestObjectsFollowTheirRows;
    procedure TestClearResetsEverything;
    procedure TestCapacity;
    // the relation
    procedure TestSortOrderIsOrdinal;
    procedure TestSortIsStable;
    procedure TestCustomSortSeesPreSortPositions;
    procedure TestCaseSensitiveFlipResortsASortedList;
    // Sorted and Duplicates
    procedure TestFindOnASortedList;
    procedure TestFindOnAnUnsortedListIsIndexOf;
    procedure TestSortedDuplicatesKeepInsertionOrder;
    procedure TestSortedIgnoresDuplicates;
    procedure TestSortedRejectsDuplicatesWhenAsked;
    procedure TestDuplicatesOnlyMatterWhenSorted;
    procedure TestSortedListRefusesReordering;
    procedure TestSettingSortedSortsOnce;
    // notifications
    procedure TestChangingAndChangedFireOnce;
    procedure TestBeginUpdateSuppressesNotifications;
    procedure TestLookupFromAChangeHandler;
    procedure TestNestedMutationFromAChangeHandler;
    procedure TestMutationFromAChangingHandlerRaises;
    procedure TestClearReleasesSlotsEmptiedRowByRow;
  end;

implementation

// sorts by the value part of a Name=Value row, as an integer
function CompareByValue(aList: TbpStringList; aIndex1, aIndex2: Integer): Integer;
begin
  Result := StrToInt(aList.ValueFromIndex[aIndex1]) - StrToInt(aList.ValueFromIndex[aIndex2]);
end;

// sorts by the length of the row, so equal lengths test stability
function CompareByLength(aList: TbpStringList; aIndex1, aIndex2: Integer): Integer;
begin
  Result := Length(aList[aIndex1]) - Length(aList[aIndex2]);
end;

procedure TBpStringListTests.SetUp;
begin
  inherited;
  FList := TbpStringList.Create;
  FRef := TStringList.Create;
end;

procedure TBpStringListTests.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FRef);
  inherited;
end;

// three case variants of one shape: folding is exercised everywhere, and the folded
// ordinal order still matches the locale, so TStringList stays a valid oracle for Text
function TBpStringListTests.MakeKey(aIndex: Integer): string;
begin
  case aIndex mod 3 of
    0: Result := Format('Key_%.4d_ab', [aIndex]);
    1: Result := Format('KEY_%.4d_AB', [aIndex]);
  else
    Result := Format('key_%.4d_Ab', [aIndex]);
  end;
end;

procedure TBpStringListTests.BothAdd(const aStr: string);
begin
  FRef.Add(aStr);
  FList.Add(aStr);
end;

procedure TBpStringListTests.BothInsert(aIndex: Integer; const aStr: string);
begin
  FRef.Insert(aIndex, aStr);
  FList.Insert(aIndex, aStr);
end;

procedure TBpStringListTests.BothDelete(aIndex: Integer);
begin
  FRef.Delete(aIndex);
  FList.Delete(aIndex);
end;

procedure TBpStringListTests.BothPut(aIndex: Integer; const aStr: string);
begin
  FRef[aIndex] := aStr;
  FList[aIndex] := aStr;
end;

// the contents, then every lookup answer, against the oracle
procedure TBpStringListTests.CheckSameAnswers(const aWhat: string; aUseNames: Boolean);
var
  i: Integer;
  lvKey: string;
begin
  CheckEquals(FRef.Count, FList.Count, aWhat + ': Count');
  CheckEquals(FRef.Text, FList.Text, aWhat + ': Text');
  for i := 0 to 60 do
  begin
    lvKey := MakeKey(i);
    if aUseNames then
    begin
      CheckEquals(FRef.IndexOfName(lvKey), FList.IndexOfName(lvKey), aWhat + ': IndexOfName(' + lvKey + ')');
      CheckEquals(FRef.Values[lvKey], FList.Values[lvKey], aWhat + ': Values[' + lvKey + ']');
    end
    else
      CheckEquals(FRef.IndexOf(lvKey), FList.IndexOf(lvKey), aWhat + ': IndexOf(' + lvKey + ')');
  end;
end;

// every row finds itself at the first position holding an equal string
procedure TBpStringListTests.CheckEveryLookup(const aWhat: string);
var
  i, j, lvExpected: Integer;
begin
  for i := 0 to FList.Count - 1 do
  begin
    lvExpected := i;
    for j := 0 to i - 1 do
      if BpKeyEquals(FList[j], FList[i], not FList.CaseSensitive) then
      begin
        lvExpected := j;
        Break;
      end;
    CheckEquals(lvExpected, FList.IndexOf(FList[i]), aWhat + ': row ' + IntToStr(i));
  end;
end;

procedure TBpStringListTests.ExpectSortedError(const aWhat: string);
begin
  Fail(aWhat + ' must raise EStringListError on a sorted list');
end;

// against the oracle

procedure TBpStringListTests.TestIndexOfMatchesStringList;
var
  i: Integer;
begin
  for i := 0 to 40 do
    BothAdd(MakeKey(i));
  CheckSameAnswers('plain adds', False);
end;

procedure TBpStringListTests.TestIndexOfNameMatchesStringList;
var
  i: Integer;
begin
  for i := 0 to 40 do
    BothAdd(MakeKey(i) + '=' + IntToStr(i));
  CheckSameAnswers('name=value adds', True);
end;

procedure TBpStringListTests.TestCaseSensitiveMatchesStringList;
var
  i: Integer;
begin
  FRef.CaseSensitive := True;
  FList.CaseSensitive := True;
  for i := 0 to 40 do
    BothAdd(MakeKey(i));
  CheckSameAnswers('case sensitive', False);
  for i := 0 to 60 do
    CheckEquals(FRef.IndexOf(LowerCase(MakeKey(i))), FList.IndexOf(LowerCase(MakeKey(i))), 'lower cased probe');
end;

// keys differ only in digits, where the collation and the ordinal order agree,
// so even the sorts can be compared
procedure TBpStringListTests.TestRandomOperationsMatchStringList;
var
  lvOp, i, lvIdx, lvNew: Integer;
begin
  RandSeed := 20260829;
  for lvOp := 1 to 800 do
  begin
    i := Random(60);
    case Random(9) of
      0, 1, 2: BothAdd(MakeKey(i));
      3: if FRef.Count > 0 then BothInsert(Random(FRef.Count + 1), MakeKey(i));
      4: if FRef.Count > 0 then BothDelete(Random(FRef.Count));
      5: if FRef.Count > 0 then BothPut(Random(FRef.Count), MakeKey(i));
      6: if FRef.Count > 1 then
         begin
           lvIdx := Random(FRef.Count - 1);
           FRef.Exchange(lvIdx, lvIdx + 1);
           FList.Exchange(lvIdx, lvIdx + 1);
         end;
      7: if FRef.Count > 1 then
         begin
           lvIdx := Random(FRef.Count);
           lvNew := Random(FRef.Count);
           FRef.Move(lvIdx, lvNew);
           FList.Move(lvIdx, lvNew);
         end;
      8: if lvOp mod 71 = 0 then
         begin
           FRef.Sort;
           FList.Sort;
         end;
    end;
    if lvOp mod 25 = 0 then
    begin
      CheckSameAnswers('random op ' + IntToStr(lvOp), False);
      CheckEveryLookup('random op ' + IntToStr(lvOp));
    end;
  end;
  CheckSameAnswers('after 800 random operations', False);
end;

procedure TBpStringListTests.TestSortedListMatchesStringList;
var
  i: Integer;
begin
  FRef.Sorted := True;
  FList.Sorted := True;
  for i := 40 downto 0 do
    BothAdd(MakeKey(i));
  CheckSameAnswers('sorted', False);
end;

procedure TBpStringListTests.TestSortedRandomOperationsMatchStringList;
var
  lvOp, i: Integer;
begin
  RandSeed := 20260905;
  FRef.Sorted := True;
  FList.Sorted := True;
  FRef.Duplicates := dupIgnore;
  FList.Duplicates := dupIgnore;
  for lvOp := 1 to 600 do
  begin
    i := Random(60);
    case Random(3) of
      0, 1: BothAdd(MakeKey(i));
      2: if FRef.Count > 0 then BothDelete(Random(FRef.Count));
    end;
    if lvOp mod 50 = 0 then
      CheckSameAnswers('sorted random op ' + IntToStr(lvOp), False);
  end;
  CheckSameAnswers('after 600 sorted random operations', False);
end;

procedure TBpStringListTests.TestValuesReadAndWrite;
begin
  FRef.Values['host'] := 'localhost';
  FList.Values['host'] := 'localhost';
  FRef.Values['port'] := '8080';
  FList.Values['port'] := '8080';
  CheckEquals(FRef.Text, FList.Text, 'writing through Values');
  CheckEquals('localhost', FList.Values['HOST'], 'reading back, folded');
  FRef.Values['host'] := 'remote';
  FList.Values['host'] := 'remote';
  CheckEquals(FRef.Text, FList.Text, 'overwriting through Values');
  FRef.Values['host'] := '';
  FList.Values['host'] := '';
  CheckEquals(FRef.Text, FList.Text, 'assigning an empty value removes the row');
  CheckEquals(-1, FList.IndexOfName('host'), 'and the index knows it is gone');
  CheckEquals('8080', FList.Values['port'], 'the other row is still found');
end;

procedure TBpStringListTests.TestAssignFromStringList;
var
  i: Integer;
begin
  for i := 0 to 20 do
    FRef.Add(MakeKey(i));
  FList.Assign(FRef);
  CheckSameAnswers('after Assign', False);
end;

// a sorted TStringList is ordered by the collation; the copy must be ordered
// by this class's relation or Find on it would lie
procedure TBpStringListTests.TestAssignCopiesTheFlagsAndResorts;
var
  lvOther: TbpStringList;
  lvIdx: Integer;
begin
  FRef.CaseSensitive := True;
  FRef.Sorted := True;
  FRef.Duplicates := dupIgnore;
  FRef.Add('b');
  FRef.Add('a');
  FRef.Add('B');
  FList.Assign(FRef);
  CheckTrue(FList.Sorted, 'Sorted copied');
  CheckTrue(FList.CaseSensitive, 'CaseSensitive copied');
  CheckTrue(FList.Duplicates = dupIgnore, 'Duplicates copied');
  CheckEquals('B' + sLineBreak + 'a' + sLineBreak + 'b' + sLineBreak, FList.Text, 'ordinal order after the copy');
  CheckTrue(FList.Find('a', lvIdx), 'Find works on the copy');
  CheckEquals(1, lvIdx, 'at the ordinal position');
  lvOther := TbpStringList.Create;
  try
    lvOther.Assign(FList);
    CheckTrue(lvOther.Sorted and lvOther.CaseSensitive, 'flags copied between two of ours');
    CheckEquals(FList.Text, lvOther.Text, 'same content');
  finally
    lvOther.Free;
  end;
end;

procedure TBpStringListTests.TestTextRoundTrip;
var
  i: Integer;
begin
  for i := 0 to 20 do
    FRef.Add(MakeKey(i));
  FList.Text := FRef.Text;
  CheckSameAnswers('after setting Text', False);
  CheckEquals(FRef.CommaText, FList.CommaText, 'CommaText agrees');
end;

procedure TBpStringListTests.TestAddStringsKeepsTheIndexCorrect;
var
  lvSource: TStringList;
  i: Integer;
begin
  lvSource := TStringList.Create;
  try
    for i := 0 to 20 do
      lvSource.Add(MakeKey(i));
    BothAdd('first');
    FList.IndexOf('first');
    FRef.AddStrings(lvSource);
    FList.AddStrings(lvSource);
    CheckSameAnswers('after AddStrings onto a live index', False);
  finally
    lvSource.Free;
  end;
end;

procedure TBpStringListTests.TestSaveAndLoadRoundTrip;
var
  lvFileName: string;
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i) + '=' + IntToStr(i));
  lvFileName := Format('%sBpStringListTests_%d.tmp',
    [IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')), GetCurrentProcessId]);
  try
    FList.SaveToFile(lvFileName);
    FList.Clear;
    CheckEquals(-1, FList.IndexOfName(MakeKey(3)), 'cleared');
    FList.LoadFromFile(lvFileName);
    CheckSameAnswers('after a save and load round trip', True);
  finally
    if FileExists(lvFileName) then
      DeleteFile(lvFileName);
  end;
end;

// SameText is ASCII only before Unicode, so a non-ASCII case pair is the test
procedure TBpStringListTests.TestNonAsciiCaseFolding;
var
  lvLower, lvUpper: string;
begin
  // CP1251 'тест' and 'ТЕСТ'
  lvLower := Chr($F2) + Chr($E5) + Chr($F1) + Chr($F2);
  lvUpper := Chr($D2) + Chr($C5) + Chr($D1) + Chr($D2);
  FRef.Add(lvUpper);
  FList.Add(lvUpper);
  CheckEquals(FRef.IndexOf(lvLower), FList.IndexOf(lvLower),
    'case-insensitive lookup must agree with TStringList on the active code page');
  FRef.CaseSensitive := True;
  FList.CaseSensitive := True;
  CheckEquals(FRef.IndexOf(lvLower), FList.IndexOf(lvLower), 'and so must the case-sensitive one');
end;

// the point of being a TStrings: existing code takes it unchanged
procedure TBpStringListTests.TestUsableThroughATStringsParameter;
var
  lvAsStrings: TStrings;
  i: Integer;
begin
  lvAsStrings := FList;
  for i := 0 to 10 do
    lvAsStrings.Add(MakeKey(i));
  lvAsStrings.Values['host'] := 'localhost';
  CheckEquals(11, lvAsStrings.IndexOfName('host'), 'IndexOfName through the base type');
  CheckEquals('localhost', lvAsStrings.Values['host'], 'Values through the base type');
  lvAsStrings.Delete(0);
  CheckEquals(10, FList.IndexOfName('host'), 'the index followed a Delete made through the base type');
  lvAsStrings.Move(10, 0);
  CheckEquals(0, FList.IndexOfName('host'), 'and a Move');
  lvAsStrings.Exchange(0, 5);
  CheckEquals(5, FList.IndexOfName('host'), 'and an Exchange');
end;

// the index

procedure TBpStringListTests.TestIndexOfEmptyList;
var
  lvIdx: Integer;
begin
  CheckEquals(-1, FList.IndexOf('nothing'), 'IndexOf on an empty list');
  CheckEquals(-1, FList.IndexOfName('nothing'), 'IndexOfName on an empty list');
  CheckFalse(FList.Find('nothing', lvIdx), 'Find on an empty list');
  CheckEquals(0, lvIdx, 'with the insertion point');
end;

procedure TBpStringListTests.TestEmptyStringIsAKey;
begin
  FList.Add('a');
  FList.Add('');
  CheckEquals(1, FList.IndexOf(''), 'the empty string is a normal entry');
  FList.Add('=v');
  CheckEquals(2, FList.IndexOfName(''), 'a row with a leading separator has the empty name');
end;

procedure TBpStringListTests.TestRowWithoutSeparatorIsNotAName;
begin
  FRef.Add('plain');
  FList.Add('plain');
  FRef.Add('k=v');
  FList.Add('k=v');
  CheckEquals(FRef.IndexOfName('plain'), FList.IndexOfName('plain'), 'a row with no separator has no name');
  CheckEquals(1, FList.IndexOfName('k'), 'the row with a separator is found');
  FList[0] := 'plain=now';
  CheckEquals(0, FList.IndexOfName('plain'), 'Put gave the row a name');
  FList[1] := 'k';
  CheckEquals(-1, FList.IndexOfName('k'), 'and took one away');
end;

procedure TBpStringListTests.TestDuplicatesAnswerWithTheFirst;
begin
  FList.Add('one');
  FList.Add('dup');
  FList.Add('two');
  FList.Add('DUP');
  CheckEquals(1, FList.IndexOf('dup'), 'IndexOf answers with the lowest match');
  FList.Delete(1);
  CheckEquals(2, FList.IndexOf('dup'), 'after deleting the first, the later one answers');
  FList.Insert(0, 'Dup');
  CheckEquals(0, FList.IndexOf('dup'), 'an insert in front becomes the answer');
end;

procedure TBpStringListTests.TestDeleteKeepsTheIndexCorrect;
var
  i: Integer;
begin
  for i := 0 to 40 do
    BothAdd(MakeKey(i));
  for i := 1 to 12 do
  begin
    BothDelete(FRef.Count div 2);
    CheckSameAnswers('after middle delete ' + IntToStr(i), False);
  end;
  while FRef.Count > 0 do
    BothDelete(FRef.Count - 1);
  CheckSameAnswers('after deleting everything from the tail', False);
  BothAdd('again');
  CheckEquals(0, FList.IndexOf('again'), 'usable after being emptied by deletes');
end;

procedure TBpStringListTests.TestInsertInTheMiddleKeepsTheIndexCorrect;
var
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i));
  FList.IndexOf(MakeKey(0));
  for i := 30 to 40 do
  begin
    BothInsert(FRef.Count div 2, MakeKey(i));
    CheckSameAnswers('after insert ' + IntToStr(i), False);
  end;
  BothInsert(0, MakeKey(50));
  BothInsert(FRef.Count, MakeKey(51));
  CheckSameAnswers('after inserting at both ends', False);
end;

procedure TBpStringListTests.TestExchangeKeepsTheIndexCorrect;
var
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i));
  FList.IndexOf(MakeKey(0));
  FRef.Exchange(2, 17);
  FList.Exchange(2, 17);
  CheckSameAnswers('after exchange with warm positions', False);
  BothInsert(5, MakeKey(30));
  FRef.Exchange(0, 20);
  FList.Exchange(0, 20);
  CheckSameAnswers('after exchange across a cold watermark', False);
end;

procedure TBpStringListTests.TestMoveKeepsTheIndexCorrect;
var
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i));
  FRef.Move(3, 15);
  FList.Move(3, 15);
  CheckSameAnswers('after Move down', False);
  FRef.Move(18, 0);
  FList.Move(18, 0);
  CheckSameAnswers('after Move up', False);
  FRef.Move(7, 7);
  FList.Move(7, 7);
  CheckSameAnswers('after Move onto itself', False);
end;

// colliding keys deleted from mid-chain, where a hand-kept index usually breaks
procedure TBpStringListTests.TestManyCollisions;
var
  i: Integer;
begin
  for i := 0 to 300 do
    BothAdd('collide' + IntToStr(i));
  FList.IndexOf('collide0');
  for i := 1 to 40 do
    BothDelete(Random(FRef.Count));
  for i := 0 to 300 do
    CheckEquals(FRef.IndexOf('collide' + IntToStr(i)), FList.IndexOf('collide' + IntToStr(i)),
      'collide' + IntToStr(i));
end;

// add and delete cycles must not grow the storage without bound
procedure TBpStringListTests.TestFreedSlotsAreReused;
var
  i: Integer;
begin
  for i := 0 to 9 do
    FList.Add(MakeKey(i));
  FList.IndexOf(MakeKey(0));
  for i := 1 to 5000 do
  begin
    FList.Add('temp' + IntToStr(i));
    FList.Delete(Random(FList.Count));
  end;
  CheckEquals(10, FList.Count, 'count is stable');
  CheckTrue(FList.Capacity < 64, 'capacity stayed small: ' + IntToStr(FList.Capacity));
  CheckEveryLookup('after 5000 add and delete cycles');
end;

procedure TBpStringListTests.TestCaseSensitiveFlipRebuilds;
var
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i));
  CheckSameAnswers('case insensitive', False);
  FRef.CaseSensitive := True;
  FList.CaseSensitive := True;
  CheckSameAnswers('after flipping to case sensitive', False);
  FRef.CaseSensitive := False;
  FList.CaseSensitive := False;
  CheckSameAnswers('after flipping back', False);
end;

procedure TBpStringListTests.TestNameValueSeparatorChangeRebuilds;
begin
  FRef.Add('a=1|b');
  FList.Add('a=1|b');
  FRef.Add('c|2');
  FList.Add('c|2');
  CheckEquals(FRef.IndexOfName('a'), FList.IndexOfName('a'), 'with the default separator');
  FRef.NameValueSeparator := '|';
  FList.NameValueSeparator := '|';
  CheckEquals(FRef.IndexOfName('c'), FList.IndexOfName('c'), 'after changing the separator');
  CheckEquals(FRef.IndexOfName('a=1'), FList.IndexOfName('a=1'), 'the first row now has another name');
  CheckEquals(-1, FList.IndexOfName('a'), 'and the old name is gone');
end;

procedure TBpStringListTests.TestObjectsFollowTheirRows;
var
  lvObjs: array[0..9] of TObject;
  i: Integer;
begin
  for i := 0 to 9 do
    lvObjs[i] := TObject.Create;
  try
    for i := 0 to 9 do
      FList.AddObject('row' + IntToStr(9 - i), lvObjs[i]);
    FList.InsertObject(5, 'tagged', lvObjs[0]);
    CheckEquals(5, FList.IndexOf('tagged'), 'the inserted row is indexed');
    Check(FList.Objects[5] = lvObjs[0], 'the object rode along');
    FList.Insert(0, 'front');
    Check(FList.Objects[FList.IndexOf('tagged')] = lvObjs[0], 'and survived a shift');
    FList.Delete(FList.IndexOf('front'));
    FList.Delete(FList.IndexOf('tagged'));
    FList.Sort;
    for i := 0 to 9 do
      Check(FList.Objects[FList.IndexOf('row' + IntToStr(i))] = lvObjs[9 - i], 'object after Sort, row ' + IntToStr(i));
    FList.Move(0, 9);
    FList.Exchange(1, 2);
    for i := 0 to 9 do
      Check(FList.Objects[FList.IndexOf('row' + IntToStr(i))] = lvObjs[9 - i], 'object after Move and Exchange, row ' + IntToStr(i));
    FList.Objects[0] := nil;
    Check(FList.Objects[0] = nil, 'PutObject');
  finally
    for i := 0 to 9 do
      lvObjs[i].Free;
  end;
end;

procedure TBpStringListTests.TestClearResetsEverything;
var
  i: Integer;
begin
  for i := 0 to 20 do
    FList.Add(MakeKey(i) + '=' + IntToStr(i));
  FList.IndexOf(MakeKey(0));
  FList.IndexOfName(MakeKey(0));
  FList.Clear;
  CheckEquals(0, FList.Count, 'empty');
  CheckEquals(0, FList.Capacity, 'storage released');
  CheckEquals(-1, FList.IndexOf(MakeKey(0) + '=0'), 'nothing found');
  CheckEquals(-1, FList.IndexOfName(MakeKey(0)), 'no name found');
  FList.Add('x=1');
  CheckEquals(0, FList.IndexOfName('x'), 'usable again');
end;

procedure TBpStringListTests.TestCapacity;
var
  i: Integer;
begin
  FList.Capacity := 100;
  CheckEquals(100, FList.Capacity, 'presized');
  for i := 0 to 99 do
    FList.Add(IntToStr(i));
  CheckEquals(100, FList.Capacity, 'no growth needed within the presize');
  FList.Add('one more');
  CheckTrue(FList.Capacity > 100, 'grew');
  FList.Capacity := 10;
  CheckTrue(FList.Capacity >= 101, 'cannot shrink below the rows in use');
  CheckEquals(101, FList.Count, 'nothing lost');
end;

// the relation

procedure TBpStringListTests.TestSortOrderIsOrdinal;
begin
  FList.Add('b');
  FList.Add('B');
  FList.Add('a');
  FList.Add('A');
  FList.Add('_');
  FList.Sort;
  // folded: '_' ($5F) sorts after 'A' ($41) and 'B' ($42); equal keys keep their order
  CheckEquals('a,A,b,B,_', FList.CommaText, 'case-insensitive ordinal order, stable among equals');
  FList.CaseSensitive := True;
  FList.Sort;
  CheckEquals('A,B,_,a,b', FList.CommaText, 'case-sensitive ordinal order');
end;

procedure TBpStringListTests.TestSortIsStable;
var
  i: Integer;
begin
  for i := 1 to 200 do
    FList.Add(Format('%s=%d', [Chr(Ord('a') + i mod 7), i]));
  FList.CustomSort(CompareByValue);
  FList.CustomSort(CompareByLength);
  // lengths are 3 or 5 chars, so within each length the value order must hold
  for i := 1 to FList.Count - 1 do
    if Length(FList[i]) = Length(FList[i - 1]) then
      CheckTrue(StrToInt(FList.ValueFromIndex[i - 1]) < StrToInt(FList.ValueFromIndex[i]),
        'stable at row ' + IntToStr(i));
  CheckEveryLookup('after two custom sorts');
end;

procedure TBpStringListTests.TestCustomSortSeesPreSortPositions;
var
  i: Integer;
begin
  for i := 0 to 50 do
    FList.Add(Format('k%d=%d', [i, 50 - i]));
  FList.CustomSort(CompareByValue);
  for i := 0 to 50 do
    CheckEquals(IntToStr(i), FList.ValueFromIndex[i], 'row ' + IntToStr(i));
  CheckEveryLookup('after CustomSort');
end;

// TStringList forgets to re-sort here, because its Sort is a no-op while Sorted
procedure TBpStringListTests.TestCaseSensitiveFlipResortsASortedList;
var
  lvIdx: Integer;
begin
  FList.CaseSensitive := True;
  FList.Sorted := True;
  FList.Add('b');
  FList.Add('B');
  FList.Add('a');
  FList.Add('A');
  CheckEquals('A,B,a,b', FList.CommaText, 'case-sensitive');
  FList.CaseSensitive := False;
  CheckEquals('A,a,B,b', FList.CommaText, 're-sorted under the new fold, stable');
  CheckTrue(FList.Find('B', lvIdx), 'Find works after the flip');
  CheckEquals(2, lvIdx, 'and lands on the first equal row');
end;

// Sorted and Duplicates

procedure TBpStringListTests.TestFindOnASortedList;
var
  lvIdx, i: Integer;
begin
  FList.Sorted := True;
  for i := 0 to 20 do
    FList.Add(Format('k%.3d', [i * 2]));
  CheckTrue(FList.Find('K010', lvIdx), 'hit, folded');
  CheckEquals(5, lvIdx, 'at its position');
  CheckFalse(FList.Find('k011', lvIdx), 'miss');
  CheckEquals(6, lvIdx, 'with the insertion point');
  CheckFalse(FList.Find('k999', lvIdx), 'miss past the end');
  CheckEquals(21, lvIdx, 'insertion point is Count');
  CheckFalse(FList.Find('a', lvIdx), 'miss before the start');
  CheckEquals(0, lvIdx, 'insertion point is 0');
  CheckEquals(5, FList.IndexOf('k010'), 'IndexOf agrees with Find');
end;

procedure TBpStringListTests.TestFindOnAnUnsortedListIsIndexOf;
var
  lvIdx: Integer;
begin
  FList.Add('z');
  FList.Add('a');
  FList.Add('m');
  CheckTrue(FList.Find('A', lvIdx), 'found without sorting');
  CheckEquals(1, lvIdx, 'at its position');
  CheckFalse(FList.Find('q', lvIdx), 'miss');
  CheckEquals(3, lvIdx, 'aIndex is Count on a miss');
end;

procedure TBpStringListTests.TestSortedDuplicatesKeepInsertionOrder;
var
  lvIdx: Integer;
begin
  FList.Sorted := True;
  FList.Duplicates := dupAccept;
  FList.AddObject('b', TObject(1));
  FList.AddObject('B', TObject(2));
  FList.AddObject('a', TObject(3));
  FList.AddObject('b', TObject(4));
  CheckEquals('a,b,B,b', FList.CommaText, 'equal keys in the order they came');
  CheckTrue(FList.Objects[1] = TObject(1), 'first duplicate');
  CheckTrue(FList.Objects[3] = TObject(4), 'last duplicate');
  CheckEquals(1, FList.IndexOf('B'), 'IndexOf answers the first equal row');
  CheckTrue(FList.Find('b', lvIdx) and (lvIdx = 1), 'so does Find');
end;

procedure TBpStringListTests.TestSortedIgnoresDuplicates;
begin
  FRef.Sorted := True;
  FList.Sorted := True;
  FRef.Duplicates := dupIgnore;
  FList.Duplicates := dupIgnore;
  BothAdd('beta');
  BothAdd('alpha');
  CheckEquals(1, FList.Add('BETA'), 'the ignored add returns the existing row');
  FRef.Add('BETA');
  CheckEquals(2, FList.Count, 'the duplicate was not added');
  CheckSameAnswers('sorted with dupIgnore', False);
end;

procedure TBpStringListTests.TestSortedRejectsDuplicatesWhenAsked;
begin
  FList.Sorted := True;
  FList.Duplicates := dupError;
  FList.Add('only');
  try
    FList.Add('ONLY');
    Fail('a duplicate must raise with dupError');
  except
    // narrow, or Fail is caught by its own handler
    on E: EStringListError do
      CheckEquals(1, FList.Count, 'and nothing must have been added');
  end;
  CheckEquals(0, FList.IndexOf('only'), 'the index survived the rejected add');
end;

// as in TStringList, and unlike a set: the default Duplicates is dupIgnore,
// which must not start dropping rows from an ordinary list
procedure TBpStringListTests.TestDuplicatesOnlyMatterWhenSorted;
begin
  CheckTrue(FList.Duplicates = dupIgnore, 'the TStringList default');
  FList.Add('a');
  FList.Add('A');
  FList.Insert(0, 'a');
  FList.Duplicates := dupError;
  FList.Add('a');
  FList[1] := 'A';
  CheckEquals('a,A,A,a', FList.CommaText, 'nothing dropped, nothing raised');
  CheckEquals(0, FList.IndexOf('a'), 'and the first still answers');
end;

procedure TBpStringListTests.TestSortedListRefusesReordering;
begin
  FList.Sorted := True;
  FList.Add('b');
  FList.Add('a');
  try
    FList.Insert(0, 'z');
    ExpectSortedError('Insert');
  except
    on E: EStringListError do ;
  end;
  try
    FList[0] := 'z';
    ExpectSortedError('Put');
  except
    on E: EStringListError do ;
  end;
  try
    FList.Exchange(0, 1);
    ExpectSortedError('Exchange');
  except
    on E: EStringListError do ;
  end;
  try
    FList.Move(0, 1);
    ExpectSortedError('Move');
  except
    on E: EStringListError do ;
  end;
  try
    FList.CustomSort(CompareByLength);
    ExpectSortedError('CustomSort');
  except
    on E: EStringListError do ;
  end;
  CheckEquals('a,b', FList.CommaText, 'nothing moved');
  FList.Objects[0] := TObject(1);
  CheckTrue(FList.Objects[0] = TObject(1), 'PutObject is allowed');
  FList.Delete(0);
  CheckEquals('b', FList.CommaText, 'Delete is allowed');
end;

procedure TBpStringListTests.TestSettingSortedSortsOnce;
begin
  FList.Add('c');
  FList.Add('a');
  FList.Add('b');
  FList.OnChange := CountChange;
  FList.Sorted := True;
  CheckEquals(1, FChangeHits, 'one notification for the sort');
  CheckEquals('a,b,c', FList.CommaText, 'sorted');
  FList.Sorted := True;
  CheckEquals(1, FChangeHits, 'setting it again does nothing');
  FList.Sorted := False;
  CheckEquals(1, FChangeHits, 'turning it off does not touch the rows');
  CheckEquals('a,b,c', FList.CommaText, 'still in order');
end;

// notifications

procedure TBpStringListTests.CountChanging(Sender: TObject);
begin
  Inc(FChangingHits);
end;

procedure TBpStringListTests.CountChange(Sender: TObject);
begin
  Inc(FChangeHits);
end;

procedure TBpStringListTests.TestChangingAndChangedFireOnce;
begin
  FList.OnChanging := CountChanging;
  FList.OnChange := CountChange;
  FList.Add('a');
  FList.Insert(0, 'b');
  FList[0] := 'c';
  FList.Objects[0] := nil;
  FList.Exchange(0, 1);
  FList.Move(0, 1);
  FList.Sort;
  FList.Delete(0);
  FList.Clear;
  CheckEquals(9, FChangingHits, 'OnChanging once per mutation');
  CheckEquals(9, FChangeHits, 'OnChange once per mutation');
  FList.Clear;
  FList.Sort;
  CheckEquals(9, FChangeHits, 'nothing to do, nothing fired');
end;

procedure TBpStringListTests.TestBeginUpdateSuppressesNotifications;
var
  i: Integer;
begin
  FList.OnChanging := CountChanging;
  FList.OnChange := CountChange;
  FList.BeginUpdate;
  try
    for i := 0 to 9 do
      FList.Add(IntToStr(i));
    FList.Sort;
  finally
    FList.EndUpdate;
  end;
  CheckEquals(1, FChangingHits, 'one OnChanging for the batch');
  CheckEquals(1, FChangeHits, 'one OnChange for the batch');
end;

// a lookup from inside OnChange sees the finished mutation
procedure TBpStringListTests.LookupOnChange(Sender: TObject);
begin
  Inc(FChangeHits);
  FList.IndexOf(MakeKey(2) + '=2');
  FList.IndexOfName(MakeKey(2));
  FHandlerValue := FList.Values[MakeKey(4)];
end;

// the harder case: the handler mutates the list the mutation just finished on
procedure TBpStringListTests.AppendOnChange(Sender: TObject);
begin
  if FChangeHits > 0 then
    Exit;
  Inc(FChangeHits);
  FList.Add('AddedByTheHandler');
end;

procedure TBpStringListTests.TestLookupFromAChangeHandler;
var
  i: Integer;
begin
  for i := 0 to 30 do
    BothAdd(MakeKey(i) + '=' + IntToStr(i));
  FList.IndexOf(MakeKey(0) + '=0');
  FList.IndexOfName(MakeKey(0));
  FList.OnChange := LookupOnChange;
  FList.OnChanging := LookupOnChange;
  BothAdd(MakeKey(31) + '=31');
  CheckSameAnswers('an Add watched by a handler that looks up', True);
  BothInsert(5, MakeKey(32) + '=32');
  CheckSameAnswers('a middle Insert watched by a handler', True);
  BothDelete(7);
  CheckSameAnswers('a Delete watched by a handler', True);
  BothPut(3, MakeKey(33) + '=33');
  CheckSameAnswers('a Put watched by a handler', True);
  FList.Exchange(0, 1);
  FRef.Exchange(0, 1);
  FList.Move(2, 9);
  FRef.Move(2, 9);
  BothAdd(MakeKey(34) + '=34');
  CheckSameAnswers('an Add with a cold watermark watched by a handler', True);
  FList.Sort;
  FRef.Sort;
  CheckSameAnswers('a Sort watched by a handler', True);
  CheckEquals('4', FHandlerValue, 'the handler read a value');
  FList.OnChange := nil;
  FList.OnChanging := nil;
  CheckTrue(FChangeHits > 0, 'the handler ran');
end;

procedure TBpStringListTests.TestNestedMutationFromAChangeHandler;
var
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i));
  FList.IndexOf(MakeKey(0));
  FList.OnChange := AppendOnChange;
  FList.Add(MakeKey(21));
  FList.OnChange := nil;
  FRef.Add(MakeKey(21));
  FRef.Add('AddedByTheHandler');
  CheckEquals(1, FChangeHits, 'the handler ran once');
  CheckSameAnswers('after a handler added a row of its own', False);
  CheckEquals(FRef.IndexOf('AddedByTheHandler'), FList.IndexOf('AddedByTheHandler'),
    'the row the handler added is findable');
end;

// OnChanging fires before the mutator reads its index, so the index goes stale
procedure TBpStringListTests.DeleteOnChanging(Sender: TObject);
begin
  if FChangingHits > 0 then
    Exit;
  Inc(FChangingHits);
  FList.Delete(FList.Count - 1);
end;

procedure TBpStringListTests.TestMutationFromAChangingHandlerRaises;
var
  i: Integer;
begin
  for i := 0 to 4 do
    FList.Add(MakeKey(i));
  // warm both indexes and the whole position array, so a stale hit would be silent
  FList.IndexOf(MakeKey(0));
  FList.IndexOfName(MakeKey(0));
  FList.OnChanging := DeleteOnChanging;
  FChangingHits := 0;
  try
    FList.Delete(4);
    Fail('the handler already removed row 4, so Delete must raise');
  except
    // narrow, or Fail is caught by its own handler
    on E: EStringListError do
      CheckEquals(4, FList.Count, 'only the handler''s delete happened');
  end;
  FChangingHits := 0;
  try
    FList.Add('X');
    Fail('the handler shrank the list under the captured index, so Add must raise');
  except
    on E: EStringListError do
      CheckEquals(3, FList.Count, 'and nothing was appended');
  end;
  FList.OnChanging := nil;
  CheckEveryLookup('after a handler mutated from OnChanging');
  FList.Add('X');
  CheckEquals(3, FList.IndexOf('X'), 'the slot allocator survived');
end;

procedure TBpStringListTests.TestClearReleasesSlotsEmptiedRowByRow;
var
  i: Integer;
begin
  for i := 0 to 999 do
    FList.Add(IntToStr(i));
  CheckTrue(FList.Capacity >= 1000, 'grew to hold them');
  for i := 999 downto 0 do
    FList.Delete(i);
  CheckEquals(0, FList.Count, 'every row gone');
  FList.Capacity := 0;
  CheckTrue(FList.Capacity >= 1000, 'the free list still owns every slot');
  FList.OnChange := CountChange;
  FChangeHits := 0;
  FList.Clear;
  FList.OnChange := nil;
  CheckEquals(0, FList.Capacity, 'Clear releases them');
  CheckEquals(0, FChangeHits, 'and notifies nobody, there were no rows');
  FList.Add('again');
  CheckEquals(0, FList.IndexOf('again'), 'and the list still works');
end;

initialization
  RegisterTest(TBpStringListTests.Suite);

end.
