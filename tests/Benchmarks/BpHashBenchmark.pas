unit BpHashBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpBaseBenchmarkTestCase, BpSHA256, BpMD5;

type
  // pure Pascal BpSHA256/BpMD5 vs the Windows CryptoAPI implementations,
  // throughput in MB/s on one large buffer
  TBpHashBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    function BuildPayload(ASize: Integer): AnsiString;
    procedure LogThroughput(const AName: string; ASize: Integer);
  published
    procedure TestSHA256BpSHA256;
    procedure TestSHA256CryptoApi;
    procedure TestMD5BpMD5;
    procedure TestMD5CryptoApi;
  end;

implementation

uses
  BpCryptoApiHash;

const
  PAYLOAD_SIZE = 10 * 1024 * 1024; // 10 MB

function TBpHashBenchmark.BuildPayload(ASize: Integer): AnsiString;
var
  i: Integer;
begin
  SetLength(Result, ASize);
  for i := 1 to ASize do
    Result[i] := AnsiChar(i and $FF);
end;

procedure TBpHashBenchmark.LogThroughput(const AName: string; ASize: Integer);
begin
  LogStatusFmt('%s: %.1f ms, %.0f MB/s',
    [AName, GetElapsedTime, (ASize / (1024 * 1024)) / (GetElapsedTime / 1000)]);
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
