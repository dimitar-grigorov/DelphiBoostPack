unit BpStringOperationsBenchmark;

interface

uses
  TestFramework, SysUtils, Classes, Windows;

type
  TBpStringOperationsBenchmark = class(TTestCase)
  private
    function FunctionWithStringParam(s: string): string;
    function FunctionWithConstStringParam(const s: string): string;
    function ReverseStringWithTStringList(const s: string): string;
    function ReverseStringWithArray(const s: string): string;
    function ReverseStringWithConcatenation(const s: string): string;
    procedure LogStatus(const Msg: string);
    procedure LogStatusFmt(const Msg: string; const Args: array of const);
  public
    procedure TearDown; override;
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

var
  gvStringOperationsMessages: TStringList;

procedure TBpStringOperationsBenchmark.TearDown;
begin
  inherited;
  Status(gvStringOperationsMessages.Text);
end;

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

procedure TBpStringOperationsBenchmark.LogStatus(const Msg: string);
begin
  gvStringOperationsMessages.Add(Msg);
end;

procedure TBpStringOperationsBenchmark.LogStatusFmt(const Msg: string; const Args: array of const);
begin
  LogStatus(Format(Msg, Args));
end;

procedure TBpStringOperationsBenchmark.TestFunctionWithStringParam;
var
  StartTime: Cardinal;
  i: Integer;
begin
  StartTime := GetTickCount;
  for i := 1 to STRING_PARAM_NUM_ITERATIONS do
    FunctionWithStringParam('Test string');
  LogStatusFmt('TestFunctionWithStringParam - Elapsed time: %d ms', [GetTickCount - StartTime]);
end;

procedure TBpStringOperationsBenchmark.TestFunctionWithConstStringParam;
var
  StartTime: Cardinal;
  i: Integer;
begin
  StartTime := GetTickCount;
  for i := 1 to STRING_PARAM_NUM_ITERATIONS do
    FunctionWithConstStringParam('Test string');
  LogStatusFmt('TestFunctionWithConstStringParam - Elapsed time: %d ms', [GetTickCount - StartTime]);
end;

procedure TBpStringOperationsBenchmark.TestReverseStringWithTStringList;
var
  StartTime: Cardinal;
  i: Integer;
begin
  StartTime := GetTickCount;
  for i := 1 to REVERSE_STRING_NUM_ITERATIONS do
    ReverseStringWithTStringList('Test string');
  LogStatusFmt('TestReverseStringWithTStringList - Elapsed time: %d ms', [GetTickCount - StartTime]);
end;

procedure TBpStringOperationsBenchmark.TestReverseStringWithArray;
var
  StartTime: Cardinal;
  i: Integer;
begin
  StartTime := GetTickCount;
  for i := 1 to REVERSE_STRING_NUM_ITERATIONS do
    ReverseStringWithArray('Test string');
  LogStatusFmt('TestReverseStringWithArray - Elapsed time: %d ms', [GetTickCount - StartTime]);
end;

procedure TBpStringOperationsBenchmark.TestReverseStringWithConcatenation;
var
  StartTime: Cardinal;
  i: Integer;
begin
  StartTime := GetTickCount;
  for i := 1 to REVERSE_STRING_NUM_ITERATIONS do
    ReverseStringWithConcatenation('Test string');
  LogStatusFmt('TestReverseStringWithConcatenation - Elapsed time: %d ms', [GetTickCount - StartTime]);
end;

initialization
  gvStringOperationsMessages := TStringList.Create;
  RegisterTest(TBpStringOperationsBenchmark.Suite);

finalization
  gvStringOperationsMessages.Free;

end.

