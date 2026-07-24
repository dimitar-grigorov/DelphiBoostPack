unit BpHttpDownloadTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, WinSock, BpHttpClient;

type
  // offline tests: progress math, header parsing, error classification,
  // argument validation and the task state machine (no network access)
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

  // mid-flight cancellation tests against a loopback HTTP server that sends
  // a burst and then dribbles: deterministic, no network needed, and the
  // abort happens while WinInet is genuinely blocked in a read
  TBpHttpDownloadCancelTests = class(TTestCase)
  private
    FClient: TbpHttpClient;
    FServer: TSlowHttpServer;
    FCancelAtFirstData: Boolean;
    FCompleteFired: Boolean;
    FErrorFired: Boolean;
    function ServerUrl: string;
    procedure HandleProgress(ASender: TObject; const AReceived, ATotal: Int64;
      var ACancel: Boolean);
    procedure HandleComplete(ASender: TObject);
    procedure HandleError(ASender: TObject; const AErrorMessage: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSyncCancelViaProgressCallback;
    procedure TestAsyncCancelMidFlight;
  end;

  // integration tests against stable public endpoints; each test is skipped
  // (with a status note) when the network probe fails, so the suite stays
  // green offline
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
    procedure HandleProgress(ASender: TObject; const AReceived, ATotal: Int64;
      var ACancel: Boolean);
    procedure HandleComplete(ASender: TObject);
    procedure HandleError(ASender: TObject; const AErrorMessage: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHttpsGet;
    procedure TestStreamingDownloadWithProgress;
    procedure TestDownloadToFileKeepsGoodDeletesBad;
    procedure TestAsyncDownloadCompletes;
  end;

  // one-client-at-a-time HTTP server on 127.0.0.1: replies 200 with a large
  // Content-Length, sends an initial burst, then dribbles small packets
  // until the client disconnects or Shutdown is called
  TSlowHttpServer = class(TThread)
  private
    FListenSocket: TSocket;
    FPort: Integer;
    procedure ServeClient(AClient: TSocket);
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
  // Cloudflare's speed-test endpoint returns exactly the requested number of
  // bytes with a Content-Length header, which makes progress checks exact
  gcProbeUrl = 'https://speed.cloudflare.com/__down?bytes=16';
  gcSmallUrl = 'https://speed.cloudflare.com/__down?bytes=65536';
  gcMediumUrl = 'https://speed.cloudflare.com/__down?bytes=262144';
  gcHtmlUrl = 'https://example.com/';
  gcNotFoundUrl = 'https://example.com/definitely-not-here-404';

  gcServerClaimedTotal = 10485760;  // Content-Length the slow server advertises
  gcServerBurst = 65536;            // bytes sent immediately after the header

var
  gvOnlineProbed: Boolean = False;
  gvOnlineAvailable: Boolean = False;

function TempFilePath(const AName: string): string;
var
  lvBuffer: array[0..MAX_PATH] of Char;
begin
  GetTempPath(MAX_PATH, lvBuffer);
  Result := IncludeTrailingPathDelimiter(lvBuffer) + AName;
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

procedure TSlowHttpServer.ServeClient(AClient: TSocket);
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
  lvLen := recv(AClient, lvRequest, SizeOf(lvRequest), 0);
  if lvLen <= 0 then
    Exit;

  if send(AClient, PAnsiChar(lcHeader)^, Length(lcHeader), 0) = SOCKET_ERROR then
    Exit;

  // burst so the client sees progress fast, then dribble so it stays
  // mid-transfer long enough for a cancel to land while a read blocks
  FillChar(lvBurst, SizeOf(lvBurst), $42);
  if send(AClient, lvBurst, SizeOf(lvBurst), 0) = SOCKET_ERROR then
    Exit;

  FillChar(lvDribble, SizeOf(lvDribble), $42);
  while not Terminated do
  begin
    if send(AClient, lvDribble, SizeOf(lvDribble), 0) = SOCKET_ERROR then
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
begin
  Check(BpHttpContentLength(lcHeaders) = 262144, 'plain value');
  // > 4 GB stays exact in Int64
  Check(BpHttpContentLength(lcHuge) = Int64(5) * 1024 * 1024 * 1024, '5 GB value');
  Check(BpHttpContentLength(lcChunked) = -1, 'absent header yields -1');
  Check(BpHttpContentLength(lcJunk) = -1, 'garbage yields -1');
  Check(BpHttpContentLength(lcNegative) = -1, 'negative yields -1');
  Check(BpHttpContentLength('') = -1, 'empty block yields -1');
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
  // hot task: created, wired and already started; an unparsable url makes
  // it fail fast without touching the network
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

procedure TBpHttpDownloadCancelTests.HandleProgress(ASender: TObject;
  const AReceived, ATotal: Int64; var ACancel: Boolean);
begin
  if FCancelAtFirstData and (AReceived > 0) then
    ACancel := True;
end;

procedure TBpHttpDownloadCancelTests.HandleComplete(ASender: TObject);
begin
  FCompleteFired := True;
end;

procedure TBpHttpDownloadCancelTests.HandleError(ASender: TObject;
  const AErrorMessage: string);
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

    // wait for the first bytes, then cancel from this thread; the token
    // closes the WinInet handle, so the abort is prompt even while the
    // worker sits in a blocked read waiting for the server's dribble
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

procedure TBpHttpDownloadOnlineTests.HandleProgress(ASender: TObject;
  const AReceived, ATotal: Int64; var ACancel: Boolean);
begin
  Inc(FProgressCalls);
  if AReceived < FLastReceived then
    FMonotonic := False;
  FLastReceived := AReceived;
  FLastTotal := ATotal;
end;

procedure TBpHttpDownloadOnlineTests.HandleComplete(ASender: TObject);
begin
  FCompleteFired := True;
end;

procedure TBpHttpDownloadOnlineTests.HandleError(ASender: TObject;
  const AErrorMessage: string);
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

initialization
  RegisterTest(TBpHttpDownloadTests.Suite);
  RegisterTest(TBpHttpDownloadCancelTests.Suite);
  RegisterTest(TBpHttpDownloadOnlineTests.Suite);

end.
