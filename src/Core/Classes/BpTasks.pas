unit BpTasks;

// Background tasks for Delphi 7/2007+: run a method on a worker thread,
// get completion events on the main thread, cancel cooperatively.
// Self-contained; one thread per task, no pool.
//
//   FTask := BpRunAsync(DoWork, HandleDone);  // DoWork polls aToken
//   FTask.Cancel;  // or FTask.Free: cancels, joins, cleans up
//
// Rules
// - Any thread may create or free a task.
// - Default: events run on the main thread (the one that loaded the module),
//   which must pump messages. Create(False): events run on the worker.
// - Free cancels and joins. After Free is entered no event starts; a running
//   handler finishes first. A handler may free its own task.
// - A handler exception goes to BpSetTaskExceptionHook, else to
//   ApplicationHandleException on the main thread, else to ShowException.

interface

uses
  Classes, SysUtils, Windows, Messages;

type
  EbpTask = class(Exception);

  // thread-safe, one-shot
  TbpTaskToken = class
  private
    FCancelled: Integer;
  public
    procedure Cancel;
    function IsCancellationRequested: Boolean;
  end;

  TbpTaskState = (tskPending, tskRunning, tskSucceeded, tskFailed,
    tskCancelled);

  // poll aToken and return early to honour a cancel
  TbpTaskWorkEvent = procedure(aSender: TObject;
    aToken: TbpTaskToken) of object;
  TbpTaskCompleteEvent = procedure(aSender: TObject) of object;
  TbpTaskErrorEvent = procedure(aSender: TObject;
    const aErrorMessage: string) of object;

  // one-shot, C# Task style
  TbpTask = class
  private
    FId: Cardinal;               // registry key, never reused in a process
    FToken: TbpTaskToken;        // owned
    FThread: TThread;            // owned worker, joined in Destroy
    FLock: TRTLCriticalSection;  // guards state, results and FThread
    FMarshalToMainThread: Boolean;
    FState: TbpTaskState;
    FErrorMessage: string;
    FErrorClass: string;
    FWork: TbpTaskWorkEvent;
    FOnComplete: TbpTaskCompleteEvent;
    FOnError: TbpTaskErrorEvent;
    function GetState: TbpTaskState;
    function GetErrorMessage: string;
    function GetErrorClass: string;
    function GetWorkerThreadId: Cardinal;
    procedure RunWork;  // worker thread body
  protected
    // a raise here leaves the task pending
    function CreateWorkerThread: TThread; virtual;
  public
    constructor Create(aMarshalToMainThread: Boolean = True);
    // cancels and joins
    destructor Destroy; override;

    // raises when already started or Work is unassigned
    procedure Start;
    // safe from any thread, also before Start
    procedure Cancel;
    // waits for the work, not for the events
    function WaitFor(aTimeoutMs: DWORD = INFINITE): Boolean;
    function IsFinished: Boolean;

    // configure before Start
    property Work: TbpTaskWorkEvent read FWork write FWork;
    property Token: TbpTaskToken read FToken;
    property MarshalToMainThread: Boolean read FMarshalToMainThread;
    // 0 before Start
    property WorkerThreadId: Cardinal read GetWorkerThreadId;

    // thread-safe results; authoritative once IsFinished
    property State: TbpTaskState read GetState;
    property ErrorMessage: string read GetErrorMessage;
    property ErrorClass: string read GetErrorClass;  // '' when no exception

    // OnComplete fires on every terminal state, OnError before it on tskFailed
    property OnComplete: TbpTaskCompleteEvent read FOnComplete write FOnComplete;
    property OnError: TbpTaskErrorEvent read FOnError write FOnError;
  end;

  // aTask is nil when the handler freed it
  TbpTaskExceptionProc = procedure(aTask: TbpTask; aException: Exception);

// create, wire and start; the caller frees
// (no overloads: old compilers reject nil events on overloads)
function BpRunAsync(aWork: TbpTaskWorkEvent;
  aOnComplete: TbpTaskCompleteEvent = nil;
  aMarshalToMainThread: Boolean = True): TbpTask;

// nil restores the default
procedure BpSetTaskExceptionHook(aProc: TbpTaskExceptionProc);

implementation

const
  gcWmTaskDone = WM_APP + 1;
  gcDispatcherClass = 'TbpTaskDispatcher';

type
  // DispatchThread: 0 when no event is running
  TbpTaskEntry = record
    Id: Cardinal;
    Task: TbpTask;
    DispatchThread: DWORD;
  end;

var
  gvLock: TRTLCriticalSection;  // guards the registry below
  gvEntries: array of TbpTaskEntry;
  gvCount: Integer;
  gvNextId: Cardinal;
  gvWnd: HWND;                  // the dispatcher window, 0 when it failed
  gvWndThreadId: DWORD;
  gvExceptionHook: TbpTaskExceptionProc;

{ task registry: decides whether a completion may still reach its task }

// caller holds gvLock
function FindEntry(aId: Cardinal): Integer;
var
  i: Integer;
begin
  for i := 0 to gvCount - 1 do
    if gvEntries[i].Id = aId then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
end;

function RegisterTask(aTask: TbpTask): Cardinal;
begin
  EnterCriticalSection(gvLock);
  try
    Inc(gvNextId);
    if gvCount = Length(gvEntries) then
      SetLength(gvEntries, gvCount * 2 + 4);
    gvEntries[gvCount].Id := gvNextId;
    gvEntries[gvCount].Task := aTask;
    gvEntries[gvCount].DispatchThread := 0;
    Inc(gvCount);
    Result := gvNextId;
  finally
    LeaveCriticalSection(gvLock);
  end;
end;

// waits for a handler on a third thread; the own worker is joined anyway
procedure UnregisterTask(aId: Cardinal; aWorkerThreadId: DWORD);
var
  i: Integer;
  lvBusy: Boolean;
begin
  repeat
    EnterCriticalSection(gvLock);
    try
      i := FindEntry(aId);
      lvBusy := (i >= 0) and (gvEntries[i].DispatchThread <> 0) and
        (gvEntries[i].DispatchThread <> GetCurrentThreadId) and
        (gvEntries[i].DispatchThread <> aWorkerThreadId);
      if (i >= 0) and not lvBusy then
      begin
        Dec(gvCount);
        gvEntries[i] := gvEntries[gvCount];
        gvEntries[gvCount].Task := nil;
      end;
    finally
      LeaveCriticalSection(gvLock);
    end;
    if lvBusy then
      Sleep(1);
  until not lvBusy;
end;

// False once Free was entered
function BeginDispatch(aId: Cardinal; aTask: TbpTask): Boolean;
var
  i: Integer;
begin
  EnterCriticalSection(gvLock);
  try
    i := FindEntry(aId);
    Result := (i >= 0) and (gvEntries[i].Task = aTask);
    if Result then
      gvEntries[i].DispatchThread := GetCurrentThreadId;
  finally
    LeaveCriticalSection(gvLock);
  end;
end;

function IsRegistered(aId: Cardinal): Boolean;
begin
  EnterCriticalSection(gvLock);
  try
    Result := FindEntry(aId) >= 0;
  finally
    LeaveCriticalSection(gvLock);
  end;
end;

procedure EndDispatch(aId: Cardinal);
var
  i: Integer;
begin
  EnterCriticalSection(gvLock);
  try
    i := FindEntry(aId);
    if i >= 0 then
      gvEntries[i].DispatchThread := 0;
  finally
    LeaveCriticalSection(gvLock);
  end;
end;

// nil when the handler freed the task
function LiveTask(aId: Cardinal; aTask: TbpTask): TbpTask;
begin
  if IsRegistered(aId) then
    Result := aTask
  else
    Result := nil;
end;

// ApplicationHandleException reads ExceptObject, so call inside except
procedure ReportHandlerException(aTask: TbpTask; aException: Exception);
begin
  if Assigned(gvExceptionHook) then
    gvExceptionHook(aTask, aException)
  // a VCL handler expects the main thread
  else if (GetCurrentThreadId = gvWndThreadId) and
    Assigned(Classes.ApplicationHandleException) then
    Classes.ApplicationHandleException(aTask)
  else
    SysUtils.ShowException(aException, ExceptAddr);
end;

procedure RunEvents(aTask: TbpTask; aId: Cardinal);
var
  lvOnError: TbpTaskErrorEvent;
  lvOnComplete: TbpTaskCompleteEvent;
  lvFailed: Boolean;
  lvMessage: string;
begin
  if not BeginDispatch(aId, aTask) then
    Exit;
  try
    // a handler may free the task
    lvOnError := aTask.FOnError;
    lvOnComplete := aTask.FOnComplete;
    lvFailed := aTask.GetState = tskFailed;
    lvMessage := aTask.GetErrorMessage;
    if lvFailed and Assigned(lvOnError) then
      try
        lvOnError(aTask, lvMessage);
      except
        on E: Exception do
          ReportHandlerException(LiveTask(aId, aTask), E);
      end;
    if Assigned(lvOnComplete) and IsRegistered(aId) then
      try
        lvOnComplete(aTask);
      except
        on E: Exception do
          ReportHandlerException(LiveTask(aId, aTask), E);
      end;
  finally
    EndDispatch(aId);
  end;
end;

{ dispatcher window: one per module, owned by the thread that loaded it }

function DispatcherWndProc(aWnd: HWND; aMsg: UINT; aWParam: WPARAM;
  aLParam: LPARAM): LRESULT; stdcall;
begin
  if aMsg = gcWmTaskDone then
  begin
    RunEvents(TbpTask(aLParam), Cardinal(aWParam));
    Result := 0;
  end
  else
    Result := DefWindowProc(aWnd, aMsg, aWParam, aLParam);
end;

procedure CreateDispatcher;
var
  lvClass, lvExisting: TWndClass;
begin
  FillChar(lvClass, SizeOf(lvClass), 0);
  lvClass.lpfnWndProc := @DispatcherWndProc;
  lvClass.hInstance := HInstance;
  lvClass.lpszClassName := gcDispatcherClass;
  // a stale registration points at dead code
  if not GetClassInfo(HInstance, gcDispatcherClass, lvExisting) or
    (lvExisting.lpfnWndProc <> @DispatcherWndProc) then
  begin
    Windows.UnregisterClass(gcDispatcherClass, HInstance);
    Windows.RegisterClass(lvClass);
  end;
  gvWnd := CreateWindowEx(0, gcDispatcherClass, '', 0, 0, 0, 0, 0,
    HWND(HWND_MESSAGE), 0, HInstance, nil);
  if gvWnd <> 0 then
    gvWndThreadId := GetCurrentThreadId;
end;

procedure DestroyDispatcher;
begin
  if gvWnd <> 0 then
    DestroyWindow(gvWnd);
  gvWnd := 0;
  Windows.UnregisterClass(gcDispatcherClass, HInstance);
end;

{ TbpTaskToken }

procedure TbpTaskToken.Cancel;
begin
  InterlockedExchange(FCancelled, 1);
end;

function TbpTaskToken.IsCancellationRequested: Boolean;
begin
  // aligned 32-bit read is atomic
  Result := FCancelled <> 0;
end;

{ TbpTask }

type
  TbpTaskThread = class(TThread)
  private
    FTask: TbpTask;
  protected
    procedure Execute; override;
  public
    constructor Create(aTask: TbpTask);
  end;

constructor TbpTaskThread.Create(aTask: TbpTask);
begin
  FTask := aTask;
  FreeOnTerminate := False;  // the task owns and joins the thread
  inherited Create(False);
end;

procedure TbpTaskThread.Execute;
begin
  FTask.RunWork;
end;

constructor TbpTask.Create(aMarshalToMainThread: Boolean);
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  if aMarshalToMainThread and (gvWnd = 0) then
    raise EbpTask.Create('Task events cannot be marshalled: ' +
      'the dispatcher window does not exist');
  FToken := TbpTaskToken.Create;
  FState := tskPending;
  FMarshalToMainThread := aMarshalToMainThread;
  FId := RegisterTask(Self);
end;

destructor TbpTask.Destroy;
var
  lvThread: TThread;
  lvWorkerThreadId: DWORD;
begin
  lvThread := FThread;
  if lvThread <> nil then
    lvWorkerThreadId := lvThread.ThreadID
  else
    lvWorkerThreadId := 0;
  // no event may start from here on
  if FId <> 0 then
    UnregisterTask(FId, lvWorkerThreadId);
  if FToken <> nil then
    FToken.Cancel;
  if lvThread <> nil then
    if lvWorkerThreadId = GetCurrentThreadId then
      // freed by its own handler: the thread frees itself
      lvThread.FreeOnTerminate := True
    else
    begin
      lvThread.WaitFor;
      lvThread.Free;
    end;
  FToken.Free;
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpTask.GetState: TbpTaskState;
begin
  EnterCriticalSection(FLock);
  Result := FState;
  LeaveCriticalSection(FLock);
end;

function TbpTask.GetErrorMessage: string;
begin
  EnterCriticalSection(FLock);
  Result := FErrorMessage;
  LeaveCriticalSection(FLock);
end;

function TbpTask.GetErrorClass: string;
begin
  EnterCriticalSection(FLock);
  Result := FErrorClass;
  LeaveCriticalSection(FLock);
end;

function TbpTask.GetWorkerThreadId: Cardinal;
begin
  EnterCriticalSection(FLock);
  if FThread = nil then
    Result := 0
  else
    Result := FThread.ThreadID;
  LeaveCriticalSection(FLock);
end;

function TbpTask.IsFinished: Boolean;
begin
  Result := GetState in [tskSucceeded, tskFailed, tskCancelled];
end;

function TbpTask.CreateWorkerThread: TThread;
begin
  Result := TbpTaskThread.Create(Self);
end;

procedure TbpTask.Start;
begin
  if not Assigned(FWork) then
    raise EbpTask.Create('Task has no Work assigned');

  EnterCriticalSection(FLock);
  try
    if FState <> tskPending then
      raise EbpTask.Create('Task already started');
    // the worker takes FLock first, so it sees FThread
    FThread := CreateWorkerThread;
    FState := tskRunning;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TbpTask.Cancel;
begin
  FToken.Cancel;
end;

function TbpTask.WaitFor(aTimeoutMs: DWORD): Boolean;
var
  lvHandle: THandle;
begin
  EnterCriticalSection(FLock);
  if FThread = nil then
    lvHandle := 0
  else
    lvHandle := FThread.Handle;
  LeaveCriticalSection(FLock);
  if lvHandle = 0 then
    Result := IsFinished  // never started
  else
    Result := WaitForSingleObject(lvHandle, aTimeoutMs) = WAIT_OBJECT_0;
end;

procedure TbpTask.RunWork;
var
  lvId: Cardinal;
  lvMarshal: Boolean;
  lvState: TbpTaskState;
  lvErrorMessage, lvErrorClass: string;
begin
  // Start still holds FLock
  EnterCriticalSection(FLock);
  LeaveCriticalSection(FLock);
  lvId := FId;
  lvMarshal := FMarshalToMainThread;

  lvErrorMessage := '';
  lvErrorClass := '';
  if FToken.IsCancellationRequested then
    lvState := tskCancelled  // cancelled before the work began
  else
    try
      FWork(Self, FToken);
      // cancel wins over success
      if FToken.IsCancellationRequested then
        lvState := tskCancelled
      else
        lvState := tskSucceeded;
    except
      on E: Exception do
      begin
        lvErrorMessage := E.Message;
        lvErrorClass := E.ClassName;
        // and over an exception
        if FToken.IsCancellationRequested then
          lvState := tskCancelled
        else
          lvState := tskFailed;
      end;
    end;

  EnterCriticalSection(FLock);
  FErrorMessage := lvErrorMessage;
  FErrorClass := lvErrorClass;
  FState := lvState;
  LeaveCriticalSection(FLock);

  // last touch of Self: a handler may free the task
  if lvMarshal then
    PostMessage(gvWnd, gcWmTaskDone, WPARAM(lvId), LPARAM(Self))
  else
    RunEvents(Self, lvId);
end;

{ hot task factory }

function BpRunAsync(aWork: TbpTaskWorkEvent;
  aOnComplete: TbpTaskCompleteEvent; aMarshalToMainThread: Boolean): TbpTask;
begin
  Result := TbpTask.Create(aMarshalToMainThread);
  try
    Result.Work := aWork;
    Result.OnComplete := aOnComplete;
    Result.Start;
  except
    Result.Free;
    raise;
  end;
end;

procedure BpSetTaskExceptionHook(aProc: TbpTaskExceptionProc);
begin
  gvExceptionHook := aProc;
end;

initialization
  InitializeCriticalSection(gvLock);
  CreateDispatcher;

finalization
  DestroyDispatcher;
  DeleteCriticalSection(gvLock);

end.
