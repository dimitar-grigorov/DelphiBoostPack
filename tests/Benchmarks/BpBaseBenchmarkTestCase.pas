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
  protected
    procedure InitializeBenchmark;
    procedure StartBenchmark;
    procedure StopBenchmark;
    function GetElapsedTime: Double;
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
end;

procedure TBpBaseBenchmarkTestCase.TearDown;
begin
  inherited TearDown;
  Status(gvSuiteBenchmarkMessages.Text);
end;

procedure TBpBaseBenchmarkTestCase.StartBenchmark;
begin
  QueryPerformanceCounter(FStartTime);
end;

procedure TBpBaseBenchmarkTestCase.StopBenchmark;
begin
  QueryPerformanceCounter(FStopTime);
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

