unit BpStopWatchTests;

{$TYPEINFO ON}

interface

{$IF CompilerVersion < 20.0} // the unit itself stops there

uses
  TestFramework, Windows, SysUtils, StopWatch;

type
  TBpStopWatchTests = class(TTestCase)
  published
    procedure TestDocumentedSurfaceThroughTheInterface;
    procedure TestStopFreezesTheReading;
    procedure TestResetAndStart;
    procedure TestInstanceIsShared;
  end;

{$IFEND}

implementation

{$IF CompilerVersion < 20.0}

// the README example, verbatim, so a missing interface member breaks the build
procedure TBpStopWatchTests.TestDocumentedSurfaceThroughTheInterface;
var
  lvSw: IStopWatch;
  lvMs: Double;
  lvTicks: Int64;
begin
  lvSw := TStopWatch.StartNew;
  CheckTrue(lvSw.IsRunning, 'running after StartNew');
  Sleep(2);
  lvSw.Stop;
  CheckFalse(lvSw.IsRunning, 'stopped');
  lvMs := lvSw.ElapsedMilliseconds;
  lvTicks := lvSw.ElapsedTicks;
  CheckTrue(lvMs >= 0, 'elapsed is not negative');
  CheckTrue(lvTicks >= 0, 'ticks are not negative');
end;

procedure TBpStopWatchTests.TestStopFreezesTheReading;
var
  lvSw: IStopWatch;
  lvFirst: Int64;
begin
  lvSw := TStopWatch.StartNew;
  Sleep(2);
  lvSw.Stop;
  lvFirst := lvSw.ElapsedTicks;
  Sleep(5);
  CheckEquals(lvFirst, lvSw.ElapsedTicks, 'a stopped watch does not move');
end;

procedure TBpStopWatchTests.TestResetAndStart;
var
  lvSw: IStopWatch;
begin
  lvSw := TStopWatch.StartNew;
  Sleep(2);
  lvSw.Stop;
  lvSw.Reset;
  CheckEquals(Int64(0), lvSw.ElapsedTicks, 'Reset zeroes');
  CheckFalse(lvSw.IsRunning, 'Reset does not start');
  lvSw.ResetAndStart;
  CheckTrue(lvSw.IsRunning, 'ResetAndStart runs');
  lvSw.Stop;
end;

procedure TBpStopWatchTests.TestInstanceIsShared;
begin
  Check(TStopWatch.Instance = TStopWatch.Instance, 'one shared instance');
end;

initialization
  RegisterTest(TBpStopWatchTests.Suite);

{$IFEND}

end.
