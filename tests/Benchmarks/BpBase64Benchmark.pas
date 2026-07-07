unit BpBase64Benchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpBaseBenchmarkTestCase, BpBase64;

type
  // BpBase64 vs the RTL EncdDecd unit. EncdDecd streams through TMemoryStream
  // in small chunks and inserts line breaks; BpBase64 computes the exact
  // output size and encodes in one pass.
  TBpBase64Benchmark = class(TBpBaseBenchmarkTestCase)
  private
    function BuildPayload(ASize: Integer): AnsiString;
  published
    procedure TestEncodeBpBase64;
    procedure TestEncodeRtlEncdDecd;
    procedure TestDecodeBpBase64;
    procedure TestDecodeRtlEncdDecd;
  end;

implementation

uses
  EncdDecd;

const
  PAYLOAD_SIZE = 3 * 1024 * 1024; // 3 MB of binary data, 4 MB encoded

function TBpBase64Benchmark.BuildPayload(ASize: Integer): AnsiString;
var
  i: Integer;
begin
  SetLength(Result, ASize);
  for i := 1 to ASize do
    Result[i] := AnsiChar(i and $FF);
end;

procedure TBpBase64Benchmark.TestEncodeBpBase64;
var
  lvData: AnsiString;
  lvEncoded: string;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  StartBenchmark;
  lvEncoded := Base64Encode(lvData);
  StopBenchmark;
  CheckEquals(((PAYLOAD_SIZE + 2) div 3) * 4, Length(lvEncoded));
  LogStatusFmt('Encode 3 MB: BpBase64 - %.3f ms', [GetElapsedTime]);
end;

procedure TBpBase64Benchmark.TestEncodeRtlEncdDecd;
var
  lvData: AnsiString;
  lvEncoded: string;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  StartBenchmark;
  lvEncoded := EncodeString(lvData);
  StopBenchmark;
  Check(Length(lvEncoded) > 0, 'encoded result must not be empty');
  LogStatusFmt('Encode 3 MB: EncdDecd.EncodeString - %.3f ms', [GetElapsedTime]);
end;

procedure TBpBase64Benchmark.TestDecodeBpBase64;
var
  lvData, lvDecoded: AnsiString;
  lvEncoded: string;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  lvEncoded := Base64Encode(lvData);
  StartBenchmark;
  lvDecoded := Base64DecodeStr(lvEncoded);
  StopBenchmark;
  CheckEquals(PAYLOAD_SIZE, Length(lvDecoded));
  LogStatusFmt('Decode 4 MB: BpBase64 - %.3f ms', [GetElapsedTime]);
end;

procedure TBpBase64Benchmark.TestDecodeRtlEncdDecd;
var
  lvData, lvDecoded: AnsiString;
  lvEncoded: string;
begin
  lvData := BuildPayload(PAYLOAD_SIZE);
  lvEncoded := EncodeString(lvData);
  StartBenchmark;
  lvDecoded := DecodeString(lvEncoded);
  StopBenchmark;
  CheckEquals(PAYLOAD_SIZE, Length(lvDecoded));
  LogStatusFmt('Decode 4 MB: EncdDecd.DecodeString - %.3f ms', [GetElapsedTime]);
end;

initialization
  RegisterTest(TBpBase64Benchmark.Suite);

end.
