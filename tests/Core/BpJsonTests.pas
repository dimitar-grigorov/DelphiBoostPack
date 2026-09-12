unit BpJsonTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpJson;

type
  TBpJsonTests = class(TTestCase)
  private
    // helpers passed to CheckException, each parses one bad document
    procedure ParseEmpty;
    procedure ParseLeadingZero;
    procedure ParseTrailingComma;
    procedure ParseTrailingCommaArray;
    procedure ParseTextAfterValue;
    procedure ParseUnterminatedString;
    procedure ParseControlCharInString;
    procedure ParseUnpairedHighSurrogate;
    procedure ParseBadEscape;
    procedure ParseMissingColon;
    procedure ParseDeepNesting;
    procedure AsIntOnString;
    procedure GetMissingMember;
    procedure AddToNonArray;
    procedure SetOnNonObject;
  published
    procedure TestParseScalars;
    procedure TestParseNumbersIntVsFloat;
    procedure TestInt64Boundaries;
    procedure TestBigIntegerFallsBackToFloat;
    procedure TestParseObject;
    procedure TestParseArray;
    procedure TestParseNested;
    procedure TestWhitespaceAndBom;
    procedure TestDuplicateKeyKeepsLast;
    procedure TestStringEscapesRoundTrip;
    procedure TestUnicodeEscape;
    procedure TestUnicodeEscapeMatchesTheRawCharacter;
{$IF CompilerVersion >= 20.0}
    procedure TestSurrogatePair;
{$IFEND}
    procedure TestTypedAccessors;
    procedure TestTryAndDefAccessors;
    procedure TestKindMismatchRaises;
    procedure TestContainerMisuseRaises;
    procedure TestAsFloatAcceptsInt;
    procedure TestBuildObjectAndWrite;
    procedure TestBuildArrayAndWrite;
    procedure TestSetReplacesMember;
    procedure TestRemoveAndContains;
    procedure TestDeleteFromArray;
    procedure TestClone;
    procedure TestFindPath;
    procedure TestPathDefAccessors;
    procedure TestWriterEscapesControlChars;
    procedure TestWriterEscapeNonAscii;
    procedure TestPrettyPrint;
    procedure TestFloatUsesDotSeparator;
    procedure TestFloatRoundTripsThroughText;
    procedure TestEmptyContainersWrite;
    procedure TestRoundTripComplexDocument;
    procedure TestParseErrorsRaise;
    procedure TestTryParseReturnsFalse;
    procedure TestLookupOnANonObject;
    procedure TestFindPathOversizedIndex;
    procedure TestExponentPastDoubleRange;
    procedure TestBomDoesNotShiftTheReportedColumn;
    procedure TestStrictnessRejectsWhatTheDocsSayItDoes;
    procedure TestErrorPositionIsExact;
    procedure TestNegativeZeroKeepsItsSign;
    // a wide object crosses the member count where a hash index takes over
    procedure TestWideObjectFindsEveryMember;
    procedure TestWideObjectKeepsInsertionOrder;
    procedure TestWideObjectSurvivesRemoveAndReadd;
    procedure TestWideObjectDuplicateKeyKeepsLast;
    procedure TestWideObjectDeleteByIndex;
    procedure TestWideObjectClones;
    procedure TestGrowingObjectFindsEveryMemberAtEveryStep;
  end;

implementation

// a small but varied document reused by several tests
const
  gcSampleJson =
    '{' +
    '"name":"boost","version":3,"stable":true,"ratio":0.5,"note":null,' +
    '"tags":["a","b","c"],' +
    '"nested":{"count":2,"items":[{"id":1},{"id":2}]}' +
    '}';

procedure TBpJsonTests.TestParseScalars;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('true');
  try
    CheckTrue(lvValue.Kind = bjkBool);
    CheckTrue(lvValue.AsBool);
  finally
    lvValue.Free;
  end;

  lvValue := TbpJsonValue.Parse('  "hello"  ');
  try
    CheckEquals('hello', lvValue.AsStr);
  finally
    lvValue.Free;
  end;

  lvValue := TbpJsonValue.Parse('null');
  try
    CheckTrue(lvValue.IsNull);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestParseNumbersIntVsFloat;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('42');
  try
    CheckTrue(lvValue.Kind = bjkInt, 'plain integer should be bjkInt');
    CheckEquals(42, lvValue.AsInt);
  finally
    lvValue.Free;
  end;

  lvValue := TbpJsonValue.Parse('-7');
  try
    CheckEquals(-7, lvValue.AsInt);
  finally
    lvValue.Free;
  end;

  lvValue := TbpJsonValue.Parse('3.14');
  try
    CheckTrue(lvValue.Kind = bjkFloat, 'decimal should be bjkFloat');
    CheckEquals(3.14, lvValue.AsFloat, 1E-12);
  finally
    lvValue.Free;
  end;

  lvValue := TbpJsonValue.Parse('1e3');
  try
    CheckTrue(lvValue.Kind = bjkFloat, 'exponent should be bjkFloat');
    CheckEquals(1000, lvValue.AsFloat, 1E-9);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestInt64Boundaries;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('9223372036854775807');
  try
    CheckTrue(lvValue.Kind = bjkInt);
    CheckEquals(High(Int64), lvValue.AsInt);
  finally
    lvValue.Free;
  end;

  lvValue := TbpJsonValue.Parse('-9223372036854775808');
  try
    CheckTrue(lvValue.Kind = bjkInt);
    CheckEquals(Low(Int64), lvValue.AsInt);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestBigIntegerFallsBackToFloat;
var
  lvValue: TbpJsonValue;
begin
  // one past High(Int64), cannot be an Int64, must become a float
  lvValue := TbpJsonValue.Parse('9223372036854775808');
  try
    CheckTrue(lvValue.Kind = bjkFloat, 'overflowing integer should fall back to float');
    CheckEquals(9223372036854775808.0, lvValue.AsFloat, 1E3);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestParseObject;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('{"a":1,"b":"two","c":false}');
  try
    CheckTrue(lvValue.Kind = bjkObject);
    CheckEquals(3, lvValue.Count);
    CheckEquals(1, lvValue.GetInt('a'));
    CheckEquals('two', lvValue.GetStr('b'));
    CheckFalse(lvValue.GetBool('c'));
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestParseArray;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('[10,20,30]');
  try
    CheckTrue(lvValue.Kind = bjkArray);
    CheckEquals(3, lvValue.Count);
    CheckEquals(10, lvValue.Items[0].AsInt);
    CheckEquals(30, lvValue.Items[2].AsInt);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestParseNested;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    CheckEquals('boost', lvValue.GetStr('name'));
    CheckEquals(3, lvValue.GetInt('version'));
    CheckEquals(3, lvValue.Find('tags').Count);
    CheckEquals('b', lvValue.Find('tags').Items[1].AsStr);
    CheckEquals(2, lvValue.Find('nested').GetInt('count'));
    CheckEquals(2, lvValue.Find('nested').Find('items').Items[1].GetInt('id'));
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestWhitespaceAndBom;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse(#9#10#13' { "a" : [ 1 , 2 ] } '#10);
  try
    CheckEquals(2, lvValue.Find('a').Count);
  finally
    lvValue.Free;
  end;

{$IF CompilerVersion >= 20.0}
  lvValue := TbpJsonValue.Parse(#$FEFF + '{"a":1}');
{$ELSE}
  lvValue := TbpJsonValue.Parse(#$EF#$BB#$BF + '{"a":1}');
{$IFEND}
  try
    CheckEquals(1, lvValue.GetInt('a'));
  finally
    lvValue.Free;
  end;
end;

// wider than gcBpJsonIndexFrom, and wide enough to rechain the buckets twice
const
  gcWideMembers = 50;

function WideMemberName(aIndex: Integer): string;
begin
  Result := 'key' + IntToStr(aIndex);
end;

function ParseWideObject: TbpJsonValue;
var
  lvText: string;
  i: Integer;
begin
  lvText := '{';
  for i := 0 to gcWideMembers - 1 do
  begin
    if i > 0 then
      lvText := lvText + ',';
    lvText := lvText + '"' + WideMemberName(i) + '":' + IntToStr(i);
  end;
  Result := TbpJsonValue.Parse(lvText + '}');
end;

procedure TBpJsonTests.TestWideObjectFindsEveryMember;
var
  lvObj: TbpJsonValue;
  i: Integer;
begin
  lvObj := ParseWideObject;
  try
    CheckEquals(gcWideMembers, lvObj.Count);
    for i := 0 to gcWideMembers - 1 do
      CheckEquals(i, lvObj.GetInt(WideMemberName(i)), WideMemberName(i));
    CheckFalse(lvObj.Contains('key' + IntToStr(gcWideMembers)),
      'a name that was never added must not be found');
    CheckFalse(lvObj.Contains(''), 'nor must an empty name');
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestWideObjectKeepsInsertionOrder;
var
  lvObj: TbpJsonValue;
  i: Integer;
begin
  lvObj := ParseWideObject;
  try
    for i := 0 to gcWideMembers - 1 do
      CheckEquals(WideMemberName(i), lvObj.Names[i], 'position ' + IntToStr(i));
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestWideObjectSurvivesRemoveAndReadd;
var
  lvObj: TbpJsonValue;
  i: Integer;
begin
  lvObj := ParseWideObject;
  try
    // removing the first member shifts every later one, index or not
    CheckTrue(lvObj.Remove(WideMemberName(0)));
    CheckEquals(gcWideMembers - 1, lvObj.Count);
    CheckFalse(lvObj.Contains(WideMemberName(0)));
    for i := 1 to gcWideMembers - 1 do
      CheckEquals(i, lvObj.GetInt(WideMemberName(i)), WideMemberName(i));

    lvObj.SetInt(WideMemberName(0), 999);
    CheckEquals(gcWideMembers, lvObj.Count);
    CheckEquals(999, lvObj.GetInt(WideMemberName(0)), 'a re-added name is found');
    CheckEquals(WideMemberName(0), lvObj.Names[gcWideMembers - 1],
      'and lands at the end, because it is a new member');
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestWideObjectDuplicateKeyKeepsLast;
var
  lvObj: TbpJsonValue;
  lvText: string;
  i: Integer;
begin
  lvText := '{';
  for i := 0 to gcWideMembers - 1 do
    lvText := lvText + '"' + WideMemberName(i) + '":' + IntToStr(i) + ',';
  // every name once more, in the same order, with a different value
  for i := 0 to gcWideMembers - 1 do
  begin
    lvText := lvText + '"' + WideMemberName(i) + '":' + IntToStr(1000 + i);
    if i < gcWideMembers - 1 then
      lvText := lvText + ',';
  end;
  lvObj := TbpJsonValue.Parse(lvText + '}');
  try
    CheckEquals(gcWideMembers, lvObj.Count, 'duplicates collapse to one member');
    for i := 0 to gcWideMembers - 1 do
    begin
      CheckEquals(1000 + i, lvObj.GetInt(WideMemberName(i)), 'last value wins');
      CheckEquals(WideMemberName(i), lvObj.Names[i], 'at its first position');
    end;
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestWideObjectDeleteByIndex;
var
  lvObj: TbpJsonValue;
  i: Integer;
begin
  lvObj := ParseWideObject;
  try
    lvObj.Delete(gcWideMembers div 2);
    CheckEquals(gcWideMembers - 1, lvObj.Count);
    CheckFalse(lvObj.Contains(WideMemberName(gcWideMembers div 2)));
    for i := 0 to gcWideMembers - 1 do
      if i <> gcWideMembers div 2 then
        CheckEquals(i, lvObj.GetInt(WideMemberName(i)), WideMemberName(i));
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestWideObjectClones;
var
  lvObj, lvCopy: TbpJsonValue;
  i: Integer;
begin
  lvObj := ParseWideObject;
  try
    lvCopy := lvObj.Clone;
    try
      CheckEquals(gcWideMembers, lvCopy.Count);
      for i := 0 to gcWideMembers - 1 do
      begin
        CheckEquals(i, lvCopy.GetInt(WideMemberName(i)), WideMemberName(i));
        CheckEquals(WideMemberName(i), lvCopy.Names[i], 'order survives a clone');
      end;
    finally
      lvCopy.Free;
    end;
  finally
    lvObj.Free;
  end;
end;

// the crossing itself, where a scan hands over to a hash chain mid-object
procedure TBpJsonTests.TestGrowingObjectFindsEveryMemberAtEveryStep;
var
  lvObj: TbpJsonValue;
  i, j: Integer;
begin
  lvObj := TbpJsonValue.CreateObject;
  try
    for i := 0 to gcWideMembers - 1 do
    begin
      lvObj.SetInt(WideMemberName(i), i);
      CheckEquals(i + 1, lvObj.Count);
      for j := 0 to i do
        CheckEquals(j, lvObj.GetInt(WideMemberName(j)),
          Format('member %d after %d were added', [j, i + 1]));
    end;
  finally
    lvObj.Free;
  end;
end;

const
{$IF CompilerVersion >= 20.0}
  gcJsonBom = #$FEFF;
{$ELSE}
  gcJsonBom = #$EF#$BB#$BF;
{$IFEND}

function ParseErrorMessage(const aJson: string): string;
begin
  Result := '';
  try
    TbpJsonValue.Parse(aJson).Free;
  except
    on E: EbpJson do
      Result := E.Message;
  end;
end;

procedure TBpJsonTests.TestBomDoesNotShiftTheReportedColumn;
var
  lvPlain, lvWithBom: string;
begin
  // the '}' closes an object with no value for "a", at character six
  lvPlain := ParseErrorMessage('{"a":}');
  Check(Pos('position 6', lvPlain) > 0, lvPlain);
  lvWithBom := ParseErrorMessage(gcJsonBom + '{"a":}');
  CheckEquals(lvPlain, lvWithBom, 'a BOM must not move the reported position');
end;

// the only difference from plain zero is the sign bit, so read that
function IsNegativeZero(const aValue: Double): Boolean;
begin
  Result := (aValue = 0) and (PInt64(@aValue)^ <> 0);
end;

// every rule docs\FEATURES.md claims for the parser, on one document each
procedure TBpJsonTests.TestStrictnessRejectsWhatTheDocsSayItDoes;
var
  lvValue: TbpJsonValue;

  procedure CheckRejected(const aJson, aWhy: string);
  begin
    if TbpJsonValue.TryParse(aJson, lvValue) then
    try
      Fail(Format('%s was accepted; %s', [aJson, aWhy]));
    finally
      lvValue.Free;
    end;
  end;

begin
  // numbers
  CheckRejected('01', 'a leading zero means another notation');
  CheckRejected('-01', 'the sign does not excuse a leading zero');
  CheckRejected('1.', 'a decimal point needs a digit after it');
  CheckRejected('.1', 'and one before it');
  CheckRejected('+1', 'JSON has no leading plus');
  CheckRejected('1e', 'an exponent needs digits');
  CheckRejected('1e+', 'a sign is not a digit');
  CheckRejected('--1', 'one sign only');
  CheckRejected('1.2.3', 'one decimal point only');
  CheckRejected('0x10', 'JSON has no hex literal');
  CheckRejected('1 2', 'two values are not one document');
  // the non-finite spellings JavaScript accepts and JSON does not
  CheckRejected('NaN', 'JSON has no NaN');
  CheckRejected('Infinity', 'nor an Infinity');
  CheckRejected('-Infinity', 'nor a signed one');
  // literals are lower case and exact
  CheckRejected('True', 'literals are lower case');
  CheckRejected('NULL', 'including null');
  CheckRejected('nul', 'and they are not prefixes');
  CheckRejected('nulll', 'nor prefixes of something longer');
  CheckRejected('undefined', 'JSON has no undefined');
  // strings
  CheckRejected('''single''', 'JSON strings are double quoted');
  CheckRejected('"unterminated', 'a string has to close');
  CheckRejected('"a' + #9 + 'b"', 'a raw tab is a control character');
  CheckRejected('"\x41"', 'x is not an escape');
  CheckRejected('"\u12"', 'a \u escape takes four hex digits');
  CheckRejected('"\uZZZZ"', 'and they have to be hex');
  // structure
  CheckRejected('{''a'':1}', 'a member name is a double quoted string');
  CheckRejected('{a:1}', 'and it is quoted');
  CheckRejected('{,}', 'a comma needs a member on each side');
  CheckRejected('[,]', 'and an element');
  CheckRejected('[1 2]', 'elements are comma separated');
  CheckRejected('[1', 'an array has to close');
  CheckRejected('{"a":1', 'and so does an object');
  CheckRejected('', 'an empty document is not a value');
  CheckRejected('   ', 'nor is whitespace');
end;

// the line and column BpJsonFail counts are what a user is told to look at
procedure TBpJsonTests.TestErrorPositionIsExact;

  procedure CheckPosition(const aJson: string; aLine, aPos: Integer);
  var
    lvMessage, lvWanted: string;
  begin
    lvMessage := ParseErrorMessage(aJson);
    lvWanted := Format('at line %d, position %d', [aLine, aPos]);
    Check(Pos(lvWanted, lvMessage) > 0,
      Format('expected %s, got: %s', [lvWanted, lvMessage]));
  end;

begin
  CheckPosition('{"a":}', 1, 6);
  CheckPosition('  x', 1, 3);
  // a newline starts the count again, and CR carries no column of its own
  CheckPosition('{'#10'"a":'#10'x}', 3, 1);
  CheckPosition('{'#13#10'"a":'#13#10'x}', 3, 1);
  CheckPosition('['#10'1,'#10'  }'#10']', 3, 3);
  // a string spans lines only as escapes, so the column counts them as written
  CheckPosition('{'#10'  "a": "one",'#10'  "b": x'#10'}', 3, 8);
end;

procedure TBpJsonTests.TestNegativeZeroKeepsItsSign;
var
  lvValue: TbpJsonValue;

  procedure CheckSign(const aJson: string; aNegative: Boolean);
  begin
    lvValue := TbpJsonValue.Parse(aJson);
    try
      CheckEquals(aNegative, IsNegativeZero(lvValue.AsFloat), aJson);
    finally
      lvValue.Free;
    end;
  end;

begin
  CheckSign('-0.0', True);
  CheckSign('-0e5120', True);
  CheckSign('-0.000e10', True);
  CheckSign('0.0', False);
  CheckSign('0e5120', False);
  // underflow keeps the sign of the value it came from, as IEEE rounding does
  CheckSign('-1e-999999', True);
  CheckSign('1e-999999', False);

  // and it survives the writer, so a document round trips unchanged
  lvValue := TbpJsonValue.Parse('-0.0');
  try
    CheckEquals('-0', lvValue.ToJson);
  finally
    lvValue.Free;
  end;
  lvValue := TbpJsonValue.Parse('0.0');
  try
    CheckEquals('0', lvValue.ToJson);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestExponentPastDoubleRange;
var
  lvValue: TbpJsonValue;

  procedure CheckFails(const aJson: string);
  begin
    if TbpJsonValue.TryParse(aJson, lvValue) then
    try
      Fail(Format('%s parsed as %g instead of failing', [aJson, lvValue.AsFloat]));
    finally
      lvValue.Free;
    end;
  end;

  procedure CheckZero(const aJson: string);
  begin
    CheckTrue(TbpJsonValue.TryParse(aJson, lvValue), aJson + ' must parse');
    try
      CheckEquals(0, lvValue.AsFloat, aJson);
    finally
      lvValue.Free;
    end;
  end;

  procedure CheckFloat(const aJson: string; aValue: Double);
  begin
    CheckTrue(TbpJsonValue.TryParse(aJson, lvValue), aJson + ' must parse');
    try
      CheckEquals(aValue, lvValue.AsFloat, Abs(aValue) * 1E-12, aJson);
    finally
      lvValue.Free;
    end;
  end;

begin
  // past Double range, so there is no value to return and no silent infinity.
  // Python and JavaScript answer Infinity here; this unit cannot, because
  // ToJson would then have to write a literal JSON has no spelling for
  CheckFails('1e400');
  CheckFails('1e5120');
  CheckFails('-1e5120');
  CheckFails('1e99999');
  CheckFails('1e999999');
  // a zero mantissa is zero whatever the exponent says
  CheckZero('0e5120');
  CheckZero('0e999999');
  CheckZero('-0e5120');
  // and an exponent far below range underflows to zero, as every parser does
  CheckZero('1e-5120');
  CheckZero('1e-999999');
  // the edges themselves, which is where the exponent arithmetic is decided
  CheckFloat('1e308', 1E308);
  CheckFloat('9e307', 9E307);
  CheckFails('1e309');
  CheckFails('1.8e308');
  // the leading significant digit sets the power, wherever the point sits
  CheckFloat('0.0001e5', 10);
  CheckFloat('0.5', 0.5);
  CheckFloat('1234.5e305', 1.2345E308);
  CheckFails('1234.5e306');
end;

procedure TBpJsonTests.TestDuplicateKeyKeepsLast;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('{"a":1,"a":2,"a":3}');
  try
    CheckEquals(1, lvValue.Count, 'duplicate keys collapse to one member');
    CheckEquals(3, lvValue.GetInt('a'), 'last value wins');
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestStringEscapesRoundTrip;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('"a\"b\\c\/d\b\f\n\r\te"');
  try
    CheckEquals('a"b\c/d'#8#12#10#13#9'e', lvValue.AsStr);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestUnicodeEscape;
var
  lvValue: TbpJsonValue;
begin
  // \uXXXX escapes for ASCII: U+0041 U+0009 U+0042 -> 'A' tab 'B'
  lvValue := TbpJsonValue.Parse('"\u0041\u0009\u0042"');
  try
    CheckEquals('A'#9'B', lvValue.AsStr);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestUnicodeEscapeMatchesTheRawCharacter;
var
  lvEscaped, lvRaw: TbpJsonValue;
begin
  // U+00E9, U+20AC and U+1F600, once escaped and once as the raw bytes the
  // literal path already passes through. Neither may lose anything.
  lvEscaped := TbpJsonValue.Parse('"\u00e9\u20ac\ud83d\ude00"');
  try
{$IF CompilerVersion >= 20.0}
    CheckEquals(4, Length(lvEscaped.AsStr), 'two BMP chars plus a surrogate pair');
    lvRaw := TbpJsonValue.CreateStr(lvEscaped.AsStr);
{$ELSE}
    CheckEquals(9, Length(lvEscaped.AsStr), '2 + 3 + 4 UTF-8 bytes');
    lvRaw := TbpJsonValue.Parse('"'#$C3#$A9#$E2#$82#$AC#$F0#$9F#$98#$80'"');
{$IFEND}
    try
      CheckEquals(lvRaw.AsStr, lvEscaped.AsStr,
        'an escape must decode to what the raw character parses to');
      // and back out again, both spellings and both writer modes
      CheckEquals(lvRaw.ToJson, lvEscaped.ToJson);
      CheckEquals('"\u00e9\u20ac\ud83d\ude00"',
        LowerCase(lvEscaped.ToJson(True)));
    finally
      lvRaw.Free;
    end;
  finally
    lvEscaped.Free;
  end;
end;

{$IF CompilerVersion >= 20.0}
// U+1F600 as the surrogate pair D83D DE00; a supplementary-plane char needs a
// Unicode string, so this round-trip only holds on Delphi 2009 and later
procedure TBpJsonTests.TestSurrogatePair;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('"\uD83D\uDE00"');
  try
    // one code point survives as two UTF-16 units
    CheckEquals(2, Length(lvValue.AsStr));
    CheckEquals('"\ud83d\ude00"', LowerCase(lvValue.ToJson(True)));
  finally
    lvValue.Free;
  end;
end;
{$IFEND}

procedure TBpJsonTests.TestTypedAccessors;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    CheckEquals('boost', lvValue.GetStr('name'));
    CheckEquals(3, lvValue.GetInt('version'));
    CheckTrue(lvValue.GetBool('stable'));
    CheckEquals(0.5, lvValue.GetFloat('ratio'), 1E-12);
    CheckTrue(lvValue.Find('note').IsNull);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestTryAndDefAccessors;
var
  lvValue: TbpJsonValue;
  lvInt: Int64;
  lvStr: string;
begin
  lvValue := TbpJsonValue.Parse('{"a":1,"s":"x"}');
  try
    CheckTrue(lvValue.TryGetInt('a', lvInt));
    CheckEquals(1, lvInt);
    CheckFalse(lvValue.TryGetInt('missing', lvInt));
    CheckFalse(lvValue.TryGetInt('s', lvInt), 'string is not an int');
    CheckTrue(lvValue.TryGetStr('s', lvStr));
    CheckEquals('x', lvStr);

    CheckEquals(99, lvValue.GetIntDef('missing', 99));
    CheckEquals(1, lvValue.GetIntDef('a', 99));
    CheckEquals('def', lvValue.GetStrDef('missing', 'def'));
    CheckTrue(lvValue.GetBoolDef('missing', True));
    CheckEquals(2.5, lvValue.GetFloatDef('missing', 2.5), 1E-12);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestKindMismatchRaises;
begin
  CheckException(AsIntOnString, EbpJson);
  CheckException(GetMissingMember, EbpJson);
end;

procedure TBpJsonTests.TestContainerMisuseRaises;
begin
  // array-only calls on an object and object-only calls on an array both fail
  CheckException(AddToNonArray, EbpJson);
  CheckException(SetOnNonObject, EbpJson);
end;

procedure TBpJsonTests.TestAsFloatAcceptsInt;
var
  lvValue: TbpJsonValue;
begin
  // AsFloat is the one lenient accessor: an int reads as a float
  lvValue := TbpJsonValue.Parse('{"n":7}');
  try
    CheckEquals(7, lvValue.GetFloat('n'), 1E-12);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestBuildObjectAndWrite;
var
  lvObj: TbpJsonValue;
begin
  lvObj := TbpJsonValue.CreateObject;
  try
    lvObj.SetStr('name', 'boost');
    lvObj.SetInt('version', 3);
    lvObj.SetBool('stable', True);
    lvObj.SetNull('note');
    CheckEquals('{"name":"boost","version":3,"stable":true,"note":null}',
      lvObj.ToJson);
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestBuildArrayAndWrite;
var
  lvArr, lvChild: TbpJsonValue;
begin
  lvArr := TbpJsonValue.CreateArray;
  try
    lvArr.AddInt(1);
    lvArr.AddStr('two');
    lvArr.AddBool(False);
    lvArr.AddNull;
    lvChild := lvArr.AddObject;
    lvChild.SetInt('id', 9);
    CheckEquals('[1,"two",false,null,{"id":9}]', lvArr.ToJson);
  finally
    lvArr.Free;
  end;
end;

procedure TBpJsonTests.TestSetReplacesMember;
var
  lvObj: TbpJsonValue;
begin
  lvObj := TbpJsonValue.CreateObject;
  try
    lvObj.SetInt('a', 1);
    lvObj.SetInt('a', 2);
    lvObj.SetStr('a', 'now a string');
    CheckEquals(1, lvObj.Count, 'set replaces, does not append');
    CheckEquals('now a string', lvObj.GetStr('a'));
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestRemoveAndContains;
var
  lvObj: TbpJsonValue;
begin
  lvObj := TbpJsonValue.Parse('{"a":1,"b":2,"c":3}');
  try
    CheckTrue(lvObj.Contains('b'));
    CheckTrue(lvObj.Remove('b'));
    CheckFalse(lvObj.Contains('b'));
    CheckFalse(lvObj.Remove('b'), 'removing a missing member returns False');
    CheckEquals(2, lvObj.Count);
    CheckEquals(1, lvObj.GetInt('a'));
    CheckEquals(3, lvObj.GetInt('c'));
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestDeleteFromArray;
var
  lvArr: TbpJsonValue;
begin
  lvArr := TbpJsonValue.Parse('[10,20,30,40]');
  try
    lvArr.Delete(1);
    CheckEquals(3, lvArr.Count);
    CheckEquals(10, lvArr.Items[0].AsInt);
    CheckEquals(30, lvArr.Items[1].AsInt);
    CheckEquals(40, lvArr.Items[2].AsInt);
  finally
    lvArr.Free;
  end;
end;

procedure TBpJsonTests.TestClone;
var
  lvValue, lvCopy: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    lvCopy := lvValue.Clone;
    try
      CheckEquals(lvValue.ToJson, lvCopy.ToJson, 'clone serializes identically');
      // prove independence: mutating the copy must not touch the original
      lvCopy.SetStr('name', 'changed');
      CheckEquals('boost', lvValue.GetStr('name'));
      CheckEquals('changed', lvCopy.GetStr('name'));
    finally
      lvCopy.Free;
    end;
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestFindPath;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    CheckEquals('boost', lvValue.FindPath('name').AsStr);
    CheckEquals(2, lvValue.FindPath('nested.count').AsInt);
    CheckEquals(2, lvValue.FindPath('nested.items[1].id').AsInt);
    CheckEquals('c', lvValue.FindPath('tags[2]').AsStr);
    CheckNull(lvValue.FindPath('nested.missing'));
    CheckNull(lvValue.FindPath('tags[9]'), 'out of range index yields nil');
    CheckNull(lvValue.FindPath('name.deeper'), 'descending into a scalar yields nil');
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestPathDefAccessors;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    CheckEquals('boost', lvValue.PathStrDef('name', 'def'));
    CheckEquals('def', lvValue.PathStrDef('missing.path', 'def'));
    CheckEquals(2, lvValue.PathIntDef('nested.count', -1));
    CheckEquals(-1, lvValue.PathIntDef('nested.nope', -1));
    CheckEquals(0.5, lvValue.PathFloatDef('ratio', 0), 1E-12);
    CheckTrue(lvValue.PathBoolDef('stable', False));
    CheckTrue(lvValue.PathBoolDef('missing', True));
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestWriterEscapesControlChars;
var
  lvObj: TbpJsonValue;
begin
  lvObj := TbpJsonValue.CreateObject;
  try
    lvObj.SetStr('s', 'line1'#10'tab'#9'quote"back\end');
    CheckEquals('{"s":"line1\ntab\tquote\"back\\end"}', lvObj.ToJson);
  finally
    lvObj.Free;
  end;
end;

procedure TBpJsonTests.TestWriterEscapeNonAscii;
var
  lvValue: TbpJsonValue;
begin
  // a char above #127 stays literal by default, becomes \u.... when asked
  lvValue := TbpJsonValue.Parse('"\u0410"'); // U+0410 Cyrillic A, present in cp1251
  try
    CheckEquals('"\u0410"', LowerCase(lvValue.ToJson(True)));
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestPrettyPrint;
var
  lvValue: TbpJsonValue;
  lvExpected: string;
begin
  lvValue := TbpJsonValue.Parse('{"a":1,"b":[2,3]}');
  try
    lvExpected :=
      '{'#13#10 +
      '  "a": 1,'#13#10 +
      '  "b": ['#13#10 +
      '    2,'#13#10 +
      '    3'#13#10 +
      '  ]'#13#10 +
      '}';
    CheckEquals(lvExpected, lvValue.ToJsonPretty(2));
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestFloatUsesDotSeparator;
var
  lvObj: TbpJsonValue;
  lvSaved: Char;
begin
  // the writer must ignore the locale decimal separator, so move it first
{$IF CompilerVersion >= 22.0}
  lvSaved := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := ',';
{$ELSE}
  lvSaved := DecimalSeparator;
  DecimalSeparator := ',';
{$IFEND}
  try
    lvObj := TbpJsonValue.CreateObject;
    try
      lvObj.SetFloat('x', 1.25);
      CheckEquals('{"x":1.25}', lvObj.ToJson);
      // and the reader must not be fooled by it either
      lvObj.Free;
      lvObj := TbpJsonValue.Parse('{"x":2.5}');
      CheckEquals(2.5, lvObj.GetFloat('x'), 1E-12);
    finally
      lvObj.Free;
    end;
  finally
{$IF CompilerVersion >= 22.0}
    FormatSettings.DecimalSeparator := lvSaved;
{$ELSE}
    DecimalSeparator := lvSaved;
{$IFEND}
  end;
end;

// FloatToStr stops at 15 significant digits, which loses the last bits of a
// Double; the writer must emit the shortest text that reads back identically
procedure TBpJsonTests.TestFloatRoundTripsThroughText;
const
  lcValues: array[0..4] of Double = (
    0.1, 1/3, 1.7976931348623157E308,
    123456789.12345678, -0.30000000000000004);
var
  lvObj, lvBack: TbpJsonValue;
  i: Integer;
  lvJson: string;
begin
  for i := Low(lcValues) to High(lcValues) do
  begin
    lvObj := TbpJsonValue.CreateObject;
    try
      lvObj.SetFloat('v', lcValues[i]);
      lvJson := lvObj.ToJson;
    finally
      lvObj.Free;
    end;
    lvBack := TbpJsonValue.Parse(lvJson);
    try
      Check(lvBack.GetFloat('v') = lcValues[i],
        Format('%s does not round-trip: %.17g', [lvJson, lvBack.GetFloat('v')]));
    finally
      lvBack.Free;
    end;
  end;
end;

procedure TBpJsonTests.TestEmptyContainersWrite;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('{"o":{},"a":[]}');
  try
    CheckEquals('{"o":{},"a":[]}', lvValue.ToJson);
    // empty containers stay compact even when the parent is pretty-printed
    CheckEquals('{'#13#10 + '  "o": {},'#13#10 + '  "a": []'#13#10 + '}',
      lvValue.ToJsonPretty(2));
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestRoundTripComplexDocument;
var
  lvValue, lvReparsed: TbpJsonValue;
  lvText: string;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    lvText := lvValue.ToJson;
    lvReparsed := TbpJsonValue.Parse(lvText);
    try
      // writing then parsing then writing again must be stable
      CheckEquals(lvText, lvReparsed.ToJson);
    finally
      lvReparsed.Free;
    end;
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestParseErrorsRaise;
begin
  CheckException(ParseEmpty, EbpJson);
  CheckException(ParseLeadingZero, EbpJson);
  CheckException(ParseTrailingComma, EbpJson);
  CheckException(ParseTrailingCommaArray, EbpJson);
  CheckException(ParseTextAfterValue, EbpJson);
  CheckException(ParseUnterminatedString, EbpJson);
  CheckException(ParseControlCharInString, EbpJson);
  CheckException(ParseUnpairedHighSurrogate, EbpJson);
  CheckException(ParseBadEscape, EbpJson);
  CheckException(ParseMissingColon, EbpJson);
  CheckException(ParseDeepNesting, EbpJson);
end;

procedure TBpJsonTests.TestTryParseReturnsFalse;
var
  lvValue: TbpJsonValue;
begin
  CheckFalse(TbpJsonValue.TryParse('{bad', lvValue));
  CheckNull(lvValue, 'failed TryParse must not leak a value');
  CheckTrue(TbpJsonValue.TryParse('{"ok":1}', lvValue));
  try
    CheckEquals(1, lvValue.GetInt('ok'));
  finally
    lvValue.Free;
  end;
end;

// exception helpers below; each does the one illegal thing under test

procedure TBpJsonTests.ParseEmpty;
begin
  TbpJsonValue.Parse('   ').Free;
end;

procedure TBpJsonTests.ParseLeadingZero;
begin
  TbpJsonValue.Parse('012').Free;
end;

procedure TBpJsonTests.ParseTrailingComma;
begin
  TbpJsonValue.Parse('{"a":1,}').Free;
end;

procedure TBpJsonTests.ParseTrailingCommaArray;
begin
  TbpJsonValue.Parse('[1,2,]').Free;
end;

procedure TBpJsonTests.ParseTextAfterValue;
begin
  TbpJsonValue.Parse('{"a":1} garbage').Free;
end;

procedure TBpJsonTests.ParseUnterminatedString;
begin
  TbpJsonValue.Parse('"no end').Free;
end;

procedure TBpJsonTests.ParseControlCharInString;
begin
  // a raw newline inside a string is illegal, it must be escaped
  TbpJsonValue.Parse('"bad'#10'char"').Free;
end;

procedure TBpJsonTests.ParseUnpairedHighSurrogate;
begin
  TbpJsonValue.Parse('"\uD83D"').Free;
end;

procedure TBpJsonTests.ParseBadEscape;
begin
  TbpJsonValue.Parse('"\x"').Free;
end;

procedure TBpJsonTests.ParseMissingColon;
begin
  TbpJsonValue.Parse('{"a" 1}').Free;
end;

procedure TBpJsonTests.ParseDeepNesting;
var
  lvIdx: Integer;
  lvText: string;
begin
  // 600 levels, past the 512 guard, must fail rather than crash the stack
  lvText := '';
  for lvIdx := 1 to 600 do
    lvText := lvText + '[';
  TbpJsonValue.Parse(lvText).Free;
end;

procedure TBpJsonTests.AsIntOnString;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('"text"');
  try
    lvValue.AsInt;
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.GetMissingMember;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse('{"a":1}');
  try
    lvValue.GetInt('missing');
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.AddToNonArray;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.CreateObject;
  try
    lvValue.AddInt(1);
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.SetOnNonObject;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.CreateArray;
  try
    lvValue.SetInt('a', 1);
  finally
    lvValue.Free;
  end;
end;


procedure TBpJsonTests.TestLookupOnANonObject;
var
  lvValue: TbpJsonValue;
  lvStr: string;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    // the receiver is an array, so a member lookup misses rather than raising
    CheckNull(lvValue.FindPath('tags').Find('name'), 'Find');
    CheckFalse(lvValue.FindPath('tags').Contains('name'), 'Contains');
    CheckFalse(lvValue.FindPath('tags').TryGetStr('name', lvStr), 'TryGetStr');
    CheckEquals('fallback',
      lvValue.FindPath('tags').GetStrDef('name', 'fallback'), 'GetStrDef');
    // and so does a lookup on a scalar
    CheckNull(lvValue.FindPath('name').Find('anything'), 'scalar receiver');
  finally
    lvValue.Free;
  end;
end;

procedure TBpJsonTests.TestFindPathOversizedIndex;
var
  lvValue: TbpJsonValue;
begin
  lvValue := TbpJsonValue.Parse(gcSampleJson);
  try
    // the accumulator must clamp, not wrap into a valid index
    CheckNull(lvValue.FindPath('tags[2147483648]'), 'past MaxInt');
    CheckNull(lvValue.FindPath('tags[4294967296]'), 'past Cardinal');
    CheckNull(lvValue.FindPath('tags[99999999999999999999]'), 'twenty digits');
    CheckNull(lvValue.FindPath('tags[abc]'), 'not a number');
    CheckNull(lvValue.FindPath('tags[]'), 'empty index');
  finally
    lvValue.Free;
  end;
end;

initialization
  RegisterTest(TBpJsonTests.Suite);

end.
