{
 Delphi 7-2007 High-Precision Stopwatch
}

unit StopWatch;

interface

{$IF CompilerVersion < 20.0} // Delphi 2009 or lower

type
  IStopWatch = interface
    ['{C4EBF6C1-1E91-4DA7-A99B-5101707DD067}']
    procedure Start;
    procedure Stop;
    procedure Reset;
    function GetElapsedMilliseconds: Double;
    function GetElapsedTicks: Int64;
    function GetIsRunning: Boolean;
  end;

type
  TStopWatch = class(TInterfacedObject, IStopWatch)
  private
    FElapsed: Int64;
    FRunning: Boolean;
    FStartTimeStamp: Int64;
    FFrequency: Int64;
    FIsHighResolution: Boolean;
    FTickFrequency: Double;
    procedure InitStopwatchType;
    function GetElapsedDateTimeTicks: Double;
  public
    constructor Create;
    function GetTimeStamp: Int64;
    procedure Reset;
    procedure Start;
    class function StartNew: IStopWatch;
    class function Instance: IStopWatch;    
    procedure Stop;
    function GetElapsedMilliseconds: Double;
    function GetElapsedTicks: Int64;
    function GetIsRunning: Boolean;
  public
    property ElapsedMilliseconds: Double read GetElapsedMilliseconds;
    property ElapsedTicks: Int64 read GetElapsedTicks;
    property IsRunning: Boolean read GetIsRunning;
  end;

{$IFEND}  

implementation

{$IF CompilerVersion < 20.0}  // Delphi 2009 or lower

uses
  Windows;

var
  StopWatchInstance: IStopWatch = nil;

const
  TicksPerMillisecond = 10000;
  TicksPerSecond = 1000 * Int64(TicksPerMillisecond);

constructor TStopWatch.Create;
begin
  inherited Create;
  InitStopwatchType;
  Reset;
end;

function TStopwatch.GetElapsedDateTimeTicks: Double;
begin
  Result := Int64(GetElapsedTicks);
  if FIsHighResolution then
    Result := Result * FTickFrequency;
end;

function TStopWatch.GetElapsedMilliseconds: Double;
begin
  Result := GetElapsedDateTimeTicks / TicksPerMillisecond;
end;

function TStopwatch.GetElapsedTicks: Int64;
begin
  Result := FElapsed;
  if FRunning then
    Result := Result + GetTimeStamp - FStartTimeStamp;
end;

function TStopWatch.GetTimeStamp: Int64;
begin
  if FIsHighResolution then
    QueryPerformanceCounter(Result)
  else
    Result := GetTickCount * Int64(TicksPerMillisecond);
end;

procedure TStopwatch.InitStopwatchType;
begin
  if FFrequency = 0 then
  begin
    if not QueryPerformanceFrequency(FFrequency) then
    begin
      FIsHighResolution := False;
      FFrequency := TicksPerSecond;
      FTickFrequency := 1.0;
    end
    else
    begin
      FIsHighResolution := True;
      FTickFrequency := 10000000.0 / FFrequency;
    end;
  end;
end;

procedure TStopwatch.Reset;
begin
  FElapsed := 0;
  FRunning := False;
  FStartTimeStamp := 0;
end;

procedure TStopwatch.Start;
begin
  if not FRunning then
  begin
    FStartTimeStamp := GetTimeStamp;
    FRunning := True;
  end;
end;

class function TStopwatch.StartNew: IStopwatch;
begin
  Result := TStopWatch.Create;
  Result.Start;
end;

class function TStopWatch.Instance: IStopWatch;
begin
  if StopWatchInstance = nil then
    StopWatchInstance := TStopWatch.Create;
  Result := StopWatchInstance;
end;

procedure TStopwatch.Stop;
begin
  if FRunning then
  begin
    FElapsed := FElapsed + GetTimeStamp - FStartTimeStamp;
    FRunning := False;
  end;
end;

function TStopWatch.GetIsRunning: Boolean;
begin
  Result := FRunning;
end;

{$IFEND}

end.

