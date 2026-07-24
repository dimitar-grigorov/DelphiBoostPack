unit BpTasksTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpTasks;

type
  // all offline, all console mode (aMarshalToMainThread=False): a test
  // runner has no message loop, so events fire on the worker thread
  TBpTasksTests = class(TTestCase)
  private
    FWorkRan: Boolean;
    FWorkExited: Boolean;
    FCompleteCount: Integer;
    FErrorCount: Integer;
    FLastErrorMessage: string;
    FStateInComplete: TbpTaskState;
    procedure WorkQuick(aSender: TObject; aToken: TbpTaskToken);
    procedure WorkRaise(aSender: TObject; aToken: TbpTaskToken);
    procedure WorkLoopUntilCancelled(aSender: TObject; aToken: TbpTaskToken);
    procedure HandleComplete(aSender: TObject);
    procedure HandleError(aSender: TObject; const aErrorMessage: string);
    function WaitForFlag(var aFlag: Boolean; aTimeoutMs: Cardinal): Boolean;
  protected
    procedure SetUp; override;
  published
    procedure TestTokenCancelIsSticky;
    procedure TestInitialState;
    procedure TestWorkRunsAndSucceeds;
    procedure TestExceptionMapsToFailed;
    procedure TestCancelBeforeStart;
    procedure TestCancelDuringRun;
    procedure TestWaitForJoins;
    procedure TestOnCompleteFiresExactlyOnce;
    procedure TestDestroyRunningTaskCancelsAndJoins;
    procedure TestDoubleStartRaises;
    procedure TestStartWithoutWorkRaises;
    procedure TestRunAsyncFactory;
    procedure TestRunAsyncWithNilComplete;
  end;

implementation

type
  // a distinct class so the test can check ErrorClass capture
  EbpTasksTestError = class(Exception);

{ TBpTasksTests }

procedure TBpTasksTests.SetUp;
begin
  inherited;
  FWorkRan := False;
  FWorkExited := False;
  FCompleteCount := 0;
  FErrorCount := 0;
  FLastErrorMessage := '';
  FStateInComplete := tskPending;
end;

procedure TBpTasksTests.WorkQuick(aSender: TObject; aToken: TbpTaskToken);
begin
  FWorkRan := True;
end;

procedure TBpTasksTests.WorkRaise(aSender: TObject; aToken: TbpTaskToken);
begin
  FWorkRan := True;
  raise EbpTasksTestError.Create('boom');
end;

procedure TBpTasksTests.WorkLoopUntilCancelled(aSender: TObject;
  aToken: TbpTaskToken);
var
  lvDeadline: Cardinal;
begin
  FWorkRan := True;
  // cooperative worker: polls the token, gives up after 10 s so a broken
  // cancel cannot hang the suite
  lvDeadline := GetTickCount + 10000;
  while not aToken.IsCancellationRequested and (GetTickCount < lvDeadline) do
    Sleep(10);
  FWorkExited := True;
end;

procedure TBpTasksTests.HandleComplete(aSender: TObject);
begin
  Inc(FCompleteCount);
  FStateInComplete := TbpTask(aSender).State;
end;

procedure TBpTasksTests.HandleError(aSender: TObject;
  const aErrorMessage: string);
begin
  Inc(FErrorCount);
  FLastErrorMessage := aErrorMessage;
end;

// polls a worker-written flag from this thread; True when it turned on in time
function TBpTasksTests.WaitForFlag(var aFlag: Boolean;
  aTimeoutMs: Cardinal): Boolean;
var
  lvDeadline: Cardinal;
begin
  lvDeadline := GetTickCount + aTimeoutMs;
  while not aFlag and (GetTickCount < lvDeadline) do
    Sleep(10);
  Result := aFlag;
end;

procedure TBpTasksTests.TestTokenCancelIsSticky;
var
  lvToken: TbpTaskToken;
begin
  lvToken := TbpTaskToken.Create;
  try
    CheckFalse(lvToken.IsCancellationRequested, 'fresh token is not cancelled');
    lvToken.Cancel;
    CheckTrue(lvToken.IsCancellationRequested);
    // a second cancel is a no-op, not an error
    lvToken.Cancel;
    CheckTrue(lvToken.IsCancellationRequested);
  finally
    lvToken.Free;
  end;
end;

procedure TBpTasksTests.TestInitialState;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    Check(lvTask.State = tskPending, 'fresh task is pending');
    CheckFalse(lvTask.IsFinished);
    CheckFalse(lvTask.WaitFor(0), 'a never-started task has not finished');
    CheckFalse(lvTask.MarshalToMainThread);
    CheckEquals('', lvTask.ErrorMessage);
    CheckEquals('', lvTask.ErrorClass);
    Check(lvTask.Token <> nil, 'token exists from creation');
    CheckFalse(lvTask.Token.IsCancellationRequested);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestWorkRunsAndSucceeds;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkQuick;
    lvTask.OnComplete := HandleComplete;
    lvTask.OnError := HandleError;
    lvTask.Start;
    Check(lvTask.State in [tskRunning, tskSucceeded], 'started task runs');
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskSucceeded, 'expected success, got: ' +
      lvTask.ErrorMessage);
    CheckTrue(lvTask.IsFinished);
    CheckTrue(FWorkRan, 'the work must actually run');
    CheckEquals('', lvTask.ErrorMessage);
    CheckEquals('', lvTask.ErrorClass);
    CheckEquals(1, FCompleteCount, 'OnComplete fires on success');
    Check(FStateInComplete = tskSucceeded, 'state is terminal inside OnComplete');
    CheckEquals(0, FErrorCount, 'OnError must not fire on success');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestExceptionMapsToFailed;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkRaise;
    lvTask.OnComplete := HandleComplete;
    lvTask.OnError := HandleError;
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskFailed, 'an exception in the work fails the task');
    CheckEquals('boom', lvTask.ErrorMessage, 'exception message captured');
    CheckEquals('EbpTasksTestError', lvTask.ErrorClass, 'exception class captured');
    CheckEquals(1, FErrorCount, 'OnError fires on failure');
    CheckEquals('boom', FLastErrorMessage);
    CheckEquals(1, FCompleteCount, 'OnComplete fires on every terminal state');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestCancelBeforeStart;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkQuick;
    lvTask.OnComplete := HandleComplete;
    lvTask.OnError := HandleError;
    lvTask.Cancel;
    // the pre-cancelled token stops the worker before the work runs
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskCancelled, 'cancel before start wins');
    CheckFalse(FWorkRan, 'the work must never run');
    CheckEquals(1, FCompleteCount, 'OnComplete fires on cancellation too');
    CheckEquals(0, FErrorCount, 'cancellation is not an error');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestCancelDuringRun;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkLoopUntilCancelled;
    lvTask.OnComplete := HandleComplete;
    lvTask.Start;
    CheckTrue(WaitForFlag(FWorkRan, 5000), 'the work must start');
    lvTask.Cancel;
    CheckTrue(lvTask.WaitFor(5000), 'cancel must unwind promptly');
    Check(lvTask.State = tskCancelled, 'cancel during run leads to cancelled');
    CheckTrue(FWorkExited, 'the work observed the token and returned');
    CheckEquals(1, FCompleteCount);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestWaitForJoins;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkLoopUntilCancelled;
    lvTask.Start;
    CheckTrue(WaitForFlag(FWorkRan, 5000), 'the work must start');
    CheckFalse(lvTask.WaitFor(50), 'WaitFor times out while the work runs');
    lvTask.Cancel;
    CheckTrue(lvTask.WaitFor(5000), 'WaitFor joins once the work returns');
    CheckTrue(lvTask.IsFinished);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestOnCompleteFiresExactlyOnce;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkQuick;
    lvTask.OnComplete := HandleComplete;
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    // the join guarantees the direct-mode event already fired; a short
    // grace period would catch an erroneous second notification
    Sleep(50);
    CheckEquals(1, FCompleteCount, 'OnComplete fires exactly once');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestDestroyRunningTaskCancelsAndJoins;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  lvTask.Work := WorkLoopUntilCancelled;
  lvTask.Start;
  CheckTrue(WaitForFlag(FWorkRan, 5000), 'the work must start');
  // the destructor cancels the token and joins the worker; afterwards the
  // work must have seen the cancel and returned on its own
  lvTask.Free;
  CheckTrue(FWorkExited, 'destructor waited for the cooperative exit');
end;

procedure TBpTasksTests.TestDoubleStartRaises;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkLoopUntilCancelled;
    lvTask.Start;
    try
      lvTask.Start;
      Fail('expected raise: task already running');
    except
      on EbpTask do ;
    end;
    lvTask.Cancel;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    // one-shot: a finished task refuses a restart too
    try
      lvTask.Start;
      Fail('expected raise: task already finished');
    except
      on EbpTask do ;
    end;
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestStartWithoutWorkRaises;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    try
      lvTask.Start;
      Fail('expected raise: no Work assigned');
    except
      on EbpTask do ;
    end;
    Check(lvTask.State = tskPending, 'failed validation must not change state');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestRunAsyncFactory;
var
  lvTask: TbpTask;
begin
  // hot task: created, wired and already started
  lvTask := BpRunAsync(WorkQuick, HandleComplete, False);
  try
    Check(lvTask.State in [tskRunning, tskSucceeded],
      'factory returns a started task');
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskSucceeded, 'expected success, got: ' +
      lvTask.ErrorMessage);
    CheckTrue(FWorkRan);
    CheckEquals(1, FCompleteCount);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestRunAsyncWithNilComplete;
var
  lvTask: TbpTask;
begin
  // nil for the completion event must compile and run (the factory is a
  // single name, not an overload, exactly because of the D7/2007 E2250 trap)
  lvTask := BpRunAsync(WorkQuick, nil, False);
  try
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskSucceeded);
    CheckTrue(FWorkRan);
  finally
    lvTask.Free;
  end;
end;

initialization
  RegisterTest(TBpTasksTests.Suite);

end.
