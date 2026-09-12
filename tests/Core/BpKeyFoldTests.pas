unit BpKeyFoldTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, Windows, SysUtils, BpKeyFold;

type
  TBpKeyFoldTests = class(TTestCase)
  private
    function Cp1251Lower: string;
    function Cp1251Upper: string;
  published
    procedure TestFoldedEqualityMatchesAnsiSameText;
    procedure TestFoldedEqualityOnEveryCharacterPair;
    procedure TestEqualityRejectsDifferentLengths;
    procedure TestCaseSensitiveEqualityIsExact;
    procedure TestEqualityOnNonAscii;
    procedure TestHashAgreesWithEquality;
    procedure TestHashOfASliceEqualsHashOfTheCopy;
    procedure TestHashSpreadsSimilarKeys;
    procedure TestEqualsBufMatchesEquals;
    procedure TestCompareIsOrdinal;
    procedure TestCompareAgreesWithEquality;
    procedure TestCompareIsAntisymmetric;
    procedure TestFoldIntoMatchesEquality;
    procedure TestFoldIntoRefusesAnOversizedKey;
    procedure TestFoldCharIsIdempotent;
  end;

implementation

function TBpKeyFoldTests.Cp1251Lower: string;
begin
  Result := Chr($F2) + Chr($E5) + Chr($F1) + Chr($F2);   // тест
end;

function TBpKeyFoldTests.Cp1251Upper: string;
begin
  Result := Chr($D2) + Chr($C5) + Chr($D1) + Chr($D2);   // ТЕСТ
end;

procedure TBpKeyFoldTests.TestFoldedEqualityMatchesAnsiSameText;
begin
  CheckTrue(BpKeyEquals('abc', 'ABC', True), 'plain ASCII');
  CheckTrue(BpKeyEquals('', '', True), 'two empty keys');
  CheckFalse(BpKeyEquals('abc', 'abd', True), 'different keys');
  CheckEquals(AnsiSameText('Delphi', 'DELPHI'), BpKeyEquals('Delphi', 'DELPHI', True), 'agrees with the RTL');
  CheckTrue(BpFoldedSame('Delphi', 'DELPHI'), 'the old name still works');
end;

// the fold is upper casing, which on a single byte page is AnsiSameText
procedure TBpKeyFoldTests.TestFoldedEqualityOnEveryCharacterPair;
var
  i, j, lvDisagreements: Integer;
  a, b: string;
begin
  lvDisagreements := 0;
  for i := 1 to 255 do
    for j := 1 to 255 do
    begin
      a := Chr(i);
      b := Chr(j);
      if BpKeyEquals(a, b, True) <> AnsiSameText(a, b) then
        Inc(lvDisagreements);
    end;
  CheckEquals(0, lvDisagreements, 'BpKeyEquals must agree with AnsiSameText on every pair');
end;

procedure TBpKeyFoldTests.TestEqualityRejectsDifferentLengths;
begin
  CheckFalse(BpKeyEquals('a', 'ab', True), 'shorter than');
  CheckFalse(BpKeyEquals('ab', 'a', True), 'longer than');
  CheckFalse(BpKeyEquals('', 'a', True), 'empty against non empty');
  CheckFalse(BpKeyEquals('a', 'ab', False), 'shorter than, case-sensitive');
end;

procedure TBpKeyFoldTests.TestCaseSensitiveEqualityIsExact;
begin
  CheckTrue(BpKeyEquals('abc', 'abc', False), 'same bytes');
  CheckFalse(BpKeyEquals('abc', 'ABC', False), 'case differs');
  CheckFalse(BpKeyEquals(Cp1251Lower, Cp1251Upper, False), 'non-ASCII case differs');
end;

procedure TBpKeyFoldTests.TestEqualityOnNonAscii;
begin
  // SameText is ASCII only before Unicode, which is what a naive fold gets wrong
  CheckEquals(AnsiSameText(Cp1251Lower, Cp1251Upper), BpKeyEquals(Cp1251Lower, Cp1251Upper, True),
    'a non-ASCII case pair must fold the way the RTL compares');
end;

procedure TBpKeyFoldTests.TestHashAgreesWithEquality;
var
  lvKeys: array[0..7] of string;
  i, j: Integer;
begin
  lvKeys[0] := 'Delphi';
  lvKeys[1] := 'DELPHI';
  lvKeys[2] := 'delphi';
  lvKeys[3] := Cp1251Lower;
  lvKeys[4] := Cp1251Upper;
  lvKeys[5] := '';
  lvKeys[6] := 'Delphi ';
  lvKeys[7] := 'Delphj';
  for i := 0 to High(lvKeys) do
    for j := 0 to High(lvKeys) do
    begin
      if BpKeyEquals(lvKeys[i], lvKeys[j], True) then
        CheckEquals(BpKeyHash(lvKeys[i], True), BpKeyHash(lvKeys[j], True),
          Format('folded hash of "%s" and "%s"', [lvKeys[i], lvKeys[j]]));
      if BpKeyEquals(lvKeys[i], lvKeys[j], False) then
        CheckEquals(BpKeyHash(lvKeys[i], False), BpKeyHash(lvKeys[j], False),
          Format('exact hash of "%s" and "%s"', [lvKeys[i], lvKeys[j]]));
    end;
  CheckEquals(BpKeyHash('', True), BpKeyHash('', True), 'stable for an empty key');
end;

// the name index hashes the part before the separator in place
procedure TBpKeyFoldTests.TestHashOfASliceEqualsHashOfTheCopy;
var
  lvRow: string;
begin
  lvRow := 'Host=localhost';
  CheckEquals(BpKeyHash('Host', True), BpKeyHashBuf(PChar(lvRow), 4, True), 'folded slice');
  CheckEquals(BpKeyHash('Host', False), BpKeyHashBuf(PChar(lvRow), 4, False), 'exact slice');
  CheckEquals(BpKeyHash('', False), BpKeyHashBuf(PChar(lvRow), 0, False), 'empty slice');
end;

// one character apart must mostly land in different buckets, or chains grow
procedure TBpKeyFoldTests.TestHashSpreadsSimilarKeys;
var
  i, lvUsed: Integer;
  lvSeen: array[0..1023] of Boolean;
begin
  FillChar(lvSeen, SizeOf(lvSeen), 0);
  lvUsed := 0;
  for i := 0 to 999 do
    if not lvSeen[BpKeyHash('SomeKey' + IntToStr(i), True) and 1023] then
    begin
      lvSeen[BpKeyHash('SomeKey' + IntToStr(i), True) and 1023] := True;
      Inc(lvUsed);
    end;
  // 1000 keys into 1024 buckets fill about 63 percent at random
  CheckTrue(lvUsed > 550, 'buckets used: ' + IntToStr(lvUsed));
end;

procedure TBpKeyFoldTests.TestEqualsBufMatchesEquals;
var
  lvRow: string;
begin
  lvRow := 'Host=localhost';
  CheckTrue(BpKeyEqualsBuf('HOST', PChar(lvRow), 4, True), 'folded slice');
  CheckFalse(BpKeyEqualsBuf('HOST', PChar(lvRow), 4, False), 'exact slice, case differs');
  CheckTrue(BpKeyEqualsBuf('Host', PChar(lvRow), 4, False), 'exact slice');
  CheckFalse(BpKeyEqualsBuf('Hos', PChar(lvRow), 4, True), 'length differs');
  CheckTrue(BpKeyEqualsBuf('', PChar(lvRow), 0, True), 'empty slice');
end;

procedure TBpKeyFoldTests.TestCompareIsOrdinal;
begin
  CheckTrue(BpKeyCompare('a', 'B', True) < 0, 'folded: a before B');
  CheckTrue(BpKeyCompare('B', 'a', False) < 0, 'exact: B before a, byte order');
  CheckTrue(BpKeyCompare('a', 'ab', True) < 0, 'a prefix sorts first');
  CheckTrue(BpKeyCompare('ab', 'a', True) > 0, 'and the longer one after');
  CheckEquals(0, BpKeyCompare('', '', True), 'two empty keys');
  CheckTrue(BpKeyCompare('', 'a', True) < 0, 'empty first');
  CheckTrue(BpKeyCompare('_', 'A', True) > 0, 'folded: the underscore is above A in byte order');
  CheckEquals(0, BpKeyCompare(Cp1251Lower, Cp1251Upper, True), 'non-ASCII case pair compares equal');
  CheckTrue(BpKeyCompare(Cp1251Lower, Cp1251Upper, False) > 0, 'and apart when case-sensitive');
end;

procedure TBpKeyFoldTests.TestCompareAgreesWithEquality;
var
  i, j: Integer;
  a, b: string;
begin
  for i := 1 to 255 do
    for j := 1 to 255 do
    begin
      a := Chr(i);
      b := Chr(j);
      CheckEquals(BpKeyEquals(a, b, True), BpKeyCompare(a, b, True) = 0, Format('folded %d %d', [i, j]));
      CheckEquals(BpKeyEquals(a, b, False), BpKeyCompare(a, b, False) = 0, Format('exact %d %d', [i, j]));
    end;
end;

procedure TBpKeyFoldTests.TestCompareIsAntisymmetric;
var
  i: Integer;
  a, b: string;
begin
  for i := 0 to 200 do
  begin
    a := 'key' + IntToStr(i * 7 mod 13);
    b := 'KEY' + IntToStr(i * 5 mod 11);
    CheckEquals(BpKeyCompare(a, b, True) > 0, BpKeyCompare(b, a, True) < 0, a + ' vs ' + b);
    CheckEquals(BpKeyCompare(a, b, False) > 0, BpKeyCompare(b, a, False) < 0, a + ' vs ' + b + ' exact');
  end;
end;

procedure TBpKeyFoldTests.TestFoldIntoMatchesEquality;
var
  lvBufA, lvBufB: array[0..15] of Char;
  lvLenA, lvLenB: Integer;
begin
  lvLenA := BpFoldInto('MixedCase', lvBufA, Length(lvBufA));
  lvLenB := BpFoldInto('mIXEDcASE', lvBufB, Length(lvBufB));
  if not BpKeyFoldUsable then
  begin
    CheckEquals(-1, lvLenA, 'without the table BpFoldInto must decline');
    Exit;
  end;
  CheckEquals(9, lvLenA, 'folded length');
  CheckEquals(lvLenA, lvLenB, 'same length');
  CheckTrue(CompareMem(@lvBufA, @lvBufB, lvLenA * SizeOf(Char)), 'the two folds are byte-identical');
end;

procedure TBpKeyFoldTests.TestFoldIntoRefusesAnOversizedKey;
var
  lvBuf: array[0..3] of Char;
begin
  CheckEquals(-1, BpFoldInto('far too long for this buffer', lvBuf, Length(lvBuf)),
    'BpFoldInto must decline rather than overrun, so the caller takes its slow path');
end;

procedure TBpKeyFoldTests.TestFoldCharIsIdempotent;
var
  i: Integer;
  lvCh: Char;
begin
  for i := 0 to 255 do
  begin
    lvCh := BpFoldChar(Chr(i));
    CheckEquals(lvCh, BpFoldChar(lvCh), 'folding an already folded character must not change it');
  end;
end;

initialization
  RegisterTest(TBpKeyFoldTests.Suite);

end.
