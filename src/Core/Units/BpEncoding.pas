unit BpEncoding;

// Bytes to text through the Windows code page tables, which is all Delphi 7
// has. The interesting one is BpUtf8OrAnsiToWide: strict UTF-8 first, the
// system code page only when the bytes cannot be UTF-8 at all.

interface

// aBytes through aCodePage; an invalid byte becomes U+FFFD rather than failing
function BpDecodeBytes(const aBytes: AnsiString; aCodePage: Cardinal): WideString;

// strict: '' unless every byte of aUtf8 is valid UTF-8
function BpUtf8ToWide(const aUtf8: AnsiString): WideString;

// the code page BpUtf8OrAnsiToWide picks, so a fragment decodes like its stream
function BpUtf8OrAnsiCodePage(const aBytes: AnsiString): Cardinal;

// for a stream of unknown encoding, such as a file body out of git show
function BpUtf8OrAnsiToWide(const aBytes: AnsiString): WideString;

implementation

uses
  Windows;

const
  // MB_ERR_INVALID_CHARS, missing in D2007's Windows.pas
  gcNoBadChars = $00000008;

function DecodeWithFlags(const aBytes: AnsiString; aCodePage: Cardinal;
  aFlags: Cardinal): WideString;
var
  lvLen: Integer;
begin
  Result := '';
  if Length(aBytes) = 0 then
    Exit;
  lvLen := MultiByteToWideChar(aCodePage, aFlags, PAnsiChar(aBytes),
    Length(aBytes), nil, 0);
  if lvLen <= 0 then
    Exit;
  SetLength(Result, lvLen);
  MultiByteToWideChar(aCodePage, aFlags, PAnsiChar(aBytes), Length(aBytes),
    PWideChar(Result), lvLen);
end;

function BpDecodeBytes(const aBytes: AnsiString; aCodePage: Cardinal): WideString;
begin
  Result := DecodeWithFlags(aBytes, aCodePage, 0);
end;

function BpUtf8ToWide(const aUtf8: AnsiString): WideString;
begin
  Result := DecodeWithFlags(aUtf8, CP_UTF8, gcNoBadChars);
end;

function BpUtf8OrAnsiCodePage(const aBytes: AnsiString): Cardinal;
begin
  Result := CP_UTF8;
  if Length(aBytes) = 0 then
    Exit;
  if MultiByteToWideChar(CP_UTF8, gcNoBadChars, PAnsiChar(aBytes),
    Length(aBytes), nil, 0) <= 0 then
    Result := CP_ACP;
end;

function BpUtf8OrAnsiToWide(const aBytes: AnsiString): WideString;
begin
  Result := BpDecodeBytes(aBytes, BpUtf8OrAnsiCodePage(aBytes));
end;

end.
