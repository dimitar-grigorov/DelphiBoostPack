unit BpStrUtilsBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpBaseBenchmarkTestCase, BpStrUtils;

type
  // FastStringReplace vs SysUtils.StringReplace. The RTL copies the whole
  // remaining string on every match, so its cost grows quadratically with
  // the match count; FastStringReplace collects positions and builds the
  // result with a single allocation.
  TBpStrUtilsBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    function BuildText(const AChunk: string; ACount: Integer): string;
  published
    procedure TestReplaceAllFast;
    procedure TestReplaceAllRtl;
    procedure TestReplaceAllIgnoreCaseFast;
    procedure TestReplaceAllIgnoreCaseRtl;
    procedure TestReplaceSingleCharFast;
    procedure TestReplaceSingleCharRtl;
  end;

implementation

const
  NUM_MATCHES = 10000;         // 12 char chunks, 120 KB source text
  CHUNK = '0123456789ab';      // 'ab' is the pattern to replace
  CHUNK_COMMA = '0123456789,'; // single char pattern text

function TBpStrUtilsBenchmark.BuildText(const AChunk: string; ACount: Integer): string;
var
  i, lvChunkLen: Integer;
  lvDest: PChar;
begin
  lvChunkLen := Length(AChunk);
  SetLength(Result, lvChunkLen * ACount);
  lvDest := Pointer(Result);
  for i := 1 to ACount do
  begin
    Move(Pointer(AChunk)^, lvDest^, lvChunkLen * SizeOf(Char));
    Inc(lvDest, lvChunkLen);
  end;
end;

procedure TBpStrUtilsBenchmark.TestReplaceAllFast;
var
  lvText, lvResult: string;
begin
  lvText := BuildText(CHUNK, NUM_MATCHES);
  StartBenchmark;
  lvResult := FastStringReplace(lvText, 'ab', 'xyz', [rfReplaceAll]);
  StopBenchmark;
  CheckEquals(Length(lvText) + NUM_MATCHES, Length(lvResult));
  LogStatusFmt('Replace %d matches in %d KB: FastStringReplace - %.3f ms',
    [NUM_MATCHES, Length(lvText) div 1024, GetElapsedTime]);
end;

procedure TBpStrUtilsBenchmark.TestReplaceAllRtl;
var
  lvText, lvResult: string;
begin
  lvText := BuildText(CHUNK, NUM_MATCHES);
  StartBenchmark;
  lvResult := StringReplace(lvText, 'ab', 'xyz', [rfReplaceAll]);
  StopBenchmark;
  CheckEquals(Length(lvText) + NUM_MATCHES, Length(lvResult));
  LogStatusFmt('Replace %d matches in %d KB: SysUtils.StringReplace - %.3f ms',
    [NUM_MATCHES, Length(lvText) div 1024, GetElapsedTime]);
end;

procedure TBpStrUtilsBenchmark.TestReplaceAllIgnoreCaseFast;
var
  lvText, lvResult: string;
begin
  lvText := BuildText(CHUNK, NUM_MATCHES);
  StartBenchmark;
  lvResult := FastStringReplace(lvText, 'AB', 'xyz', [rfReplaceAll, rfIgnoreCase]);
  StopBenchmark;
  CheckEquals(Length(lvText) + NUM_MATCHES, Length(lvResult));
  LogStatusFmt('Replace %d matches ignore case: FastStringReplace - %.3f ms',
    [NUM_MATCHES, GetElapsedTime]);
end;

procedure TBpStrUtilsBenchmark.TestReplaceAllIgnoreCaseRtl;
var
  lvText, lvResult: string;
begin
  lvText := BuildText(CHUNK, NUM_MATCHES);
  StartBenchmark;
  lvResult := StringReplace(lvText, 'AB', 'xyz', [rfReplaceAll, rfIgnoreCase]);
  StopBenchmark;
  CheckEquals(Length(lvText) + NUM_MATCHES, Length(lvResult));
  LogStatusFmt('Replace %d matches ignore case: SysUtils.StringReplace - %.3f ms',
    [NUM_MATCHES, GetElapsedTime]);
end;

procedure TBpStrUtilsBenchmark.TestReplaceSingleCharFast;
var
  lvText, lvResult: string;
begin
  lvText := BuildText(CHUNK_COMMA, NUM_MATCHES);
  StartBenchmark;
  lvResult := FastStringReplace(lvText, ',', ';', [rfReplaceAll]);
  StopBenchmark;
  CheckEquals(Length(lvText), Length(lvResult));
  CheckEquals(';', lvResult[Length(lvResult)]);
  LogStatusFmt('Replace %d single chars: FastStringReplace - %.3f ms',
    [NUM_MATCHES, GetElapsedTime]);
end;

procedure TBpStrUtilsBenchmark.TestReplaceSingleCharRtl;
var
  lvText, lvResult: string;
begin
  lvText := BuildText(CHUNK_COMMA, NUM_MATCHES);
  StartBenchmark;
  lvResult := StringReplace(lvText, ',', ';', [rfReplaceAll]);
  StopBenchmark;
  CheckEquals(Length(lvText), Length(lvResult));
  CheckEquals(';', lvResult[Length(lvResult)]);
  LogStatusFmt('Replace %d single chars: SysUtils.StringReplace - %.3f ms',
    [NUM_MATCHES, GetElapsedTime]);
end;

initialization
  RegisterTest(TBpStrUtilsBenchmark.Suite);

end.
