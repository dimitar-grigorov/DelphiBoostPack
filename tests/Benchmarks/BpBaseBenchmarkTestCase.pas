unit BpBaseBenchmarkTestCase;

interface

uses
  TestFramework, Windows, SysUtils, Classes;

type
  TBpBaseBenchmarkTestCase = class(TTestCase)
  private
    FFrequency: Int64;
    FStartTime: Int64;
    FStopTime: Int64;
    FFirstMessage: Integer;   // where this test's own messages start
    FSamples: array of Double;
  protected
    procedure InitializeBenchmark;
    procedure StartBenchmark;
    procedure StopBenchmark;
    function GetElapsedTime: Double;
    // one run varies by half on a boosting CPU, so a claim needs several
    function MedianTime: Double;
    function SampleCount: Integer;
    procedure LogStatus(const Msg: string);
    procedure LogStatusFmt(const Msg: string; const Args: array of const);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  end;

implementation

var
  gvSuiteBenchmarkMessages: TStringList;  // Global list to store all messages

procedure TBpBaseBenchmarkTestCase.InitializeBenchmark;
begin
  if not QueryPerformanceFrequency(FFrequency) then
    raise Exception.Create('High-resolution performance counter not supported');
end;

procedure TBpBaseBenchmarkTestCase.SetUp;
begin
  inherited;
  InitializeBenchmark;
  FFirstMessage := gvSuiteBenchmarkMessages.Count;
  SetLength(FSamples, 0);
end;

// only this test's own lines, otherwise every TearDown reprints the whole run
procedure TBpBaseBenchmarkTestCase.TearDown;
var
  i: Integer;
begin
  inherited TearDown;
  for i := FFirstMessage to gvSuiteBenchmarkMessages.Count - 1 do
    Status(gvSuiteBenchmarkMessages[i]);
end;

procedure TBpBaseBenchmarkTestCase.StartBenchmark;
begin
  QueryPerformanceCounter(FStartTime);
end;

procedure TBpBaseBenchmarkTestCase.StopBenchmark;
begin
  QueryPerformanceCounter(FStopTime);
  SetLength(FSamples, Length(FSamples) + 1);
  FSamples[High(FSamples)] := GetElapsedTime;
end;

function TBpBaseBenchmarkTestCase.SampleCount: Integer;
begin
  Result := Length(FSamples);
end;

// the middle of the samples, which no single slow run can move
function TBpBaseBenchmarkTestCase.MedianTime: Double;
var
  lvSorted: array of Double;
  i, j: Integer;
  lvSwap: Double;
begin
  if Length(FSamples) = 0 then
  begin
    Result := 0;
    Exit;
  end;
  // two anonymous dynamic array types never assign, so copy element wise
  SetLength(lvSorted, Length(FSamples));
  for i := 0 to High(FSamples) do
    lvSorted[i] := FSamples[i];
  for i := 1 to High(lvSorted) do
  begin
    lvSwap := lvSorted[i];
    j := i - 1;
    while (j >= 0) and (lvSorted[j] > lvSwap) do
    begin
      lvSorted[j + 1] := lvSorted[j];
      Dec(j);
    end;
    lvSorted[j + 1] := lvSwap;
  end;
  i := Length(lvSorted);
  if Odd(i) then
    Result := lvSorted[i div 2]
  else
    Result := (lvSorted[i div 2 - 1] + lvSorted[i div 2]) / 2;
end;

function TBpBaseBenchmarkTestCase.GetElapsedTime: Double;
begin
  Result := (FStopTime - FStartTime) / FFrequency * 1000; // Elapsed time in milliseconds
end;

procedure TBpBaseBenchmarkTestCase.LogStatus(const Msg: string);
begin
  gvSuiteBenchmarkMessages.Add(Msg);
end;

procedure TBpBaseBenchmarkTestCase.LogStatusFmt(const Msg: string; const Args: array of const);
begin
  LogStatus(Format(Msg, Args));
end;

initialization
  gvSuiteBenchmarkMessages := TStringList.Create;

finalization
  gvSuiteBenchmarkMessages.Free;

end.

