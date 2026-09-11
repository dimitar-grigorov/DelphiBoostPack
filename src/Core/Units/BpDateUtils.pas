unit BpDateUtils;

// ISO 8601 / RFC 3339 dates the RTL lacks before XE6, plus Unix epoch <->
// TDateTime. Strict parse of date-only, T or space timestamps, fractional
// seconds, the leap second and Z / +hh:mm / +hhmm / +hh zones; formats to UTC
// 'Z' or a local offset. Pairs with BpJson.
//
//   lvDt := BpISO8601ToDateTime('2026-07-24T15:30:00.250Z');
//   lvS  := BpDateTimeToISO8601(lvDt);   // '2026-07-24T15:30:00.250Z'
//
// Local is the machine zone unless a TTimeZoneInformation is passed, and the
// zone's rule is read for the date converted, not for today. Where wall clock
// and UTC are not one-to-one, RFC 5545 3.3.5 applies: a wall clock that happens
// twice means the first, and one that is skipped moves ahead by the gap.

interface

uses
  Windows, SysUtils;

type
  EbpDateTime = class(Exception);

// Strict parse. With a zone aReturnUTC picks UTC or local, without one as written
function BpTryISO8601ToDateTime(const aText: string; out aDateTime: TDateTime;
  aReturnUTC: Boolean = True): Boolean;
function BpISO8601ToDateTime(const aText: string;
  aReturnUTC: Boolean = True): TDateTime;

// Format to ISO 8601: UTC 'Z', or wall clock with the offset of the zone
function BpDateTimeToISO8601(aDateTime: TDateTime;
  aInputIsUTC: Boolean = True): string;
function BpDateTimeToISO8601Local(aDateTime: TDateTime;
  aInputIsUTC: Boolean = True): string; overload;
function BpDateTimeToISO8601Local(aDateTime: TDateTime; aInputIsUTC: Boolean;
  const aZone: TTimeZoneInformation): string; overload;

// UTC <-> wall clock, DST read for the date itself; the header states the two odd hours
function BpUtcToLocal(aUtc: TDateTime): TDateTime; overload;
function BpUtcToLocal(aUtc: TDateTime;
  const aZone: TTimeZoneInformation): TDateTime; overload;
function BpLocalToUtc(aLocal: TDateTime): TDateTime; overload;
function BpLocalToUtc(aLocal: TDateTime;
  const aZone: TTimeZoneInformation): TDateTime; overload;

// Unix epoch (UTC) <-> TDateTime, seconds and milliseconds, Int64 both ways.
function BpUnixToDateTime(aUnixSeconds: Int64): TDateTime;
function BpDateTimeToUnix(aDateTime: TDateTime): Int64;
function BpUnixMSToDateTime(aUnixMillis: Int64): TDateTime;
function BpDateTimeToUnixMS(aDateTime: TDateTime): Int64;

implementation

const
  lcUnixEpoch = 25569.0;         // TDateTime of 1970-01-01
  lcSecsPerDay = 86400;
  lcMSecsPerDay = 86400000;
  lcMinsPerDay = 1440;
  lcMaxOffsetHours = 14;         // largest real UTC offset is +14:00
  lcTimeZoneIdInvalid = DWORD($FFFFFFFF);

// TDateTime moves its fraction away from zero, so 1899-12-29 06:00 is -1.25.
// Every offset and epoch computation here goes through this pair to avoid it.
function DaysSinceEpoch(aDateTime: TDateTime): Double;
begin
  if aDateTime < 0 then
    Result := Trunc(aDateTime) - Frac(aDateTime) - lcUnixEpoch
  else
    Result := aDateTime - lcUnixEpoch;
end;

function EpochDaysToDateTime(aDays: Double): TDateTime;
var
  lvDay, lvTime: Double;
begin
  Result := aDays + lcUnixEpoch;
  if Result >= 0 then
    Exit;
  lvDay := Int(Result);
  if lvDay > Result then
    lvDay := lvDay - 1;   // Int truncates toward zero, the date needs the floor
  lvTime := Result - lvDay;
  Result := lvDay - lvTime;
end;

// an unconfigured zone counts as UTC
procedure MachineZone(out aZone: TTimeZoneInformation);
begin
  if GetTimeZoneInformation(aZone) = lcTimeZoneIdInvalid then
    FillChar(aZone, SizeOf(aZone), 0);
end;

function ZoneUtcToLocal(aUtc: TDateTime;
  const aZone: TTimeZoneInformation): TDateTime;
var
  lvUtcSt, lvLocalSt: TSystemTime;
begin
  DateTimeToSystemTime(aUtc, lvUtcSt);
  if SystemTimeToTzSpecificLocalTime(@aZone, lvUtcSt, lvLocalSt) then
    Result := SystemTimeToDateTime(lvLocalSt)
  else
    // Windows answers only for the years 1601..30827; standard time outside
    Result := EpochDaysToDateTime(DaysSinceEpoch(aUtc) -
      (aZone.Bias + aZone.StandardBias) / lcMinsPerDay);
end;

// does the UTC instant show aWallClock in aZone, to the millisecond
function ShowsWallClock(aUtcDays: Double; aWallClock: TDateTime;
  const aZone: TTimeZoneInformation): Boolean;
begin
  Result := BpDateTimeToUnixMS(ZoneUtcToLocal(EpochDaysToDateTime(aUtcDays),
    aZone)) = BpDateTimeToUnixMS(aWallClock);
end;

// Delphi 7 has no TzSpecificLocalTimeToSystemTime and Windows does not document
// its choice in the two DST hours, so try both offsets and see which one holds.
function ZoneLocalToUtc(aLocal: TDateTime;
  const aZone: TTimeZoneInformation): TDateTime;
var
  lvDays, lvStdDays, lvDstDays: Double;
  lvStdFits, lvDstFits: Boolean;
begin
  lvDays := DaysSinceEpoch(aLocal);
  lvStdDays := lvDays + (aZone.Bias + aZone.StandardBias) / lcMinsPerDay;
  lvDstDays := lvDays + (aZone.Bias + aZone.DaylightBias) / lcMinsPerDay;
  lvStdFits := ShowsWallClock(lvStdDays, aLocal, aZone);
  lvDstFits := ShowsWallClock(lvDstDays, aLocal, aZone);
  if lvStdFits <> lvDstFits then
  begin
    if lvStdFits then
      lvDays := lvStdDays
    else
      lvDays := lvDstDays;
  end
  else if lvStdFits then
  begin
    // the clock went back and shows this time twice: the first occurrence
    if lvDstDays < lvStdDays then
      lvDays := lvDstDays
    else
      lvDays := lvStdDays;
  end
  else
  begin
    // the clock skipped this time: the offset before the gap, the later instant
    if lvDstDays > lvStdDays then
      lvDays := lvDstDays
    else
      lvDays := lvStdDays;
  end;
  Result := EpochDaysToDateTime(lvDays);
end;

// read exactly aCount digits, advancing aPos
function ReadFixedInt(const aText: string; var aPos: Integer; aCount: Integer;
  out aValue: Integer): Boolean;
var
  i: Integer;
  lvCh: Char;
begin
  Result := False;
  aValue := 0;
  if aPos + aCount - 1 > Length(aText) then
    Exit;
  for i := 1 to aCount do
  begin
    lvCh := aText[aPos];
    if (lvCh < '0') or (lvCh > '9') then
      Exit;
    aValue := aValue * 10 + (Ord(lvCh) - Ord('0'));
    Inc(aPos);
  end;
  Result := True;
end;

function MatchChar(const aText: string; var aPos: Integer; aCh: Char): Boolean;
begin
  Result := (aPos <= Length(aText)) and (aText[aPos] = aCh);
  if Result then
    Inc(aPos);
end;

// fraction after '.': first three digits are ms, the rest truncated ('.5' -> 500)
function ReadFraction(const aText: string; var aPos: Integer;
  out aMSec: Integer): Boolean;
var
  lvStart, lvCount, i, lvVal: Integer;
begin
  Result := False;
  aMSec := 0;
  lvStart := aPos;
  while (aPos <= Length(aText)) and (aText[aPos] >= '0') and
    (aText[aPos] <= '9') do
    Inc(aPos);
  lvCount := aPos - lvStart;
  if lvCount = 0 then
    Exit;
  lvVal := 0;
  for i := 0 to 2 do
  begin
    lvVal := lvVal * 10;
    if i < lvCount then
      Inc(lvVal, Ord(aText[lvStart + i]) - Ord('0'));
  end;
  aMSec := lvVal;
  Result := True;
end;

// '+hh', '+hhmm' or '+hh:mm' (and the '-' forms) into signed minutes
function ReadZoneOffset(const aText: string; var aPos: Integer;
  out aOffsetMin: Integer): Boolean;
var
  lvSign, lvHour, lvMin: Integer;
begin
  Result := False;
  aOffsetMin := 0;
  lvMin := 0;
  if aText[aPos] = '+' then
    lvSign := 1
  else if aText[aPos] = '-' then
    lvSign := -1
  else
    Exit;
  Inc(aPos);
  if not ReadFixedInt(aText, aPos, 2, lvHour) then
    Exit;
  // minutes are optional, with or without the ':'
  if MatchChar(aText, aPos, ':') then
  begin
    if not ReadFixedInt(aText, aPos, 2, lvMin) then
      Exit;
  end
  else if (aPos <= Length(aText)) and (aText[aPos] >= '0') and
    (aText[aPos] <= '9') then
  begin
    if not ReadFixedInt(aText, aPos, 2, lvMin) then
      Exit;
  end;
  if (lvHour > lcMaxOffsetHours) or (lvMin > 59) then
    Exit;
  aOffsetMin := lvSign * (lvHour * 60 + lvMin);
  Result := True;
end;

function BpTryISO8601ToDateTime(const aText: string; out aDateTime: TDateTime;
  aReturnUTC: Boolean): Boolean;
var
  lvPos, lvLen: Integer;
  lvYear, lvMonth, lvDay, lvHour, lvMin, lvSec, lvMSec, lvOffsetMin: Integer;
  lvSep, lvCh: Char;
  lvDate, lvTime, lvNaive: TDateTime;
  lvUtcDays: Double;
  lvHasZone: Boolean;
begin
  Result := False;
  aDateTime := 0;
  lvLen := Length(aText);
  lvPos := 1;
  lvHour := 0;
  lvMin := 0;
  lvSec := 0;
  lvMSec := 0;
  lvOffsetMin := 0;
  lvHasZone := False;

  // date, always required: YYYY-MM-DD
  if not ReadFixedInt(aText, lvPos, 4, lvYear) then Exit;
  if not MatchChar(aText, lvPos, '-') then Exit;
  if not ReadFixedInt(aText, lvPos, 2, lvMonth) then Exit;
  if not MatchChar(aText, lvPos, '-') then Exit;
  if not ReadFixedInt(aText, lvPos, 2, lvDay) then Exit;

  // optional time, introduced by T / t / space
  if lvPos <= lvLen then
  begin
    lvSep := aText[lvPos];
    if (lvSep <> 'T') and (lvSep <> 't') and (lvSep <> ' ') then Exit;
    Inc(lvPos);
    if not ReadFixedInt(aText, lvPos, 2, lvHour) then Exit;
    if not MatchChar(aText, lvPos, ':') then Exit;
    if not ReadFixedInt(aText, lvPos, 2, lvMin) then Exit;
    if MatchChar(aText, lvPos, ':') then
    begin
      if not ReadFixedInt(aText, lvPos, 2, lvSec) then Exit;
      if MatchChar(aText, lvPos, '.') then
        if not ReadFraction(aText, lvPos, lvMSec) then Exit;
    end;
    if lvPos <= lvLen then
    begin
      lvCh := aText[lvPos];
      if (lvCh = 'Z') or (lvCh = 'z') then
      begin
        Inc(lvPos);
        lvHasZone := True;
      end
      else if (lvCh = '+') or (lvCh = '-') then
      begin
        if not ReadZoneOffset(aText, lvPos, lvOffsetMin) then Exit;
        lvHasZone := True;
      end
      else
        Exit;
    end;
  end;

  // nothing may trail the value
  if lvPos <= lvLen then Exit;

  // a leap second only falls at 23:59:60 UTC (RFC 3339 5.7), kept as its day's last ms
  if lvSec = 60 then
  begin
    if (lvHour * 60 + lvMin - lvOffsetMin + lcMinsPerDay) mod lcMinsPerDay <>
      lcMinsPerDay - 1 then Exit;
    lvSec := 59;
    lvMSec := 999;
  end;

  // TryEncode* enforce the real ranges, leap years and 24:00 included
  if not TryEncodeDate(Word(lvYear), Word(lvMonth), Word(lvDay), lvDate) then Exit;
  if not TryEncodeTime(Word(lvHour), Word(lvMin), Word(lvSec), Word(lvMSec),
    lvTime) then Exit;

  // before 1899-12-30 the date part is negative and time counts back
  if lvDate < 0 then
    lvNaive := lvDate - lvTime
  else
    lvNaive := lvDate + lvTime;

  if lvHasZone then
  begin
    lvUtcDays := DaysSinceEpoch(lvNaive) - lvOffsetMin / lcMinsPerDay;
    if aReturnUTC then
      aDateTime := EpochDaysToDateTime(lvUtcDays)
    else
      aDateTime := BpUtcToLocal(EpochDaysToDateTime(lvUtcDays));
  end
  else
    aDateTime := lvNaive;

  Result := True;
end;

function BpISO8601ToDateTime(const aText: string; aReturnUTC: Boolean): TDateTime;
begin
  if not BpTryISO8601ToDateTime(aText, Result, aReturnUTC) then
    raise EbpDateTime.CreateFmt('Invalid ISO 8601 date/time: "%s"', [aText]);
end;

function BpDateTimeToISO8601(aDateTime: TDateTime; aInputIsUTC: Boolean): string;
var
  lvUtc: TDateTime;
  lvY, lvMo, lvD, lvH, lvMi, lvS, lvMs: Word;
begin
  if aInputIsUTC then
    lvUtc := aDateTime
  else
    lvUtc := BpLocalToUtc(aDateTime);
  DecodeDate(lvUtc, lvY, lvMo, lvD);
  DecodeTime(lvUtc, lvH, lvMi, lvS, lvMs);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%.3dZ',
    [lvY, lvMo, lvD, lvH, lvMi, lvS, lvMs]);
end;

function BpDateTimeToISO8601Local(aDateTime: TDateTime; aInputIsUTC: Boolean;
  const aZone: TTimeZoneInformation): string;
var
  lvUtc, lvLocal: TDateTime;
  lvOffset, lvAbs: Int64;
  lvY, lvMo, lvD, lvH, lvMi, lvS, lvMs: Word;
  lvSign: string;
begin
  if aInputIsUTC then
    lvUtc := aDateTime
  else
    lvUtc := ZoneLocalToUtc(aDateTime, aZone);
  // from the instant even for local input, so a skipped hour prints where it moved to
  lvLocal := ZoneUtcToLocal(lvUtc, aZone);
  DecodeDate(lvLocal, lvY, lvMo, lvD);
  DecodeTime(lvLocal, lvH, lvMi, lvS, lvMs);
  // minutes east of UTC
  lvOffset := (BpDateTimeToUnixMS(lvLocal) - BpDateTimeToUnixMS(lvUtc)) div 60000;
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
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%.3d%s%.2d:%.2d',
    [lvY, lvMo, lvD, lvH, lvMi, lvS, lvMs, lvSign, lvAbs div 60, lvAbs mod 60]);
end;

function BpDateTimeToISO8601Local(aDateTime: TDateTime;
  aInputIsUTC: Boolean): string;
var
  lvZone: TTimeZoneInformation;
begin
  MachineZone(lvZone);
  Result := BpDateTimeToISO8601Local(aDateTime, aInputIsUTC, lvZone);
end;

function BpUtcToLocal(aUtc: TDateTime): TDateTime;
var
  lvZone: TTimeZoneInformation;
begin
  MachineZone(lvZone);
  Result := ZoneUtcToLocal(aUtc, lvZone);
end;

function BpUtcToLocal(aUtc: TDateTime;
  const aZone: TTimeZoneInformation): TDateTime;
begin
  Result := ZoneUtcToLocal(aUtc, aZone);
end;

function BpLocalToUtc(aLocal: TDateTime): TDateTime;
var
  lvZone: TTimeZoneInformation;
begin
  MachineZone(lvZone);
  Result := ZoneLocalToUtc(aLocal, lvZone);
end;

function BpLocalToUtc(aLocal: TDateTime;
  const aZone: TTimeZoneInformation): TDateTime;
begin
  Result := ZoneLocalToUtc(aLocal, aZone);
end;

function BpUnixToDateTime(aUnixSeconds: Int64): TDateTime;
begin
  Result := EpochDaysToDateTime(aUnixSeconds / lcSecsPerDay);
end;

function BpDateTimeToUnix(aDateTime: TDateTime): Int64;
begin
  // Round, never Trunc: a whole second can land just under itself as a float
  Result := Round(DaysSinceEpoch(aDateTime) * lcSecsPerDay);
end;

function BpUnixMSToDateTime(aUnixMillis: Int64): TDateTime;
begin
  Result := EpochDaysToDateTime(aUnixMillis / lcMSecsPerDay);
end;

function BpDateTimeToUnixMS(aDateTime: TDateTime): Int64;
begin
  Result := Round(DaysSinceEpoch(aDateTime) * lcMSecsPerDay);
end;

end.
