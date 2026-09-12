unit BpHttpDownloadTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpHttpClient, BpTasks,
  BpMockHttpServer, BpTestSupport;

type
  // offline: progress math, header parsing, error classification, state machine
  TBpHttpDownloadTests = class(TTestCase)
  private
    FClient: TbpHttpClient;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestProgressPercent;
    procedure TestContentLengthParsing;
    procedure TestResponseHasBody;
    procedure TestClassifyCancelledError;
    procedure TestDownloadRejectsNilStream;
    procedure TestDownloadHonoursPreCancelledToken;
    procedure TestDownloadToFileKeepsTheOldFileOnPreCancelledToken;
    procedure TestTaskInitialState;
    procedure TestTaskStartValidation;
    procedure TestTaskInvalidUrlFails;
    procedure TestTaskCancelBeforeStart;
    procedure TestDownloadAsyncFactory;
  end;

  // the async download end to end, against the loopback server; no network
  TBpHttpDownloadTaskTests = class(TBpWireTestCase)
  private
    FTask: TbpHttpDownloadTask;
    FStream: TMemoryStream;
    FDir: string;
    FDest: string;
    FCompleteCount: Integer;
    FErrorCount: Integer;
    FProgressCount: Integer;
    FCompleteThreadId: Cardinal;
    FProgressThreadId: Cardinal;
    FErrorBeforeComplete: Boolean;
    FFreedInHandler: Boolean;
    FCancelOnData: Boolean;
    FMonotonic: Boolean;
    FLastReceived: Int64;
    FLastTotal: Int64;
    FStateInComplete: TbpHttpDownloadState;
    function NewTask(aMarshal: Boolean): TbpHttpDownloadTask;
    procedure EnqueueStall;
    procedure HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
      var aCancel: Boolean);
    procedure HandleComplete(aSender: TObject);
    procedure HandleError(aSender: TObject; const aErrorMessage: string);
    procedure HandleCompleteAndFree(aSender: TObject);
    procedure HandleErrorAndFree(aSender: TObject; const aErrorMessage: string);
    procedure HandleCompleteRaise(aSender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMarshalledCompleteRunsOnTheCreatingThread;
    procedure TestFailedStatusPinsResponseAndStatus;
    procedure TestTransportFailurePinsWhatItKnows;
    procedure TestFreeWhileRunningFiresNothing;
    procedure TestFreeFromInsideOwnCompleteMarshalled;
    procedure TestFreeFromInsideOwnCompleteDirect;
    procedure TestFreeFromInsideOwnErrorMarshalled;
    procedure TestFreeFromInsideOwnErrorDirect;
    procedure TestFreeMarshalledFromAForeignThread;
    procedure TestHandlerExceptionReachesTheHook;
    procedure TestProgressArrivesOnTheCreatingThread;
    procedure TestProgressPostsCoalesce;
    procedure TestCancelFromAProgressHandler;
    procedure TestNotFoundLeavesTheFileAlone;
    procedure TestCancelMidBodyLeavesNoTempFile;
    procedure TestStreamingDownloadReportsTheTotal;
  end;

  // the one thing the loopback server cannot serve: a real TLS handshake
  TBpHttpsOnlineTests = class(TTestCase)
  private
    function SkipIfOffline: Boolean;
  published
    procedure TestHttpsGet;
  end;

implementation

const
  // never contacted: every test using it stops before any network activity
  gcUnreachableUrl = 'http://127.0.0.1:1/never-contacted';
  gcTlsUrl = 'https://example.com/';

  gcClaimed = 10485760;  // Content-Length the stalling reply advertises
  gcBurst = 65536;       // what it really sends before going quiet
  gcBigBody = 1048576;
  gcReadBuffer = 65536;  // BpHttpClient's download buffer, mirrored to count reads

type
  EbpDownloadTestError = class(Exception);

  // frees a task on a thread that did not create it
  TForeignFreeThread = class(TThread)
  private
    FTask: TbpHttpDownloadTask;
  protected
    procedure Execute; override;
  public
    constructor Create(aTask: TbpHttpDownloadTask);
  end;

var
  gvOnlineProbed: Boolean = False;
  gvOnlineAvailable: Boolean = False;
  gvHookCount: Integer;
  gvHookMessage: string;

procedure DownloadTestExceptionHook(aTask: TbpTask; aException: Exception);
begin
  Inc(gvHookCount);
  gvHookMessage := aException.Message;
end;

function FileSizeOf(const aFileName: string): Integer;
var
  lvFile: TFileStream;
begin
  lvFile := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyNone);
  try
    Result := lvFile.Size;
  finally
    lvFile.Free;
  end;
end;

{ TForeignFreeThread }

constructor TForeignFreeThread.Create(aTask: TbpHttpDownloadTask);
begin
  FTask := aTask;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TForeignFreeThread.Execute;
begin
  FTask.Free;
end;

{ TBpHttpDownloadTests }

procedure TBpHttpDownloadTests.SetUp;
begin
  inherited;
  FClient := TbpHttpClient.Create;
end;

procedure TBpHttpDownloadTests.TearDown;
begin
  FClient.Free;
  inherited;
end;

procedure TBpHttpDownloadTests.TestProgressPercent;
begin
  CheckEquals(-1, BpHttpProgressPercent(0, -1), 'unknown total');
  CheckEquals(-1, BpHttpProgressPercent(500, 0), 'zero total is unknown');
  CheckEquals(0, BpHttpProgressPercent(0, 1000));
  CheckEquals(0, BpHttpProgressPercent(-5, 1000), 'negative received clamps to 0');
  CheckEquals(50, BpHttpProgressPercent(500, 1000));
  CheckEquals(99, BpHttpProgressPercent(999, 1000), 'no premature 100');
  CheckEquals(100, BpHttpProgressPercent(1000, 1000));
  CheckEquals(100, BpHttpProgressPercent(2000, 1000), 'overshoot clamps to 100');
  // Int64 pairs beyond the 32-bit range must not overflow
  CheckEquals(50, BpHttpProgressPercent(Int64(5) * 1024 * 1024 * 1024,
    Int64(10) * 1024 * 1024 * 1024));
end;

procedure TBpHttpDownloadTests.TestContentLengthParsing;
const
  lcHeaders = 'HTTP/1.1 200 OK'#13#10'Content-Length: 262144'#13#10;
  lcHuge = 'HTTP/1.1 200 OK'#13#10'Content-Length: 5368709120'#13#10;
  lcChunked = 'HTTP/1.1 200 OK'#13#10'Transfer-Encoding: chunked'#13#10;
  lcJunk = 'HTTP/1.1 200 OK'#13#10'Content-Length: banana'#13#10;
  lcNegative = 'HTTP/1.1 200 OK'#13#10'Content-Length: -5'#13#10;
  lcHex = 'HTTP/1.1 200 OK'#13#10'Content-Length: $40000'#13#10;
  lcCHex = 'HTTP/1.1 200 OK'#13#10'Content-Length: 0x40000'#13#10;
  lcPlus = 'HTTP/1.1 200 OK'#13#10'Content-Length: +42'#13#10;
  lcTrailing = 'HTTP/1.1 200 OK'#13#10'Content-Length: 42 bytes'#13#10;
  lcOverflow = 'HTTP/1.1 200 OK'#13#10'Content-Length: 99999999999999999999'#13#10;
begin
  Check(BpHttpContentLength(lcHeaders) = 262144, 'plain value');
  // > 4 GB stays exact in Int64
  Check(BpHttpContentLength(lcHuge) = Int64(5) * 1024 * 1024 * 1024, '5 GB value');
  Check(BpHttpContentLength(lcChunked) = -1, 'absent header yields -1');
  Check(BpHttpContentLength(lcJunk) = -1, 'garbage yields -1');
  Check(BpHttpContentLength(lcNegative) = -1, 'negative yields -1');
  Check(BpHttpContentLength('') = -1, 'empty block yields -1');
  // RFC 7230 allows digits only; each of these means another length
  Check(BpHttpContentLength(lcHex) = -1, 'Pascal hex yields -1');
  Check(BpHttpContentLength(lcCHex) = -1, 'C hex yields -1');
  Check(BpHttpContentLength(lcPlus) = -1, 'leading plus yields -1');
  Check(BpHttpContentLength(lcTrailing) = -1, 'trailing text yields -1');
  Check(BpHttpContentLength(lcOverflow) = -1, 'past Int64 yields -1');
end;

// the completeness guard must not fire on a reply that carries no body
procedure TBpHttpDownloadTests.TestResponseHasBody;
begin
  CheckTrue(BpHttpResponseHasBody('GET', 200), 'GET 200');
  CheckTrue(BpHttpResponseHasBody('POST', 201), 'POST 201');
  CheckTrue(BpHttpResponseHasBody('GET', 404), 'an error body is still a body');
  CheckFalse(BpHttpResponseHasBody('HEAD', 200), 'HEAD');
  CheckFalse(BpHttpResponseHasBody('head', 200), 'the verb match is case free');
  CheckFalse(BpHttpResponseHasBody('GET', 204), 'no content');
  CheckFalse(BpHttpResponseHasBody('GET', 304), 'not modified');
  CheckFalse(BpHttpResponseHasBody('GET', 100), 'continue');
end;

procedure TBpHttpDownloadTests.TestClassifyCancelledError;
begin
  CheckEquals('Operation cancelled',
    BpClassifyHttpError(gcErrOperationCancelled, 0));
end;

procedure TBpHttpDownloadTests.TestDownloadRejectsNilStream;
begin
  try
    FClient.Download(gcUnreachableUrl, nil);
    Fail('expected EbpHttpClient for nil stream');
  except
    on EbpHttpClientCancelled do
      Fail('nil stream must not classify as cancellation');
    on EbpHttpClient do
      ; // expected
  end;
end;

procedure TBpHttpDownloadTests.TestDownloadHonoursPreCancelledToken;
var
  lvToken: TbpCancellationToken;
  lvStream: TMemoryStream;
begin
  // the token check comes before any network activity, so this is offline
  lvToken := TbpCancellationToken.Create;
  lvStream := TMemoryStream.Create;
  try
    lvToken.Cancel;
    try
      FClient.Download(gcUnreachableUrl, lvStream, nil, lvToken);
      Fail('expected EbpHttpClientCancelled');
    except
      on E: EbpHttpClientCancelled do
        CheckEquals(gcErrOperationCancelled, E.WinInetError);
    end;
    Check(lvStream.Size = 0, 'nothing may reach the stream');
  finally
    lvStream.Free;
    lvToken.Free;
  end;
end;

procedure TBpHttpDownloadTests.TestDownloadToFileKeepsTheOldFileOnPreCancelledToken;
var
  lvToken: TbpCancellationToken;
  lvFileName: string;
begin
  lvToken := TbpCancellationToken.Create;
  lvFileName := BpTempFilePath('bp_download_cancelled_test.tmp');
  try
    BpWriteWholeFile(lvFileName, 'KEEPME');
    lvToken.Cancel;
    try
      FClient.DownloadToFile(gcUnreachableUrl, lvFileName, nil, lvToken);
      Fail('expected EbpHttpClientCancelled');
    except
      on EbpHttpClientCancelled do
        ; // expected
    end;
    CheckTrue(FileExists(lvFileName), 'the file that was there must survive');
    CheckEquals(6, FileSizeOf(lvFileName), 'and must not have been truncated');
  finally
    SysUtils.DeleteFile(lvFileName);
    lvToken.Free;
  end;
end;

procedure TBpHttpDownloadTests.TestTaskInitialState;
var
  lvTask: TbpHttpDownloadTask;
  lvStart: Cardinal;
begin
  lvTask := TbpHttpDownloadTask.Create(False);
  try
    Check(lvTask.State = dtsPending, 'fresh task is pending');
    Check(lvTask.Received = 0);
    Check(lvTask.Total = -1, 'total unknown before headers');
    CheckFalse(lvTask.IsFinished);
    // a task with no thread has nothing to wait on, so it must not wait at all
    lvStart := GetTickCount;
    CheckFalse(lvTask.WaitFor(5000), 'a never-started task has not finished');
    Check(GetTickCount - lvStart < 1000, 'WaitFor must return, not burn its timeout');
    CheckEquals('', lvTask.ErrorMessage);
  finally
    lvTask.Free;
  end;
end;

procedure TBpHttpDownloadTests.TestTaskStartValidation;
var
  lvTask: TbpHttpDownloadTask;
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  lvTask := TbpHttpDownloadTask.Create(False);
  try
    try
      lvTask.Start;
      Fail('expected raise: no Url');
    except
      on EbpHttpClient do ;
    end;

    lvTask.Url := gcUnreachableUrl;
    try
      lvTask.Start;
      Fail('expected raise: no destination');
    except
      on EbpHttpClient do ;
    end;

    lvTask.DestStream := lvStream;
    lvTask.DestFileName := BpTempFilePath('bp_task_both_dest.tmp');
    try
      lvTask.Start;
      Fail('expected raise: both destinations');
    except
      on EbpHttpClient do ;
    end;

    Check(lvTask.State = dtsPending, 'failed validation must not change state');
  finally
    lvTask.Free;
    lvStream.Free;
  end;
end;

procedure TBpHttpDownloadTests.TestTaskInvalidUrlFails;
var
  lvTask: TbpHttpDownloadTask;
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  lvTask := TbpHttpDownloadTask.Create(False);
  try
    lvTask.Url := 'not a url at all';
    lvTask.DestStream := lvStream;
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = dtsFailed, 'unparsable url fails the task');
    Check(Pos('Invalid URL', lvTask.ErrorMessage) > 0, lvTask.ErrorMessage);

    // one-shot: a finished task refuses a second start
    try
      lvTask.Start;
      Fail('expected raise: task already started');
    except
      on EbpHttpClient do ;
    end;
  finally
    lvTask.Free;
    lvStream.Free;
  end;
end;

procedure TBpHttpDownloadTests.TestTaskCancelBeforeStart;
var
  lvTask: TbpHttpDownloadTask;
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  lvTask := TbpHttpDownloadTask.Create(False);
  try
    lvTask.Url := gcUnreachableUrl;
    lvTask.DestStream := lvStream;
    lvTask.Cancel;
    // the pre-cancelled token stops the worker before any network activity
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = dtsCancelled, 'cancel before start wins');
    CheckEquals(gcErrOperationCancelled, lvTask.ErrorCode);
    Check(lvStream.Size = 0, 'nothing may reach the stream');
  finally
    lvTask.Free;
    lvStream.Free;
  end;
end;

procedure TBpHttpDownloadTests.TestDownloadAsyncFactory;
var
  lvTask: TbpHttpDownloadTask;
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  // hot task: an unparsable url makes it fail fast without touching the network
  lvTask := BpDownloadToStreamAsync('not a url at all', lvStream, nil, nil, False);
  try
    Check(lvTask.State in [dtsRunning, dtsFailed], 'factory returns a started task');
    CheckTrue(lvTask.WaitFor(5000), 'worker must finish promptly');
    Check(lvTask.State = dtsFailed, 'unparsable url fails the task');
  finally
    lvTask.Free;
    lvStream.Free;
  end;
end;

{ TBpHttpDownloadTaskTests }

procedure TBpHttpDownloadTaskTests.SetUp;
begin
  inherited;
  FDir := BpMakeTempDir('bp_task');
  FDest := IncludeTrailingPathDelimiter(FDir) + 'payload.bin';
  BpWriteWholeFile(FDest, 'ORIGINAL');
  FStream := TMemoryStream.Create;
  FMonotonic := True;
  FLastTotal := -1;
  FStateInComplete := dtsPending;
end;

procedure TBpHttpDownloadTaskTests.TearDown;
begin
  FreeAndNil(FTask);
  FreeAndNil(FStream);
  BpDeleteTree(FDir);
  inherited;
end;

// the test owns the task through FTask; a handler that frees it clears FTask
function TBpHttpDownloadTaskTests.NewTask(
  aMarshal: Boolean): TbpHttpDownloadTask;
begin
  FTask := TbpHttpDownloadTask.Create(aMarshal);
  FTask.DestStream := FStream;
  FTask.Client.ConnectTimeout := 4000;
  FTask.Client.SendTimeout := 4000;
  FTask.Client.ReceiveTimeout := 4000;
  Result := FTask;
end;

procedure TBpHttpDownloadTaskTests.EnqueueStall;
var
  lvReply: TbpMockResponse;
begin
  lvReply := BpMockOk(BpRepeated($42, gcBurst));
  lvReply.ClaimedLength := gcClaimed;
  lvReply.Effect := mseStall;
  FServer.Enqueue(lvReply);
end;

procedure TBpHttpDownloadTaskTests.HandleProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  Inc(FProgressCount);
  FProgressThreadId := GetCurrentThreadId;
  if aReceived < FLastReceived then
    FMonotonic := False;
  FLastReceived := aReceived;
  FLastTotal := aTotal;
  if FCancelOnData and (aReceived > 0) then
    aCancel := True;
end;

procedure TBpHttpDownloadTaskTests.HandleComplete(aSender: TObject);
begin
  Inc(FCompleteCount);
  FCompleteThreadId := GetCurrentThreadId;
  FStateInComplete := TbpHttpDownloadTask(aSender).State;
end;

procedure TBpHttpDownloadTaskTests.HandleError(aSender: TObject;
  const aErrorMessage: string);
begin
  Inc(FErrorCount);
  if FCompleteCount = 0 then
    FErrorBeforeComplete := True;
end;

procedure TBpHttpDownloadTaskTests.HandleCompleteAndFree(aSender: TObject);
begin
  Inc(FCompleteCount);
  FTask := nil;  // TearDown must not free it a second time
  TbpHttpDownloadTask(aSender).Free;
  FFreedInHandler := True;
end;

procedure TBpHttpDownloadTaskTests.HandleErrorAndFree(aSender: TObject;
  const aErrorMessage: string);
begin
  Inc(FErrorCount);
  FTask := nil;
  TbpHttpDownloadTask(aSender).Free;
  FFreedInHandler := True;
end;

procedure TBpHttpDownloadTaskTests.HandleCompleteRaise(aSender: TObject);
begin
  Inc(FCompleteCount);
  raise EbpDownloadTestError.Create('from the completion handler');
end;

procedure TBpHttpDownloadTaskTests.TestMarshalledCompleteRunsOnTheCreatingThread;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockOk(BpRepeated($41, 4096)));
  lvTask := NewTask(True);
  lvTask.Url := Url('/payload.bin');
  lvTask.OnComplete := HandleComplete;
  lvTask.OnError := HandleError;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');
  CheckEquals(0, FCompleteCount, 'nothing fires before the queue is pumped');
  CheckTrue(BpPumpUntilCount(FCompleteCount, 1, 5000), 'OnComplete must arrive');
  CheckEquals(Integer(GetCurrentThreadId), Integer(FCompleteThreadId),
    'the event belongs to the thread that created the task');
  CheckEquals(0, FErrorCount, 'OnError must not fire on success');
  Check(lvTask.State = dtsSucceeded, lvTask.ErrorMessage);
  Check(FStateInComplete = dtsSucceeded, 'the state is final inside OnComplete');
  Check(lvTask.Received = 4096);
  Check(lvTask.Total = 4096);
  CheckEquals(4096, FStream.Size);
  CheckEquals(200, lvTask.Response.StatusCode);
end;

procedure TBpHttpDownloadTaskTests.TestFailedStatusPinsResponseAndStatus;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockStatus(404, 'no such thing'));
  lvTask := NewTask(True);
  lvTask.Url := Url('/missing.bin');
  lvTask.OnComplete := HandleComplete;
  lvTask.OnError := HandleError;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');
  CheckTrue(BpPumpUntilCount(FCompleteCount, 1, 5000), 'OnComplete must arrive');
  CheckEquals(1, FErrorCount, 'OnError must fire once');
  CheckTrue(FErrorBeforeComplete, 'OnError comes before OnComplete');
  Check(lvTask.State = dtsFailed);
  CheckEquals(404, lvTask.HttpStatus);
  CheckEquals(404, lvTask.Response.StatusCode, 'the response stays readable');
end;

procedure TBpHttpDownloadTaskTests.TestTransportFailurePinsWhatItKnows;
var
  lvReply: TbpMockResponse;
  lvTask: TbpHttpDownloadTask;
begin
  lvReply := BpMockOk('');
  lvReply.Effect := mseNoResponse;  // the socket closes with nothing on it
  FServer.Enqueue(lvReply);

  lvTask := NewTask(True);
  lvTask.Url := Url('/silent.bin');
  lvTask.OnComplete := HandleComplete;
  lvTask.OnError := HandleError;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(15000), 'the worker must finish');
  CheckTrue(BpPumpUntilCount(FCompleteCount, 1, 5000), 'OnComplete must arrive');
  CheckTrue(FErrorBeforeComplete, 'OnError comes before OnComplete');
  Check(lvTask.State = dtsFailed, lvTask.ErrorMessage);
  CheckEquals(0, lvTask.Response.StatusCode, 'no reply, so no status');
  Check(lvTask.ErrorMessage <> '', 'the failure must say something');
end;

procedure TBpHttpDownloadTaskTests.TestFreeWhileRunningFiresNothing;
var
  lvTask: TbpHttpDownloadTask;
begin
  EnqueueStall;
  lvTask := NewTask(True);
  lvTask.Url := Url('/stall.bin');
  lvTask.Client.ReceiveTimeout := 25000;
  lvTask.OnProgress := HandleProgress;
  lvTask.OnComplete := HandleComplete;
  lvTask.OnError := HandleError;
  lvTask.Start;

  CheckTrue(BpPumpUntilCount(FProgressCount, 1, 10000), 'the body must start');
  FreeAndNil(FTask);  // cancels the live read, joins, and drops the completion
  BpPumpFor(150);
  CheckEquals(0, FCompleteCount, 'a freed task fires no completion');
  CheckEquals(0, FErrorCount, 'a freed task fires no error');
end;

procedure TBpHttpDownloadTaskTests.TestFreeFromInsideOwnCompleteMarshalled;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockOk('ok'));
  lvTask := NewTask(True);
  lvTask.Url := Url('/small.bin');
  lvTask.OnComplete := HandleCompleteAndFree;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');
  CheckTrue(BpPumpUntilFlag(FFreedInHandler, 5000),
    'the handler ran and freed its own task');
end;

procedure TBpHttpDownloadTaskTests.TestFreeFromInsideOwnCompleteDirect;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockOk('ok'));
  lvTask := NewTask(False);
  lvTask.Url := Url('/small.bin');
  lvTask.OnComplete := HandleCompleteAndFree;
  lvTask.Start;

  CheckTrue(BpWaitForFlag(FFreedInHandler, 10000),
    'the worker freed its own task without joining itself');
end;

procedure TBpHttpDownloadTaskTests.TestFreeFromInsideOwnErrorMarshalled;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockStatus(500, 'boom'));
  lvTask := NewTask(True);
  lvTask.Url := Url('/broken.bin');
  lvTask.OnError := HandleErrorAndFree;
  lvTask.OnComplete := HandleComplete;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');
  CheckTrue(BpPumpUntilFlag(FFreedInHandler, 5000), 'OnError ran and freed');
  BpPumpFor(100);
  CheckEquals(0, FCompleteCount, 'a task freed in OnError gets no OnComplete');
end;

procedure TBpHttpDownloadTaskTests.TestFreeFromInsideOwnErrorDirect;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockStatus(500, 'boom'));
  lvTask := NewTask(False);
  lvTask.Url := Url('/broken.bin');
  lvTask.OnError := HandleErrorAndFree;
  lvTask.OnComplete := HandleComplete;
  lvTask.Start;

  CheckTrue(BpWaitForFlag(FFreedInHandler, 10000), 'OnError ran and freed');
  CheckEquals(0, FCompleteCount, 'a task freed in OnError gets no OnComplete');
end;

procedure TBpHttpDownloadTaskTests.TestFreeMarshalledFromAForeignThread;
var
  lvTask: TbpHttpDownloadTask;
  lvFreer: TForeignFreeThread;
begin
  FServer.Enqueue(BpMockOk('ok'));
  lvTask := NewTask(True);
  lvTask.Url := Url('/small.bin');
  lvTask.OnComplete := HandleComplete;
  lvTask.Start;
  CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');

  FTask := nil;  // the foreign thread owns it from here
  lvFreer := TForeignFreeThread.Create(lvTask);
  // a blocked freer is left unjoined on purpose: joining it would hang the suite
  if WaitForSingleObject(lvFreer.Handle, 10000) <> WAIT_OBJECT_0 then
    Fail('freeing a marshalled task from a foreign thread blocked');
  lvFreer.Free;

  BpPumpFor(100);
  CheckEquals(0, FCompleteCount, 'the queued completion died with the task');
end;

procedure TBpHttpDownloadTaskTests.TestHandlerExceptionReachesTheHook;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockOk('ok'));
  gvHookCount := 0;
  gvHookMessage := '';
  BpSetTaskExceptionHook(DownloadTestExceptionHook);
  try
    lvTask := NewTask(True);
    lvTask.Url := Url('/small.bin');
    lvTask.OnComplete := HandleCompleteRaise;
    lvTask.Start;
    CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');
    CheckTrue(BpPumpUntilCount(gvHookCount, 1, 5000),
      'the hook must see what the handler raised');
    CheckEquals('from the completion handler', gvHookMessage);
  finally
    BpSetTaskExceptionHook(nil);
  end;
end;

procedure TBpHttpDownloadTaskTests.TestProgressArrivesOnTheCreatingThread;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockOk(BpRepeated($41, 8192)));
  lvTask := NewTask(True);
  lvTask.Url := Url('/payload.bin');
  lvTask.OnProgress := HandleProgress;
  lvTask.OnComplete := HandleComplete;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');
  CheckTrue(BpPumpUntilCount(FProgressCount, 1, 5000), 'progress must arrive');
  CheckEquals(Integer(GetCurrentThreadId), Integer(FProgressThreadId),
    'progress belongs to the thread that created the task');
  CheckTrue(FMonotonic, 'the received counter never goes backwards');
end;

// the worker samples once per read, so the queue must not grow with the body
procedure TBpHttpDownloadTaskTests.TestProgressPostsCoalesce;
var
  lvTask: TbpHttpDownloadTask;
  lvReads: Integer;
begin
  FServer.Enqueue(BpMockOk(BpRepeated($41, gcBigBody)));
  lvTask := NewTask(True);
  lvTask.Url := Url('/big.bin');
  lvTask.OnProgress := HandleProgress;
  lvTask.OnComplete := HandleComplete;
  lvTask.Start;

  // WaitFor does not pump, so every sample taken here had to collapse into one
  CheckTrue(lvTask.WaitFor(30000), 'the worker must finish');
  Check(lvTask.Received = gcBigBody, 'the whole body arrived');
  lvReads := gcBigBody div gcReadBuffer;
  Check(lvReads >= 16, 'the body must be big enough to need many reads');
  BpPumpMessages;
  CheckEquals(1, FProgressCount,
    Format('%d samples had to collapse into one event', [lvReads]));
  Check(FLastReceived = gcBigBody, 'the one event carries the newest count');
end;

procedure TBpHttpDownloadTaskTests.TestCancelFromAProgressHandler;
var
  lvTask: TbpHttpDownloadTask;
begin
  EnqueueStall;
  FCancelOnData := True;
  lvTask := NewTask(False);  // direct, so the handler runs as the body arrives
  lvTask.Url := Url('/stall.bin');
  lvTask.Client.ReceiveTimeout := 25000;
  lvTask.OnProgress := HandleProgress;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(15000), 'the cancel must stop the download');
  Check(lvTask.State = dtsCancelled, 'aCancel in a progress handler cancels');
  CheckTrue(lvTask.Token.IsCancellationRequested, 'and it goes through the token');
end;

procedure TBpHttpDownloadTaskTests.TestNotFoundLeavesTheFileAlone;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockStatus(404, 'no such thing'));
  lvTask := NewTask(False);
  lvTask.DestStream := nil;
  lvTask.DestFileName := FDest;
  lvTask.Url := Url('/missing.bin');
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(10000), 'the worker must finish');
  Check(lvTask.State = dtsFailed);
  CheckEquals(404, lvTask.HttpStatus);
  CheckEquals('ORIGINAL', string(BpReadWholeFile(FDest)),
    'a 404 body must not become the payload');
  CheckEquals(1, BpCountFiles(FDir), 'a temp file was left behind');
end;

procedure TBpHttpDownloadTaskTests.TestCancelMidBodyLeavesNoTempFile;
var
  lvTask: TbpHttpDownloadTask;
begin
  EnqueueStall;
  lvTask := NewTask(False);
  lvTask.DestStream := nil;
  lvTask.DestFileName := FDest;
  lvTask.Url := Url('/stall.bin');
  lvTask.Client.ReceiveTimeout := 25000;
  lvTask.OnProgress := HandleProgress;
  lvTask.Start;

  CheckTrue(BpWaitForCount(FProgressCount, 2, 10000), 'the body must start');
  lvTask.Cancel;
  CheckTrue(lvTask.WaitFor(15000), 'the cancel must stop the download');
  Check(lvTask.State = dtsCancelled);
  CheckEquals('ORIGINAL', string(BpReadWholeFile(FDest)),
    'a cancelled download must not touch the destination');
  CheckEquals(1, BpCountFiles(FDir), 'a temp file was left behind');
end;

procedure TBpHttpDownloadTaskTests.TestStreamingDownloadReportsTheTotal;
var
  lvTask: TbpHttpDownloadTask;
begin
  FServer.Enqueue(BpMockOk(BpRepeated($41, gcBurst)));
  lvTask := NewTask(False);  // direct, so progress arrives without a pump
  lvTask.Url := Url('/payload.bin');
  lvTask.OnProgress := HandleProgress;
  lvTask.Start;

  CheckTrue(lvTask.WaitFor(15000), 'the worker must finish');
  Check(lvTask.State = dtsSucceeded, lvTask.ErrorMessage);
  CheckEquals(gcBurst, FStream.Size, 'every byte lands in the stream');
  Check(FLastTotal = gcBurst, 'progress reports the total from Content-Length');
  Check(FLastReceived = gcBurst, 'the final tick equals the size');
  Check(FProgressCount >= 2, 'expected the initial tick and at least one more');
  CheckTrue(FMonotonic, 'the received counter never goes backwards');
  CheckEquals('', string(lvTask.Response.Body), 'a streamed body stays empty');
end;

{ TBpHttpsOnlineTests }

function TBpHttpsOnlineTests.SkipIfOffline: Boolean;
var
  lvClient: TbpHttpClient;
begin
  if not gvOnlineProbed then
  begin
    gvOnlineProbed := True;
    lvClient := TbpHttpClient.Create;
    try
      lvClient.ConnectTimeout := 5000;
      lvClient.ReceiveTimeout := 5000;
      try
        gvOnlineAvailable := BpHttpResponseIsSuccess(lvClient.Get(gcTlsUrl));
      except
        gvOnlineAvailable := False;
      end;
    finally
      lvClient.Free;
    end;
  end;
  Result := not gvOnlineAvailable;
  if Result then
    Status('SKIPPED: no network access, integration test not executed');
end;

procedure TBpHttpsOnlineTests.TestHttpsGet;
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  if SkipIfOffline then
    Exit;
  lvClient := TbpHttpClient.Create;
  try
    // TLS via Schannel, the one thing the loopback server cannot serve
    lvResponse := lvClient.Get(gcTlsUrl);
    CheckEquals(200, lvResponse.StatusCode);
    Check(Pos('Example Domain', string(lvResponse.Body)) > 0,
      'expected page text in the body');
  finally
    lvClient.Free;
  end;
end;

initialization
  // offline unit tests always run
  RegisterTest(TBpHttpDownloadTests.Suite);
{$IFNDEF NO_INTEGRATION}
  // integration, on by default; NO_INTEGRATION gives a socket-free run
  RegisterTest(TBpHttpDownloadTaskTests.Suite);
  RegisterTest(TBpHttpsOnlineTests.Suite);
{$ENDIF}

end.
