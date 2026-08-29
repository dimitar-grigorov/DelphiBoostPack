unit BpKeyFold;

// Case folding for hash keys without the AnsiUpperCase temporary: a table
// built once from the active code page. Byte-at-a-time folding is only valid
// on a single byte code page, so DBCS and Unicode fall back to the RTL.

interface

uses
  Windows, SysUtils;

// True when the table applies: a single byte code page on a pre-Unicode compiler
function BpKeyFoldUsable: Boolean;

// upper cased through the table when that is valid, otherwise unchanged
function BpFoldChar(aCh: Char): Char;

// FNV-1a over the folded key; never returns a negative value
function BpFoldedHash(const aKey: string): Integer;

// case-insensitive equality, equivalent to AnsiSameText
function BpFoldedSame(const aA, aB: string): Boolean;

// folds aKey into aBuf for a caller running its own hash; the folded length,
// or -1 when it will not fit or the table does not apply
function BpFoldInto(const aKey: string; var aBuf; aBufChars: Integer): Integer;

implementation

var
  gvKfUpcase: array[0..255] of Char;
  gvKfUsable: Boolean;
  gvKfReady: Boolean;

procedure KfBuildTable;
var
  i: Integer;
  lvBuf: array[0..255] of Char;
  lvInfo: TCPInfo;
begin
  for i := 0 to 255 do
    lvBuf[i] := Chr(i);
  CharUpperBuff(@lvBuf[0], 256);
  for i := 0 to 255 do
    gvKfUpcase[i] := lvBuf[i];
  {$IFDEF UNICODE}
  gvKfUsable := False;
  {$ELSE}
  gvKfUsable := GetCPInfo(CP_ACP, lvInfo) and (lvInfo.MaxCharSize = 1);
  {$ENDIF}
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
    Result := gvKfUpcase[Ord(aCh) and $FF]
  else
    Result := aCh;
end;

function BpFoldedHash(const aKey: string): Integer;
var
  i: Integer;
  lvH: Cardinal;
  lvFolded: string;
begin
  lvH := 2166136261;
  if BpKeyFoldUsable then
  begin
    for i := 1 to Length(aKey) do
      lvH := (lvH xor Cardinal(Ord(gvKfUpcase[Ord(aKey[i]) and $FF]))) * 16777619;
  end
  else
  begin
    lvFolded := AnsiUpperCase(aKey);
    for i := 1 to Length(lvFolded) do
      lvH := (lvH xor Cardinal(Ord(lvFolded[i]))) * 16777619;
  end;
  Result := Integer(lvH and $7FFFFFFF);
end;

function BpFoldedSame(const aA, aB: string): Boolean;
var
  i: Integer;
begin
  if not BpKeyFoldUsable then
  begin
    Result := AnsiSameText(aA, aB);
    Exit;
  end;
  Result := Length(aA) = Length(aB);
  if not Result then
    Exit;
  for i := 1 to Length(aA) do
    if gvKfUpcase[Ord(aA[i]) and $FF] <> gvKfUpcase[Ord(aB[i]) and $FF] then
    begin
      Result := False;
      Exit;
    end;
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
    lvOut[i - 1] := gvKfUpcase[Ord(aKey[i]) and $FF];
  Result := lvLen;
end;

end.
