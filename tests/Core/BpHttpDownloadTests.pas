unit BpHttpDownloadTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, WinSock, BpHttpClient, BpHttpTrace;

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
    procedure TestClassifyCancelledError;
    procedure TestDownloadRejectsNilStream;
    procedure TestDownloadHonoursPreCancelledToken;
    procedure TestDownloadToFileDeletesFileOnPreCancelledToken;
    procedure TestTaskInitialState;
    procedure TestTaskStartValidation;
    procedure TestTaskInvalidUrlFails;
    procedure TestTaskCancelBeforeStart;
    procedure TestDownloadAsyncFactory;
  end;

  TSlowHttpServer = class;
  TShortBodyHttpServer = class;

  // mid-flight cancellation against a loopback server that bursts then dribbles,
  // so the abort lands while WinInet is genuinely blocked in a read
  TBpHttpDownloadCancelTests = class(TTestCase)
  private
    FClient: TbpHttpClient;
    FServer: TSlowHttpServer;
    FCancelAtFirstData: Boolean;
    FCompleteFired: Boolean;
    FErrorFired: Boolean;
    function ServerUrl: string;
    procedure HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
      var aCancel: Boolean);
    procedure HandleComplete(aSender: TObject);
    procedure HandleError(aSender: TObject; const aErrorMessage: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSyncCancelViaProgressCallback;
    procedure TestSyncRequestCancelMidFlight;
    procedure TestAsyncCancelMidFlight;
    procedure TestTraceSinkSeesTheWire;
  end;

  // a server that under-delivers: the body stops early but the socket closes cleanly
  TBpHttpShortBodyTests = class(TTestCase)
  private
    FClient: TbpHttpClient;
    FServer: TShortBodyHttpServer;
    function ServerUrl: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestShortBodyToStreamFails;
    procedure TestShortBodyLeavesNoFile;
  end;

  // integration against public endpoints, skipped with a status note when offline
  TBpHttpDownloadOnlineTests = class(TTestCase)
  private
    FClient: TbpHttpClient;
    FProgressCalls: Integer;
    FLastReceived: Int64;
    FLastTotal: Int64;
    FMonotonic: Boolean;
    FCompleteFired: Boolean;
    FErrorFired: Boolean;
    function SkipIfOffline: Boolean;
    procedure HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
      var aCancel: Boolean);
    procedure HandleComplete(aSender: TObject);
    procedure HandleError(aSender: TObject; const aErrorMessage: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHttpsGet;
    procedure TestStreamingDownloadWithProgress;
    procedure TestDownloadToFileKeepsGoodDeletesBad;
    procedure TestAsyncDownloadCompletes;
  end;

  // one-client-at-a-time server on 127.0.0.1: a large Content-Length, a burst,
  // then dribbles until the client disconnects or Shutdown is called
  TSlowHttpServer = class(TThread)
  private
    FListenSocket: TSocket;
    FPort: Integer;
    procedure ServeClient(aClient: TSocket);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Shutdown;
    property Port: Integer read FPort;
  end;

  // announces gcShortClaimed bytes, sends gcShortSent and closes
  TShortBodyHttpServer = class(TThread)
  private
    FListenSocket: TSocket;
    FPort: Integer;
    procedure ServeClient(aClient: TSocket);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Shutdown;
    property Port: Integer read FPort;
  end;

implementation

const
  // this endpoint returns exactly the requested byte count, so progress is exact
  gcProbeUrl = 'https://speed.cloudflare.com/__down?bytes=16';
  gcSmallUrl = 'https://speed.cloudflare.com/__down?bytes=65536';
  gcMediumUrl = 'https://speed.cloudflare.com/__down?bytes=262144';
  gcHtmlUrl = 'https://example.com/';
  gcNotFoundUrl = 'https://example.com/definitely-not-here-404';

  gcServerClaimedTotal = 10485760;  // Content-Length the slow server advertises
  gcServerBurst = 65536;            // bytes sent immediately after the header

  gcShortClaimed = 1000;            // Content-Length the short server advertises
  gcShortSent = 500;                // what it actually delivers before closing

var
  gvOnlineProbed: Boolean = False;
  gvOnlineAvailable: Boolean = False;

function TempFilePath(const aName: string): string;
var
  lvBuffer: array[0..MAX_PATH] of Char;
begin
  GetTempPath(MAX_PATH, lvBuffer);
  Result := IncludeTrailingPathDelimiter(lvBuffer) + aName;
end;

var
  // the sink is a bare procedure, so the log is unit level
  gvTraceLog: string;

procedure CollectTraceLine(aHandle: Pointer; const aLine: string);
begin
  gvTraceLog := gvTraceLog + aLine + #13#10;
end;

type
  // cancels a token after a delay, from outside the blocked call
  TDelayedCancelThread = class(TThread)
  private
    FToken: TbpCancellationToken;
    FDelayMs: Cardinal;
  protected
    procedure Execute; override;
  public
    constructor Create(aToken: TbpCancellationToken; aDelayMs: Cardinal);
  end;

constructor TDelayedCancelThread.Create(aToken: TbpCancellationToken;
  aDelayMs: Cardinal);
begin
  FToken := aToken;
  FDelayMs := aDelayMs;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TDelayedCancelThread.Execute;
begin
  Sleep(FDelayMs);
  FToken.Cancel;
end;

{ TSlowHttpServer }

constructor TSlowHttpServer.Create;
var
  lvWsaData: TWSAData;
  lvAddr: TSockAddrIn;
  lvAddrLen: Integer;
begin
  if WSAStartup($0202, lvWsaData) <> 0 then
    raise Exception.Create('WSAStartup failed');

  FListenSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FListenSocket = INVALID_SOCKET then
    raise Exception.Create('socket() failed');

  FillChar(lvAddr, SizeOf(lvAddr), 0);
  lvAddr.sin_family := AF_INET;
  lvAddr.sin_port := htons(0);  // ephemeral port
  lvAddr.sin_addr.S_addr := inet_addr('127.0.0.1');
  if bind(FListenSocket, TSockAddr(lvAddr), SizeOf(lvAddr)) <> 0 then
    raise Exception.Create('bind() failed');
  if listen(FListenSocket, 1) <> 0 then
    raise Exception.Create('listen() failed');

  lvAddrLen := SizeOf(lvAddr);
  if getsockname(FListenSocket, TSockAddr(lvAddr), lvAddrLen) <> 0 then
    raise Exception.Create('getsockname() failed');
  FPort := ntohs(lvAddr.sin_port);

  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TSlowHttpServer.Destroy;
begin
  Shutdown;
  inherited;  // TThread.Destroy joins the thread
  WSACleanup;
end;

procedure TSlowHttpServer.Shutdown;
begin
  Terminate;
  // closing the listener unblocks a pending accept in Execute
  if FListenSocket <> INVALID_SOCKET then
  begin
    closesocket(FListenSocket);
    FListenSocket := INVALID_SOCKET;
  end;
end;

procedure TSlowHttpServer.Execute;
var
  lvClient: TSocket;
begin
  while not Terminated do
  begin
    lvClient := accept(FListenSocket, nil, nil);
    if lvClient = INVALID_SOCKET then
      Break;  // listener closed by Shutdown
    try
      ServeClient(lvClient);
    finally
      closesocket(lvClient);
    end;
  end;
end;

procedure TSlowHttpServer.ServeClient(aClient: TSocket);
const
  lcHeader: AnsiString = 'HTTP/1.1 200 OK'#13#10 +
    'Content-Type: application/octet-stream'#13#10 +
    'Content-Length: 10485760'#13#10 +   // = gcServerClaimedTotal
    'Connection: close'#13#10#13#10;
var
  lvRequest: array[0..4095] of AnsiChar;
  lvBurst: array[0..gcServerBurst - 1] of Byte;
  lvDribble: array[0..511] of Byte;
  lvLen: Integer;
begin
  // consume the request line and headers; a GET fits one recv in practice
  lvLen := recv(aClient, lvRequest, SizeOf(lvRequest), 0);
  if lvLen <= 0 then
    Exit;

  if send(aClient, PAnsiChar(lcHeader)^, Length(lcHeader), 0) = SOCKET_ERROR then
    Exit;

  // burst so progress shows, then dribble so a cancel lands mid-read
  FillChar(lvBurst, SizeOf(lvBurst), $42);
  if send(aClient, lvBurst, SizeOf(lvBurst), 0) = SOCKET_ERROR then
    Exit;

  FillChar(lvDribble, SizeOf(lvDribble), $42);
  while not Terminated do
  begin
    if send(aClient, lvDribble, SizeOf(lvDribble), 0) = SOCKET_ERROR then
      Exit;  // client hung up (cancelled) - done with this one
    Sleep(50);
  end;
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

procedure TBpHttpDownloadTests.TestClassifyCancelledError;
begin
  CheckEquals('Operation cancelled',
    BpClassifyHttpError(gcErrOperationCancelled, 0));
end;

procedure TBpHttpDownloadTests.TestDownloadRejectsNilStream;
begin
  try
    FClient.Download('https://example.com/', nil);
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
      FClient.Download('https://example.com/', lvStream, nil, lvToken);
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

procedure TBpHttpDownloadTests.TestDownloadToFileDeletesFileOnPreCancelledToken;
var
  lvToken: TbpCancellationToken;
  lvFileName: string;
begin
  lvToken := TbpCancellationToken.Create;
  try
    lvToken.Cancel;
    lvFileName := TempFilePath('bp_download_cancelled_test.tmp');
    try
      FClient.DownloadToFile('https://example.com/', lvFileName, nil, lvToken);
      Fail('expected EbpHttpClientCancelled');
    except
      on EbpHttpClientCancelled do
        ; // expected
    end;
    CheckFalse(FileExists(lvFileName), 'partial file must be deleted');
  finally
    lvToken.Free;
  end;
end;

procedure TBpHttpDownloadTests.TestTaskInitialState;
var
  lvTask: TbpHttpDownloadTask;
begin
  lvTask := TbpHttpDownloadTask.Create(False);
  try
    Check(lvTask.State = dtsPending, 'fresh task is pending');
    Check(lvTask.Received = 0);
    Check(lvTask.Total = -1, 'total unknown before headers');
    CheckFalse(lvTask.IsFinished);
    CheckFalse(lvTask.WaitFor(0), 'a never-started task has not finished');
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

    lvTask.Url := 'https://example.com/file.bin';
    try
      lvTask.Start;
      Fail('expected raise: no destination');
    except
      on EbpHttpClient do ;
    end;

    lvTask.DestStream := lvStream;
    lvTask.DestFileName := TempFilePath('bp_task_both_dest.tmp');
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
    lvTask.Url := 'https://example.com/file.bin';
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

{ TBpHttpDownloadCancelTests }

procedure TBpHttpDownloadCancelTests.SetUp;
begin
  inherited;
  FClient := TbpHttpClient.Create;
  FServer := TSlowHttpServer.Create;
  FCancelAtFirstData := False;
  FCompleteFired := False;
  FErrorFired := False;
end;

procedure TBpHttpDownloadCancelTests.TearDown;
begin
  FServer.Free;   // Shutdown + join inside
  FClient.Free;
  inherited;
end;

function TBpHttpDownloadCancelTests.ServerUrl: string;
begin
  Result := Format('http://127.0.0.1:%d/slow.bin', [FServer.Port]);
end;

procedure TBpHttpDownloadCancelTests.HandleProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  if FCancelAtFirstData and (aReceived > 0) then
    aCancel := True;
end;

procedure TBpHttpDownloadCancelTests.HandleComplete(aSender: TObject);
begin
  FCompleteFired := True;
end;

procedure TBpHttpDownloadCancelTests.HandleError(aSender: TObject;
  const aErrorMessage: string);
begin
  FErrorFired := True;
end;

procedure TBpHttpDownloadCancelTests.TestSyncCancelViaProgressCallback;
var
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  try
    FCancelAtFirstData := True;
    try
      FClient.Download(ServerUrl, lvStream, HandleProgress);
      Fail('expected EbpHttpClientCancelled');
    except
      on E: EbpHttpClientCancelled do
        CheckEquals(gcErrOperationCancelled, E.WinInetError);
    end;
    Check(lvStream.Size > 0, 'some data arrived before the cancel');
    Check(lvStream.Size < gcServerClaimedTotal,
      'the download must not run to completion');
  finally
    lvStream.Free;
  end;
end;

// a plain Get blocked in a read must abort on a cancel from another thread
procedure TBpHttpDownloadCancelTests.TestSyncRequestCancelMidFlight;
var
  lvToken: TbpCancellationToken;
  lvCanceller: TDelayedCancelThread;
  lvStart, lvElapsed: Cardinal;
begin
  lvToken := TbpCancellationToken.Create;
  try
    // the server dribbles for minutes, so only the cancel can end this
    FClient.ReceiveTimeout := 30000;
    lvCanceller := TDelayedCancelThread.Create(lvToken, 300);
    try
      lvStart := GetTickCount;
      try
        FClient.Get(ServerUrl, '', lvToken);
        Fail('expected EbpHttpClientCancelled');
      except
        on E: EbpHttpClientCancelled do
          CheckEquals(gcErrOperationCancelled, E.WinInetError);
      end;
      lvElapsed := GetTickCount - lvStart;
      Check(lvElapsed < 10000,
        Format('cancel must not wait for the timeout, took %d ms', [lvElapsed]));
    finally
      lvCanceller.WaitFor;
      lvCanceller.Free;
    end;
  finally
    lvToken.Free;
  end;
end;

// the sink must see the phases, and nothing once detached
procedure TBpHttpDownloadCancelTests.TestTraceSinkSeesTheWire;
var
  lvStream: TMemoryStream;
  lvOffLength: Integer;
begin
  lvStream := TMemoryStream.Create;
  try
    gvTraceLog := '';
    FCancelAtFirstData := True;  // the server never ends on its own
    TbpHttpTrace.Attach(FClient, CollectTraceLine);
    try
      try
        FClient.Download(ServerUrl, lvStream, HandleProgress);
      except
        on EbpHttpClientCancelled do ; // expected
      end;
    finally
      TbpHttpTrace.Detach(FClient);
    end;

    Check(Pos('connecting to', gvTraceLog) > 0, 'connect phase: ' + gvTraceLog);
    Check(Pos('sending request', gvTraceLog) > 0, 'send phase: ' + gvTraceLog);
    Check(Pos('request sent', gvTraceLog) > 0, 'byte count: ' + gvTraceLog);
    Check(Pos('response received', gvTraceLog) > 0, 'read phase: ' + gvTraceLog);

    lvOffLength := Length(gvTraceLog);
    try
      FClient.Download(ServerUrl, lvStream, HandleProgress);
    except
      on EbpHttpClientCancelled do ;
    end;
    CheckEquals(lvOffLength, Length(gvTraceLog), 'detached must be silent');
  finally
    lvStream.Free;
  end;
end;

procedure TBpHttpDownloadCancelTests.TestAsyncCancelMidFlight;
var
  lvTask: TbpHttpDownloadTask;
  lvFileName: string;
  lvDeadline: Cardinal;
begin
  lvFileName := TempFilePath('bp_async_cancel_test.bin');
  lvTask := TbpHttpDownloadTask.Create(False);  // events on the worker thread
  try
    lvTask.Url := ServerUrl;
    lvTask.DestFileName := lvFileName;
    lvTask.OnComplete := HandleComplete;
    lvTask.OnError := HandleError;
    lvTask.Start;

    // cancel from this thread once bytes arrive; the token closes the WinInet
    // handle, so the abort is prompt even inside a blocked read
    lvDeadline := GetTickCount + 15000;
    while (lvTask.Received = 0) and not lvTask.IsFinished and
      (GetTickCount < lvDeadline) do
      Sleep(10);
    Check(lvTask.Received > 0,
      'no data arrived to cancel mid-flight: ' + lvTask.ErrorMessage);
    lvTask.Cancel;

    CheckTrue(lvTask.WaitFor(10000), 'cancel must unwind promptly');
    Check(lvTask.State = dtsCancelled,
      'expected cancelled, got: ' + lvTask.ErrorMessage);
    CheckEquals(gcErrOperationCancelled, lvTask.ErrorCode);
    CheckFalse(FileExists(lvFileName), 'cancelled download deletes the partial file');
    CheckTrue(FCompleteFired, 'OnComplete fires on every terminal state');
    CheckFalse(FErrorFired, 'cancellation is not an error');
  finally
    lvTask.Free;
    SysUtils.DeleteFile(lvFileName);
  end;
end;

{ TBpHttpDownloadOnlineTests }

procedure TBpHttpDownloadOnlineTests.SetUp;
begin
  inherited;
  FClient := TbpHttpClient.Create;
  FProgressCalls := 0;
  FLastReceived := 0;
  FLastTotal := -1;
  FMonotonic := True;
  FCompleteFired := False;
  FErrorFired := False;
end;

procedure TBpHttpDownloadOnlineTests.TearDown;
begin
  FClient.Free;
  inherited;
end;

function TBpHttpDownloadOnlineTests.SkipIfOffline: Boolean;
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  if not gvOnlineProbed then
  begin
    gvOnlineProbed := True;
    lvClient := TbpHttpClient.Create;
    try
      lvClient.ConnectTimeout := 5000;
      lvClient.ReceiveTimeout := 5000;
      try
        lvResponse := lvClient.Get(gcProbeUrl);
        gvOnlineAvailable := BpHttpResponseIsSuccess(lvResponse);
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

procedure TBpHttpDownloadOnlineTests.HandleProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  Inc(FProgressCalls);
  if aReceived < FLastReceived then
    FMonotonic := False;
  FLastReceived := aReceived;
  FLastTotal := aTotal;
end;

procedure TBpHttpDownloadOnlineTests.HandleComplete(aSender: TObject);
begin
  FCompleteFired := True;
end;

procedure TBpHttpDownloadOnlineTests.HandleError(aSender: TObject;
  const aErrorMessage: string);
begin
  FErrorFired := True;
end;

procedure TBpHttpDownloadOnlineTests.TestHttpsGet;
var
  lvResponse: TbpHttpResponse;
begin
  if SkipIfOffline then
    Exit;
  // TLS via Schannel, no OpenSSL anywhere near this
  lvResponse := FClient.Get(gcHtmlUrl);
  CheckEquals(200, lvResponse.StatusCode);
  Check(Pos('Example Domain', string(lvResponse.Body)) > 0,
    'expected page text in the body');
end;

procedure TBpHttpDownloadOnlineTests.TestStreamingDownloadWithProgress;
var
  lvStream: TMemoryStream;
  lvResponse: TbpHttpResponse;
begin
  if SkipIfOffline then
    Exit;
  lvStream := TMemoryStream.Create;
  try
    lvResponse := FClient.Download(gcMediumUrl, lvStream, HandleProgress);
    CheckEquals(200, lvResponse.StatusCode);
    CheckEquals('', string(lvResponse.Body), 'streamed response keeps Body empty');
    Check(lvResponse.ContentLength = 262144, 'Content-Length parsed');
    Check(lvStream.Size = 262144, 'every byte lands in the stream');
    Check(FLastTotal = 262144, 'progress reports the total');
    Check(FLastReceived = 262144, 'final progress equals the size');
    Check(FProgressCalls >= 2, 'expected the initial and at least one data tick');
    CheckTrue(FMonotonic, 'received counter never goes backwards');
  finally
    lvStream.Free;
  end;
end;

procedure TBpHttpDownloadOnlineTests.TestDownloadToFileKeepsGoodDeletesBad;
var
  lvFileName: string;
  lvResponse: TbpHttpResponse;
begin
  if SkipIfOffline then
    Exit;
  lvFileName := TempFilePath('bp_download_ok_test.bin');
  try
    lvResponse := FClient.DownloadToFile(gcSmallUrl, lvFileName);
    CheckEquals(200, lvResponse.StatusCode);
    CheckTrue(FileExists(lvFileName), 'successful download keeps the file');
  finally
    SysUtils.DeleteFile(lvFileName);
  end;

  // a 404 body must not survive pretending to be the payload
  lvFileName := TempFilePath('bp_download_404_test.bin');
  lvResponse := FClient.DownloadToFile(gcNotFoundUrl, lvFileName);
  CheckEquals(404, lvResponse.StatusCode);
  CheckFalse(FileExists(lvFileName), 'non-2xx download deletes the file');
end;

procedure TBpHttpDownloadOnlineTests.TestAsyncDownloadCompletes;
var
  lvTask: TbpHttpDownloadTask;
  lvStream: TMemoryStream;
begin
  if SkipIfOffline then
    Exit;
  lvStream := TMemoryStream.Create;
  lvTask := TbpHttpDownloadTask.Create(False);  // events on the worker thread
  try
    lvTask.Url := gcSmallUrl;
    lvTask.DestStream := lvStream;
    lvTask.OnProgress := HandleProgress;
    lvTask.OnComplete := HandleComplete;
    lvTask.OnError := HandleError;
    lvTask.Start;
    CheckFalse(lvTask.MarshalToMainThread);
    CheckTrue(lvTask.WaitFor(30000), 'download must finish within 30s');
    Check(lvTask.State = dtsSucceeded, 'expected success, got: ' + lvTask.ErrorMessage);
    Check(lvStream.Size = 65536, 'every byte lands in the stream');
    Check(lvTask.Received = 65536);
    Check(lvTask.Total = 65536);
    CheckEquals(200, lvTask.Response.StatusCode);
    CheckTrue(FCompleteFired, 'OnComplete must fire');
    CheckFalse(FErrorFired, 'OnError must not fire on success');
    CheckTrue(FMonotonic);
  finally
    lvTask.Free;
    lvStream.Free;
  end;
end;


constructor TShortBodyHttpServer.Create;
var
  lvWsaData: TWSAData;
  lvAddr: TSockAddrIn;
  lvAddrLen: Integer;
begin
  if WSAStartup($0202, lvWsaData) <> 0 then
    raise Exception.Create('WSAStartup failed');
  FListenSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FListenSocket = INVALID_SOCKET then
    raise Exception.Create('socket() failed');
  FillChar(lvAddr, SizeOf(lvAddr), 0);
  lvAddr.sin_family := AF_INET;
  lvAddr.sin_port := htons(0);
  lvAddr.sin_addr.S_addr := inet_addr('127.0.0.1');
  if bind(FListenSocket, TSockAddr(lvAddr), SizeOf(lvAddr)) <> 0 then
    raise Exception.Create('bind() failed');
  if listen(FListenSocket, 1) <> 0 then
    raise Exception.Create('listen() failed');
  lvAddrLen := SizeOf(lvAddr);
  if getsockname(FListenSocket, TSockAddr(lvAddr), lvAddrLen) <> 0 then
    raise Exception.Create('getsockname() failed');
  FPort := ntohs(lvAddr.sin_port);
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TShortBodyHttpServer.Destroy;
begin
  Shutdown;
  inherited Destroy;
  WSACleanup;
end;

procedure TShortBodyHttpServer.Shutdown;
begin
  Terminate;
  if FListenSocket <> INVALID_SOCKET then
  begin
    closesocket(FListenSocket);
    FListenSocket := INVALID_SOCKET;
  end;
end;

procedure TShortBodyHttpServer.Execute;
var
  lvClient: TSocket;
begin
  while not Terminated do
  begin
    lvClient := accept(FListenSocket, nil, nil);
    if lvClient = INVALID_SOCKET then
      Break;
    try
      ServeClient(lvClient);
    finally
      closesocket(lvClient);
    end;
  end;
end;

procedure TShortBodyHttpServer.ServeClient(aClient: TSocket);
const
  lcHeader: AnsiString = 'HTTP/1.1 200 OK'#13#10 +
    'Content-Type: application/octet-stream'#13#10 +
    'Content-Length: 1000'#13#10 +      // = gcShortClaimed
    'Connection: close'#13#10#13#10;
var
  lvRequest: array[0..4095] of AnsiChar;
  lvBody: array[0..gcShortSent - 1] of Byte;
  lvLen: Integer;
begin
  lvLen := recv(aClient, lvRequest, SizeOf(lvRequest), 0);
  if lvLen <= 0 then
    Exit;
  if send(aClient, PAnsiChar(lcHeader)^, Length(lcHeader), 0) = SOCKET_ERROR then
    Exit;
  FillChar(lvBody, SizeOf(lvBody), $41);
  send(aClient, lvBody, SizeOf(lvBody), 0);
  // and close without the remaining bytes
end;

procedure TBpHttpShortBodyTests.SetUp;
begin
  inherited;
  FServer := TShortBodyHttpServer.Create;
  FClient := TbpHttpClient.Create;
  FClient.ReceiveTimeout := 5000;
end;

procedure TBpHttpShortBodyTests.TearDown;
begin
  FreeAndNil(FClient);
  if FServer <> nil then
  begin
    FServer.Shutdown;
    FServer.WaitFor;
    FreeAndNil(FServer);
  end;
  inherited;
end;

function TBpHttpShortBodyTests.ServerUrl: string;
begin
  Result := Format('http://127.0.0.1:%d/short', [FServer.Port]);
end;

procedure TBpHttpShortBodyTests.TestShortBodyToStreamFails;
var
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  try
    try
      FClient.Download(ServerUrl, lvStream);
      Fail('a body shorter than Content-Length must not be reported as success');
    except
      on E: EbpHttpClient do
        Check(Pos('Incomplete', E.Message) > 0,
          'the error must say the response was incomplete, got: ' + E.Message);
    end;
  finally
    lvStream.Free;
  end;
end;

procedure TBpHttpShortBodyTests.TestShortBodyLeavesNoFile;
var
  lvFileName: string;
begin
  lvFileName := TempFilePath('BpShortBody.tmp');
  if FileExists(lvFileName) then
    SysUtils.DeleteFile(lvFileName);
  try
    FClient.DownloadToFile(ServerUrl, lvFileName);
    Fail('a truncated download must not be reported as success');
  except
    on E: EbpHttpClient do
      Check(not FileExists(lvFileName),
        'the partial file must not be left behind');
  end;
  if FileExists(lvFileName) then
    SysUtils.DeleteFile(lvFileName);
end;

initialization
  // offline unit tests always run
  RegisterTest(TBpHttpDownloadTests.Suite);
{$IFNDEF NO_INTEGRATION}
  // integration, on by default; NO_INTEGRATION gives a socket-free run
  RegisterTest(TBpHttpDownloadCancelTests.Suite);
  RegisterTest(TBpHttpShortBodyTests.Suite);
  RegisterTest(TBpHttpDownloadOnlineTests.Suite);
{$ENDIF}

end.
