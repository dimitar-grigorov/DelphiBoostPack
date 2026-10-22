unit BpHttpWireTests;

// TbpHttpClient against real bytes on a socket, served by BpMockHttpServer.
// Everything here asserts on what the client actually put on the wire and on
// what it made of the reply, which no pure-function test of a helper can show.

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpHttpClient, BpHttpTrace,
  BpMockHttpServer, BpTestSupport;

type
  TBpHttpVerbTests = class(TBpWireTestCase)
  published
    procedure TestGetReachesTheServer;
    procedure TestBodyVerbsSendTheBody;
    procedure TestBodylessVerbsSendNone;
    procedure TestFetchUrlRaisesOnAnErrorStatus;
  end;

  TBpHttpHeaderWireTests = class(TBpWireTestCase)
  private
    function SentAuthorization(const aUrl: string): string;
  published
    procedure TestPersistentHeaderIsOneLine;
    procedure TestPerRequestHeaderReplacesPersistent;
    procedure TestAuthorizationHasOneWriter;
    procedure TestUrlCredentialsBecomeBasicAuth;
    procedure TestServerCookiesAreNotStored;
    procedure TestUsernameAndPasswordAnswerAChallenge;
  end;

  TBpHttpBodyWireTests = class(TBpWireTestCase)
  published
    procedure TestChunkedResponseIsBuffered;
    procedure TestRepliesWithoutABody;
    procedure TestShortBodyFails;
    procedure TestNoResponseAtAllIsAnError;
    procedure TestMaxResponseBytesStopsABigBody;
  end;

  // only a 2xx may touch the destination, and no path may leave a temp file
  TBpHttpDownloadToFileTests = class(TBpWireTestCase)
  private
    FDir: string;
    FDest: string;
    procedure CheckSurvived(const aWhat: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSuccessWritesTheFile;
    procedure TestEveryFailureLeavesTheFileAlone;
    procedure TestCancelLeavesTheFileAlone;
  end;

  TBpHttpGzipTests = class(TBpWireTestCase)
  published
    procedure TestGzipIsDecoded;
    procedure TestNoAcceptEncodingWhenDecompressionIsOff;
  end;

  TBpHttpRedirectWireTests = class(TBpWireTestCase)
  published
    procedure TestChainIsFollowedOnOneConnection;
    procedure TestPostBecomesGetOn301And302;
    procedure Test307And308KeepMethodAndBody;
    procedure TestRedirectIsReturnedWhenNotFollowed;
    procedure TestMaxRedirectsExceededRaises;
    procedure TestDownloadFollowsARedirect;
  end;

  // two servers, because two ports on 127.0.0.1 are already two origins
  TBpHttpRedirectCredentialTests = class(TBpWireTestCase)
  private
    FOther: TbpMockHttpServer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCrossOriginRedirectDropsEverySecret;
    procedure TestUrlCredentialsDoNotCrossOrigins;
    procedure TestSameOriginRedirectKeepsThem;
  end;

  // cancellation and timeouts against a server that answers and then goes quiet
  TBpHttpCancelWireTests = class(TBpWireTestCase)
  private
    procedure CancelAtFirstData(aSender: TObject; const aReceived, aTotal: Int64;
      var aCancel: Boolean);
  published
    procedure TestSyncCancelViaProgressCallback;
    procedure TestSyncRequestCancelMidFlight;
    procedure TestTraceFollowsEachRequestOfItsClient;
    procedure TestDetachWaitsForASinkInFlight;
    procedure TestFailureNamesTheCallAndTheHost;
    procedure TestReceiveTimeoutFiresOnAStall;
    procedure TestTimeoutEndsTheWholeCall;
  end;

  // Begin* and the lifetimes around it: the task, its client, a form holding both
  TBpHttpTaskWireTests = class(TBpWireTestCase)
  private
    FTask: IbpHttpTask;
    FDoneCount: Integer;
    FDoneThread: Cardinal;
    FDoneState: TbpHttpTaskState;
    FDoneBody: AnsiString;
    FArmed: Boolean;
    FReleasedInProgress: Boolean;
    procedure StartSlowDownload(aDest: TStream;
      aOnProgress: TbpHttpTaskProgressEvent);
    procedure HandleDone(const aTask: IbpHttpTask);
    procedure ReleaseOnProgress(const aTask: IbpHttpTask;
      const aReceived, aTotal: Int64);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBeginGetAnswersLikeTheSyncCall;
    procedure TestReleasingTheTaskCancelsIt;
    procedure TestReleaseInsideAWorkerEventIsDeferred;
    procedure TestFreeingTheClientEndsEveryCallInFlight;
  end;

implementation

const
  gcSlowClaimed = 10485760;  // Content-Length the stalling reply advertises
  gcSlowBurst = 65536;       // what it really sends before going quiet

  gcGzipPlain = 'The quick brown fox jumps over the lazy dog. ' +
    'The quick brown fox jumps over the lazy dog. ' +
    'The quick brown fox jumps over the lazy dog. ' +
    'The quick brown fox jumps over the lazy dog. ' +
    'The quick brown fox jumps over the lazy dog. ' +
    'The quick brown fox jumps over the lazy dog. ';

  // gzip of gcGzipPlain, made once with Python 3; there is no compressor here
  gcGzipBytes: array[0..66] of Byte = (
    $1F, $8B, $08, $00, $00, $00, $00, $00, $02, $FF, $0B, $C9, $48, $55,
    $28, $2C, $CD, $4C, $CE, $56, $48, $2A, $CA, $2F, $CF, $53, $48, $CB,
    $AF, $50, $C8, $2A, $CD, $2D, $28, $56, $C8, $2F, $4B, $2D, $52, $28,
    $01, $4A, $E7, $24, $56, $55, $2A, $A4, $E4, $A7, $EB, $29, $84, $0C,
    $77, $C5, $00, $B5, $95, $B8, $F8, $0E, $01, $00, $00
  );

type
  // a Get on its own thread, for a Detach or a Free across it
  TbpGetThread = class(TThread)
  private
    FClient: TbpHttpClient;
    FUrl: string;
    FErrorClass: string;  // what the Get raised, '' when it returned
  protected
    procedure Execute; override;
  public
    constructor Create(aClient: TbpHttpClient; const aUrl: string);
  end;

var
  // the trace sink is a bare procedure, so its log has to be unit level
  gvTraceLog: string;
  gvSinkHoldMs: Cardinal = 0;
  gvSinkEntered: Boolean = False;
  gvSinkLeft: Boolean = False;

procedure CollectTraceLine(aHandle: Pointer; const aLine: string);
begin
  gvTraceLog := gvTraceLog + aLine + #13#10;
end;

// holds the very first callback, so Detach has something to wait out
procedure HoldingTraceLine(aHandle: Pointer; const aLine: string);
begin
  if (gvSinkHoldMs = 0) or gvSinkEntered then
    Exit;
  gvSinkEntered := True;
  Sleep(gvSinkHoldMs);
  gvSinkLeft := True;
end;

constructor TbpGetThread.Create(aClient: TbpHttpClient; const aUrl: string);
begin
  FClient := aClient;
  FUrl := aUrl;
  inherited Create(False);
end;

procedure TbpGetThread.Execute;
begin
  try
    FClient.Get(FUrl);
  except
    on E: Exception do
      FErrorClass := E.ClassName;
  end;
end;

// a burst then silence, so a cancel lands while WinInet is blocked in a read
procedure EnqueueSlowReply(aServer: TbpMockHttpServer);
var
  lvReply: TbpMockResponse;
begin
  lvReply := BpMockOk(BpRepeated($42, gcSlowBurst));
  lvReply.Headers.Add('Content-Type: application/octet-stream');
  lvReply.ClaimedLength := gcSlowClaimed;
  lvReply.Effect := mseStall;
  aServer.Enqueue(lvReply);
end;

// the userinfo goes between the scheme and the host the mock server hands out
function WithUserInfo(const aUrl, aUserInfo: string): string;
const
  lcScheme = 'http://';
begin
  Result := lcScheme + aUserInfo + '@' + Copy(aUrl, Length(lcScheme) + 1,
    Length(aUrl));
end;

function BytesToAnsi(const aBytes: array of Byte): AnsiString;
var
  i: Integer;
begin
  SetLength(Result, Length(aBytes));
  for i := 0 to High(aBytes) do
    Result[i + 1] := AnsiChar(aBytes[i]);
end;

// how many header lines the value could have produced, counted on raw bytes
function CountOccurrences(const aText, aSub: AnsiString): Integer;
var
  lvRest: AnsiString;
  lvPos: Integer;
begin
  Result := 0;
  if aSub = '' then
    Exit;
  lvRest := aText;
  lvPos := Pos(aSub, lvRest);
  while lvPos > 0 do
  begin
    Inc(Result);
    Delete(lvRest, 1, lvPos + Length(aSub) - 1);
    lvPos := Pos(aSub, lvRest);
  end;
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

{ TBpHttpVerbTests }

procedure TBpHttpVerbTests.TestGetReachesTheServer;
var
  lvReply: TbpMockResponse;
  lvResponse: TbpHttpResponse;
  lvRequest: TbpRecordedRequest;
begin
  lvReply := BpMockOk('hello');
  lvReply.ReasonPhrase := 'Fine Indeed';  // no local table knows this one
  FServer.Enqueue(lvReply);
  lvResponse := FClient.Get(Url('/search?q=delphi&page=2'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('Fine Indeed', lvResponse.StatusText);
  CheckEquals('hello', string(lvResponse.Body));
  CheckEquals(5, lvResponse.ContentLength);
  CheckEquals(Url('/search?q=delphi&page=2'), lvResponse.FinalUrl,
    'no redirect, so the same url');

  lvRequest := NextRequest;
  CheckEquals('GET', lvRequest.Method);
  CheckEquals('/search?q=delphi&page=2', lvRequest.Path, 'the query survives');
  CheckEquals('HTTP/1.1', lvRequest.HttpVersion);
  CheckEquals('', string(lvRequest.Body));
end;

procedure TBpHttpVerbTests.TestBodyVerbsSendTheBody;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockStatus(201, 'made'));
  FServer.Enqueue(BpMockOk('{}'));
  FServer.Enqueue(BpMockOk('ok'));
  FServer.Enqueue(BpMockOk('ok'));
  CheckEquals(201, FClient.Post(Url('/items'), 'name=box').StatusCode);
  FClient.PostJson(Url('/api'), '{"a":1}');
  FClient.Put(Url('/items/7'), 'replaced');
  FClient.Patch(Url('/items/7'), '{"n":2}');

  lvRequest := NextRequest;
  CheckEquals('POST', lvRequest.Method);
  CheckEquals('name=box', string(lvRequest.Body));
  CheckEquals('8', lvRequest.HeaderValue('Content-Length'));
  lvRequest := NextRequest;
  CheckEquals('POST', lvRequest.Method);
  CheckEquals('{"a":1}', string(lvRequest.Body));
  CheckEquals('application/json', lvRequest.HeaderValue('Content-Type'));
  lvRequest := NextRequest;
  CheckEquals('PUT', lvRequest.Method);
  CheckEquals('replaced', string(lvRequest.Body));
  lvRequest := NextRequest;
  CheckEquals('PATCH', lvRequest.Method);
  CheckEquals('{"n":2}', string(lvRequest.Body));
end;

procedure TBpHttpVerbTests.TestBodylessVerbsSendNone;
var
  lvHead, lvOptions: TbpMockResponse;
  lvResponse: TbpHttpResponse;
  lvRequest: TbpRecordedRequest;
begin
  // a real HEAD reply announces what a GET would have returned and sends none
  lvHead := BpMockStatus(200);
  lvHead.ClaimedLength := 4096;
  lvOptions := BpMockStatus(204);
  lvOptions.Headers.Add('Allow: GET, POST');
  FServer.Enqueue(BpMockStatus(204));
  FServer.Enqueue(lvHead);
  FServer.Enqueue(lvOptions);

  CheckEquals(204, FClient.Delete(Url('/items/7')).StatusCode);
  lvResponse := FClient.Head(Url('/big.bin'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('', string(lvResponse.Body), 'a HEAD reply carries no body');
  CheckEquals(4096, lvResponse.ContentLength, 'the announced length is reported');
  CheckEquals('GET, POST',
    BpHttpHeaderValue(FClient.Options(Url('/api')).Headers, 'Allow'));

  lvRequest := NextRequest;
  CheckEquals('DELETE', lvRequest.Method);
  CheckEquals('', string(lvRequest.Body));
  CheckEquals('HEAD', NextRequest.Method);
  CheckEquals('OPTIONS', NextRequest.Method);
end;

// the README parses FetchUrl as JSON, so a 404 page became a parse error later
procedure TBpHttpVerbTests.TestFetchUrlRaisesOnAnErrorStatus;
begin
  FServer.Enqueue(BpMockStatus(404, '<html>not here</html>'));
  try
    TbpHttpClient.FetchUrl(Url('/missing'));
    Fail('a 404 must not come back as the body');
  except
    on E: EbpHttpClient do
    begin
      CheckEquals(404, E.StatusCode);
      Check(Pos('404', E.Message) > 0, E.Message);
    end;
  end;
end;

{ TBpHttpHeaderWireTests }

// one Get, and the one Authorization line it carried
function TBpHttpHeaderWireTests.SentAuthorization(const aUrl: string): string;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(aUrl);
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('Authorization'), 'one Authorization line');
  Result := lvRequest.HeaderValue('Authorization');
end;

procedure TBpHttpHeaderWireTests.TestPersistentHeaderIsOneLine;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.AddHeader('X-Api-Key', 'secret-value');
  FClient.AddHeader('X-Note', 'a: b, c');
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('X-Api-Key'), 'exactly one header line');
  CheckEquals('secret-value', lvRequest.HeaderValue('X-Api-Key'));
  CheckEquals(1, CountOccurrences(lvRequest.RawHead, 'secret-value'),
    'the value must appear once in the raw head');
  CheckEquals('a: b, c', lvRequest.HeaderValue('X-Note'));
  CheckEquals(0, lvRequest.HeaderCount('a'), 'a colon in the value starts no header');
end;

procedure TBpHttpHeaderWireTests.TestPerRequestHeaderReplacesPersistent;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.AddHeader('X-Scope', 'client');
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'), 'X-Scope: request');
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('X-Scope'), 'one line, not two');
  CheckEquals('request', lvRequest.HeaderValue('X-Scope'));
  CheckEquals(0, CountOccurrences(lvRequest.RawHead, 'client'),
    'the replaced value must not reach the wire');
end;

// two lines would let the server pick the one the caller did not mean
procedure TBpHttpHeaderWireTests.TestAuthorizationHasOneWriter;
begin
  FClient.BearerToken := 'tok-123';
  CheckEquals('Bearer tok-123', SentAuthorization(Url('/a')));
  FClient.AddHeader('Authorization', 'Basic AAAA');
  CheckEquals('Basic AAAA', SentAuthorization(Url('/b')),
    'an explicit header replaces the bearer');
  FClient.BearerToken := 'tok-456';
  CheckEquals('Bearer tok-456', SentAuthorization(Url('/c')),
    'and a bearer replaces an explicit header');
  FClient.SetBasicAuth('user', 'pass');
  // RFC 7617 base64 of user:pass
  CheckEquals('Basic dXNlcjpwYXNz', SentAuthorization(Url('/d')));
end;

// curl, requests, axios and .NET all send user:pass@host as Basic auth
procedure TBpHttpHeaderWireTests.TestUrlCredentialsBecomeBasicAuth;
begin
  CheckEquals('Basic dXNlcjpwYXNz',
    SentAuthorization(WithUserInfo(Url('/a'), 'user:pass')));
  // an email as the user id is the case that forces the escaping
  CheckEquals('Basic dXNAZXI6cDp3',
    SentAuthorization(WithUserInfo(Url('/b'), 'us%40er:p%3Aw')));
  // %2540 is an escaped percent sign, so it must decode exactly once
  CheckEquals('Basic JTQwOnBhc3M=',
    SentAuthorization(WithUserInfo(Url('/c'), '%2540:pass')));

  // a url carries non-ASCII as escaped UTF-8, and SetBasicAuth must send the same
  CheckEquals('Basic dXNlcjpwYcOf',
    SentAuthorization(WithUserInfo(Url('/d'), 'user:pa%C3%9F')));
  FClient.SetBasicAuth('user', WideChar('p') + WideChar('a') + WideChar($00DF));
  CheckEquals('Basic dXNlcjpwYcOf', SentAuthorization(Url('/e')),
    'url credentials and SetBasicAuth must agree');

  FClient.SetBasicAuth('real', 'secret');
  CheckEquals('Basic cmVhbDpzZWNyZXQ=',
    SentAuthorization(WithUserInfo(Url('/f'), 'user:pass')),
    'what the caller set wins over what the url carried');
end;

// the client keeps no jar, so WinInet's per-user one must not answer for it
procedure TBpHttpHeaderWireTests.TestServerCookiesAreNotStored;
var
  lvReply: TbpMockResponse;
  lvSecond: TbpRecordedRequest;
begin
  lvReply := BpMockOk('one');
  lvReply.Headers.Add('Set-Cookie: sid=abc; Path=/');
  FServer.Enqueue(lvReply);
  FServer.Enqueue(BpMockOk('two'));
  FClient.Get(Url('/first'));
  FClient.Get(Url('/second'));
  NextRequest;
  lvSecond := NextRequest;
  CheckFalse(lvSecond.HasHeader('Cookie'),
    'nothing the client did not send may come back, got: ' +
    lvSecond.HeaderValue('Cookie'));
end;

// Username/Password are WinInet-level, so only a real 401 exercises them
procedure TBpHttpHeaderWireTests.TestUsernameAndPasswordAnswerAChallenge;
var
  lvChallenge: TbpMockResponse;
  lvResponse: TbpHttpResponse;
begin
  lvChallenge := TbpMockResponse.Create(401);
  lvChallenge.Headers.Add('WWW-Authenticate: Basic realm="test"');
  FServer.Enqueue(lvChallenge);
  FServer.Enqueue(BpMockOk('in'));
  FClient.Username := 'user';
  FClient.Password := 'pass';
  lvResponse := FClient.Get(Url('/secret'));
  CheckEquals(200, lvResponse.StatusCode, 'the challenge must be answered');
  CheckFalse(NextRequest.HasHeader('Authorization'), 'the first try is unauthenticated');
  CheckEquals('Basic dXNlcjpwYXNz', NextRequest.HeaderValue('Authorization'),
    'the retry carries user:pass');
end;

{ TBpHttpBodyWireTests }

procedure TBpHttpBodyWireTests.TestChunkedResponseIsBuffered;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockChunked('one-two-three-four-five', 7));
  lvResponse := FClient.Get(Url('/chunked'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('one-two-three-four-five', string(lvResponse.Body),
    'every chunk must be reassembled');
  CheckEquals(-1, lvResponse.ContentLength, 'a chunked reply has no length');
end;

// none of these may trip the completeness check, which lives on the streaming path
procedure TBpHttpBodyWireTests.TestRepliesWithoutABody;
var
  lvHead, lvNoContent, lvNotModified: TbpMockResponse;
  lvResponse: TbpHttpResponse;
  lvStream: TMemoryStream;
begin
  lvHead := BpMockStatus(200);
  lvHead.ClaimedLength := 4096;
  lvNoContent := BpMockStatus(204);
  lvNoContent.ClaimedLength := gcMockNoContentLength;  // as a real server sends it
  lvNotModified := BpMockStatus(304);
  lvNotModified.ClaimedLength := 4096;  // a 304 repeats the length it would have sent
  lvNotModified.Effect := mseStall;     // and never sends it, so it goes last
  FServer.Enqueue(BpMockOk(''));
  FServer.Enqueue(lvHead);
  FServer.Enqueue(lvNoContent);
  FServer.Enqueue(lvNotModified);

  lvResponse := FClient.Get(Url('/empty'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('', string(lvResponse.Body));
  CheckEquals(0, lvResponse.ContentLength);

  lvStream := TMemoryStream.Create;
  try
    CheckEquals(200, FClient.Download(Url('/big.bin'), lvStream, nil, nil, '',
      'HEAD').StatusCode);
    CheckEquals(204, FClient.Download(Url('/none'), lvStream).StatusCode);
    CheckEquals(304, FClient.Download(Url('/cached'), lvStream).StatusCode);
    CheckEquals(0, lvStream.Size, 'none of them writes anything');
  finally
    lvStream.Free;
  end;
end;

// a 200 used to come back with half the body, as if nothing had happened
procedure TBpHttpBodyWireTests.TestShortBodyFails;
const
  lcCall: array[Boolean] of string = ('Download', 'Get');
var
  lvReply: TbpMockResponse;
  lvStream: TMemoryStream;
  lvBuffered: Boolean;
begin
  lvStream := TMemoryStream.Create;
  try
    for lvBuffered := True downto False do
    begin
      lvReply := BpMockOk(BpRepeated($41, 500));
      lvReply.ClaimedLength := 1000;   // announces twice what it sends
      lvReply.Effect := mseCloseAtEnd;
      FServer.Enqueue(lvReply);
      try
        if lvBuffered then
          FClient.Get(Url('/short'))
        else
          FClient.Download(Url('/short'), lvStream);
        Fail(lcCall[lvBuffered] + ': a short body must not pass as success');
      except
        on E: EbpHttpClient do
          Check(Pos('Incomplete', E.Message) > 0,
            lcCall[lvBuffered] + ' must say the response was incomplete, got: ' +
            E.Message);
      end;
    end;
  finally
    lvStream.Free;
  end;
end;

procedure TBpHttpBodyWireTests.TestNoResponseAtAllIsAnError;
var
  lvReply: TbpMockResponse;
begin
  lvReply := BpMockOk('never sent');
  lvReply.Effect := mseNoResponse;
  FServer.Enqueue(lvReply);
  try
    FClient.Get(Url('/silent'));
    Fail('a closed connection with no reply must not look like success');
  except
    on EbpHttpClientCancelled do
      Fail('a dropped connection is not a cancellation');
    on EbpHttpClient do
      ; // expected
  end;
  CheckEquals(1, FServer.RequestCount, 'the request did reach the server');
end;

// a buffered body is the one place a hostile endpoint can exhaust memory
procedure TBpHttpBodyWireTests.TestMaxResponseBytesStopsABigBody;
begin
  FServer.Enqueue(BpMockOk(BpRepeated($41, 40000)));
  FClient.MaxResponseBytes := 1024;
  try
    FClient.Get(Url('/huge.bin'));
    Fail('expected EbpHttpClient past the ceiling');
  except
    on EbpHttpClientCancelled do
      Fail('a ceiling is not a cancellation');
    on EbpHttpClient do
      ; // expected
  end;

  // and the default, no ceiling, still takes the same body whole
  FServer.Enqueue(BpMockOk(BpRepeated($41, 40000)));
  FClient.MaxResponseBytes := 0;
  CheckEquals(40000, Length(FClient.Get(Url('/huge.bin')).Body));
end;

{ TBpHttpDownloadToFileTests }

procedure TBpHttpDownloadToFileTests.SetUp;
begin
  inherited;
  FDir := BpMakeTempDir('bp_wire');
  FDest := IncludeTrailingPathDelimiter(FDir) + 'payload.bin';
  BpWriteWholeFile(FDest, 'ORIGINAL');
end;

procedure TBpHttpDownloadToFileTests.TearDown;
begin
  BpDeleteTree(FDir);
  inherited;
end;

procedure TBpHttpDownloadToFileTests.CheckSurvived(const aWhat: string);
begin
  CheckTrue(FileExists(FDest), aWhat + ': the file was removed');
  CheckEquals('ORIGINAL', string(BpReadWholeFile(FDest)),
    aWhat + ': the file was rewritten');
  CheckEquals(1, BpCountFiles(FDir), aWhat + ': a temp file was left behind');
end;

procedure TBpHttpDownloadToFileTests.TestSuccessWritesTheFile;
begin
  FServer.Enqueue(BpMockOk('REPLACED'));
  FServer.Enqueue(BpMockOk('BRAND NEW'));
  CheckEquals(200, FClient.DownloadToFile(Url('/f.bin'), FDest).StatusCode);
  CheckEquals('REPLACED', string(BpReadWholeFile(FDest)));
  CheckEquals(1, BpCountFiles(FDir), 'no temp file may survive a success');

  SysUtils.DeleteFile(FDest);
  CheckEquals(200, FClient.DownloadToFile(Url('/f.bin'), FDest).StatusCode);
  CheckEquals('BRAND NEW', string(BpReadWholeFile(FDest)), 'a missing file is created');
  CheckEquals(1, BpCountFiles(FDir));
end;

procedure TBpHttpDownloadToFileTests.TestEveryFailureLeavesTheFileAlone;
var
  lvPartial, lvTruncated: TbpMockResponse;
begin
  lvPartial := BpMockStatus(206, 'PART');
  lvPartial.Headers.Add('Content-Range: bytes 0-3/9999');
  lvTruncated := BpMockOk(BpRepeated($41, 500));
  lvTruncated.ClaimedLength := 1000;
  lvTruncated.Effect := mseCloseAtEnd;
  FServer.Enqueue(BpMockStatus(404, '<html>not here</html>'));
  FServer.Enqueue(BpMockStatus(204));
  FServer.Enqueue(lvPartial);
  FServer.Enqueue(lvTruncated);

  CheckEquals(404, FClient.DownloadToFile(Url('/gone.bin'), FDest).StatusCode);
  CheckSurvived('404');

  // a 2xx with no file in it used to empty the destination
  CheckEquals(204, FClient.DownloadToFile(Url('/empty.bin'), FDest).StatusCode);
  CheckSurvived('204');

  // nothing asked for a range, so a fragment must not become the whole file
  try
    FClient.DownloadToFile(Url('/part.bin'), FDest);
    Fail('expected EbpHttpClient for 206 Partial Content');
  except
    on E: EbpHttpClient do
      CheckEquals(206, E.StatusCode);
  end;
  CheckSurvived('206');

  try
    FClient.DownloadToFile(Url('/short.bin'), FDest);
    Fail('a truncated download must not be reported as success');
  except
    on EbpHttpClient do
      ; // expected
  end;
  CheckSurvived('truncated body');

  try
    FClient.DownloadToFile('not a url at all', FDest);
    Fail('expected EbpHttpClient for an unparsable url');
  except
    on EbpHttpClient do
      ; // expected
  end;
  CheckSurvived('unparsable url');
end;

procedure TBpHttpDownloadToFileTests.TestCancelLeavesTheFileAlone;
var
  lvReply: TbpMockResponse;
  lvToken: TbpCancellationToken;
  lvCanceller: TDelayedCancelThread;
begin
  lvReply := BpMockOk(BpRepeated($42, 65536));
  lvReply.ClaimedLength := 10485760;
  lvReply.Effect := mseStall;
  FServer.Enqueue(lvReply);

  FClient.ReceiveTimeout := 25000;
  lvToken := TbpCancellationToken.Create;
  try
    lvCanceller := TDelayedCancelThread.Create(lvToken, 300);
    try
      try
        FClient.DownloadToFile(Url('/slow.bin'), FDest, nil, lvToken);
        Fail('expected EbpHttpClientCancelled');
      except
        on EbpHttpClientCancelled do
          ; // expected
      end;
    finally
      lvCanceller.WaitFor;
      lvCanceller.Free;
    end;
  finally
    lvToken.Free;
  end;
  CheckSurvived('cancel');
end;

{ TBpHttpGzipTests }

procedure TBpHttpGzipTests.TestGzipIsDecoded;
var
  lvReply: TbpMockResponse;
  lvResponse: TbpHttpResponse;
begin
  lvReply := BpMockOk(BytesToAnsi(gcGzipBytes));
  lvReply.Headers.Add('Content-Encoding: gzip');
  FServer.Enqueue(lvReply);
  lvResponse := FClient.Get(Url('/gz'));
  CheckEquals('gzip, deflate', NextRequest.HeaderValue('Accept-Encoding'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals(gcGzipPlain, string(lvResponse.Body),
    'WinInet must hand back the decoded bytes');
  // the truncation check relies on it: no length is left to compare decoded bytes with
  CheckEquals(-1, lvResponse.ContentLength, 'WinInet drops Content-Length when it decodes');
  CheckEquals('', BpHttpHeaderValue(lvResponse.Headers, 'Content-Encoding'),
    'WinInet drops Content-Encoding when it decodes');
end;

procedure TBpHttpGzipTests.TestNoAcceptEncodingWhenDecompressionIsOff;
var
  lvReply: TbpMockResponse;
  lvRequest: TbpRecordedRequest;
  lvResponse: TbpHttpResponse;
begin
  FClient.AutoDecompress := False;
  lvReply := BpMockOk(BytesToAnsi(gcGzipBytes));
  lvReply.Headers.Add('Content-Encoding: gzip');
  FServer.Enqueue(lvReply);
  lvResponse := FClient.Get(Url('/gz'));
  lvRequest := NextRequest;
  CheckFalse(lvRequest.HasHeader('Accept-Encoding'),
    'the client must not ask for what it will not decode');
  // a server that gzips anyway hands back bytes the caller has to deal with
  CheckEquals(BytesToAnsi(gcGzipBytes), lvResponse.Body,
    'the compressed bytes come back untouched');
end;

{ TBpHttpRedirectWireTests }

// one connection for every hop is the only real proof each 3xx body was drained
procedure TBpHttpRedirectWireTests.TestChainIsFollowedOnOneConnection;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockRedirect(302, '/b'));
  FServer.Enqueue(BpMockRedirect(302, '/c'));
  FServer.Enqueue(BpMockRedirect(302, '/d'));
  FServer.Enqueue(BpMockOk('last'));
  lvResponse := FClient.Get(Url('/a'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('last', string(lvResponse.Body));
  CheckEquals(Url('/d'), lvResponse.FinalUrl, 'FinalUrl is the resolved absolute url');

  CheckEquals(4, FServer.RequestCount);
  CheckEquals(1, FServer.ConnectionCount, 'every hop shares the pooled connection');
  CheckEquals('/a', NextRequest.Path);
  CheckEquals('/b', NextRequest.Path, 'a relative Location is resolved');
  CheckEquals('/c', NextRequest.Path);
  CheckEquals('/d', NextRequest.Path);
end;

// the body is gone, so whatever described it must go too
procedure TBpHttpRedirectWireTests.TestPostBecomesGetOn301And302;
var
  lvHop: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(301, '/moved'));
  FServer.Enqueue(BpMockOk('done'));
  FServer.Enqueue(BpMockRedirect(302, '/moved'));
  FServer.Enqueue(BpMockOk('done'));

  FClient.Post(Url('/old'), 'a=1', 'Content-Type: text/plain');
  NextRequest;
  lvHop := NextRequest;
  CheckEquals('GET', lvHop.Method, '301');
  CheckEquals('', string(lvHop.Body), 'the body is dropped');
  CheckFalse(lvHop.HasHeader('Content-Type'), 'Content-Type described the body');
  CheckEquals('', lvHop.HeaderValue('Content-Length'),
    'Content-Length described the body');

  // a Content-Type set on the client, not per request, is the harder case
  FClient.AddHeader('Content-Type', 'application/json');
  FClient.Post(Url('/old'), '{"a":1}');
  NextRequest;
  lvHop := NextRequest;
  CheckEquals('GET', lvHop.Method, '302');
  CheckEquals('', string(lvHop.Body));
  CheckFalse(lvHop.HasHeader('Content-Type'),
    'a persistent Content-Type described the body that is now gone');
end;

procedure TBpHttpRedirectWireTests.Test307And308KeepMethodAndBody;
var
  lvHop: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(307, '/here'));
  FServer.Enqueue(BpMockOk('done'));
  FServer.Enqueue(BpMockRedirect(308, '/here'));
  FServer.Enqueue(BpMockOk('done'));
  FClient.Post(Url('/old'), 'payload=307');
  FClient.Put(Url('/old'), 'payload=308');

  NextRequest;
  lvHop := NextRequest;
  CheckEquals('POST', lvHop.Method);
  CheckEquals('payload=307', string(lvHop.Body), 'the body is resent');
  NextRequest;
  lvHop := NextRequest;
  CheckEquals('PUT', lvHop.Method);
  CheckEquals('payload=308', string(lvHop.Body));
end;

// the interface documents MaxRedirects 0 as FollowRedirects False
procedure TBpHttpRedirectWireTests.TestRedirectIsReturnedWhenNotFollowed;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockStatus(302, 'no location here'));
  FServer.Enqueue(BpMockRedirect(302, '/second'));
  FServer.Enqueue(BpMockRedirect(302, '/second'));

  lvResponse := FClient.Get(Url('/first'));
  CheckEquals(302, lvResponse.StatusCode);
  CheckEquals('no location here', string(lvResponse.Body));
  CheckEquals(1, FServer.RequestCount, 'without a Location there is nowhere to go');

  FClient.FollowRedirects := False;
  lvResponse := FClient.Get(Url('/first'));
  CheckEquals(302, lvResponse.StatusCode);
  CheckEquals('/second', BpHttpHeaderValue(lvResponse.Headers, 'Location'));
  CheckEquals('redirecting', string(lvResponse.Body), 'the 3xx body is returned');
  CheckEquals(2, FServer.RequestCount, 'FollowRedirects False takes no hop');

  FClient.FollowRedirects := True;
  FClient.MaxRedirects := 0;
  lvResponse := FClient.Get(Url('/first'));
  CheckEquals(302, lvResponse.StatusCode);
  CheckEquals('/second', BpHttpHeaderValue(lvResponse.Headers, 'Location'));
  CheckEquals(3, FServer.RequestCount, 'MaxRedirects 0 takes no hop');
end;

procedure TBpHttpRedirectWireTests.TestMaxRedirectsExceededRaises;
var
  i: Integer;
begin
  FClient.MaxRedirects := 2;
  for i := 1 to 5 do
    FServer.Enqueue(BpMockRedirect(302, Format('/hop%d', [i])));
  try
    FClient.Get(Url('/hop0'));
    Fail('expected EbpHttpClient once the redirect budget is spent');
  except
    on E: EbpHttpClient do
      Check(Pos('redirects', E.Message) > 0, E.Message);
  end;
  CheckEquals(3, FServer.RequestCount, 'one request plus the two allowed hops');
end;

procedure TBpHttpRedirectWireTests.TestDownloadFollowsARedirect;
var
  lvStream: TMemoryStream;
  lvResponse: TbpHttpResponse;
  lvRedirect: TbpMockResponse;
begin
  lvRedirect := BpMockRedirect(302, '/payload.bin');
  lvRedirect.Body := BpRepeated($41, 4096);
  FServer.Enqueue(lvRedirect);
  FServer.Enqueue(BpMockOk('0123456789'));
  // the cap is for buffered bodies; a redirect's body used to be buffered even here
  FClient.MaxResponseBytes := 1024;
  lvStream := TMemoryStream.Create;
  try
    lvResponse := FClient.Download(Url('/start'), lvStream);
    CheckEquals(200, lvResponse.StatusCode);
    CheckEquals(10, lvStream.Size, 'only the final body reaches the stream');
    CheckEquals(Url('/payload.bin'), lvResponse.FinalUrl);
  finally
    lvStream.Free;
  end;
end;

{ TBpHttpRedirectCredentialTests }

procedure TBpHttpRedirectCredentialTests.SetUp;
begin
  inherited;
  FOther := TbpMockHttpServer.Create;
end;

procedure TBpHttpRedirectCredentialTests.TearDown;
begin
  FreeAndNil(FOther);
  inherited;
end;

// the http to https exception needs TLS, so it stays in TestKeepsCredentials
procedure TBpHttpRedirectCredentialTests.TestCrossOriginRedirectDropsEverySecret;
var
  lvSecond: TbpRecordedRequest;
begin
  FClient.AddHeader('Authorization', 'Bearer secret-token');
  FClient.AddHeader('Cookie', 'session=abc');
  FClient.AddHeader('Proxy-Authorization', 'Basic cHJveHk=');
  FClient.AddHeader('X-Api-Key', 'persistent-key');

  FServer.Enqueue(BpMockRedirect(302, FOther.Url('/landing')));
  FOther.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/start'));

  lvSecond := FOther.TakeRequest;
  Check(lvSecond <> nil, 'the other origin never saw the hop');
  CheckFalse(lvSecond.HasHeader('Authorization'), 'Authorization must not follow');
  CheckFalse(lvSecond.HasHeader('Cookie'),
    'Cookie must not follow, got: ' + lvSecond.HeaderValue('Cookie'));
  CheckFalse(lvSecond.HasHeader('Proxy-Authorization'),
    'Proxy-Authorization must not follow');
  CheckFalse(lvSecond.HasHeader('X-Api-Key'),
    'no persistent header of ours follows to another origin');
  CheckEquals(0, CountOccurrences(lvSecond.RawHead, 'secret-token'));
  CheckEquals(0, CountOccurrences(lvSecond.RawHead, 'persistent-key'));
end;

procedure TBpHttpRedirectCredentialTests.TestUrlCredentialsDoNotCrossOrigins;
var
  lvSecond: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(302, FOther.Url('/landing')));
  FOther.Enqueue(BpMockOk('ok'));
  FClient.Get(WithUserInfo(Url('/start'), 'user:pass'));

  lvSecond := FOther.TakeRequest;
  Check(lvSecond <> nil, 'the other origin never saw the hop');
  CheckFalse(lvSecond.HasHeader('Authorization'),
    'credentials from the url are credentials like any other');
  CheckEquals(0, CountOccurrences(lvSecond.RawHead, 'dXNlcjpwYXNz'));
end;

procedure TBpHttpRedirectCredentialTests.TestSameOriginRedirectKeepsThem;
var
  lvSecond: TbpRecordedRequest;
begin
  FClient.AddHeader('Authorization', 'Bearer secret-token');
  FClient.AddHeader('X-Api-Key', 'persistent-key');
  FServer.Enqueue(BpMockRedirect(302, '/landing'));
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/start'));

  NextRequest;
  lvSecond := NextRequest;
  CheckEquals('Bearer secret-token', lvSecond.HeaderValue('Authorization'));
  CheckEquals('persistent-key', lvSecond.HeaderValue('X-Api-Key'));
end;

{ TBpHttpCancelWireTests }

procedure TBpHttpCancelWireTests.CancelAtFirstData(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  if aReceived > 0 then
    aCancel := True;
end;

procedure TBpHttpCancelWireTests.TestSyncCancelViaProgressCallback;
var
  lvStream: TMemoryStream;
begin
  EnqueueSlowReply(FServer);
  lvStream := TMemoryStream.Create;
  try
    try
      FClient.Download(Url('/slow.bin'), lvStream, CancelAtFirstData);
      Fail('expected EbpHttpClientCancelled');
    except
      on E: EbpHttpClientCancelled do
        CheckEquals(gcErrOperationCancelled, E.WinInetError);
    end;
    Check(lvStream.Size > 0, 'some data arrived before the cancel');
    Check(lvStream.Size < gcSlowClaimed, 'the download must not run to completion');
  finally
    lvStream.Free;
  end;
end;

procedure TBpHttpCancelWireTests.TestSyncRequestCancelMidFlight;
var
  lvToken: TbpCancellationToken;
  lvCanceller: TDelayedCancelThread;
  lvStart, lvElapsed: Cardinal;
begin
  EnqueueSlowReply(FServer);
  lvToken := TbpCancellationToken.Create;
  try
    // the server stays quiet for half a minute, so only the cancel can end this
    FClient.ReceiveTimeout := 25000;
    lvCanceller := TDelayedCancelThread.Create(lvToken, 300);
    try
      lvStart := GetTickCount;
      try
        FClient.Get(Url('/slow.bin'), '', lvToken);
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

// freeing a sink the moment Detach returns must not race a thread inside it
procedure TBpHttpCancelWireTests.TestDetachWaitsForASinkInFlight;
var
  lvWorker: TbpGetThread;
  lvEntered, lvLeftBeforeDetachReturned, lvFinished: Boolean;
begin
  FServer.Enqueue(BpMockOk('warm'));
  FServer.Enqueue(BpMockOk('held'));
  FClient.Get(Url('/warm'));  // open the session before another thread uses it
  gvSinkEntered := False;
  gvSinkLeft := False;
  gvSinkHoldMs := 300;
  CheckTrue(TbpHttpTrace.Attach(FClient, HoldingTraceLine), 'attach');
  lvLeftBeforeDetachReturned := False;
  lvWorker := TbpGetThread.Create(FClient, Url('/held'));
  // every check waits until after the cleanup, so nothing throws past the Free
  try
    lvEntered := BpWaitForFlag(gvSinkEntered, 5000);
    if lvEntered then
    begin
      TbpHttpTrace.Detach(FClient);
      lvLeftBeforeDetachReturned := gvSinkLeft;
    end;
    lvFinished := WaitForSingleObject(lvWorker.Handle, 10000) = WAIT_OBJECT_0;
  finally
    gvSinkHoldMs := 0;
    TbpHttpTrace.Detach(FClient);
    lvWorker.Free;
  end;
  CheckTrue(lvEntered, 'no callback reached the sink');
  CheckTrue(lvLeftBeforeDetachReturned, 'Detach returned with a thread still in the sink');
  CheckTrue(lvFinished, 'the worker request finished');
end;

// the trace used to be one sink per process with no request ids or timings
procedure TBpHttpCancelWireTests.TestTraceFollowsEachRequestOfItsClient;
var
  lvOther: TbpHttpClient;
  lvFirst, lvSecond: string;
  lvTracedLength: Integer;
begin
  FServer.Enqueue(BpMockOk('one'));
  FServer.Enqueue(BpMockOk('two'));
  FServer.Enqueue(BpMockOk('three'));
  FServer.Enqueue(BpMockOk('four'));
  gvTraceLog := '';
  lvOther := TbpHttpClient.Create;
  try
    CheckTrue(TbpHttpTrace.Attach(FClient, CollectTraceLine), 'attach');
    try
      FClient.Get(Url('/one'));
      FClient.Get(Url('/two'));
      lvOther.Get(Url('/three'));  // untraced, so it must add nothing
    finally
      TbpHttpTrace.Detach(FClient);
    end;
  finally
    lvOther.Free;
  end;
  lvTracedLength := Length(gvTraceLog);
  FClient.Get(Url('/four'));
  CheckEquals(lvTracedLength, Length(gvTraceLog), 'detached must be silent');

  Check(Pos('connecting to', gvTraceLog) > 0, 'connect phase: ' + gvTraceLog);
  Check(Pos('sending request', gvTraceLog) > 0, 'send phase: ' + gvTraceLog);
  Check(Pos('request sent', gvTraceLog) > 0, 'byte count: ' + gvTraceLog);
  Check(Pos('response received', gvTraceLog) > 0, 'read phase: ' + gvTraceLog);
  lvFirst := Copy(gvTraceLog, Pos('#1 done', gvTraceLog), MaxInt);
  lvFirst := Copy(lvFirst, 1, Pos(#13#10, lvFirst));
  lvSecond := Copy(gvTraceLog, Pos('#2 done', gvTraceLog), MaxInt);
  lvSecond := Copy(lvSecond, 1, Pos(#13#10, lvSecond));
  Check(Pos('new connection', lvFirst) > 0, 'first summary: ' + gvTraceLog);
  Check(Pos('127.0.0.1', lvFirst) > 0, 'the remote address: ' + gvTraceLog);
  Check(Pos('reused connection', lvSecond) > 0, 'second summary: ' + gvTraceLog);
  CheckEquals(0, Pos('#3', gvTraceLog), 'another client is not traced: ' + gvTraceLog);
end;

// errors used to blame "send" for a refused connect and name no host
procedure TBpHttpCancelWireTests.TestFailureNamesTheCallAndTheHost;
begin
  gvTraceLog := '';
  CheckTrue(TbpHttpTrace.Attach(FClient, CollectTraceLine), 'attach');
  try
    try
      // nothing listens on port 1, so the connect is refused at once
      FClient.Get('http://127.0.0.1:1/');
      Fail('expected a refused connection');
    except
      on E: EbpHttpClient do
        Check(Pos('HttpSendRequest failed for 127.0.0.1:1', E.Message) > 0,
          'name the call and the host: ' + E.Message);
    end;
  finally
    TbpHttpTrace.Detach(FClient);
  end;
  Check(Pos('#1 failed: HttpSendRequest failed for 127.0.0.1:1', gvTraceLog) > 0,
    'the sink hears of the failure: ' + gvTraceLog);
end;

procedure TBpHttpCancelWireTests.TestReceiveTimeoutFiresOnAStall;
var
  lvReply: TbpMockResponse;
  lvStart, lvElapsed: Cardinal;
begin
  lvReply := BpMockStatus(200);
  lvReply.ClaimedLength := 4096;  // announced and then never sent
  lvReply.Effect := mseStall;
  FServer.Enqueue(lvReply);

  FClient.ReceiveTimeout := 1500;
  lvStart := GetTickCount;
  try
    FClient.Get(Url('/stall'));
    Fail('expected the receive timeout to end the read');
  except
    on EbpHttpClientCancelled do
      Fail('a timeout is not a cancellation');
    on E: EbpHttpClient do
      CheckNotEquals(0, Integer(E.WinInetError), 'a WinInet error is expected');
  end;
  lvElapsed := GetTickCount - lvStart;
  Check(lvElapsed < 15000,
    Format('the timeout must end the read, took %d ms', [lvElapsed]));
end;

// the step timeout alone would wait 25 s here; the deadline closes the handle
procedure TBpHttpCancelWireTests.TestTimeoutEndsTheWholeCall;
var
  lvReply: TbpMockResponse;
  lvStart, lvElapsed: Cardinal;
begin
  lvReply := BpMockStatus(200);
  lvReply.ClaimedLength := 4096;
  lvReply.Effect := mseStall;
  FServer.Enqueue(lvReply);

  FClient.ReceiveTimeout := 25000;
  FClient.Timeout := 1000;
  lvStart := GetTickCount;
  try
    FClient.Get(Url('/stall'));
    Fail('expected the deadline to end the call');
  except
    on EbpHttpClientCancelled do
      Fail('a deadline is not a cancellation');
    on E: EbpHttpClient do
    begin
      CheckEquals(12002, Integer(E.WinInetError), 'ERROR_INTERNET_TIMEOUT');
      Check(Pos('Timeout', E.Message) > 0, 'say it was the deadline: ' + E.Message);
    end;
  end;
  lvElapsed := GetTickCount - lvStart;
  Check(lvElapsed < 10000,
    Format('the deadline must end the call, took %d ms', [lvElapsed]));
end;

{ TBpHttpTaskWireTests }

procedure TBpHttpTaskWireTests.SetUp;
begin
  inherited;
  FDoneCount := 0;
  FDoneThread := 0;
  FDoneBody := '';
  FArmed := False;
  FReleasedInProgress := False;
  // the server stays quiet for half a minute, so only a cancel ends a slow reply
  FClient.ReceiveTimeout := 25000;
end;

procedure TBpHttpTaskWireTests.TearDown;
begin
  FTask := nil;  // cancels and waits, before the client and the server go
  inherited;
end;

// a method of its own: Delphi keeps a hidden copy of a returned interface
// until the caller returns, which would hold the task past FTask := nil
procedure TBpHttpTaskWireTests.StartSlowDownload(aDest: TStream;
  aOnProgress: TbpHttpTaskProgressEvent);
begin
  EnqueueSlowReply(FServer);
  FTask := FClient.BeginDownload(Url('/slow.bin'), aDest, HandleDone, aOnProgress);
end;

procedure TBpHttpTaskWireTests.HandleDone(const aTask: IbpHttpTask);
begin
  FDoneThread := GetCurrentThreadId;
  FDoneState := aTask.State;
  if FDoneState = htsSucceeded then
    FDoneBody := aTask.Response.Body;
  Inc(FDoneCount);
end;

procedure TBpHttpTaskWireTests.ReleaseOnProgress(const aTask: IbpHttpTask;
  const aReceived, aTotal: Int64);
begin
  // the worker may get here before the test thread has stored FTask
  if FReleasedInProgress or not BpWaitForFlag(FArmed, 5000) then
    Exit;
  FTask := nil;
  FReleasedInProgress := True;
end;

// the same call on a worker: its response, or its exception with every field
procedure TBpHttpTaskWireTests.TestBeginGetAnswersLikeTheSyncCall;
begin
  FServer.Enqueue(BpMockOk('async'));
  FTask := FClient.BeginGet(Url('/a'), HandleDone);
  CheckTrue(BpPumpUntilCount(FDoneCount, 1, 5000), 'OnDone must arrive');
  CheckEquals(GetCurrentThreadId, FDoneThread, 'OnDone runs on the main thread');
  Check(FDoneState = htsSucceeded, 'failed: ' + FTask.ErrorMessage);
  CheckEquals('async', string(FDoneBody));

  // nothing listens on port 1, so the connect is refused at once
  FTask := FClient.BeginGet('http://127.0.0.1:1/', nil);
  CheckTrue(FTask.WaitFor(10000), 'the task must end');
  Check(FTask.State = htsFailed, 'expected failed');
  try
    FTask.Response;
    Fail('expected the error of the sync call');
  except
    on EbpHttpClientCancelled do
      Fail('a refused connection is not a cancel');
    on E: EbpHttpClient do
    begin
      CheckNotEquals(0, Integer(E.WinInetError), 'the WinInet error survives');
      Check(Pos('HttpSendRequest failed for 127.0.0.1:1', E.Message) > 0,
        'the message survives: ' + E.Message);
    end;
  end;
end;

// a form's field going away must not leave a request running behind it
procedure TBpHttpTaskWireTests.TestReleasingTheTaskCancelsIt;
var
  lvStream: TMemoryStream;
  lvStart, lvElapsed: Cardinal;
begin
  lvStream := TMemoryStream.Create;
  try
    StartSlowDownload(lvStream, nil);
    CheckNotNull(FServer.TakeRequest(10000), 'the request must reach the server');
    lvStart := GetTickCount;
    FTask := nil;
    lvElapsed := GetTickCount - lvStart;
  finally
    FTask := nil;
    lvStream.Free;
  end;
  Check(lvElapsed < 10000,
    Format('the release must cancel, not wait out the reply, took %d ms', [lvElapsed]));
  BpPumpFor(100);
  CheckEquals(0, FDoneCount, 'a released task tells no one');
end;

// the worker cannot join itself, so the free waits for the end of the work
procedure TBpHttpTaskWireTests.TestReleaseInsideAWorkerEventIsDeferred;
var
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  try
    FClient.MarshalTaskEvents := False;
    StartSlowDownload(lvStream, ReleaseOnProgress);
    FArmed := True;
    CheckTrue(BpWaitForFlag(FReleasedInProgress, 10000), 'progress must arrive');
  finally
    // returns once the worker has left the call, so the stream is free to go
    FreeAndNil(FClient);
    lvStream.Free;
  end;
  CheckFalse(BpWaitForCount(FDoneCount, 1, 200), 'a released task tells no one');
end;

// the client used to go while a call on another thread still read its fields
procedure TBpHttpTaskWireTests.TestFreeingTheClientEndsEveryCallInFlight;
var
  lvStream: TMemoryStream;
  lvWorker: TbpGetThread;
  lvStart, lvElapsed: Cardinal;
begin
  lvStream := TMemoryStream.Create;
  lvWorker := nil;
  try
    StartSlowDownload(lvStream, nil);
    EnqueueSlowReply(FServer);
    lvWorker := TbpGetThread.Create(FClient, Url('/thread.bin'));
    CheckNotNull(FServer.TakeRequest(10000), 'the first request must arrive');
    CheckNotNull(FServer.TakeRequest(10000), 'the second request must arrive');
    lvStart := GetTickCount;
    FreeAndNil(FClient);
    lvElapsed := GetTickCount - lvStart;
    CheckTrue(WaitForSingleObject(lvWorker.Handle, 10000) = WAIT_OBJECT_0,
      'the call on the other thread must end');
    CheckEquals('EbpHttpClientCancelled', lvWorker.FErrorClass);
    Check(lvElapsed < 10000,
      Format('Free must cancel, not wait out the replies, took %d ms', [lvElapsed]));
    CheckTrue(BpPumpUntilCount(FDoneCount, 1, 5000), 'OnDone must arrive');
    Check(FDoneState = htsCancelled, 'expected cancelled: ' + FTask.ErrorMessage);
  finally
    FTask := nil;
    lvWorker.Free;
    lvStream.Free;
  end;
end;

initialization
{$IFNDEF NO_INTEGRATION}
  // every test here binds a loopback port, so /nointeg drops the lot
  RegisterTest(TBpHttpVerbTests.Suite);
  RegisterTest(TBpHttpHeaderWireTests.Suite);
  RegisterTest(TBpHttpBodyWireTests.Suite);
  RegisterTest(TBpHttpDownloadToFileTests.Suite);
  RegisterTest(TBpHttpGzipTests.Suite);
  RegisterTest(TBpHttpRedirectWireTests.Suite);
  RegisterTest(TBpHttpRedirectCredentialTests.Suite);
  RegisterTest(TBpHttpCancelWireTests.Suite);
  RegisterTest(TBpHttpTaskWireTests.Suite);
{$ENDIF}

end.
