unit BpStringOperationsBenchmark;

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpBaseBenchmarkTestCase;

type
  TBpStringOperationsBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    function FunctionWithStringParam(s: string): string;
    function FunctionWithConstStringParam(const s: string): string;
    function ReverseStringWithTStringList(const s: string): string;
    function ReverseStringWithArray(const s: string): string;
    function ReverseStringWithConcatenation(const s: string): string;
  published
    procedure TestFunctionWithStringParam;
    procedure TestFunctionWithConstStringParam;
    procedure TestReverseStringWithTStringList;
    procedure TestReverseStringWithArray;
    procedure TestReverseStringWithConcatenation;
  end;

implementation

const
  STRING_PARAM_NUM_ITERATIONS = 5000000;
  REVERSE_STRING_NUM_ITERATIONS = 300000;

function TBpStringOperationsBenchmark.FunctionWithStringParam(s: string): string;
begin
  Result := s + ' processed';
end;

function TBpStringOperationsBenchmark.FunctionWithConstStringParam(const s: string): string;
begin
  Result := s + ' processed';
end;

function TBpStringOperationsBenchmark.ReverseStringWithTStringList(const s: string): string;
var
  i: Integer;
  List: TStringList;
begin
  List := TStringList.Create;
  try
    for i := Length(s) downto 1 do
      List.Add(s[i]);
    Result := TrimRight(List.Text);
  finally
    List.Free;
  end;
end;

function TBpStringOperationsBenchmark.ReverseStringWithArray(const s: string): string;
var
  i, len: Integer;
  CharArray: array of Char;
begin
  len := Length(s);
  SetLength(CharArray, len);
  for i := 1 to len do
    CharArray[len - i] := s[i];
  SetString(Result, PChar(CharArray), len);
end;

function TBpStringOperationsBenchmark.ReverseStringWithConcatenation(const s: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := Length(s) downto 1 do
    Result := Result + s[i];
end;

procedure TBpStringOperationsBenchmark.TestFunctionWithStringParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to STRING_PARAM_NUM_ITERATIONS do
    FunctionWithStringParam('Test string');
  StopBenchmark;

  LogStatusFmt('TestFunctionWithStringParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpStringOperationsBenchmark.TestFunctionWithConstStringParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to STRING_PARAM_NUM_ITERATIONS do
    FunctionWithConstStringParam('Test string');
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstStringParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpStringOperationsBenchmark.TestReverseStringWithTStringList;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to REVERSE_STRING_NUM_ITERATIONS do
    ReverseStringWithTStringList('Test string');
  StopBenchmark;
  LogStatusFmt('TestReverseStringWithTStringList - Elapsed time: %.3fms', [GetElapsedTime]);
end;

procedure TBpStringOperationsBenchmark.TestReverseStringWithArray;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to REVERSE_STRING_NUM_ITERATIONS do
    ReverseStringWithArray('Test string');
  StopBenchmark;
  LogStatusFmt('TestReverseStringWithArray - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpStringOperationsBenchmark.TestReverseStringWithConcatenation;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to REVERSE_STRING_NUM_ITERATIONS do
    ReverseStringWithConcatenation('Test string');
  StopBenchmark;
  LogStatusFmt('TestReverseStringWithConcatenation - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

initialization
  RegisterTest(TBpStringOperationsBenchmark.Suite);

end.

