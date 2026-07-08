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
    procedure TestSurrogatePair;
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
    procedure TestEmptyContainersWrite;
    procedure TestRoundTripComplexDocument;
    procedure TestParseErrorsRaise;
    procedure TestTryParseReturnsFalse;
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

procedure TBpJsonTests.TestSurrogatePair;
var
  lvValue: TbpJsonValue;
begin
  // U+1F600 as the surrogate pair D83D DE00; a supplementary-plane char needs
  // a Unicode string, so this round-trip only holds on Delphi 2009 and later
{$IF CompilerVersion >= 20.0}
  lvValue := TbpJsonValue.Parse('"\uD83D\uDE00"');
  try
    // one code point survives as two UTF-16 units
    CheckEquals(2, Length(lvValue.AsStr));
    CheckEquals('"\ud83d\ude00"', LowerCase(lvValue.ToJson(True)));
  finally
    lvValue.Free;
  end;
{$IFEND}
end;

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
begin
  // the writer must ignore the locale decimal separator
  lvObj := TbpJsonValue.CreateObject;
  try
    lvObj.SetFloat('x', 1.25);
    CheckEquals('{"x":1.25}', lvObj.ToJson);
  finally
    lvObj.Free;
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
  lvI: Integer;
  lvText: string;
begin
  // 600 levels, past the 512 guard, must fail rather than crash the stack
  lvText := '';
  for lvI := 1 to 600 do
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

initialization
  RegisterTest(TBpJsonTests.Suite);

end.
