unit BpHttpClient;

// HTTP/HTTPS over WinInet for Delphi 7/2007+. TLS comes from Schannel, so no
// OpenSSL DLLs to ship. Cancellable sync verbs, streaming downloads with
// progress, and an async download task. Not from a Windows service: WinInet
// is unsupported there, that is what WinHTTP is for. README has examples.
//
// House rule: the library is one class per unit, this one is deliberately
// self-contained. A helper of up to ~300 lines that nothing else needs lives
// here rather than in a unit of its own; the moment a second unit needs it,
// it moves out, which is what Base64 and the cancellation token did.

interface

uses
  Classes, SysUtils, Windows, WinInet, BpTasks;

type
  TbpHttpMethod = (hmGet, hmPost, hmPut, hmDelete, hmPatch, hmHead, hmOptions);

  EbpHttpClient = class(Exception)
  private
    FStatusCode: Integer;
    FWinInetError: DWORD;
  public
    constructor Create(const aMessage: string; aStatusCode: Integer = 0;
      aWinInetError: DWORD = 0);
    property StatusCode: Integer read FStatusCode;
    property WinInetError: DWORD read FWinInetError;
  end;

  // raised on cancel; WinInetError is gcErrOperationCancelled
  EbpHttpClientCancelled = class(EbpHttpClient);

  TbpHttpResponse = record
    StatusCode: Integer;
    StatusText: string;
    Headers: string;         // raw response headers, CRLF separated
    Body: AnsiString;        // raw bytes as received; empty for Download
    ContentLength: Int64;    // from the Content-Length header, -1 when absent
    FinalUrl: string;        // where the redirects ended, = the requested url when none
  end;

{$IFNDEF BPAMALGAMATION}
  // BpTasks owns these now; `uses BpHttpClient` still reaches them
  TbpCancelCleanupProc = BpTasks.TbpCancelCleanupProc;
  TbpCancellationToken = BpTasks.TbpCancellationToken;
{$ENDIF}

  // per-chunk download progress; aTotal -1 = unknown, set aCancel to abort
  TbpHttpProgressEvent = procedure(aSender: TObject; const aReceived,
    aTotal: Int64; var aCancel: Boolean) of object;

  // synchronous client: verbs, streaming downloads, one reused session
  TbpHttpClient = class
  private
    FUserAgent: string;
    FConnectTimeout: DWORD;
    FSendTimeout: DWORD;
    FReceiveTimeout: DWORD;
    FFollowRedirects: Boolean;
    FMaxRedirects: Integer;
    FAutoDecompress: Boolean;
    FMaxResponseBytes: Int64;
    FUsername: AnsiString;
    FPassword: AnsiString;
    FBearerToken: string;
    FHeaders: TStringList;  // persistent headers as Name=Value pairs
    FSession: HINTERNET;    // reused by every request, nil until the first
    FSessionLock: TRTLCriticalSection;  // guards FSession
    procedure SetUserAgent(const aValue: string);
    procedure SetConnectTimeout(aValue: DWORD);
    procedure SetSendTimeout(aValue: DWORD);
    procedure SetReceiveTimeout(aValue: DWORD);
    procedure SetBearerToken(const aValue: string);
    function GetWinInetErrorMessage(aErrorCode: DWORD): string;
    function CreateSession: HINTERNET;
    procedure CloseSession;
    procedure ApplyTimeoutsToSession;
    function CreateConnection(aSession: HINTERNET; const aServerName: string;
      aPort: Integer): HINTERNET;
    function CreateRequest(aConnection: HINTERNET; const aMethod, aResource: string;
      aSecure: Boolean): HINTERNET;
    procedure ApplyTimeouts(aHandle: HINTERNET);
    procedure ApplyAuthentication(aRequest: HINTERNET);
    function UrlBasicAuth(const aUrl: string): string;
    procedure ApplyDecoding(aRequest: HINTERNET);
    procedure SendHttpRequest(aRequest: HINTERNET; const aHeaders: string;
      const aBody: AnsiString);
    function ReadResponseStatus(aRequest: HINTERNET): Integer;
    function ReadResponseHeaders(aRequest: HINTERNET): string;
    function ReadResponseBody(aRequest: HINTERNET;
      aToken: TbpCancellationToken): AnsiString;
    procedure ReadBodyToStream(aRequest: HINTERNET; aDest: TStream;
      const aTotal: Int64; aProgress: TbpHttpProgressEvent;
      aToken: TbpCancellationToken);
    // one request, no redirect of its own; aRedirectTo names the next hop
    function PerformHop(const aUrl, aMethod, aHeaders: string;
      const aBody: AnsiString; aWithCredentials, aDropContentHeaders: Boolean;
      aDest: TStream; aProgress: TbpHttpProgressEvent;
      aToken: TbpCancellationToken; out aRedirectTo: string): TbpHttpResponse;
    // the one request every verb and download goes through; nil aDest buffers
    function PerformRequest(const aUrl, aMethod, aHeaders: string;
      const aBody: AnsiString; aDest: TStream; aProgress: TbpHttpProgressEvent;
      aToken: TbpCancellationToken): TbpHttpResponse;
  public
    constructor Create;
    destructor Destroy; override;

    // aToken aborts the call from another thread (EbpHttpClientCancelled)
    function Execute(const aUrl: string; aMethod: TbpHttpMethod = hmGet;
      const aHeaders: string = ''; const aBody: AnsiString = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Get(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Post(const aUrl: string; const aBody: AnsiString;
      const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function PostJson(const aUrl: string; const aJson: AnsiString;
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Put(const aUrl: string; const aBody: AnsiString;
      const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Delete(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Patch(const aUrl: string; const aBody: AnsiString;
      const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Head(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Options(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    class function FetchUrl(const aUrl: string; const aHeaders: string = ''): AnsiString;

    // streams the body whatever the status; 'Range: bytes=N-' in aHeaders resumes
    function Download(const aUrl: string; aDest: TStream;
      aProgress: TbpHttpProgressEvent = nil; aToken: TbpCancellationToken = nil;
      const aHeaders: string = ''; const aMethod: string = 'GET'): TbpHttpResponse;
    // a 200 renames a sibling temp file over the destination, nothing else does
    function DownloadToFile(const aUrl, aFileName: string;
      aProgress: TbpHttpProgressEvent = nil; aToken: TbpCancellationToken = nil;
      const aHeaders: string = ''): TbpHttpResponse;

    // persistent headers sent with every request; setting a name again replaces it
    procedure AddHeader(const aName, aValue: string);
    procedure ClearHeaders;
    // preemptive Basic auth header, UTF-8 per RFC 7617; clears BearerToken
    procedure SetBasicAuth(const aUser, aPassword: WideString);

    // exposed for testing; also useful on their own
    function ParseUrl(const aUrl: string; out aServerName, aResource: string;
      out aPort: Integer; out aSecure: Boolean): Boolean;
    // aWithCredentials False builds the block a foreign redirect origin may see
    function BuildHeaders(const aRequestHeaders: string;
      aWithCredentials: Boolean = True): string;
    // scheme, host and port all equal, the WHATWG fetch definition
    function SameOrigin(const aUrl, aOther: string): Boolean;
    // True while a redirect may still carry Authorization, Cookie and the rest
    function KeepsCredentials(const aFrom, aTo: string): Boolean;
    class function MethodToString(aMethod: TbpHttpMethod): string;

    // the WinInet session, opened on demand
    function SessionHandle: HINTERNET;
    function SessionActive: Boolean;

    // changing it drops the session, so set it before the first request
    property UserAgent: string read FUserAgent write SetUserAgent;
    property Username: AnsiString read FUsername write FUsername;
    property Password: AnsiString read FPassword write FPassword;
    // sent as 'Authorization: Bearer <token>'; replaces any Authorization set
    property BearerToken: string read FBearerToken write SetBearerToken;
    property ConnectTimeout: DWORD read FConnectTimeout write SetConnectTimeout;
    property SendTimeout: DWORD read FSendTimeout write SetSendTimeout;
    property ReceiveTimeout: DWORD read FReceiveTimeout write SetReceiveTimeout;
    property FollowRedirects: Boolean read FFollowRedirects write FFollowRedirects;
    // hops allowed before EbpHttpClient; 0 has the same effect as FollowRedirects False
    property MaxRedirects: Integer read FMaxRedirects write FMaxRedirects;
    // gzip and deflate on the buffered verbs, where no Content-Length is checked
    property AutoDecompress: Boolean read FAutoDecompress write FAutoDecompress;
    // ceiling for a body held in memory; 0 is no ceiling, as every mainstream
    // client defaults. A streamed Download never buffers, so it is unaffected
    property MaxResponseBytes: Int64 read FMaxResponseBytes write FMaxResponseBytes;
  end;

  TbpHttpDownloadState = (dtsPending, dtsRunning, dtsSucceeded, dtsFailed,
    dtsCancelled);

  TbpHttpDownloadCompleteEvent = procedure(aSender: TObject) of object;
  TbpHttpDownloadErrorEvent = procedure(aSender: TObject;
    const aErrorMessage: string) of object;

  // one download on an owned worker thread, C# Task style, one-shot
  TbpHttpDownloadTask = class
  private
    FTask: TbpTask;                // owned; the thread, the events, the states
    FClient: TbpHttpClient;        // owned; configure via Client before Start
    FLock: TRTLCriticalSection;    // guards the progress pair and the results
    FUrl: string;
    FDestFileName: string;
    FDestStream: TStream;          // caller-owned; must outlive the task
    FHeaders: string;
    FReceived: Int64;
    FTotal: Int64;
    FResponse: TbpHttpResponse;
    FErrorCode: DWORD;
    FHttpStatus: Integer;
    FOnProgress: TbpHttpProgressEvent;
    FOnComplete: TbpHttpDownloadCompleteEvent;
    FOnError: TbpHttpDownloadErrorEvent;
    function GetState: TbpHttpDownloadState;
    function GetMarshalToMainThread: Boolean;
    function GetToken: TbpCancellationToken;
    function GetReceived: Int64;
    function GetTotal: Int64;
    function GetResponse: TbpHttpResponse;
    function GetErrorMessage: string;
    function GetErrorCode: DWORD;
    function GetHttpStatus: Integer;
    procedure DoWork(aSender: TObject; aToken: TbpCancellationToken);
    procedure HandleWorkerProgress(aSender: TObject; const aReceived,
      aTotal: Int64; var aCancel: Boolean);
    procedure DispatchProgress(aSender: TObject);
    procedure DispatchComplete(aSender: TObject);
    procedure DispatchError(aSender: TObject; const aErrorMessage: string);
  public
    // create on the thread that should receive the events
    constructor Create(aMarshalToMainThread: Boolean = True);
    destructor Destroy; override;

    // returns immediately; raises when already started or misconfigured
    procedure Start;
    // prompt and safe from any thread, also before Start
    procedure Cancel;
    function WaitFor(aTimeoutMs: DWORD = INFINITE): Boolean;
    function IsFinished: Boolean;

    // configure before Start
    property Url: string read FUrl write FUrl;
    property DestFileName: string read FDestFileName write FDestFileName;
    property DestStream: TStream read FDestStream write FDestStream;
    property Headers: string read FHeaders write FHeaders;
    property Client: TbpHttpClient read FClient;  // timeouts, auth, proxy...
    property Token: TbpCancellationToken read GetToken;
    property MarshalToMainThread: Boolean read GetMarshalToMainThread;

    // results, thread-safe at any time; authoritative once IsFinished
    property State: TbpHttpDownloadState read GetState;
    property Received: Int64 read GetReceived;
    property Total: Int64 read GetTotal;   // -1 while or when unknown
    property Response: TbpHttpResponse read GetResponse;
    property ErrorMessage: string read GetErrorMessage;
    property ErrorCode: DWORD read GetErrorCode;        // WinInet error, 0 if none
    property HttpStatus: Integer read GetHttpStatus;    // status of a failed response

    // OnComplete fires on every terminal state; OnError first on dtsFailed
    property OnProgress: TbpHttpProgressEvent read FOnProgress write FOnProgress;
    property OnComplete: TbpHttpDownloadCompleteEvent read FOnComplete write FOnComplete;
    property OnError: TbpHttpDownloadErrorEvent read FOnError write FOnError;
  end;

// create, wire and start; caller frees. Two names: nil events break an overload
function BpDownloadAsync(const aUrl, aFileName: string;
  aOnProgress: TbpHttpProgressEvent = nil;
  aOnComplete: TbpHttpDownloadCompleteEvent = nil;
  aMarshalToMainThread: Boolean = True): TbpHttpDownloadTask;
function BpDownloadToStreamAsync(const aUrl: string; aDest: TStream;
  aOnProgress: TbpHttpProgressEvent = nil;
  aOnComplete: TbpHttpDownloadCompleteEvent = nil;
  aMarshalToMainThread: Boolean = True): TbpHttpDownloadTask;

function BpHttpResponseIsSuccess(const aResponse: TbpHttpResponse): Boolean;
// decodes the body as UTF-8; invalid bytes become U+FFFD, not an error
function BpHttpResponseBodyAsUtf8(const aResponse: TbpHttpResponse): WideString;
// value of a header line from a raw CRLF header block, '' when absent
function BpHttpHeaderValue(const aHeaders, aName: string): string;
// Content-Length parsed from a raw header block; -1 when absent or invalid
function BpHttpContentLength(const aHeaders: string): Int64;
// False for the replies that carry no body, whatever Content-Length says
function BpHttpResponseHasBody(const aMethod: string; aStatus: Integer): Boolean;
// reason phrase off the status line, '' when the server sent none
function BpHttpReasonPhrase(const aHeaders: string): string;
// absolute redirect target, '' when the reply is not a redirect or has no Location
function BpHttpRedirectTarget(const aBaseUrl, aHeaders: string; aStatus: Integer): string;
// the method the next hop uses, per the WHATWG fetch redirect rules
function BpHttpRedirectMethod(aStatus: Integer; const aMethod: string): string;
// drops the header lines that must not follow a redirect to another origin
function BpHttpStripCredentials(const aHeaders: string): string;
// drops the entity headers that described a body the next hop will not send
function BpHttpStripContentHeaders(const aHeaders: string): string;
// whole percent 0..100 for a progress pair; -1 when the total is unknown
function BpHttpProgressPercent(const aReceived, aTotal: Int64): Integer;
// user-facing categorization; pass 0 for the dimension that does not apply
function BpClassifyHttpError(aWinInetError: DWORD; aHttpStatus: Integer): string;

const
  // WinInet ERROR_INTERNET_OPERATION_CANCELLED, missing from D2007's WinInet.pas
  gcErrOperationCancelled = 12017;
  // INTERNET_OPTION_HTTP_DECODING, Vista and up, missing from D2007's WinInet.pas
  gcInternetOptionHttpDecoding = 65;
  gcBpHttpMaxRedirects = 10;

implementation

uses
  BpBase64;

const
  gcBufferSize = 8192;
  gcDownloadBufferSize = 65536;  // bigger chunks pay off on large bodies
  gcDefaultTimeout = 8000;  // milliseconds
  gcDefaultUserAgent = 'DelphiBoostPack/1.0';
  gcRequestContext = 1;  // non-zero, or WinInet skips its status callbacks

procedure AppendHeaderLine(var aHeaders: string; const aLine: string);
begin
  if aLine = '' then
    Exit;
  if aHeaders <> '' then
    aHeaders := aHeaders + #13#10;
  aHeaders := aHeaders + aLine;
end;

// walks a CRLF header block in place; aPos starts at 1, aName '' on a bad line
function NextHeaderLine(const aHeaders: string; var aPos: Integer;
  out aLine, aName: string): Boolean;
var
  lvEnd, lvColon, lvLen: Integer;
begin
  Result := False;
  lvLen := Length(aHeaders);
  while aPos <= lvLen do
  begin
    lvEnd := aPos;
    while (lvEnd <= lvLen) and (aHeaders[lvEnd] <> #13) and
      (aHeaders[lvEnd] <> #10) do
      Inc(lvEnd);
    aLine := Copy(aHeaders, aPos, lvEnd - aPos);
    if (lvEnd < lvLen) and (aHeaders[lvEnd] = #13) and
      (aHeaders[lvEnd + 1] = #10) then
      aPos := lvEnd + 2
    else
      aPos := lvEnd + 1;
    if aLine = '' then
      Continue;
    lvColon := Pos(':', aLine);
    if lvColon > 0 then
      aName := Trim(Copy(aLine, 1, lvColon - 1))
    else
      aName := '';
    Result := True;
    Exit;
  end;
end;

function HeaderBlockHasName(const aHeaders, aName: string): Boolean;
var
  lvPos: Integer;
  lvLine, lvName: string;
begin
  Result := False;
  if aName = '' then
    Exit;
  lvPos := 1;
  while NextHeaderLine(aHeaders, lvPos, lvLine, lvName) do
    if SameText(lvName, aName) then
    begin
      Result := True;
      Exit;
    end;
end;

// a CR or LF here would start another header line, overriding ours (CWE-113)
procedure BpCheckHeaderPart(const aText, aWhat: string);
var
  i: Integer;
begin
  for i := 1 to Length(aText) do
    if (aText[i] = #13) or (aText[i] = #10) then
      raise EbpHttpClient.CreateFmt('Header %s must not contain CR or LF', [aWhat]);
end;

// RFC 7230 tchar; Ord keeps the set legal on Unicode compilers too
function BpIsHeaderNameChar(aChar: Char): Boolean;
begin
  case Ord(aChar) of
    Ord('0')..Ord('9'), Ord('A')..Ord('Z'), Ord('a')..Ord('z'),
    Ord('!'), Ord('#')..Ord(''''), Ord('*'), Ord('+'), Ord('-'), Ord('.'),
    Ord('^')..Ord('`'), Ord('|'), Ord('~'):
      Result := True;
  else
    Result := False;
  end;
end;

// one bad name fails every later request on the client, not just this header
procedure BpCheckHeaderName(const aName: string);
var
  i: Integer;
begin
  if aName = '' then
    raise EbpHttpClient.Create('Header name must not be empty');
  for i := 1 to Length(aName) do
    if not BpIsHeaderNameChar(aName[i]) then
      raise EbpHttpClient.CreateFmt(
        'Header name must be a token, got %s', [aName]);
end;

// registered with the token so Cancel closes the handle of a blocked call
procedure BpCloseInetHandleCleanup(aData: Pointer);
begin
  InternetCloseHandle(HINTERNET(aData));
end;

procedure RaiseOperationCancelled;
begin
  raise EbpHttpClientCancelled.Create('Operation cancelled', 0,
    gcErrOperationCancelled);
end;

{ EbpHttpClient }

constructor EbpHttpClient.Create(const aMessage: string; aStatusCode: Integer;
  aWinInetError: DWORD);
begin
  inherited Create(aMessage);
  FStatusCode := aStatusCode;
  FWinInetError := aWinInetError;
end;

{ TbpHttpClient }

constructor TbpHttpClient.Create;
begin
  inherited Create;
  InitializeCriticalSection(FSessionLock);
  FUserAgent := gcDefaultUserAgent;
  FConnectTimeout := gcDefaultTimeout;
  FSendTimeout := gcDefaultTimeout;
  FReceiveTimeout := gcDefaultTimeout;
  FFollowRedirects := True;
  FMaxRedirects := gcBpHttpMaxRedirects;
  FAutoDecompress := True;
  FHeaders := TStringList.Create;
end;

destructor TbpHttpClient.Destroy;
begin
  CloseSession;
  FHeaders.Free;
  DeleteCriticalSection(FSessionLock);
  inherited;
end;

// the agent string is baked into the session by InternetOpen
procedure TbpHttpClient.SetUserAgent(const aValue: string);
begin
  // WinInet turns this into the User-Agent line, so it needs the same guard
  BpCheckHeaderPart(aValue, 'value');
  if aValue = FUserAgent then
    Exit;
  FUserAgent := aValue;
  CloseSession;
end;

procedure TbpHttpClient.SetConnectTimeout(aValue: DWORD);
begin
  FConnectTimeout := aValue;
  ApplyTimeoutsToSession;
end;

procedure TbpHttpClient.SetSendTimeout(aValue: DWORD);
begin
  FSendTimeout := aValue;
  ApplyTimeoutsToSession;
end;

procedure TbpHttpClient.SetReceiveTimeout(aValue: DWORD);
begin
  FReceiveTimeout := aValue;
  ApplyTimeoutsToSession;
end;

procedure TbpHttpClient.AddHeader(const aName, aValue: string);
begin
  BpCheckHeaderName(aName);
  BpCheckHeaderPart(aValue, 'value');
  FHeaders.Values[aName] := aValue;
  // Authorization has one writer at a time, or the block goes out with two
  if SameText(aName, 'Authorization') then
    FBearerToken := '';
end;

procedure TbpHttpClient.SetBearerToken(const aValue: string);
begin
  BpCheckHeaderPart(aValue, 'value');
  FBearerToken := aValue;
  if aValue <> '' then
    FHeaders.Values['Authorization'] := '';
end;

procedure TbpHttpClient.ClearHeaders;
begin
  FHeaders.Clear;
end;

procedure TbpHttpClient.SetBasicAuth(const aUser, aPassword: WideString);
var
  i: Integer;
begin
  // RFC 7617: the colon separates the pair, so the user-id may not hold one
  for i := 1 to Length(aUser) do
    if (aUser[i] = ':') or (Ord(aUser[i]) < 32) then
      raise EbpHttpClient.Create(
        'Basic auth user must not contain a colon or a control character');
  // RFC 7617 says UTF-8, and the ANSI page would differ from machine to machine
  AddHeader('Authorization', 'Basic ' +
    Base64EncodeUtf8(aUser + ':' + aPassword));
end;

class function TbpHttpClient.MethodToString(aMethod: TbpHttpMethod): string;
begin
  case aMethod of
    hmGet: Result := 'GET';
    hmPost: Result := 'POST';
    hmPut: Result := 'PUT';
    hmDelete: Result := 'DELETE';
    hmPatch: Result := 'PATCH';
    hmHead: Result := 'HEAD';
    hmOptions: Result := 'OPTIONS';
  else
    Result := 'GET';
  end;
end;

function TbpHttpClient.GetWinInetErrorMessage(aErrorCode: DWORD): string;
var
  lvBuffer: array[0..1023] of Char;
  lvLen: DWORD;
begin
  lvLen := FormatMessage(
    FORMAT_MESSAGE_FROM_HMODULE or FORMAT_MESSAGE_FROM_SYSTEM,
    Pointer(GetModuleHandle('wininet.dll')),
    aErrorCode,
    0,
    lvBuffer,
    Length(lvBuffer),
    nil);

  if lvLen > 0 then
  begin
    SetString(Result, lvBuffer, lvLen);
    Result := Trim(Result);
  end
  else
    Result := Format('WinInet error %d', [aErrorCode]);
end;

// InternetCrackUrl reports one url component as a pointer and a length
function CrackedPart(aText: PChar; aLen: DWORD): string;
begin
  if (aText = nil) or (aLen = 0) then
    Result := ''
  else
    SetString(Result, aText, aLen);
end;

// curl, requests, axios and .NET all read user:pass@host as Basic auth
function TbpHttpClient.UrlBasicAuth(const aUrl: string): string;
var
  lvComponents: TURLComponents;
  lvUser, lvPassword: AnsiString;
  lvCopy: string;
begin
  Result := '';
  // asked for the userinfo, InternetCrackUrl unescapes the buffer in place, so
  // it never gets the caller's string, and the parts come back already decoded
  lvCopy := Copy(aUrl, 1, Length(aUrl));
  ZeroMemory(@lvComponents, SizeOf(lvComponents));
  lvComponents.dwStructSize := SizeOf(lvComponents);
  // a nil buffer with a non-zero length asks for pointers into the url itself
  lvComponents.dwUserNameLength := 1;
  lvComponents.dwPasswordLength := 1;
  if not InternetCrackUrl(PChar(lvCopy), Length(lvCopy), 0, lvComponents) then
    Exit;
  lvUser := CrackedPart(lvComponents.lpszUserName,
    lvComponents.dwUserNameLength);
  if lvUser = '' then
    Exit;
  lvPassword := CrackedPart(lvComponents.lpszPassword,
    lvComponents.dwPasswordLength);
  Result := 'Basic ' + Base64Encode(lvUser + ':' + lvPassword);
end;

function TbpHttpClient.ParseUrl(const aUrl: string; out aServerName,
  aResource: string; out aPort: Integer; out aSecure: Boolean): Boolean;
var
  lvComponents: TURLComponents;
  lvHash, i: Integer;
begin
  Result := False;

  // InternetCrackUrl drops CR, LF and TAB instead of failing the parse
  for i := 1 to Length(aUrl) do
    if Ord(aUrl[i]) < 32 then
      Exit;

  ZeroMemory(@lvComponents, SizeOf(lvComponents));
  lvComponents.dwStructSize := SizeOf(lvComponents);
  // a nil buffer with a non-zero length asks for pointers into aUrl itself
  lvComponents.dwHostNameLength := 1;
  lvComponents.dwUrlPathLength := 1;
  lvComponents.dwExtraInfoLength := 1;

  if not InternetCrackUrl(PChar(aUrl), Length(aUrl), 0, lvComponents) then
    Exit;

  // an ftp, file or mailto url must not become an http request to its host
  if not (lvComponents.nScheme in [INTERNET_SCHEME_HTTP, INTERNET_SCHEME_HTTPS]) then
    Exit;

  aServerName := CrackedPart(lvComponents.lpszHostName,
    lvComponents.dwHostNameLength);
  if aServerName = '' then
    Exit;
  // the extra info is the query string, and it stays on the resource
  aResource := CrackedPart(lvComponents.lpszUrlPath, lvComponents.dwUrlPathLength) +
    CrackedPart(lvComponents.lpszExtraInfo, lvComponents.dwExtraInfoLength);
  // the fragment is client side only, it never goes into the request line
  lvHash := Pos('#', aResource);
  if lvHash > 0 then
    SetLength(aResource, lvHash - 1);
  if aResource = '' then
    aResource := '/';

  aPort := lvComponents.nPort;
  aSecure := lvComponents.nScheme = INTERNET_SCHEME_HTTPS;

  if aPort = 0 then
  begin
    if aSecure then
      aPort := INTERNET_DEFAULT_HTTPS_PORT
    else
      aPort := INTERNET_DEFAULT_HTTP_PORT;
  end;

  Result := True;
end;

function TbpHttpClient.SameOrigin(const aUrl, aOther: string): Boolean;
var
  lvHost, lvOtherHost, lvResource: string;
  lvPort, lvOtherPort: Integer;
  lvSecure, lvOtherSecure: Boolean;
begin
  Result := ParseUrl(aUrl, lvHost, lvResource, lvPort, lvSecure) and
    ParseUrl(aOther, lvOtherHost, lvResource, lvOtherPort, lvOtherSecure) and
    (lvSecure = lvOtherSecure) and (lvPort = lvOtherPort) and
    SameText(lvHost, lvOtherHost);
end;

// same origin, or the http to https upgrade requests deliberately allows
function TbpHttpClient.KeepsCredentials(const aFrom, aTo: string): Boolean;
var
  lvHost, lvToHost, lvResource: string;
  lvPort, lvToPort: Integer;
  lvSecure, lvToSecure: Boolean;
begin
  Result := ParseUrl(aFrom, lvHost, lvResource, lvPort, lvSecure) and
    ParseUrl(aTo, lvToHost, lvResource, lvToPort, lvToSecure) and
    SameText(lvHost, lvToHost) and
    (((lvSecure = lvToSecure) and (lvPort = lvToPort)) or
     (not lvSecure and lvToSecure and (lvPort = INTERNET_DEFAULT_HTTP_PORT) and
      (lvToPort = INTERNET_DEFAULT_HTTPS_PORT)));
end;

function TbpHttpClient.BuildHeaders(const aRequestHeaders: string;
  aWithCredentials: Boolean): string;
var
  i: Integer;
  lvRequest: string;
begin
  Result := '';
  lvRequest := Trim(aRequestHeaders);
  // another origin gets no persistent header of ours and no caller credential
  if not aWithCredentials then
  begin
    Result := BpHttpStripCredentials(lvRequest);
    Exit;
  end;
  // a per-request line replaces the persistent one, rather than joining it
  for i := 0 to FHeaders.Count - 1 do
    if not HeaderBlockHasName(lvRequest, FHeaders.Names[i]) then
      AppendHeaderLine(Result, FHeaders.Names[i] + ': ' + FHeaders.ValueFromIndex[i]);
  if (FBearerToken <> '') and not HeaderBlockHasName(lvRequest, 'Authorization') then
    AppendHeaderLine(Result, 'Authorization: Bearer ' + FBearerToken);
  AppendHeaderLine(Result, lvRequest);
end;

function TbpHttpClient.CreateSession: HINTERNET;
var
  lvErr: DWORD;
begin
  Result := InternetOpen(
    PChar(FUserAgent),
    INTERNET_OPEN_TYPE_PRECONFIG,
    nil,
    nil,
    0);

  if Result = nil then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      'Failed to initialize HTTP session: ' + GetWinInetErrorMessage(lvErr),
      0, lvErr);
  end;

  ApplyTimeouts(Result);
end;

function TbpHttpClient.SessionActive: Boolean;
begin
  EnterCriticalSection(FSessionLock);
  try
    Result := FSession <> nil;
  finally
    LeaveCriticalSection(FSessionLock);
  end;
end;

// lazy, one per client; WinInet pools its keep-alive connections here
function TbpHttpClient.SessionHandle: HINTERNET;
begin
  EnterCriticalSection(FSessionLock);
  try
    if FSession = nil then
      FSession := CreateSession;
    Result := FSession;
  finally
    LeaveCriticalSection(FSessionLock);
  end;
end;

// drops the pooled connections; the next request opens a new session
procedure TbpHttpClient.CloseSession;
var
  lvSession: HINTERNET;
begin
  EnterCriticalSection(FSessionLock);
  try
    lvSession := FSession;
    FSession := nil;
  finally
    LeaveCriticalSection(FSessionLock);
  end;
  if lvSession <> nil then
    InternetCloseHandle(lvSession);
end;

// timeouts live on the session handle, so a live one needs them again
procedure TbpHttpClient.ApplyTimeoutsToSession;
begin
  EnterCriticalSection(FSessionLock);
  try
    if FSession <> nil then
      ApplyTimeouts(FSession);
  finally
    LeaveCriticalSection(FSessionLock);
  end;
end;

function TbpHttpClient.CreateConnection(aSession: HINTERNET;
  const aServerName: string; aPort: Integer): HINTERNET;
var
  lvErr: DWORD;
begin
  Result := InternetConnect(
    aSession,
    PChar(aServerName),
    aPort,
    nil,
    nil,
    INTERNET_SERVICE_HTTP,
    0,
    gcRequestContext);

  if Result = nil then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      Format('Failed to connect to %s:%d: %s',
        [aServerName, aPort, GetWinInetErrorMessage(lvErr)]),
      0, lvErr);
  end;
end;

function TbpHttpClient.CreateRequest(aConnection: HINTERNET;
  const aMethod, aResource: string; aSecure: Boolean): HINTERNET;
var
  lvFlags, lvErr: DWORD;
begin
  // keep-alive: without it WinInet may drop the pooled connection
  lvFlags := INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or
    INTERNET_FLAG_KEEP_CONNECTION;

  if aSecure then
    lvFlags := lvFlags or INTERNET_FLAG_SECURE;

  // always ours to follow: WinInet replays the header block, secrets included
  lvFlags := lvFlags or INTERNET_FLAG_NO_AUTO_REDIRECT;

  // that jar is the user's own, keyed by host, and outlives every strip we do
  lvFlags := lvFlags or INTERNET_FLAG_NO_COOKIES;

  Result := HttpOpenRequest(
    aConnection,
    PChar(aMethod),
    PChar(aResource),
    nil,  // nil version defaults to HTTP/1.1 on any non-ancient Windows
    nil,
    nil,
    lvFlags,
    gcRequestContext);

  if Result = nil then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      Format('Failed to create HTTP request for %s: %s',
        [aResource, GetWinInetErrorMessage(lvErr)]),
      0, lvErr);
  end;
end;

procedure TbpHttpClient.ApplyTimeouts(aHandle: HINTERNET);
begin
  if FConnectTimeout > 0 then
    InternetSetOption(aHandle, INTERNET_OPTION_CONNECT_TIMEOUT,
      @FConnectTimeout, SizeOf(FConnectTimeout));

  if FSendTimeout > 0 then
    InternetSetOption(aHandle, INTERNET_OPTION_SEND_TIMEOUT,
      @FSendTimeout, SizeOf(FSendTimeout));

  if FReceiveTimeout > 0 then
    InternetSetOption(aHandle, INTERNET_OPTION_RECEIVE_TIMEOUT,
      @FReceiveTimeout, SizeOf(FReceiveTimeout));
end;

procedure TbpHttpClient.ApplyAuthentication(aRequest: HINTERNET);
begin
  // WinInet-level credentials, also used for proxy and 401 challenges
  if FUsername <> '' then
    InternetSetOption(aRequest, INTERNET_OPTION_USERNAME,
      @FUsername[1], Length(FUsername));

  if FPassword <> '' then
    InternetSetOption(aRequest, INTERNET_OPTION_PASSWORD,
      @FPassword[1], Length(FPassword));
end;

// pre-Vista WinInet rejects the option, and then we simply get the bytes raw
procedure TbpHttpClient.ApplyDecoding(aRequest: HINTERNET);
var
  lvOn: BOOL;
begin
  lvOn := True;
  InternetSetOption(aRequest, gcInternetOptionHttpDecoding, @lvOn, SizeOf(lvOn));
end;

procedure TbpHttpClient.SendHttpRequest(aRequest: HINTERNET;
  const aHeaders: string; const aBody: AnsiString);
var
  lvHeadersPtr: PChar;
  lvHeadersLen: DWORD;
  lvBodyPtr: Pointer;
  lvBodyLen, lvErr: DWORD;
begin
  if aHeaders <> '' then
  begin
    lvHeadersPtr := PChar(aHeaders);
    lvHeadersLen := Length(aHeaders);
  end
  else
  begin
    lvHeadersPtr := nil;
    lvHeadersLen := 0;
  end;

  if Length(aBody) > 0 then
  begin
    lvBodyPtr := @aBody[1];
    lvBodyLen := Length(aBody);
  end
  else
  begin
    lvBodyPtr := nil;
    lvBodyLen := 0;
  end;

  if not HttpSendRequest(aRequest, lvHeadersPtr, lvHeadersLen,
    lvBodyPtr, lvBodyLen) then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      'Failed to send HTTP request: ' + GetWinInetErrorMessage(lvErr),
      0, lvErr);
  end;
end;

function TbpHttpClient.ReadResponseStatus(aRequest: HINTERNET): Integer;
var
  lvStatusCode, lvBufferLen, lvReserved, lvErr: DWORD;
begin
  lvBufferLen := SizeOf(lvStatusCode);
  lvReserved := 0;

  if not HttpQueryInfo(
    aRequest,
    HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER,
    @lvStatusCode,
    lvBufferLen,
    lvReserved) then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      'Failed to query HTTP status code: ' + GetWinInetErrorMessage(lvErr),
      0, lvErr);
  end;

  Result := lvStatusCode;
end;

function TbpHttpClient.ReadResponseHeaders(aRequest: HINTERNET): string;
var
  lvSize, lvReserved: DWORD;
begin
  Result := '';
  lvSize := 0;
  lvReserved := 0;

  // first call just reports the required buffer size
  if HttpQueryInfo(aRequest, HTTP_QUERY_RAW_HEADERS_CRLF, nil, lvSize, lvReserved) then
    Exit;
  if GetLastError <> ERROR_INSUFFICIENT_BUFFER then
    Exit;

  SetLength(Result, lvSize div SizeOf(Char));
  if HttpQueryInfo(aRequest, HTTP_QUERY_RAW_HEADERS_CRLF, PChar(Result),
    lvSize, lvReserved) then
    SetLength(Result, lvSize div SizeOf(Char))
  else
    Result := '';
end;

function TbpHttpClient.ReadResponseBody(aRequest: HINTERNET;
  aToken: TbpCancellationToken): AnsiString;
var
  lvBytesRead, lvErr: DWORD;
  lvSize, lvCapacity: Integer;
begin
  Result := '';
  lvSize := 0;
  lvCapacity := 0;
  repeat
    if (aToken <> nil) and aToken.IsCancellationRequested then
      RaiseOperationCancelled;
    if (FMaxResponseBytes > 0) and (lvSize > FMaxResponseBytes) then
      raise EbpHttpClient.CreateFmt(
        'Response body is larger than MaxResponseBytes (%d)',
        [FMaxResponseBytes]);

    if lvCapacity - lvSize < gcBufferSize then
    begin
      if lvCapacity > MaxInt div 2 then
        raise EbpHttpClient.Create('Response body is too large to buffer');
      // doubling keeps the reallocations logarithmic in the body size
      if lvCapacity = 0 then
        lvCapacity := gcBufferSize
      else
        lvCapacity := lvCapacity * 2;
      SetLength(Result, lvCapacity);
    end;

    if not InternetReadFile(aRequest, @Result[lvSize + 1], gcBufferSize,
      lvBytesRead) then
    begin
      lvErr := GetLastError;
      raise EbpHttpClient.Create(
        'Failed to read HTTP response: ' + GetWinInetErrorMessage(lvErr),
        0, lvErr);
    end;

    Inc(lvSize, lvBytesRead);
  until lvBytesRead = 0;

  SetLength(Result, lvSize);
end;

procedure TbpHttpClient.ReadBodyToStream(aRequest: HINTERNET; aDest: TStream;
  const aTotal: Int64; aProgress: TbpHttpProgressEvent;
  aToken: TbpCancellationToken);
var
  lvBuffer: array[0..gcDownloadBufferSize - 1] of Byte;
  lvBytesRead, lvErr: DWORD;
  lvReceived: Int64;
  lvCancel: Boolean;
begin
  lvReceived := 0;
  if Assigned(aProgress) then
  begin
    // headers are in; announce the total before the first byte
    lvCancel := False;
    aProgress(Self, 0, aTotal, lvCancel);
    if lvCancel then
      RaiseOperationCancelled;
  end;

  repeat
    if (aToken <> nil) and aToken.IsCancellationRequested then
      RaiseOperationCancelled;

    if not InternetReadFile(aRequest, @lvBuffer[0], gcDownloadBufferSize,
      lvBytesRead) then
    begin
      lvErr := GetLastError;
      raise EbpHttpClient.Create(
        'Failed to read HTTP response: ' + GetWinInetErrorMessage(lvErr),
        0, lvErr);
    end;

    if lvBytesRead > 0 then
    begin
      aDest.WriteBuffer(lvBuffer[0], lvBytesRead);
      Inc(lvReceived, lvBytesRead);
      if Assigned(aProgress) then
      begin
        lvCancel := False;
        aProgress(Self, lvReceived, aTotal, lvCancel);
        if lvCancel then
          RaiseOperationCancelled;
      end;
    end;
  until lvBytesRead = 0;

  // a dropped connection reads as a clean end of stream, so count the bytes
  if (aTotal >= 0) and (lvReceived <> aTotal) then
    raise EbpHttpClient.CreateFmt(
      'Incomplete response: received %d of %d bytes', [lvReceived, aTotal]);
end;

function TbpHttpClient.PerformHop(const aUrl, aMethod, aHeaders: string;
  const aBody: AnsiString; aWithCredentials, aDropContentHeaders: Boolean;
  aDest: TStream; aProgress: TbpHttpProgressEvent;
  aToken: TbpCancellationToken; out aRedirectTo: string): TbpHttpResponse;
var
  lvConnection, lvRequest: HINTERNET;
  lvServerName, lvResource: string;
  lvPort: Integer;
  lvSecure, lvOwnsRequest: Boolean;
  lvCleanupId: Integer;
  lvBlock: string;
begin
  aRedirectTo := '';
  if (aToken <> nil) and aToken.IsCancellationRequested then
    RaiseOperationCancelled;
  if not ParseUrl(aUrl, lvServerName, lvResource, lvPort, lvSecure) then
    raise EbpHttpClient.Create('Invalid URL: ' + aUrl);

  // the instance owns the session; it is not closed here
  lvConnection := CreateConnection(SessionHandle, lvServerName, lvPort);
  try
    lvRequest := CreateRequest(lvConnection, aMethod, lvResource, lvSecure);
    // Cancel closes this handle, so a blocked call fails over at once
    lvOwnsRequest := True;
    lvCleanupId := 0;
    if aToken <> nil then
      if not aToken.RegisterCleanup(BpCloseInetHandleCleanup, lvRequest,
        lvCleanupId) then
      begin
        // cancelled between the check above and here
        InternetCloseHandle(lvRequest);
        RaiseOperationCancelled;
      end;
    try
      try
        if aWithCredentials then
          ApplyAuthentication(lvRequest);
        lvBlock := BuildHeaders(aHeaders, aWithCredentials);
        // a persistent Content-Type described the dropped body just as much
        if aDropContentHeaders then
          lvBlock := BpHttpStripContentHeaders(lvBlock);
        // decoded bytes outnumber Content-Length, so not where it is checked
        if FAutoDecompress and (aDest = nil) then
        begin
          ApplyDecoding(lvRequest);
          if not HeaderBlockHasName(lvBlock, 'Accept-Encoding') then
            AppendHeaderLine(lvBlock, 'Accept-Encoding: gzip, deflate');
        end;
        SendHttpRequest(lvRequest, lvBlock, aBody);

        Result.StatusCode := ReadResponseStatus(lvRequest);
        Result.Headers := ReadResponseHeaders(lvRequest);
        Result.StatusText := BpHttpReasonPhrase(Result.Headers);
        if Result.StatusText = '' then
          Result.StatusText := Format('HTTP %d', [Result.StatusCode]);
        Result.ContentLength := BpHttpContentLength(Result.Headers);
        Result.FinalUrl := aUrl;
        Result.Body := '';
        // a budget of none is documented as behaving like FollowRedirects False
        if FFollowRedirects and (FMaxRedirects > 0) then
          aRedirectTo := BpHttpRedirectTarget(aUrl, Result.Headers, Result.StatusCode);

        // WinInet honours Content-Length even on a 304, so never read one
        if BpHttpResponseHasBody(aMethod, Result.StatusCode) then
        begin
          // the else drains a redirect body, which keeps the connection pooled
          if (aDest <> nil) and (aRedirectTo = '') then
            ReadBodyToStream(lvRequest, aDest, Result.ContentLength,
              aProgress, aToken)
          else
            Result.Body := ReadResponseBody(lvRequest, aToken);
        end;
      except
        // a failure caused by Cancel surfaces as the typed cancellation
        on E: EbpHttpClient do
          if (aToken <> nil) and aToken.IsCancellationRequested and
            not (E is EbpHttpClientCancelled) then
            RaiseOperationCancelled
          else
            raise;
      end;
    finally
      // Unregister hands the handle back, unless Cancel already closed it
      if aToken <> nil then
        lvOwnsRequest := aToken.UnregisterCleanup(lvCleanupId);
      if lvOwnsRequest then
        InternetCloseHandle(lvRequest);
    end;
  finally
    InternetCloseHandle(lvConnection);
  end;
end;

function TbpHttpClient.PerformRequest(const aUrl, aMethod, aHeaders: string;
  const aBody: AnsiString; aDest: TStream; aProgress: TbpHttpProgressEvent;
  aToken: TbpCancellationToken): TbpHttpResponse;
var
  lvUrl, lvMethod, lvNext, lvHeaders, lvAuth: string;
  lvBody: AnsiString;
  lvCredentials, lvDroppedBody: Boolean;
  i: Integer;
begin
  lvUrl := aUrl;
  lvMethod := aMethod;
  lvBody := aBody;
  lvHeaders := aHeaders;
  lvCredentials := True;
  lvDroppedBody := False;
  // an Authorization the caller set wins; a foreign origin sees neither, because
  // this line is a request header and BuildHeaders strips those off origin
  if BpHttpHeaderValue(BuildHeaders(aHeaders), 'Authorization') = '' then
  begin
    lvAuth := UrlBasicAuth(aUrl);
    if lvAuth <> '' then
      lvHeaders := 'Authorization: ' + lvAuth + #13#10 + lvHeaders;
  end;
  for i := 0 to FMaxRedirects do
  begin
    Result := PerformHop(lvUrl, lvMethod, lvHeaders, lvBody, lvCredentials,
      lvDroppedBody, aDest, aProgress, aToken, lvNext);
    if lvNext = '' then
      Exit;
    lvMethod := BpHttpRedirectMethod(Result.StatusCode, lvMethod);
    // the body is gone, so the headers that described it must go too
    if lvMethod <> aMethod then
    begin
      lvBody := '';
      lvDroppedBody := True;
    end;
    lvUrl := lvNext;
    // once off the origin they were set for, credentials never come back
    lvCredentials := lvCredentials and KeepsCredentials(aUrl, lvUrl);
  end;
  raise EbpHttpClient.CreateFmt('More than %d redirects for %s',
    [FMaxRedirects, aUrl]);
end;

function TbpHttpClient.Execute(const aUrl: string; aMethod: TbpHttpMethod;
  const aHeaders: string; const aBody: AnsiString;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := PerformRequest(aUrl, MethodToString(aMethod), aHeaders, aBody,
    nil, nil, aToken);
end;

function TbpHttpClient.Get(const aUrl: string; const aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmGet, aHeaders, '', aToken);
end;

function TbpHttpClient.Post(const aUrl: string; const aBody: AnsiString;
  const aHeaders: string; aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmPost, aHeaders, aBody, aToken);
end;

function TbpHttpClient.PostJson(const aUrl: string; const aJson: AnsiString;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmPost, 'Content-Type: application/json', aJson, aToken);
end;

function TbpHttpClient.Put(const aUrl: string; const aBody: AnsiString;
  const aHeaders: string; aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmPut, aHeaders, aBody, aToken);
end;

function TbpHttpClient.Delete(const aUrl: string; const aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmDelete, aHeaders, '', aToken);
end;

function TbpHttpClient.Patch(const aUrl: string; const aBody: AnsiString;
  const aHeaders: string; aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmPatch, aHeaders, aBody, aToken);
end;

function TbpHttpClient.Head(const aUrl, aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmHead, aHeaders, '', aToken);
end;

function TbpHttpClient.Options(const aUrl, aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(aUrl, hmOptions, aHeaders, '', aToken);
end;

class function TbpHttpClient.FetchUrl(const aUrl: string;
  const aHeaders: string): AnsiString;
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  lvClient := TbpHttpClient.Create;
  try
    lvResponse := lvClient.Get(aUrl, aHeaders);
    Result := lvResponse.Body;
  finally
    lvClient.Free;
  end;
end;

function TbpHttpClient.Download(const aUrl: string; aDest: TStream;
  aProgress: TbpHttpProgressEvent; aToken: TbpCancellationToken;
  const aHeaders: string; const aMethod: string): TbpHttpResponse;
begin
  if aDest = nil then
    raise EbpHttpClient.Create('Download destination stream is nil');
  Result := PerformRequest(aUrl, aMethod, aHeaders, '', aDest, aProgress,
    aToken);
end;

// beside the destination, so the rename stays on one volume; Windows names it
function BpTempFileNear(const aFileName: string): string;
var
  lvDir: string;
  lvErr: DWORD;
  lvBuffer: array[0..MAX_PATH] of Char;
begin
  lvDir := ExtractFilePath(ExpandFileName(aFileName));
  if GetTempFileName(PChar(lvDir), 'bp', 0, lvBuffer) = 0 then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.CreateFmt(
      'Cannot create a temporary file in %s: Windows error %d', [lvDir, lvErr]);
  end;
  Result := lvBuffer;
end;

// one step on the same volume, so the destination is never briefly missing
procedure BpReplaceFile(const aTemp, aFileName: string);
var
  lvErr: DWORD;
begin
  if MoveFileEx(PChar(aTemp), PChar(aFileName), MOVEFILE_REPLACE_EXISTING) then
    Exit;
  lvErr := GetLastError;
  raise EbpHttpClient.CreateFmt(
    'Cannot replace %s with the downloaded file: Windows error %d',
    [aFileName, lvErr]);
end;

// a typo in the url used to cost the caller the file that was already there
function TbpHttpClient.DownloadToFile(const aUrl, aFileName: string;
  aProgress: TbpHttpProgressEvent; aToken: TbpCancellationToken;
  const aHeaders: string): TbpHttpResponse;
var
  lvFile: TFileStream;
  lvTemp: string;
  lvDone: Boolean;
begin
  lvDone := False;
  lvTemp := BpTempFileNear(aFileName);
  try
    lvFile := TFileStream.Create(lvTemp, fmCreate);
    try
      Result := Download(aUrl, lvFile, aProgress, aToken, aHeaders);
    finally
      lvFile.Free;
    end;
    // 206 carries a fragment, and this call asked for a whole file; returning it
    // would look like success to BpHttpResponseIsSuccess and quietly truncate
    if Result.StatusCode = 206 then
      raise EbpHttpClient.Create(
        'Server answered 206 Partial Content for a whole-file download',
        Result.StatusCode);
    if BpHttpResponseIsSuccess(Result) then
    begin
      BpReplaceFile(lvTemp, aFileName);
      lvDone := True;
    end;
  finally
    // every other path, a failed rename included, leaves no temp file behind
    if not lvDone then
      SysUtils.DeleteFile(lvTemp);
  end;
end;

{ TbpHttpDownloadTask }

// TbpTask owns the thread, the marshalling window and the state machine, so
// what is left here is the download itself and the shape of its events.

constructor TbpHttpDownloadTask.Create(aMarshalToMainThread: Boolean);
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FTotal := -1;
  FClient := TbpHttpClient.Create;
  try
    FTask := TbpTask.Create(aMarshalToMainThread);
  except
    // this unit promises EbpHttpClient, and a missing dispatcher is its problem
    on E: EbpTask do
      raise EbpHttpClient.Create(E.Message);
  end;
  FTask.Work := DoWork;
  FTask.OnProgress := DispatchProgress;
  FTask.OnComplete := DispatchComplete;
  FTask.OnError := DispatchError;
end;

destructor TbpHttpDownloadTask.Destroy;
begin
  // cancels, joins, and lets no further event start; the worker holds FClient
  FTask.Free;
  FClient.Free;
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpHttpDownloadTask.GetState: TbpHttpDownloadState;
const
  lcStates: array[TbpTaskState] of TbpHttpDownloadState = (dtsPending,
    dtsRunning, dtsSucceeded, dtsFailed, dtsCancelled);
begin
  Result := lcStates[FTask.State];
end;

function TbpHttpDownloadTask.GetMarshalToMainThread: Boolean;
begin
  Result := FTask.MarshalToMainThread;
end;

function TbpHttpDownloadTask.GetToken: TbpCancellationToken;
begin
  Result := FTask.Token;
end;

function TbpHttpDownloadTask.GetReceived: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FReceived;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetTotal: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FTotal;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetResponse: TbpHttpResponse;
begin
  EnterCriticalSection(FLock);
  Result := FResponse;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetErrorMessage: string;
begin
  Result := FTask.ErrorMessage;
end;

function TbpHttpDownloadTask.GetErrorCode: DWORD;
begin
  EnterCriticalSection(FLock);
  Result := FErrorCode;
  LeaveCriticalSection(FLock);
  // a cancel before the first byte never reached WinInet, but the caller
  // checks the same code whenever the download ends cancelled
  if (Result = 0) and (GetState = dtsCancelled) then
    Result := gcErrOperationCancelled;
end;

function TbpHttpDownloadTask.GetHttpStatus: Integer;
begin
  EnterCriticalSection(FLock);
  Result := FHttpStatus;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.IsFinished: Boolean;
begin
  Result := FTask.IsFinished;
end;

procedure TbpHttpDownloadTask.Start;
begin
  if FUrl = '' then
    raise EbpHttpClient.Create('Download task has no Url');
  if (FDestFileName = '') and (FDestStream = nil) then
    raise EbpHttpClient.Create('Download task has no destination (set DestFileName or DestStream)');
  if (FDestFileName <> '') and (FDestStream <> nil) then
    raise EbpHttpClient.Create('Download task has both DestFileName and DestStream; set only one');

  try
    FTask.Start;
  except
    // Work is wired in the constructor, so a second start is the only EbpTask
    on EbpTask do
      raise EbpHttpClient.Create('Download task already started');
  end;
end;

procedure TbpHttpDownloadTask.Cancel;
begin
  FTask.Cancel;
end;

function TbpHttpDownloadTask.WaitFor(aTimeoutMs: DWORD): Boolean;
begin
  Result := FTask.WaitFor(aTimeoutMs);
end;

// worker thread: publish the pair, then ask for one coalesced note
procedure TbpHttpDownloadTask.HandleWorkerProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  EnterCriticalSection(FLock);
  FReceived := aReceived;
  FTotal := aTotal;
  LeaveCriticalSection(FLock);
  if Assigned(FOnProgress) then
    FTask.ReportProgress;
end;

// event thread: a handler that sets aCancel cancels through the token, so a
// direct-mode and a marshalled download stop the same way
procedure TbpHttpDownloadTask.DispatchProgress(aSender: TObject);
var
  lvReceived, lvTotal: Int64;
  lvCancel: Boolean;
begin
  if not Assigned(FOnProgress) then
    Exit;
  EnterCriticalSection(FLock);
  lvReceived := FReceived;
  lvTotal := FTotal;
  LeaveCriticalSection(FLock);
  lvCancel := False;
  FOnProgress(Self, lvReceived, lvTotal, lvCancel);
  if lvCancel then
    Cancel;
end;

// the handler may free this task, so nothing here may touch Self afterwards
procedure TbpHttpDownloadTask.DispatchComplete(aSender: TObject);
begin
  if Assigned(FOnComplete) then
    FOnComplete(Self);
end;

procedure TbpHttpDownloadTask.DispatchError(aSender: TObject;
  const aErrorMessage: string);
begin
  if Assigned(FOnError) then
    FOnError(Self, aErrorMessage);
end;

procedure TbpHttpDownloadTask.DoWork(aSender: TObject;
  aToken: TbpCancellationToken);
var
  lvResponse: TbpHttpResponse;
begin
  try
    if FDestFileName <> '' then
      lvResponse := FClient.DownloadToFile(FUrl, FDestFileName,
        HandleWorkerProgress, aToken, FHeaders)
    else
      lvResponse := FClient.Download(FUrl, FDestStream,
        HandleWorkerProgress, aToken, FHeaders);
  except
    on E: EbpHttpClient do
    begin
      EnterCriticalSection(FLock);
      FErrorCode := E.WinInetError;
      FHttpStatus := E.StatusCode;
      LeaveCriticalSection(FLock);
      raise;
    end;
  end;

  EnterCriticalSection(FLock);
  FResponse := lvResponse;
  LeaveCriticalSection(FLock);
  if BpHttpResponseIsSuccess(lvResponse) then
    Exit;

  EnterCriticalSection(FLock);
  FHttpStatus := lvResponse.StatusCode;
  LeaveCriticalSection(FLock);
  // a status the caller did not ask for is a failure, not an exception path
  raise EbpHttpClient.Create(BpClassifyHttpError(0, lvResponse.StatusCode),
    lvResponse.StatusCode);
end;

{ hot task factories }

function BpDownloadAsync(const aUrl, aFileName: string;
  aOnProgress: TbpHttpProgressEvent; aOnComplete: TbpHttpDownloadCompleteEvent;
  aMarshalToMainThread: Boolean): TbpHttpDownloadTask;
begin
  Result := TbpHttpDownloadTask.Create(aMarshalToMainThread);
  try
    Result.Url := aUrl;
    Result.DestFileName := aFileName;
    Result.OnProgress := aOnProgress;
    Result.OnComplete := aOnComplete;
    Result.Start;
  except
    Result.Free;
    raise;
  end;
end;

function BpDownloadToStreamAsync(const aUrl: string; aDest: TStream;
  aOnProgress: TbpHttpProgressEvent; aOnComplete: TbpHttpDownloadCompleteEvent;
  aMarshalToMainThread: Boolean): TbpHttpDownloadTask;
begin
  Result := TbpHttpDownloadTask.Create(aMarshalToMainThread);
  try
    Result.Url := aUrl;
    Result.DestStream := aDest;
    Result.OnProgress := aOnProgress;
    Result.OnComplete := aOnComplete;
    Result.Start;
  except
    Result.Free;
    raise;
  end;
end;

{ helper functions }

function BpHttpResponseIsSuccess(const aResponse: TbpHttpResponse): Boolean;
begin
  Result := (aResponse.StatusCode >= 200) and (aResponse.StatusCode < 300);
end;

function BpHttpResponseBodyAsUtf8(const aResponse: TbpHttpResponse): WideString;
var
  lvLen: Integer;
begin
  Result := '';
  if aResponse.Body = '' then
    Exit;
  // convert straight from the raw bytes so no ANSI codepage round trip happens
  lvLen := MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(aResponse.Body),
    Length(aResponse.Body), nil, 0);
  if lvLen = 0 then
    Exit;
  SetLength(Result, lvLen);
  MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(aResponse.Body),
    Length(aResponse.Body), PWideChar(Result), lvLen);
end;

function BpHttpHeaderValue(const aHeaders, aName: string): string;
var
  lvPos: Integer;
  lvLine, lvName: string;
begin
  Result := '';
  if aName = '' then
    Exit;
  lvPos := 1;
  while NextHeaderLine(aHeaders, lvPos, lvLine, lvName) do
    if SameText(lvName, aName) then
    begin
      Result := Trim(Copy(lvLine, Pos(':', lvLine) + 1, MaxInt));
      Exit;
    end;
end;

// RFC 7230 says 1*DIGIT; StrToInt64Def also takes '$40000', '0x40000' and '+42'
function BpHttpContentLength(const aHeaders: string): Int64;
var
  lvValue: string;
  i, lvDigit: Integer;
begin
  Result := -1;
  lvValue := BpHttpHeaderValue(aHeaders, 'Content-Length');
  if lvValue = '' then
    Exit;
  Result := 0;
  for i := 1 to Length(lvValue) do
  begin
    lvDigit := Ord(lvValue[i]) - Ord('0');
    // the overflow test comes first, or {$Q+} raises on the multiply
    if (lvDigit < 0) or (lvDigit > 9) or
      (Result > (High(Int64) - lvDigit) div 10) then
    begin
      Result := -1;
      Exit;
    end;
    Result := Result * 10 + lvDigit;
  end;
end;

function BpHttpReasonPhrase(const aHeaders: string): string;
var
  lvPos, lvSpace: Integer;
  lvLine, lvName: string;
begin
  Result := '';
  lvPos := 1;
  if not NextHeaderLine(aHeaders, lvPos, lvLine, lvName) then
    Exit;
  if Copy(lvLine, 1, 5) <> 'HTTP/' then
    Exit;
  // drop the version, then the status code, and the phrase is what is left
  lvSpace := Pos(' ', lvLine);
  if lvSpace = 0 then
    Exit;
  lvLine := Trim(Copy(lvLine, lvSpace + 1, MaxInt));
  lvSpace := Pos(' ', lvLine);
  if lvSpace > 0 then
    Result := Trim(Copy(lvLine, lvSpace + 1, MaxInt));
end;

function BpHttpRedirectTarget(const aBaseUrl, aHeaders: string;
  aStatus: Integer): string;
var
  lvLocation: string;
  lvBuffer: array[0..INTERNET_MAX_URL_LENGTH] of Char;
  lvLen: DWORD;
begin
  Result := '';
  case aStatus of
    301, 302, 303, 307, 308: ;
  else
    Exit;
  end;
  lvLocation := BpHttpHeaderValue(aHeaders, 'Location');
  if lvLocation = '' then
    Exit;
  lvLen := Length(lvBuffer);
  // Location may be relative, and this is the RFC 3986 resolver Windows ships
  if InternetCombineUrl(PChar(aBaseUrl), PChar(lvLocation), lvBuffer, lvLen, 0) then
    SetString(Result, lvBuffer, lvLen);
end;

function BpHttpRedirectMethod(aStatus: Integer; const aMethod: string): string;
begin
  Result := aMethod;
  case aStatus of
    301, 302: if SameText(aMethod, 'POST') then Result := 'GET';
    303: if not SameText(aMethod, 'HEAD') then Result := 'GET';
  end;
end;

type
  TbpHeaderNameTest = function(const aName: string): Boolean;

function BpHttpFilterHeaders(const aHeaders: string;
  aDrop: TbpHeaderNameTest): string;
var
  lvPos: Integer;
  lvLine, lvName: string;
begin
  Result := '';
  lvPos := 1;
  while NextHeaderLine(aHeaders, lvPos, lvLine, lvName) do
    if not aDrop(lvName) then
      AppendHeaderLine(Result, lvLine);
end;

// the set every mainstream client strips: see requests, reqwest and fetch
function BpHttpIsCredentialHeader(const aName: string): Boolean;
begin
  Result := SameText(aName, 'Authorization') or SameText(aName, 'Cookie') or
    SameText(aName, 'Cookie2') or SameText(aName, 'Proxy-Authorization');
end;

function BpHttpIsContentHeader(const aName: string): Boolean;
begin
  Result := SameText(aName, 'Content-Length') or SameText(aName, 'Content-Type') or
    SameText(aName, 'Transfer-Encoding');
end;

function BpHttpStripCredentials(const aHeaders: string): string;
begin
  Result := BpHttpFilterHeaders(aHeaders, BpHttpIsCredentialHeader);
end;

function BpHttpStripContentHeaders(const aHeaders: string): string;
begin
  Result := BpHttpFilterHeaders(aHeaders, BpHttpIsContentHeader);
end;

// RFC 9110: a Content-Length on these describes what a GET would have returned
function BpHttpResponseHasBody(const aMethod: string; aStatus: Integer): Boolean;
begin
  Result := not (SameText(aMethod, 'HEAD') or (aStatus = 204) or
    (aStatus = 304) or ((aStatus >= 100) and (aStatus < 200)));
end;

function BpHttpProgressPercent(const aReceived, aTotal: Int64): Integer;
begin
  if aTotal <= 0 then
    Result := -1
  else if aReceived <= 0 then
    Result := 0
  else if aReceived >= aTotal then
    Result := 100
  else
    Result := (aReceived * 100) div aTotal;
end;

function BpClassifyHttpError(aWinInetError: DWORD; aHttpStatus: Integer): string;
const
  // some of these are missing from D2007's WinInet.pas, so declared inline
  lcErrTimeout           = 12002;
  lcErrNameNotResolved   = 12007;
  lcErrCannotConnect     = 12029;
  lcErrConnectionReset   = 12031;
  lcErrCertDateInvalid   = 12037;
  lcErrCertCnInvalid     = 12038;
  lcErrInvalidCa         = 12045;
  lcErrSecCertErrors     = 12055;
  lcErrSecureChannel     = 12157;
  lcErrSecInvalidCert    = 12169;
  lcErrSecCertRevoked    = 12170;
  lcErrDecodingFailed    = 12175;
begin
  if aWinInetError <> 0 then
  begin
    case aWinInetError of
      lcErrNameNotResolved:
        Result := 'Cannot reach server (DNS or network issue)';
      lcErrTimeout:
        Result := 'Connection timed out';
      gcErrOperationCancelled:
        Result := 'Operation cancelled';
      lcErrCannotConnect:
        Result := 'Cannot connect to server';
      lcErrConnectionReset:
        Result := 'Connection lost';
      lcErrDecodingFailed:
        Result := 'Cannot decode the compressed response';
      lcErrCertDateInvalid, lcErrCertCnInvalid, lcErrInvalidCa, lcErrSecCertErrors,
      lcErrSecureChannel, lcErrSecInvalidCert, lcErrSecCertRevoked:
        Result := 'SSL/TLS certificate error';
    else
      Result := 'Network error';
    end;
    Exit;
  end;

  case aHttpStatus of
    401: Result := 'Authentication failed (invalid credentials or token?)';
    403: Result := 'Access denied (missing permission or scope?)';
    404: Result := 'Endpoint not found (check URL)';
    429: Result := 'Rate limited by server';
  else
    if (aHttpStatus >= 500) and (aHttpStatus <= 599) then
      Result := 'Server error'
    else if aHttpStatus > 0 then
      Result := Format('HTTP error %d', [aHttpStatus])
    else
      Result := 'Unknown error';
  end;
end;

end.
