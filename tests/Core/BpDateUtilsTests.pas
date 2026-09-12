unit BpDateUtilsTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Windows, BpDateUtils;

type
  TBpDateUtilsTests = class(TTestCase)
  private
    FEet, FUsEast, FIndia: TTimeZoneInformation;
    procedure CallBadInput;
    procedure CheckEqualsI64(aExpected, aActual: Int64; const aMsg: string = '');
    procedure CheckSameInstant(const aText, aExpectedIso: string);
    function Utc(aY, aMo, aD, aH, aMi, aSec: Word): TDateTime;
    function OffsetSuffix(const aIso: string): string;
  protected
    procedure SetUp; override;
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
    procedure TestParseLeapSecond;
    // parse: zones map to a single instant
    procedure TestZonesSameInstant;
    procedure TestParseOffsetToUtc;
    procedure TestParseOffsetBefore1899;
    procedure TestParseNaiveVerbatim;
    // parse: strict rejects
    procedure TestRejectEmpty;
    procedure TestRejectBadMonth;
    procedure TestRejectBadDay;
    procedure TestRejectBadTime;
    procedure TestRejectLeapSecondElsewhere;
    procedure TestRejectMissingDigits;
    procedure TestRejectTrailingJunk;
    procedure TestRejectGarbage;
    procedure TestRejectDanglingFraction;
    procedure TestRaisingRaises;
    // format
    procedure TestFormatUtc;
    procedure TestFormatRoundTrip;
    // local time in a fixed zone rule: same strings on every machine
    procedure TestLocalOffsetFixedZones;
    procedure TestLocalSpringForward;
    procedure TestLocalFallBack;
    procedure TestAmbiguousLocalIsFirstOccurrence;
    procedure TestSkippedLocalMovesForward;
    procedure TestLocalBefore1899;
    procedure TestLocalBefore1601;
    procedure TestLocalRoundTripAcrossYear;
    // local time in the machine zone: only what holds in every zone
    procedure TestMachineOffsetFollowsDate;
    procedure TestMachineZoneIsExplicitZone;
    procedure TestMachineLocalRoundTrip;
    procedure TestMachineParseLocal;
    // unix epoch
    procedure TestUnixEpochZero;
    procedure TestUnixKnownValue;
    procedure TestUnixPre1970;
    procedure TestUnixAnchorsBefore1900;
    procedure TestUnixPast2038;
    procedure TestUnixRoundTrip;
    procedure TestUnixMSKnown;
    procedure TestUnixMSFloatRounding;
    procedure TestUnixMSRoundTrip;
  end;

implementation

const
  cMs = 1.0 / 86400000.0;   // one millisecond as a fraction of a day
  cHour = 1.0 / 24.0;

// a recurring Windows DST rule: month, week of month (5 = last), hour, Sunday
function TransitionDate(aMonth, aWeek, aHour: Word): TSystemTime;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.wMonth := aMonth;
  Result.wDay := aWeek;
  Result.wHour := aHour;
end;

procedure TBpDateUtilsTests.SetUp;
begin
  inherited;
  // EET: +02:00, +03:00 from March's last Sunday 03:00 to October's last 04:00
  FillChar(FEet, SizeOf(FEet), 0);
  FEet.Bias := -120;
  FEet.DaylightBias := -60;
  FEet.DaylightDate := TransitionDate(3, 5, 3);
  FEet.StandardDate := TransitionDate(10, 5, 4);
  // US Eastern: -05:00, -04:00 from March's second Sunday to November's first, 02:00
  FillChar(FUsEast, SizeOf(FUsEast), 0);
  FUsEast.Bias := 300;
  FUsEast.DaylightBias := -60;
  FUsEast.DaylightDate := TransitionDate(3, 2, 2);
  FUsEast.StandardDate := TransitionDate(11, 1, 2);
  // India: +05:30, no DST, half-hour offset
  FillChar(FIndia, SizeOf(FIndia), 0);
  FIndia.Bias := -330;
end;

procedure TBpDateUtilsTests.CheckEqualsI64(aExpected, aActual: Int64;
  const aMsg: string);
begin
  Check(aExpected = aActual,
    Format('%s: expected %d but got %d', [aMsg, aExpected, aActual]));
end;

// parse to the UTC instant, format it back, and compare the ISO text
procedure TBpDateUtilsTests.CheckSameInstant(const aText, aExpectedIso: string);
begin
  CheckEquals(aExpectedIso,
    BpDateTimeToISO8601(BpISO8601ToDateTime(aText, True)), aText);
end;

function TBpDateUtilsTests.Utc(aY, aMo, aD, aH, aMi, aSec: Word): TDateTime;
begin
  Result := EncodeDate(aY, aMo, aD) + EncodeTime(aH, aMi, aSec, 0);
end;

// the '+hh:mm' tail of a local ISO string
function TBpDateUtilsTests.OffsetSuffix(const aIso: string): string;
begin
  Result := Copy(aIso, Length(aIso) - 5, 6);
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

procedure TBpDateUtilsTests.TestParseLeapSecond;
begin
  // 23:59:60 UTC is accepted and stays the last millisecond of its day
  CheckSameInstant('2026-06-30T23:59:60Z', '2026-06-30T23:59:59.999Z');
  CheckSameInstant('2026-12-31T23:59:60.5Z', '2026-12-31T23:59:59.999Z');
  // the RFC 3339 example: the leap second seen from Pacific time
  CheckSameInstant('1990-12-31T15:59:60-08:00', '1990-12-31T23:59:59.999Z');
  // and from a half-hour zone
  CheckSameInstant('2026-07-01T05:29:60+05:30', '2026-06-30T23:59:59.999Z');
  // zone-less: taken as written
  CheckEquals(EncodeDate(2026, 12, 31) + EncodeTime(23, 59, 59, 999),
    BpISO8601ToDateTime('2026-12-31T23:59:60'), cMs);
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

procedure TBpDateUtilsTests.TestParseOffsetBefore1899;
begin
  // the offset moves the clock the same way on a negative TDateTime
  CheckSameInstant('1899-12-29T06:00:00+02:00', '1899-12-29T04:00:00.000Z');
  CheckSameInstant('1899-12-29T06:00:00-02:00', '1899-12-29T08:00:00.000Z');
  CheckSameInstant('1850-06-15T18:30:00-01:30', '1850-06-15T20:00:00.000Z');
  // crossing 1899-12-30 midnight in both directions
  CheckSameInstant('1899-12-30T01:00:00+02:00', '1899-12-29T23:00:00.000Z');
  CheckSameInstant('1899-12-29T23:00:00-02:00', '1899-12-30T01:00:00.000Z');
  // the RTL's own encoding of a negative date with a time of day
  CheckEquals(EncodeDate(1899, 12, 29) - EncodeTime(4, 0, 0, 0),
    BpISO8601ToDateTime('1899-12-29T06:00:00+02:00'), cMs);
end;

procedure TBpDateUtilsTests.TestParseNaiveVerbatim;
var
  lvUtc, lvLocal: TDateTime;
begin
  // no zone: same value whatever aReturnUTC asks, nothing to convert from
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
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:61', lvDt), 'second 61');
end;

procedure TBpDateUtilsTests.TestRejectLeapSecondElsewhere;
var
  lvDt: TDateTime;
begin
  // second 60 only where a leap second can be: 23:59 UTC
  CheckFalse(BpTryISO8601ToDateTime('2026-07-24T15:30:60', lvDt), 'mid-day');
  CheckFalse(BpTryISO8601ToDateTime('2026-06-30T23:59:60+02:00', lvDt),
    '21:59 UTC');
  CheckFalse(BpTryISO8601ToDateTime('2026-06-30T23:58:60Z', lvDt), '23:58');
  CheckFalse(BpTryISO8601ToDateTime('2026-06-30T23:59:61Z', lvDt), 'second 61');
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

procedure TBpDateUtilsTests.TestLocalOffsetFixedZones;
begin
  // the same 13:00 UTC in January and July: the offset belongs to the date, not to today
  CheckEquals('2026-01-15T15:00:00.000+02:00',
    BpDateTimeToISO8601Local(Utc(2026, 1, 15, 13, 0, 0), True, FEet), 'EET jan');
  CheckEquals('2026-07-24T16:00:00.000+03:00',
    BpDateTimeToISO8601Local(Utc(2026, 7, 24, 13, 0, 0), True, FEet), 'EET jul');
  CheckEquals('2026-01-15T08:00:00.000-05:00',
    BpDateTimeToISO8601Local(Utc(2026, 1, 15, 13, 0, 0), True, FUsEast), 'US jan');
  CheckEquals('2026-07-24T09:00:00.000-04:00',
    BpDateTimeToISO8601Local(Utc(2026, 7, 24, 13, 0, 0), True, FUsEast), 'US jul');
  CheckEquals('2026-07-24T18:30:00.000+05:30',
    BpDateTimeToISO8601Local(Utc(2026, 7, 24, 13, 0, 0), True, FIndia), 'India');
  // local input, the other direction of the same rule
  CheckEquals('2026-01-15T15:00:00.000+02:00',
    BpDateTimeToISO8601Local(Utc(2026, 1, 15, 15, 0, 0), False, FEet),
    'EET jan local');
  CheckEquals('2026-07-24T16:00:00.000+03:00',
    BpDateTimeToISO8601Local(Utc(2026, 7, 24, 16, 0, 0), False, FEet),
    'EET jul local');
  CheckEquals(Utc(2026, 7, 24, 13, 0, 0),
    BpLocalToUtc(Utc(2026, 7, 24, 16, 0, 0), FEet), cMs);
  CheckEquals(Utc(2026, 1, 15, 13, 0, 0),
    BpLocalToUtc(Utc(2026, 1, 15, 15, 0, 0), FEet), cMs);
end;

procedure TBpDateUtilsTests.TestLocalSpringForward;
begin
  // 2026-03-29 01:00 UTC: 03:00 EET becomes 04:00 EEST
  CheckEquals('2026-03-29T02:59:59.000+02:00',
    BpDateTimeToISO8601Local(Utc(2026, 3, 29, 0, 59, 59), True, FEet));
  CheckEquals('2026-03-29T04:00:00.000+03:00',
    BpDateTimeToISO8601Local(Utc(2026, 3, 29, 1, 0, 0), True, FEet));
  // 2026-03-08 07:00 UTC: 02:00 EST becomes 03:00 EDT
  CheckEquals('2026-03-08T01:59:59.000-05:00',
    BpDateTimeToISO8601Local(Utc(2026, 3, 8, 6, 59, 59), True, FUsEast));
  CheckEquals('2026-03-08T03:00:00.000-04:00',
    BpDateTimeToISO8601Local(Utc(2026, 3, 8, 7, 0, 0), True, FUsEast));
end;

procedure TBpDateUtilsTests.TestLocalFallBack;
begin
  // 2026-10-25 01:00 UTC: 04:00 EEST becomes 03:00 EET
  CheckEquals('2026-10-25T03:59:59.000+03:00',
    BpDateTimeToISO8601Local(Utc(2026, 10, 25, 0, 59, 59), True, FEet));
  CheckEquals('2026-10-25T03:00:00.000+02:00',
    BpDateTimeToISO8601Local(Utc(2026, 10, 25, 1, 0, 0), True, FEet));
  // 2026-11-01 06:00 UTC: 02:00 EDT becomes 01:00 EST
  CheckEquals('2026-11-01T01:59:59.000-04:00',
    BpDateTimeToISO8601Local(Utc(2026, 11, 1, 5, 59, 59), True, FUsEast));
  CheckEquals('2026-11-01T01:00:00.000-05:00',
    BpDateTimeToISO8601Local(Utc(2026, 11, 1, 6, 0, 0), True, FUsEast));
end;

procedure TBpDateUtilsTests.TestAmbiguousLocalIsFirstOccurrence;
var
  lvFirst, lvSecond: TDateTime;
begin
  // 03:30 on 2026-10-25 happens twice in EET: 00:30Z (EEST) and 01:30Z (EET)
  lvFirst := Utc(2026, 10, 25, 0, 30, 0);
  lvSecond := Utc(2026, 10, 25, 1, 30, 0);
  CheckEquals(Utc(2026, 10, 25, 3, 30, 0), BpUtcToLocal(lvFirst, FEet), cMs,
    'first shows 03:30');
  CheckEquals(Utc(2026, 10, 25, 3, 30, 0), BpUtcToLocal(lvSecond, FEet), cMs,
    'second shows 03:30');
  // the wall clock alone resolves to the first occurrence
  CheckEquals(lvFirst, BpLocalToUtc(Utc(2026, 10, 25, 3, 30, 0), FEet), cMs,
    'first occurrence');
  CheckEquals('2026-10-25T03:30:00.000+03:00',
    BpDateTimeToISO8601Local(Utc(2026, 10, 25, 3, 30, 0), False, FEet));
  CheckEquals('2026-10-25T00:30:00.000Z',
    BpDateTimeToISO8601(BpLocalToUtc(Utc(2026, 10, 25, 3, 30, 0), FEet)));
  // so the second occurrence does not survive a trip through the wall clock
  CheckEquals(lvFirst, BpLocalToUtc(BpUtcToLocal(lvSecond, FEet), FEet), cMs,
    'second collapses to first');
  // US: 01:30 on 2026-11-01 is 05:30Z (EDT) first, 06:30Z (EST) second
  CheckEquals(Utc(2026, 11, 1, 5, 30, 0),
    BpLocalToUtc(Utc(2026, 11, 1, 1, 30, 0), FUsEast), cMs, 'US first');
  CheckEquals('2026-11-01T01:30:00.000-04:00',
    BpDateTimeToISO8601Local(Utc(2026, 11, 1, 1, 30, 0), False, FUsEast));
end;

procedure TBpDateUtilsTests.TestSkippedLocalMovesForward;
begin
  // 03:30 on 2026-03-29 never happens in EET: the offset before the gap gives 01:30Z
  CheckEquals(Utc(2026, 3, 29, 1, 30, 0),
    BpLocalToUtc(Utc(2026, 3, 29, 3, 30, 0), FEet), cMs, 'EET gap');
  CheckEquals('2026-03-29T04:30:00.000+03:00',
    BpDateTimeToISO8601Local(Utc(2026, 3, 29, 3, 30, 0), False, FEet));
  CheckEquals('2026-03-29T01:30:00.000Z',
    BpDateTimeToISO8601(BpLocalToUtc(Utc(2026, 3, 29, 3, 30, 0), FEet)));
  // US: 02:30 on 2026-03-08 is 07:30Z, shown as 03:30 EDT
  CheckEquals(Utc(2026, 3, 8, 7, 30, 0),
    BpLocalToUtc(Utc(2026, 3, 8, 2, 30, 0), FUsEast), cMs, 'US gap');
  CheckEquals('2026-03-08T03:30:00.000-04:00',
    BpDateTimeToISO8601Local(Utc(2026, 3, 8, 2, 30, 0), False, FUsEast));
  // the edges of the gap are ordinary times
  CheckEquals(Utc(2026, 3, 29, 0, 59, 59),
    BpLocalToUtc(Utc(2026, 3, 29, 2, 59, 59), FEet), cMs, 'before gap');
  CheckEquals(Utc(2026, 3, 29, 1, 0, 0),
    BpLocalToUtc(Utc(2026, 3, 29, 4, 0, 0), FEet), cMs, 'after gap');
end;

procedure TBpDateUtilsTests.TestLocalBefore1899;
var
  lvUtc: TDateTime;
begin
  // negative TDateTime both ways; the zone rule applies to 1850 too, so June is summer
  lvUtc := BpISO8601ToDateTime('1850-06-15T18:30:00Z');
  CheckEquals('1850-06-15T21:30:00.000+03:00',
    BpDateTimeToISO8601Local(lvUtc, True, FEet), 'EET 1850');
  CheckEquals('1850-06-15T14:30:00.000-04:00',
    BpDateTimeToISO8601Local(lvUtc, True, FUsEast), 'US 1850');
  CheckEquals(lvUtc, BpLocalToUtc(BpUtcToLocal(lvUtc, FEet), FEet), cMs,
    'round trip 1850');
  // the day 1899-12-29 with a time, and the offset across 1899-12-30 midnight
  CheckEquals('1899-12-29T08:00:00.000+02:00',
    BpDateTimeToISO8601Local(BpISO8601ToDateTime('1899-12-29T06:00:00Z'), True,
    FEet), '1899-12-29');
  CheckEquals('1899-12-30T01:00:00.000+02:00',
    BpDateTimeToISO8601Local(BpISO8601ToDateTime('1899-12-29T23:00:00Z'), True,
    FEet), 'across 1899-12-30');
  CheckEquals('1899-12-29T23:00:00.000Z',
    BpDateTimeToISO8601(BpLocalToUtc(EncodeDate(1899, 12, 30) +
    EncodeTime(1, 0, 0, 0), FEet)), 'back across 1899-12-30');
end;

procedure TBpDateUtilsTests.TestLocalBefore1601;
begin
  // Windows has no answer before 1601; standard time applies, no DST
  CheckEquals('1500-06-15T14:00:00.000+02:00',
    BpDateTimeToISO8601Local(BpISO8601ToDateTime('1500-06-15T12:00:00Z'), True,
    FEet));
  CheckEquals('1500-06-15T12:00:00.000Z',
    BpDateTimeToISO8601(BpLocalToUtc(BpISO8601ToDateTime('1500-06-15T14:00:00'),
    FEet)));
end;

procedure TBpDateUtilsTests.TestLocalRoundTripAcrossYear;
var
  i: Integer;
  lvUtc, lvBack: TDateTime;
  lvSecondOccurrence: Boolean;
begin
  // every hour of 2026 in EET survives the wall clock, bar the repeated hour
  for i := 0 to 365 * 24 - 1 do
  begin
    // one product per step, so no drift accumulates over the year
    lvUtc := Utc(2026, 1, 1, 0, 30, 0) + i * cHour;
    lvBack := BpLocalToUtc(BpUtcToLocal(lvUtc, FEet), FEet);
    lvSecondOccurrence := Abs(lvUtc - Utc(2026, 10, 25, 1, 30, 0)) < cMs;
    if lvSecondOccurrence then
      CheckEquals(lvUtc - cHour, lvBack, cMs, 'second occurrence')
    else
      CheckEquals(lvUtc, lvBack, cMs, BpDateTimeToISO8601(lvUtc));
  end;
end;

procedure TBpDateUtilsTests.TestMachineOffsetFollowsDate;
var
  lvZone: TTimeZoneInformation;
  lvJan, lvJul: string;
  lvObservesDst: Boolean;
begin
  // whether the machine zone has a DST rule is a fact, not the code under test
  lvObservesDst := (GetTimeZoneInformation(lvZone) <> DWORD($FFFFFFFF)) and
    (lvZone.StandardDate.wMonth <> 0) and
    (lvZone.DaylightBias <> lvZone.StandardBias);
  lvJan := BpDateTimeToISO8601Local(Utc(2026, 1, 15, 12, 0, 0), True);
  lvJul := BpDateTimeToISO8601Local(Utc(2026, 7, 15, 12, 0, 0), True);
  if lvObservesDst then
    CheckNotEquals(OffsetSuffix(lvJan), OffsetSuffix(lvJul),
      'a DST zone gives January and July different offsets')
  else
    CheckEquals(OffsetSuffix(lvJan), OffsetSuffix(lvJul),
      'a fixed zone gives one offset all year');
  // the wall clock and its offset agree on the instant
  CheckEquals('2026-01-15T12:00:00.000Z',
    BpDateTimeToISO8601(BpISO8601ToDateTime(lvJan)), lvJan);
  CheckEquals('2026-07-15T12:00:00.000Z',
    BpDateTimeToISO8601(BpISO8601ToDateTime(lvJul)), lvJul);
end;

procedure TBpDateUtilsTests.TestMachineZoneIsExplicitZone;
var
  lvZone: TTimeZoneInformation;
  lvUtc: TDateTime;
  i: Integer;
begin
  // the machine-zone entry points are the explicit ones fed GetTimeZoneInformation
  if GetTimeZoneInformation(lvZone) = DWORD($FFFFFFFF) then
    FillChar(lvZone, SizeOf(lvZone), 0);
  lvUtc := Utc(2026, 1, 1, 12, 0, 0);
  for i := 1 to 12 do
  begin
    CheckEquals(BpDateTimeToISO8601Local(lvUtc, True, lvZone),
      BpDateTimeToISO8601Local(lvUtc, True), 'format');
    CheckEquals(BpUtcToLocal(lvUtc, lvZone), BpUtcToLocal(lvUtc), cMs, 'to local');
    CheckEquals(BpLocalToUtc(lvUtc, lvZone), BpLocalToUtc(lvUtc), cMs, 'to utc');
    lvUtc := lvUtc + 30;
  end;
end;

procedure TBpDateUtilsTests.TestMachineLocalRoundTrip;
var
  i: Integer;
  lvUtc, lvLocal, lvBack: TDateTime;
begin
  // in any zone the parse back is never later and shows the same wall clock
  for i := 0 to 365 * 24 - 1 do
  begin
    lvUtc := Utc(2026, 1, 1, 0, 30, 0) + i * cHour;
    lvLocal := BpUtcToLocal(lvUtc);
    lvBack := BpLocalToUtc(lvLocal);
    CheckTrue(lvBack <= lvUtc + cMs, 'never later: ' + BpDateTimeToISO8601(lvUtc));
    CheckEquals(lvLocal, BpUtcToLocal(lvBack), cMs, 'same wall clock');
    // the wall clock with its offset always names the instant itself
    CheckEquals(BpDateTimeToISO8601(lvUtc),
      BpDateTimeToISO8601(BpISO8601ToDateTime(BpDateTimeToISO8601Local(lvUtc))),
      'local text');
  end;
end;

procedure TBpDateUtilsTests.TestMachineParseLocal;
var
  lvLocal: TDateTime;
begin
  // aReturnUTC = False yields the machine wall clock, which formats back to the UTC
  lvLocal := BpISO8601ToDateTime('2026-01-15T13:00:00Z', False);
  CheckEquals('2026-01-15T13:00:00.000Z', BpDateTimeToISO8601(lvLocal, False));
  CheckEquals(BpUtcToLocal(Utc(2026, 1, 15, 13, 0, 0)), lvLocal, cMs);
  lvLocal := BpISO8601ToDateTime('2026-07-24T15:30:45.250+02:00', False);
  CheckEquals('2026-07-24T13:30:45.250Z', BpDateTimeToISO8601(lvLocal, False));
end;

procedure TBpDateUtilsTests.TestUnixEpochZero;
begin
  CheckEqualsI64(0, BpDateTimeToUnix(EncodeDate(1970, 1, 1)), 'epoch to unix');
  CheckEquals(EncodeDate(1970, 1, 1), BpUnixToDateTime(0), cMs);
  CheckEquals('1970-01-01T00:00:00.000Z', BpDateTimeToISO8601(BpUnixToDateTime(0)));
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

procedure TBpDateUtilsTests.TestUnixAnchorsBefore1900;
begin
  // fixed instants below 1899-12-30; the numbers come from the calendar, not the code
  CheckEquals('1900-01-01T00:00:00.000Z',
    BpDateTimeToISO8601(BpUnixToDateTime(-2208988800)), '1900');
  CheckEquals('1899-12-30T00:00:00.000Z',
    BpDateTimeToISO8601(BpUnixToDateTime(-2209161600)), 'TDateTime zero');
  CheckEquals('1899-12-29T12:00:00.000Z',
    BpDateTimeToISO8601(BpUnixToDateTime(-2209204800)), 'day before, noon');
  CheckEquals('1899-12-29T18:00:00.000Z',
    BpDateTimeToISO8601(BpUnixToDateTime(-2209183200)), 'day before, 18:00');
  CheckEquals('1850-06-15T18:30:00.000Z',
    BpDateTimeToISO8601(BpUnixToDateTime(-3772503000)), '1850 with time');
  CheckEquals('1800-01-01T00:00:00.000Z',
    BpDateTimeToISO8601(BpUnixToDateTime(-5364662400)), '1800');
  CheckEqualsI64(-2208988800, BpDateTimeToUnix(EncodeDate(1900, 1, 1)), '1900 back');
  CheckEqualsI64(-2209161600, BpDateTimeToUnix(0), 'zero back');
  CheckEqualsI64(-2209204800,
    BpDateTimeToUnix(BpISO8601ToDateTime('1899-12-29T12:00:00Z')), 'noon back');
  CheckEqualsI64(-3772503000,
    BpDateTimeToUnix(BpISO8601ToDateTime('1850-06-15T18:30:00Z')), '1850 back');
  CheckEqualsI64(-3772503000,
    BpDateTimeToUnix(EncodeDate(1850, 6, 15) - EncodeTime(18, 30, 0, 0)),
    '1850 back from the RTL encoding');
  // milliseconds, same anchors plus a fraction
  CheckEquals('1850-06-15T18:30:00.250Z',
    BpDateTimeToISO8601(BpUnixMSToDateTime(-3772502999750)), '1850 ms');
  CheckEqualsI64(-3772502999750,
    BpDateTimeToUnixMS(BpISO8601ToDateTime('1850-06-15T18:30:00.250Z')),
    '1850 ms back');
  CheckEquals('1899-12-29T23:59:59.999Z',
    BpDateTimeToISO8601(BpUnixMSToDateTime(-2209161600001)), 'ms before zero');
  CheckEqualsI64(-2209161600001,
    BpDateTimeToUnixMS(BpISO8601ToDateTime('1899-12-29T23:59:59.999Z')),
    'ms before zero back');
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
  lvSecs := -6000000000;   // from 1779, past 1899-12-30, the epoch and 2038
  for i := 0 to 24 do
  begin
    CheckEqualsI64(lvSecs, BpDateTimeToUnix(BpUnixToDateTime(lvSecs)),
      Format('roundtrip %d', [lvSecs]));
    Inc(lvSecs, 350000001);
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
    // and below 1899-12-30, where the fraction counts backwards
    lvDt := EncodeDate(1850, 6, 15) - EncodeTime(12, 34, 56, Word(i));
    CheckEqualsI64(i, (BpDateTimeToUnixMS(lvDt) mod 1000 + 1000) mod 1000,
      Format('1850 ms %d', [i]));
  end;
end;

procedure TBpDateUtilsTests.TestUnixMSRoundTrip;
var
  i: Integer;
  lvMs: Int64;
begin
  lvMs := -6000000000000;   // from 1779, past 1899-12-30, the epoch and 2038
  for i := 0 to 24 do
  begin
    CheckEqualsI64(lvMs, BpDateTimeToUnixMS(BpUnixMSToDateTime(lvMs)),
      Format('ms roundtrip %d', [lvMs]));
    Inc(lvMs, 350000000123);
  end;
end;

initialization
  RegisterTest(TBpDateUtilsTests.Suite);

end.
