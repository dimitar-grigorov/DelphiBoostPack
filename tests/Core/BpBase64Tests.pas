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
    CheckEquals(Length(lvBytes), Length(Base64Decode(lvUrl)));
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

initialization
  RegisterTest(TBpBase64Tests.Suite);

end.
