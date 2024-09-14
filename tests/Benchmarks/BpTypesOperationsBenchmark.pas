unit BpTypesOperationsBenchmark;

{$TYPEINFO ON}

interface

uses
  TestFramework, Classes, SysUtils, Variants, BpBaseBenchmarkTestCase;

type
  TMyRecord = record
    Field1: Integer;
    Field2: Double;
    Field3: Boolean;
  end;

  TBpTypesOperationsBenchmark = class(TBpBaseBenchmarkTestCase)
  private
    function FunctionWithIntegerParam(i: Integer): Integer;
    function FunctionWithConstIntegerParam(const i: Integer): Integer;
    function FunctionWithInt64Param(i: Int64): Int64;
    function FunctionWithConstInt64Param(const i: Int64): Int64;
    function FunctionWithCurrencyParam(c: Currency): Currency;
    function FunctionWithConstCurrencyParam(const c: Currency): Currency;
    function FunctionWithSingleParam(s: Single): Single;
    function FunctionWithConstSingleParam(const s: Single): Single;
    function FunctionWithExtendedParam(e: Extended): Extended;
    function FunctionWithConstExtendedParam(const e: Extended): Extended;
    function FunctionWithObjectParam(o: TObject): TObject;
    function FunctionWithConstObjectParam(const o: TObject): TObject;
    function FunctionWithPointerParam(p: Pointer): Pointer;
    function FunctionWithConstPointerParam(const p: Pointer): Pointer;
    function FunctionWithVariantParam(v: Variant): Variant;
    function FunctionWithConstVariantParam(const v: Variant): Variant;
    function FunctionWithAnsiStringParam(s: AnsiString): AnsiString;
    function FunctionWithConstAnsiStringParam(const s: AnsiString): AnsiString;
    function FunctionWithWideStringParam(s: WideString): WideString;
    function FunctionWithConstWideStringParam(const s: WideString): WideString;
    function FunctionWithStaticArrayParam(arr: array of Integer): Integer;
    function FunctionWithConstStaticArrayParam(const arr: array of Integer): Integer;
    function FunctionWithRecordParam(r: TMyRecord): TMyRecord;
    function FunctionWithConstRecordParam(const r: TMyRecord): TMyRecord;
  published
    procedure TestFunctionWithIntegerParam;
    procedure TestFunctionWithConstIntegerParam;
    procedure TestFunctionWithInt64Param;
    procedure TestFunctionWithConstInt64Param;
    procedure TestFunctionWithCurrencyParam;
    procedure TestFunctionWithConstCurrencyParam;
    procedure TestFunctionWithSingleParam;
    procedure TestFunctionWithConstSingleParam;
    procedure TestFunctionWithExtendedParam;
    procedure TestFunctionWithConstExtendedParam;
    procedure TestFunctionWithObjectParam;
    procedure TestFunctionWithConstObjectParam;
    procedure TestFunctionWithPointerParam;
    procedure TestFunctionWithConstPointerParam;
    procedure TestFunctionWithVariantParam;
    procedure TestFunctionWithConstVariantParam;
    procedure TestFunctionWithAnsiStringParam;
    procedure TestFunctionWithConstAnsiStringParam;
    procedure TestFunctionWithWideStringParam;
    procedure TestFunctionWithConstWideStringParam;
    procedure TestFunctionWithStaticArrayParam;
    procedure TestFunctionWithConstStaticArrayParam;
    procedure TestFunctionWithRecordParam;
    procedure TestFunctionWithConstRecordParam;
  end;

implementation

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

function TBpTypesOperationsBenchmark.FunctionWithInt64Param(i: Int64): Int64;
begin
  Result := i + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstInt64Param(const i: Int64): Int64;
begin
  Result := i + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithCurrencyParam(c: Currency): Currency;
begin
  Result := c + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstCurrencyParam(const c: Currency): Currency;
begin
  Result := c + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithSingleParam(s: Single): Single;
begin
  Result := s + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstSingleParam(const s: Single): Single;
begin
  Result := s + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithExtendedParam(e: Extended): Extended;
begin
  Result := e + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstExtendedParam(const e: Extended): Extended;
begin
  Result := e + 1;
end;

function TBpTypesOperationsBenchmark.FunctionWithObjectParam(o: TObject): TObject;
begin
  Result := o;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstObjectParam(const o: TObject): TObject;
begin
  Result := o;
end;

function TBpTypesOperationsBenchmark.FunctionWithPointerParam(p: Pointer): Pointer;
begin
  Result := p;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstPointerParam(const p: Pointer): Pointer;
begin
  Result := p;
end;

function TBpTypesOperationsBenchmark.FunctionWithVariantParam(v: Variant): Variant;
begin
  Result := v;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstVariantParam(const v: Variant): Variant;
begin
  Result := v;
end;

function TBpTypesOperationsBenchmark.FunctionWithAnsiStringParam(s: AnsiString): AnsiString;
begin
  Result := s + ' appended';
end;

function TBpTypesOperationsBenchmark.FunctionWithConstAnsiStringParam(const s: AnsiString): AnsiString;
begin
  Result := s + ' appended';
end;

function TBpTypesOperationsBenchmark.FunctionWithWideStringParam(s: WideString): WideString;
begin
  Result := s + ' appended';
end;

function TBpTypesOperationsBenchmark.FunctionWithConstWideStringParam(const s: WideString): WideString;
begin
  Result := s + ' appended';
end;

function TBpTypesOperationsBenchmark.FunctionWithStaticArrayParam(arr: array of Integer): Integer;
var
  i, sum: Integer;
begin
  sum := 0;
  for i := Low(arr) to High(arr) do
    sum := sum + arr[i];
  Result := sum;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstStaticArrayParam(const arr: array of Integer): Integer;
var
  i, sum: Integer;
begin
  sum := 0;
  for i := Low(arr) to High(arr) do
    sum := sum + arr[i];
  Result := sum;
end;

function TBpTypesOperationsBenchmark.FunctionWithRecordParam(r: TMyRecord): TMyRecord;
begin
  r.Field1 := r.Field1 + 1;
  Result := r;
end;

function TBpTypesOperationsBenchmark.FunctionWithConstRecordParam(const r: TMyRecord): TMyRecord;
begin
  Result := r;
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithIntegerParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithIntegerParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithIntegerParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstIntegerParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstIntegerParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstIntegerParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithInt64Param;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithInt64Param(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithInt64Param - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstInt64Param;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstInt64Param(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstInt64Param - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithCurrencyParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithCurrencyParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithCurrencyParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstCurrencyParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstCurrencyParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstCurrencyParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithSingleParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithSingleParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithSingleParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstSingleParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstSingleParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstSingleParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithExtendedParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithExtendedParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithExtendedParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstExtendedParam;
var
  i: Integer;
begin
  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstExtendedParam(i);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstExtendedParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithObjectParam;
var
  i: Integer;
  lvResult: TObject;
begin
  lvResult := TObject.Create;
  try
    StartBenchmark;
    for i := 1 to NUM_ITERATIONS do
    begin
      lvResult := FunctionWithObjectParam(lvResult);
      if lvResult = nil then lvResult := TObject.Create; 
    end;
    StopBenchmark;
    LogStatusFmt('TestFunctionWithObjectParam - Elapsed time: %.3f ms', [GetElapsedTime]);
  finally
    lvResult.Free;
  end;
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstObjectParam;
var
  i: Integer;
  lvResult: TObject;
begin
  lvResult := TObject.Create;
  try
    StartBenchmark;
    for i := 1 to NUM_ITERATIONS do
    begin
      lvResult := FunctionWithConstObjectParam(lvResult);
      if lvResult = nil then lvResult := TObject.Create; 
    end;
    StopBenchmark;
    LogStatusFmt('TestFunctionWithConstObjectParam - Elapsed time: %.3f ms', [GetElapsedTime]);
  finally
    lvResult.Free;
  end;
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithPointerParam;
var
  i: Integer;
  lvPointer: Pointer;
begin
  lvPointer := @i;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithPointerParam(lvPointer);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithPointerParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstPointerParam;
var
  i: Integer;
  lvPointer: Pointer;
begin
  lvPointer := @i;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstPointerParam(lvPointer);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstPointerParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithVariantParam;
var
  i: Integer;
  lvVariant: Variant;
  lvResult: Variant;
begin
  lvVariant := 123;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
  begin
    lvResult := FunctionWithVariantParam(lvVariant);
    if VarIsNull(lvResult) then lvResult := lvVariant; 
  end;
  StopBenchmark;
  LogStatusFmt('TestFunctionWithVariantParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstVariantParam;
var
  i: Integer;
  lvVariant: Variant;
  lvResult: Variant;
begin
  lvVariant := 123;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
  begin
    lvResult := FunctionWithConstVariantParam(lvVariant);
    if VarIsNull(lvResult) then lvResult := lvVariant; 
  end;
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstVariantParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithAnsiStringParam;
var
  i: Integer;
  lvString, lvResult: AnsiString;
begin
  lvString := 'Test';

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
  begin
    lvResult := FunctionWithAnsiStringParam(lvString);
    if lvResult = '' then lvResult := lvString; 
  end;
  StopBenchmark;
  LogStatusFmt('TestFunctionWithAnsiStringParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstAnsiStringParam;
var
  i: Integer;
  lvString: AnsiString;
  lvResult: AnsiString;
begin
  lvString := 'Test';

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
  begin
    lvResult := FunctionWithConstAnsiStringParam(lvString);
    if lvResult = '' then lvResult := lvString; 
  end;
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstAnsiStringParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithWideStringParam;
var
  i: Integer;
  lvString: WideString;
  lvResult: WideString;
begin
  lvString := 'Test';

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
  begin
    lvResult := FunctionWithWideStringParam(lvString);
    if lvResult = '' then lvResult := lvString; 
  end;
  StopBenchmark;
  LogStatusFmt('TestFunctionWithWideStringParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstWideStringParam;
var
  i: Integer;
  lvString: WideString;
begin
  lvString := 'Test';

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstWideStringParam(lvString);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstWideStringParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithStaticArrayParam;
var
  i: Integer;
  lvArray: array[0..99] of Integer;
begin
  for i := 0 to 99 do
    lvArray[i] := i;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithStaticArrayParam(lvArray);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithStaticArrayParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstStaticArrayParam;
var
  i: Integer;
  lvArray: array[0..99] of Integer;
begin
  for i := 0 to 99 do
    lvArray[i] := i;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
    FunctionWithConstStaticArrayParam(lvArray);
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstStaticArrayParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithRecordParam;
var
  i: Integer;
  lvRecord: TMyRecord;
  lvResult: TMyRecord;
begin
  lvRecord.Field1 := 0;
  lvRecord.Field2 := 0.0;
  lvRecord.Field3 := False;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
  begin
    lvResult := FunctionWithRecordParam(lvRecord);
    if lvResult.Field1 < 0 then lvResult.Field1 := -lvResult.Field1; 
  end;
  StopBenchmark;
  LogStatusFmt('TestFunctionWithRecordParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;

procedure TBpTypesOperationsBenchmark.TestFunctionWithConstRecordParam;
var
  i: Integer;
  lvRecord: TMyRecord;
  lvResult: TMyRecord;
begin
  lvRecord.Field1 := 0;
  lvRecord.Field2 := 0.0;
  lvRecord.Field3 := False;

  StartBenchmark;
  for i := 1 to NUM_ITERATIONS do
  begin
    lvResult := FunctionWithConstRecordParam(lvRecord);
    if lvResult.Field1 < 0 then lvResult.Field1 := -lvResult.Field1; 
  end;
  StopBenchmark;
  LogStatusFmt('TestFunctionWithConstRecordParam - Elapsed time: %.3f ms', [GetElapsedTime]);
end;


initialization
  RegisterTest(TBpTypesOperationsBenchmark.Suite);

end.

