unit BpStringListTests;

interface

uses
  TestFramework, Windows, Classes, SysUtils, BpStringList;

type
  TBpStringListTests = class(TTestCase)
  private
    FList: TbpStringList;
    FRef: TStringList;
    // every mutation is applied to both, so TStringList is the oracle
    procedure BothAdd(const aStr: string);
    procedure BothInsert(aIndex: Integer; const aStr: string);
    procedure BothDelete(aIndex: Integer);
    procedure BothPut(aIndex: Integer; const aStr: string);
    procedure CheckSameAnswers(const aWhat: string; aUseNames: Boolean);
    function MakeKey(aIndex: Integer): string;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestIndexOfMatchesStringList;
    procedure TestIndexOfNameMatchesStringList;
    procedure TestCaseSensitiveMatchesStringList;
    procedure TestRandomOperationsMatchStringList;
    procedure TestSortedListMatchesStringList;
    procedure TestIndexOfEmptyList;
    procedure TestEmptyStringIsAKey;
    procedure TestRowWithoutSeparatorIsNotAName;
    procedure TestDuplicatesAnswerWithTheFirst;
    procedure TestDeleteKeepsTheIndexCorrect;
    procedure TestInsertInTheMiddleKeepsTheIndexCorrect;
    procedure TestExchangeKeepsTheIndexCorrect;
    procedure TestSortInvalidatesAndRebuilds;
    procedure TestCaseSensitiveFlipRebuilds;
    procedure TestNameValueSeparatorChangeRebuilds;
    procedure TestValuesReadAndWrite;
    procedure TestAssignFromStringList;
    procedure TestTextRoundTrip;
    procedure TestObjectsSurviveIndexing;
    procedure TestNonAsciiCaseFolding;
    procedure TestManyCollisions;
    procedure TestMoveKeepsTheIndexCorrect;
    procedure TestAddStringsKeepsTheIndexCorrect;
    procedure TestSortedIgnoresDuplicates;
    procedure TestSortedRejectsDuplicatesWhenAsked;
    procedure TestUsableThroughATStringsParameter;
    procedure TestSaveAndLoadRoundTrip;
  end;

implementation

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

// compares the contents and then every lookup answer against the oracle
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
      CheckEquals(FRef.IndexOfName(lvKey), FList.IndexOfName(lvKey),
        aWhat + ': IndexOfName(' + lvKey + ')');
      CheckEquals(FRef.Values[lvKey], FList.Values[lvKey], aWhat + ': Values[' + lvKey + ']');
    end
    else
      CheckEquals(FRef.IndexOf(lvKey), FList.IndexOf(lvKey), aWhat + ': IndexOf(' + lvKey + ')');
  end;
end;

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
end;

procedure TBpStringListTests.TestRandomOperationsMatchStringList;
var
  lvOp, i, lvIdx: Integer;
begin
  RandSeed := 20260829;
  for lvOp := 1 to 600 do
  begin
    i := Random(60);
    case Random(8) of
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
      7: if lvOp mod 71 = 0 then
         begin
           FRef.Sort;
           FList.Sort;
         end;
    end;
    if lvOp mod 25 = 0 then
      CheckSameAnswers('random op ' + IntToStr(lvOp), False);
  end;
  CheckSameAnswers('after 600 random operations', False);
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

procedure TBpStringListTests.TestIndexOfEmptyList;
begin
  CheckEquals(-1, FList.IndexOf('nothing'), 'IndexOf on an empty list');
  CheckEquals(-1, FList.IndexOfName('nothing'), 'IndexOfName on an empty list');
end;

procedure TBpStringListTests.TestEmptyStringIsAKey;
begin
  FList.Add('a');
  FList.Add('');
  CheckEquals(1, FList.IndexOf(''), 'the empty string is a normal entry');
end;

procedure TBpStringListTests.TestRowWithoutSeparatorIsNotAName;
begin
  FRef.Add('plain');
  FList.Add('plain');
  FRef.Add('k=v');
  FList.Add('k=v');
  CheckEquals(FRef.IndexOfName('plain'), FList.IndexOfName('plain'),
    'a row with no separator has no name');
  CheckEquals(1, FList.IndexOfName('k'), 'the row with a separator is found');
end;

procedure TBpStringListTests.TestDuplicatesAnswerWithTheFirst;
begin
  FList.Add('one');
  FList.Add('dup');
  FList.Add('two');
  FList.Add('dup');
  CheckEquals(1, FList.IndexOf('dup'), 'IndexOf answers with the lowest match');
  FList.Delete(1);
  CheckEquals(2, FList.IndexOf('dup'), 'after deleting the first, the later one answers');
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
    CheckSameAnswers('after delete ' + IntToStr(i), False);
  end;
end;

procedure TBpStringListTests.TestInsertInTheMiddleKeepsTheIndexCorrect;
var
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i));
  for i := 30 to 40 do
  begin
    BothInsert(FRef.Count div 2, MakeKey(i));
    CheckSameAnswers('after insert ' + IntToStr(i), False);
  end;
end;

procedure TBpStringListTests.TestExchangeKeepsTheIndexCorrect;
var
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i));
  FRef.Exchange(2, 17);
  FList.Exchange(2, 17);
  CheckSameAnswers('after exchange', False);
end;

procedure TBpStringListTests.TestSortInvalidatesAndRebuilds;
var
  i: Integer;
begin
  for i := 20 downto 0 do
    BothAdd(MakeKey(i));
  CheckEquals(FRef.IndexOf(MakeKey(5)), FList.IndexOf(MakeKey(5)), 'before the sort');
  FRef.Sort;
  FList.Sort;
  CheckSameAnswers('after Sort', False);
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
end;

procedure TBpStringListTests.TestValuesReadAndWrite;
begin
  FRef.Values['host'] := 'localhost';
  FList.Values['host'] := 'localhost';
  FRef.Values['port'] := '8080';
  FList.Values['port'] := '8080';
  CheckEquals(FRef.Text, FList.Text, 'writing through Values');
  CheckEquals('localhost', FList.Values['host'], 'reading back');
  FRef.Values['host'] := '';
  FList.Values['host'] := '';
  CheckEquals(FRef.Text, FList.Text, 'assigning an empty value removes the row');
  CheckEquals(-1, FList.IndexOfName('host'), 'and the index knows it is gone');
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

procedure TBpStringListTests.TestTextRoundTrip;
var
  i: Integer;
begin
  for i := 0 to 20 do
    FRef.Add(MakeKey(i));
  FList.Text := FRef.Text;
  CheckSameAnswers('after setting Text', False);
end;

procedure TBpStringListTests.TestObjectsSurviveIndexing;
var
  lvObj: TObject;
  i: Integer;
begin
  lvObj := TObject.Create;
  try
    for i := 0 to 10 do
      FList.Add(MakeKey(i));
    FList.InsertObject(5, 'tagged', lvObj);
    CheckEquals(5, FList.IndexOf('tagged'), 'the inserted row is indexed');
    Check(FList.Objects[5] = lvObj, 'the object rode along');
    FList.Delete(0);
    CheckEquals(4, FList.IndexOf('tagged'), 'the index followed the shift');
    Check(FList.Objects[4] = lvObj, 'and so did the object');
  finally
    lvObj.Free;
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
  CheckEquals(FRef.IndexOf(lvLower), FList.IndexOf(lvLower),
    'and so must the case-sensitive one');
end;

// colliding keys deleted from mid-chain, where a hand-kept index usually breaks
procedure TBpStringListTests.TestManyCollisions;
var
  i: Integer;
begin
  for i := 0 to 300 do
    BothAdd('collide' + IntToStr(i));
  for i := 1 to 40 do
  begin
    BothDelete(Random(FRef.Count));
    CheckEquals(FRef.Count, FList.Count, 'count after delete');
  end;
  for i := 0 to 300 do
    CheckEquals(FRef.IndexOf('collide' + IntToStr(i)), FList.IndexOf('collide' + IntToStr(i)),
      'collide' + IntToStr(i));
end;


// TStrings.Move is Delete plus InsertObject, so it goes through the hooks
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
    FRef.AddStrings(lvSource);
    FList.AddStrings(lvSource);
    CheckSameAnswers('after AddStrings', False);
  finally
    lvSource.Free;
  end;
end;

procedure TBpStringListTests.TestSortedIgnoresDuplicates;
begin
  FRef.Sorted := True;
  FList.Sorted := True;
  FRef.Duplicates := dupIgnore;
  FList.Duplicates := dupIgnore;
  BothAdd('beta');
  BothAdd('alpha');
  BothAdd('beta');
  CheckEquals(2, FList.Count, 'the duplicate was not added');
  CheckSameAnswers('sorted with dupIgnore', False);
end;

procedure TBpStringListTests.TestSortedRejectsDuplicatesWhenAsked;
begin
  FList.Sorted := True;
  FList.Duplicates := dupError;
  FList.Add('only');
  try
    FList.Add('only');
    Fail('a duplicate must raise with dupError');
  except
    // narrow, or Fail is caught by its own handler
    on E: EStringListError do
      CheckEquals(1, FList.Count, 'and nothing must have been added');
  end;
  CheckEquals(0, FList.IndexOf('only'), 'the index survived the rejected add');
end;

// the point of descending from TStringList: it can be handed to existing code
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
end;

procedure TBpStringListTests.TestSaveAndLoadRoundTrip;
var
  lvFileName: string;
  i: Integer;
begin
  for i := 0 to 20 do
    BothAdd(MakeKey(i) + '=' + IntToStr(i));
  lvFileName := Format('%sBpStringListTests_%d.tmp', [IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')), GetCurrentProcessId]);
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

initialization
  RegisterTest(TBpStringListTests.Suite);

end.
