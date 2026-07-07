unit BpStrUtilsTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpStrUtils;

type
  TBpStrUtilsTests = class(TTestCase)
  private
    // both results must match for every flag combination
    procedure CheckReplaceParity(const AText, AOld, ANew: string);
  published
    // Split with a Char delimiter
    procedure TestSplitCharBasic;
    procedure TestSplitCharEmptyText;
    procedure TestSplitCharNoDelimiter;
    procedure TestSplitCharLeadingTrailing;
    procedure TestSplitCharConsecutive;
    procedure TestSplitCharOnlyDelimiters;
    // Split with a string delimiter
    procedure TestSplitStrBasic;
    procedure TestSplitStrEmptyDelimiter;
    procedure TestSplitStrNotFound;
    procedure TestSplitStrLeadingTrailing;
    procedure TestSplitStrOverlappingPattern;
    procedure TestSplitStrManyParts;
    // Join
    procedure TestJoinBasic;
    procedure TestJoinEmptyArray;
    procedure TestJoinSingleElement;
    procedure TestJoinEmptySeparator;
    procedure TestJoinEmptyElements;
    procedure TestJoinSplitRoundTrip;
    // FastStringReplace
    procedure TestReplaceBasic;
    procedure TestReplaceEmptyText;
    procedure TestReplaceEmptyOldPattern;
    procedure TestReplaceDelete;
    procedure TestReplaceLongerPattern;
    procedure TestReplaceAdjacentMatches;
    procedure TestReplaceOverlappingPattern;
    procedure TestReplaceFirstOnly;
    procedure TestReplaceIgnoreCase;
    procedure TestReplaceIgnoreCaseNonAscii;
    procedure TestReplaceSingleCharFastPath;
    procedure TestReplaceNoMatch;
    procedure TestReplaceWholeText;
    procedure TestReplaceManyMatches;
    procedure TestReplaceRandomParity;
    // StartsWith / EndsWith
    procedure TestStartsWith;
    procedure TestEndsWith;
    procedure TestStartsWithText;
    procedure TestEndsWithText;
  end;

implementation

procedure TBpStrUtilsTests.CheckReplaceParity(const AText, AOld, ANew: string);
begin
  CheckEquals(StringReplace(AText, AOld, ANew, []),
    FastStringReplace(AText, AOld, ANew, []), 'flags []');
  CheckEquals(StringReplace(AText, AOld, ANew, [rfReplaceAll]),
    FastStringReplace(AText, AOld, ANew, [rfReplaceAll]), 'flags [rfReplaceAll]');
  CheckEquals(StringReplace(AText, AOld, ANew, [rfIgnoreCase]),
    FastStringReplace(AText, AOld, ANew, [rfIgnoreCase]), 'flags [rfIgnoreCase]');
  CheckEquals(StringReplace(AText, AOld, ANew, [rfReplaceAll, rfIgnoreCase]),
    FastStringReplace(AText, AOld, ANew, [rfReplaceAll, rfIgnoreCase]),
    'flags [rfReplaceAll, rfIgnoreCase]');
end;

procedure TBpStrUtilsTests.TestSplitCharBasic;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split('a,b,c', ',');
  CheckEquals(3, Length(lvParts));
  CheckEquals('a', lvParts[0]);
  CheckEquals('b', lvParts[1]);
  CheckEquals('c', lvParts[2]);
end;

procedure TBpStrUtilsTests.TestSplitCharEmptyText;
begin
  CheckEquals(0, Length(Split('', ',')));
end;

procedure TBpStrUtilsTests.TestSplitCharNoDelimiter;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split('abc', ',');
  CheckEquals(1, Length(lvParts));
  CheckEquals('abc', lvParts[0]);
end;

procedure TBpStrUtilsTests.TestSplitCharLeadingTrailing;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split(',a,', ',');
  CheckEquals(3, Length(lvParts));
  CheckEquals('', lvParts[0]);
  CheckEquals('a', lvParts[1]);
  CheckEquals('', lvParts[2]);
end;

procedure TBpStrUtilsTests.TestSplitCharConsecutive;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split('a,,b', ',');
  CheckEquals(3, Length(lvParts));
  CheckEquals('a', lvParts[0]);
  CheckEquals('', lvParts[1]);
  CheckEquals('b', lvParts[2]);
end;

procedure TBpStrUtilsTests.TestSplitCharOnlyDelimiters;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split(',,', ',');
  CheckEquals(3, Length(lvParts));
  CheckEquals('', lvParts[0]);
  CheckEquals('', lvParts[1]);
  CheckEquals('', lvParts[2]);
end;

procedure TBpStrUtilsTests.TestSplitStrBasic;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split('a::b::c', '::');
  CheckEquals(3, Length(lvParts));
  CheckEquals('a', lvParts[0]);
  CheckEquals('b', lvParts[1]);
  CheckEquals('c', lvParts[2]);
end;

procedure TBpStrUtilsTests.TestSplitStrEmptyDelimiter;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split('abc', '');
  CheckEquals(1, Length(lvParts));
  CheckEquals('abc', lvParts[0]);
end;

procedure TBpStrUtilsTests.TestSplitStrNotFound;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split('abc', 'xy');
  CheckEquals(1, Length(lvParts));
  CheckEquals('abc', lvParts[0]);
end;

procedure TBpStrUtilsTests.TestSplitStrLeadingTrailing;
var
  lvParts: TbpStringArray;
begin
  lvParts := Split('::a::', '::');
  CheckEquals(3, Length(lvParts));
  CheckEquals('', lvParts[0]);
  CheckEquals('a', lvParts[1]);
  CheckEquals('', lvParts[2]);
end;

procedure TBpStrUtilsTests.TestSplitStrOverlappingPattern;
var
  lvParts: TbpStringArray;
begin
  // matches do not overlap: 'aaa' splits at position 1, remainder is 'a'
  lvParts := Split('aaa', 'aa');
  CheckEquals(2, Length(lvParts));
  CheckEquals('', lvParts[0]);
  CheckEquals('a', lvParts[1]);
end;

procedure TBpStrUtilsTests.TestSplitStrManyParts;
var
  lvParts: TbpStringArray;
  lvText: string;
  i: Integer;
begin
  // 20 parts exercise the doubling growth of the result array
  lvText := '';
  for i := 1 to 20 do
  begin
    if i > 1 then
      lvText := lvText + '|';
    lvText := lvText + IntToStr(i);
  end;
  lvParts := Split(lvText, '|');
  CheckEquals(20, Length(lvParts));
  for i := 1 to 20 do
    CheckEquals(IntToStr(i), lvParts[i - 1]);
end;

procedure TBpStrUtilsTests.TestJoinBasic;
begin
  CheckEquals('a,b,c', Join(['a', 'b', 'c'], ','));
end;

procedure TBpStrUtilsTests.TestJoinEmptyArray;
var
  lvValues: TbpStringArray;
begin
  lvValues := nil;
  CheckEquals('', Join(lvValues, ','));
end;

procedure TBpStrUtilsTests.TestJoinSingleElement;
begin
  CheckEquals('abc', Join(['abc'], ','));
end;

procedure TBpStrUtilsTests.TestJoinEmptySeparator;
begin
  CheckEquals('abc', Join(['a', 'b', 'c'], ''));
end;

procedure TBpStrUtilsTests.TestJoinEmptyElements;
begin
  CheckEquals(',,', Join(['', '', ''], ','));
end;

procedure TBpStrUtilsTests.TestJoinSplitRoundTrip;
const
  lcText = ',start,middle,,end,';
begin
  CheckEquals(lcText, Join(Split(lcText, ','), ','));
end;

procedure TBpStrUtilsTests.TestReplaceBasic;
begin
  CheckEquals('the cat sat on the cat',
    FastStringReplace('the dog sat on the dog', 'dog', 'cat', [rfReplaceAll]));
  CheckReplaceParity('the dog sat on the dog', 'dog', 'cat');
end;

procedure TBpStrUtilsTests.TestReplaceEmptyText;
begin
  CheckReplaceParity('', 'a', 'b');
end;

procedure TBpStrUtilsTests.TestReplaceEmptyOldPattern;
begin
  CheckReplaceParity('abc', '', 'x');
end;

procedure TBpStrUtilsTests.TestReplaceDelete;
begin
  CheckEquals('abc', FastStringReplace('a-b-c', '-', '', [rfReplaceAll]));
  CheckReplaceParity('a-b-c', '-', '');
end;

procedure TBpStrUtilsTests.TestReplaceLongerPattern;
begin
  CheckEquals('<tag>x<tag>', FastStringReplace('.x.', '.', '<tag>', [rfReplaceAll]));
  CheckReplaceParity('.x.', '.', '<tag>');
end;

procedure TBpStrUtilsTests.TestReplaceAdjacentMatches;
begin
  CheckEquals('xyxyxy', FastStringReplace('ababab', 'ab', 'xy', [rfReplaceAll]));
  CheckReplaceParity('ababab', 'ab', 'xy');
end;

procedure TBpStrUtilsTests.TestReplaceOverlappingPattern;
begin
  // non-overlapping scan, same as SysUtils: 'aaaa' has two matches of 'aa'
  CheckEquals('bb', FastStringReplace('aaaa', 'aa', 'b', [rfReplaceAll]));
  CheckReplaceParity('aaaa', 'aa', 'b');
end;

procedure TBpStrUtilsTests.TestReplaceFirstOnly;
begin
  CheckEquals('xbab', FastStringReplace('abab', 'a', 'x', []));
  CheckReplaceParity('abab', 'a', 'x');
end;

procedure TBpStrUtilsTests.TestReplaceIgnoreCase;
begin
  CheckEquals('x_x_x', FastStringReplace('Ab_aB_AB', 'ab', 'x', [rfReplaceAll, rfIgnoreCase]));
  CheckReplaceParity('Ab_aB_AB', 'ab', 'x');
end;

procedure TBpStrUtilsTests.TestReplaceIgnoreCaseNonAscii;
begin
  // #$C0/#$E0 are an upper/lower pair both in cp1251 (Cyrillic A) and in
  // Latin-1 (A grave), so the parity check works under D2007 and XE6
  CheckReplaceParity(#$C0#$C1 + 'x' + #$E0#$E1, #$E0#$E1, 'y');
  CheckReplaceParity(#$E0#$E0#$E0, #$C0, 'z');
end;

procedure TBpStrUtilsTests.TestReplaceSingleCharFastPath;
begin
  CheckEquals('a.b.c', FastStringReplace('a,b,c', ',', '.', [rfReplaceAll]));
  CheckReplaceParity('a,b,c', ',', '.');
  // case-insensitive single char goes through the same patch-in-place path
  CheckEquals('x_x', FastStringReplace('A_a', 'a', 'x', [rfReplaceAll, rfIgnoreCase]));
  CheckReplaceParity('A_a', 'a', 'x');
end;

procedure TBpStrUtilsTests.TestReplaceNoMatch;
begin
  CheckEquals('abc', FastStringReplace('abc', 'xy', 'z', [rfReplaceAll]));
  CheckReplaceParity('abc', 'xy', 'z');
end;

procedure TBpStrUtilsTests.TestReplaceWholeText;
begin
  CheckEquals('new', FastStringReplace('old', 'old', 'new', [rfReplaceAll]));
  CheckReplaceParity('old', 'old', 'new');
end;

procedure TBpStrUtilsTests.TestReplaceManyMatches;
var
  lvText, lvExpected: string;
  i: Integer;
begin
  // 50 matches exercise the doubling growth of the match position buffer
  lvText := '';
  lvExpected := '';
  for i := 1 to 50 do
  begin
    lvText := lvText + 'ab' + IntToStr(i);
    lvExpected := lvExpected + 'XYZ' + IntToStr(i);
  end;
  CheckEquals(lvExpected, FastStringReplace(lvText, 'ab', 'XYZ', [rfReplaceAll]));
  CheckReplaceParity(lvText, 'ab', 'XYZ');
end;

procedure TBpStrUtilsTests.TestReplaceRandomParity;
const
  lcAlphabet = 'abABxy ';
var
  lvText, lvOld, lvNew: string;
  lvCase: Integer;

  function RandomText(AMaxLen: Integer): string;
  var
    lvLen, j: Integer;
  begin
    lvLen := Random(AMaxLen + 1);
    SetLength(Result, lvLen);
    for j := 1 to lvLen do
      Result[j] := lcAlphabet[Random(Length(lcAlphabet)) + 1];
  end;

begin
  // fixed seed keeps the test deterministic
  RandSeed := 20260707;
  for lvCase := 1 to 300 do
  begin
    lvText := RandomText(60);
    lvOld := RandomText(3);
    lvNew := RandomText(5);
    CheckReplaceParity(lvText, lvOld, lvNew);
  end;
end;

procedure TBpStrUtilsTests.TestStartsWith;
begin
  CheckTrue(StartsWith('abcdef', 'abc'));
  CheckTrue(StartsWith('abc', 'abc'));
  CheckTrue(StartsWith('abc', ''));
  CheckTrue(StartsWith('', ''));
  CheckFalse(StartsWith('abc', 'abcd'));
  CheckFalse(StartsWith('abc', 'ABC'));
  CheckFalse(StartsWith('abc', 'bc'));
  CheckFalse(StartsWith('', 'a'));
end;

procedure TBpStrUtilsTests.TestEndsWith;
begin
  CheckTrue(EndsWith('abcdef', 'def'));
  CheckTrue(EndsWith('abc', 'abc'));
  CheckTrue(EndsWith('abc', ''));
  CheckTrue(EndsWith('', ''));
  CheckFalse(EndsWith('abc', 'zabc'));
  CheckFalse(EndsWith('abc', 'DEF'));
  CheckFalse(EndsWith('abc', 'ab'));
  CheckFalse(EndsWith('', 'a'));
end;

procedure TBpStrUtilsTests.TestStartsWithText;
begin
  CheckTrue(StartsWithText('AbCdef', 'abc'));
  CheckTrue(StartsWithText('abc', 'ABC'));
  CheckTrue(StartsWithText('abc', ''));
  CheckTrue(StartsWithText(#$E0#$E1 + 'x', #$C0#$C1));
  CheckFalse(StartsWithText('abc', 'abcd'));
  CheckFalse(StartsWithText('abc', 'bc'));
  CheckFalse(StartsWithText('', 'a'));
end;

procedure TBpStrUtilsTests.TestEndsWithText;
begin
  CheckTrue(EndsWithText('abcDeF', 'def'));
  CheckTrue(EndsWithText('abc', 'ABC'));
  CheckTrue(EndsWithText('abc', ''));
  CheckTrue(EndsWithText('x' + #$E0#$E1, #$C0#$C1));
  CheckFalse(EndsWithText('abc', 'zabc'));
  CheckFalse(EndsWithText('abc', 'ab'));
  CheckFalse(EndsWithText('', 'a'));
end;

initialization
  RegisterTest(TBpStrUtilsTests.Suite);

end.
