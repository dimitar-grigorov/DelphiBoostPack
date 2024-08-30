unit BpTypesOperationsBenchmark;

interface

uses
  TestFramework, Classes, BpBaseBenchmarkTestCase;

type
  TBpTypesOperationsBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    function FunctionWithIntegerParam(i: Integer): Integer;
    function FunctionWithConstIntegerParam(const i: Integer): Integer;
    function FunctionWithDoubleParam(d: Double): Double;
    function FunctionWithConstDoubleParam(const d: Double): Double;
    function FunctionWithBooleanParam(b: Boolean): Boolean;
    function FunctionWithConstBooleanParam(const b: Boolean): Boolean;
  published
    procedure TestFunctionWithIntegerParam;
    procedure TestFunctionWithConstIntegerParam;
    procedure TestFunctionWithDoubleParam;
    procedure TestFunctionWithConstDoubleParam;
    procedure TestFunctionWithBooleanParam;
    procedure TestFunctionWithConstBooleanParam;
  end;

implementation

uses
  SysUtils;

const
  NUM_ITERATIONS = 10000000;

function TBpTypesOperationsBenchmark.FunctionWithIntegerParam(i: Integer): Integer;
begin
  Result := i + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstIntegerParam(const i: Integer): Integer;
begin
  Result := i + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithDoubleParam(d: Double): Double;
begin
  Result := d + 1.0;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstDoubleParam(const d: Double): Double;
begin
  Result := d + 1.0;
end;

function TBpTypesOperationsBenchmark.FunctionWithBooleanParam(b: Boolean): Boolean;
begin
  Result := not b;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstBooleanParam(const b: Boolean): Boolean;
begin
  Result := not b;
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithIntegerParam;
var
  i: Integer;
  lvResult: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    lvResult := FunctionWithIntegerParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithIntegerParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstIntegerParam;
var
  i: Integer;
  lvResult: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    lvResult := FunctionWithConstIntegerParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstIntegerParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithDoubleParam;
var
  i: Integer;
  lvResult: Double;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    lvResult := FunctionWithDoubleParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithDoubleParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstDoubleParam;
var
  i: Integer;
  lvResult: Double;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    lvResult := FunctionWithConstDoubleParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstDoubleParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithBooleanParam;
var
  i: Integer;
  lvResult: Boolean;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    lvResult := FunctionWithBooleanParam(True);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithBooleanParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstBooleanParam;
var
  i: Integer;
  lvResult: Boolean;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    lvResult := FunctionWithConstBooleanParam(True);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstBooleanParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

initialization
  RegisterTest(TBpTypesOperationsBenchmark.Suite);

end.

