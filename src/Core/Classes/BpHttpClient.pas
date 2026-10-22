unit BpHttpClient;

// HTTP/HTTPS over WinInet with Schannel TLS: cancellable requests, streaming downloads, the same calls async.
// Not for a Windows service, where WinInet is unsupported. The Base64 region is mirrored from BpBase64 to keep the bundle small.

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
    constructor Create(const aMessage: string; aStatusCode: Integer = 0; aWinInetError: DWORD = 0);
    property StatusCode: Integer read FStatusCode;
    property WinInetError: DWORD read FWinInetError;
  end;

  // WinInetError is gcErrOperationCancelled
  EbpHttpClientCancelled = class(EbpHttpClient);

  TbpHttpResponse = record
    StatusCode: Integer;
    StatusText: string;
    Headers: string;         // raw, CRLF separated
    Body: AnsiString;        // raw bytes as received; empty for Download
    ContentLength: Int64;    // -1 when absent
    FinalUrl: string;        // where the redirects ended
  end;

{$IFNDEF BPAMALGAMATION}
  // from BpTasks, so `uses BpHttpClient` alone reaches them
  TbpCancelCleanupProc = BpTasks.TbpCancelCleanupProc;
  TbpCancellationToken = BpTasks.TbpCancellationToken;
{$ENDIF}

  // per-chunk download progress; aTotal -1 = unknown, set aCancel to abort
  TbpHttpProgressEvent = procedure(aSender: TObject; const aReceived,
    aTotal: Int64; var aCancel: Boolean) of object;

  // runs on the failing thread just before the raise; aRequest is nil before a handle exists
  TbpHttpFailureHook = procedure(aContextId: Cardinal; aRequest: Pointer;
    const aMessage: string; aError: DWORD);

  TbpHttpTaskState = (htsPending, htsRunning, htsSucceeded, htsFailed,
    htsCancelled);

  // what Begin* returns; releasing the last reference cancels the call and frees the task
  IbpHttpTask = interface
    ['{89376BC3-512C-4BF9-BCD4-856D70300ACA}']
    procedure Cancel;
    function WaitFor(aTimeoutMs: DWORD = INFINITE): Boolean;
    function IsFinished: Boolean;
    function State: TbpHttpTaskState;
    // waits, then returns what the sync call returned or raises what it raised
    function Response: TbpHttpResponse;
    function ErrorMessage: string;
    function Received: Int64;
    function Total: Int64;  // -1 while unknown
  end;

  // once, on success, failure or cancel; aTask.Response tells which
  TbpHttpTaskEvent = procedure(const aTask: IbpHttpTask) of object;
  // coalesced: a slow handler sees only the latest pair
  TbpHttpTaskProgressEvent = procedure(const aTask: IbpHttpTask;
    const aReceived, aTotal: Int64) of object;

  // one reused session; every sync call has a Begin* twin on a worker thread
  // Sync:  lvResponse := FClient.Get(lvUrl);
  //        if BpHttpResponseIsSuccess(lvResponse) then
  //          lvText := BpHttpResponseBodyAsUtf8(lvResponse);
  // Async: FTask := FClient.BeginGet(lvUrl, HandleItems);  // dropping FTask cancels the call
  //        procedure TMainForm.HandleItems(const aTask: IbpHttpTask);
  //        ... lvResponse := aTask.Response;  // or the exception Get would have raised
  TbpHttpClient = class
  private
    FUserAgent: string;
    FConnectTimeout: DWORD;
    FSendTimeout: DWORD;
    FReceiveTimeout: DWORD;
    FTimeout: DWORD;
    FFollowRedirects: Boolean;
    FMaxRedirects: Integer;
    FAutoDecompress: Boolean;
    FMaxResponseBytes: Int64;
    FUsername: WideString;
    FPassword: WideString;
    FBearerToken: string;
    FHeaders: TStringList;  // Name=Value pairs
    FSession: HINTERNET;    // nil until the first request
    FSessionLock: TRTLCriticalSection;  // guards FSession
    FContextId: Cardinal;
    FMarshalTaskEvents: Boolean;
    // under gvHttpLock: what Destroy cancels and waits out
    FCalls: TList;         // TbpHttpCall per request in flight, on any thread
    FTasks: TList;         // live Begin* tasks
    FWorkers: Integer;     // task workers inside a call
    FDestroying: Boolean;
    class function MethodToString(aMethod: TbpHttpMethod): string;
    procedure SetUserAgent(const aValue: string);
    procedure SetConnectTimeout(aValue: DWORD);
    procedure SetSendTimeout(aValue: DWORD);
    procedure SetReceiveTimeout(aValue: DWORD);
    procedure SetTimeout(aValue: DWORD);
    procedure SetBearerToken(const aValue: string);
    function GetWinInetErrorMessage(aErrorCode: DWORD): string;
    // tells the failure hook first
    procedure RaiseFailure(aRequest: HINTERNET; const aMessage: string; aError: DWORD);
    procedure RaiseWinInetError(aRequest: HINTERNET; const aCall, aHost: string; aError: DWORD);
    function HostPort(const aUrl: string): string;
    function CreateSession: HINTERNET;
    procedure CloseSession;
    procedure ApplyTimeoutsToSession;
    function CreateConnection(aSession: HINTERNET; const aServerName: string;
      aPort: Integer; const aHost: string): HINTERNET;
    function CreateRequest(aConnection: HINTERNET; const aMethod, aResource: string;
      aSecure: Boolean; const aHost: string): HINTERNET;
    procedure ApplyTimeouts(aHandle: HINTERNET);
    procedure ApplyAuthentication(aRequest: HINTERNET);
    function UrlBasicAuth(const aUrl: string): string;
    function ApplyDecoding(aRequest: HINTERNET): Boolean;
    procedure SendHttpRequest(aRequest: HINTERNET; const aHeaders: string;
      const aBody: AnsiString; const aHost: string);
    function ReadResponseStatus(aRequest: HINTERNET; const aHost: string): Integer;
    function ReadResponseHeaders(aRequest: HINTERNET): string;
    // aExpected -1 skips the length check
    function ReadResponseBody(aRequest: HINTERNET; const aExpected: Int64;
      aToken: TbpCancellationToken; const aHost: string): AnsiString;
    procedure ReadBodyToStream(aRequest: HINTERNET; aDest: TStream; const aTotal: Int64;
      aProgress: TbpHttpProgressEvent; aToken: TbpCancellationToken; const aHost: string);
    procedure DrainRedirectBody(aRequest: HINTERNET; aToken: TbpCancellationToken;
      const aHost: string);
    procedure CheckBodyComplete(aRequest: HINTERNET;
      const aReceived, aExpected: Int64; const aHost: string);
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
    // for the tests and BpHttpTrace, not part of the client's API
    function ParseUrl(const aUrl: string; out aServerName, aResource: string;
      out aPort: Integer; out aSecure: Boolean): Boolean;
    // aWithCredentials False builds the block a foreign redirect origin may see
    function BuildHeaders(const aRequestHeaders: string; aWithCredentials: Boolean = True): string;
    // scheme, host and port all equal, the WHATWG fetch definition
    function SameOrigin(const aUrl, aOther: string): Boolean;
    // True while a redirect may still carry Authorization, Cookie and the rest
    function KeepsCredentials(const aFrom, aTo: string): Boolean;
    function SessionHandle: HINTERNET;
    function SessionActive: Boolean;
    // the WinInet context of every handle this client opens
    property ContextId: Cardinal read FContextId;

  public
    // one call without a client: the body of a 2xx, any other status raises EbpHttpClient
    class function FetchUrl(const aUrl: string; const aHeaders: string = ''): AnsiString;
    // Execute on a fresh client; aTimeoutMs is the whole call, which the send and receive steps may take
    class function Send(aMethod: TbpHttpMethod; const aUrl: string; const aBody: AnsiString = '';
      const aHeaders: string = ''; aTimeoutMs: DWORD = 0): TbpHttpResponse;

  public
    constructor Create;
    destructor Destroy; override;

    // aToken aborts the call from another thread (EbpHttpClientCancelled)
    function Get(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Post(const aUrl: string; const aBody: AnsiString; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function PostJson(const aUrl: string; const aJson: AnsiString;
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Put(const aUrl: string; const aBody: AnsiString; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Delete(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    // the same calls on a worker thread, started at once; aOnDone may be nil
    function BeginGet(const aUrl: string; aOnDone: TbpHttpTaskEvent;
      const aHeaders: string = ''): IbpHttpTask;
    function BeginPost(const aUrl: string; const aBody: AnsiString;
      aOnDone: TbpHttpTaskEvent; const aHeaders: string = ''): IbpHttpTask;

    // replaces any Authorization set before
    property BearerToken: string read FBearerToken write SetBearerToken;
    // preemptive, UTF-8 per RFC 7617; clears BearerToken
    procedure SetBasicAuth(const aUser, aPassword: WideString);
    // sent with every request; adding a name again replaces it
    procedure AddHeader(const aName, aValue: string);
    procedure ClearHeaders;
    // changing it drops the session, so set it before the first request
    property UserAgent: string read FUserAgent write SetUserAgent;
    // a whole buffered call in ms, a cap above the step timeouts; 0 restores 30000, Download ignores it
    property Timeout: DWORD read FTimeout write SetTimeout;
    property FollowRedirects: Boolean read FFollowRedirects write FFollowRedirects;

  public
    function Patch(const aUrl: string; const aBody: AnsiString; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Head(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function Options(const aUrl: string; const aHeaders: string = '';
      aToken: TbpCancellationToken = nil): TbpHttpResponse;
    // any method; BeginExecute is the async twin of Put, Delete and the rest
    function Execute(aMethod: TbpHttpMethod; const aUrl: string; const aBody: AnsiString = '';
      const aHeaders: string = ''; aToken: TbpCancellationToken = nil): TbpHttpResponse;
    function BeginExecute(aMethod: TbpHttpMethod; const aUrl: string; aOnDone: TbpHttpTaskEvent;
      const aBody: AnsiString = ''; const aHeaders: string = ''): IbpHttpTask;

    // streams the body whatever the status; 'Range: bytes=N-' in aHeaders resumes
    function Download(const aUrl: string; aDest: TStream;
      aProgress: TbpHttpProgressEvent = nil; aToken: TbpCancellationToken = nil;
      const aHeaders: string = ''; const aMethod: string = 'GET'): TbpHttpResponse;
    // a 200 renames a sibling temp file over the destination, nothing else does
    function DownloadToFile(const aUrl, aFileName: string; aProgress: TbpHttpProgressEvent = nil;
      aToken: TbpCancellationToken = nil; const aHeaders: string = ''): TbpHttpResponse;
    // aDest belongs to the caller and must outlive the task
    function BeginDownload(const aUrl: string; aDest: TStream; aOnDone: TbpHttpTaskEvent;
      aOnProgress: TbpHttpTaskProgressEvent = nil; const aHeaders: string = ''): IbpHttpTask;
    function BeginDownloadToFile(const aUrl, aFileName: string; aOnDone: TbpHttpTaskEvent;
      aOnProgress: TbpHttpTaskProgressEvent = nil; const aHeaders: string = ''): IbpHttpTask;

    // a server's 401 only, not a proxy's 407; sent in the ANSI code page, SetBasicAuth in UTF-8
    property Username: WideString read FUsername write FUsername;
    property Password: WideString read FPassword write FPassword;
    // how long one WinInet step may wait, in ms; 0 restores the default, 10000
    property ConnectTimeout: DWORD read FConnectTimeout write SetConnectTimeout;
    property SendTimeout: DWORD read FSendTimeout write SetSendTimeout;
    property ReceiveTimeout: DWORD read FReceiveTimeout write SetReceiveTimeout;
    // hops allowed before EbpHttpClient; 0 or less has the same effect as FollowRedirects False
    property MaxRedirects: Integer read FMaxRedirects write FMaxRedirects;
    // gzip and deflate on the buffered verbs; a decoded body has no length to check
    property AutoDecompress: Boolean read FAutoDecompress write FAutoDecompress;
    // ceiling for a body held in memory, 0 for none; a stream never buffers
    property MaxResponseBytes: Int64 read FMaxResponseBytes write FMaxResponseBytes;
    // True: Begin* events run on the main thread, which must pump; False: on the worker
    property MarshalTaskEvents: Boolean read FMarshalTaskEvents write FMarshalTaskEvents;
  end;

function BpHttpResponseIsSuccess(const aResponse: TbpHttpResponse): Boolean;
// invalid bytes become U+FFFD, not an error
function BpHttpResponseBodyAsUtf8(const aResponse: TbpHttpResponse): WideString;
// the body as text by its BOM, else its charset, else UTF-8, like THTTPClient's ContentAsString
function BpHttpResponseText(const aResponse: TbpHttpResponse): WideString;
// UTF-8 bytes for a body on every compiler: PostJson(lvUrl, BpHttpUtf8(lvJson.ToJson))
function BpHttpUtf8(const aText: WideString): AnsiString;
// the first line with that name; '' for absent and empty alike
function BpHttpHeaderValue(const aHeaders, aName: string): string;
function BpHttpStripUserInfo(const aUrl: string): string;
// 0..100; -1 when the total is unknown
function BpHttpProgressPercent(const aReceived, aTotal: Int64): Integer;
// user-facing categorization; pass 0 for the dimension that does not apply
function BpClassifyHttpError(aWinInetError: DWORD; aHttpStatus: Integer): string;

// public for the tests and BpHttpTrace, not part of the client's API

// -1 when absent or invalid
function BpHttpContentLength(const aHeaders: string): Int64;
// False for the replies that carry no body, whatever Content-Length says
function BpHttpResponseHasBody(const aMethod: string; aStatus: Integer): Boolean;
// '' when the server sent none
function BpHttpReasonPhrase(const aHeaders: string): string;
// absolute; '' when the reply is not a redirect or has no Location
function BpHttpRedirectTarget(const aBaseUrl, aHeaders: string; aStatus: Integer): string;
// the method the next hop uses, per the WHATWG fetch redirect rules
function BpHttpRedirectMethod(aStatus: Integer; const aMethod: string): string;
// drops the header lines that must not follow a redirect to another origin
function BpHttpStripCredentials(const aHeaders: string): string;
// drops the entity headers that described a body the next hop will not send
function BpHttpStripContentHeaders(const aHeaders: string): string;
// one per process; BpHttpTrace sets it while it is linked in
procedure BpSetHttpFailureHook(aHook: TbpHttpFailureHook);

const
  // WinInet ERROR_INTERNET_OPERATION_CANCELLED, missing from D2007's WinInet.pas
  gcErrOperationCancelled = 12017;
  // INTERNET_OPTION_HTTP_DECODING, Vista and up, missing from D2007's WinInet.pas
  gcInternetOptionHttpDecoding = 65;
  gcBpHttpMaxRedirects = 10;

implementation

const
  gcBufferSize = 8192;
  gcDownloadBufferSize = 65536;  // bigger chunks pay off on large bodies
  gcDefaultTimeout = 10000;  // milliseconds, OkHttp's connect, read and write default
  gcDefaultTotalTimeout = 30000;  // ends a server that trickles bytes inside every step timeout
  gcErrTimeout = 12002;  // ERROR_INTERNET_TIMEOUT
  gcDefaultUserAgent = 'DelphiBoostPack/1.0';

var
  gvLastContextId: Integer = 0;
  gvFailureHook: TbpHttpFailureHook = nil;
  // guards the call and task bookkeeping of every client and task
  gvHttpLock: TRTLCriticalSection;
  gvLiveTasks: Integer = 0;

// bp:mirror base64-encode
// Copied, not shared: tools\CheckMirrors.js fails if the copies stop matching.
const
  gcBase64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

// RFC 4648. aSize past (MaxInt div 4) * 3 wraps the length arithmetic below,
// which each copy guards in its own vocabulary before calling in here.
function Base64EncodeBuffer(aSource: PByte; aSize: Integer;
  const aAlphabet: string; aPadded: Boolean): string;
var
  lvDest: PChar;
  lvB0, lvB1, lvB2: Byte;
  lvFull, lvRest, lvOutLen, i: Integer;
begin
  Result := '';
  if aSize <= 0 then
    Exit;
  lvFull := aSize div 3;
  lvRest := aSize mod 3;
  lvOutLen := lvFull * 4;
  if lvRest > 0 then
  begin
    if aPadded then
      Inc(lvOutLen, 4)
    else
      Inc(lvOutLen, lvRest + 1);
  end;
  SetLength(Result, lvOutLen);
  lvDest := Pointer(Result);
  for i := 1 to lvFull do
  begin
    lvB0 := aSource^; Inc(aSource);
    lvB1 := aSource^; Inc(aSource);
    lvB2 := aSource^; Inc(aSource);
    lvDest[0] := aAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := aAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := aAlphabet[(((lvB1 and $0F) shl 2) or (lvB2 shr 6)) + 1];
    lvDest[3] := aAlphabet[(lvB2 and $3F) + 1];
    Inc(lvDest, 4);
  end;
  if lvRest = 1 then
  begin
    lvB0 := aSource^;
    lvDest[0] := aAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := aAlphabet[((lvB0 and $03) shl 4) + 1];
    if aPadded then
    begin
      lvDest[2] := '=';
      lvDest[3] := '=';
    end;
  end
  else if lvRest = 2 then
  begin
    lvB0 := aSource^; Inc(aSource);
    lvB1 := aSource^;
    lvDest[0] := aAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := aAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := aAlphabet[((lvB1 and $0F) shl 2) + 1];
    if aPadded then
      lvDest[3] := '=';
  end;
end;
// bp:mirror-end

// bp:mirror wide-to-utf8
// Copied, not shared: tools\CheckMirrors.js fails if the copies stop matching.
// not UTF8Encode, which breaks surrogate pairs before Delphi 2009
function WideToUtf8Bytes(const aText: WideString; out aBytes: AnsiString): Boolean;
var
  lvLen: Integer;
begin
  aBytes := '';
  Result := True;
  if aText = '' then
    Exit;
  lvLen := WideCharToMultiByte(CP_UTF8, 0, PWideChar(aText), Length(aText),
    nil, 0, nil, nil);
  Result := lvLen > 0;
  if not Result then
    Exit;
  SetLength(aBytes, lvLen);
  WideCharToMultiByte(CP_UTF8, 0, PWideChar(aText), Length(aText),
    PAnsiChar(aBytes), lvLen, nil, nil);
end;
// bp:mirror-end

function BpHttpUtf8(const aText: WideString): AnsiString;
begin
  if not WideToUtf8Bytes(aText, Result) then
    raise EbpHttpClient.Create('Text cannot be encoded as UTF-8');
end;

// the size the encoder above will not check for itself, in this unit's words
function Base64Credential(const aBytes: AnsiString): string;
begin
  if Length(aBytes) > (MaxInt div 4) * 3 then
    raise EbpHttpClient.Create('Credentials are too large to encode');
  Result := Base64EncodeBuffer(Pointer(aBytes), Length(aBytes), gcBase64Chars, True);
end;

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

procedure CheckCancelled(aToken: TbpCancellationToken);
begin
  if (aToken <> nil) and aToken.IsCancellationRequested then
    RaiseOperationCancelled;
end;

// the timer queue API, Windows 2000 and up, missing from D7's and D2007's Windows.pas
const
  gcWtExecuteOnlyOnce = $00000008;

type
  TbpWaitOrTimerCallback = procedure(aParameter: Pointer; aTimerOrWaitFired: Boolean); stdcall;

function BpCreateTimerQueueTimer(out aTimer: THandle; aTimerQueue: THandle;
  aCallback: TbpWaitOrTimerCallback; aParameter: Pointer;
  aDueTime, aPeriod, aFlags: DWORD): BOOL; stdcall;
  external kernel32 name 'CreateTimerQueueTimer';
function BpDeleteTimerQueueTimer(aTimerQueue, aTimer, aCompletionEvent: THandle): BOOL; stdcall;
  external kernel32 name 'DeleteTimerQueueTimer';

type
  // one PerformRequest; the caller's cancel, the deadline and Destroy all go through FToken
  TbpHttpCall = class
  private
    FClient: TbpHttpClient;  // listed in its FCalls while set
    FToken: TbpCancellationToken;
    FCallerToken: TbpCancellationToken;  // linked to FToken while set
    FLinkId: Integer;
    FTimer: THandle;
    FTimedOut: Integer;
  public
    constructor Create(aClient: TbpHttpClient; aCallerToken: TbpCancellationToken;
      aTimeoutMs: DWORD);
    destructor Destroy; override;
    function TimedOut: Boolean;
    property Token: TbpCancellationToken read FToken;
  end;

procedure BpCancelTokenCleanup(aData: Pointer);
begin
  TbpCancellationToken(aData).Cancel;
end;

// runs on a timer queue thread
procedure BpHttpDeadlineFired(aParameter: Pointer; aTimerOrWaitFired: Boolean); stdcall;
begin
  InterlockedExchange(TbpHttpCall(aParameter).FTimedOut, 1);
  TbpHttpCall(aParameter).FToken.Cancel;
end;

constructor TbpHttpCall.Create(aClient: TbpHttpClient;
  aCallerToken: TbpCancellationToken; aTimeoutMs: DWORD);
begin
  inherited Create;
  FToken := TbpCancellationToken.Create;
  // listed before anything can block, so the client's Destroy can cancel it
  EnterCriticalSection(gvHttpLock);
  try
    if aClient.FDestroying then
      RaiseOperationCancelled;
    aClient.FCalls.Add(Self);
    FClient := aClient;
  finally
    LeaveCriticalSection(gvHttpLock);
  end;
  if aCallerToken <> nil then
    if aCallerToken.RegisterCleanup(BpCancelTokenCleanup, FToken, FLinkId) then
      FCallerToken := aCallerToken
    else
      FToken.Cancel;  // cancelled already; the first hop raises
  if aTimeoutMs <> INFINITE then
    if not BpCreateTimerQueueTimer(FTimer, 0, BpHttpDeadlineFired, Self,
      aTimeoutMs, 0, gcWtExecuteOnlyOnce) then
    begin
      FTimer := 0;  // Destroy runs next and must not delete garbage
      raise EbpHttpClient.CreateFmt(
        'Cannot start the request timer: Windows error %d', [GetLastError]);
    end;
end;

destructor TbpHttpCall.Destroy;
begin
  // first, and the last touch of the client: its Destroy waits for this
  if FClient <> nil then
  begin
    EnterCriticalSection(gvHttpLock);
    FClient.FCalls.Remove(Self);
    LeaveCriticalSection(gvHttpLock);
  end;
  // INVALID_HANDLE_VALUE waits out a callback already running
  if FTimer <> 0 then
    BpDeleteTimerQueueTimer(0, FTimer, INVALID_HANDLE_VALUE);
  // once it returns, the caller's Cancel can no longer reach FToken
  if FCallerToken <> nil then
    FCallerToken.UnregisterCleanup(FLinkId);
  FToken.Free;
  inherited;
end;

function TbpHttpCall.TimedOut: Boolean;
begin
  Result := FTimedOut <> 0;
end;

type
  TbpHttpTaskKind = (htkBuffered, htkStream, htkFile);

  // what Begin* hands out; TbpTask owns the thread, the events and the states
  TbpHttpTaskImpl = class(TObject, IbpHttpTask)
  private
    FRefCount: Integer;          // under FLock, see Hold
    FTask: TbpTask;
    FClient: TbpHttpClient;      // under gvHttpLock; nil once that client is gone
    FLock: TRTLCriticalSection;  // guards the count and the progress pair
    FKind: TbpHttpTaskKind;
    FMethod: string;
    FUrl: string;
    FHeaders: string;
    FBody: AnsiString;
    FDest: TStream;
    FFileName: string;
    FOnDone: TbpHttpTaskEvent;
    FOnProgress: TbpHttpTaskProgressEvent;
    // written by the worker before the state turns final, read only after
    FResponse: TbpHttpResponse;
    FErrorClass: ExceptClass;
    FErrorStatus: Integer;
    FErrorCode: DWORD;
    FReceived: Int64;
    FTotal: Int64;
    FFreePending: Boolean;  // released inside its own work; the last event frees it
    FWorkDone: Boolean;     // the last event began, so even the worker may free it
    function Hold: IbpHttpTask;
    procedure Detach;
    procedure DoWork(aSender: TObject; aToken: TbpCancellationToken);
    procedure HandleWorkerProgress(aSender: TObject; const aReceived,
      aTotal: Int64; var aCancel: Boolean);
    procedure DispatchProgress(aSender: TObject);
    procedure DispatchComplete(aSender: TObject);
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    constructor Create(aClient: TbpHttpClient; aKind: TbpHttpTaskKind);
    destructor Destroy; override;
    procedure Cancel;
    function WaitFor(aTimeoutMs: DWORD = INFINITE): Boolean;
    function IsFinished: Boolean;
    function State: TbpHttpTaskState;
    function Response: TbpHttpResponse;
    function ErrorMessage: string;
    function Received: Int64;
    function Total: Int64;
  end;

  EbpHttpClientClass = class of EbpHttpClient;

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
  // non-zero, or WinInet skips its status callbacks
  FContextId := Cardinal(InterlockedIncrement(gvLastContextId));
  FUserAgent := gcDefaultUserAgent;
  FConnectTimeout := gcDefaultTimeout;
  FSendTimeout := gcDefaultTimeout;
  FReceiveTimeout := gcDefaultTimeout;
  FTimeout := gcDefaultTotalTimeout;
  FFollowRedirects := True;
  FMaxRedirects := gcBpHttpMaxRedirects;
  FAutoDecompress := True;
  FMarshalTaskEvents := True;
  FHeaders := TStringList.Create;
  FCalls := TList.Create;
  FTasks := TList.Create;
end;

// cancels every call and task on any thread, and returns once none can touch Self
destructor TbpHttpClient.Destroy;
var
  i: Integer;
  lvBusy: Boolean;
begin
  EnterCriticalSection(gvHttpLock);
  try
    FDestroying := True;
    // under the lock, so nothing listed here can be freed meanwhile
    for i := 0 to FTasks.Count - 1 do
      TbpHttpTaskImpl(FTasks[i]).Detach;
    FTasks.Clear;
    for i := 0 to FCalls.Count - 1 do
      TbpHttpCall(FCalls[i]).Token.Cancel;
  finally
    LeaveCriticalSection(gvHttpLock);
  end;
  // a cancelled call unwinds as fast as its closed handle fails
  repeat
    EnterCriticalSection(gvHttpLock);
    lvBusy := (FCalls.Count > 0) or (FWorkers > 0);
    LeaveCriticalSection(gvHttpLock);
    if lvBusy then
      Sleep(1);
  until not lvBusy;
  CloseSession;
  FTasks.Free;
  FCalls.Free;
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

// zero is the default, never whatever the session happens to hold
function DefaultIfZero(aValue, aDefault: DWORD): DWORD;
begin
  if aValue = 0 then
    Result := aDefault
  else
    Result := aValue;
end;

procedure TbpHttpClient.SetConnectTimeout(aValue: DWORD);
begin
  FConnectTimeout := DefaultIfZero(aValue, gcDefaultTimeout);
  ApplyTimeoutsToSession;
end;

procedure TbpHttpClient.SetSendTimeout(aValue: DWORD);
begin
  FSendTimeout := DefaultIfZero(aValue, gcDefaultTimeout);
  ApplyTimeoutsToSession;
end;

procedure TbpHttpClient.SetReceiveTimeout(aValue: DWORD);
begin
  FReceiveTimeout := DefaultIfZero(aValue, gcDefaultTimeout);
  ApplyTimeoutsToSession;
end;

procedure TbpHttpClient.SetTimeout(aValue: DWORD);
begin
  FTimeout := DefaultIfZero(aValue, gcDefaultTotalTimeout);
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
    Base64Credential(BpHttpUtf8(aUser + ':' + aPassword)));
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
  // nil arguments, so an insert like %1 in a text must stay as it is
  lvLen := FormatMessage(FORMAT_MESSAGE_FROM_HMODULE or FORMAT_MESSAGE_FROM_SYSTEM or
    FORMAT_MESSAGE_IGNORE_INSERTS, Pointer(GetModuleHandle('wininet.dll')), aErrorCode, 0,
    lvBuffer, Length(lvBuffer), nil);
  if lvLen > 0 then
  begin
    SetString(Result, lvBuffer, lvLen);
    Result := Format('%s (%d)', [Trim(Result), aErrorCode]);
  end
  else
    Result := Format('WinInet error %d', [aErrorCode]);
end;

procedure TbpHttpClient.RaiseFailure(aRequest: HINTERNET; const aMessage: string; aError: DWORD);
var
  lvHook: TbpHttpFailureHook;
begin
  lvHook := gvFailureHook;
  if Assigned(lvHook) then
    // a diagnostic must not replace the failure it reports
    try
      lvHook(FContextId, aRequest, aMessage, aError);
    except
    end;
  raise EbpHttpClient.Create(aMessage, 0, aError);
end;

// names the call, since HttpSendRequest also resolves, connects and does TLS
procedure TbpHttpClient.RaiseWinInetError(aRequest: HINTERNET;
  const aCall, aHost: string; aError: DWORD);
begin
  if aHost = '' then
    RaiseFailure(aRequest, Format('%s failed: %s',
      [aCall, GetWinInetErrorMessage(aError)]), aError)
  else
    RaiseFailure(aRequest, Format('%s failed for %s: %s',
      [aCall, aHost, GetWinInetErrorMessage(aError)]), aError);
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
  // InternetCrackUrl unescapes its buffer in place here, so it never gets aUrl
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
  // percent-decoding already produced the UTF-8 bytes RFC 7617 wants, so no transcode
  Result := 'Basic ' + Base64Credential(lvUser + ':' + lvPassword);
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

// what a message names: never the path, which may carry a token in its query
function TbpHttpClient.HostPort(const aUrl: string): string;
var
  lvHost, lvResource: string;
  lvPort: Integer;
  lvSecure: Boolean;
begin
  if ParseUrl(aUrl, lvHost, lvResource, lvPort, lvSecure) then
    Result := Format('%s:%d', [lvHost, lvPort])
  else
    Result := '';
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
begin
  Result := InternetOpen(PChar(FUserAgent), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Result = nil then
    RaiseWinInetError(nil, 'InternetOpen', '', GetLastError);
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
  const aServerName: string; aPort: Integer; const aHost: string): HINTERNET;
begin
  Result := InternetConnect(aSession, PChar(aServerName), aPort, nil, nil, INTERNET_SERVICE_HTTP,
    0, FContextId);
  if Result = nil then
    RaiseWinInetError(nil, 'InternetConnect', aHost, GetLastError);
end;

function TbpHttpClient.CreateRequest(aConnection: HINTERNET; const aMethod, aResource: string;
  aSecure: Boolean; const aHost: string): HINTERNET;
var
  lvFlags: DWORD;
begin
  // keep-alive: without it WinInet may drop the pooled connection
  lvFlags := INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_KEEP_CONNECTION;
  if aSecure then
    lvFlags := lvFlags or INTERNET_FLAG_SECURE;
  // always ours to follow: WinInet replays the header block, secrets included
  lvFlags := lvFlags or INTERNET_FLAG_NO_AUTO_REDIRECT;
  // that jar is the user's own, keyed by host, and outlives every strip we do
  lvFlags := lvFlags or INTERNET_FLAG_NO_COOKIES;
  // a nil version is HTTP/1.1 on any non-ancient Windows
  Result := HttpOpenRequest(aConnection, PChar(aMethod), PChar(aResource), nil, nil, nil, lvFlags,
    FContextId);
  if Result = nil then
    RaiseWinInetError(nil, 'HttpOpenRequest', aHost, GetLastError);
end;

// never zero: the setters turn a zero into the default
procedure TbpHttpClient.ApplyTimeouts(aHandle: HINTERNET);
begin
  InternetSetOption(aHandle, INTERNET_OPTION_CONNECT_TIMEOUT,
    @FConnectTimeout, SizeOf(FConnectTimeout));
  InternetSetOption(aHandle, INTERNET_OPTION_SEND_TIMEOUT,
    @FSendTimeout, SizeOf(FSendTimeout));
  InternetSetOption(aHandle, INTERNET_OPTION_RECEIVE_TIMEOUT,
    @FReceiveTimeout, SizeOf(FReceiveTimeout));
end;

procedure TbpHttpClient.ApplyAuthentication(aRequest: HINTERNET);
begin
  // W by name on every compiler: the unsuffixed one is A on D2007 and W on 2009+
  if FUsername <> '' then
    InternetSetOptionW(aRequest, INTERNET_OPTION_USERNAME,
      PWideChar(FUsername), Length(FUsername));

  if FPassword <> '' then
    InternetSetOptionW(aRequest, INTERNET_OPTION_PASSWORD,
      PWideChar(FPassword), Length(FPassword));
end;

// False on pre-Vista WinInet, which rejects the option and could not decode a gzip reply
function TbpHttpClient.ApplyDecoding(aRequest: HINTERNET): Boolean;
var
  lvOn: BOOL;
begin
  lvOn := True;
  Result := InternetSetOption(aRequest, gcInternetOptionHttpDecoding, @lvOn,
    SizeOf(lvOn));
end;

procedure TbpHttpClient.SendHttpRequest(aRequest: HINTERNET;
  const aHeaders: string; const aBody: AnsiString; const aHost: string);
begin
  // Pointer() of an empty string is nil, which is how WinInet takes none
  if not HttpSendRequest(aRequest, Pointer(aHeaders), Length(aHeaders), Pointer(aBody),
    Length(aBody)) then
    RaiseWinInetError(aRequest, 'HttpSendRequest', aHost, GetLastError);
end;

function TbpHttpClient.ReadResponseStatus(aRequest: HINTERNET; const aHost: string): Integer;
var
  lvStatusCode, lvBufferLen, lvReserved: DWORD;
begin
  lvBufferLen := SizeOf(lvStatusCode);
  lvReserved := 0;
  if not HttpQueryInfo(aRequest, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @lvStatusCode,
    lvBufferLen, lvReserved) then
    RaiseWinInetError(aRequest, 'HttpQueryInfo', aHost, GetLastError);
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

function TbpHttpClient.ReadResponseBody(aRequest: HINTERNET; const aExpected: Int64;
  aToken: TbpCancellationToken; const aHost: string): AnsiString;
var
  lvBytesRead: DWORD;
  lvSize, lvCapacity: Integer;
begin
  Result := '';
  lvSize := 0;
  lvCapacity := 0;
  repeat
    CheckCancelled(aToken);
    if (FMaxResponseBytes > 0) and (lvSize > FMaxResponseBytes) then
      RaiseFailure(aRequest, Format(
        'Response body from %s is larger than MaxResponseBytes (%d)',
        [aHost, FMaxResponseBytes]), 0);

    if lvCapacity - lvSize < gcBufferSize then
    begin
      if lvCapacity > MaxInt div 2 then
        RaiseFailure(aRequest, Format(
          'Response body from %s is too large to buffer', [aHost]), 0);
      // doubling keeps the reallocations logarithmic in the body size
      if lvCapacity = 0 then
        lvCapacity := gcBufferSize
      else
        lvCapacity := lvCapacity * 2;
      SetLength(Result, lvCapacity);
    end;

    if not InternetReadFile(aRequest, @Result[lvSize + 1], gcBufferSize, lvBytesRead) then
      RaiseWinInetError(aRequest, 'InternetReadFile', aHost, GetLastError);
    Inc(lvSize, lvBytesRead);
  until lvBytesRead = 0;

  SetLength(Result, lvSize);
  CheckBodyComplete(aRequest, lvSize, aExpected, aHost);
end;

// read and dropped, which keeps the connection pooled; past 64 KB closing the handle is cheaper
procedure TbpHttpClient.DrainRedirectBody(aRequest: HINTERNET; aToken: TbpCancellationToken;
  const aHost: string);
var
  lvBuffer: array[0..gcBufferSize - 1] of Byte;
  lvBytesRead: DWORD;
  lvTotal: Integer;
begin
  lvTotal := 0;
  repeat
    CheckCancelled(aToken);
    if not InternetReadFile(aRequest, @lvBuffer, SizeOf(lvBuffer), lvBytesRead) then
      RaiseWinInetError(aRequest, 'InternetReadFile', aHost, GetLastError);
    Inc(lvTotal, lvBytesRead);
  until (lvBytesRead = 0) or (lvTotal >= gcDownloadBufferSize);
end;

procedure TbpHttpClient.ReadBodyToStream(aRequest: HINTERNET; aDest: TStream; const aTotal: Int64;
  aProgress: TbpHttpProgressEvent; aToken: TbpCancellationToken; const aHost: string);
var
  lvBuffer: array[0..gcDownloadBufferSize - 1] of Byte;
  lvBytesRead: DWORD;
  lvReceived: Int64;

  procedure Report;
  var
    lvCancel: Boolean;
  begin
    if not Assigned(aProgress) then
      Exit;
    lvCancel := False;
    aProgress(Self, lvReceived, aTotal, lvCancel);
    if lvCancel then
      RaiseOperationCancelled;
  end;

begin
  lvReceived := 0;
  // headers are in; announce the total before the first byte
  Report;
  repeat
    CheckCancelled(aToken);
    if not InternetReadFile(aRequest, @lvBuffer[0], gcDownloadBufferSize, lvBytesRead) then
      RaiseWinInetError(aRequest, 'InternetReadFile', aHost, GetLastError);
    if lvBytesRead > 0 then
    begin
      aDest.WriteBuffer(lvBuffer[0], lvBytesRead);
      Inc(lvReceived, lvBytesRead);
      Report;
    end;
  until lvBytesRead = 0;
  CheckBodyComplete(aRequest, lvReceived, aTotal, aHost);
end;

// a dropped connection reads as a clean end of stream, so count the bytes
procedure TbpHttpClient.CheckBodyComplete(aRequest: HINTERNET;
  const aReceived, aExpected: Int64; const aHost: string);
begin
  if (aExpected >= 0) and (aReceived <> aExpected) then
    RaiseFailure(aRequest, Format(
      'Incomplete response from %s: received %d of %d bytes',
      [aHost, aReceived, aExpected]), 0);
end;

function TbpHttpClient.PerformHop(const aUrl, aMethod, aHeaders: string; const aBody: AnsiString;
  aWithCredentials, aDropContentHeaders: Boolean; aDest: TStream; aProgress: TbpHttpProgressEvent;
  aToken: TbpCancellationToken; out aRedirectTo: string): TbpHttpResponse;
var
  lvConnection, lvRequest: HINTERNET;
  lvServerName, lvResource: string;
  lvPort: Integer;
  lvSecure, lvOwnsRequest, lvDecoding: Boolean;
  lvCleanupId: Integer;
  lvBlock, lvHost: string;
  lvExpected: Int64;
begin
  aRedirectTo := '';
  CheckCancelled(aToken);
  if not ParseUrl(aUrl, lvServerName, lvResource, lvPort, lvSecure) then
    RaiseFailure(nil, 'Invalid URL: ' + BpHttpStripUserInfo(aUrl), 0);
  lvHost := HostPort(aUrl);

  // the instance owns the session; it is not closed here
  lvConnection := CreateConnection(SessionHandle, lvServerName, lvPort, lvHost);
  try
    lvRequest := CreateRequest(lvConnection, aMethod, lvResource, lvSecure,
      lvHost);
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
        // not on a stream, which checks Content-Length; and only from a WinInet that decodes
        lvDecoding := FAutoDecompress and (aDest = nil) and
          ApplyDecoding(lvRequest);
        if lvDecoding and not HeaderBlockHasName(lvBlock, 'Accept-Encoding') then
          AppendHeaderLine(lvBlock, 'Accept-Encoding: gzip, deflate');
        SendHttpRequest(lvRequest, lvBlock, aBody, lvHost);

        Result.StatusCode := ReadResponseStatus(lvRequest, lvHost);
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
          if aRedirectTo <> '' then
            DrainRedirectBody(lvRequest, aToken, lvHost)
          else if aDest <> nil then
            ReadBodyToStream(lvRequest, aDest, Result.ContentLength,
              aProgress, aToken, lvHost)
          else
          begin
            // WinInet drops both headers when it decodes; one that kept them would not count
            lvExpected := Result.ContentLength;
            if lvDecoding and (BpHttpHeaderValue(Result.Headers, 'Content-Encoding') <> '') then
              lvExpected := -1;
            Result.Body := ReadResponseBody(lvRequest, lvExpected, aToken,
              lvHost);
          end;
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
  lvCall: TbpHttpCall;
  lvTimeout: DWORD;
  i, lvHops: Integer;
begin
  // a stream's length is the caller's business, so a 1 GB download is not cut at 30 s
  if aDest = nil then
    lvTimeout := FTimeout
  else
    lvTimeout := INFINITE;
  // first, so a Destroy on another thread waits for everything below
  lvCall := TbpHttpCall.Create(Self, aToken, lvTimeout);
  try
    lvUrl := aUrl;
    lvMethod := aMethod;
    lvBody := aBody;
    lvHeaders := aHeaders;
    lvCredentials := True;
    lvDroppedBody := False;
    // a request header, so BuildHeaders drops it off origin like any other credential
    if BpHttpHeaderValue(BuildHeaders(aHeaders), 'Authorization') = '' then
    begin
      lvAuth := UrlBasicAuth(aUrl);
      if lvAuth <> '' then
        lvHeaders := 'Authorization: ' + lvAuth + #13#10 + lvHeaders;
    end;
    // a negative budget follows nothing, as 0 does, instead of failing every call
    lvHops := FMaxRedirects;
    if lvHops < 0 then
      lvHops := 0;
    try
      for i := 0 to lvHops do
      begin
        Result := PerformHop(lvUrl, lvMethod, lvHeaders, lvBody, lvCredentials,
          lvDroppedBody, aDest, aProgress, lvCall.Token, lvNext);
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
      RaiseFailure(nil, Format('More than %d redirects for %s',
        [FMaxRedirects, BpHttpStripUserInfo(aUrl)]), 0);
    except
      // the caller's own cancel wins; the deadline is a failure, not a cancel
      on E: EbpHttpClient do
        if lvCall.TimedOut and not ((aToken <> nil) and
          aToken.IsCancellationRequested) then
          RaiseFailure(nil, Format('Request to %s timed out: Timeout of %d ms elapsed',
            [HostPort(lvUrl), lvTimeout]), gcErrTimeout)
        else
          raise;
    end;
  finally
    lvCall.Free;
  end;
end;

function TbpHttpClient.Execute(aMethod: TbpHttpMethod; const aUrl: string; const aBody: AnsiString;
  const aHeaders: string; aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := PerformRequest(aUrl, MethodToString(aMethod), aHeaders, aBody,
    nil, nil, aToken);
end;

function TbpHttpClient.Get(const aUrl: string; const aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmGet, aUrl, '', aHeaders, aToken);
end;

function TbpHttpClient.Post(const aUrl: string; const aBody: AnsiString;
  const aHeaders: string; aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmPost, aUrl, aBody, aHeaders, aToken);
end;

function TbpHttpClient.PostJson(const aUrl: string; const aJson: AnsiString;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmPost, aUrl, aJson, 'Content-Type: application/json', aToken);
end;

function TbpHttpClient.Put(const aUrl: string; const aBody: AnsiString;
  const aHeaders: string; aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmPut, aUrl, aBody, aHeaders, aToken);
end;

function TbpHttpClient.Delete(const aUrl: string; const aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmDelete, aUrl, '', aHeaders, aToken);
end;

function TbpHttpClient.Patch(const aUrl: string; const aBody: AnsiString;
  const aHeaders: string; aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmPatch, aUrl, aBody, aHeaders, aToken);
end;

function TbpHttpClient.Head(const aUrl, aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmHead, aUrl, '', aHeaders, aToken);
end;

function TbpHttpClient.Options(const aUrl, aHeaders: string;
  aToken: TbpCancellationToken): TbpHttpResponse;
begin
  Result := Execute(hmOptions, aUrl, '', aHeaders, aToken);
end;

// .NET's GetStringAsync raises on a non-2xx too: an error page is no body to parse
class function TbpHttpClient.FetchUrl(const aUrl: string; const aHeaders: string): AnsiString;
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  lvClient := TbpHttpClient.Create;
  try
    lvResponse := lvClient.Get(aUrl, aHeaders);
    if not BpHttpResponseIsSuccess(lvResponse) then
      raise EbpHttpClient.Create(Format('HTTP %d %s from %s: %s',
        [lvResponse.StatusCode, lvResponse.StatusText,
        lvClient.HostPort(lvResponse.FinalUrl),
        BpClassifyHttpError(0, lvResponse.StatusCode)]), lvResponse.StatusCode);
    Result := lvResponse.Body;
  finally
    lvClient.Free;
  end;
end;

class function TbpHttpClient.Send(aMethod: TbpHttpMethod; const aUrl: string;
  const aBody: AnsiString; const aHeaders: string; aTimeoutMs: DWORD): TbpHttpResponse;
var
  lvClient: TbpHttpClient;
begin
  lvClient := TbpHttpClient.Create;
  try
    lvClient.Timeout := aTimeoutMs;
    // the 10 s steps would end a slow server's answer long before the deadline
    if aTimeoutMs > lvClient.ReceiveTimeout then
    begin
      lvClient.SendTimeout := aTimeoutMs;
      lvClient.ReceiveTimeout := aTimeoutMs;
    end;
    Result := lvClient.Execute(aMethod, aUrl, aBody, aHeaders);
  finally
    lvClient.Free;
  end;
end;

function TbpHttpClient.Download(const aUrl: string; aDest: TStream; aProgress: TbpHttpProgressEvent;
  aToken: TbpCancellationToken; const aHeaders: string; const aMethod: string): TbpHttpResponse;
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
  lvTemp, lvFileName: string;
  lvDone: Boolean;
begin
  lvDone := False;
  // once, so the temp file and the rename agree on the folder
  lvFileName := ExpandFileName(aFileName);
  lvTemp := BpTempFileNear(lvFileName);
  try
    lvFile := TFileStream.Create(lvTemp, fmCreate);
    try
      Result := Download(aUrl, lvFile, aProgress, aToken, aHeaders);
    finally
      lvFile.Free;
    end;
    // a 206 is a fragment, and BpHttpResponseIsSuccess would call it success
    if Result.StatusCode = 206 then
      raise EbpHttpClient.Create(
        'Server answered 206 Partial Content for a whole-file download',
        Result.StatusCode);
    // only a 200 carries the file; a 204 would empty the destination
    if Result.StatusCode = 200 then
    begin
      BpReplaceFile(lvTemp, lvFileName);
      lvDone := True;
    end;
  finally
    // every other path, a failed rename included, leaves no temp file behind
    if not lvDone then
      SysUtils.DeleteFile(lvTemp);
  end;
end;

{ async calls }

function BpStartHttpTask(aClient: TbpHttpClient; aKind: TbpHttpTaskKind;
  const aMethod, aUrl, aHeaders: string; const aBody: AnsiString;
  aDest: TStream; const aFileName: string; aOnDone: TbpHttpTaskEvent;
  aOnProgress: TbpHttpTaskProgressEvent): IbpHttpTask;
var
  lvTask: TbpHttpTaskImpl;
  lvRef: IbpHttpTask;
begin
  lvTask := TbpHttpTaskImpl.Create(aClient, aKind);
  // from here the reference count frees it, a failed Start included
  lvRef := lvTask;
  lvTask.FMethod := aMethod;
  lvTask.FUrl := aUrl;
  lvTask.FHeaders := aHeaders;
  lvTask.FBody := aBody;
  lvTask.FDest := aDest;
  lvTask.FFileName := aFileName;
  lvTask.FOnDone := aOnDone;
  lvTask.FOnProgress := aOnProgress;
  lvTask.FTask.Start;
  Result := lvRef;
end;

function TbpHttpClient.BeginExecute(aMethod: TbpHttpMethod; const aUrl: string;
  aOnDone: TbpHttpTaskEvent; const aBody: AnsiString; const aHeaders: string): IbpHttpTask;
begin
  Result := BpStartHttpTask(Self, htkBuffered, MethodToString(aMethod), aUrl,
    aHeaders, aBody, nil, '', aOnDone, nil);
end;

function TbpHttpClient.BeginGet(const aUrl: string; aOnDone: TbpHttpTaskEvent;
  const aHeaders: string): IbpHttpTask;
begin
  Result := BeginExecute(hmGet, aUrl, aOnDone, '', aHeaders);
end;

function TbpHttpClient.BeginPost(const aUrl: string; const aBody: AnsiString;
  aOnDone: TbpHttpTaskEvent; const aHeaders: string): IbpHttpTask;
begin
  Result := BeginExecute(hmPost, aUrl, aOnDone, aBody, aHeaders);
end;

function TbpHttpClient.BeginDownload(const aUrl: string; aDest: TStream; aOnDone: TbpHttpTaskEvent;
  aOnProgress: TbpHttpTaskProgressEvent; const aHeaders: string): IbpHttpTask;
begin
  if aDest = nil then
    raise EbpHttpClient.Create('Download destination stream is nil');
  Result := BpStartHttpTask(Self, htkStream, 'GET', aUrl, aHeaders, '', aDest,
    '', aOnDone, aOnProgress);
end;

function TbpHttpClient.BeginDownloadToFile(const aUrl, aFileName: string; aOnDone: TbpHttpTaskEvent;
  aOnProgress: TbpHttpTaskProgressEvent; const aHeaders: string): IbpHttpTask;
begin
  // on the caller's thread, against the folder the caller meant
  Result := BpStartHttpTask(Self, htkFile, 'GET', aUrl, aHeaders, '', nil,
    ExpandFileName(aFileName), aOnDone, aOnProgress);
end;

{ TbpHttpTaskImpl }

constructor TbpHttpTaskImpl.Create(aClient: TbpHttpClient; aKind: TbpHttpTaskKind);
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  InterlockedIncrement(gvLiveTasks);
  FKind := aKind;
  FTotal := -1;
  try
    FTask := TbpTask.Create(aClient.MarshalTaskEvents);
  except
    // callers of this unit catch EbpHttpClient, not EbpTask
    on E: EbpTask do
      raise EbpHttpClient.Create(E.Message);
  end;
  FTask.Work := DoWork;
  FTask.OnProgress := DispatchProgress;
  FTask.OnComplete := DispatchComplete;
  // linked before the worker exists, so the client's Destroy always sees it
  EnterCriticalSection(gvHttpLock);
  try
    if aClient.FDestroying then
      RaiseOperationCancelled;
    aClient.FTasks.Add(Self);
    FClient := aClient;
  finally
    LeaveCriticalSection(gvHttpLock);
  end;
end;

destructor TbpHttpTaskImpl.Destroy;
begin
  EnterCriticalSection(gvHttpLock);
  try
    if FClient <> nil then
      FClient.FTasks.Remove(Self);
    FClient := nil;
  finally
    LeaveCriticalSection(gvHttpLock);
  end;
  // cancels, joins, and lets no further event start
  FTask.Free;
  DeleteCriticalSection(FLock);
  InterlockedDecrement(gvLiveTasks);
  inherited;
end;

function TbpHttpTaskImpl.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TbpHttpTaskImpl._AddRef: Integer;
begin
  EnterCriticalSection(FLock);
  Inc(FRefCount);
  Result := FRefCount;
  LeaveCriticalSection(FLock);
end;

function TbpHttpTaskImpl._Release: Integer;
begin
  EnterCriticalSection(FLock);
  Dec(FRefCount);
  Result := FRefCount;
  LeaveCriticalSection(FLock);
  if Result > 0 then
    Exit;
  // released inside its own work: the worker cannot join itself, so the last event frees it
  if not FWorkDone and (FTask.WorkerThreadId = GetCurrentThreadId) then
  begin
    FFreePending := True;
    FTask.Cancel;
  end
  else
    Destroy;
end;

// nil once the count hit 0: another thread is freeing the task, and a hold would free it twice
function TbpHttpTaskImpl.Hold: IbpHttpTask;
begin
  EnterCriticalSection(FLock);
  try
    if FRefCount > 0 then
      Result := Self  // _AddRef enters FLock again, which a critical section allows
    else
      Result := nil;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

// gvHttpLock is held: the client is being destroyed
procedure TbpHttpTaskImpl.Detach;
begin
  FClient := nil;
  FTask.Cancel;
end;

procedure TbpHttpTaskImpl.DoWork(aSender: TObject; aToken: TbpCancellationToken);
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  EnterCriticalSection(gvHttpLock);
  lvClient := FClient;
  if lvClient <> nil then
    Inc(lvClient.FWorkers);
  LeaveCriticalSection(gvHttpLock);
  if lvClient = nil then
    RaiseOperationCancelled;  // the client went before the work began
  try
    try
      case FKind of
        htkBuffered:
          lvResponse := lvClient.PerformRequest(FUrl, FMethod, FHeaders, FBody,
            nil, nil, aToken);
        htkStream:
          lvResponse := lvClient.Download(FUrl, FDest, HandleWorkerProgress,
            aToken, FHeaders);
      else
        lvResponse := lvClient.DownloadToFile(FUrl, FFileName,
          HandleWorkerProgress, aToken, FHeaders);
      end;
    except
      // Response raises it again, as the sync call would have
      on E: Exception do
      begin
        FErrorClass := ExceptClass(E.ClassType);
        if E is EbpHttpClient then
        begin
          FErrorStatus := EbpHttpClient(E).StatusCode;
          FErrorCode := EbpHttpClient(E).WinInetError;
        end;
        raise;
      end;
    end;
  finally
    // the last touch of the client, whose Destroy waits for it
    EnterCriticalSection(gvHttpLock);
    Dec(lvClient.FWorkers);
    LeaveCriticalSection(gvHttpLock);
  end;
  FResponse := lvResponse;
end;

procedure TbpHttpTaskImpl.HandleWorkerProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  EnterCriticalSection(FLock);
  FReceived := aReceived;
  FTotal := aTotal;
  LeaveCriticalSection(FLock);
  if Assigned(FOnProgress) and not FFreePending then
    FTask.ReportProgress;
end;

procedure TbpHttpTaskImpl.DispatchProgress(aSender: TObject);
var
  lvSelf: IbpHttpTask;
  lvReceived, lvTotal: Int64;
begin
  if FFreePending or not Assigned(FOnProgress) then
    Exit;
  // held across the handler, which may drop the caller's reference
  lvSelf := Hold;
  if lvSelf = nil then
    Exit;
  EnterCriticalSection(FLock);
  lvReceived := FReceived;
  lvTotal := FTotal;
  LeaveCriticalSection(FLock);
  FOnProgress(lvSelf, lvReceived, lvTotal);
end;

procedure TbpHttpTaskImpl.DispatchComplete(aSender: TObject);
var
  lvSelf: IbpHttpTask;
begin
  // its caller let go inside the work, so there is no one to tell
  if FFreePending then
  begin
    Destroy;
    Exit;
  end;
  lvSelf := Hold;
  if lvSelf = nil then
    Exit;
  FWorkDone := True;
  if Assigned(FOnDone) then
    FOnDone(lvSelf);
end;

procedure TbpHttpTaskImpl.Cancel;
begin
  FTask.Cancel;
end;

function TbpHttpTaskImpl.WaitFor(aTimeoutMs: DWORD): Boolean;
begin
  Result := FTask.WaitFor(aTimeoutMs);
end;

function TbpHttpTaskImpl.IsFinished: Boolean;
begin
  Result := FTask.IsFinished;
end;

function TbpHttpTaskImpl.State: TbpHttpTaskState;
const
  lcStates: array[TbpTaskState] of TbpHttpTaskState = (htsPending, htsRunning,
    htsSucceeded, htsFailed, htsCancelled);
begin
  Result := lcStates[FTask.State];
end;

function TbpHttpTaskImpl.Response: TbpHttpResponse;
begin
  // the state is final before any event runs, so OnDone never waits here
  if not FTask.IsFinished then
  begin
    if FTask.WorkerThreadId = GetCurrentThreadId then
      raise EbpHttpClient.Create('Response waits for the task, which is this thread');
    FTask.WaitFor;
  end;
  case FTask.State of
    tskSucceeded:
      Result := FResponse;
    tskCancelled:
      RaiseOperationCancelled;
  else
    if FErrorClass = nil then
      raise EbpHttpClient.Create(ErrorMessage);
    if FErrorClass.InheritsFrom(EbpHttpClient) then
      raise EbpHttpClientClass(FErrorClass).Create(ErrorMessage, FErrorStatus, FErrorCode);
    raise FErrorClass.Create(ErrorMessage);
  end;
end;

function TbpHttpTaskImpl.ErrorMessage: string;
begin
  Result := FTask.ErrorMessage;
end;

function TbpHttpTaskImpl.Received: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FReceived;
  LeaveCriticalSection(FLock);
end;

function TbpHttpTaskImpl.Total: Int64;
begin
  EnterCriticalSection(FLock);
  Result := FTotal;
  LeaveCriticalSection(FLock);
end;

{ helper functions }

function BpHttpResponseIsSuccess(const aResponse: TbpHttpResponse): Boolean;
begin
  Result := (aResponse.StatusCode >= 200) and (aResponse.StatusCode < 300);
end;

// BpEncoding decodes the same, inline here so the bundle needs no extra unit
//   Result := BpDecodeBytes(aBytes, aCodePage);
function BpHttpDecode(const aBytes: AnsiString; aCodePage: Cardinal): WideString;
var
  lvLen: Integer;
begin
  Result := '';
  if aBytes = '' then
    Exit;
  // convert straight from the raw bytes so no ANSI codepage round trip happens
  lvLen := MultiByteToWideChar(aCodePage, 0, PAnsiChar(aBytes),
    Length(aBytes), nil, 0);
  if lvLen = 0 then
    Exit;
  SetLength(Result, lvLen);
  MultiByteToWideChar(aCodePage, 0, PAnsiChar(aBytes), Length(aBytes),
    PWideChar(Result), lvLen);
end;

// MultiByteToWideChar takes neither UTF-16 code page; an odd last byte is dropped
function BpHttpDecodeUtf16(const aBytes: AnsiString; aBigEndian: Boolean): WideString;
var
  i: Integer;
begin
  SetLength(Result, Length(aBytes) div 2);
  if Result = '' then
    Exit;
  Move(aBytes[1], Result[1], Length(Result) * SizeOf(WideChar));
  if aBigEndian then
    for i := 1 to Length(Result) do
      Result[i] := WideChar(Swap(Word(Result[i])));
end;

const
  gcCodePageUtf16 = 1200;
  gcCodePageUtf16BE = 1201;

// the charset parameter of a Content-Type, as a Windows code page; UTF-8 when absent or unknown
function BpHttpCharsetCodePage(const aContentType: string): Cardinal;
var
  lvName: string;
  lvPos: Integer;
begin
  Result := CP_UTF8;
  lvName := LowerCase(aContentType);
  lvPos := Pos('charset=', lvName);
  if lvPos = 0 then
    Exit;
  lvName := Copy(lvName, lvPos + Length('charset='), MaxInt);
  lvPos := Pos(';', lvName);
  if lvPos > 0 then
    SetLength(lvName, lvPos - 1);
  lvName := Trim(lvName);
  // RFC 9110 allows the value as a quoted-string
  if (Length(lvName) >= 2) and (lvName[1] = '"') and
    (lvName[Length(lvName)] = '"') then
    lvName := Copy(lvName, 2, Length(lvName) - 2);

  if (lvName = 'utf-16') or (lvName = 'utf-16le') then
    Result := gcCodePageUtf16
  else if lvName = 'utf-16be' then
    Result := gcCodePageUtf16BE
  else if lvName = 'us-ascii' then
    Result := 20127
  else if lvName = 'koi8-r' then
    Result := 20866
  else if lvName = 'koi8-u' then
    Result := 21866
  // iso-8859-1 is 28591 and so on up to iso-8859-15, 28605
  else if Copy(lvName, 1, 9) = 'iso-8859-' then
    Result := 28590 + Cardinal(StrToIntDef(Copy(lvName, 10, MaxInt), 0))
  else if Copy(lvName, 1, 8) = 'windows-' then
    Result := Cardinal(StrToIntDef(Copy(lvName, 9, MaxInt), CP_UTF8))
  else
    Exit;
  if (Result <> gcCodePageUtf16) and (Result <> gcCodePageUtf16BE) and
    not IsValidCodePage(Result) then
    Result := CP_UTF8;
end;

function BpHttpResponseBodyAsUtf8(const aResponse: TbpHttpResponse): WideString;
begin
  Result := BpHttpDecode(aResponse.Body, CP_UTF8);
end;

function BpHttpResponseText(const aResponse: TbpHttpResponse): WideString;
var
  lvBody: AnsiString;
  lvCodePage: Cardinal;
begin
  lvBody := aResponse.Body;
  // a BOM outranks the charset, as in .NET and WHATWG; Ord keeps the test code page free
  if (Length(lvBody) >= 3) and (Ord(lvBody[1]) = $EF) and (Ord(lvBody[2]) = $BB) and
    (Ord(lvBody[3]) = $BF) then
    Result := BpHttpDecode(Copy(lvBody, 4, MaxInt), CP_UTF8)
  else if (Length(lvBody) >= 2) and (Ord(lvBody[1]) = $FF) and (Ord(lvBody[2]) = $FE) then
    Result := BpHttpDecodeUtf16(Copy(lvBody, 3, MaxInt), False)
  else if (Length(lvBody) >= 2) and (Ord(lvBody[1]) = $FE) and (Ord(lvBody[2]) = $FF) then
    Result := BpHttpDecodeUtf16(Copy(lvBody, 3, MaxInt), True)
  else
  begin
    lvCodePage := BpHttpCharsetCodePage(BpHttpHeaderValue(aResponse.Headers,
      'Content-Type'));
    if lvCodePage = gcCodePageUtf16 then
      Result := BpHttpDecodeUtf16(lvBody, False)
    else if lvCodePage = gcCodePageUtf16BE then
      Result := BpHttpDecodeUtf16(lvBody, True)
    else
      Result := BpHttpDecode(lvBody, lvCodePage);
  end;
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

function BpHttpRedirectTarget(const aBaseUrl, aHeaders: string; aStatus: Integer): string;
var
  lvLocation: string;
  lvLen: DWORD;
  lvCombined: Boolean;
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
  lvLen := INTERNET_MAX_URL_LENGTH + 1;
  SetLength(Result, lvLen);
  // Location may be relative, and this is the RFC 3986 resolver Windows ships
  lvCombined := InternetCombineUrl(PChar(aBaseUrl), PChar(lvLocation),
    PChar(Result), lvLen, 0);
  // a longer url fails, and reports the size it needs in lvLen
  if not lvCombined and (GetLastError = ERROR_INSUFFICIENT_BUFFER) then
  begin
    SetLength(Result, lvLen);
    lvCombined := InternetCombineUrl(PChar(aBaseUrl), PChar(lvLocation),
      PChar(Result), lvLen, 0);
  end;
  if lvCombined then
    SetLength(Result, lvLen)
  else
    Result := '';
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

function BpHttpFilterHeaders(const aHeaders: string; aDrop: TbpHeaderNameTest): string;
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

function BpHttpStripUserInfo(const aUrl: string): string;
var
  lvStart, lvAt, i: Integer;
begin
  Result := aUrl;
  lvStart := Pos('://', Result);
  if lvStart = 0 then
    Exit;
  Inc(lvStart, 3);

  // userinfo sits before the last @ of the authority
  lvAt := 0;
  for i := lvStart to Length(Result) do
  begin
    // the authority ends at the path, the query or the fragment
    if (Result[i] = '/') or (Result[i] = '?') or (Result[i] = '#') then
      Break;
    if Result[i] = '@' then
      lvAt := i;
  end;

  if lvAt > 0 then
    Delete(Result, lvStart, lvAt - lvStart + 1);
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
      gcErrTimeout:
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

procedure BpSetHttpFailureHook(aHook: TbpHttpFailureHook);
begin
  gvFailureHook := aHook;
end;

initialization
  InitializeCriticalSection(gvHttpLock);

finalization
  // a task its caller never released may still be running, and would enter a deleted lock
  if gvLiveTasks = 0 then
    DeleteCriticalSection(gvHttpLock);

end.
