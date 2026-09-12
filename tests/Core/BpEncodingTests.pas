unit BpEncodingTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, Windows, SysUtils, BpEncoding;

type
  TBpEncodingTests = class(TTestCase)
  private
    function Utf8Cyrillic: AnsiString;
  published
    procedure TestUtf8ToWideDecodesMultiByte;
    procedure TestUtf8ToWideRefusesALoneContinuationByte;
    procedure TestUtf8ToWideRefusesAnOverlongEncoding;
    procedure TestUtf8ToWideRefusesATruncatedSequence;
    procedure TestUtf8ToWideKeepsAByteOrderMark;
    procedure TestUtf8ToWideOnEmptyAndAscii;
    procedure TestDecodeBytesReplacesRatherThanFailing;
    procedure TestUtf8OrAnsiCodePagePicksUtf8ForValidBytes;
    procedure TestUtf8OrAnsiCodePageFallsBackForInvalidBytes;
    procedure TestUtf8OrAnsiToWideTakesTheFallbackWhole;
  end;

implementation

// U+0411 U+044A, two characters that need two bytes each
function TBpEncodingTests.Utf8Cyrillic: AnsiString;
begin
  Result := #$D0#$91#$D1#$8A;
end;

procedure TBpEncodingTests.TestUtf8ToWideDecodesMultiByte;
var
  lvText: WideString;
begin
  lvText := BpUtf8ToWide(Utf8Cyrillic);
  CheckEquals(2, Length(lvText), 'four bytes are two characters');
  CheckEquals(Integer($0411), Ord(lvText[1]), 'the first code point');
  CheckEquals(Integer($044A), Ord(lvText[2]), 'the second code point');
end;

procedure TBpEncodingTests.TestUtf8ToWideRefusesALoneContinuationByte;
begin
  CheckEquals('', BpUtf8ToWide(#$80), 'a continuation byte with nothing to continue');
  CheckEquals('', BpUtf8ToWide('ok' + #$80), 'and one after valid text');
end;

procedure TBpEncodingTests.TestUtf8ToWideRefusesAnOverlongEncoding;
begin
  // C0 AF is '/' written in two bytes, the classic path-traversal smuggle
  CheckEquals('', BpUtf8ToWide(#$C0#$AF), 'an overlong slash');
  CheckEquals('', BpUtf8ToWide(#$E0#$80#$AF), 'and its three-byte form');
end;

procedure TBpEncodingTests.TestUtf8ToWideRefusesATruncatedSequence;
begin
  // E2 82 AC is the euro sign; the buffer ends one byte early
  CheckEquals('', BpUtf8ToWide(#$E2#$82), 'a sequence cut off at the end');
  CheckEquals('', BpUtf8ToWide(Copy(Utf8Cyrillic, 1, 3)), 'and a cut-off pair');
end;

procedure TBpEncodingTests.TestUtf8ToWideKeepsAByteOrderMark;
var
  lvText: WideString;
begin
  lvText := BpUtf8ToWide(#$EF#$BB#$BF'ab');
  CheckEquals(3, Length(lvText), 'a BOM is a character here, not a marker');
  CheckEquals(Integer($FEFF), Ord(lvText[1]), 'and the caller has to strip it');
end;

procedure TBpEncodingTests.TestUtf8ToWideOnEmptyAndAscii;
begin
  CheckEquals('', BpUtf8ToWide(''), 'no bytes');
  CheckEquals('plain', BpUtf8ToWide('plain'), 'ASCII is UTF-8');
end;

procedure TBpEncodingTests.TestDecodeBytesReplacesRatherThanFailing;
var
  lvText: WideString;
begin
  lvText := BpDecodeBytes('ok' + #$80, CP_UTF8);
  CheckEquals(3, Length(lvText), 'the bad byte becomes a character instead of failing');
  CheckEquals(Integer($FFFD), Ord(lvText[3]), 'the replacement character');
  CheckEquals('', BpDecodeBytes('', CP_UTF8), 'no bytes');
end;

procedure TBpEncodingTests.TestUtf8OrAnsiCodePagePicksUtf8ForValidBytes;
begin
  CheckEquals(Integer(CP_UTF8), Integer(BpUtf8OrAnsiCodePage(Utf8Cyrillic)), 'valid UTF-8');
  CheckEquals(Integer(CP_UTF8), Integer(BpUtf8OrAnsiCodePage('plain')), 'ASCII');
  CheckEquals(Integer(CP_UTF8), Integer(BpUtf8OrAnsiCodePage('')), 'no bytes at all');
end;

procedure TBpEncodingTests.TestUtf8OrAnsiCodePageFallsBackForInvalidBytes;
begin
  CheckEquals(Integer(CP_ACP), Integer(BpUtf8OrAnsiCodePage(#$80)), 'a lone continuation byte');
  CheckEquals(Integer(CP_ACP), Integer(BpUtf8OrAnsiCodePage(#$C0#$AF)), 'an overlong encoding');
  CheckEquals(Integer(CP_ACP), Integer(BpUtf8OrAnsiCodePage(#$E2#$82)), 'a truncated sequence');
end;

procedure TBpEncodingTests.TestUtf8OrAnsiToWideTakesTheFallbackWhole;
var
  lvBytes: AnsiString;
begin
  CheckEquals(BpUtf8ToWide(Utf8Cyrillic), BpUtf8OrAnsiToWide(Utf8Cyrillic),
    'valid UTF-8 decodes as UTF-8');
  // bytes that cannot be UTF-8 go through the system code page, whichever it is
  lvBytes := #$C0#$AF#$80;
  CheckEquals(BpDecodeBytes(lvBytes, CP_ACP), BpUtf8OrAnsiToWide(lvBytes),
    'invalid UTF-8 decodes through the system code page');
  CheckEquals('', BpUtf8OrAnsiToWide(''), 'no bytes');
end;

initialization
  RegisterTest(TBpEncodingTests.Suite);

end.
