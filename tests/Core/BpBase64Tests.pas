unit BpBase64Tests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpBase64;

type
  TBpBase64Tests = class(TTestCase)
  private
    procedure CallDecodeInvalidChar;
    procedure CallDecodeDataAfterPadding;
    procedure CallDecodeTruncated;
    procedure CheckDecodes(const aInput: string; const aExpected: AnsiString;
      const aWhat: string);
    procedure CheckDecodeRaises(const aInput, aWhat: string);
    procedure CheckBytesEqual(const aExpected, aActual: TBytes;
      const aWhat: string);
  published
    procedure TestEncodeRfcVectors;
    procedure TestDecodeRfcVectors;
    procedure TestDecodeUnpadded;
    procedure TestDecodeWhitespaceTolerant;
    procedure TestDecodeInvalidCharRaises;
    procedure TestDecodeDataAfterPaddingRaises;
    procedure TestDecodeTruncatedRaises;
    procedure TestUrlAlphabetAndNoPadding;
    procedure TestUrlMatchesTranslatedStandard;
    procedure TestEncodeBytesOverload;
    procedure TestEncodeUntypedOverload;
    procedure TestDecodeToBytes;
    procedure TestRandomRoundTrip;
    procedure TestRtlParity;
    procedure TestPaddingPolicy;
    procedure TestRejectedCharacters;
    procedure TestUrlAlphabetDecodesToTheRightBytes;
    procedure TestUrlEncodeUntypedOverload;
{$IF SizeOf(Char) > 1}
    procedure TestDecodeRejectsWideCharacter;
{$IFEND}
    procedure TestEncodeRejectsOversizedInput;
    procedure TestUtf8RoundTrip;
    procedure TestDecodeUtf8RejectsBadBytes;
  end;

implementation

uses
  EncdDecd;

procedure TBpBase64Tests.TestEncodeRfcVectors;
begin
  // RFC 4648 section 10 test vectors
  CheckEquals('', Base64Encode(''));
  CheckEquals('Zg==', Base64Encode('f'));
  CheckEquals('Zm8=', Base64Encode('fo'));
  CheckEquals('Zm9v', Base64Encode('foo'));
  CheckEquals('Zm9vYg==', Base64Encode('foob'));
  CheckEquals('Zm9vYmE=', Base64Encode('fooba'));
  CheckEquals('Zm9vYmFy', Base64Encode('foobar'));
end;

procedure TBpBase64Tests.TestDecodeRfcVectors;
begin
  CheckEquals('', Base64DecodeStr(''));
  CheckEquals('f', Base64DecodeStr('Zg=='));
  CheckEquals('fo', Base64DecodeStr('Zm8='));
  CheckEquals('foo', Base64DecodeStr('Zm9v'));
  CheckEquals('foob', Base64DecodeStr('Zm9vYg=='));
  CheckEquals('fooba', Base64DecodeStr('Zm9vYmE='));
  CheckEquals('foobar', Base64DecodeStr('Zm9vYmFy'));
end;

procedure TBpBase64Tests.TestDecodeUnpadded;
begin
  CheckEquals('f', Base64DecodeStr('Zg'));
  CheckEquals('fo', Base64DecodeStr('Zm8'));
  CheckEquals('foob', Base64DecodeStr('Zm9vYg'));
end;

procedure TBpBase64Tests.TestDecodeWhitespaceTolerant;
begin
  CheckEquals('foobar', Base64DecodeStr('Zm9v' + #13#10 + 'YmFy'));
  CheckEquals('foobar', Base64DecodeStr(' Zm9v Ym Fy '#9));
end;

procedure TBpBase64Tests.CallDecodeInvalidChar;
begin
  Base64Decode('Zm9v*mFy');
end;

procedure TBpBase64Tests.CallDecodeDataAfterPadding;
begin
  Base64Decode('Zg==Zg');
end;

procedure TBpBase64Tests.CallDecodeTruncated;
begin
  Base64Decode('Zm9vY');
end;

procedure TBpBase64Tests.TestDecodeInvalidCharRaises;
begin
  CheckException(CallDecodeInvalidChar, EbpBase64);
end;

procedure TBpBase64Tests.TestDecodeDataAfterPaddingRaises;
begin
  CheckException(CallDecodeDataAfterPadding, EbpBase64);
end;

procedure TBpBase64Tests.TestDecodeTruncatedRaises;
begin
  CheckException(CallDecodeTruncated, EbpBase64);
end;

procedure TBpBase64Tests.TestUrlAlphabetAndNoPadding;
var
  lvBytes: TBytes;
  lvStd, lvUrl: string;
begin
  // bytes chosen to produce '+' and '/' in the standard alphabet
  SetLength(lvBytes, 3);
  lvBytes[0] := $FB;
  lvBytes[1] := $EF;
  lvBytes[2] := $BE;
  lvStd := Base64Encode(lvBytes);
  lvUrl := Base64UrlEncode(lvBytes);
  CheckEquals('++++', lvStd);
  CheckEquals('----', lvUrl);
  // padding omitted in the url form
  CheckEquals('Zg==', Base64Encode('f'));
  CheckEquals('Zg', Base64UrlEncode('f'));
end;

procedure TBpBase64Tests.TestUrlMatchesTranslatedStandard;
var
  lvBytes: TBytes;
  lvStd, lvUrl: string;
  i, lvCase: Integer;
begin
  RandSeed := 20260707;
  for lvCase := 1 to 50 do
  begin
    SetLength(lvBytes, Random(40));
    for i := 0 to High(lvBytes) do
      lvBytes[i] := Random(256);
    lvStd := Base64Encode(lvBytes);
    // translate the standard form: swap alphabet, drop padding
    lvStd := StringReplace(lvStd, '+', '-', [rfReplaceAll]);
    lvStd := StringReplace(lvStd, '/', '_', [rfReplaceAll]);
    lvStd := StringReplace(lvStd, '=', '', [rfReplaceAll]);
    lvUrl := Base64UrlEncode(lvBytes);
    CheckEquals(lvStd, lvUrl);
    // both decode back to the same bytes through the shared table
    CheckBytesEqual(lvBytes, Base64Decode(lvUrl), 'url decode');
    CheckBytesEqual(lvBytes, Base64Decode(Base64Encode(lvBytes)), 'standard decode');
  end;
end;

procedure TBpBase64Tests.TestEncodeBytesOverload;
var
  lvBytes: TBytes;
begin
  lvBytes := nil;
  CheckEquals('', Base64Encode(lvBytes));
  SetLength(lvBytes, 3);
  lvBytes[0] := Ord('f');
  lvBytes[1] := Ord('o');
  lvBytes[2] := Ord('o');
  CheckEquals('Zm9v', Base64Encode(lvBytes));
end;

procedure TBpBase64Tests.TestEncodeUntypedOverload;
var
  lvBuf: array[0..2] of AnsiChar;
begin
  lvBuf[0] := 'f';
  lvBuf[1] := 'o';
  lvBuf[2] := 'o';
  CheckEquals('Zm9v', Base64Encode(lvBuf, 3));
  CheckEquals('', Base64Encode(lvBuf, 0));
end;

procedure TBpBase64Tests.TestDecodeToBytes;
var
  lvBytes: TBytes;
begin
  lvBytes := Base64Decode('Zm9v');
  CheckEquals(3, Length(lvBytes));
  CheckEquals(Ord('f'), lvBytes[0]);
  CheckEquals(Ord('o'), lvBytes[1]);
  CheckEquals(Ord('o'), lvBytes[2]);
  CheckEquals(0, Length(Base64Decode('')));
end;

procedure TBpBase64Tests.TestRandomRoundTrip;
var
  lvData: AnsiString;
  lvCase, i: Integer;
begin
  RandSeed := 20260707;
  for lvCase := 1 to 200 do
  begin
    SetLength(lvData, Random(120));
    for i := 1 to Length(lvData) do
      lvData[i] := AnsiChar(Random(256));
    CheckEquals(lvData, Base64DecodeStr(Base64Encode(lvData)), 'standard roundtrip');
    CheckEquals(lvData, Base64DecodeStr(Base64UrlEncode(lvData)), 'url roundtrip');
  end;
end;

procedure TBpBase64Tests.TestRtlParity;
var
  lvData: AnsiString;
  lvCase, i: Integer;
begin
  RandSeed := 20260708;
  for lvCase := 1 to 50 do
  begin
    SetLength(lvData, Random(200));
    for i := 1 to Length(lvData) do
      lvData[i] := AnsiChar(Random(256));
    // our decoder reads RTL output (it wraps lines), RTL reads our output
    CheckEquals(lvData, Base64DecodeStr(EncodeString(lvData)), 'decode RTL encode');
    CheckEquals(lvData, DecodeString(Base64Encode(lvData)), 'RTL decode our encode');
  end;
end;

procedure TBpBase64Tests.CheckBytesEqual(const aExpected, aActual: TBytes;
  const aWhat: string);
var
  i: Integer;
begin
  CheckEquals(Length(aExpected), Length(aActual), aWhat + ': length');
  for i := 0 to High(aExpected) do
    CheckEquals(aExpected[i], aActual[i], aWhat + ': byte ' + IntToStr(i));
end;

// one place for the two things every padding case asserts
procedure TBpBase64Tests.CheckDecodes(const aInput: string;
  const aExpected: AnsiString; const aWhat: string);
begin
  CheckEquals(aExpected, Base64DecodeStr(aInput), aWhat + ' (' + aInput + ')');
end;

procedure TBpBase64Tests.CheckDecodeRaises(const aInput, aWhat: string);
begin
  try
    Base64Decode(aInput);
    Fail(aWhat + ' must raise EbpBase64 (' + aInput + ')');
  except
    // narrow, or Fail lands in this handler
    on E: EbpBase64 do
      ; // expected
  end;
end;

procedure TBpBase64Tests.TestPaddingPolicy;
begin
  // padding is tolerated wherever it cannot be mistaken for data
  CheckDecodes('Zm9v=', 'foo', 'a stray pad after a full group');
  CheckDecodes('Zg=', 'f', 'short padding');
  CheckDecodes('Zg===', 'f', 'excess padding');
  CheckDecodes('Zg = =', 'f', 'whitespace between the pads');
  CheckDecodes('Zm9v'#13#10'=', 'foo', 'padding on its own line');
  CheckDecodes('=', '', 'pad only');
  CheckDecodes('==', '', 'pads only');
  CheckDecodes('   ', '', 'whitespace only');

  // but data after a pad is a corrupt stream, not a concatenation
  CheckDecodeRaises('=Zg', 'a pad before the data');
  CheckDecodeRaises('Zg==Zg', 'two padded streams joined');
  CheckDecodeRaises('Z=g', 'a pad inside a group');
end;

procedure TBpBase64Tests.TestRejectedCharacters;
begin
  // the whitespace set is exactly tab, LF, CR and space; nothing else passes
  CheckDecodeRaises('Zm'#0'9v', 'a nul byte');
  CheckDecodeRaises('Zm'#11'9v', 'a vertical tab');
  CheckDecodeRaises('Zm'#12'9v', 'a form feed');
  CheckDecodeRaises('Zm'#160'9v', 'a non-breaking space');
  CheckDecodeRaises('Zm.9v', 'a full stop');
end;

procedure TBpBase64Tests.TestUrlAlphabetDecodesToTheRightBytes;
var
  lvBytes: TBytes;
  i, lvCase: Integer;
  lvUrl: string;
begin
  // '-' and '_' must map to 62 and 63, and the two alphabets may be mixed
  lvBytes := Base64Decode('+_/-');
  CheckEquals(3, Length(lvBytes), 'four sextets are three bytes');
  CheckEquals($FB, lvBytes[0]);
  CheckEquals($FF, lvBytes[1]);
  CheckEquals($FE, lvBytes[2]);
  CheckEquals('foobar', Base64DecodeStr('Zm9v' + 'YmFy'), 'plain');

  // the url form of random data decodes to the bytes it came from
  RandSeed := 20260830;
  for lvCase := 1 to 50 do
  begin
    SetLength(lvBytes, Random(40));
    for i := 0 to High(lvBytes) do
      lvBytes[i] := Random(256);
    lvUrl := Base64UrlEncode(lvBytes);
    CheckBytesEqual(lvBytes, Base64Decode(lvUrl), 'url round trip case ' +
      IntToStr(lvCase));
  end;
end;

procedure TBpBase64Tests.TestUrlEncodeUntypedOverload;
var
  lvBuf: array[0..2] of AnsiChar;
begin
  lvBuf[0] := 'f';
  lvBuf[1] := 'o';
  lvBuf[2] := 'o';
  CheckEquals('Zm9v', Base64UrlEncode(lvBuf, 3));
  CheckEquals('', Base64UrlEncode(lvBuf, 0));
  // one byte, so the url form drops the padding the standard one would add
  CheckEquals('Zg', Base64UrlEncode(lvBuf, 1));
end;

{$IF SizeOf(Char) > 1}
procedure TBpBase64Tests.TestDecodeRejectsWideCharacter;
begin
  // above U+00FF there is no table entry to look up, so it must not index it
  CheckDecodeRaises('Zm9v' + WideChar($0410), 'a Cyrillic character');
end;
{$IFEND}

procedure TBpBase64Tests.TestEncodeRejectsOversizedInput;
var
  lvBuf: array[0..2] of AnsiChar;
begin
  // the guard reads the size only, so the tiny buffer is never touched
  try
    Base64Encode(lvBuf, MaxInt);
    Fail('an oversized input must raise instead of wrapping the length');
  except
    on E: EbpBase64 do
      ; // expected
  end;
end;

procedure TBpBase64Tests.TestUtf8RoundTrip;
var
  lvText: WideString;
begin
  CheckEquals('', Base64EncodeUtf8(''));
  CheckEquals('Zm9v', Base64EncodeUtf8('foo'), 'ascii is unchanged');
  // U+00E9 is C3 A9 in UTF-8, whatever the machine code page says
  lvText := WideChar($00E9);
  CheckEquals('w6k=', Base64EncodeUtf8(lvText));
  CheckEquals('w6k', Base64UrlEncodeUtf8(lvText), 'url form, no padding');

  // an accent, a euro sign and a surrogate pair, compared as WideString
  lvText := 'caf' + WideChar($00E9) + WideChar($20AC) +
    WideChar($D83D) + WideChar($DE00);
  CheckTrue(Base64DecodeUtf8(Base64EncodeUtf8(lvText)) = lvText, 'standard');
  CheckTrue(Base64DecodeUtf8(Base64UrlEncodeUtf8(lvText)) = lvText, 'url');
  CheckTrue(Base64DecodeUtf8('') = '', 'empty');
end;

procedure TBpBase64Tests.TestDecodeUtf8RejectsBadBytes;
begin
  // $FF starts no UTF-8 sequence; better a raise than a U+FFFD nobody notices
  try
    Base64DecodeUtf8(Base64Encode(AnsiString(#$FF#$FE)));
    Fail('invalid UTF-8 must raise EbpBase64');
  except
    on E: EbpBase64 do
      ; // expected
  end;
end;

initialization
  RegisterTest(TBpBase64Tests.Suite);

end.
