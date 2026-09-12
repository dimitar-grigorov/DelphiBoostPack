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
    procedure TestPostSendsTheBody;
    procedure TestPostJsonSetsContentType;
    procedure TestPutSendsTheBody;
    procedure TestDeleteHasNoBody;
    procedure TestPatchSendsTheBody;
    procedure TestHeadHasNoBody;
    procedure TestOptionsReachesTheServer;
    procedure TestQueryStringSurvives;
    procedure TestStatusTextComesFromTheServer;
  end;

  TBpHttpHeaderWireTests = class(TBpWireTestCase)
  published
    procedure TestPersistentHeaderIsSentOnce;
    procedure TestBearerTokenIsSentOnce;
    procedure TestBasicAuthIsSentOnce;
    procedure TestPerRequestHeaderReplacesPersistent;
    procedure TestColonInValueStaysOneLine;
    procedure TestServerCookiesAreNotStored;
    procedure TestExplicitAuthorizationReplacesTheBearer;
    procedure TestBearerReplacesAnExplicitAuthorization;
    procedure TestUrlCredentialsBecomeBasicAuth;
    procedure TestUrlCredentialsArePercentDecoded;
    procedure TestExplicitAuthorizationBeatsTheUrl;
  end;

  TBpHttpBodyWireTests = class(TBpWireTestCase)
  published
    procedure TestChunkedResponseIsBuffered;
    procedure TestEmptyBodyIsFine;
    procedure TestShortBodyFailsTheDownload;
    procedure TestShortBodyLeavesNoFile;
    procedure TestHeadReplyHasNoBodyAndNoError;
    procedure TestNoContentReplyHasNoBody;
    procedure TestNotModifiedReplyHasNoBody;
    procedure TestNoResponseAtAllIsAnError;
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
    procedure TestSuccessReplacesTheFile;
    procedure TestSuccessCreatesAMissingFile;
    procedure TestNotFoundLeavesTheFileAlone;
    procedure TestTruncatedBodyLeavesTheFileAlone;
    procedure TestCancelLeavesTheFileAlone;
    procedure TestUnparsableUrlLeavesTheFileAlone;
    procedure TestPartialContentLeavesTheFileAlone;
  end;

  TBpHttpGzipTests = class(TBpWireTestCase)
  published
    procedure TestGzipIsDecoded;
    procedure TestAcceptEncodingIsSent;
    procedure TestNoAcceptEncodingWhenDecompressionIsOff;
  end;

  TBpHttpRedirectWireTests = class(TBpWireTestCase)
  published
    procedure TestRelativeLocationIsResolved;
    procedure TestThreeHopChain;
    procedure TestPostBecomesGetOn301;
    procedure TestPostBecomesGetOn302;
    procedure Test307KeepsMethodAndBody;
    procedure Test308KeepsMethodAndBody;
    procedure Test303TurnsPutIntoGet;
    procedure Test303LeavesHeadAlone;
    procedure TestMaxRedirectsExceededRaises;
    procedure TestMaxRedirectsZeroReturnsTheRedirect;
    procedure TestFollowRedirectsFalseReturnsTheRedirect;
    procedure TestRedirectWithoutLocationIsReturned;
    procedure TestRedirectBodyIsDrainedSoTheConnectionIsReused;
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
    FCancelAtFirstData: Boolean;
    FCompleteFired: Boolean;
    FErrorFired: Boolean;
    procedure EnqueueSlowReply;
    procedure HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
      var aCancel: Boolean);
    procedure HandleComplete(aSender: TObject);
    procedure HandleError(aSender: TObject; const aErrorMessage: string);
  protected
    procedure SetUp; override;
  published
    procedure TestSyncCancelViaProgressCallback;
    procedure TestSyncRequestCancelMidFlight;
    procedure TestAsyncCancelMidFlight;
    procedure TestTraceSinkSeesTheWire;
    procedure TestReceiveTimeoutFiresOnAStall;
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

var
  // the trace sink is a bare procedure, so its log has to be unit level
  gvTraceLog: string;

procedure CollectTraceLine(aHandle: Pointer; const aLine: string);
begin
  gvTraceLog := gvTraceLog + aLine + #13#10;
end;

// the mock server hands out http://127.0.0.1:port/path, and a test needs the
// userinfo between the scheme and the host
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
  lvResponse: TbpHttpResponse;
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('hello'));
  lvResponse := FClient.Get(Url('/plain'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('hello', string(lvResponse.Body));
  CheckEquals(5, lvResponse.ContentLength);
  CheckEquals(Url('/plain'), lvResponse.FinalUrl, 'no redirect, so the same url');

  lvRequest := NextRequest;
  CheckEquals('GET', lvRequest.Method);
  CheckEquals('/plain', lvRequest.Path);
  CheckEquals('HTTP/1.1', lvRequest.HttpVersion);
  CheckEquals('', string(lvRequest.Body));
end;

procedure TBpHttpVerbTests.TestPostSendsTheBody;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockStatus(201, 'made'));
  CheckEquals(201, FClient.Post(Url('/items'), 'name=box').StatusCode);
  lvRequest := NextRequest;
  CheckEquals('POST', lvRequest.Method);
  CheckEquals('name=box', string(lvRequest.Body));
  CheckEquals('8', lvRequest.HeaderValue('Content-Length'));
end;

procedure TBpHttpVerbTests.TestPostJsonSetsContentType;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('{}'));
  FClient.PostJson(Url('/api'), '{"a":1}');
  lvRequest := NextRequest;
  CheckEquals('POST', lvRequest.Method);
  CheckEquals('{"a":1}', string(lvRequest.Body));
  CheckEquals('application/json', lvRequest.HeaderValue('Content-Type'));
end;

procedure TBpHttpVerbTests.TestPutSendsTheBody;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Put(Url('/items/7'), 'replaced');
  lvRequest := NextRequest;
  CheckEquals('PUT', lvRequest.Method);
  CheckEquals('replaced', string(lvRequest.Body));
end;

procedure TBpHttpVerbTests.TestDeleteHasNoBody;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockStatus(204));
  CheckEquals(204, FClient.Delete(Url('/items/7')).StatusCode);
  lvRequest := NextRequest;
  CheckEquals('DELETE', lvRequest.Method);
  CheckEquals('', string(lvRequest.Body));
end;

procedure TBpHttpVerbTests.TestPatchSendsTheBody;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Patch(Url('/items/7'), '{"n":2}');
  lvRequest := NextRequest;
  CheckEquals('PATCH', lvRequest.Method);
  CheckEquals('{"n":2}', string(lvRequest.Body));
end;

procedure TBpHttpVerbTests.TestHeadHasNoBody;
var
  lvResponse: TbpHttpResponse;
  lvRequest: TbpRecordedRequest;
  lvReply: TbpMockResponse;
begin
  // a real HEAD reply announces what a GET would have returned and sends none
  lvReply := BpMockStatus(200);
  lvReply.ClaimedLength := 4096;
  FServer.Enqueue(lvReply);
  lvResponse := FClient.Head(Url('/big.bin'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('', string(lvResponse.Body), 'a HEAD reply carries no body');
  CheckEquals(4096, lvResponse.ContentLength, 'the announced length is reported');
  lvRequest := NextRequest;
  CheckEquals('HEAD', lvRequest.Method);
end;

procedure TBpHttpVerbTests.TestOptionsReachesTheServer;
var
  lvResponse: TbpMockResponse;
  lvRequest: TbpRecordedRequest;
begin
  lvResponse := BpMockStatus(204);
  lvResponse.Headers.Add('Allow: GET, POST');
  FServer.Enqueue(lvResponse);
  CheckEquals('GET, POST',
    BpHttpHeaderValue(FClient.Options(Url('/api')).Headers, 'Allow'));
  lvRequest := NextRequest;
  CheckEquals('OPTIONS', lvRequest.Method);
end;

procedure TBpHttpVerbTests.TestQueryStringSurvives;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/search?q=delphi&page=2'));
  lvRequest := NextRequest;
  CheckEquals('/search?q=delphi&page=2', lvRequest.Path);
end;

procedure TBpHttpVerbTests.TestStatusTextComesFromTheServer;
var
  lvResponse: TbpMockResponse;
begin
  lvResponse := BpMockStatus(418, 'nope');
  lvResponse.ReasonPhrase := 'I am a teapot';
  FServer.Enqueue(lvResponse);
  CheckEquals('I am a teapot', FClient.Get(Url('/tea')).StatusText);
end;

{ TBpHttpHeaderWireTests }

procedure TBpHttpHeaderWireTests.TestPersistentHeaderIsSentOnce;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.AddHeader('X-Api-Key', 'secret-value');
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('X-Api-Key'), 'exactly one header line');
  CheckEquals('secret-value', lvRequest.HeaderValue('X-Api-Key'));
  CheckEquals(1, CountOccurrences(lvRequest.RawHead, 'secret-value'),
    'the value must appear once in the raw head');
end;

procedure TBpHttpHeaderWireTests.TestBearerTokenIsSentOnce;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.BearerToken := 'tok-123';
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('Authorization'));
  CheckEquals('Bearer tok-123', lvRequest.HeaderValue('Authorization'));
end;

procedure TBpHttpHeaderWireTests.TestBasicAuthIsSentOnce;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.SetBasicAuth('user', 'pass');
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('Authorization'));
  // RFC 7617 base64 of user:pass
  CheckEquals('Basic dXNlcjpwYXNz', lvRequest.HeaderValue('Authorization'));
end;

// curl, requests, axios and .NET all send user:pass@host as Basic auth
procedure TBpHttpHeaderWireTests.TestUrlCredentialsBecomeBasicAuth;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(WithUserInfo(Url('/a'), 'user:pass'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('Authorization'));
  CheckEquals('Basic dXNlcjpwYXNz', lvRequest.HeaderValue('Authorization'));
  CheckEquals('/a', lvRequest.Path, 'the userinfo is not part of the resource');
end;

procedure TBpHttpHeaderWireTests.TestUrlCredentialsArePercentDecoded;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('ok'));
  // an email as the user id is the case that forces the escaping
  FClient.Get(WithUserInfo(Url('/a'), 'us%40er:p%3Aw'));
  lvRequest := NextRequest;
  CheckEquals('Basic dXNAZXI6cDp3', lvRequest.HeaderValue('Authorization'));

  // %2540 is an escaped percent sign, so it must decode exactly once
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(WithUserInfo(Url('/b'), '%2540:pass'));
  lvRequest := NextRequest;
  CheckEquals('Basic JTQwOnBhc3M=', lvRequest.HeaderValue('Authorization'));
end;

procedure TBpHttpHeaderWireTests.TestExplicitAuthorizationBeatsTheUrl;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.SetBasicAuth('real', 'secret');
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(WithUserInfo(Url('/a'), 'user:pass'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('Authorization'));
  CheckEquals('Basic cmVhbDpzZWNyZXQ=', lvRequest.HeaderValue('Authorization'),
    'what the caller set wins over what the url carried');
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

procedure TBpHttpHeaderWireTests.TestColonInValueStaysOneLine;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.AddHeader('X-Note', 'a: b, c');
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('X-Note'));
  CheckEquals('a: b, c', lvRequest.HeaderValue('X-Note'));
  CheckEquals(0, lvRequest.HeaderCount('a'), 'no header named after the value');
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

// two lines would let the server pick the one the caller did not mean
procedure TBpHttpHeaderWireTests.TestExplicitAuthorizationReplacesTheBearer;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.BearerToken := 'tok-456';
  FClient.AddHeader('Authorization', 'Basic AAAA');
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('Authorization'));
  CheckEquals('Basic AAAA', lvRequest.HeaderValue('Authorization'));
  CheckEquals(0, CountOccurrences(lvRequest.RawHead, 'tok-456'));
end;

procedure TBpHttpHeaderWireTests.TestBearerReplacesAnExplicitAuthorization;
var
  lvRequest: TbpRecordedRequest;
begin
  FClient.AddHeader('Authorization', 'Basic AAAA');
  FClient.BearerToken := 'tok-456';
  FServer.Enqueue(BpMockOk('ok'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals(1, lvRequest.HeaderCount('Authorization'));
  CheckEquals('Bearer tok-456', lvRequest.HeaderValue('Authorization'));
  CheckEquals(0, CountOccurrences(lvRequest.RawHead, 'Basic AAAA'));
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

procedure TBpHttpBodyWireTests.TestEmptyBodyIsFine;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockOk(''));
  lvResponse := FClient.Get(Url('/empty'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('', string(lvResponse.Body));
  CheckEquals(0, lvResponse.ContentLength);
end;

procedure TBpHttpBodyWireTests.TestShortBodyFailsTheDownload;
var
  lvReply: TbpMockResponse;
  lvStream: TMemoryStream;
begin
  lvReply := BpMockOk(BpRepeated($41, 500));
  lvReply.ClaimedLength := 1000;   // announces twice what it sends
  lvReply.Effect := mseCloseAtEnd;
  FServer.Enqueue(lvReply);

  lvStream := TMemoryStream.Create;
  try
    try
      FClient.Download(Url('/short'), lvStream);
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

procedure TBpHttpBodyWireTests.TestShortBodyLeavesNoFile;
var
  lvReply: TbpMockResponse;
  lvFileName: string;
begin
  lvReply := BpMockOk(BpRepeated($41, 500));
  lvReply.ClaimedLength := 1000;
  lvReply.Effect := mseCloseAtEnd;
  FServer.Enqueue(lvReply);

  lvFileName := BpTempFilePath('BpWireShortBody.tmp');
  SysUtils.DeleteFile(lvFileName);
  try
    try
      FClient.DownloadToFile(Url('/short'), lvFileName);
      Fail('a truncated download must not be reported as success');
    except
      on EbpHttpClient do
        CheckFalse(FileExists(lvFileName),
          'the partial file must not be left behind');
    end;
  finally
    SysUtils.DeleteFile(lvFileName);
  end;
end;

procedure TBpHttpBodyWireTests.TestHeadReplyHasNoBodyAndNoError;
var
  lvReply: TbpMockResponse;
  lvStream: TMemoryStream;
  lvResponse: TbpHttpResponse;
begin
  lvReply := BpMockStatus(200);
  lvReply.ClaimedLength := 4096;
  FServer.Enqueue(lvReply);
  lvStream := TMemoryStream.Create;
  try
    // the streaming path is where the completeness guard lives
    lvResponse := FClient.Download(Url('/big.bin'), lvStream, nil, nil, '', 'HEAD');
    CheckEquals(200, lvResponse.StatusCode);
    CheckEquals(0, lvStream.Size, 'a HEAD reply writes nothing');
  finally
    lvStream.Free;
  end;
end;

procedure TBpHttpBodyWireTests.TestNoContentReplyHasNoBody;
var
  lvReply: TbpMockResponse;
  lvStream: TMemoryStream;
begin
  lvReply := BpMockStatus(204);
  lvReply.ClaimedLength := gcMockNoContentLength;  // as a real server sends it
  FServer.Enqueue(lvReply);
  lvStream := TMemoryStream.Create;
  try
    CheckEquals(204, FClient.Download(Url('/none'), lvStream).StatusCode);
    CheckEquals(0, lvStream.Size);
  finally
    lvStream.Free;
  end;
end;

procedure TBpHttpBodyWireTests.TestNotModifiedReplyHasNoBody;
var
  lvReply: TbpMockResponse;
  lvStream: TMemoryStream;
begin
  lvReply := BpMockStatus(304);
  lvReply.ClaimedLength := 4096;  // a 304 repeats the length it would have sent
  lvReply.Effect := mseStall;     // and then never sends it, as the RFC requires
  FServer.Enqueue(lvReply);
  lvStream := TMemoryStream.Create;
  try
    CheckEquals(304, FClient.Download(Url('/cached'), lvStream).StatusCode);
    CheckEquals(0, lvStream.Size);
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

// nothing asked for a range, so a fragment must not become the whole file
procedure TBpHttpDownloadToFileTests.TestPartialContentLeavesTheFileAlone;
var
  lvReply: TbpMockResponse;
begin
  lvReply := BpMockStatus(206, 'PART');
  lvReply.Headers.Add('Content-Range: bytes 0-3/9999');
  FServer.Enqueue(lvReply);
  try
    FClient.DownloadToFile(Url('/part.bin'), FDest);
    Fail('expected EbpHttpClient for 206 Partial Content');
  except
    on E: EbpHttpClient do
      CheckEquals(206, E.StatusCode);
  end;
  CheckSurvived('206');
end;

procedure TBpHttpDownloadToFileTests.TestSuccessReplacesTheFile;
begin
  FServer.Enqueue(BpMockOk('REPLACED'));
  CheckEquals(200, FClient.DownloadToFile(Url('/f.bin'), FDest).StatusCode);
  CheckEquals('REPLACED', string(BpReadWholeFile(FDest)));
  CheckEquals(1, BpCountFiles(FDir), 'no temp file may survive a success');
end;

procedure TBpHttpDownloadToFileTests.TestSuccessCreatesAMissingFile;
begin
  SysUtils.DeleteFile(FDest);
  FServer.Enqueue(BpMockOk('BRAND NEW'));
  CheckEquals(200, FClient.DownloadToFile(Url('/f.bin'), FDest).StatusCode);
  CheckEquals('BRAND NEW', string(BpReadWholeFile(FDest)));
  CheckEquals(1, BpCountFiles(FDir));
end;

procedure TBpHttpDownloadToFileTests.TestNotFoundLeavesTheFileAlone;
begin
  FServer.Enqueue(BpMockStatus(404, '<html>not here</html>'));
  CheckEquals(404, FClient.DownloadToFile(Url('/gone.bin'), FDest).StatusCode);
  CheckSurvived('404');
end;

procedure TBpHttpDownloadToFileTests.TestTruncatedBodyLeavesTheFileAlone;
var
  lvReply: TbpMockResponse;
begin
  lvReply := BpMockOk(BpRepeated($41, 500));
  lvReply.ClaimedLength := 1000;
  lvReply.Effect := mseCloseAtEnd;
  FServer.Enqueue(lvReply);
  try
    FClient.DownloadToFile(Url('/short.bin'), FDest);
    Fail('a truncated download must not be reported as success');
  except
    on EbpHttpClient do
      ; // expected
  end;
  CheckSurvived('truncated body');
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

procedure TBpHttpDownloadToFileTests.TestUnparsableUrlLeavesTheFileAlone;
begin
  try
    FClient.DownloadToFile('not a url at all', FDest);
    Fail('expected EbpHttpClient for an unparsable url');
  except
    on EbpHttpClient do
      ; // expected
  end;
  CheckSurvived('unparsable url');
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
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals(gcGzipPlain, string(lvResponse.Body),
    'WinInet must hand back the decoded bytes');
end;

procedure TBpHttpGzipTests.TestAcceptEncodingIsSent;
var
  lvRequest: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockOk('plain'));
  FClient.Get(Url('/a'));
  lvRequest := NextRequest;
  CheckEquals('gzip, deflate', lvRequest.HeaderValue('Accept-Encoding'));
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

procedure TBpHttpRedirectWireTests.TestRelativeLocationIsResolved;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockRedirect(302, '/second'));
  FServer.Enqueue(BpMockOk('arrived'));
  lvResponse := FClient.Get(Url('/first'));
  CheckEquals(200, lvResponse.StatusCode);
  CheckEquals('arrived', string(lvResponse.Body));
  CheckEquals(Url('/second'), lvResponse.FinalUrl,
    'FinalUrl is the resolved absolute url');
  CheckEquals(2, FServer.RequestCount);
  CheckEquals('/first', NextRequest.Path);
  CheckEquals('/second', NextRequest.Path);
end;

procedure TBpHttpRedirectWireTests.TestThreeHopChain;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockRedirect(302, '/b'));
  FServer.Enqueue(BpMockRedirect(302, '/c'));
  FServer.Enqueue(BpMockRedirect(302, '/d'));
  FServer.Enqueue(BpMockOk('last'));
  lvResponse := FClient.Get(Url('/a'));
  CheckEquals('last', string(lvResponse.Body));
  CheckEquals(Url('/d'), lvResponse.FinalUrl);
  CheckEquals(4, FServer.RequestCount);
end;

procedure TBpHttpRedirectWireTests.TestPostBecomesGetOn301;
var
  lvSecond: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(301, '/moved'));
  FServer.Enqueue(BpMockOk('done'));
  FClient.Post(Url('/old'), 'a=1', 'Content-Type: text/plain');
  NextRequest;
  lvSecond := NextRequest;
  CheckEquals('GET', lvSecond.Method);
  CheckEquals('', string(lvSecond.Body), 'the body is dropped');
  CheckFalse(lvSecond.HasHeader('Content-Type'), 'Content-Type described the body');
  CheckEquals('', lvSecond.HeaderValue('Content-Length'),
    'Content-Length described the body');
end;

procedure TBpHttpRedirectWireTests.TestPostBecomesGetOn302;
var
  lvSecond: TbpRecordedRequest;
begin
  // a Content-Type set on the client, not per request, is the harder case
  FClient.AddHeader('Content-Type', 'application/json');
  FServer.Enqueue(BpMockRedirect(302, '/moved'));
  FServer.Enqueue(BpMockOk('done'));
  FClient.Post(Url('/old'), '{"a":1}');
  NextRequest;
  lvSecond := NextRequest;
  CheckEquals('GET', lvSecond.Method);
  CheckEquals('', string(lvSecond.Body));
  CheckFalse(lvSecond.HasHeader('Content-Type'),
    'a persistent Content-Type described the body that is now gone');
end;

procedure TBpHttpRedirectWireTests.Test307KeepsMethodAndBody;
var
  lvSecond: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(307, '/here'));
  FServer.Enqueue(BpMockOk('done'));
  FClient.Post(Url('/old'), 'payload=307');
  NextRequest;
  lvSecond := NextRequest;
  CheckEquals('POST', lvSecond.Method);
  CheckEquals('payload=307', string(lvSecond.Body), 'the body is resent');
end;

procedure TBpHttpRedirectWireTests.Test308KeepsMethodAndBody;
var
  lvSecond: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(308, '/here'));
  FServer.Enqueue(BpMockOk('done'));
  FClient.Put(Url('/old'), 'payload=308');
  NextRequest;
  lvSecond := NextRequest;
  CheckEquals('PUT', lvSecond.Method);
  CheckEquals('payload=308', string(lvSecond.Body));
end;

procedure TBpHttpRedirectWireTests.Test303TurnsPutIntoGet;
var
  lvSecond: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(303, '/result'));
  FServer.Enqueue(BpMockOk('done'));
  FClient.Put(Url('/jobs'), 'start');
  NextRequest;
  lvSecond := NextRequest;
  CheckEquals('GET', lvSecond.Method);
  CheckEquals('', string(lvSecond.Body));
end;

procedure TBpHttpRedirectWireTests.Test303LeavesHeadAlone;
var
  lvSecond: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(303, '/result'));
  FServer.Enqueue(BpMockOk(''));
  FClient.Head(Url('/jobs'));
  NextRequest;
  lvSecond := NextRequest;
  CheckEquals('HEAD', lvSecond.Method, 'a 303 does not downgrade a HEAD');
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

// the interface documents 0 as having the same effect as FollowRedirects False
procedure TBpHttpRedirectWireTests.TestMaxRedirectsZeroReturnsTheRedirect;
var
  lvResponse: TbpHttpResponse;
begin
  FClient.MaxRedirects := 0;
  FServer.Enqueue(BpMockRedirect(302, '/second'));
  lvResponse := FClient.Get(Url('/first'));
  CheckEquals(302, lvResponse.StatusCode);
  CheckEquals('/second', BpHttpHeaderValue(lvResponse.Headers, 'Location'));
  CheckEquals(1, FServer.RequestCount, 'no hop may be taken');
end;

procedure TBpHttpRedirectWireTests.TestFollowRedirectsFalseReturnsTheRedirect;
var
  lvResponse: TbpHttpResponse;
begin
  FClient.FollowRedirects := False;
  FServer.Enqueue(BpMockRedirect(302, '/second'));
  lvResponse := FClient.Get(Url('/first'));
  CheckEquals(302, lvResponse.StatusCode);
  CheckEquals('/second', BpHttpHeaderValue(lvResponse.Headers, 'Location'));
  CheckEquals('redirecting', string(lvResponse.Body), 'the 3xx body is returned');
  CheckEquals(1, FServer.RequestCount);
end;

procedure TBpHttpRedirectWireTests.TestRedirectWithoutLocationIsReturned;
var
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockStatus(302, 'no location here'));
  lvResponse := FClient.Get(Url('/first'));
  CheckEquals(302, lvResponse.StatusCode);
  CheckEquals('no location here', string(lvResponse.Body));
  CheckEquals(1, FServer.RequestCount, 'there is nowhere to go');
end;

// the only real proof that the 3xx body was drained rather than abandoned
procedure TBpHttpRedirectWireTests.TestRedirectBodyIsDrainedSoTheConnectionIsReused;
var
  lvFirst, lvSecond: TbpRecordedRequest;
begin
  FServer.Enqueue(BpMockRedirect(302, '/second'));
  FServer.Enqueue(BpMockOk('arrived'));
  FClient.Get(Url('/first'));
  lvFirst := NextRequest;
  lvSecond := NextRequest;
  CheckEquals(lvFirst.ConnectionId, lvSecond.ConnectionId,
    'both hops must share the pooled connection');
  CheckEquals(1, FServer.ConnectionCount);
end;

procedure TBpHttpRedirectWireTests.TestDownloadFollowsARedirect;
var
  lvStream: TMemoryStream;
  lvResponse: TbpHttpResponse;
begin
  FServer.Enqueue(BpMockRedirect(302, '/payload.bin'));
  FServer.Enqueue(BpMockOk('0123456789'));
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

procedure TBpHttpCancelWireTests.SetUp;
begin
  inherited;
  FCancelAtFirstData := False;
  FCompleteFired := False;
  FErrorFired := False;
end;

// a burst then silence, so a cancel lands while WinInet is blocked in a read
procedure TBpHttpCancelWireTests.EnqueueSlowReply;
var
  lvReply: TbpMockResponse;
begin
  lvReply := BpMockOk(BpRepeated($42, gcSlowBurst));
  lvReply.Headers.Add('Content-Type: application/octet-stream');
  lvReply.ClaimedLength := gcSlowClaimed;
  lvReply.Effect := mseStall;
  FServer.Enqueue(lvReply);
end;

procedure TBpHttpCancelWireTests.HandleProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  if FCancelAtFirstData and (aReceived > 0) then
    aCancel := True;
end;

procedure TBpHttpCancelWireTests.HandleComplete(aSender: TObject);
begin
  FCompleteFired := True;
end;

procedure TBpHttpCancelWireTests.HandleError(aSender: TObject;
  const aErrorMessage: string);
begin
  FErrorFired := True;
end;

procedure TBpHttpCancelWireTests.TestSyncCancelViaProgressCallback;
var
  lvStream: TMemoryStream;
begin
  EnqueueSlowReply;
  lvStream := TMemoryStream.Create;
  try
    FCancelAtFirstData := True;
    try
      FClient.Download(Url('/slow.bin'), lvStream, HandleProgress);
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
  EnqueueSlowReply;
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

procedure TBpHttpCancelWireTests.TestAsyncCancelMidFlight;
var
  lvTask: TbpHttpDownloadTask;
  lvFileName: string;
  lvDeadline: Cardinal;
begin
  EnqueueSlowReply;
  lvFileName := BpTempFilePath('bp_wire_async_cancel.bin');
  lvTask := TbpHttpDownloadTask.Create(False);  // events on the worker thread
  try
    lvTask.Client.ReceiveTimeout := 25000;
    lvTask.Url := Url('/slow.bin');
    lvTask.DestFileName := lvFileName;
    lvTask.OnComplete := HandleComplete;
    lvTask.OnError := HandleError;
    lvTask.Start;

    // the token closes the handle, so even a blocked read aborts promptly
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
    CheckFalse(FileExists(lvFileName),
      'a cancelled download leaves no file behind');
    CheckTrue(FCompleteFired, 'OnComplete fires on every terminal state');
    CheckFalse(FErrorFired, 'cancellation is not an error');
  finally
    lvTask.Free;
    SysUtils.DeleteFile(lvFileName);
  end;
end;

procedure TBpHttpCancelWireTests.TestTraceSinkSeesTheWire;
var
  lvStream: TMemoryStream;
  lvOffLength: Integer;
begin
  EnqueueSlowReply;
  EnqueueSlowReply;
  lvStream := TMemoryStream.Create;
  try
    gvTraceLog := '';
    FCancelAtFirstData := True;  // the reply never ends on its own
    TbpHttpTrace.Attach(FClient, CollectTraceLine);
    try
      try
        FClient.Download(Url('/slow.bin'), lvStream, HandleProgress);
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
      FClient.Download(Url('/slow.bin'), lvStream, HandleProgress);
    except
      on EbpHttpClientCancelled do ;
    end;
    CheckEquals(lvOffLength, Length(gvTraceLog), 'detached must be silent');
  finally
    lvStream.Free;
  end;
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
{$ENDIF}

end.
