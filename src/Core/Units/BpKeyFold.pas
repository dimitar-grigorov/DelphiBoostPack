unit BpKeyFold;

// One ordinal relation for string keys: hash, equality and order read the same
// folded characters, so a hash table and a binary search cannot disagree. The
// fold is upper casing through a table built once, over the active code page on
// Delphi 7 and 2007 and over the BMP on a Unicode compiler. A DBCS code page
// cannot fold a byte at a time and takes the RTL path, which allocates.

interface

uses
  Windows, SysUtils;

// True when the table applies; False only on a DBCS code page before Unicode
function BpKeyFoldUsable: Boolean;

// one character, upper cased through the table, unchanged when it does not apply
function BpFoldChar(aCh: Char): Char;

// 32-bit hash of the key, folded when aFold; equal keys hash equal
function BpKeyHash(const aKey: string; aFold: Boolean): Cardinal;

// the same hash over a character buffer, so a slice needs no Copy
function BpKeyHashBuf(aBuf: PChar; aLen: Integer; aFold: Boolean): Cardinal;

// equality under the relation
function BpKeyEquals(const aA, aB: string; aFold: Boolean): Boolean;

// equality of a key against a character buffer
function BpKeyEqualsBuf(const aKey: string; aBuf: PChar; aLen: Integer; aFold: Boolean): Boolean;

// ordinal order under the relation: negative, zero or positive like CompareStr
function BpKeyCompare(const aA, aB: string; aFold: Boolean): Integer;

// case-insensitive equality, BpKeyEquals(aA, aB, True)
function BpFoldedSame(const aA, aB: string): Boolean;

// folds aKey into aBuf; the folded length, or -1 when it does not apply
function BpFoldInto(const aKey: string; var aBuf; aBufChars: Integer): Integer;

implementation

// the hash wraps by definition
{$Q-}

type
  {$IFDEF UNICODE}
  TKfTable = array[Word] of WideChar;
  {$ELSE}
  TKfTable = array[Byte] of AnsiChar;
  {$ENDIF}
  PKfTable = ^TKfTable;

var
  // a static table, so the unit needs no finalization and can be bundled
  gvKfUpcase: TKfTable;
  gvKfUsable: Boolean;
  gvKfReady: Boolean;

// built aside and published whole, so no thread folds through a half-built table
procedure KfBuildTable;
var
  i: Integer;
  lvNew: PKfTable;
  {$IFNDEF UNICODE}
  lvInfo: TCPInfo;
  {$ENDIF}
begin
  New(lvNew);
  try
    for i := Low(lvNew^) to High(lvNew^) do
      lvNew^[i] := Char(i);
    {$IFDEF UNICODE}
    // simple case mapping is one to one, so a table is exact for the BMP
    CharUpperBuffW(@lvNew^[1], High(lvNew^));
    gvKfUsable := True;
    {$ELSE}
    CharUpperBuffA(@lvNew^[1], High(lvNew^));
    gvKfUsable := GetCPInfo(CP_ACP, lvInfo) and (lvInfo.MaxCharSize = 1);
    {$ENDIF}
    gvKfUpcase := lvNew^;
  finally
    Dispose(lvNew);
  end;
  gvKfReady := True;
end;

function BpKeyFoldUsable: Boolean;
begin
  if not gvKfReady then
    KfBuildTable;
  Result := gvKfUsable;
end;

function BpFoldChar(aCh: Char): Char;
begin
  if BpKeyFoldUsable then
    Result := gvKfUpcase[Ord(aCh)]
  else
    Result := aCh;
end;

// FNV-1a then the murmur3 finaliser, so a bucket index depends on every character
function KfHash(aBuf: PChar; aLen: Integer; aFold: Boolean): Cardinal;
var
  i: Integer;
begin
  Result := 2166136261;
  if aFold then
    for i := 0 to aLen - 1 do
      Result := (Result xor Cardinal(Ord(gvKfUpcase[Ord(aBuf[i])]))) * 16777619
  else
    for i := 0 to aLen - 1 do
      Result := (Result xor Cardinal(Ord(aBuf[i]))) * 16777619;
  Result := Result xor (Result shr 16);
  Result := Result * $85EBCA6B;
  Result := Result xor (Result shr 13);
  Result := Result * $C2B2AE35;
  Result := Result xor (Result shr 16);
end;

function BpKeyHashBuf(aBuf: PChar; aLen: Integer; aFold: Boolean): Cardinal;
var
  lvUpper: string;
begin
  if aFold and not BpKeyFoldUsable then
  begin
    // DBCS: the RTL knows the lead bytes, the table does not
    SetString(lvUpper, aBuf, aLen);
    lvUpper := AnsiUpperCase(lvUpper);
    Result := KfHash(PChar(lvUpper), Length(lvUpper), False);
    Exit;
  end;
  if aFold and not gvKfReady then
    KfBuildTable;
  Result := KfHash(aBuf, aLen, aFold);
end;

function BpKeyHash(const aKey: string; aFold: Boolean): Cardinal;
begin
  Result := BpKeyHashBuf(PChar(aKey), Length(aKey), aFold);
end;

function BpKeyEqualsBuf(const aKey: string; aBuf: PChar; aLen: Integer; aFold: Boolean): Boolean;
var
  i: Integer;
  lvKey: PChar;
  lvOther: string;
begin
  if aFold and not BpKeyFoldUsable then
  begin
    // the same relation the DBCS hash and compare take: upper case, then ordinal
    SetString(lvOther, aBuf, aLen);
    Result := CompareStr(AnsiUpperCase(aKey), AnsiUpperCase(lvOther)) = 0;
    Exit;
  end;
  Result := Length(aKey) = aLen;
  if not Result then
    Exit;
  lvKey := PChar(aKey);
  if aFold then
  begin
    for i := 0 to aLen - 1 do
      if gvKfUpcase[Ord(lvKey[i])] <> gvKfUpcase[Ord(aBuf[i])] then
      begin
        Result := False;
        Exit;
      end;
  end
  else
    Result := CompareMem(lvKey, aBuf, aLen * SizeOf(Char));
end;

function BpKeyEquals(const aA, aB: string; aFold: Boolean): Boolean;
begin
  // unfolded is plain ordinal equality, and the RTL compares a word at a time
  if aFold then
    Result := BpKeyEqualsBuf(aA, PChar(aB), Length(aB), True)
  else
    Result := aA = aB;
end;

function BpKeyCompare(const aA, aB: string; aFold: Boolean): Integer;
var
  i, lvLen: Integer;
  lvA, lvB: PChar;
  lvChA, lvChB: Char;
begin
  if not aFold then
  begin
    Result := CompareStr(aA, aB);
    Exit;
  end;
  if not BpKeyFoldUsable then
  begin
    Result := CompareStr(AnsiUpperCase(aA), AnsiUpperCase(aB));
    Exit;
  end;
  lvLen := Length(aA);
  if Length(aB) < lvLen then
    lvLen := Length(aB);
  lvA := PChar(aA);
  lvB := PChar(aB);
  for i := 0 to lvLen - 1 do
  begin
    lvChA := gvKfUpcase[Ord(lvA[i])];
    lvChB := gvKfUpcase[Ord(lvB[i])];
    if lvChA <> lvChB then
    begin
      Result := Ord(lvChA) - Ord(lvChB);
      Exit;
    end;
  end;
  Result := Length(aA) - Length(aB);
end;

function BpFoldedSame(const aA, aB: string): Boolean;
begin
  Result := BpKeyEquals(aA, aB, True);
end;

function BpFoldInto(const aKey: string; var aBuf; aBufChars: Integer): Integer;
var
  i, lvLen: Integer;
  lvOut: PChar;
begin
  lvLen := Length(aKey);
  if (not BpKeyFoldUsable) or (lvLen > aBufChars) then
  begin
    Result := -1;
    Exit;
  end;
  lvOut := PChar(@aBuf);
  for i := 1 to lvLen do
    lvOut[i - 1] := gvKfUpcase[Ord(aKey[i])];
  Result := lvLen;
end;

end.
