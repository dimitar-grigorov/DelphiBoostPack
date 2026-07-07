unit BpStringBuilderTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpStringBuilder;

type
  TBpStringBuilderTests = class(TTestCase)
  private
    FBuilder: TbpStringBuilder;
    procedure CallAppendNegativeRepeat;
    procedure CallInsertNegativeIndex;
    procedure CallInsertBeyondLength;
    procedure CallCharsNegative;
    procedure CallCharsAtLength;
    procedure CallSetCharOutOfBounds;
    procedure CallSetLengthNegative;
    procedure CallSetCapacityBelowLength;
    procedure CallCreateNegativeCapacity;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // appends
    procedure TestAppendString;
    procedure TestAppendEmptyString;
    procedure TestAppendChar;
    procedure TestAppendCharRepeat;
    procedure TestAppendInteger;
    procedure TestAppendInt64;
    procedure TestAppendDouble;
    procedure TestAppendBoolean;
    procedure TestAppendLine;
    procedure TestAppendFormat;
    procedure TestChaining;
    // insert
    procedure TestInsert;
    procedure TestInsertIntoEmpty;
    procedure TestInsertBoundsRaise;
    // buffer management
    procedure TestToStringEmpty;
    procedure TestGrowth;
    procedure TestMultiMegabyte;
    procedure TestClearKeepsCapacity;
    procedure TestCreateWithCapacity;
    procedure TestCreateWithString;
    procedure TestCapacity;
    // length and chars
    procedure TestCharsReadWrite;
    procedure TestCharsBoundsRaise;
    procedure TestLengthTruncate;
    procedure TestLengthExtendPadsZero;
    procedure TestLengthNegativeRaises;
  end;

implementation

procedure TBpStringBuilderTests.SetUp;
begin
  FBuilder := TbpStringBuilder.Create;
end;

procedure TBpStringBuilderTests.TearDown;
begin
  FreeAndNil(FBuilder);
end;

procedure TBpStringBuilderTests.TestAppendString;
begin
  FBuilder.Append('Hello');
  FBuilder.Append(', ');
  FBuilder.Append('world');
  CheckEquals('Hello, world', FBuilder.ToString);
  CheckEquals(12, FBuilder.Length);
end;

procedure TBpStringBuilderTests.TestAppendEmptyString;
begin
  FBuilder.Append('abc');
  FBuilder.Append('');
  CheckEquals('abc', FBuilder.ToString);
  CheckEquals(3, FBuilder.Length);
end;

procedure TBpStringBuilderTests.TestAppendChar;
var
  i: Integer;
begin
  for i := 1 to 5 do
    FBuilder.Append('x');
  CheckEquals('xxxxx', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.CallAppendNegativeRepeat;
begin
  FBuilder.Append('x', -1);
end;

procedure TBpStringBuilderTests.TestAppendCharRepeat;
begin
  FBuilder.Append('-', 3);
  CheckEquals('---', FBuilder.ToString);
  FBuilder.Append('x', 0);
  CheckEquals('---', FBuilder.ToString);
  CheckException(CallAppendNegativeRepeat, EbpStringBuilder, 'negative repeat count must raise');
end;

procedure TBpStringBuilderTests.TestAppendInteger;
begin
  FBuilder.Append(0);
  FBuilder.Append(Integer(42));
  FBuilder.Append(Integer(-7));
  FBuilder.Append(High(Integer));
  FBuilder.Append(Low(Integer));
  CheckEquals('042-72147483647-2147483648', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestAppendInt64;
begin
  FBuilder.Append(Int64(0));
  FBuilder.Append($1FFFFFFFF);           // 8589934591, does not fit in Integer
  FBuilder.Append(Int64(-1234567890123));
  FBuilder.Append(High(Int64));
  FBuilder.Append(Low(Int64));
  CheckEquals('08589934591-12345678901239223372036854775807-9223372036854775808',
    FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestAppendDouble;
var
  lvValue: Double;
begin
  lvValue := 1.5;
  FBuilder.Append(lvValue);
  // FloatToStr formatting is locale dependent, so compare against it directly
  CheckEquals(FloatToStr(lvValue), FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestAppendBoolean;
begin
  FBuilder.Append(True);
  FBuilder.Append(False);
  CheckEquals('TrueFalse', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestAppendLine;
begin
  FBuilder.AppendLine('first');
  FBuilder.AppendLine;
  FBuilder.Append('last');
  CheckEquals('first' + sLineBreak + sLineBreak + 'last', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestAppendFormat;
begin
  FBuilder.AppendFormat('%s=%d', ['count', 5]);
  CheckEquals('count=5', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestChaining;
begin
  FBuilder.Append('n=').Append(1).Append(' b=').Append(True).AppendLine.Append('end');
  CheckEquals('n=1 b=True' + sLineBreak + 'end', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestInsert;
begin
  FBuilder.Append('Helloworld');
  FBuilder.Insert(5, ', ');
  CheckEquals('Hello, world', FBuilder.ToString);
  FBuilder.Insert(0, '>> ');
  CheckEquals('>> Hello, world', FBuilder.ToString);
  FBuilder.Insert(FBuilder.Length, '!');
  CheckEquals('>> Hello, world!', FBuilder.ToString);
  FBuilder.Insert(3, '');
  CheckEquals('>> Hello, world!', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestInsertIntoEmpty;
begin
  FBuilder.Insert(0, 'abc');
  CheckEquals('abc', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.CallInsertNegativeIndex;
begin
  FBuilder.Insert(-1, 'x');
end;

procedure TBpStringBuilderTests.CallInsertBeyondLength;
begin
  FBuilder.Insert(FBuilder.Length + 1, 'x');
end;

procedure TBpStringBuilderTests.TestInsertBoundsRaise;
begin
  FBuilder.Append('ab');
  CheckException(CallInsertNegativeIndex, EbpStringBuilder, 'negative insert index must raise');
  CheckException(CallInsertBeyondLength, EbpStringBuilder, 'insert past the end must raise');
end;

procedure TBpStringBuilderTests.TestToStringEmpty;
begin
  CheckEquals('', FBuilder.ToString);
  CheckEquals(0, FBuilder.Length);
  CheckEquals(0, FBuilder.Capacity);
end;

procedure TBpStringBuilderTests.TestGrowth;
var
  i: Integer;
  lvExpected: string;
begin
  lvExpected := '';
  for i := 1 to 1000 do
  begin
    FBuilder.Append(i);
    FBuilder.Append(';');
    lvExpected := lvExpected + IntToStr(i) + ';';
  end;
  CheckEquals(lvExpected, FBuilder.ToString);
  Check(FBuilder.Capacity >= FBuilder.Length, 'capacity must cover the content');
end;

procedure TBpStringBuilderTests.TestMultiMegabyte;
var
  i: Integer;
  lvResult: string;
begin
  // 200k appends of a 10 char chunk = 2 MB
  for i := 1 to 200000 do
    FBuilder.Append('0123456789');
  CheckEquals(2000000, FBuilder.Length);
  lvResult := FBuilder.ToString;
  CheckEquals(2000000, System.Length(lvResult));
  CheckEquals('0', lvResult[1]);
  CheckEquals('9', lvResult[2000000]);
  CheckEquals('5', lvResult[999996]);
end;

procedure TBpStringBuilderTests.TestClearKeepsCapacity;
var
  lvCapacity: Integer;
begin
  FBuilder.Append('some content that forces an allocation');
  lvCapacity := FBuilder.Capacity;
  Check(lvCapacity > 0, 'appending must allocate');
  FBuilder.Clear;
  CheckEquals(0, FBuilder.Length);
  CheckEquals(lvCapacity, FBuilder.Capacity);
  FBuilder.Append('reuse');
  CheckEquals('reuse', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.CallCreateNegativeCapacity;
var
  lvBuilder: TbpStringBuilder;
begin
  lvBuilder := TbpStringBuilder.Create(-1);
  lvBuilder.Free; // not reached
end;

procedure TBpStringBuilderTests.TestCreateWithCapacity;
var
  lvBuilder: TbpStringBuilder;
begin
  lvBuilder := TbpStringBuilder.Create(100);
  try
    CheckEquals(100, lvBuilder.Capacity);
    CheckEquals(0, lvBuilder.Length);
  finally
    lvBuilder.Free;
  end;
  CheckException(CallCreateNegativeCapacity, EbpStringBuilder, 'negative capacity must raise');
end;

procedure TBpStringBuilderTests.TestCreateWithString;
var
  lvBuilder: TbpStringBuilder;
begin
  lvBuilder := TbpStringBuilder.Create('start');
  try
    CheckEquals('start', lvBuilder.ToString);
    CheckEquals(5, lvBuilder.Length);
  finally
    lvBuilder.Free;
  end;
end;

procedure TBpStringBuilderTests.CallSetCapacityBelowLength;
begin
  FBuilder.Capacity := FBuilder.Length - 1;
end;

procedure TBpStringBuilderTests.TestCapacity;
begin
  FBuilder.Capacity := 50;
  CheckEquals(50, FBuilder.Capacity);
  FBuilder.Append('abcdef');
  FBuilder.Capacity := 6; // shrink to fit
  CheckEquals(6, FBuilder.Capacity);
  CheckEquals('abcdef', FBuilder.ToString);
  CheckException(CallSetCapacityBelowLength, EbpStringBuilder, 'capacity below length must raise');
end;

procedure TBpStringBuilderTests.CallCharsNegative;
var
  lvChar: Char;
begin
  lvChar := FBuilder[-1];
  Check(lvChar = lvChar); // silence the unused warning, not reached
end;

procedure TBpStringBuilderTests.CallCharsAtLength;
var
  lvChar: Char;
begin
  lvChar := FBuilder[FBuilder.Length];
  Check(lvChar = lvChar); // not reached
end;

procedure TBpStringBuilderTests.CallSetCharOutOfBounds;
begin
  FBuilder[FBuilder.Length] := 'x';
end;

procedure TBpStringBuilderTests.TestCharsReadWrite;
begin
  FBuilder.Append('abc');
  CheckEquals('a', FBuilder[0]);
  CheckEquals('c', FBuilder[2]);
  FBuilder[1] := 'B';
  CheckEquals('aBc', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestCharsBoundsRaise;
begin
  FBuilder.Append('ab');
  CheckException(CallCharsNegative, EbpStringBuilder, 'negative index must raise');
  CheckException(CallCharsAtLength, EbpStringBuilder, 'index at length must raise');
  CheckException(CallSetCharOutOfBounds, EbpStringBuilder, 'write past the end must raise');
end;

procedure TBpStringBuilderTests.TestLengthTruncate;
begin
  FBuilder.Append('abcdef');
  FBuilder.Length := 3;
  CheckEquals('abc', FBuilder.ToString);
  // appending after a truncate overwrites the cut part
  FBuilder.Append('XY');
  CheckEquals('abcXY', FBuilder.ToString);
end;

procedure TBpStringBuilderTests.TestLengthExtendPadsZero;
begin
  FBuilder.Append('ab');
  FBuilder.Length := 4;
  CheckEquals(4, FBuilder.Length);
  CheckEquals('ab'#0#0, FBuilder.ToString);
end;

procedure TBpStringBuilderTests.CallSetLengthNegative;
begin
  FBuilder.Length := -1;
end;

procedure TBpStringBuilderTests.TestLengthNegativeRaises;
begin
  CheckException(CallSetLengthNegative, EbpStringBuilder, 'negative length must raise');
end;

initialization
  RegisterTest(TBpStringBuilderTests.Suite);

end.
