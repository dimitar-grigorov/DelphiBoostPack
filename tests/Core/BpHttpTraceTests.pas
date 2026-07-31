unit BpHttpTraceTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Windows, BpHttpTrace;

type
  // decoder only, no network
  TBpHttpTraceTests = class(TTestCase)
  published
    procedure TestStatusWithoutPayload;
    procedure TestStatusWithHostPayload;
    procedure TestStatusWithByteCount;
    procedure TestNoisyStatusesAreSkipped;
    procedure TestUnknownStatus;
    procedure TestRedirectDropsCredentials;
    procedure TestSanitizeUrl;
  end;

implementation

const
  // WinInet status values
  lcResolvingName       = 10;
  lcNameResolved        = 11;
  lcConnectingToServer  = 20;
  lcConnectedToServer   = 21;
  lcSendingRequest      = 30;
  lcRequestSent         = 31;
  lcReceivingResponse   = 40;
  lcResponseReceived    = 41;
  lcClosingConnection   = 50;
  lcConnectionClosed    = 51;
  lcHandleCreated       = 60;
  lcHandleClosing       = 70;
  lcDetectingProxy      = 80;
  lcRequestComplete     = 100;
  lcRedirect            = 110;
  lcStateChange         = 200;

// the callback hands over a NUL terminated buffer
function TextInfo(const aText: string): PChar;
begin
  Result := PChar(aText);
end;

procedure TBpHttpTraceTests.TestStatusWithoutPayload;
begin
  CheckEquals('sending request',
    TbpHttpTrace.StatusText(lcSendingRequest, nil, 0));
  CheckEquals('waiting for response',
    TbpHttpTrace.StatusText(lcReceivingResponse, nil, 0));
  CheckEquals('closing connection',
    TbpHttpTrace.StatusText(lcClosingConnection, nil, 0));
  CheckEquals('connection closed',
    TbpHttpTrace.StatusText(lcConnectionClosed, nil, 0));
  CheckEquals('detecting proxy',
    TbpHttpTrace.StatusText(lcDetectingProxy, nil, 0));
end;

procedure TBpHttpTraceTests.TestStatusWithHostPayload;
const
  lcHost = 'api.example.com';
  lcAddr = '93.184.216.34:443';
begin
  CheckEquals('resolving ' + lcHost,
    TbpHttpTrace.StatusText(lcResolvingName, TextInfo(lcHost), Length(lcHost)));
  CheckEquals('resolved -> ' + lcAddr,
    TbpHttpTrace.StatusText(lcNameResolved, TextInfo(lcAddr), Length(lcAddr)));
  CheckEquals('connecting to ' + lcAddr,
    TbpHttpTrace.StatusText(lcConnectingToServer, TextInfo(lcAddr), Length(lcAddr)));
  CheckEquals('connected to ' + lcAddr,
    TbpHttpTrace.StatusText(lcConnectedToServer, TextInfo(lcAddr), Length(lcAddr)));

  // a missing payload must not take the decoder down
  CheckEquals('resolving ', TbpHttpTrace.StatusText(lcResolvingName, nil, 0));
end;

procedure TBpHttpTraceTests.TestStatusWithByteCount;
var
  lvBytes: DWORD;
begin
  lvBytes := 1460;
  CheckEquals('request sent (1460 bytes)',
    TbpHttpTrace.StatusText(lcRequestSent, @lvBytes, SizeOf(lvBytes)));

  lvBytes := 65536;
  CheckEquals('response received (65536 bytes)',
    TbpHttpTrace.StatusText(lcResponseReceived, @lvBytes, SizeOf(lvBytes)));

  // too short a payload reads as zero rather than as garbage
  CheckEquals('request sent (0 bytes)',
    TbpHttpTrace.StatusText(lcRequestSent, @lvBytes, 2));
  CheckEquals('request sent (0 bytes)',
    TbpHttpTrace.StatusText(lcRequestSent, nil, SizeOf(lvBytes)));
end;

procedure TBpHttpTraceTests.TestNoisyStatusesAreSkipped;
begin
  CheckEquals('', TbpHttpTrace.StatusText(lcHandleCreated, nil, 0),
    'handle bookkeeping is noise');
  CheckEquals('', TbpHttpTrace.StatusText(lcHandleClosing, nil, 0));
  CheckEquals('', TbpHttpTrace.StatusText(lcRequestComplete, nil, 0));
  CheckEquals('', TbpHttpTrace.StatusText(lcStateChange, nil, 0));
end;

procedure TBpHttpTraceTests.TestUnknownStatus;
begin
  CheckEquals('status 999', TbpHttpTrace.StatusText(999, nil, 0));
end;

procedure TBpHttpTraceTests.TestRedirectDropsCredentials;
const
  lcUrl = 'https://user:secret@api.example.com/v2/items?page=2';
var
  lvLine: string;
begin
  lvLine := TbpHttpTrace.StatusText(lcRedirect, TextInfo(lcUrl), Length(lcUrl));
  CheckEquals('redirect -> https://api.example.com/v2/items?page=2', lvLine);
  Check(Pos('secret', lvLine) = 0, 'no password may survive in a trace line');
end;

procedure TBpHttpTraceTests.TestSanitizeUrl;
begin
  CheckEquals('https://example.com/path',
    TbpHttpTrace.SanitizeUrl('https://example.com/path'));
  CheckEquals('', TbpHttpTrace.SanitizeUrl(''));
  CheckEquals('not a url', TbpHttpTrace.SanitizeUrl('not a url'));

  CheckEquals('http://example.com/',
    TbpHttpTrace.SanitizeUrl('http://user@example.com/'));
  CheckEquals('https://example.com:8443/x',
    TbpHttpTrace.SanitizeUrl('https://user:pass@example.com:8443/x'));

  // an @ in the path or query is not userinfo and must stay
  CheckEquals('https://example.com/mail@host',
    TbpHttpTrace.SanitizeUrl('https://example.com/mail@host'));
  CheckEquals('https://example.com/?to=a@b.com',
    TbpHttpTrace.SanitizeUrl('https://example.com/?to=a@b.com'));

  // bare authority, no trailing slash
  CheckEquals('https://example.com',
    TbpHttpTrace.SanitizeUrl('https://user:pass@example.com'));
end;

initialization
  RegisterTest(TBpHttpTraceTests.Suite);

end.
