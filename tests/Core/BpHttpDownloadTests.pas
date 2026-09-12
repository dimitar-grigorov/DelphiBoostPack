unit BpHttpDownloadTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpHttpClient;

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
    procedure TestDownloadToFileDeletesFileOnPreCancelledToken;
    procedure TestTaskInitialState;
    procedure TestTaskStartValidation;
    procedure TestTaskInvalidUrlFails;
    procedure TestTaskCancelBeforeStart;
    procedure TestDownloadAsyncFactory;
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

implementation

const
  // this endpoint returns exactly the requested byte count, so progress is exact
  gcProbeUrl = 'https://speed.cloudflare.com/__down?bytes=16';
  gcSmallUrl = 'https://speed.cloudflare.com/__down?bytes=65536';
  gcMediumUrl = 'https://speed.cloudflare.com/__down?bytes=262144';
  gcHtmlUrl = 'https://example.com/';
  gcNotFoundUrl = 'https://example.com/definitely-not-here-404';

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

initialization
  // offline unit tests always run
  RegisterTest(TBpHttpDownloadTests.Suite);
{$IFNDEF NO_INTEGRATION}
  // integration, on by default; NO_INTEGRATION gives a socket-free run
  RegisterTest(TBpHttpDownloadOnlineTests.Suite);
{$ENDIF}

end.
