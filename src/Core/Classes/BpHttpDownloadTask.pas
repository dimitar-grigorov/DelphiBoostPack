unit BpHttpDownloadTask;

// Non-blocking HTTP(S) download for Delphi 7/2007 and later, shaped like a
// C# Task / JS Promise: configure, Start, receive OnProgress and OnComplete,
// Cancel at any point, optionally WaitFor to join. One instance is one
// download (one-shot); create a new task for a retry.
//
// The transport is the synchronous TbpHttpClient.Download running on a
// dedicated worker thread - no Application.ProcessMessages anywhere. Cancel
// works through TbpCancellationToken, which closes the WinInet request
// handle, so even a worker blocked in connect or read aborts promptly.
//
// Event threading (document of record):
// - MarshalToMainThread = True (default, for VCL apps): events are posted
//   through a hidden window and fire on the thread that created the task,
//   which must be the one running the message loop. Progress posts are
//   coalesced, so a fast download cannot flood the queue; each event
//   reports the latest byte counts. Events only fire while messages are
//   being pumped - do not combine with blocking the main thread in WaitFor
//   and expecting events first.
// - MarshalToMainThread = False (console apps, tests, own threads): events
//   fire directly on the worker thread; the handler must be thread-safe.
//
// State machine: dtsPending -> dtsRunning -> dtsSucceeded | dtsFailed |
// dtsCancelled. A non-2xx status is dtsFailed (the response record stays
// available). Results (State, Response, ErrorMessage...) are valid and
// thread-safe to read as soon as the state is terminal, independent of
// event delivery.
//
// The destructor cancels a running download, joins the worker and frees
// everything - no orphan threads, no leaked handles, whatever state the
// task died in.

interface

uses
  Classes, SysUtils, Windows, Messages, BpHttpClient, BpCancellationToken;

type
  TbpHttpDownloadState = (dtsPending, dtsRunning, dtsSucceeded, dtsFailed,
    dtsCancelled);

  TbpHttpDownloadCompleteEvent = procedure(ASender: TObject) of object;
  TbpHttpDownloadErrorEvent = procedure(ASender: TObject;
    const AErrorMessage: string) of object;

  TbpHttpDownloadTask = class
  private
    FClient: TbpHttpClient;        // owned; configure via Client before Start
    FToken: TbpCancellationToken;  // owned
    FThread: TThread;              // owned worker, joined in Destroy
    FLock: TRTLCriticalSection;    // guards state, progress pair and results
    FUrl: string;
    FDestFileName: string;
    FDestStream: TStream;          // caller-owned; must outlive the task
    FHeaders: string;
    FMarshalToMainThread: Boolean;
    FWnd: HWND;                    // hidden marshaling window, 0 when direct
    FState: TbpHttpDownloadState;
    FReceived: Int64;
    FTotal: Int64;
    FProgressPosted: Integer;      // coalescing flag for progress posts
    FResponse: TbpHttpResponse;
    FErrorMessage: string;
    FErrorCode: DWORD;
    FHttpStatus: Integer;
    FOnProgress: TbpHttpProgressEvent;
    FOnComplete: TbpHttpDownloadCompleteEvent;
    FOnError: TbpHttpDownloadErrorEvent;
    function GetState: TbpHttpDownloadState;
    function GetReceived: Int64;
    function GetTotal: Int64;
    function GetResponse: TbpHttpResponse;
    function GetErrorMessage: string;
    function GetErrorCode: DWORD;
    function GetHttpStatus: Integer;
    procedure WndProc(var AMessage: TMessage);
    procedure HandleWorkerProgress(ASender: TObject; const AReceived,
      ATotal: Int64; var ACancel: Boolean);
    procedure FireCompletionEvents;
    procedure RunDownload;  // worker thread body
  public
    // create the task on the thread that should receive marshaled events
    // (the main thread in a VCL app); pass False to get events directly on
    // the worker thread instead
    constructor Create(AMarshalToMainThread: Boolean = True);
    destructor Destroy; override;

    // validates Url and destination, then returns immediately while the
    // download runs on the worker thread; raises EbpHttpClient when the
    // task was already started or is misconfigured
    procedure Start;
    // requests cancellation; prompt and safe from any thread, also before
    // Start. The task reaches dtsCancelled when the worker has unwound and
    // any partial file has been deleted.
    procedure Cancel;
    // joins the worker; True when the download has finished (any outcome).
    // Marshaled events still need a running message loop to fire, but all
    // result properties are valid once this returns True.
    function WaitFor(ATimeoutMs: DWORD = INFINITE): Boolean;
    function IsFinished: Boolean;

    // configure before Start
    property Url: string read FUrl write FUrl;
    property DestFileName: string read FDestFileName write FDestFileName;
    property DestStream: TStream read FDestStream write FDestStream;
    property Headers: string read FHeaders write FHeaders;
    // timeouts, auth, proxy behaviour, user agent: set them here
    property Client: TbpHttpClient read FClient;
    property Token: TbpCancellationToken read FToken;
    property MarshalToMainThread: Boolean read FMarshalToMainThread;

    // results, thread-safe at any time; authoritative once IsFinished
    property State: TbpHttpDownloadState read GetState;
    property Received: Int64 read GetReceived;
    property Total: Int64 read GetTotal;
    property Response: TbpHttpResponse read GetResponse;
    property ErrorMessage: string read GetErrorMessage;
    property ErrorCode: DWORD read GetErrorCode;        // WinInet error, 0 if none
    property HttpStatus: Integer read GetHttpStatus;    // status of a failed response

    // OnProgress fires per chunk with Int64 received/total (-1 = unknown);
    // set ACancel to abort. OnError fires before OnComplete on dtsFailed.
    // OnComplete fires once on every terminal state - check State inside.
    property OnProgress: TbpHttpProgressEvent read FOnProgress write FOnProgress;
    property OnComplete: TbpHttpDownloadCompleteEvent read FOnComplete write FOnComplete;
    property OnError: TbpHttpDownloadErrorEvent read FOnError write FOnError;
  end;

implementation

const
  gcWmTaskProgress = WM_APP + 1;
  gcWmTaskDone = WM_APP + 2;

type
  // thin shell; the logic lives in TbpHttpDownloadTask.RunDownload
  TbpDownloadThread = class(TThread)
  private
    FTask: TbpHttpDownloadTask;
  protected
    procedure Execute; override;
  public
    constructor Create(ATask: TbpHttpDownloadTask);
  end;

constructor TbpDownloadThread.Create(ATask: TbpHttpDownloadTask);
begin
  FTask := ATask;
  FreeOnTerminate := False;  // the task owns and joins the thread
  inherited Create(False);
end;

procedure TbpDownloadThread.Execute;
begin
  FTask.RunDownload;
end;

{ TbpHttpDownloadTask }

constructor TbpHttpDownloadTask.Create(AMarshalToMainThread: Boolean);
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FClient := TbpHttpClient.Create;
  FToken := TbpCancellationToken.Create;
  FState := dtsPending;
  FTotal := -1;
  FMarshalToMainThread := AMarshalToMainThread;
  if FMarshalToMainThread then
    FWnd := Classes.AllocateHWnd(WndProc);
end;

destructor TbpHttpDownloadTask.Destroy;
begin
  // abort and join first: the worker touches FClient/FToken/fields
  FToken.Cancel;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FThread.Free;
  end;
  if FWnd <> 0 then
    Classes.DeallocateHWnd(FWnd);  // pending posted messages are discarded
  FToken.Free;
  FClient.Free;
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpHttpDownloadTask.GetState: TbpHttpDownloadState;
begin
  EnterCriticalSection(FLock);
  Result := FState;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetReceived: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FReceived;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetTotal: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FTotal;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetResponse: TbpHttpResponse;
begin
  EnterCriticalSection(FLock);
  Result := FResponse;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetErrorMessage: string;
begin
  EnterCriticalSection(FLock);
  Result := FErrorMessage;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetErrorCode: DWORD;
begin
  EnterCriticalSection(FLock);
  Result := FErrorCode;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetHttpStatus: Integer;
begin
  EnterCriticalSection(FLock);
  Result := FHttpStatus;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.IsFinished: Boolean;
begin
  Result := GetState in [dtsSucceeded, dtsFailed, dtsCancelled];
end;

procedure TbpHttpDownloadTask.Start;
begin
  if FUrl = '' then
    raise EbpHttpClient.Create('Download task has no Url');
  if (FDestFileName = '') and (FDestStream = nil) then
    raise EbpHttpClient.Create('Download task has no destination (set DestFileName or DestStream)');
  if (FDestFileName <> '') and (FDestStream <> nil) then
    raise EbpHttpClient.Create('Download task has both DestFileName and DestStream; set only one');

  EnterCriticalSection(FLock);
  try
    if FState <> dtsPending then
      raise EbpHttpClient.Create('Download task already started');
    FState := dtsRunning;
  finally
    LeaveCriticalSection(FLock);
  end;

  FThread := TbpDownloadThread.Create(Self);
end;

procedure TbpHttpDownloadTask.Cancel;
begin
  FToken.Cancel;
end;

function TbpHttpDownloadTask.WaitFor(ATimeoutMs: DWORD): Boolean;
begin
  if FThread = nil then
    Result := IsFinished  // never started
  else
    Result := WaitForSingleObject(FThread.Handle, ATimeoutMs) = WAIT_OBJECT_0;
end;

// worker thread: progress from the sync core. Direct mode forwards to the
// user handler as-is; marshaled mode stores the counters and posts at most
// one pending notification.
procedure TbpHttpDownloadTask.HandleWorkerProgress(ASender: TObject;
  const AReceived, ATotal: Int64; var ACancel: Boolean);
begin
  EnterCriticalSection(FLock);
  FReceived := AReceived;
  FTotal := ATotal;
  LeaveCriticalSection(FLock);

  if FMarshalToMainThread then
  begin
    if InterlockedExchange(FProgressPosted, 1) = 0 then
      PostMessage(FWnd, gcWmTaskProgress, 0, 0);
  end
  else if Assigned(FOnProgress) then
    FOnProgress(Self, AReceived, ATotal, ACancel);
end;

// main thread (marshaled mode only)
procedure TbpHttpDownloadTask.WndProc(var AMessage: TMessage);
var
  lvReceived, lvTotal: Int64;
  lvCancel: Boolean;
begin
  case AMessage.Msg of
    gcWmTaskProgress:
      begin
        InterlockedExchange(FProgressPosted, 0);
        if Assigned(FOnProgress) then
        begin
          EnterCriticalSection(FLock);
          lvReceived := FReceived;
          lvTotal := FTotal;
          LeaveCriticalSection(FLock);
          lvCancel := False;
          FOnProgress(Self, lvReceived, lvTotal, lvCancel);
          if lvCancel then
            Cancel;
        end;
      end;
    gcWmTaskDone:
      FireCompletionEvents;
  else
    AMessage.Result := DefWindowProc(FWnd, AMessage.Msg, AMessage.WParam,
      AMessage.LParam);
  end;
end;

procedure TbpHttpDownloadTask.FireCompletionEvents;
begin
  if (GetState = dtsFailed) and Assigned(FOnError) then
    FOnError(Self, GetErrorMessage);
  if Assigned(FOnComplete) then
    FOnComplete(Self);
end;

procedure TbpHttpDownloadTask.RunDownload;
var
  lvResponse: TbpHttpResponse;
  lvState: TbpHttpDownloadState;
  lvErrorMessage: string;
  lvErrorCode: DWORD;
  lvHttpStatus: Integer;
begin
  lvErrorMessage := '';
  lvErrorCode := 0;
  lvHttpStatus := 0;
  // an exception path leaves lvResponse unassigned; keep it defined
  lvResponse.StatusCode := 0;
  lvResponse.StatusText := '';
  lvResponse.Headers := '';
  lvResponse.Body := '';
  lvResponse.ContentLength := -1;
  try
    if FDestFileName <> '' then
      lvResponse := FClient.DownloadToFile(FUrl, FDestFileName,
        HandleWorkerProgress, FToken, FHeaders)
    else
      lvResponse := FClient.Download(FUrl, FDestStream,
        HandleWorkerProgress, FToken, FHeaders);

    if BpHttpResponseIsSuccess(lvResponse) then
      lvState := dtsSucceeded
    else
    begin
      lvState := dtsFailed;
      lvHttpStatus := lvResponse.StatusCode;
      lvErrorMessage := BpClassifyHttpError(0, lvResponse.StatusCode);
    end;
  except
    on E: EbpHttpClientCancelled do
    begin
      lvState := dtsCancelled;
      lvErrorMessage := E.Message;
      lvErrorCode := E.WinInetError;
    end;
    on E: EbpHttpClient do
    begin
      lvState := dtsFailed;
      lvErrorMessage := E.Message;
      lvErrorCode := E.WinInetError;
      lvHttpStatus := E.StatusCode;
    end;
    on E: Exception do
    begin
      lvState := dtsFailed;
      lvErrorMessage := E.Message;
    end;
  end;

  // publish results before the state turns terminal, then notify
  EnterCriticalSection(FLock);
  FResponse := lvResponse;
  FErrorMessage := lvErrorMessage;
  FErrorCode := lvErrorCode;
  FHttpStatus := lvHttpStatus;
  FState := lvState;
  LeaveCriticalSection(FLock);

  if FMarshalToMainThread then
    PostMessage(FWnd, gcWmTaskDone, 0, 0)
  else
    FireCompletionEvents;
end;

end.
