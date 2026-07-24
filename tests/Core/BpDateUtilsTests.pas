unit BpDateUtilsTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Windows, BpDateUtils;

type
  TBpDateUtilsTests = class(TTestCase)
  private
    procedure CallBadInput;
    function LocalBias: Integer;
    procedure CheckEqualsI64(AExpected, AActual: Int64; const AMsg: string = '');
    procedure CheckSameInstant(const AText, AExpectedIso: string);
  published
    // parse: accepted forms
    procedure TestParseDateOnly;
    procedure TestParseTimestampT;
    procedure TestParseTimestampSpace;
    procedure TestParseNoSeconds;
    procedure TestParseFractionHalf;
    procedure TestParseFraction500;
    procedure TestParseFractionTruncate;
    procedure TestParseFractionOneDigit;
    // parse: zones map to a single instant
    procedure TestZonesSameInstant;
    procedure TestParseOffsetToUtc;
    procedure TestParseNaiveVerbatim;
    // parse: strict rejects
    procedure TestRejectEmpty;
    procedure TestRejectBadMonth;
    procedure TestRejectBadDay;
    procedure TestRejectBadTime;
    procedure TestRejectMissingDigits;
    procedure TestRejectTrailingJunk;
    procedure TestRejectGarbage;
    procedure TestRejectDanglingFraction;
    procedure TestRaisingRaises;
    // format
    procedure TestFormatUtc;
    procedure TestFormatRoundTrip;
    procedure TestLocalOffsetRoundTrip;
    // unix epoch
    procedure TestUnixEpochZero;
    procedure TestUnixKnownValue;
    procedure TestUnixPre1970;
    procedure TestUnixPast2038;
    procedure TestUnixRoundTrip;
    procedure TestUnixMSKnown;
    procedure TestUnixMSFloatRounding;
    procedure TestUnixMSRoundTrip;
  end;

implementation

const
  cMs = 1.0 / 86400000.0;   // one millisecond as a fraction of a day

// mirrors the unit's private bias so the local-offset test can predict output
function TBpDateUtilsTests.LocalBias: Integer;
var
  lvTZI: TTimeZoneInformation;
  lvRet: DWORD;
begin
  lvRet := GetTimeZoneInformation(lvTZI);
  if lvRet = TIME_ZONE_ID_DAYLIGHT then
    Result := lvTZI.Bias + lvTZI.DaylightBias
  else if lvRet = DWORD($FFFFFFFF) then
    Result := 0
  else
    Result := lvTZI.Bias + lvTZI.StandardBias;
end;

procedure TBpDateUtilsTests.CheckEqualsI64(AExpected, AActual: Int64;
  const AMsg: string);
begin
  Check(AExpected = AActual,
    Format('%s: expected %d but got %d', [AMsg, AExpected, AActual]));
end;

// parse to the UTC instant, format it back, and compare the ISO text
procedure TBpDateUtilsTests.CheckSameInstant(const AText, AExpectedIso: string);
begin
  CheckEquals(AExpectedIso,
    BpDateTimeToISO8601(BpISO8601ToDateTime(AText, True)), AText);
end;

procedure TBpDateUtilsTests.TestParseDateOnly;
begin
  CheckEquals(EncodeDate(2026, 7, 24), BpISO8601ToDateTime('2026-07-24'), cMs);
end;

procedure TBpDateUtilsTests.TestParseTimestampT;
begin
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(15, 30, 45, 0),
    BpISO8601ToDateTime('2026-07-24T15:30:45'), cMs);
end;

procedure TBpDateUtilsTests.TestParseTimestampSpace;
begin
  // space separator, same value as the T form
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(15, 30, 45, 0),
    BpISO8601ToDateTime('2026-07-24 15:30:45'), cMs);
end;

procedure TBpDateUtilsTests.TestParseNoSeconds;
begin
  // hh:mm with no seconds, seconds default to 0
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(15, 30, 0, 0),
    BpISO8601ToDateTime('2026-07-24T15:30Z'), cMs);
end;

procedure TBpDateUtilsTests.TestParseFractionHalf;
begin
  // '.5' is 500 ms
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(0, 0, 0, 500),
    BpISO8601ToDateTime('2026-07-24T00:00:00.5'), cMs);
end;

procedure TBpDateUtilsTests.TestParseFraction500;
begin
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(0, 0, 0, 500),
    BpISO8601ToDateTime('2026-07-24T00:00:00.500'), cMs);
end;

procedure TBpDateUtilsTests.TestParseFractionTruncate;
begin
  // more than 3 fraction digits: keep ms, truncate the rest
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(0, 0, 0, 123),
    BpISO8601ToDateTime('2026-07-24T00:00:00.123456'), cMs);
end;

procedure TBpDateUtilsTests.TestParseFractionOneDigit;
begin
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(0, 0, 0, 100),
    BpISO8601ToDateTime('2026-07-24T00:00:00.1'), cMs);
end;

procedure TBpDateUtilsTests.TestZonesSameInstant;
begin
  // every accepted zone syntax denotes the same 13:30:45 UTC instant
  CheckSameInstant('2026-07-24T13:30:45Z',      '2026-07-24T13:30:45.000Z');
  CheckSameInstant('2026-07-24T13:30:45z',      '2026-07-24T13:30:45.000Z');
  CheckSameInstant('2026-07-24T13:30:45+00:00', '2026-07-24T13:30:45.000Z');
  CheckSameInstant('2026-07-24T15:30:45+02:00', '2026-07-24T13:30:45.000Z');
  CheckSameInstant('2026-07-24T15:30:45+0200',  '2026-07-24T13:30:45.000Z');
  CheckSameInstant('2026-07-24T14:30:45+01',    '2026-07-24T13:30:45.000Z');
  CheckSameInstant('2026-07-24T10:30:45-03:00', '2026-07-24T13:30:45.000Z');
  CheckSameInstant('2026-07-24T12:00:45-01:30', '2026-07-24T13:30:45.000Z');
end;

procedure TBpDateUtilsTests.TestParseOffsetToUtc;
begin
  // +02:00 wall clock resolves to two hours earlier in UTC
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(13, 30, 45, 0),
    BpISO8601ToDateTime('2026-07-24T15:30:45+02:00', True), cMs);
end;

procedure TBpDateUtilsTests.TestParseNaiveVerbatim;
var
  lvUtc, lvLocal: TDateTime;
begin
  // no zone: same value whatever AReturnUTC asks, nothing to convert from
  lvUtc := BpISO8601ToDateTime('2026-07-24T15:30:45', True);
  lvLocal := BpISO8601ToDateTime('2026-07-24T15:30:45', False);
  CheckEquals(lvUtc, lvLocal, cMs);
  CheckEquals(EncodeDate(2026, 7, 24) + EncodeTime(15, 30, 45, 0), lvUtc, cMs);
end;

procedure TBpDateUtilsTests.TestRejectEmpty;
var
  lvDt: TDateTime;
begin
  CheckFalse(BpTryISO8601ToDateTime('', lvDt));
end;

procedure TBpDateUtilsTests.TestRejectBadMonth;
var
  lvDt: TDateTime;
begin
  CheckFalse(BpTryISO8601ToDateTime('2026-13-01', lvDt), 'month 13');
  CheckFalse(BpTryISO8601ToDateTime('2026-00-01', lvDt), 'month 00');
end;

procedure TBpDateUtilsTests.TestRejectBadDay;
var
  lvDt: TDateTime;
begin
  CheckFalse(BpTryISO8601ToDateTime('2026-02-30', lvDt), 'feb 30');
  CheckFalse(BpTryISO8601ToDateTime('2025-02-29', lvDt), 'non-leap feb 29');
  CheckFalse(BpTryISO8601ToDateTime('2026-04-31', lvDt), 'apr 31');
end;

procedure TBpDateUtilsTests.TestRejectBadTime;
var
  lvDt: TDateTime;
begin
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T24:00:00', lvDt), 'hour 24');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:60:00', lvDt), 'minute 60');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:60', lvDt), 'second 60');
end;

procedure TBpDateUtilsTests.TestRejectMissingDigits;
var
  lvDt: TDateTime;
begin
  CheckFalse(BpTryISO8601ToDateTime('2026-7-24', lvDt), 'one-digit month');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-2', lvDt), 'one-digit day');
  CheckFalse(BpTryISO8601ToDateTime('226-07-24', lvDt), 'three-digit year');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T5:30:00', lvDt), 'one-digit hour');
end;

procedure TBpDateUtilsTests.TestRejectTrailingJunk;
var
  lvDt: TDateTime;
begin
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:00Zx', lvDt), 'after Z');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24xyz', lvDt), 'after date');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24 ', lvDt), 'trailing space');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:00+02:00 ', lvDt),
    'after offset');
end;

procedure TBpDateUtilsTests.TestRejectGarbage;
var
  lvDt: TDateTime;
begin
  CheckFalse(BpTryISO8601ToDateTime('hello', lvDt));
  CheckFalse(BpTryISO8601ToDateTime('2026/07/24', lvDt), 'slashes');
  CheckFalse(BpTryISO8601ToDateTime('24-07-2026', lvDt), 'day first');
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:00+25:00', lvDt),
    'offset hour 25');
end;

procedure TBpDateUtilsTests.TestRejectDanglingFraction;
var
  lvDt: TDateTime;
begin
  // a '.' with no digit after it is malformed
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:00.', lvDt));
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:00.Z', lvDt));
end;

procedure TBpDateUtilsTests.CallBadInput;
begin
  BpISO8601ToDateTime('2026-13-01');   // invalid month
end;

procedure TBpDateUtilsTests.TestRaisingRaises;
begin
  CheckException(CallBadInput, EbpDateTime);
end;

procedure TBpDateUtilsTests.TestFormatUtc;
begin
  CheckEquals('2026-07-24T15:30:45.250Z',
    BpDateTimeToISO8601(EncodeDate(2026, 7, 24) + EncodeTime(15, 30, 45, 250)));
  // a date-only value formats at midnight
  CheckEquals('2026-07-24T00:00:00.000Z',
    BpDateTimeToISO8601(EncodeDate(2026, 7, 24)));
end;

procedure TBpDateUtilsTests.TestFormatRoundTrip;
var
  lvDt: TDateTime;
  lvIso: string;
begin
  lvDt := EncodeDate(1985, 3, 9) + EncodeTime(7, 5, 1, 42);
  lvIso := BpDateTimeToISO8601(lvDt);
  CheckEquals('1985-03-09T07:05:01.042Z', lvIso);
  CheckEquals(lvDt, BpISO8601ToDateTime(lvIso), cMs);
end;

// the one test that reads the machine zone: the instant must survive a
// local-offset round-trip, and the emitted offset must match GetTimeZoneInformation
procedure TBpDateUtilsTests.TestLocalOffsetRoundTrip;
var
  lvUtc: TDateTime;
  lvIso, lvSign, lvSuffix: string;
  lvOffset, lvAbs: Integer;
begin
  lvUtc := EncodeDate(2026, 7, 24) + EncodeTime(13, 0, 0, 0);
  lvIso := BpDateTimeToISO8601Local(lvUtc, True);

  lvOffset := -LocalBias;   // minutes east of UTC
  if lvOffset < 0 then
  begin
    lvSign := '-';
    lvAbs := -lvOffset;
  end
  else
  begin
    lvSign := '+';
    lvAbs := lvOffset;
  end;
  lvSuffix := Format('%s%.2d:%.2d', [lvSign, lvAbs div 60, lvAbs mod 60]);
  CheckEquals(lvSuffix,
    Copy(lvIso, Length(lvIso) - Length(lvSuffix) + 1, Length(lvSuffix)),
    'offset suffix');

  // parsing the local form back to UTC returns the original instant
  CheckEquals(lvUtc, BpISO8601ToDateTime(lvIso, True), cMs);
end;

procedure TBpDateUtilsTests.TestUnixEpochZero;
begin
  CheckEqualsI64(0, BpDateTimeToUnix(EncodeDate(1970, 1, 1)), 'epoch to unix');
  CheckEquals(EncodeDate(1970, 1, 1), BpUnixToDateTime(0), cMs);
end;

procedure TBpDateUtilsTests.TestUnixKnownValue;
begin
  // 1 000 000 000 s = 2001-09-09 01:46:40 UTC
  CheckEquals(EncodeDate(2001, 9, 9) + EncodeTime(1, 46, 40, 0),
    BpUnixToDateTime(1000000000), cMs);
  CheckEqualsI64(1000000000,
    BpDateTimeToUnix(EncodeDate(2001, 9, 9) + EncodeTime(1, 46, 40, 0)),
    'known value back');
end;

procedure TBpDateUtilsTests.TestUnixPre1970;
begin
  // one second before the epoch
  CheckEqualsI64(-1,
    BpDateTimeToUnix(EncodeDate(1969, 12, 31) + EncodeTime(23, 59, 59, 0)),
    'pre-epoch -1');
  // 1960-01-01: 3653 days before the epoch
  CheckEqualsI64(-315619200, BpDateTimeToUnix(EncodeDate(1960, 1, 1)), '1960');
  CheckEquals(EncodeDate(1960, 1, 1), BpUnixToDateTime(-315619200), cMs);
end;

procedure TBpDateUtilsTests.TestUnixPast2038;
var
  lvUnix: Int64;
begin
  // 2040-01-01, well past the signed 32-bit second limit (2038-01-19)
  lvUnix := 2208988800;
  CheckTrue(lvUnix > 2147483647, 'exceeds 32-bit range');
  CheckEquals(EncodeDate(2040, 1, 1), BpUnixToDateTime(lvUnix), cMs);
  CheckEqualsI64(lvUnix, BpDateTimeToUnix(EncodeDate(2040, 1, 1)), '2040 back');
end;

procedure TBpDateUtilsTests.TestUnixRoundTrip;
var
  i: Integer;
  lvSecs: Int64;
begin
  lvSecs := -2000000000;   // crosses the epoch and 2038
  for i := 0 to 20 do
  begin
    CheckEqualsI64(lvSecs, BpDateTimeToUnix(BpUnixToDateTime(lvSecs)),
      Format('roundtrip %d', [lvSecs]));
    Inc(lvSecs, 200000000);
  end;
end;

procedure TBpDateUtilsTests.TestUnixMSKnown;
begin
  // 1 ms past the epoch must round to exactly 1, not truncate to 0
  CheckEqualsI64(1,
    BpDateTimeToUnixMS(EncodeDate(1970, 1, 1) + EncodeTime(0, 0, 0, 1)), '1 ms');
  CheckEqualsI64(1000,
    BpDateTimeToUnixMS(EncodeDate(1970, 1, 1) + EncodeTime(0, 0, 1, 0)), '1 s');
  CheckEqualsI64(1000000000123,
    BpDateTimeToUnixMS(EncodeDate(2001, 9, 9) + EncodeTime(1, 46, 40, 123)),
    'known ms');
  CheckEquals(EncodeDate(2001, 9, 9) + EncodeTime(1, 46, 40, 123),
    BpUnixMSToDateTime(1000000000123), cMs);
end;

procedure TBpDateUtilsTests.TestUnixMSFloatRounding;
var
  i: Integer;
  lvDt: TDateTime;
begin
  // every millisecond value survives the TDateTime float round-trip
  for i := 0 to 999 do
  begin
    lvDt := EncodeDate(2026, 7, 24) + EncodeTime(12, 34, 56, Word(i));
    CheckEqualsI64(i, BpDateTimeToUnixMS(lvDt) mod 1000, Format('ms %d', [i]));
  end;
end;

procedure TBpDateUtilsTests.TestUnixMSRoundTrip;
var
  i: Integer;
  lvMs: Int64;
begin
  lvMs := -2000000000000;
  for i := 0 to 20 do
  begin
    CheckEqualsI64(lvMs, BpDateTimeToUnixMS(BpUnixMSToDateTime(lvMs)),
      Format('ms roundtrip %d', [lvMs]));
    Inc(lvMs, 200000000000);
  end;
end;

initialization
  RegisterTest(TBpDateUtilsTests.Suite);

end.
