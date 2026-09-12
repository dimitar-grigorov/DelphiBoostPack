unit BpHttpClientTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpHttpClient;

type
  // basic offline tests, no network access needed
  TBpHttpClientTests = class(TTestCase)
  private
    FClient: TbpHttpClient;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParseUrl;
    procedure TestBuildHeaders;
    procedure TestBasicAuth;
    procedure TestMethodToString;
    procedure TestHeaderValue;
    procedure TestIsSuccess;
    procedure TestBodyAsUtf8;
    procedure TestClassifyHttpError;
    procedure TestHeaderInjectionRejected;
    procedure TestBuildHeadersOddValues;
    procedure TestVerbsHonourPreCancelledToken;
    procedure TestSameOrigin;
    procedure TestKeepsCredentials;
    procedure TestReasonPhrase;
    procedure TestRedirectMethod;
    procedure TestRedirectTarget;
    procedure TestStripCredentials;
  end;

implementation

procedure TBpHttpClientTests.SetUp;
begin
  inherited;
  FClient := TbpHttpClient.Create;
end;

procedure TBpHttpClientTests.TearDown;
begin
  FClient.Free;
  inherited;
end;

procedure TBpHttpClientTests.TestParseUrl;
var
  lvServer, lvResource: string;
  lvPort: Integer;
  lvSecure: Boolean;
begin
  Check(FClient.ParseUrl('http://example.com/index.html', lvServer, lvResource,
    lvPort, lvSecure), 'plain http should parse');
  CheckEquals('example.com', lvServer);
  CheckEquals('/index.html', lvResource);
  CheckEquals(80, lvPort);
  CheckFalse(lvSecure);

  Check(FClient.ParseUrl('https://api.example.com/v1/items', lvServer, lvResource,
    lvPort, lvSecure), 'https should parse');
  CheckEquals('api.example.com', lvServer);
  CheckEquals('/v1/items', lvResource);
  CheckEquals(443, lvPort);
  CheckTrue(lvSecure);

  Check(FClient.ParseUrl('http://localhost:8080/status', lvServer, lvResource,
    lvPort, lvSecure), 'explicit port should parse');
  CheckEquals('localhost', lvServer);
  CheckEquals(8080, lvPort);

  // query string must stay attached to the resource
  Check(FClient.ParseUrl('https://example.com/search?q=delphi&page=2', lvServer,
    lvResource, lvPort, lvSecure), 'url with query should parse');
  CheckEquals('/search?q=delphi&page=2', lvResource);

  // bare host gets '/' as resource
  Check(FClient.ParseUrl('http://example.com', lvServer, lvResource,
    lvPort, lvSecure), 'bare host should parse');
  CheckEquals('/', lvResource);

  // the fragment is client side only and must not reach the request line
  Check(FClient.ParseUrl('https://example.com/doc?a=1#part2', lvServer,
    lvResource, lvPort, lvSecure), 'url with fragment should parse');
  CheckEquals('/doc?a=1', lvResource);
  Check(FClient.ParseUrl('https://example.com/#top', lvServer, lvResource,
    lvPort, lvSecure), 'fragment only should parse');
  CheckEquals('/', lvResource);

  CheckFalse(FClient.ParseUrl('not a url at all', lvServer, lvResource,
    lvPort, lvSecure), 'garbage should not parse');

  // only http and https, or the client would post to an ftp host
  CheckFalse(FClient.ParseUrl('ftp://example.com/f.txt', lvServer, lvResource,
    lvPort, lvSecure), 'ftp should not parse');
  CheckFalse(FClient.ParseUrl('file:///c:/temp/f.txt', lvServer, lvResource,
    lvPort, lvSecure), 'file should not parse');
  CheckFalse(FClient.ParseUrl('mailto:a@b.com', lvServer, lvResource,
    lvPort, lvSecure), 'mailto should not parse');

  // WinInet would strip these and send a different query than was passed
  CheckFalse(FClient.ParseUrl('http://example.com/a'#13'b', lvServer,
    lvResource, lvPort, lvSecure), 'CR should not parse');
  CheckFalse(FClient.ParseUrl('http://example.com/a'#10'b', lvServer,
    lvResource, lvPort, lvSecure), 'LF should not parse');
  CheckFalse(FClient.ParseUrl('http://example.com/a?q=1'#9'2', lvServer,
    lvResource, lvPort, lvSecure), 'TAB should not parse');
end;

procedure TBpHttpClientTests.TestBuildHeaders;
begin
  CheckEquals('', FClient.BuildHeaders(''), 'no headers yields empty string');

  FClient.AddHeader('X-Custom', 'one');
  CheckEquals('X-Custom: one', FClient.BuildHeaders(''));

  // setting the same name again replaces, not duplicates
  FClient.AddHeader('X-Custom', 'two');
  CheckEquals('X-Custom: two', FClient.BuildHeaders(''));

  // bearer token appends its own Authorization line
  FClient.BearerToken := 'abc123';
  CheckEquals('X-Custom: two'#13#10'Authorization: Bearer abc123',
    FClient.BuildHeaders(''));

  // per-request headers come last
  CheckEquals('X-Custom: two'#13#10'Authorization: Bearer abc123'#13#10 +
    'Accept: text/plain', FClient.BuildHeaders('Accept: text/plain'));

  // a per-request name replaces the persistent one instead of joining it
  CheckEquals('Authorization: Bearer abc123'#13#10'X-Custom: three',
    FClient.BuildHeaders('X-Custom: three'), 'persistent header overridden');
  CheckEquals('X-Custom: two'#13#10'Authorization: Bearer other',
    FClient.BuildHeaders('Authorization: Bearer other'), 'bearer overridden');
  // the name match ignores case and surrounding spaces
  CheckEquals('Authorization: Bearer abc123'#13#10'x-custom : four',
    FClient.BuildHeaders(' x-custom : four'), 'match is case and space insensitive');

  // one Authorization line whichever order they were set in, last writer wins
  FClient.AddHeader('Authorization', 'Basic AAAA');
  CheckEquals('X-Custom: two'#13#10'Authorization: Basic AAAA',
    FClient.BuildHeaders(''), 'an explicit header replaces the bearer token');
  FClient.BearerToken := 'later';
  CheckEquals('X-Custom: two'#13#10'Authorization: Bearer later',
    FClient.BuildHeaders(''), 'and the bearer token replaces it back');

  FClient.ClearHeaders;
  FClient.BearerToken := '';
  CheckEquals('', FClient.BuildHeaders(''), 'clear removes everything');
end;

procedure TBpHttpClientTests.TestBasicAuth;
var
  lvPassword: WideString;
begin
  FClient.BearerToken := 'stale-token';
  // 'user:pass' in Base64 is dXNlcjpwYXNz
  FClient.SetBasicAuth('user', 'pass');
  CheckEquals('Authorization: Basic dXNlcjpwYXNz', FClient.BuildHeaders(''),
    'basic auth header expected and bearer token cleared');

  // RFC 7617 is UTF-8, so 'user:pa' + U+00DF is 75736572 3a7061 c39f
  lvPassword := 'pa' + WideChar($00DF);
  FClient.SetBasicAuth('user', lvPassword);
  CheckEquals('Authorization: Basic dXNlcjpwYcOf', FClient.BuildHeaders(''),
    'non-ascii credentials go out as UTF-8, not the machine code page');
end;

procedure TBpHttpClientTests.TestMethodToString;
begin
  CheckEquals('GET', TbpHttpClient.MethodToString(hmGet));
  CheckEquals('POST', TbpHttpClient.MethodToString(hmPost));
  CheckEquals('PUT', TbpHttpClient.MethodToString(hmPut));
  CheckEquals('DELETE', TbpHttpClient.MethodToString(hmDelete));
  CheckEquals('PATCH', TbpHttpClient.MethodToString(hmPatch));
  CheckEquals('HEAD', TbpHttpClient.MethodToString(hmHead));
  CheckEquals('OPTIONS', TbpHttpClient.MethodToString(hmOptions));
end;

procedure TBpHttpClientTests.TestHeaderValue;
const
  lcHeaders = 'HTTP/1.1 200 OK'#13#10 +
    'Content-Type: application/json; charset=utf-8'#13#10 +
    'Content-Length: 42'#13#10 +
    'X-Rate-Limit:  100 '#13#10;
begin
  CheckEquals('application/json; charset=utf-8',
    BpHttpHeaderValue(lcHeaders, 'Content-Type'));
  // lookup is case insensitive and values get trimmed
  CheckEquals('42', BpHttpHeaderValue(lcHeaders, 'content-length'));
  CheckEquals('100', BpHttpHeaderValue(lcHeaders, 'x-rate-limit'));
  CheckEquals('', BpHttpHeaderValue(lcHeaders, 'Server'), 'absent header yields empty');
  CheckEquals('', BpHttpHeaderValue('', 'Content-Type'), 'empty block yields empty');
end;

procedure TBpHttpClientTests.TestIsSuccess;
var
  lvResponse: TbpHttpResponse;
begin
  lvResponse.StatusCode := 200;
  CheckTrue(BpHttpResponseIsSuccess(lvResponse));
  lvResponse.StatusCode := 204;
  CheckTrue(BpHttpResponseIsSuccess(lvResponse));
  lvResponse.StatusCode := 299;
  CheckTrue(BpHttpResponseIsSuccess(lvResponse));
  lvResponse.StatusCode := 199;
  CheckFalse(BpHttpResponseIsSuccess(lvResponse));
  lvResponse.StatusCode := 301;
  CheckFalse(BpHttpResponseIsSuccess(lvResponse));
  lvResponse.StatusCode := 404;
  CheckFalse(BpHttpResponseIsSuccess(lvResponse));
end;

procedure TBpHttpClientTests.TestBodyAsUtf8;
var
  lvResponse: TbpHttpResponse;
  lvText: WideString;
begin
  lvResponse.Body := '';
  CheckEquals('', BpHttpResponseBodyAsUtf8(lvResponse), 'empty body');

  // 'caf' + e-acute: C3 A9 is the UTF-8 encoding of U+00E9
  lvResponse.Body := 'caf'#$C3#$A9;
  lvText := BpHttpResponseBodyAsUtf8(lvResponse);
  CheckEquals(4, Length(lvText));
  CheckEquals('caf', Copy(lvText, 1, 3));
  CheckEquals($00E9, Ord(lvText[4]));

  // plain ASCII passes through unchanged
  lvResponse.Body := 'hello';
  CheckEquals('hello', BpHttpResponseBodyAsUtf8(lvResponse));
end;

procedure TBpHttpClientTests.TestClassifyHttpError;
begin
  // WinInet dimension wins when set
  CheckEquals('Connection timed out', BpClassifyHttpError(12002, 0));
  CheckEquals('Cannot reach server (DNS or network issue)', BpClassifyHttpError(12007, 0));
  CheckEquals('Cannot connect to server', BpClassifyHttpError(12029, 0));
  CheckEquals('SSL/TLS certificate error', BpClassifyHttpError(12045, 0));
  CheckEquals('SSL/TLS certificate error', BpClassifyHttpError(12055, 0));
  CheckEquals('SSL/TLS certificate error', BpClassifyHttpError(12157, 0));
  CheckEquals('SSL/TLS certificate error', BpClassifyHttpError(12169, 0));
  CheckEquals('SSL/TLS certificate error', BpClassifyHttpError(12170, 0));
  CheckEquals('Network error', BpClassifyHttpError(12999, 404));

  // HTTP dimension
  CheckEquals('Authentication failed (invalid credentials or token?)',
    BpClassifyHttpError(0, 401));
  CheckEquals('Access denied (missing permission or scope?)', BpClassifyHttpError(0, 403));
  CheckEquals('Endpoint not found (check URL)', BpClassifyHttpError(0, 404));
  CheckEquals('Rate limited by server', BpClassifyHttpError(0, 429));
  CheckEquals('Server error', BpClassifyHttpError(0, 500));
  CheckEquals('Server error', BpClassifyHttpError(0, 503));
  CheckEquals('HTTP error 418', BpClassifyHttpError(0, 418));
  CheckEquals('Unknown error', BpClassifyHttpError(0, 0));
  CheckEquals('Operation cancelled', BpClassifyHttpError(gcErrOperationCancelled, 0));
end;

// a CRLF in a name or a value would inject whole headers into the request
procedure TBpHttpClientTests.TestHeaderInjectionRejected;

  procedure CheckRejected(const aName, aValue, aCase: string);
  begin
    try
      FClient.AddHeader(aName, aValue);
      Fail('Expected EbpHttpClient for ' + aCase);
    except
      on E: EbpHttpClient do
        ;
    end;
  end;

begin
  CheckRejected('X', 'a'#13#10'Y: b', 'CRLF in the value');
  CheckRejected('X'#13#10'Y', 'b', 'CRLF in the name');
  CheckRejected('X', 'a'#10'Y: b', 'bare LF in the value');
  CheckRejected('X', 'a'#13'Y: b', 'bare CR in the value');
  CheckRejected('X:Y', 'b', 'colon in the name');
  CheckRejected('', 'b', 'empty name');
  CheckRejected('X Y', 'b', 'space in the name');
  CheckRejected('X'#9'Y', 'b', 'tab in the name');
  CheckRejected('X"Y', 'b', 'quote in the name');
  // '=' would also split wrong in the TStrings the headers live in
  CheckRejected('X=Y', 'b', 'equals in the name');
  CheckEquals('', FClient.BuildHeaders(''), 'no rejected header may survive');

  try
    FClient.BearerToken := 't'#13#10'Y: b';
    Fail('Expected EbpHttpClient for a CRLF in the bearer token');
  except
    on E: EbpHttpClient do
      ;
  end;

  // the password goes through Base64, so a CRLF in it cannot reach the wire
  FClient.SetBasicAuth('user', 'pa'#13#10'ss');
  CheckEquals(0, Pos(#13, FClient.BuildHeaders('')), 'no CR in the basic auth line');
  CheckEquals(0, Pos(#10, FClient.BuildHeaders('')), 'no LF in the basic auth line');
end;

procedure TBpHttpClientTests.TestBuildHeadersOddValues;
begin
  // the headers live in a TStrings, so an empty value removes the name
  FClient.AddHeader('X-Gone', 'here');
  FClient.AddHeader('X-Gone', '');
  CheckEquals('', FClient.BuildHeaders(''), 'an empty value removes the header');

  // a stray CRLF around the per-request block is trimmed off
  FClient.AddHeader('X-Custom', 'one');
  CheckEquals('X-Custom: one'#13#10'Accept: text/plain',
    FClient.BuildHeaders('Accept: text/plain'#13#10), 'trailing CRLF trimmed');
  CheckEquals('X-Custom: one'#13#10'Accept: text/plain',
    FClient.BuildHeaders(#13#10'Accept: text/plain'), 'leading CRLF trimmed');
  CheckEquals('X-Custom: one', FClient.BuildHeaders(#13#10),
    'a CRLF-only block adds nothing');
end;

procedure TBpHttpClientTests.TestSameOrigin;
begin
  CheckTrue(FClient.SameOrigin('https://a.com/x', 'https://a.com/y?q=1'), 'path only');
  CheckTrue(FClient.SameOrigin('https://A.COM/x', 'https://a.com/x'), 'host is case free');
  CheckTrue(FClient.SameOrigin('https://a.com/x', 'https://a.com:443/x'), 'default port');
  CheckFalse(FClient.SameOrigin('https://a.com/x', 'https://b.com/x'), 'other host');
  CheckFalse(FClient.SameOrigin('https://a.com/x', 'https://sub.a.com/x'), 'subdomain');
  CheckFalse(FClient.SameOrigin('https://a.com/x', 'https://a.com:8443/x'), 'other port');
  // an http to https upgrade is still a new origin, as WHATWG fetch has it
  CheckFalse(FClient.SameOrigin('http://a.com/x', 'https://a.com/x'), 'other scheme');
  CheckFalse(FClient.SameOrigin('https://a.com/x', 'not a url'), 'unparsable');
end;

procedure TBpHttpClientTests.TestKeepsCredentials;
begin
  CheckTrue(FClient.KeepsCredentials('https://a.com/x', 'https://a.com/y'),
    'same origin');
  // requests makes the same exception, so a plain to secure hop keeps the auth
  CheckTrue(FClient.KeepsCredentials('http://a.com/x', 'https://a.com/x'),
    'http to https on the same host');
  CheckTrue(FClient.KeepsCredentials('http://a.com:80/x', 'https://a.com:443/x'),
    'the same upgrade spelled out');
  CheckFalse(FClient.KeepsCredentials('https://a.com/x', 'http://a.com/x'),
    'a downgrade to http never keeps them');
  CheckFalse(FClient.KeepsCredentials('http://a.com/x', 'https://b.com/x'),
    'another host');
  CheckFalse(FClient.KeepsCredentials('http://a.com:8080/x', 'https://a.com/x'),
    'a non-default source port is not the upgrade case');
  CheckFalse(FClient.KeepsCredentials('http://a.com/x', 'not a url'),
    'unparsable');
end;

procedure TBpHttpClientTests.TestReasonPhrase;
begin
  CheckEquals('Not Found',
    BpHttpReasonPhrase('HTTP/1.1 404 Not Found'#13#10'Server: x'#13#10), 'plain');
  CheckEquals('OK', BpHttpReasonPhrase('HTTP/1.0 200 OK'#13#10), 'http 1.0');
  CheckEquals('Moved Permanently',
    BpHttpReasonPhrase('HTTP/1.1 301 Moved Permanently'), 'no trailing CRLF');
  CheckEquals('', BpHttpReasonPhrase('HTTP/1.1 204'#13#10), 'server sent none');
  CheckEquals('', BpHttpReasonPhrase('Server: x'#13#10), 'no status line');
  CheckEquals('', BpHttpReasonPhrase(''), 'empty block');
end;

procedure TBpHttpClientTests.TestRedirectMethod;
begin
  CheckEquals('GET', BpHttpRedirectMethod(301, 'POST'), '301 downgrades a POST');
  CheckEquals('GET', BpHttpRedirectMethod(302, 'POST'), '302 downgrades a POST');
  CheckEquals('PUT', BpHttpRedirectMethod(301, 'PUT'), '301 keeps a PUT');
  CheckEquals('GET', BpHttpRedirectMethod(303, 'PUT'), '303 downgrades anything');
  CheckEquals('HEAD', BpHttpRedirectMethod(303, 'HEAD'), '303 keeps a HEAD');
  CheckEquals('POST', BpHttpRedirectMethod(307, 'POST'), '307 keeps the method');
  CheckEquals('POST', BpHttpRedirectMethod(308, 'POST'), '308 keeps the method');
  CheckEquals('POST', BpHttpRedirectMethod(200, 'POST'), 'not a redirect');
end;

procedure TBpHttpClientTests.TestRedirectTarget;
const
  lcBase = 'https://a.com/dir/page?q=1';

  function Loc(const aLocation: string; aStatus: Integer = 302): string;
  begin
    Result := BpHttpRedirectTarget(lcBase,
      'HTTP/1.1 302 Found'#13#10'Location: ' + aLocation + #13#10, aStatus);
  end;

begin
  CheckEquals('https://b.com/x', Loc('https://b.com/x'), 'absolute');
  CheckEquals('https://a.com/other', Loc('/other'), 'root relative');
  CheckEquals('https://a.com/dir/next', Loc('next'), 'path relative');
  CheckEquals('https://b.com/x', Loc('//b.com/x'), 'protocol relative');
  CheckEquals('', Loc('/other', 200), 'not a redirect status');
  CheckEquals('', Loc('/other', 304), '304 is not a redirect');
  CheckEquals('', BpHttpRedirectTarget(lcBase, 'HTTP/1.1 302 Found'#13#10, 302),
    'no Location header');
end;

procedure TBpHttpClientTests.TestStripCredentials;
const
  lcBlock = 'Authorization: Bearer secret'#13#10'Accept: text/plain'#13#10 +
    'cookie: sid=1'#13#10'Proxy-Authorization: Basic x'#13#10'X-Trace: 7';
begin
  CheckEquals('Accept: text/plain'#13#10'X-Trace: 7',
    BpHttpStripCredentials(lcBlock), 'only the safe lines survive');
  CheckEquals('', BpHttpStripCredentials(''), 'empty block');
  CheckEquals('Accept: text/plain',
    BpHttpStripCredentials('Accept: text/plain'), 'nothing to strip');

  // a foreign origin sees none of the client's own headers either
  FClient.BearerToken := 'secret';
  FClient.AddHeader('X-Api-Key', 'k');
  CheckEquals('X-Api-Key: k'#13#10'Authorization: Bearer secret',
    FClient.BuildHeaders(''), 'the origin it was set for sees everything');
  CheckEquals('', FClient.BuildHeaders('', False), 'another origin sees nothing');
  CheckEquals('Accept: text/plain', FClient.BuildHeaders(
    'Accept: text/plain'#13#10'Authorization: Bearer other', False),
    'a per-request credential is dropped, the rest travels');

  // a 302 that turns a POST into a GET leaves no body for these to describe
  CheckEquals('Accept: text/plain', BpHttpStripContentHeaders(
    'Content-Type: application/json'#13#10'Accept: text/plain'#13#10 +
    'content-length: 12'#13#10'Transfer-Encoding: chunked'), 'entity headers');
end;

procedure TBpHttpClientTests.TestVerbsHonourPreCancelledToken;
const
  lcUrl = 'https://example.com/';
  lcVerbs: array[0..8] of string =
    ('Execute', 'Get', 'Post', 'PostJson', 'Put', 'Delete', 'Patch', 'Head',
     'Options');
var
  lvToken: TbpCancellationToken;
  i: Integer;
begin
  // the token check comes before any network activity, so this is offline
  lvToken := TbpCancellationToken.Create;
  try
    lvToken.Cancel;
    for i := Low(lcVerbs) to High(lcVerbs) do
    begin
      try
        case i of
          0: FClient.Execute(lcUrl, hmGet, '', '', lvToken);
          1: FClient.Get(lcUrl, '', lvToken);
          2: FClient.Post(lcUrl, 'body', '', lvToken);
          3: FClient.PostJson(lcUrl, '{}', lvToken);
          4: FClient.Put(lcUrl, 'body', '', lvToken);
          5: FClient.Delete(lcUrl, '', lvToken);
          6: FClient.Patch(lcUrl, 'body', '', lvToken);
          7: FClient.Head(lcUrl, '', lvToken);
          8: FClient.Options(lcUrl, '', lvToken);
        end;
        Fail(lcVerbs[i] + ' must raise EbpHttpClientCancelled');
      except
        on E: EbpHttpClientCancelled do
          CheckEquals(gcErrOperationCancelled, E.WinInetError,
            lcVerbs[i] + ' error code');
      end;
    end;
  finally
    lvToken.Free;
  end;
end;

initialization
  RegisterTest(TBpHttpClientTests.Suite);

end.
