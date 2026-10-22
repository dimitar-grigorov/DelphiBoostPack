unit BpHttpDownloadTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpHttpClient, BpMockHttpServer,
  BpTestSupport;

type
  // offline: progress math and the misuse that fails before the network
  TBpHttpDownloadTests = class(TTestCase)
  private
    FClient: TbpHttpClient;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestProgressPercent;
    procedure TestNilStreamRaisesBeforeTheNetwork;
  end;

  // streaming progress, sync and async, against the loopback server; no network
  TBpHttpDownloadWireTests = class(TBpWireTestCase)
  private
    FTask: IbpHttpTask;
    FStream: TMemoryStream;
    FProgressCount: Integer;
    FMonotonic: Boolean;
    FLastReceived: Int64;
    FLastTotal: Int64;
    procedure HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
      var aCancel: Boolean);
    procedure HandleTaskProgress(const aTask: IbpHttpTask;
      const aReceived, aTotal: Int64);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStreamingDownloadReportsTheTotal;
    procedure TestProgressPostsCoalesce;
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

  gcBurst = 65536;
  gcBigBody = 1048576;
  gcReadBuffer = 65536;  // BpHttpClient's download buffer, mirrored to count reads

var
  gvOnlineProbed: Boolean = False;
  gvOnlineAvailable: Boolean = False;

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

// a misconfigured call fails at once and names the mistake, never as a cancel
procedure TBpHttpDownloadTests.TestNilStreamRaisesBeforeTheNetwork;
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

  try
    FClient.BeginDownload(gcUnreachableUrl, nil, nil);
    Fail('expected EbpHttpClient for nil stream, async');
  except
    on EbpHttpClient do
      ; // expected
  end;
end;

{ TBpHttpDownloadWireTests }

procedure TBpHttpDownloadWireTests.SetUp;
begin
  inherited;
  FStream := TMemoryStream.Create;
  FMonotonic := True;
  FLastTotal := -1;
end;

procedure TBpHttpDownloadWireTests.TearDown;
begin
  FTask := nil;  // before the stream it writes to
  FreeAndNil(FStream);
  inherited;
end;

procedure TBpHttpDownloadWireTests.HandleProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  Inc(FProgressCount);
  if aReceived < FLastReceived then
    FMonotonic := False;
  FLastReceived := aReceived;
  FLastTotal := aTotal;
end;

procedure TBpHttpDownloadWireTests.HandleTaskProgress(const aTask: IbpHttpTask;
  const aReceived, aTotal: Int64);
var
  lvCancel: Boolean;
begin
  lvCancel := False;
  HandleProgress(nil, aReceived, aTotal, lvCancel);
end;

procedure TBpHttpDownloadWireTests.TestStreamingDownloadReportsTheTotal;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockOk(BpRepeated($41, gcBurst)));
  lvResponse := FClient.Download(Url('/payload.bin'), FStream, HandleProgress);
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals(gcBurst, FStream.Size, 'every byte lands in the stream');
  Check(FLastTotal = gcBurst, 'progress reports the total from Content-Length');
  Check(FLastReceived = gcBurst, 'the final tick equals the size');
  Check(FProgressCount >= 2, 'expected the initial tick and at least one more');
  CheckTrue(FMonotonic, 'the received counter never goes backwards');
  CheckEquals('', string(lvResponse.Body), 'a streamed body stays empty');
end;

// the worker samples once per read, so the queue must not grow with the body
procedure TBpHttpDownloadWireTests.TestProgressPostsCoalesce;
var
  lvReads: Integer;
begin
  FServer.Enqueue(BpMockOk(BpRepeated($41, gcBigBody)));
  FTask := FClient.BeginDownload(Url('/big.bin'), FStream, nil, HandleTaskProgress);

  // WaitFor does not pump, so every sample taken here had to collapse into one
  CheckTrue(FTask.WaitFor(30000), 'the worker must finish');
  Check(FTask.Received = gcBigBody, 'the whole body arrived');
  lvReads := gcBigBody div gcReadBuffer;
  Check(lvReads >= 16, 'the body must be big enough to need many reads');
  BpPumpMessages;
  CheckEquals(1, FProgressCount,
    Format('%d samples had to collapse into one event', [lvReads]));
  Check(FLastReceived = gcBigBody, 'the one event carries the newest count');
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
  RegisterTest(TBpHttpDownloadWireTests.Suite);
  RegisterTest(TBpHttpsOnlineTests.Suite);
{$ENDIF}

end.
