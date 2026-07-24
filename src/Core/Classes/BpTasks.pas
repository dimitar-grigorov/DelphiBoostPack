unit BpTasks;

// Background tasks for Delphi 7/2007+: run a method on a worker thread,
// get completion events on the creating thread, cancel cooperatively.
// Self-contained; one thread per task, no pool.
//
//   FTask := BpRunAsync(DoWork, HandleDone);  // DoWork polls aToken
//   FTask.Cancel;  // or FTask.Free: cancels, joins, cleans up

interface

uses
  Classes, SysUtils, Windows, Messages;

type
  EbpTask = class(Exception);

  // cooperative cancel flag: thread-safe, one-shot
  TbpTaskToken = class
  private
    FCancelled: Integer;
  public
    procedure Cancel;
    function IsCancellationRequested: Boolean;
  end;

  TbpTaskState = (tskPending, tskRunning, tskSucceeded, tskFailed,
    tskCancelled);

  // worker-thread body; poll aToken and return early to honour a cancel
  TbpTaskWorkEvent = procedure(aSender: TObject;
    aToken: TbpTaskToken) of object;
  TbpTaskCompleteEvent = procedure(aSender: TObject) of object;
  TbpTaskErrorEvent = procedure(aSender: TObject;
    const aErrorMessage: string) of object;

  // one unit of work on an owned worker thread, C# Task style; one-shot.
  // Events fire on the creating thread (default) or the worker (Create(False)).
  TbpTask = class
  private
    FToken: TbpTaskToken;        // owned
    FThread: TThread;            // owned worker, joined in Destroy
    FLock: TRTLCriticalSection;  // guards state and results
    FMarshalToMainThread: Boolean;
    FWnd: HWND;                  // hidden marshaling window, 0 when direct
    FState: TbpTaskState;
    FErrorMessage: string;
    FErrorClass: string;
    FWork: TbpTaskWorkEvent;
    FOnComplete: TbpTaskCompleteEvent;
    FOnError: TbpTaskErrorEvent;
    function GetState: TbpTaskState;
    function GetErrorMessage: string;
    function GetErrorClass: string;
    procedure WndProc(var aMessage: TMessage);
    procedure FireCompletionEvents;
    procedure RunWork;  // worker thread body
  public
    // create on the thread that should receive the events
    constructor Create(aMarshalToMainThread: Boolean = True);
    // cancels, joins the worker, frees everything
    destructor Destroy; override;

    // returns immediately; raises when already started or Work is unassigned
    procedure Start;
    // safe from any thread, also before Start
    procedure Cancel;
    function WaitFor(aTimeoutMs: DWORD = INFINITE): Boolean;
    function IsFinished: Boolean;

    // configure before Start
    property Work: TbpTaskWorkEvent read FWork write FWork;
    property Token: TbpTaskToken read FToken;
    property MarshalToMainThread: Boolean read FMarshalToMainThread;

    // thread-safe results; authoritative once IsFinished
    property State: TbpTaskState read GetState;
    property ErrorMessage: string read GetErrorMessage;
    property ErrorClass: string read GetErrorClass;  // '' when no exception

    // OnComplete fires on every terminal state; OnError precedes it on tskFailed
    property OnComplete: TbpTaskCompleteEvent read FOnComplete write FOnComplete;
    property OnError: TbpTaskErrorEvent read FOnError write FOnError;
  end;

// hot task: create, wire and start in one call; the caller frees the task
// (a single name, no overloads: old compilers reject nil events on overloads)
function BpRunAsync(aWork: TbpTaskWorkEvent;
  aOnComplete: TbpTaskCompleteEvent = nil;
  aMarshalToMainThread: Boolean = True): TbpTask;

implementation

const
  gcWmTaskDone = WM_APP + 1;

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
  // thin shell around TbpTask.RunWork
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
  FToken := TbpTaskToken.Create;
  FState := tskPending;
  FMarshalToMainThread := aMarshalToMainThread;
  if FMarshalToMainThread then
    FWnd := Classes.AllocateHWnd(WndProc);
end;

destructor TbpTask.Destroy;
begin
  // cancel and join before freeing anything the worker touches
  FToken.Cancel;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FThread.Free;
  end;
  if FWnd <> 0 then
    Classes.DeallocateHWnd(FWnd);  // pending posted messages are discarded
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

function TbpTask.IsFinished: Boolean;
begin
  Result := GetState in [tskSucceeded, tskFailed, tskCancelled];
end;

procedure TbpTask.Start;
begin
  if not Assigned(FWork) then
    raise EbpTask.Create('Task has no Work assigned');

  EnterCriticalSection(FLock);
  try
    if FState <> tskPending then
      raise EbpTask.Create('Task already started');
    FState := tskRunning;
  finally
    LeaveCriticalSection(FLock);
  end;

  FThread := TbpTaskThread.Create(Self);
end;

procedure TbpTask.Cancel;
begin
  FToken.Cancel;
end;

function TbpTask.WaitFor(aTimeoutMs: DWORD): Boolean;
begin
  if FThread = nil then
    Result := IsFinished  // never started
  else
    Result := WaitForSingleObject(FThread.Handle, aTimeoutMs) = WAIT_OBJECT_0;
end;

// main thread (marshaled mode only)
procedure TbpTask.WndProc(var aMessage: TMessage);
begin
  if aMessage.Msg = gcWmTaskDone then
    FireCompletionEvents
  else
    aMessage.Result := DefWindowProc(FWnd, aMessage.Msg, aMessage.WParam,
      aMessage.LParam);
end;

procedure TbpTask.FireCompletionEvents;
begin
  if (GetState = tskFailed) and Assigned(FOnError) then
    FOnError(Self, GetErrorMessage);
  if Assigned(FOnComplete) then
    FOnComplete(Self);
end;

procedure TbpTask.RunWork;
var
  lvState: TbpTaskState;
  lvErrorMessage, lvErrorClass: string;
begin
  lvErrorMessage := '';
  lvErrorClass := '';
  if FToken.IsCancellationRequested then
    lvState := tskCancelled  // cancelled before the work began
  else
    try
      FWork(Self, FToken);
      // a cancel requested before the work finished wins over success
      if FToken.IsCancellationRequested then
        lvState := tskCancelled
      else
        lvState := tskSucceeded;
    except
      on E: Exception do
      begin
        lvErrorMessage := E.Message;
        lvErrorClass := E.ClassName;
        // an exception with a cancel pending counts as cancelled
        if FToken.IsCancellationRequested then
          lvState := tskCancelled
        else
          lvState := tskFailed;
      end;
    end;

  // publish results before the state turns terminal, then notify
  EnterCriticalSection(FLock);
  FErrorMessage := lvErrorMessage;
  FErrorClass := lvErrorClass;
  FState := lvState;
  LeaveCriticalSection(FLock);

  if FMarshalToMainThread then
    PostMessage(FWnd, gcWmTaskDone, 0, 0)
  else
    FireCompletionEvents;
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

end.
