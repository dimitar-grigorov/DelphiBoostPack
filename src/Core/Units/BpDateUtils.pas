unit BpDateUtils;

// ISO 8601 / RFC 3339 dates the RTL lacks before XE6, plus Unix epoch <->
// TDateTime. Strict parse of date-only, T or space timestamps, fractional
// seconds and Z / +hh:mm / +hhmm / +hh zones; formats to UTC 'Z' or a local
// offset. Pairs with BpJson.
//
//   lvDt := BpISO8601ToDateTime('2026-07-24T15:30:00.250Z');
//   lvS  := BpDateTimeToISO8601(lvDt);   // '2026-07-24T15:30:00.250Z'

interface

uses
  SysUtils;

type
  EbpDateTime = class(Exception);

// Strict ISO 8601 parse. With a zone present, aReturnUTC returns UTC or local;
// a zone-less value comes back as written (nothing to convert).
function BpTryISO8601ToDateTime(const aText: string; out aDateTime: TDateTime;
  aReturnUTC: Boolean = True): Boolean;
function BpISO8601ToDateTime(const aText: string;
  aReturnUTC: Boolean = True): TDateTime;

// Format to ISO 8601: UTC 'Z', or local wall-clock with a numeric offset.
function BpDateTimeToISO8601(aDateTime: TDateTime;
  aInputIsUTC: Boolean = True): string;
function BpDateTimeToISO8601Local(aDateTime: TDateTime;
  aInputIsUTC: Boolean = True): string;

// Unix epoch (UTC) <-> TDateTime, seconds and milliseconds, Int64 both ways.
function BpUnixToDateTime(aUnixSeconds: Int64): TDateTime;
function BpDateTimeToUnix(aDateTime: TDateTime): Int64;
function BpUnixMSToDateTime(aUnixMillis: Int64): TDateTime;
function BpDateTimeToUnixMS(aDateTime: TDateTime): Int64;

implementation

uses
  Windows;

const
  lcUnixEpoch = 25569.0;         // TDateTime of 1970-01-01
  lcSecsPerDay = 86400;
  lcMSecsPerDay = 86400000;
  lcMinsPerDay = 1440;
  lcMaxOffsetHours = 14;         // largest real UTC offset is +14:00
  lcTimeZoneIdInvalid = DWORD($FFFFFFFF);

// effective bias in minutes, UTC = local + bias, DST folded in
function LocalBiasMinutes: Integer;
var
  lvTZI: TTimeZoneInformation;
  lvRet: DWORD;
begin
  lvRet := GetTimeZoneInformation(lvTZI);
  if lvRet = TIME_ZONE_ID_DAYLIGHT then
    Result := lvTZI.Bias + lvTZI.DaylightBias
  else if lvRet = lcTimeZoneIdInvalid then
    Result := 0
  else
    Result := lvTZI.Bias + lvTZI.StandardBias;
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
  lvDate, lvTime, lvNaive, lvUtc: TDateTime;
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

  // TryEncode* enforce the real ranges, leap years and 24:00 / :60 included
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
    lvUtc := lvNaive - lvOffsetMin / lcMinsPerDay;
    if aReturnUTC then
      aDateTime := lvUtc
    else
      aDateTime := lvUtc - LocalBiasMinutes / lcMinsPerDay;
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
    lvUtc := aDateTime + LocalBiasMinutes / lcMinsPerDay;
  DecodeDate(lvUtc, lvY, lvMo, lvD);
  DecodeTime(lvUtc, lvH, lvMi, lvS, lvMs);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%.3dZ',
    [lvY, lvMo, lvD, lvH, lvMi, lvS, lvMs]);
end;

function BpDateTimeToISO8601Local(aDateTime: TDateTime;
  aInputIsUTC: Boolean): string;
var
  lvLocal: TDateTime;
  lvBias, lvOffset, lvAbs: Integer;
  lvY, lvMo, lvD, lvH, lvMi, lvS, lvMs: Word;
  lvSign: string;
begin
  lvBias := LocalBiasMinutes;
  if aInputIsUTC then
    lvLocal := aDateTime - lvBias / lcMinsPerDay
  else
    lvLocal := aDateTime;
  DecodeDate(lvLocal, lvY, lvMo, lvD);
  DecodeTime(lvLocal, lvH, lvMi, lvS, lvMs);
  lvOffset := -lvBias;   // minutes east of UTC
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

function BpUnixToDateTime(aUnixSeconds: Int64): TDateTime;
begin
  Result := lcUnixEpoch + aUnixSeconds / lcSecsPerDay;
end;

function BpDateTimeToUnix(aDateTime: TDateTime): Int64;
begin
  // Round, never Trunc: a whole second can land just under itself as a float
  Result := Round((aDateTime - lcUnixEpoch) * lcSecsPerDay);
end;

function BpUnixMSToDateTime(aUnixMillis: Int64): TDateTime;
begin
  Result := lcUnixEpoch + aUnixMillis / lcMSecsPerDay;
end;

function BpDateTimeToUnixMS(aDateTime: TDateTime): Int64;
begin
  Result := Round((aDateTime - lcUnixEpoch) * lcMSecsPerDay);
end;

end.
