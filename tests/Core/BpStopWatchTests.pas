unit BpStopWatchTests;

{$TYPEINFO ON}

interface

{$IF CompilerVersion < 20.0} // the unit itself stops there

uses
  TestFramework, SysUtils, StopWatch;

type
  TBpStopWatchTests = class(TTestCase)
  published
    procedure TestDocumentedSurfaceThroughTheInterface;
    procedure TestARunningWatchAdvances;
    procedure TestStopFreezesTheReading;
    procedure TestStartAfterStopResumes;
    procedure TestResetAndStart;
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

// 20 ms, so the GetTickCount fallback on a box without QPC also moves
procedure TBpStopWatchTests.TestARunningWatchAdvances;
var
  lvSw: IStopWatch;
  lvFirst: Int64;
begin
  lvSw := TStopWatch.StartNew;
  Sleep(20);
  lvFirst := lvSw.ElapsedTicks;
  CheckTrue(lvFirst > 0, 'a slept-through watch has ticked');
  CheckTrue(lvSw.ElapsedMilliseconds > 0, 'and says so in milliseconds');
  Sleep(20);
  CheckTrue(lvSw.ElapsedTicks > lvFirst, 'a running watch keeps ticking');
end;

procedure TBpStopWatchTests.TestStopFreezesTheReading;
var
  lvSw: IStopWatch;
  lvFirst: Int64;
begin
  lvSw := TStopWatch.StartNew;
  Sleep(20);
  lvSw.Stop;
  lvFirst := lvSw.ElapsedTicks;
  CheckTrue(lvFirst > 0, 'the watch ran before it stopped');
  Sleep(20);
  CheckEquals(lvFirst, lvSw.ElapsedTicks, 'a stopped watch does not move');
end;

procedure TBpStopWatchTests.TestStartAfterStopResumes;
var
  lvSw: IStopWatch;
  lvFirst: Int64;
begin
  lvSw := TStopWatch.StartNew;
  Sleep(20);
  lvSw.Stop;
  lvFirst := lvSw.ElapsedTicks;
  lvSw.Start;
  Sleep(20);
  lvSw.Stop;
  CheckTrue(lvSw.ElapsedTicks > lvFirst, 'Start adds to what was there, it does not restart');
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

initialization
  RegisterTest(TBpStopWatchTests.Suite);

{$IFEND}

end.
