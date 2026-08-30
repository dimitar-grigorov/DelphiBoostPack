unit BpVariantUtilsTests;

{$TYPEINFO ON}

interface

uses
  TestFramework;

type
  TBpVariantUtilsTests = class(TTestCase)
  published
    procedure TestIntAcceptsIntegerKinds;
    procedure TestIntRejectsEverythingElse;
    procedure TestIntRangeLimits;
    procedure TestUnsigned64;
    procedure TestStrAcceptsStringKinds;
    procedure TestStrRoundTripsOrFails;
    procedure TestBool;
    procedure TestFloat;
    procedure TestDate;
    procedure TestIntArray;
  end;

implementation

uses
  SysUtils, Variants, BpVariantUtils;

const
  gcVarWord64 = $0015; // varWord64, missing from the D2007 headers

procedure TBpVariantUtilsTests.TestIntAcceptsIntegerKinds;
var
  lvInt: Integer;
  lvI64: Int64;
begin
  CheckTrue(BpTryVarToInt(VarAsType(7, varShortInt), lvInt), 'varShortInt');
  CheckEquals(7, lvInt);
  CheckTrue(BpTryVarToInt(VarAsType(7, varSmallint), lvInt), 'varSmallint');
  CheckTrue(BpTryVarToInt(VarAsType(7, varByte), lvInt), 'varByte');
  CheckTrue(BpTryVarToInt(VarAsType(7, varWord), lvInt), 'varWord');
  CheckTrue(BpTryVarToInt(VarAsType(7, varLongWord), lvInt), 'varLongWord');
  CheckTrue(BpTryVarToInt(VarAsType(7, varInteger), lvInt), 'varInteger');
  CheckTrue(BpTryVarToInt(VarAsType(7, varInt64), lvInt), 'varInt64');
  CheckEquals(7, lvInt);

  CheckTrue(BpTryVarToInt64(VarAsType(7, varByte), lvI64), 'Int64 from varByte');
  CheckEquals(7, Integer(lvI64));
end;

procedure TBpVariantUtilsTests.TestIntRejectsEverythingElse;
var
  lvInt: Integer;
  lvI64: Int64;
  lvVar: Variant;
  lvWhole: Double;
begin
  // nothing is parsed and nothing is rounded, and a failure zeroes the out param
  lvInt := 99;
  CheckFalse(BpTryVarToInt('42', lvInt), 'a numeric string is not an integer');
  CheckEquals(0, lvInt, 'out param zeroed on failure');

  CheckFalse(BpTryVarToInt(True, lvInt), 'Boolean');
  CheckFalse(BpTryVarToInt(3.5, lvInt), 'varDouble with a fraction');
  lvWhole := 3.0;
  CheckFalse(BpTryVarToInt(lvWhole, lvInt), 'varDouble without a fraction');
  CheckFalse(BpTryVarToInt(VarAsType(3, varCurrency), lvInt), 'varCurrency');
  CheckFalse(BpTryVarToInt(VarAsType(1.5, varSingle), lvInt), 'varSingle');
  CheckFalse(BpTryVarToInt(Null, lvInt), 'Null');
  CheckFalse(BpTryVarToInt(Unassigned, lvInt), 'Unassigned');

  lvVar := VarAsType(EncodeDate(2026, 8, 30), varDate);
  CheckFalse(BpTryVarToInt(lvVar, lvInt), 'varDate');

  lvI64 := 99;
  CheckFalse(BpTryVarToInt64('42', lvI64), 'Int64 from a string');
  CheckEquals(0, Integer(lvI64), 'out param zeroed on failure');
end;

procedure TBpVariantUtilsTests.TestIntRangeLimits;
var
  lvInt: Integer;
  lvI64: Int64;
begin
  CheckTrue(BpTryVarToInt(Int64(High(Integer)), lvInt), 'High(Integer) fits');
  CheckEquals(High(Integer), lvInt);
  CheckTrue(BpTryVarToInt(Int64(Low(Integer)), lvInt), 'Low(Integer) fits');
  CheckEquals(Low(Integer), lvInt);

  CheckFalse(BpTryVarToInt(Int64(High(Integer)) + 1, lvInt), 'one past High');
  CheckEquals(0, lvInt, 'out param zeroed on overflow');
  CheckFalse(BpTryVarToInt(Int64(Low(Integer)) - 1, lvInt), 'one below Low');

  // the same value is fine as an Int64
  CheckTrue(BpTryVarToInt64(Int64(High(Integer)) + 1, lvI64));
  CheckTrue(lvI64 = Int64(High(Integer)) + 1, 'value preserved');
end;

procedure TBpVariantUtilsTests.TestUnsigned64;
var
  lvVar: Variant;
  lvI64: Int64;
  lvFloat: Double;
begin
  // varWord64 has no header constant on D2007, so build the payload by hand;
  // a fresh local is varEmpty, so writing VType directly is safe
  TVarData(lvVar).VType := gcVarWord64;
  try
    TVarData(lvVar).VInt64 := 5;
    CheckTrue(BpTryVarToInt64(lvVar, lvI64), 'a small unsigned value converts');
    CheckEquals(5, Integer(lvI64), 'read exactly, not through a Double');

    // bit 63 set: past High(Int64), so it must fail rather than raise
    TVarData(lvVar).VInt64 := Int64($FFFFFFFFFFFFFFFF);
    lvI64 := 99;
    CheckFalse(BpTryVarToInt64(lvVar, lvI64), 'too large for Int64');
    CheckEquals(0, Integer(lvI64), 'out param zeroed on failure');

    // as a float it is representable, on the unsigned side
    CheckTrue(BpTryVarToFloat(lvVar, lvFloat), 'float accepts it');
    CheckTrue(lvFloat > 1.8e19, Format('expected ~1.84e19, got %g', [lvFloat]));
  finally
    // the RTL does not know this type, so it must not reach VarClear
    TVarData(lvVar).VType := varEmpty;
  end;
end;

procedure TBpVariantUtilsTests.TestStrAcceptsStringKinds;
var
  lvStr: string;
begin
  CheckTrue(BpTryVarToStr('hello', lvStr), 'a plain string');
  CheckEquals('hello', lvStr);
  CheckTrue(BpTryVarToStr(VarAsType('wide', varOleStr), lvStr), 'varOleStr');
  CheckEquals('wide', lvStr);

  lvStr := 'stale';
  CheckFalse(BpTryVarToStr(42, lvStr), 'an integer is not a string');
  CheckEquals('', lvStr, 'out param emptied on failure');
  CheckFalse(BpTryVarToStr(True, lvStr), 'Boolean');
  CheckFalse(BpTryVarToStr(Null, lvStr), 'Null');
  CheckFalse(BpTryVarToStr(Unassigned, lvStr), 'Unassigned');
end;

procedure TBpVariantUtilsTests.TestStrRoundTripsOrFails;
const
  lcCandidates: array[0..5] of Word =
    ($4E2D, $0416, $05D0, $0E01, $2603, $10D0);
var
  lvWide: WideString;
  lvStr: string;
  i: Integer;
  lvFound: Boolean;
begin
  // whatever comes out must mean what went in
  lvFound := False;
  for i := Low(lcCandidates) to High(lcCandidates) do
  begin
    lvWide := WideChar(lcCandidates[i]);
{$IF CompilerVersion >= 20.0}
    // a string is Unicode here, so every code point simply passes through
    CheckTrue(BpTryVarToStr(VarAsType(lvWide, varOleStr), lvStr),
      Format('U+%.4X', [lcCandidates[i]]));
    CheckEquals(lvWide, lvStr);
    lvFound := True;
{$ELSE}
    // the RTL round trip is the oracle for what this machine's page carries
    if WideString(AnsiString(lvWide)) = lvWide then
      Continue;
    lvFound := True;
    lvStr := 'stale';
    CheckFalse(BpTryVarToStr(VarAsType(lvWide, varOleStr), lvStr),
      Format('U+%.4X is not in the ANSI page, so it must not arrive as ''?''',
        [lcCandidates[i]]));
    CheckEquals('', lvStr, 'out param emptied on failure');
{$IFEND}
  end;
  Check(lvFound, 'no candidate was outside the ANSI page, nothing was tested');
end;

procedure TBpVariantUtilsTests.TestBool;
var
  lvBool: Boolean;
begin
  CheckTrue(BpTryVarToBool(True, lvBool), 'True');
  CheckTrue(lvBool);
  CheckTrue(BpTryVarToBool(False, lvBool), 'False');
  CheckFalse(lvBool);

  lvBool := True;
  CheckFalse(BpTryVarToBool(1, lvBool), 'an integer is not a Boolean');
  CheckFalse(lvBool, 'out param zeroed on failure');
  CheckFalse(BpTryVarToBool('True', lvBool), 'a string is not a Boolean');
  CheckFalse(BpTryVarToBool(Null, lvBool), 'Null');
end;

procedure TBpVariantUtilsTests.TestFloat;
var
  lvFloat: Double;
begin
  CheckTrue(BpTryVarToFloat(1.5, lvFloat), 'varDouble');
  CheckEquals(1.5, lvFloat, 0.0);
  CheckTrue(BpTryVarToFloat(VarAsType(1.5, varSingle), lvFloat), 'varSingle');
  CheckEquals(1.5, lvFloat, 0.0);
  CheckTrue(BpTryVarToFloat(VarAsType(1.5, varCurrency), lvFloat), 'varCurrency');
  CheckEquals(1.5, lvFloat, 0.0);
  CheckTrue(BpTryVarToFloat(7, lvFloat), 'an integer widens');
  CheckEquals(7, lvFloat, 0.0);

  lvFloat := 99;
  CheckFalse(BpTryVarToFloat('1.5', lvFloat), 'a numeric string');
  CheckEquals(0, lvFloat, 0.0, 'out param zeroed on failure');
  CheckFalse(BpTryVarToFloat(True, lvFloat), 'Boolean');
  CheckFalse(BpTryVarToFloat(Null, lvFloat), 'Null');
  // a date is a kind of its own here, BpTryVarToDate reads it
  CheckFalse(BpTryVarToFloat(VarAsType(EncodeDate(2026, 8, 30), varDate),
    lvFloat), 'varDate');
end;

procedure TBpVariantUtilsTests.TestDate;
var
  lvDate: TDateTime;
  lvWhen: TDateTime;
begin
  lvWhen := EncodeDate(2026, 8, 30) + EncodeTime(12, 34, 56, 0);
  CheckTrue(BpTryVarToDate(VarAsType(lvWhen, varDate), lvDate), 'varDate');
  CheckEquals(lvWhen, lvDate, 1 / 86400 / 10);

  lvDate := 99;
  CheckFalse(BpTryVarToDate(lvWhen + 0.0, lvDate), 'a bare Double is not a date');
  CheckEquals(0, lvDate, 0.0, 'out param zeroed on failure');
  CheckFalse(BpTryVarToDate('2026-08-30', lvDate), 'a date string');
  CheckFalse(BpTryVarToDate(Null, lvDate), 'Null');
end;

procedure TBpVariantUtilsTests.TestIntArray;
var
  lvArr: Variant;
  lvInts: TbpIntegerDynArray;
begin
  lvArr := VarArrayCreate([0, 2], varVariant);
  lvArr[0] := 10;
  lvArr[1] := 20;
  lvArr[2] := 30;
  CheckTrue(BpTryVarToIntArray(lvArr, lvInts), 'three integers');
  CheckEquals(3, Length(lvInts));
  CheckEquals(10, lvInts[0]);
  CheckEquals(30, lvInts[2]);

  // one bad element rejects the whole array, and leaves nothing behind
  lvArr[1] := 'twenty';
  CheckFalse(BpTryVarToIntArray(lvArr, lvInts), 'a string element');
  CheckEquals(0, Length(lvInts), 'out param cleared on failure');

  // a non-zero low bound still lands at index 0
  lvArr := VarArrayCreate([5, 6], varVariant);
  lvArr[5] := 1;
  lvArr[6] := 2;
  CheckTrue(BpTryVarToIntArray(lvArr, lvInts), 'low bound 5');
  CheckEquals(2, Length(lvInts));
  CheckEquals(1, lvInts[0]);
  CheckEquals(2, lvInts[1]);

  // more than one dimension is not a list of ids
  lvArr := VarArrayCreate([0, 1, 0, 1], varVariant);
  CheckFalse(BpTryVarToIntArray(lvArr, lvInts), 'two dimensions');

  CheckFalse(BpTryVarToIntArray(42, lvInts), 'not an array at all');
  CheckFalse(BpTryVarToIntArray(Null, lvInts), 'Null');
  CheckFalse(BpTryVarToIntArray(Unassigned, lvInts), 'Unassigned');
end;

initialization
  RegisterTest(TBpVariantUtilsTests.Suite);

end.
