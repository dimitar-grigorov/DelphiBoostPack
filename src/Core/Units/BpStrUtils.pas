unit BpStrUtils;

// String helpers that D2007 lacks: Split, Join, a fast StringReplace and
// StartsWith / EndsWith checks (ordinal and locale case-insensitive).
//
// FastStringReplace uses the FastCode project idea (StringReplace_JOH_PAS):
// collect all match positions first, then allocate the exact result size once
// and stream the pieces with Move. SysUtils.StringReplace instead copies the
// whole remaining string on every match, which goes quadratic on many matches.
// Case-insensitive mode folds text and pattern once with AnsiUpperCase (the
// same locale fold the RTL uses), searches the folded copy and copies from
// the original, so results match SysUtils.StringReplace exactly.
//
// Split('' ) returns an empty array; delimiters at the ends produce empty
// elements ('a,' gives 'a' and ''), matching XE6 SplitString and .NET.
// The string-delimiter overload treats the whole delimiter as one separator.
//
// StartsWith / EndsWith compare bytes without allocating; the *Text variants
// are locale case-insensitive via CompareString, the API behind AnsiSameText.
// Note for D2007 MBCS locales: EndsWithText anchors at a byte offset, so a
// suffix starting inside a double-byte character is compared as-is (the RTL
// AnsiEndsText has the same behavior).

interface

uses
  SysUtils;

type
  TbpStringArray = array of string;

function Split(const AText: string; ADelimiter: Char): TbpStringArray; overload;
function Split(const AText, ADelimiter: string): TbpStringArray; overload;
function Join(const AValues: array of string; const ASeparator: string): string;
function FastStringReplace(const AText, AOldPattern, ANewPattern: string;
  AFlags: TReplaceFlags): string;
function StartsWith(const AText, APrefix: string): Boolean;
function EndsWith(const AText, ASuffix: string): Boolean;
function StartsWithText(const AText, APrefix: string): Boolean;
function EndsWithText(const AText, ASuffix: string): Boolean;

implementation

uses
  Windows, StrUtils;

function Split(const AText: string; ADelimiter: Char): TbpStringArray;
var
  lvSource: PChar;
  lvTextLen, lvCount, lvIndex, lvStart, lvPos: Integer;
begin
  Result := nil;
  lvTextLen := Length(AText);
  if lvTextLen = 0 then
    Exit;
  // count delimiters so the result array is allocated exactly once
  lvSource := Pointer(AText);
  lvCount := 0;
  for lvPos := 0 to lvTextLen - 1 do
    if lvSource[lvPos] = ADelimiter then
      Inc(lvCount);
  SetLength(Result, lvCount + 1);
  lvIndex := 0;
  lvStart := 0;
  for lvPos := 0 to lvTextLen - 1 do
    if lvSource[lvPos] = ADelimiter then
    begin
      SetString(Result[lvIndex], lvSource + lvStart, lvPos - lvStart);
      Inc(lvIndex);
      lvStart := lvPos + 1;
    end;
  SetString(Result[lvIndex], lvSource + lvStart, lvTextLen - lvStart);
end;

function Split(const AText, ADelimiter: string): TbpStringArray;
var
  lvDelimLen, lvCount, lvStart, lvFound: Integer;
begin
  Result := nil;
  if AText = '' then
    Exit;
  lvDelimLen := Length(ADelimiter);
  if lvDelimLen = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := AText;
    Exit;
  end;
  SetLength(Result, 8);
  lvCount := 0;
  lvStart := 1;
  lvFound := PosEx(ADelimiter, AText, 1);
  while lvFound > 0 do
  begin
    if lvCount = Length(Result) then
      SetLength(Result, lvCount * 2);
    Result[lvCount] := Copy(AText, lvStart, lvFound - lvStart);
    Inc(lvCount);
    lvStart := lvFound + lvDelimLen;
    lvFound := PosEx(ADelimiter, AText, lvStart);
  end;
  if lvCount = Length(Result) then
    SetLength(Result, lvCount + 1);
  Result[lvCount] := Copy(AText, lvStart, Length(AText) - lvStart + 1);
  SetLength(Result, lvCount + 1);
end;

function Join(const AValues: array of string; const ASeparator: string): string;
var
  lvTotal, lvSepLen, lvItemLen, i: Integer;
  lvDest: PChar;
begin
  Result := '';
  if Length(AValues) = 0 then
    Exit;
  lvSepLen := Length(ASeparator);
  lvTotal := lvSepLen * (Length(AValues) - 1);
  for i := 0 to High(AValues) do
    Inc(lvTotal, Length(AValues[i]));
  if lvTotal = 0 then
    Exit;
  // exact size known upfront, build with a single allocation
  SetLength(Result, lvTotal);
  lvDest := Pointer(Result);
  for i := 0 to High(AValues) do
  begin
    if (i > 0) and (lvSepLen > 0) then
    begin
      Move(Pointer(ASeparator)^, lvDest^, lvSepLen * SizeOf(Char));
      Inc(lvDest, lvSepLen);
    end;
    lvItemLen := Length(AValues[i]);
    if lvItemLen > 0 then
    begin
      Move(Pointer(AValues[i])^, lvDest^, lvItemLen * SizeOf(Char));
      Inc(lvDest, lvItemLen);
    end;
  end;
end;

function FastStringReplace(const AText, AOldPattern, ANewPattern: string;
  AFlags: TReplaceFlags): string;
var
  lvTextLen, lvOldLen, lvNewLen: Integer;
  lvSearchText, lvSearchPattern: string;
  lvMatches: array of Integer;
  lvMatchCount, lvFound: Integer;
  lvOldChar, lvNewChar: Char;
  lvSource, lvDest: PChar;
  lvStart, lvGap, i: Integer;
begin
  lvTextLen := Length(AText);
  lvOldLen := Length(AOldPattern);
  lvNewLen := Length(ANewPattern);
  if (lvOldLen = 0) or (lvTextLen < lvOldLen) then
  begin
    Result := AText;
    Exit;
  end;
  if rfIgnoreCase in AFlags then
  begin
    // fold once; CharUpperBuff keeps the length, so folded positions map 1:1
    lvSearchText := AnsiUpperCase(AText);
    lvSearchPattern := AnsiUpperCase(AOldPattern);
  end
  else
  begin
    lvSearchText := AText;
    lvSearchPattern := AOldPattern;
  end;
  // single char to single char replace-all: copy once and patch in place
  if (lvOldLen = 1) and (lvNewLen = 1) and (rfReplaceAll in AFlags) then
  begin
    SetString(Result, PChar(AText), lvTextLen);
    lvOldChar := lvSearchPattern[1];
    lvNewChar := ANewPattern[1];
    lvSource := Pointer(lvSearchText);
    lvDest := Pointer(Result);
    for i := 0 to lvTextLen - 1 do
      if lvSource[i] = lvOldChar then
        lvDest[i] := lvNewChar;
    Exit;
  end;
  // collect all match positions first, then build the result in one allocation
  lvMatchCount := 0;
  lvFound := PosEx(lvSearchPattern, lvSearchText, 1);
  while lvFound > 0 do
  begin
    if lvMatchCount = Length(lvMatches) then
    begin
      if lvMatchCount = 0 then
        SetLength(lvMatches, 16)
      else
        SetLength(lvMatches, lvMatchCount * 2);
    end;
    lvMatches[lvMatchCount] := lvFound;
    Inc(lvMatchCount);
    if not (rfReplaceAll in AFlags) then
      Break;
    lvFound := PosEx(lvSearchPattern, lvSearchText, lvFound + lvOldLen);
  end;
  if lvMatchCount = 0 then
  begin
    Result := AText;
    Exit;
  end;
  SetLength(Result, lvTextLen + lvMatchCount * (lvNewLen - lvOldLen));
  lvSource := Pointer(AText);
  lvDest := Pointer(Result);
  lvStart := 1;
  for i := 0 to lvMatchCount - 1 do
  begin
    lvGap := lvMatches[i] - lvStart;
    if lvGap > 0 then
    begin
      Move(lvSource^, lvDest^, lvGap * SizeOf(Char));
      Inc(lvDest, lvGap);
    end;
    Inc(lvSource, lvGap + lvOldLen);
    if lvNewLen > 0 then
    begin
      Move(Pointer(ANewPattern)^, lvDest^, lvNewLen * SizeOf(Char));
      Inc(lvDest, lvNewLen);
    end;
    lvStart := lvMatches[i] + lvOldLen;
  end;
  // tail after the last match
  lvGap := lvTextLen - lvStart + 1;
  if lvGap > 0 then
    Move(lvSource^, lvDest^, lvGap * SizeOf(Char));
end;

function StartsWith(const AText, APrefix: string): Boolean;
var
  lvPrefixLen: Integer;
begin
  lvPrefixLen := Length(APrefix);
  Result := (lvPrefixLen <= Length(AText)) and ((lvPrefixLen = 0) or
    CompareMem(Pointer(AText), Pointer(APrefix), lvPrefixLen * SizeOf(Char)));
end;

function EndsWith(const AText, ASuffix: string): Boolean;
var
  lvSuffixLen, lvTextLen: Integer;
begin
  lvSuffixLen := Length(ASuffix);
  lvTextLen := Length(AText);
  Result := (lvSuffixLen <= lvTextLen) and ((lvSuffixLen = 0) or
    CompareMem(PChar(Pointer(AText)) + lvTextLen - lvSuffixLen,
      Pointer(ASuffix), lvSuffixLen * SizeOf(Char)));
end;

function StartsWithText(const AText, APrefix: string): Boolean;
var
  lvPrefixLen: Integer;
begin
  lvPrefixLen := Length(APrefix);
  if lvPrefixLen = 0 then
    Result := True
  else if lvPrefixLen > Length(AText) then
    Result := False
  else
    Result := CompareString(LOCALE_USER_DEFAULT, NORM_IGNORECASE,
      Pointer(AText), lvPrefixLen, Pointer(APrefix), lvPrefixLen) = CSTR_EQUAL;
end;

function EndsWithText(const AText, ASuffix: string): Boolean;
var
  lvSuffixLen, lvTextLen: Integer;
begin
  lvSuffixLen := Length(ASuffix);
  lvTextLen := Length(AText);
  if lvSuffixLen = 0 then
    Result := True
  else if lvSuffixLen > lvTextLen then
    Result := False
  else
    Result := CompareString(LOCALE_USER_DEFAULT, NORM_IGNORECASE,
      PChar(Pointer(AText)) + lvTextLen - lvSuffixLen, lvSuffixLen,
      Pointer(ASuffix), lvSuffixLen) = CSTR_EQUAL;
end;

end.
