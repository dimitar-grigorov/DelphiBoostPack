unit BpSHA256Tests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, BpSHA256;

type
  TBpSHA256Tests = class(TTestCase)
  private
    procedure CheckHashStr(const AExpectedHex: string; const AText: AnsiString);
  published
    procedure TestFipsVectors;
    procedure TestMillionA;
    procedure TestStreamingMatchesOneShot;
    procedure TestBlockBoundaries;
    procedure TestInstanceReuseAfterFinal;
    procedure TestHashBytes;
    procedure TestHashBuffer;
    procedure TestHashFile;
    procedure TestDigestToBase64;
    procedure TestCryptoApiCrossCheck;
  end;

implementation

uses
  BpBase64, BpCryptoApiHash;

procedure TBpSHA256Tests.CheckHashStr(const AExpectedHex: string; const AText: AnsiString);
begin
  CheckEquals(AExpectedHex, TbpSHA256.HashStrHex(AText), string(AText));
end;

procedure TBpSHA256Tests.TestFipsVectors;
begin
  // FIPS 180-4 known-answer vectors
  CheckHashStr('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', '');
  CheckHashStr('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'abc');
  CheckHashStr('248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq');
  CheckHashStr('cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
    'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno' +
    'ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu');
end;

procedure TBpSHA256Tests.TestMillionA;
var
  lvHasher: TbpSHA256;
  lvChunk: AnsiString;
  lvDigest: TbpSHA256Digest;
  i: Integer;
begin
  // FIPS streaming vector: one million 'a', fed in 1000-byte chunks
  lvChunk := StringOfChar(AnsiChar('a'), 1000);
  lvHasher := TbpSHA256.Create;
  try
    for i := 1 to 1000 do
      lvHasher.Update(lvChunk);
    lvHasher.Final(lvDigest);
  finally
    lvHasher.Free;
  end;
  CheckEquals('cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    TbpSHA256.DigestToHex(lvDigest));
end;

procedure TBpSHA256Tests.TestStreamingMatchesOneShot;
var
  lvData: AnsiString;
  lvHasher: TbpSHA256;
  lvDigest: TbpSHA256Digest;
  lvExpected: string;
  i, lvPos, lvChunk: Integer;
begin
  RandSeed := 20260707;
  SetLength(lvData, 300);
  for i := 1 to Length(lvData) do
    lvData[i] := AnsiChar(Random(256));
  lvExpected := TbpSHA256.HashStrHex(lvData);
  lvHasher := TbpSHA256.Create;
  try
    // byte-at-a-time
    for i := 1 to Length(lvData) do
      lvHasher.Update(lvData[i], 1);
    lvHasher.Final(lvDigest);
    CheckEquals(lvExpected, TbpSHA256.DigestToHex(lvDigest), 'byte at a time');
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
    CheckEquals(lvExpected, TbpSHA256.DigestToHex(lvDigest), 'odd chunks');
  finally
    lvHasher.Free;
  end;
end;

procedure TBpSHA256Tests.TestBlockBoundaries;
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
    CheckEquals(CryptoApiHashHex(CALG_SHA_256, PAnsiChar(lvData)^, Length(lvData)),
      TbpSHA256.HashStrHex(lvData), Format('size %d', [gcSizes[i]]));
  end;
end;

procedure TBpSHA256Tests.TestInstanceReuseAfterFinal;
var
  lvHasher: TbpSHA256;
  lvFirst, lvSecond: TbpSHA256Digest;
begin
  lvHasher := TbpSHA256.Create;
  try
    lvHasher.Update(AnsiString('abc'));
    lvHasher.Final(lvFirst);
    // Final resets the state, the same instance hashes the next message cleanly
    lvHasher.Update(AnsiString('abc'));
    lvHasher.Final(lvSecond);
  finally
    lvHasher.Free;
  end;
  CheckEquals(TbpSHA256.DigestToHex(lvFirst), TbpSHA256.DigestToHex(lvSecond));
  CheckEquals('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    TbpSHA256.DigestToHex(lvFirst));
end;

procedure TBpSHA256Tests.TestHashBytes;
var
  lvBytes: TBytes;
begin
  SetLength(lvBytes, 3);
  lvBytes[0] := Ord('a');
  lvBytes[1] := Ord('b');
  lvBytes[2] := Ord('c');
  CheckEquals('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    TbpSHA256.DigestToHex(TbpSHA256.HashBytes(lvBytes)));
  lvBytes := nil;
  CheckEquals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    TbpSHA256.DigestToHex(TbpSHA256.HashBytes(lvBytes)), 'empty bytes');
end;

procedure TBpSHA256Tests.TestHashBuffer;
var
  lvBuf: array[0..2] of AnsiChar;
begin
  lvBuf[0] := 'a';
  lvBuf[1] := 'b';
  lvBuf[2] := 'c';
  CheckEquals('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    TbpSHA256.DigestToHex(TbpSHA256.HashBuffer(lvBuf, 3)));
end;

procedure TBpSHA256Tests.TestHashFile;
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
  lvFileName := GetEnvironmentVariable('TEMP') + '\BpSHA256Test.tmp';
  lvStream := TFileStream.Create(lvFileName, fmCreate);
  try
    lvStream.WriteBuffer(PAnsiChar(lvData)^, Length(lvData));
  finally
    lvStream.Free;
  end;
  try
    CheckEquals(TbpSHA256.HashStrHex(lvData), TbpSHA256.HashFileHex(lvFileName));
  finally
    DeleteFile(lvFileName);
  end;
end;

procedure TBpSHA256Tests.TestDigestToBase64;
var
  lvDigest: TbpSHA256Digest;
  lvBase64: string;
  lvBytes: TBytes;
  i: Integer;
begin
  lvDigest := TbpSHA256.HashStr('abc');
  lvBase64 := TbpSHA256.DigestToBase64(lvDigest);
  // 32 bytes encode to 44 chars with padding
  CheckEquals(44, Length(lvBase64));
  lvBytes := Base64Decode(lvBase64);
  CheckEquals(32, Length(lvBytes));
  for i := 0 to 31 do
    CheckEquals(lvDigest[i], lvBytes[i], Format('byte %d', [i]));
end;

procedure TBpSHA256Tests.TestCryptoApiCrossCheck;
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
    CheckEquals(CryptoApiHashHex(CALG_SHA_256, PAnsiChar(lvData)^, Length(lvData)),
      TbpSHA256.HashStrHex(lvData), Format('case %d len %d', [lvCase, Length(lvData)]));
  end;
end;

initialization
  RegisterTest(TBpSHA256Tests.Suite);

end.
