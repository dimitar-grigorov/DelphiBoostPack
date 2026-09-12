unit BpHashBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpBaseBenchmarkTestCase, BpSHA256, BpMD5,
  BpPasswordHash;

type
  // pure Pascal BpSHA256/BpMD5 vs the Windows CryptoAPI, in MB/s on one buffer
  TBpHashBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    function BuildPayload(aSize: Integer): AnsiString;
    procedure LogThroughput(const aName: string; aSize: Integer);
  published
    procedure TestSHA256BpSHA256;
    procedure TestSHA256CryptoApi;
    procedure TestMD5BpMD5;
    procedure TestMD5CryptoApi;
    procedure TestPBKDF2SHA256;
  end;

implementation

uses
  BpCryptoApiHash;

const
  PAYLOAD_SIZE = 10 * 1024 * 1024; // 10 MB
  PBKDF2_ITERATIONS = 100000;      // a sixth of the password hashing default
  PBKDF2_RUNS = 5;

function TBpHashBenchmark.BuildPayload(aSize: Integer): AnsiString;
var
  i: Integer;
begin
  SetLength(Result, aSize);
  for i := 1 to aSize do
    Result[i] := AnsiChar(i and $FF);
end;

procedure TBpHashBenchmark.LogThroughput(const aName: string; aSize: Integer);
begin
  LogStatusFmt('%s: %.1f ms, %.0f MB/s',
    [aName, GetElapsedTime, (aSize / (1024 * 1024)) / (GetElapsedTime / 1000)]);
end;

// the only hot loop in the unit: this is what a login costs the user
procedure TBpHashBenchmark.TestPBKDF2SHA256;
var
  lvKey: AnsiString;
  i: Integer;
begin
  for i := 1 to PBKDF2_RUNS do
  begin
    StartBenchmark;
    lvKey := BpPBKDF2SHA256('correct horse battery staple', 'a-salt-16-bytes',
      PBKDF2_ITERATIONS, 32);
    StopBenchmark;
  end;
  CheckEquals(32, Length(lvKey));
  LogStatusFmt('PBKDF2-HMAC-SHA256 %d iterations: %.1f ms median of %d, %.0f iterations/s',
    [PBKDF2_ITERATIONS, MedianTime, SampleCount,
     PBKDF2_ITERATIONS / (MedianTime / 1000)]);
end;

procedure TBpHashBenchmark.TestSHA256BpSHA256;
var
  lvData: AnsiString;
  lvDigest: TbpSHA256Digest;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  StartBenchmark;
  lvDigest := TbpSHA256.HashStr(lvData);
  StopBenchmark;
  CheckEquals(64, Length(TbpSHA256.DigestToHex(lvDigest)));
  LogThroughput('SHA-256 10 MB: BpSHA256', PAYLOAD_SIZE);
end;

procedure TBpHashBenchmark.TestSHA256CryptoApi;
var
  lvData: AnsiString;
  lvDigest: TBytes;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  StartBenchmark;
  lvDigest := CryptoApiHash(CALG_SHA_256, PAnsiChar(lvData)^, Length(lvData));
  StopBenchmark;
  CheckEquals(32, Length(lvDigest));
  LogThroughput('SHA-256 10 MB: CryptoAPI', PAYLOAD_SIZE);
end;

procedure TBpHashBenchmark.TestMD5BpMD5;
var
  lvData: AnsiString;
  lvDigest: TbpMD5Digest;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  StartBenchmark;
  lvDigest := TbpMD5.HashStr(lvData);
  StopBenchmark;
  CheckEquals(32, Length(TbpMD5.DigestToHex(lvDigest)));
  LogThroughput('MD5 10 MB: BpMD5', PAYLOAD_SIZE);
end;

procedure TBpHashBenchmark.TestMD5CryptoApi;
var
  lvData: AnsiString;
  lvDigest: TBytes;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  StartBenchmark;
  lvDigest := CryptoApiHash(CALG_MD5, PAnsiChar(lvData)^, Length(lvData));
  StopBenchmark;
  CheckEquals(16, Length(lvDigest));
  LogThroughput('MD5 10 MB: CryptoAPI', PAYLOAD_SIZE);
end;

initialization
  RegisterTest(TBpHashBenchmark.Suite);

end.
