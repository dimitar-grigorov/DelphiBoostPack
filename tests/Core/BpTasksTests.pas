unit BpTasksTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpTasks, BpTestSupport;

type
  // all offline; marshalled tests pump the queue themselves
  TBpTasksTests = class(TTestCase)
  private
    FWorkRan: Boolean;
    FWorkExited: Boolean;
    FCompleteCount: Integer;
    FErrorCount: Integer;
    FLastErrorMessage: string;
    FStateInComplete: TbpTaskState;
    FCompleteThreadId: Cardinal;
    FErrorBeforeComplete: Boolean;
    FFreedInHandler: Boolean;
    FInHandler: Boolean;
    FHandlerDone: Boolean;
    FWorkerIdSeen: Cardinal;
    FWorkerIdActual: Cardinal;
    procedure WorkQuick(aSender: TObject; aToken: TbpCancellationToken);
    procedure WorkRaise(aSender: TObject; aToken: TbpCancellationToken);
    procedure WorkLoopUntilCancelled(aSender: TObject; aToken: TbpCancellationToken);
    procedure WorkRecordThreadId(aSender: TObject; aToken: TbpCancellationToken);
    procedure HandleComplete(aSender: TObject);
    procedure HandleError(aSender: TObject; const aErrorMessage: string);
    procedure HandleCompleteAndFree(aSender: TObject);
    procedure HandleErrorAndFree(aSender: TObject; const aErrorMessage: string);
    procedure HandleCompleteSlow(aSender: TObject);
    procedure HandleCompleteRaise(aSender: TObject);
    function WaitForFlag(var aFlag: Boolean; aTimeoutMs: Cardinal): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTokenCancelIsSticky;
    procedure TestInitialState;
    procedure TestWorkRunsAndSucceeds;
    procedure TestExceptionMapsToFailed;
    procedure TestCancelBeforeStart;
    procedure TestCancelDuringRun;
    procedure TestWaitForJoins;
    procedure TestOnCompleteFiresExactlyOnce;
    procedure TestDestroyRunningTaskCancelsAndFiresNothing;
    procedure TestDoubleStartRaises;
    procedure TestStartWithoutWorkRaises;
    procedure TestRunAsyncFactory;
    procedure TestRunAsyncWithNilComplete;
    procedure TestWorkerThreadIdKnownBeforeWorkRuns;
    procedure TestFailedThreadCreationLeavesTaskPending;
    procedure TestFreeFromInsideOwnCompleteDirect;
    procedure TestFreeFromInsideOwnErrorSkipsComplete;
    procedure TestHandlerExceptionReachesHookDirect;
    procedure TestMarshalledCompleteArrivesOnMainThread;
    procedure TestMarshalledErrorPrecedesComplete;
    procedure TestMarshalledFreeBeforePumpDropsCompletion;
    procedure TestMarshalledFreeFromInsideOwnComplete;
    procedure TestMarshalledTasksFromWorkerThreadsCompleteOnMainThread;
    procedure TestMarshalledFreeFromForeignThread;
    procedure TestMarshalledFreeFromForeignThreadWaitsForHandler;
    procedure TestHandlerExceptionReachesHookMarshalled;
  end;

implementation

type
  // distinct class to check ErrorClass capture
  EbpTasksTestError = class(Exception);

  // fails Start a given number of times
  TbpFailingStartTask = class(TbpTask)
  private
    FFailuresLeft: Integer;
  protected
    function CreateWorkerThread: TThread; override;
  end;

  // frees a task from a third thread once aGo turns on
  TForeignFreeThread = class(TThread)
  private
    FTask: TbpTask;
    FGo: PBoolean;
    FDone: PBoolean;
    FDoneWhenFreed: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(aTask: TbpTask; aGo, aDone: PBoolean);
    property DoneWhenFreed: Boolean read FDoneWhenFreed;
  end;

  TbpTaskArray = array of TbpTask;

  // starts marshalled tasks on a worker thread
  TTaskCreatorThread = class(TThread)
  private
    FWork: TbpTaskWorkEvent;
    FOnComplete: TbpTaskCompleteEvent;
    FTasks: TbpTaskArray;
  protected
    procedure Execute; override;
  public
    constructor Create(aCount: Integer; aWork: TbpTaskWorkEvent;
      aOnComplete: TbpTaskCompleteEvent);
    property Tasks: TbpTaskArray read FTasks;
  end;

var
  gvHookCount: Integer;
  gvHookTask: TbpTask;
  gvHookMessage: string;
  gvHookThreadId: Cardinal;

procedure TestExceptionHook(aTask: TbpTask; aException: Exception);
begin
  Inc(gvHookCount);
  gvHookTask := aTask;
  gvHookMessage := aException.Message;
  gvHookThreadId := GetCurrentThreadId;
end;

{ TbpFailingStartTask }

function TbpFailingStartTask.CreateWorkerThread: TThread;
begin
  if FFailuresLeft > 0 then
  begin
    Dec(FFailuresLeft);
    raise EbpTasksTestError.Create('no thread for you');
  end;
  Result := inherited CreateWorkerThread;
end;

{ TForeignFreeThread }

constructor TForeignFreeThread.Create(aTask: TbpTask; aGo, aDone: PBoolean);
begin
  FTask := aTask;
  FGo := aGo;
  FDone := aDone;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TForeignFreeThread.Execute;
begin
  while not FGo^ do
    Sleep(1);
  FTask.Free;
  FDoneWhenFreed := FDone^;
end;

{ TTaskCreatorThread }

constructor TTaskCreatorThread.Create(aCount: Integer;
  aWork: TbpTaskWorkEvent; aOnComplete: TbpTaskCompleteEvent);
begin
  SetLength(FTasks, aCount);
  FWork := aWork;
  FOnComplete := aOnComplete;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TTaskCreatorThread.Execute;
var
  i: Integer;
begin
  for i := 0 to High(FTasks) do
    FTasks[i] := BpRunAsync(FWork, FOnComplete);
end;

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
  FCompleteThreadId := 0;
  FErrorBeforeComplete := False;
  FFreedInHandler := False;
  FInHandler := False;
  FHandlerDone := False;
  FWorkerIdSeen := 0;
  FWorkerIdActual := 0;
  gvHookCount := 0;
  gvHookTask := nil;
  gvHookMessage := '';
  gvHookThreadId := 0;
end;

procedure TBpTasksTests.TearDown;
begin
  BpSetTaskExceptionHook(nil);
  // no stray completion for the next test
  BpPumpMessages;
  inherited;
end;

procedure TBpTasksTests.WorkQuick(aSender: TObject; aToken: TbpCancellationToken);
begin
  FWorkRan := True;
end;

procedure TBpTasksTests.WorkRaise(aSender: TObject; aToken: TbpCancellationToken);
begin
  FWorkRan := True;
  raise EbpTasksTestError.Create('boom');
end;

procedure TBpTasksTests.WorkLoopUntilCancelled(aSender: TObject;
  aToken: TbpCancellationToken);
var
  lvDeadline: Cardinal;
begin
  FWorkRan := True;
  // gives up after 10 s so a broken cancel cannot hang the suite
  lvDeadline := GetTickCount + 10000;
  while not aToken.IsCancellationRequested and (GetTickCount < lvDeadline) do
    Sleep(10);
  FWorkExited := True;
end;

procedure TBpTasksTests.WorkRecordThreadId(aSender: TObject;
  aToken: TbpCancellationToken);
begin
  FWorkerIdSeen := TbpTask(aSender).WorkerThreadId;
  FWorkerIdActual := GetCurrentThreadId;
  FWorkRan := True;
end;

procedure TBpTasksTests.HandleComplete(aSender: TObject);
begin
  Inc(FCompleteCount);
  FStateInComplete := TbpTask(aSender).State;
  FCompleteThreadId := GetCurrentThreadId;
end;

procedure TBpTasksTests.HandleError(aSender: TObject;
  const aErrorMessage: string);
begin
  Inc(FErrorCount);
  FLastErrorMessage := aErrorMessage;
  FErrorBeforeComplete := FCompleteCount = 0;
end;

procedure TBpTasksTests.HandleCompleteAndFree(aSender: TObject);
begin
  Inc(FCompleteCount);
  aSender.Free;
  // set after Free returned
  FFreedInHandler := True;
end;

procedure TBpTasksTests.HandleErrorAndFree(aSender: TObject;
  const aErrorMessage: string);
begin
  Inc(FErrorCount);
  aSender.Free;
  FFreedInHandler := True;
end;

procedure TBpTasksTests.HandleCompleteSlow(aSender: TObject);
begin
  FInHandler := True;
  Sleep(200);
  Inc(FCompleteCount);
  FHandlerDone := True;
end;

procedure TBpTasksTests.HandleCompleteRaise(aSender: TObject);
begin
  Inc(FCompleteCount);
  raise EbpTasksTestError.Create('handler boom');
end;

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
  lvToken: TbpCancellationToken;
begin
  lvToken := TbpCancellationToken.Create;
  try
    CheckFalse(lvToken.IsCancellationRequested, 'fresh token is not cancelled');
    lvToken.Cancel;
    CheckTrue(lvToken.IsCancellationRequested);
    // a second cancel is a no-op
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
    Check(lvTask.WorkerThreadId = 0, 'no worker before Start');
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
    Check(FCompleteThreadId <> GetCurrentThreadId,
      'direct mode fires on the worker');
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
    CheckTrue(FErrorBeforeComplete, 'OnError precedes OnComplete');
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
    // a grace period would catch a second notification
    Sleep(50);
    CheckEquals(1, FCompleteCount, 'OnComplete fires exactly once');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestDestroyRunningTaskCancelsAndFiresNothing;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  lvTask.Work := WorkLoopUntilCancelled;
  lvTask.OnComplete := HandleComplete;
  lvTask.Start;
  CheckTrue(WaitForFlag(FWorkRan, 5000), 'the work must start');
  lvTask.Free;
  CheckTrue(FWorkExited, 'destructor waited for the cooperative exit');
  // the owner is usually tearing itself down here
  CheckEquals(0, FCompleteCount, 'no OnComplete after Free');
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
    // a finished task refuses a restart too
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
  // nil must compile: the factory is no overload because of D7/2007 E2250
  lvTask := BpRunAsync(WorkQuick, nil, False);
  try
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskSucceeded);
    CheckTrue(FWorkRan);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestWorkerThreadIdKnownBeforeWorkRuns;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkRecordThreadId;
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    CheckTrue(FWorkRan);
    Check(FWorkerIdSeen <> 0, 'WorkerThreadId is set when Work begins');
    Check(FWorkerIdSeen = FWorkerIdActual, 'and it is the worker itself');
    Check(lvTask.WorkerThreadId = FWorkerIdActual,
      'it stays readable after the join');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestFailedThreadCreationLeavesTaskPending;
var
  lvTask: TbpFailingStartTask;
begin
  lvTask := TbpFailingStartTask.Create(False);
  try
    lvTask.FFailuresLeft := 1;
    lvTask.Work := WorkQuick;
    lvTask.OnComplete := HandleComplete;
    try
      lvTask.Start;
      Fail('expected raise: the worker could not be created');
    except
      on EbpTasksTestError do ;
    end;
    Check(lvTask.State = tskPending, 'a failed Start leaves the task pending');
    Check(lvTask.WorkerThreadId = 0);
    CheckFalse(lvTask.WaitFor(0));
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskSucceeded);
    CheckEquals(1, FCompleteCount);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestFreeFromInsideOwnCompleteDirect;
var
  lvTask: TbpTask;
begin
  // the old code self-joined here
  lvTask := TbpTask.Create(False);
  lvTask.Work := WorkQuick;
  lvTask.OnComplete := HandleCompleteAndFree;
  lvTask.Start;
  CheckTrue(WaitForFlag(FFreedInHandler, 5000),
    'Free from inside OnComplete must return, not deadlock');
  CheckEquals(1, FCompleteCount);
  // the worker frees itself
  Sleep(50);
end;

procedure TBpTasksTests.TestFreeFromInsideOwnErrorSkipsComplete;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create(False);
  lvTask.Work := WorkRaise;
  lvTask.OnError := HandleErrorAndFree;
  lvTask.OnComplete := HandleComplete;
  lvTask.Start;
  CheckTrue(WaitForFlag(FFreedInHandler, 5000),
    'Free from inside OnError must return, not deadlock');
  Sleep(50);
  CheckEquals(1, FErrorCount);
  CheckEquals(0, FCompleteCount, 'no OnComplete after the handler freed the task');
end;

procedure TBpTasksTests.TestHandlerExceptionReachesHookDirect;
var
  lvTask: TbpTask;
begin
  BpSetTaskExceptionHook(TestExceptionHook);
  lvTask := TbpTask.Create(False);
  try
    lvTask.Work := WorkQuick;
    lvTask.OnComplete := HandleCompleteRaise;
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    CheckEquals(1, FCompleteCount);
    // reported instead of dying in TThread.FatalException
    CheckEquals(1, gvHookCount, 'the hook saw the handler exception');
    CheckEquals('handler boom', gvHookMessage);
    Check(gvHookTask = lvTask, 'the hook receives the task');
    Check(gvHookThreadId = lvTask.WorkerThreadId, 'reported on the worker');
    Check(lvTask.State = tskSucceeded, 'a handler failure does not fail the work');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestMarshalledCompleteArrivesOnMainThread;
var
  lvTask: TbpTask;
begin
  lvTask := TbpTask.Create;
  try
    CheckTrue(lvTask.MarshalToMainThread, 'marshalling is the default');
    lvTask.Work := WorkQuick;
    lvTask.OnComplete := HandleComplete;
    lvTask.OnError := HandleError;
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = tskSucceeded);
    Sleep(20);
    CheckEquals(0, FCompleteCount, 'nothing fires until the queue is pumped');
    CheckTrue(BpPumpUntilCount(FCompleteCount, 1, 5000),
      'OnComplete arrives through the message queue');
    Check(FCompleteThreadId = GetCurrentThreadId,
      'and runs on the pumping (main) thread');
    Check(FStateInComplete = tskSucceeded);
    CheckEquals(0, FErrorCount);
    BpPumpFor(50);
    CheckEquals(1, FCompleteCount, 'exactly once');
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestMarshalledErrorPrecedesComplete;
var
  lvTask: TbpTask;
begin
  lvTask := BpRunAsync(WorkRaise, HandleComplete);
  try
    lvTask.OnError := HandleError;
    CheckTrue(BpPumpUntilCount(FCompleteCount, 1, 5000));
    CheckEquals(1, FErrorCount, 'OnError fires on failure');
    CheckEquals('boom', FLastErrorMessage);
    CheckTrue(FErrorBeforeComplete, 'OnError precedes OnComplete');
    Check(FStateInComplete = tskFailed);
    Check(FCompleteThreadId = GetCurrentThreadId);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestMarshalledFreeBeforePumpDropsCompletion;
var
  lvTask: TbpTask;
begin
  lvTask := BpRunAsync(WorkQuick, HandleComplete);
  CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
  // queued but not dispatched
  lvTask.Free;
  BpPumpFor(100);
  CheckEquals(0, FCompleteCount, 'a completion posted before Free is dropped');

  // a new task must not inherit the stale completion
  lvTask := BpRunAsync(WorkLoopUntilCancelled, HandleComplete);
  try
    CheckTrue(WaitForFlag(FWorkRan, 5000));
    BpPumpFor(100);
    CheckEquals(0, FCompleteCount, 'the new task fires nothing while running');
    lvTask.Cancel;
    CheckTrue(lvTask.WaitFor(5000));
    CheckTrue(BpPumpUntilCount(FCompleteCount, 1, 5000), 'its own completion arrives');
    Check(FStateInComplete = tskCancelled);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestMarshalledFreeFromInsideOwnComplete;
begin
  BpRunAsync(WorkQuick, HandleCompleteAndFree);
  CheckTrue(BpPumpUntilFlag(FFreedInHandler, 5000), 'the handler ran and freed');
  CheckEquals(1, FCompleteCount);
  BpPumpFor(50);
  CheckEquals(1, FCompleteCount, 'nothing fires twice');
end;

procedure TBpTasksTests.TestMarshalledTasksFromWorkerThreadsCompleteOnMainThread;
const
  gcThreads = 4;
  gcPerThread = 5;
var
  lvCreators: array[0..gcThreads - 1] of TTaskCreatorThread;
  i, j: Integer;
  lvTask: TbpTask;
begin
  // concurrent creation used to race AllocateHWnd
  for i := 0 to gcThreads - 1 do
    lvCreators[i] := TTaskCreatorThread.Create(gcPerThread, WorkQuick,
      HandleComplete);
  try
    for i := 0 to gcThreads - 1 do
      lvCreators[i].WaitFor;
    CheckTrue(BpPumpUntilCount(FCompleteCount, gcThreads * gcPerThread, 5000),
      'every task completes, got ' + IntToStr(FCompleteCount));
    Check(FCompleteThreadId = GetCurrentThreadId,
      'events run on the main thread, whoever created the task');
    for i := 0 to gcThreads - 1 do
      for j := 0 to gcPerThread - 1 do
      begin
        lvTask := lvCreators[i].Tasks[j];
        Check(lvTask <> nil, 'creator stored its task');
        Check(lvTask.State = tskSucceeded, 'every task succeeded');
        Check(lvTask.WorkerThreadId <> GetCurrentThreadId);
      end;
    BpPumpFor(50);
    CheckEquals(gcThreads * gcPerThread, FCompleteCount, 'each exactly once');
  finally
    // any thread may free
    for i := 0 to gcThreads - 1 do
    begin
      for j := 0 to gcPerThread - 1 do
        lvCreators[i].Tasks[j].Free;
      lvCreators[i].Free;
    end;
  end;
end;

procedure TBpTasksTests.TestMarshalledFreeFromForeignThread;
var
  lvTask: TbpTask;
  lvFreer: TForeignFreeThread;
  lvGo: Boolean;
begin
  // the old per-task window leaked here and its thunk hit the next task
  lvTask := BpRunAsync(WorkQuick, HandleComplete);
  CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
  lvGo := True;
  lvFreer := TForeignFreeThread.Create(lvTask, @lvGo, @FHandlerDone);
  try
    lvFreer.WaitFor;
  finally
    lvFreer.Free;
  end;
  BpPumpFor(100);
  CheckEquals(0, FCompleteCount, 'the queued completion is dropped');

  lvTask := BpRunAsync(WorkLoopUntilCancelled, HandleComplete);
  try
    CheckTrue(WaitForFlag(FWorkRan, 5000));
    BpPumpFor(100);
    CheckEquals(0, FCompleteCount, 'no stray event while it runs');
    lvTask.Cancel;
    CheckTrue(lvTask.WaitFor(5000));
    CheckTrue(BpPumpUntilCount(FCompleteCount, 1, 5000));
    Check(FStateInComplete = tskCancelled);
  finally
    lvTask.Free;
  end;
end;

procedure TBpTasksTests.TestMarshalledFreeFromForeignThreadWaitsForHandler;
var
  lvTask: TbpTask;
  lvFreer: TForeignFreeThread;
begin
  // Free must wait for the handler running here
  lvTask := BpRunAsync(WorkQuick, HandleCompleteSlow);
  lvFreer := TForeignFreeThread.Create(lvTask, @FInHandler, @FHandlerDone);
  try
    CheckTrue(BpPumpUntilFlag(FHandlerDone, 5000), 'the slow handler ran');
    lvFreer.WaitFor;
    CheckTrue(lvFreer.DoneWhenFreed,
      'Free returned only after the running handler finished');
  finally
    lvFreer.Free;
  end;
  CheckEquals(1, FCompleteCount);
end;

procedure TBpTasksTests.TestHandlerExceptionReachesHookMarshalled;
var
  lvTask: TbpTask;
begin
  BpSetTaskExceptionHook(TestExceptionHook);
  lvTask := BpRunAsync(WorkQuick, HandleCompleteRaise);
  try
    // not thrown through the window procedure
    CheckTrue(BpPumpUntilCount(gvHookCount, 1, 5000), 'the hook saw the exception');
    CheckEquals('handler boom', gvHookMessage);
    Check(gvHookTask = lvTask);
    Check(gvHookThreadId = GetCurrentThreadId, 'reported on the main thread');
    CheckEquals(1, FCompleteCount);
  finally
    lvTask.Free;
  end;
end;

initialization
  RegisterTest(TBpTasksTests.Suite);

end.
