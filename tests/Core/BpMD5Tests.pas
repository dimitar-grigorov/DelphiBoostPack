unit BpMD5Tests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, BpMD5;

type
  TBpMD5Tests = class(TTestCase)
  private
    procedure CheckHashStr(const AExpectedHex: string; const AText: AnsiString);
  published
    procedure TestRfcVectors;
    procedure TestStreamingMatchesOneShot;
    procedure TestBlockBoundaries;
    procedure TestInstanceReuseAfterFinal;
    procedure TestHashFile;
    procedure TestDigestToBase64;
    procedure TestCryptoApiCrossCheck;
  end;

implementation

uses
  BpBase64, BpCryptoApiHash;

procedure TBpMD5Tests.CheckHashStr(const AExpectedHex: string; const AText: AnsiString);
begin
  CheckEquals(AExpectedHex, TbpMD5.HashStrHex(AText), string(AText));
end;

procedure TBpMD5Tests.TestRfcVectors;
begin
  // RFC 1321 appendix A.5 test suite
  CheckHashStr('d41d8cd98f00b204e9800998ecf8427e', '');
  CheckHashStr('0cc175b9c0f1b6a831c399e269772661', 'a');
  CheckHashStr('900150983cd24fb0d6963f7d28e17f72', 'abc');
  CheckHashStr('f96b697d7cb7938d525a2f31aaf161d0', 'message digest');
  CheckHashStr('c3fcd3d76192e4007dfb496cca67e13b', 'abcdefghijklmnopqrstuvwxyz');
  CheckHashStr('d174ab98d277d9f5a5611c2c9f419d9f',
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789');
  CheckHashStr('57edf4a22be3c955ac49da2e2107b67a',
    '12345678901234567890123456789012345678901234567890123456789012345678901234567890');
end;

procedure TBpMD5Tests.TestStreamingMatchesOneShot;
var
  lvData: AnsiString;
  lvHasher: TbpMD5;
  lvDigest: TbpMD5Digest;
  lvExpected: string;
  i, lvPos, lvChunk: Integer;
begin
  RandSeed := 20260707;
  SetLength(lvData, 300);
  for i := 1 to Length(lvData) do
    lvData[i] := AnsiChar(Random(256));
  lvExpected := TbpMD5.HashStrHex(lvData);
  lvHasher := TbpMD5.Create;
  try
    // byte-at-a-time
    for i := 1 to Length(lvData) do
      lvHasher.Update(lvData[i], 1);
    lvHasher.Final(lvDigest);
    CheckEquals(lvExpected, TbpMD5.DigestToHex(lvDigest), 'byte at a time');
    // odd-size chunks crossing block boundaries
    lvPos := 1;
    lvChunk := 1;
    while lvPos <= Length(lvData) do
    begin
      if lvPos + lvChunk - 1 > Length(lvData) then
        lvChunk := Length(lvData) - lvPos + 1;
      lvHasher.Update(lvData[lvPos], lvChunk);
      Inc(lvPos, lvChunk);
      lvChunk := lvChunk * 2 + 1;  // 1, 3, 7, 15, ...
    end;
    lvHasher.Final(lvDigest);
    CheckEquals(lvExpected, TbpMD5.DigestToHex(lvDigest), 'odd chunks');
  finally
    lvHasher.Free;
  end;
end;

procedure TBpMD5Tests.TestBlockBoundaries;
const
  // around the 56-byte padding threshold and the 64-byte block size
  gcSizes: array[0..8] of Integer = (55, 56, 57, 63, 64, 65, 119, 120, 128);
var
  lvData: AnsiString;
  i, j: Integer;
begin
  RandSeed := 20260708;
  for i := Low(gcSizes) to High(gcSizes) do
  begin
    SetLength(lvData, gcSizes[i]);
    for j := 1 to Length(lvData) do
      lvData[j] := AnsiChar(Random(256));
    CheckEquals(CryptoApiHashHex(CALG_MD5, PAnsiChar(lvData)^, Length(lvData)),
      TbpMD5.HashStrHex(lvData), Format('size %d', [gcSizes[i]]));
  end;
end;

procedure TBpMD5Tests.TestInstanceReuseAfterFinal;
var
  lvHasher: TbpMD5;
  lvFirst, lvSecond: TbpMD5Digest;
begin
  lvHasher := TbpMD5.Create;
  try
    lvHasher.Update(AnsiString('abc'));
    lvHasher.Final(lvFirst);
    // Final resets the state, the same instance hashes the next message cleanly
    lvHasher.Update(AnsiString('abc'));
    lvHasher.Final(lvSecond);
  finally
    lvHasher.Free;
  end;
  CheckEquals(TbpMD5.DigestToHex(lvFirst), TbpMD5.DigestToHex(lvSecond));
  CheckEquals('900150983cd24fb0d6963f7d28e17f72', TbpMD5.DigestToHex(lvFirst));
end;

procedure TBpMD5Tests.TestHashFile;
var
  lvFileName: string;
  lvData: AnsiString;
  lvStream: TFileStream;
  i: Integer;
begin
  // 200 KB of random data, bigger than the 64 KB read chunk
  RandSeed := 20260709;
  SetLength(lvData, 200 * 1024);
  for i := 1 to Length(lvData) do
    lvData[i] := AnsiChar(Random(256));
  lvFileName := GetEnvironmentVariable('TEMP') + '\BpMD5Test.tmp';
  lvStream := TFileStream.Create(lvFileName, fmCreate);
  try
    lvStream.WriteBuffer(PAnsiChar(lvData)^, Length(lvData));
  finally
    lvStream.Free;
  end;
  try
    CheckEquals(TbpMD5.HashStrHex(lvData), TbpMD5.HashFileHex(lvFileName));
  finally
    DeleteFile(lvFileName);
  end;
end;

procedure TBpMD5Tests.TestDigestToBase64;
var
  lvDigest: TbpMD5Digest;
  lvBase64: string;
  lvBytes: TBytes;
  i: Integer;
begin
  lvDigest := TbpMD5.HashStr('abc');
  lvBase64 := TbpMD5.DigestToBase64(lvDigest);
  // 16 bytes encode to 24 chars with padding
  CheckEquals(24, Length(lvBase64));
  lvBytes := Base64Decode(lvBase64);
  CheckEquals(16, Length(lvBytes));
  for i := 0 to 15 do
    CheckEquals(lvDigest[i], lvBytes[i], Format('byte %d', [i]));
end;

procedure TBpMD5Tests.TestCryptoApiCrossCheck;
var
  lvData: AnsiString;
  lvCase, i: Integer;
begin
  RandSeed := 20260710;
  for lvCase := 1 to 50 do
  begin
    SetLength(lvData, Random(300));
    for i := 1 to Length(lvData) do
      lvData[i] := AnsiChar(Random(256));
    CheckEquals(CryptoApiHashHex(CALG_MD5, PAnsiChar(lvData)^, Length(lvData)),
      TbpMD5.HashStrHex(lvData), Format('case %d len %d', [lvCase, Length(lvData)]));
  end;
end;

initialization
  RegisterTest(TBpMD5Tests.Suite);

end.
