unit BpStringBuilderBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpBaseBenchmarkTestCase, BpStringBuilder;

type
  // TbpStringBuilder vs naive s := s + x concatenation. FastMM4 often extends
  // strings in place, so the naive numbers are better than folklore says;
  // these tests document the honest difference.
  TBpStringBuilderBenchmark = class(TBpBaseBenchmarkTestCase)
  published
    procedure TestAppendStringBpBuilder;
    procedure TestAppendStringNaiveConcat;
    procedure TestAppendCharBpBuilder;
    procedure TestAppendCharNaiveConcat;
    procedure TestAppendIntegerBpBuilder;
    procedure TestAppendIntegerNaiveConcat;
  end;

implementation

const
  NUM_CHUNKS = 100000;       // 10 char chunks, 1 MB result
  NUM_CHARS = 1000000;       // single char appends, 1 MB result
  NUM_INTS = 100000;
  CHUNK = '0123456789';

procedure TBpStringBuilderBenchmark.TestAppendStringBpBuilder;
var
  lvBuilder: TbpStringBuilder;
  lvResult: string;
  i: Integer;
begin
  lvBuilder := TbpStringBuilder.Create;
  try
    StartBenchmark;
    for i := 1 to NUM_CHUNKS do
      lvBuilder.Append(CHUNK);
    lvResult := lvBuilder.ToString;
    StopBenchmark;
    CheckEquals(NUM_CHUNKS * Length(CHUNK), Length(lvResult));
    LogStatusFmt('Append %d x 10 chars: TbpStringBuilder - %.3f ms',
      [NUM_CHUNKS, GetElapsedTime]);
  finally
    lvBuilder.Free;
  end;
end;

procedure TBpStringBuilderBenchmark.TestAppendStringNaiveConcat;
var
  lvResult: string;
  i: Integer;
begin
  lvResult := '';
  StartBenchmark;
  for i := 1 to NUM_CHUNKS do
    lvResult := lvResult + CHUNK;
  StopBenchmark;
  CheckEquals(NUM_CHUNKS * Length(CHUNK), Length(lvResult));
  LogStatusFmt('Append %d x 10 chars: naive s := s + x - %.3f ms',
    [NUM_CHUNKS, GetElapsedTime]);
end;

procedure TBpStringBuilderBenchmark.TestAppendCharBpBuilder;
var
  lvBuilder: TbpStringBuilder;
  lvResult: string;
  i: Integer;
begin
  lvBuilder := TbpStringBuilder.Create;
  try
    StartBenchmark;
    for i := 1 to NUM_CHARS do
      lvBuilder.Append('x');
    lvResult := lvBuilder.ToString;
    StopBenchmark;
    CheckEquals(NUM_CHARS, Length(lvResult));
    LogStatusFmt('Append %d single chars: TbpStringBuilder - %.3f ms',
      [NUM_CHARS, GetElapsedTime]);
  finally
    lvBuilder.Free;
  end;
end;

procedure TBpStringBuilderBenchmark.TestAppendCharNaiveConcat;
var
  lvResult: string;
  i: Integer;
begin
  lvResult := '';
  StartBenchmark;
  for i := 1 to NUM_CHARS do
    lvResult := lvResult + 'x';
  StopBenchmark;
  CheckEquals(NUM_CHARS, Length(lvResult));
  LogStatusFmt('Append %d single chars: naive s := s + x - %.3f ms',
    [NUM_CHARS, GetElapsedTime]);
end;

procedure TBpStringBuilderBenchmark.TestAppendIntegerBpBuilder;
var
  lvBuilder: TbpStringBuilder;
  lvResult: string;
  i: Integer;
begin
  lvBuilder := TbpStringBuilder.Create;
  try
    StartBenchmark;
    for i := 1 to NUM_INTS do
      lvBuilder.Append(i);
    lvResult := lvBuilder.ToString;
    StopBenchmark;
    Check(Length(lvResult) > 0, 'result must not be empty');
    LogStatusFmt('Append %d integers: TbpStringBuilder - %.3f ms',
      [NUM_INTS, GetElapsedTime]);
  finally
    lvBuilder.Free;
  end;
end;

procedure TBpStringBuilderBenchmark.TestAppendIntegerNaiveConcat;
var
  lvResult: string;
  i: Integer;
begin
  lvResult := '';
  StartBenchmark;
  for i := 1 to NUM_INTS do
    lvResult := lvResult + IntToStr(i);
  StopBenchmark;
  Check(Length(lvResult) > 0, 'result must not be empty');
  LogStatusFmt('Append %d integers: naive s := s + IntToStr - %.3f ms',
    [NUM_INTS, GetElapsedTime]);
end;

initialization
  RegisterTest(TBpStringBuilderBenchmark.Suite);

end.
