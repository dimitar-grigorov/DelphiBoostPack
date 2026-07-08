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

  CheckFalse(FClient.ParseUrl('not a url at all', lvServer, lvResource,
    lvPort, lvSecure), 'garbage should not parse');
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

  FClient.ClearHeaders;
  FClient.BearerToken := '';
  CheckEquals('', FClient.BuildHeaders(''), 'clear removes everything');
end;

procedure TBpHttpClientTests.TestBasicAuth;
begin
  FClient.BearerToken := 'stale-token';
  // 'user:pass' in Base64 is dXNlcjpwYXNz
  FClient.SetBasicAuth('user', 'pass');
  CheckEquals('Authorization: Basic dXNlcjpwYXNz', FClient.BuildHeaders(''),
    'basic auth header expected and bearer token cleared');
end;

procedure TBpHttpClientTests.TestMethodToString;
begin
  CheckEquals('GET', TbpHttpClient.MethodToString(hmGet));
  CheckEquals('POST', TbpHttpClient.MethodToString(hmPost));
  CheckEquals('PUT', TbpHttpClient.MethodToString(hmPut));
  CheckEquals('DELETE', TbpHttpClient.MethodToString(hmDelete));
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
end;

initialization
  RegisterTest(TBpHttpClientTests.Suite);

end.
