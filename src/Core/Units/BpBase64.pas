unit BpBase64;

// Base64 encode/decode per RFC 4648, standard and url-safe alphabets.
// Encoding computes the exact output size and builds the result with a single
// allocation. Standard encode pads with '='; Base64url encode omits padding
// (the common form in tokens, e.g. JWT).
// Decoding uses one shared reverse lookup table that accepts both alphabets,
// tolerates missing padding and skips whitespace (so MIME output with CRLF
// line breaks decodes fine). Any other character raises EbpBase64.

interface

uses
  SysUtils;

type
  EbpBase64 = class(Exception);

function Base64Encode(const AData; ASize: Integer): string; overload;
function Base64Encode(const ABytes: TBytes): string; overload;
function Base64Encode(const AText: AnsiString): string; overload;
function Base64UrlEncode(const AData; ASize: Integer): string; overload;
function Base64UrlEncode(const ABytes: TBytes): string; overload;
function Base64UrlEncode(const AText: AnsiString): string; overload;
function Base64Decode(const ABase64: string): TBytes;
function Base64DecodeStr(const ABase64: string): AnsiString;

implementation

const
  gcBase64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  gcBase64UrlChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  // reverse table markers
  gcInvalid = -1;
  gcWhitespace = -2;
  gcPadding = -3;

var
  gvDecodeTable: array[0..255] of ShortInt;

procedure InitDecodeTable;
var
  i: Integer;
begin
  for i := 0 to 255 do
    gvDecodeTable[i] := gcInvalid;
  for i := 1 to 64 do
    gvDecodeTable[Ord(gcBase64Chars[i])] := i - 1;
  // url-safe alphabet decodes with the same table
  gvDecodeTable[Ord('-')] := 62;
  gvDecodeTable[Ord('_')] := 63;
  gvDecodeTable[9] := gcWhitespace;
  gvDecodeTable[10] := gcWhitespace;
  gvDecodeTable[13] := gcWhitespace;
  gvDecodeTable[32] := gcWhitespace;
  gvDecodeTable[Ord('=')] := gcPadding;
end;

function EncodeBuffer(ASource: PByte; ASize: Integer; const AAlphabet: string;
  APadded: Boolean): string;
var
  lvDest: PChar;
  lvB0, lvB1, lvB2: Byte;
  lvFull, lvRest, lvOutLen, i: Integer;
begin
  Result := '';
  if ASize <= 0 then
    Exit;
  lvFull := ASize div 3;
  lvRest := ASize mod 3;
  lvOutLen := lvFull * 4;
  if lvRest > 0 then
  begin
    if APadded then
      Inc(lvOutLen, 4)
    else
      Inc(lvOutLen, lvRest + 1);
  end;
  SetLength(Result, lvOutLen);
  lvDest := Pointer(Result);
  for i := 1 to lvFull do
  begin
    lvB0 := ASource^; Inc(ASource);
    lvB1 := ASource^; Inc(ASource);
    lvB2 := ASource^; Inc(ASource);
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := AAlphabet[(((lvB1 and $0F) shl 2) or (lvB2 shr 6)) + 1];
    lvDest[3] := AAlphabet[(lvB2 and $3F) + 1];
    Inc(lvDest, 4);
  end;
  if lvRest = 1 then
  begin
    lvB0 := ASource^;
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[((lvB0 and $03) shl 4) + 1];
    if APadded then
    begin
      lvDest[2] := '=';
      lvDest[3] := '=';
    end;
  end
  else if lvRest = 2 then
  begin
    lvB0 := ASource^; Inc(ASource);
    lvB1 := ASource^;
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := AAlphabet[((lvB1 and $0F) shl 2) + 1];
    if APadded then
      lvDest[3] := '=';
  end;
end;

function Base64Encode(const AData; ASize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@AData), ASize, gcBase64Chars, True);
end;

function Base64Encode(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@ABytes[0], Length(ABytes), gcBase64Chars, True);
end;

function Base64Encode(const AText: AnsiString): string;
begin
  if AText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(AText), Length(AText), gcBase64Chars, True);
end;

function Base64UrlEncode(const AData; ASize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@AData), ASize, gcBase64UrlChars, False);
end;

function Base64UrlEncode(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@ABytes[0], Length(ABytes), gcBase64UrlChars, False);
end;

function Base64UrlEncode(const AText: AnsiString): string;
begin
  if AText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(AText), Length(AText), gcBase64UrlChars, False);
end;

function Base64Decode(const ABase64: string): TBytes;
var
  lvLen, lvOutPos, lvAccum, lvGroup, i: Integer;
  lvCode: ShortInt;
  lvCh: Char;
  lvSeenPad: Boolean;
begin
  Result := nil;
  lvLen := Length(ABase64);
  if lvLen = 0 then
    Exit;
  // upper bound, trimmed to the real size at the end
  SetLength(Result, (lvLen div 4) * 3 + 3);
  lvOutPos := 0;
  lvAccum := 0;
  lvGroup := 0;
  lvSeenPad := False;
  for i := 1 to lvLen do
  begin
    lvCh := ABase64[i];
    {$IF SizeOf(Char) > 1}
    if Ord(lvCh) > 255 then
      raise EbpBase64.CreateFmt('Invalid Base64 character at position %d', [i]);
    {$IFEND}
    lvCode := gvDecodeTable[Ord(lvCh)];
    if lvCode = gcWhitespace then
      Continue;
    if lvCode = gcPadding then
    begin
      lvSeenPad := True;
      Continue;
    end;
    if lvCode = gcInvalid then
      raise EbpBase64.CreateFmt('Invalid Base64 character at position %d', [i]);
    if lvSeenPad then
      raise EbpBase64.Create('Base64 data continues after padding');
    lvAccum := (lvAccum shl 6) or lvCode;
    Inc(lvGroup);
    if lvGroup = 4 then
    begin
      Result[lvOutPos] := (lvAccum shr 16) and $FF;
      Result[lvOutPos + 1] := (lvAccum shr 8) and $FF;
      Result[lvOutPos + 2] := lvAccum and $FF;
      Inc(lvOutPos, 3);
      lvAccum := 0;
      lvGroup := 0;
    end;
  end;
  // 2 or 3 leftover chars carry 1 or 2 bytes; a single leftover is impossible
  case lvGroup of
    1: raise EbpBase64.Create('Truncated Base64 data');
    2:
      begin
        Result[lvOutPos] := (lvAccum shr 4) and $FF;
        Inc(lvOutPos);
      end;
    3:
      begin
        Result[lvOutPos] := (lvAccum shr 10) and $FF;
        Result[lvOutPos + 1] := (lvAccum shr 2) and $FF;
        Inc(lvOutPos, 2);
      end;
  end;
  SetLength(Result, lvOutPos);
end;

function Base64DecodeStr(const ABase64: string): AnsiString;
var
  lvBytes: TBytes;
begin
  Result := '';
  lvBytes := Base64Decode(ABase64);
  if Length(lvBytes) = 0 then
    Exit;
  SetLength(Result, Length(lvBytes));
  Move(lvBytes[0], Pointer(Result)^, Length(lvBytes));
end;

initialization
  InitDecodeTable;

end.
