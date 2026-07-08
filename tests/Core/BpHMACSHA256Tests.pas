unit BpHMACSHA256Tests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpSHA256, BpHMACSHA256;

type
  TBpHMACSHA256Tests = class(TTestCase)
  private
    // independent by-definition HMAC built from string concatenation over TbpSHA256
    function ManualHmacHex(const AKey, AMsg: AnsiString): string;
    procedure CheckHmac(const AExpectedHex: string; const AKey, AMsg: AnsiString;
      const ACase: string);
  published
    procedure TestRfc4231Vectors;
    procedure TestByDefinitionRandom;
    procedure TestStreamingMatchesOneShot;
    procedure TestReuseAfterFinal;
    procedure TestComputeBase64;
  end;

implementation

uses
  BpBase64;

function TBpHMACSHA256Tests.ManualHmacHex(const AKey, AMsg: AnsiString): string;
var
  lvKey, lvIpad, lvOpad, lvInnerStr: AnsiString;
  lvDigest: TbpSHA256Digest;
  i, lvByte: Integer;
begin
  lvKey := AKey;
  if Length(lvKey) > 64 then
  begin
    lvDigest := TbpSHA256.HashStr(lvKey);
    SetString(lvKey, PAnsiChar(@lvDigest), SizeOf(lvDigest));
  end;
  SetLength(lvIpad, 64);
  SetLength(lvOpad, 64);
  for i := 1 to 64 do
  begin
    if i <= Length(lvKey) then
      lvByte := Ord(lvKey[i])
    else
      lvByte := 0;
    lvIpad[i] := AnsiChar(lvByte xor $36);
    lvOpad[i] := AnsiChar(lvByte xor $5C);
  end;
  lvDigest := TbpSHA256.HashStr(lvIpad + AMsg);
  SetString(lvInnerStr, PAnsiChar(@lvDigest), SizeOf(lvDigest));
  Result := TbpSHA256.DigestToHex(TbpSHA256.HashStr(lvOpad + lvInnerStr));
end;

procedure TBpHMACSHA256Tests.CheckHmac(const AExpectedHex: string;
  const AKey, AMsg: AnsiString; const ACase: string);
begin
  CheckEquals(AExpectedHex, TbpHMACSHA256.ComputeHex(AKey, AMsg), ACase);
end;

procedure TBpHMACSHA256Tests.TestRfc4231Vectors;
var
  lvKey: AnsiString;
  lvDigest: TbpSHA256Digest;
  lvTruncatedHex: string;
  i: Integer;
begin
  // test case 1
  CheckHmac('b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
    StringOfChar(AnsiChar(#$0B), 20), 'Hi There', 'case 1');
  // test case 2
  CheckHmac('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    'Jefe', 'what do ya want for nothing?', 'case 2');
  // test case 3
  CheckHmac('773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe',
    StringOfChar(AnsiChar(#$AA), 20), StringOfChar(AnsiChar(#$DD), 50), 'case 3');
  // test case 4: key bytes 01..19
  SetLength(lvKey, 25);
  for i := 1 to 25 do
    lvKey[i] := AnsiChar(i);
  CheckHmac('82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b',
    lvKey, StringOfChar(AnsiChar(#$CD), 50), 'case 4');
  // test case 5: output truncated to the first 128 bits
  lvDigest := TbpHMACSHA256.Compute(StringOfChar(AnsiChar(#$0C), 20),
    AnsiString('Test With Truncation'));
  lvTruncatedHex := '';
  for i := 0 to 15 do
    lvTruncatedHex := lvTruncatedHex + LowerCase(IntToHex(lvDigest[i], 2));
  CheckEquals('a3b6167473100ee06e0c796c2955552b', lvTruncatedHex, 'case 5');
  // test case 6: key larger than the block gets hashed first
  CheckHmac('60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
    StringOfChar(AnsiChar(#$AA), 131),
    'Test Using Larger Than Block-Size Key - Hash Key First', 'case 6');
  // test case 7: large key and large data
  CheckHmac('9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2',
    StringOfChar(AnsiChar(#$AA), 131),
    'This is a test using a larger than block-size key and a larger t' +
    'han block-size data. The key needs to be hashed before being use' +
    'd by the HMAC algorithm.', 'case 7');
end;

procedure TBpHMACSHA256Tests.TestByDefinitionRandom;
var
  lvKey, lvMsg: AnsiString;
  lvCase, i: Integer;
begin
  // random key lengths cover empty, short, block-size and hashed-down keys
  RandSeed := 20260708;
  for lvCase := 1 to 50 do
  begin
    SetLength(lvKey, Random(150));
    for i := 1 to Length(lvKey) do
      lvKey[i] := AnsiChar(Random(256));
    SetLength(lvMsg, Random(300));
    for i := 1 to Length(lvMsg) do
      lvMsg[i] := AnsiChar(Random(256));
    CheckEquals(ManualHmacHex(lvKey, lvMsg), TbpHMACSHA256.ComputeHex(lvKey, lvMsg),
      Format('case %d keylen %d msglen %d', [lvCase, Length(lvKey), Length(lvMsg)]));
  end;
end;

procedure TBpHMACSHA256Tests.TestStreamingMatchesOneShot;
var
  lvHmac: TbpHMACSHA256;
  lvDigest: TbpSHA256Digest;
  lvMsg: AnsiString;
  i: Integer;
begin
  RandSeed := 20260709;
  SetLength(lvMsg, 200);
  for i := 1 to Length(lvMsg) do
    lvMsg[i] := AnsiChar(Random(256));
  lvHmac := TbpHMACSHA256.Create(AnsiString('secret key'));
  try
    // byte-at-a-time streaming
    for i := 1 to Length(lvMsg) do
      lvHmac.Update(lvMsg[i], 1);
    lvHmac.Final(lvDigest);
  finally
    lvHmac.Free;
  end;
  CheckEquals(TbpHMACSHA256.ComputeHex('secret key', lvMsg),
    TbpSHA256.DigestToHex(lvDigest));
end;

procedure TBpHMACSHA256Tests.TestReuseAfterFinal;
var
  lvHmac: TbpHMACSHA256;
  lvFirst, lvSecond: TbpSHA256Digest;
begin
  lvHmac := TbpHMACSHA256.Create(AnsiString('Jefe'));
  try
    lvHmac.Update(AnsiString('what do ya want for nothing?'));
    lvHmac.Final(lvFirst);
    // Final re-arms the instance for the next message with the same key
    lvHmac.Update(AnsiString('what do ya want for nothing?'));
    lvHmac.Final(lvSecond);
  finally
    lvHmac.Free;
  end;
  CheckEquals(TbpSHA256.DigestToHex(lvFirst), TbpSHA256.DigestToHex(lvSecond));
  CheckEquals('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    TbpSHA256.DigestToHex(lvFirst));
end;

procedure TBpHMACSHA256Tests.TestComputeBase64;
var
  lvBase64: string;
  lvBytes: TBytes;
  lvDigest: TbpSHA256Digest;
  i: Integer;
begin
  lvDigest := TbpHMACSHA256.Compute(AnsiString('key'), AnsiString('message'));
  lvBase64 := TbpHMACSHA256.ComputeBase64('key', 'message');
  CheckEquals(44, Length(lvBase64));
  lvBytes := Base64Decode(lvBase64);
  CheckEquals(32, Length(lvBytes));
  for i := 0 to 31 do
    CheckEquals(lvDigest[i], lvBytes[i], Format('byte %d', [i]));
end;

initialization
  RegisterTest(TBpHMACSHA256Tests.Suite);

end.
