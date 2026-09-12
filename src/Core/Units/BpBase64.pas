unit BpBase64;

// Base64 encode/decode (RFC 4648), standard and url-safe alphabets. Encoding
// is a single allocation; standard pads with '=', url-safe omits it. Decoding
// accepts either alphabet, tolerates missing padding and skips whitespace
// (so MIME line breaks are fine); any other character raises EbpBase64.
// The AnsiString overloads encode bytes, they do not transcode: for text use
// the Utf8 functions, which encode UTF-8 on every compiler.

interface

uses
  SysUtils, BpCompat;

type
  EbpBase64 = class(Exception);

function Base64Encode(const aData; aSize: Integer): string; overload;
function Base64Encode(const aBytes: TBytes): string; overload;
function Base64Encode(const aText: AnsiString): string; overload;
function Base64UrlEncode(const aData; aSize: Integer): string; overload;
function Base64UrlEncode(const aBytes: TBytes): string; overload;
function Base64UrlEncode(const aText: AnsiString): string; overload;
function Base64Decode(const aBase64: string): TBytes;
function Base64DecodeStr(const aBase64: string): AnsiString;

// text in, UTF-8 bytes on the wire, on every compiler
function Base64EncodeUtf8(const aText: WideString): string;
function Base64UrlEncodeUtf8(const aText: WideString): string;
function Base64DecodeUtf8(const aBase64: string): WideString;

implementation

uses
  Windows;

const
  gcBase64UrlChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  // reverse table markers
  gcInvalid = -1;
  gcWhitespace = -2;
  gcPadding = -3;
  gcNoBadChars = $00000008; // MB_ERR_INVALID_CHARS, missing in D2007's Windows.pas

// bp:mirror base64-encode
// Copied, not shared: tools\CheckMirrors.js fails if the copies stop matching.
const
  gcBase64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

// RFC 4648. aSize past (MaxInt div 4) * 3 wraps the length arithmetic below,
// which each copy guards in its own vocabulary before calling in here.
function Base64EncodeBuffer(aSource: PByte; aSize: Integer;
  const aAlphabet: string; aPadded: Boolean): string;
var
  lvDest: PChar;
  lvB0, lvB1, lvB2: Byte;
  lvFull, lvRest, lvOutLen, i: Integer;
begin
  Result := '';
  if aSize <= 0 then
    Exit;
  lvFull := aSize div 3;
  lvRest := aSize mod 3;
  lvOutLen := lvFull * 4;
  if lvRest > 0 then
  begin
    if aPadded then
      Inc(lvOutLen, 4)
    else
      Inc(lvOutLen, lvRest + 1);
  end;
  SetLength(Result, lvOutLen);
  lvDest := Pointer(Result);
  for i := 1 to lvFull do
  begin
    lvB0 := aSource^; Inc(aSource);
    lvB1 := aSource^; Inc(aSource);
    lvB2 := aSource^; Inc(aSource);
    lvDest[0] := aAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := aAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := aAlphabet[(((lvB1 and $0F) shl 2) or (lvB2 shr 6)) + 1];
    lvDest[3] := aAlphabet[(lvB2 and $3F) + 1];
    Inc(lvDest, 4);
  end;
  if lvRest = 1 then
  begin
    lvB0 := aSource^;
    lvDest[0] := aAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := aAlphabet[((lvB0 and $03) shl 4) + 1];
    if aPadded then
    begin
      lvDest[2] := '=';
      lvDest[3] := '=';
    end;
  end
  else if lvRest = 2 then
  begin
    lvB0 := aSource^; Inc(aSource);
    lvB1 := aSource^;
    lvDest[0] := aAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := aAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := aAlphabet[((lvB1 and $0F) shl 2) + 1];
    if aPadded then
      lvDest[3] := '=';
  end;
end;
// bp:mirror-end

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

function EncodeBuffer(aSource: PByte; aSize: Integer; const aAlphabet: string;
  aPadded: Boolean): string;
begin
  if aSize > (MaxInt div 4) * 3 then
    raise EbpBase64.Create('Input too large to Base64-encode');
  Result := Base64EncodeBuffer(aSource, aSize, aAlphabet, aPadded);
end;

function Base64Encode(const aData; aSize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@aData), aSize, gcBase64Chars, True);
end;

function Base64Encode(const aBytes: TBytes): string;
begin
  if Length(aBytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@aBytes[0], Length(aBytes), gcBase64Chars, True);
end;

function Base64Encode(const aText: AnsiString): string;
begin
  if aText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(aText), Length(aText), gcBase64Chars, True);
end;

function Base64UrlEncode(const aData; aSize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@aData), aSize, gcBase64UrlChars, False);
end;

function Base64UrlEncode(const aBytes: TBytes): string;
begin
  if Length(aBytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@aBytes[0], Length(aBytes), gcBase64UrlChars, False);
end;

function Base64UrlEncode(const aText: AnsiString): string;
begin
  if aText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(aText), Length(aText), gcBase64UrlChars, False);
end;

function Base64Decode(const aBase64: string): TBytes;
var
  lvLen, lvOutPos, lvAccum, lvGroup, i: Integer;
  lvCode: ShortInt;
  lvCh: Char;
  lvSeenPad: Boolean;
begin
  Result := nil;
  lvLen := Length(aBase64);
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
    lvCh := aBase64[i];
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

function Base64DecodeStr(const aBase64: string): AnsiString;
var
  lvBytes: TBytes;
begin
  Result := '';
  lvBytes := Base64Decode(aBase64);
  if Length(lvBytes) = 0 then
    Exit;
  SetLength(Result, Length(lvBytes));
  Move(lvBytes[0], Pointer(Result)^, Length(lvBytes));
end;

// not UTF8Encode: before Delphi 2009 it breaks surrogate pairs
function WideToUtf8(const aText: WideString): AnsiString;
var
  lvLen: Integer;
begin
  Result := '';
  if aText = '' then
    Exit;
  lvLen := WideCharToMultiByte(CP_UTF8, 0, PWideChar(aText), Length(aText),
    nil, 0, nil, nil);
  if lvLen <= 0 then
    raise EbpBase64.Create('Text cannot be encoded as UTF-8');
  SetLength(Result, lvLen);
  WideCharToMultiByte(CP_UTF8, 0, PWideChar(aText), Length(aText),
    PAnsiChar(Result), lvLen, nil, nil);
end;

function Utf8ToWide(const aBytes: TBytes): WideString;
var
  lvLen: Integer;
begin
  Result := '';
  if Length(aBytes) = 0 then
    Exit;
  // BpEncoding decodes the same, inline here so the bundle needs no extra unit
  //   SetString(lvRaw, PAnsiChar(@aBytes[0]), Length(aBytes));
  //   Result := BpUtf8ToWide(lvRaw);
  // gcNoBadChars: bad UTF-8 fails instead of turning into U+FFFD
  lvLen := MultiByteToWideChar(CP_UTF8, gcNoBadChars, PAnsiChar(@aBytes[0]),
    Length(aBytes), nil, 0);
  if lvLen <= 0 then
    raise EbpBase64.Create('Base64 data is not valid UTF-8');
  SetLength(Result, lvLen);
  MultiByteToWideChar(CP_UTF8, gcNoBadChars, PAnsiChar(@aBytes[0]),
    Length(aBytes), PWideChar(Result), lvLen);
end;

function Base64EncodeUtf8(const aText: WideString): string;
begin
  Result := Base64Encode(WideToUtf8(aText));
end;

function Base64UrlEncodeUtf8(const aText: WideString): string;
begin
  Result := Base64UrlEncode(WideToUtf8(aText));
end;

function Base64DecodeUtf8(const aBase64: string): WideString;
begin
  Result := Utf8ToWide(Base64Decode(aBase64));
end;

initialization
  InitDecodeTable;

end.
