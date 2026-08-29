unit BpKeyFoldTests;

interface

uses
  TestFramework, Windows, SysUtils, BpKeyFold;

type
  TBpKeyFoldTests = class(TTestCase)
  private
    function Cp1251Lower: string;
    function Cp1251Upper: string;
  published
    procedure TestFoldedSameMatchesAnsiSameText;
    procedure TestFoldedSameOnEveryCharacterPair;
    procedure TestFoldedSameRejectsDifferentLengths;
    procedure TestFoldedSameOnNonAscii;
    procedure TestHashAgreesWithEquality;
    procedure TestHashOfEmptyKey;
    procedure TestHashIsNeverNegative;
    procedure TestFoldIntoMatchesFoldedSame;
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

procedure TBpKeyFoldTests.TestFoldedSameMatchesAnsiSameText;
begin
  CheckTrue(BpFoldedSame('abc', 'ABC'), 'plain ASCII');
  CheckTrue(BpFoldedSame('', ''), 'two empty keys');
  CheckFalse(BpFoldedSame('abc', 'abd'), 'different keys');
  CheckEquals(AnsiSameText('Delphi', 'DELPHI'), BpFoldedSame('Delphi', 'DELPHI'), 'agrees with the RTL');
end;

// the whole point of the table is that it is the same relation as AnsiSameText
procedure TBpKeyFoldTests.TestFoldedSameOnEveryCharacterPair;
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
      if BpFoldedSame(a, b) <> AnsiSameText(a, b) then
        Inc(lvDisagreements);
    end;
  CheckEquals(0, lvDisagreements, 'BpFoldedSame must agree with AnsiSameText on every pair');
end;

procedure TBpKeyFoldTests.TestFoldedSameRejectsDifferentLengths;
begin
  CheckFalse(BpFoldedSame('a', 'ab'), 'shorter than');
  CheckFalse(BpFoldedSame('ab', 'a'), 'longer than');
  CheckFalse(BpFoldedSame('', 'a'), 'empty against non empty');
end;

procedure TBpKeyFoldTests.TestFoldedSameOnNonAscii;
begin
  // SameText is ASCII only before Unicode, which is what a naive fold gets wrong
  CheckEquals(AnsiSameText(Cp1251Lower, Cp1251Upper), BpFoldedSame(Cp1251Lower, Cp1251Upper),
    'a non-ASCII case pair must fold the way the RTL compares');
end;

procedure TBpKeyFoldTests.TestHashAgreesWithEquality;
var
  i, j: Integer;
  lvKeys: array[0..5] of string;
begin
  lvKeys[0] := 'Alpha';
  lvKeys[1] := 'ALPHA';
  lvKeys[2] := 'alpha';
  lvKeys[3] := 'Beta';
  lvKeys[4] := Cp1251Lower;
  lvKeys[5] := Cp1251Upper;
  for i := 0 to High(lvKeys) do
    for j := 0 to High(lvKeys) do
      if BpFoldedSame(lvKeys[i], lvKeys[j]) then
        CheckEquals(BpFoldedHash(lvKeys[i]), BpFoldedHash(lvKeys[j]),
          'equal keys must hash the same, otherwise a lookup misses a key that is there');
end;

procedure TBpKeyFoldTests.TestHashOfEmptyKey;
begin
  CheckEquals(BpFoldedHash(''), BpFoldedHash(''), 'stable for an empty key');
end;

procedure TBpKeyFoldTests.TestHashIsNeverNegative;
var
  i: Integer;
begin
  for i := 1 to 500 do
    Check(BpFoldedHash('key' + IntToStr(i) + Chr(200 + i mod 50)) >= 0,
      'a negative hash would break an and-mask bucket index');
end;

procedure TBpKeyFoldTests.TestFoldIntoMatchesFoldedSame;
var
  lvBufA, lvBufB: array[0..63] of Char;
  lvLenA, lvLenB, i: Integer;
begin
  lvLenA := BpFoldInto('MixedCase', lvBufA, Length(lvBufA));
  lvLenB := BpFoldInto('mIXEDcASE', lvBufB, Length(lvBufB));
  if not BpKeyFoldUsable then
  begin
    CheckEquals(-1, lvLenA, 'without the table BpFoldInto must decline');
    Exit;
  end;
  CheckEquals(9, lvLenA, 'folded length');
  CheckEquals(lvLenA, lvLenB, 'both fold to the same length');
  for i := 0 to lvLenA - 1 do
    CheckEquals(lvBufA[i], lvBufB[i], 'the folded bytes must match at ' + IntToStr(i));
end;

procedure TBpKeyFoldTests.TestFoldIntoRefusesAnOversizedKey;
var
  lvBuf: array[0..7] of Char;
begin
  CheckEquals(-1, BpFoldInto('far too long for this buffer', lvBuf, Length(lvBuf)),
    'BpFoldInto must decline rather than overrun, so the caller takes its slow path');
end;

procedure TBpKeyFoldTests.TestFoldCharIsIdempotent;
var
  i: Integer;
  lvCh: Char;
begin
  for i := 1 to 255 do
  begin
    lvCh := BpFoldChar(Chr(i));
    CheckEquals(lvCh, BpFoldChar(lvCh), 'folding an already folded character must not change it');
  end;
end;

initialization
  RegisterTest(TBpKeyFoldTests.Suite);

end.
