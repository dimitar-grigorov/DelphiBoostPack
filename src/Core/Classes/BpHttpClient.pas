unit BpHttpClient;

// HTTP/HTTPS over WinInet for Delphi 7/2007+. TLS comes from Schannel, so no
// OpenSSL DLLs to ship. Cancellable sync verbs, streaming downloads with
// progress, and an async download task. See the README for examples.

interface

uses
  Classes, SysUtils, Windows, Messages, WinInet;

type
  TbpHttpMethod = (hmGet, hmPost, hmPut, hmDelete);

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
  end;

  TbpCancelCleanupProc = procedure(aData: Pointer);

  // cooperative cancel (C# CancellationToken style); thread-safe, one-shot
  TbpCancellationToken = class
  private
    FLock: TRTLCriticalSection;
    FCancelled: Integer;
    FCleanupProcs: array of TbpCancelCleanupProc;
    FCleanupData: array of Pointer;
    FCleanupIds: array of Integer;
    FNextId: Integer;
    function IndexOfId(aId: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Cancel;
    function IsCancellationRequested: Boolean;
    // cleanup runs inside Cancel; False when already cancelled
    function RegisterCleanup(aProc: TbpCancelCleanupProc; aData: Pointer;
      out aId: Integer): Boolean;
    // True when still pending, False when Cancel already ran it
    function UnregisterCleanup(aId: Integer): Boolean;
  end;

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
    function GetWinInetErrorMessage(aErrorCode: DWORD): string;
    function CreateSession: HINTERNET;
    function AcquireSession: HINTERNET;
    procedure CloseSession;
    procedure ApplyTimeoutsToSession;
    function CreateConnection(aSession: HINTERNET; const aServerName: string;
      aPort: Integer): HINTERNET;
    function CreateRequest(aConnection: HINTERNET; const aMethod, aResource: string;
      aSecure: Boolean): HINTERNET;
    procedure ApplyTimeouts(aHandle: HINTERNET);
    procedure ApplyAuthentication(aRequest: HINTERNET);
    procedure SendHttpRequest(aRequest: HINTERNET; const aHeaders: string;
      const aBody: AnsiString);
    function ReadResponseStatus(aRequest: HINTERNET): Integer;
    function ReadResponseHeaders(aRequest: HINTERNET): string;
    function ReadResponseBody(aRequest: HINTERNET;
      aToken: TbpCancellationToken): AnsiString;
    procedure ReadBodyToStream(aRequest: HINTERNET; aDest: TStream;
      const aTotal: Int64; aProgress: TbpHttpProgressEvent;
      aToken: TbpCancellationToken);
    // the one request the verbs and the downloads both go through;
    // nil aDest buffers the body into the result instead of streaming it
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
    class function FetchUrl(const aUrl: string; const aHeaders: string = ''): AnsiString;

    // streams the body to aDest whatever the status; cancel raises
    // EbpHttpClientCancelled ('Range: bytes=N-' in aHeaders resumes)
    function Download(const aUrl: string; aDest: TStream;
      aProgress: TbpHttpProgressEvent = nil; aToken: TbpCancellationToken = nil;
      const aHeaders: string = ''; const aMethod: string = 'GET'): TbpHttpResponse;
    // the file survives only on a 2xx; deleted on error, cancel or non-2xx
    function DownloadToFile(const aUrl, aFileName: string;
      aProgress: TbpHttpProgressEvent = nil; aToken: TbpCancellationToken = nil;
      const aHeaders: string = ''): TbpHttpResponse;

    // persistent headers sent with every request; setting a name again replaces it
    procedure AddHeader(const aName, aValue: string);
    procedure ClearHeaders;
    // preemptive Basic auth header via Base64; clears BearerToken
    procedure SetBasicAuth(const aUser, aPassword: AnsiString);

    // exposed for testing; also useful on their own
    function ParseUrl(const aUrl: string; out aServerName, aResource: string;
      out aPort: Integer; out aSecure: Boolean): Boolean;
    function BuildHeaders(const aRequestHeaders: string): string;
    class function MethodToString(aMethod: TbpHttpMethod): string;

    // changing it drops the session, so set it before the first request
    property UserAgent: string read FUserAgent write SetUserAgent;
    property Username: AnsiString read FUsername write FUsername;
    property Password: AnsiString read FPassword write FPassword;
    // sent as 'Authorization: Bearer <token>' when not empty
    property BearerToken: string read FBearerToken write FBearerToken;
    property ConnectTimeout: DWORD read FConnectTimeout write SetConnectTimeout;
    property SendTimeout: DWORD read FSendTimeout write SetSendTimeout;
    property ReceiveTimeout: DWORD read FReceiveTimeout write SetReceiveTimeout;
    property FollowRedirects: Boolean read FFollowRedirects write FFollowRedirects;
  end;

  TbpHttpDownloadState = (dtsPending, dtsRunning, dtsSucceeded, dtsFailed,
    dtsCancelled);

  TbpHttpDownloadCompleteEvent = procedure(aSender: TObject) of object;
  TbpHttpDownloadErrorEvent = procedure(aSender: TObject;
    const aErrorMessage: string) of object;

  // one download on an owned worker thread, C# Task style; one-shot.
  // Events fire on the creating thread's message loop (default) or on the
  // worker thread (Create(False)); results are thread-safe once IsFinished.
  TbpHttpDownloadTask = class
  private
    FClient: TbpHttpClient;        // owned; configure via Client before Start
    FToken: TbpCancellationToken;  // owned
    FThread: TThread;              // owned worker, joined in Destroy
    FLock: TRTLCriticalSection;    // guards state, progress pair and results
    FUrl: string;
    FDestFileName: string;
    FDestStream: TStream;          // caller-owned; must outlive the task
    FHeaders: string;
    FMarshalToMainThread: Boolean;
    FWnd: HWND;                    // hidden marshaling window, 0 when direct
    FState: TbpHttpDownloadState;
    FReceived: Int64;
    FTotal: Int64;
    FProgressPosted: Integer;      // coalescing flag for progress posts
    FResponse: TbpHttpResponse;
    FErrorMessage: string;
    FErrorCode: DWORD;
    FHttpStatus: Integer;
    FOnProgress: TbpHttpProgressEvent;
    FOnComplete: TbpHttpDownloadCompleteEvent;
    FOnError: TbpHttpDownloadErrorEvent;
    function GetState: TbpHttpDownloadState;
    function GetReceived: Int64;
    function GetTotal: Int64;
    function GetResponse: TbpHttpResponse;
    function GetErrorMessage: string;
    function GetErrorCode: DWORD;
    function GetHttpStatus: Integer;
    procedure WndProc(var aMessage: TMessage);
    procedure HandleWorkerProgress(aSender: TObject; const aReceived,
      aTotal: Int64; var aCancel: Boolean);
    procedure FireCompletionEvents;
    procedure RunDownload;  // worker thread body
  public
    // create on the thread that should receive the events (destructor
    // cancels, joins the worker and frees everything)
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
    property Token: TbpCancellationToken read FToken;
    property MarshalToMainThread: Boolean read FMarshalToMainThread;

    // results, thread-safe at any time; authoritative once IsFinished
    property State: TbpHttpDownloadState read GetState;
    property Received: Int64 read GetReceived;
    property Total: Int64 read GetTotal;   // -1 while or when unknown
    property Response: TbpHttpResponse read GetResponse;
    property ErrorMessage: string read GetErrorMessage;
    property ErrorCode: DWORD read GetErrorCode;        // WinInet error, 0 if none
    property HttpStatus: Integer read GetHttpStatus;    // status of a failed response

    // OnComplete fires on every terminal state (check State inside);
    // OnError fires before it on dtsFailed
    property OnProgress: TbpHttpProgressEvent read FOnProgress write FOnProgress;
    property OnComplete: TbpHttpDownloadCompleteEvent read FOnComplete write FOnComplete;
    property OnError: TbpHttpDownloadErrorEvent read FOnError write FOnError;
  end;

// hot tasks: create, wire and start in one call; the caller frees the task.
// Two names, not an overload: old compilers reject nil events on overloads.
function BpDownloadAsync(const aUrl, aFileName: string;
  aOnProgress: TbpHttpProgressEvent = nil;
  aOnComplete: TbpHttpDownloadCompleteEvent = nil;
  aMarshalToMainThread: Boolean = True): TbpHttpDownloadTask;
function BpDownloadToStreamAsync(const aUrl: string; aDest: TStream;
  aOnProgress: TbpHttpProgressEvent = nil;
  aOnComplete: TbpHttpDownloadCompleteEvent = nil;
  aMarshalToMainThread: Boolean = True): TbpHttpDownloadTask;

function BpHttpResponseIsSuccess(const aResponse: TbpHttpResponse): Boolean;
// decodes the body as UTF-8 (invalid input yields an empty string)
function BpHttpResponseBodyAsUtf8(const aResponse: TbpHttpResponse): WideString;
// value of a header line from a raw CRLF header block, '' when absent
function BpHttpHeaderValue(const aHeaders, aName: string): string;
// Content-Length parsed from a raw header block; -1 when absent or invalid
function BpHttpContentLength(const aHeaders: string): Int64;
// whole percent 0..100 for a progress pair; -1 when the total is unknown
function BpHttpProgressPercent(const aReceived, aTotal: Int64): Integer;
// user-facing categorization; pass 0 for the dimension that does not apply
function BpClassifyHttpError(aWinInetError: DWORD; aHttpStatus: Integer): string;

const
  // WinInet ERROR_INTERNET_OPERATION_CANCELLED, missing from D2007's WinInet.pas
  gcErrOperationCancelled = 12017;

implementation

uses
  BpBase64;

const
  gcBufferSize = 8192;
  gcDownloadBufferSize = 65536;  // bigger chunks pay off on large bodies
  gcDefaultTimeout = 8000;  // milliseconds
  gcDefaultUserAgent = 'DelphiBoostPack/1.0';
  gcWmTaskProgress = WM_APP + 1;
  gcWmTaskDone = WM_APP + 2;

// appends a header line with a CRLF separator between lines
procedure AppendHeaderLine(var aHeaders: string; const aLine: string);
begin
  if aLine = '' then
    Exit;
  if aHeaders <> '' then
    aHeaders := aHeaders + #13#10;
  aHeaders := aHeaders + aLine;
end;

// registered with the token so Cancel aborts a blocked WinInet call by
// closing its request handle (fails over with error 12017)
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

{ TbpCancellationToken }

constructor TbpCancellationToken.Create;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FNextId := 1;
end;

destructor TbpCancellationToken.Destroy;
begin
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpCancellationToken.IsCancellationRequested: Boolean;
begin
  // aligned 32-bit read is atomic; the lock only guards the write side
  Result := FCancelled <> 0;
end;

function TbpCancellationToken.IndexOfId(aId: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FCleanupIds) do
    if FCleanupIds[i] = aId then
    begin
      Result := i;
      Exit;
    end;
end;

procedure TbpCancellationToken.Cancel;
var
  i: Integer;
begin
  EnterCriticalSection(FLock);
  try
    if FCancelled <> 0 then
      Exit;
    FCancelled := 1;
    // run in registration order, then drop everything so a later
    // UnregisterCleanup reports the cleanup as already executed
    for i := 0 to High(FCleanupProcs) do
      FCleanupProcs[i](FCleanupData[i]);
    SetLength(FCleanupProcs, 0);
    SetLength(FCleanupData, 0);
    SetLength(FCleanupIds, 0);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TbpCancellationToken.RegisterCleanup(aProc: TbpCancelCleanupProc;
  aData: Pointer; out aId: Integer): Boolean;
var
  lvCount: Integer;
begin
  aId := 0;
  Result := False;
  EnterCriticalSection(FLock);
  try
    if FCancelled <> 0 then
      Exit;
    lvCount := Length(FCleanupProcs);
    SetLength(FCleanupProcs, lvCount + 1);
    SetLength(FCleanupData, lvCount + 1);
    SetLength(FCleanupIds, lvCount + 1);
    FCleanupProcs[lvCount] := aProc;
    FCleanupData[lvCount] := aData;
    FCleanupIds[lvCount] := FNextId;
    aId := FNextId;
    Inc(FNextId);
    Result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TbpCancellationToken.UnregisterCleanup(aId: Integer): Boolean;
var
  lvIndex, i: Integer;
begin
  EnterCriticalSection(FLock);
  try
    lvIndex := IndexOfId(aId);
    Result := lvIndex >= 0;
    if not Result then
      Exit;
    for i := lvIndex to High(FCleanupProcs) - 1 do
    begin
      FCleanupProcs[i] := FCleanupProcs[i + 1];
      FCleanupData[i] := FCleanupData[i + 1];
      FCleanupIds[i] := FCleanupIds[i + 1];
    end;
    SetLength(FCleanupProcs, Length(FCleanupProcs) - 1);
    SetLength(FCleanupData, Length(FCleanupData) - 1);
    SetLength(FCleanupIds, Length(FCleanupIds) - 1);
  finally
    LeaveCriticalSection(FLock);
  end;
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
  FHeaders.Values[aName] := aValue;
end;

procedure TbpHttpClient.ClearHeaders;
begin
  FHeaders.Clear;
end;

procedure TbpHttpClient.SetBasicAuth(const aUser, aPassword: AnsiString);
begin
  FBearerToken := '';
  AddHeader('Authorization', 'Basic ' + Base64Encode(aUser + ':' + aPassword));
end;

class function TbpHttpClient.MethodToString(aMethod: TbpHttpMethod): string;
begin
  case aMethod of
    hmGet: Result := 'GET';
    hmPost: Result := 'POST';
    hmPut: Result := 'PUT';
    hmDelete: Result := 'DELETE';
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

function TbpHttpClient.ParseUrl(const aUrl: string; out aServerName,
  aResource: string; out aPort: Integer; out aSecure: Boolean): Boolean;
var
  lvComponents: TURLComponents;
  lvHostBuffer: array[0..INTERNET_MAX_HOST_NAME_LENGTH] of Char;
  lvPathBuffer: array[0..INTERNET_MAX_PATH_LENGTH] of Char;
  lvExtraBuffer: array[0..INTERNET_MAX_PATH_LENGTH] of Char;
begin
  Result := False;

  ZeroMemory(@lvComponents, SizeOf(lvComponents));
  ZeroMemory(@lvHostBuffer, SizeOf(lvHostBuffer));
  ZeroMemory(@lvPathBuffer, SizeOf(lvPathBuffer));
  ZeroMemory(@lvExtraBuffer, SizeOf(lvExtraBuffer));

  lvComponents.dwStructSize := SizeOf(lvComponents);
  lvComponents.lpszHostName := @lvHostBuffer[0];
  lvComponents.dwHostNameLength := Length(lvHostBuffer);
  lvComponents.lpszUrlPath := @lvPathBuffer[0];
  lvComponents.dwUrlPathLength := Length(lvPathBuffer);
  lvComponents.lpszExtraInfo := @lvExtraBuffer[0];
  lvComponents.dwExtraInfoLength := Length(lvExtraBuffer);

  if not InternetCrackUrl(PChar(aUrl), Length(aUrl), 0, lvComponents) then
    Exit;

  aServerName := lvComponents.lpszHostName;
  // keep the query string attached to the resource
  aResource := string(lvComponents.lpszUrlPath) + string(lvComponents.lpszExtraInfo);
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

function TbpHttpClient.BuildHeaders(const aRequestHeaders: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FHeaders.Count - 1 do
    AppendHeaderLine(Result, FHeaders.Names[i] + ': ' + FHeaders.ValueFromIndex[i]);
  if FBearerToken <> '' then
    AppendHeaderLine(Result, 'Authorization: Bearer ' + FBearerToken);
  AppendHeaderLine(Result, Trim(aRequestHeaders));
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

// lazy, one per client; WinInet pools its keep-alive connections here
function TbpHttpClient.AcquireSession: HINTERNET;
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
    0);

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

  if not FFollowRedirects then
    lvFlags := lvFlags or INTERNET_FLAG_NO_AUTO_REDIRECT;

  Result := HttpOpenRequest(
    aConnection,
    PChar(aMethod),
    PChar(aResource),
    nil,  // nil version defaults to HTTP/1.1 on any non-ancient Windows
    nil,
    nil,
    lvFlags,
    0);

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
  lvBuffer: array[0..gcBufferSize - 1] of Byte;
  lvBytesRead, lvErr: DWORD;
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  try
    repeat
      if (aToken <> nil) and aToken.IsCancellationRequested then
        RaiseOperationCancelled;

      if not InternetReadFile(aRequest, @lvBuffer[0], gcBufferSize, lvBytesRead) then
      begin
        lvErr := GetLastError;
        raise EbpHttpClient.Create(
          'Failed to read HTTP response: ' + GetWinInetErrorMessage(lvErr),
          0, lvErr);
      end;

      if lvBytesRead > 0 then
        lvStream.WriteBuffer(lvBuffer[0], lvBytesRead);
    until lvBytesRead = 0;

    SetLength(Result, lvStream.Size);
    if lvStream.Size > 0 then
    begin
      lvStream.Position := 0;
      lvStream.ReadBuffer(Result[1], lvStream.Size);
    end;
  finally
    lvStream.Free;
  end;
end;

function TbpHttpClient.PerformRequest(const aUrl, aMethod, aHeaders: string;
  const aBody: AnsiString; aDest: TStream; aProgress: TbpHttpProgressEvent;
  aToken: TbpCancellationToken): TbpHttpResponse;
var
  lvConnection, lvRequest: HINTERNET;
  lvServerName, lvResource: string;
  lvPort: Integer;
  lvSecure, lvOwnsRequest: Boolean;
  lvCleanupId: Integer;
begin
  if (aToken <> nil) and aToken.IsCancellationRequested then
    RaiseOperationCancelled;
  if not ParseUrl(aUrl, lvServerName, lvResource, lvPort, lvSecure) then
    raise EbpHttpClient.Create('Invalid URL: ' + aUrl);

  // the instance owns the session; it is not closed here
  lvConnection := CreateConnection(AcquireSession, lvServerName, lvPort);
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
        ApplyAuthentication(lvRequest);
        SendHttpRequest(lvRequest, BuildHeaders(aHeaders), aBody);

        Result.StatusCode := ReadResponseStatus(lvRequest);
        Result.Headers := ReadResponseHeaders(lvRequest);
        Result.StatusText := Format('HTTP %d', [Result.StatusCode]);
        Result.ContentLength := BpHttpContentLength(Result.Headers);
        Result.Body := '';

        if aDest <> nil then
          ReadBodyToStream(lvRequest, aDest, Result.ContentLength, aProgress,
            aToken)
        else
          Result.Body := ReadResponseBody(lvRequest, aToken);
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

function TbpHttpClient.DownloadToFile(const aUrl, aFileName: string;
  aProgress: TbpHttpProgressEvent; aToken: TbpCancellationToken;
  const aHeaders: string): TbpHttpResponse;
var
  lvFile: TFileStream;
  lvKeep: Boolean;
begin
  lvKeep := False;
  lvFile := TFileStream.Create(aFileName, fmCreate);
  try
    Result := Download(aUrl, lvFile, aProgress, aToken, aHeaders);
    lvKeep := BpHttpResponseIsSuccess(Result);
  finally
    lvFile.Free;
    // never leave a partial or error-page file behind
    if not lvKeep then
      SysUtils.DeleteFile(aFileName);
  end;
end;

{ TbpHttpDownloadTask }

type
  // thin shell; the logic lives in TbpHttpDownloadTask.RunDownload
  TbpDownloadThread = class(TThread)
  private
    FTask: TbpHttpDownloadTask;
  protected
    procedure Execute; override;
  public
    constructor Create(aTask: TbpHttpDownloadTask);
  end;

constructor TbpDownloadThread.Create(aTask: TbpHttpDownloadTask);
begin
  FTask := aTask;
  FreeOnTerminate := False;  // the task owns and joins the thread
  inherited Create(False);
end;

procedure TbpDownloadThread.Execute;
begin
  FTask.RunDownload;
end;

constructor TbpHttpDownloadTask.Create(aMarshalToMainThread: Boolean);
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FClient := TbpHttpClient.Create;
  FToken := TbpCancellationToken.Create;
  FState := dtsPending;
  FTotal := -1;
  FMarshalToMainThread := aMarshalToMainThread;
  if FMarshalToMainThread then
    FWnd := Classes.AllocateHWnd(WndProc);
end;

destructor TbpHttpDownloadTask.Destroy;
begin
  // abort and join first: the worker touches FClient/FToken/fields
  FToken.Cancel;
  if FThread <> nil then
  begin
    FThread.WaitFor;
    FThread.Free;
  end;
  if FWnd <> 0 then
    Classes.DeallocateHWnd(FWnd);  // pending posted messages are discarded
  FToken.Free;
  FClient.Free;
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpHttpDownloadTask.GetState: TbpHttpDownloadState;
begin
  EnterCriticalSection(FLock);
  Result := FState;
  LeaveCriticalSection(FLock);
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
  EnterCriticalSection(FLock);
  Result := FErrorMessage;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetErrorCode: DWORD;
begin
  EnterCriticalSection(FLock);
  Result := FErrorCode;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.GetHttpStatus: Integer;
begin
  EnterCriticalSection(FLock);
  Result := FHttpStatus;
  LeaveCriticalSection(FLock);
end;

function TbpHttpDownloadTask.IsFinished: Boolean;
begin
  Result := GetState in [dtsSucceeded, dtsFailed, dtsCancelled];
end;

procedure TbpHttpDownloadTask.Start;
begin
  if FUrl = '' then
    raise EbpHttpClient.Create('Download task has no Url');
  if (FDestFileName = '') and (FDestStream = nil) then
    raise EbpHttpClient.Create('Download task has no destination (set DestFileName or DestStream)');
  if (FDestFileName <> '') and (FDestStream <> nil) then
    raise EbpHttpClient.Create('Download task has both DestFileName and DestStream; set only one');

  EnterCriticalSection(FLock);
  try
    if FState <> dtsPending then
      raise EbpHttpClient.Create('Download task already started');
    FState := dtsRunning;
  finally
    LeaveCriticalSection(FLock);
  end;

  FThread := TbpDownloadThread.Create(Self);
end;

procedure TbpHttpDownloadTask.Cancel;
begin
  FToken.Cancel;
end;

function TbpHttpDownloadTask.WaitFor(aTimeoutMs: DWORD): Boolean;
begin
  if FThread = nil then
    Result := IsFinished  // never started
  else
    Result := WaitForSingleObject(FThread.Handle, aTimeoutMs) = WAIT_OBJECT_0;
end;

// worker thread: forward directly, or store and post one coalesced note
procedure TbpHttpDownloadTask.HandleWorkerProgress(aSender: TObject;
  const aReceived, aTotal: Int64; var aCancel: Boolean);
begin
  EnterCriticalSection(FLock);
  FReceived := aReceived;
  FTotal := aTotal;
  LeaveCriticalSection(FLock);

  if FMarshalToMainThread then
  begin
    if InterlockedExchange(FProgressPosted, 1) = 0 then
      PostMessage(FWnd, gcWmTaskProgress, 0, 0);
  end
  else if Assigned(FOnProgress) then
    FOnProgress(Self, aReceived, aTotal, aCancel);
end;

// main thread (marshaled mode only)
procedure TbpHttpDownloadTask.WndProc(var aMessage: TMessage);
var
  lvReceived, lvTotal: Int64;
  lvCancel: Boolean;
begin
  case aMessage.Msg of
    gcWmTaskProgress:
      begin
        InterlockedExchange(FProgressPosted, 0);
        if Assigned(FOnProgress) then
        begin
          EnterCriticalSection(FLock);
          lvReceived := FReceived;
          lvTotal := FTotal;
          LeaveCriticalSection(FLock);
          lvCancel := False;
          FOnProgress(Self, lvReceived, lvTotal, lvCancel);
          if lvCancel then
            Cancel;
        end;
      end;
    gcWmTaskDone:
      FireCompletionEvents;
  else
    aMessage.Result := DefWindowProc(FWnd, aMessage.Msg, aMessage.WParam,
      aMessage.LParam);
  end;
end;

procedure TbpHttpDownloadTask.FireCompletionEvents;
begin
  if (GetState = dtsFailed) and Assigned(FOnError) then
    FOnError(Self, GetErrorMessage);
  if Assigned(FOnComplete) then
    FOnComplete(Self);
end;

procedure TbpHttpDownloadTask.RunDownload;
var
  lvResponse: TbpHttpResponse;
  lvState: TbpHttpDownloadState;
  lvErrorMessage: string;
  lvErrorCode: DWORD;
  lvHttpStatus: Integer;
begin
  lvErrorMessage := '';
  lvErrorCode := 0;
  lvHttpStatus := 0;
  // an exception path leaves lvResponse unassigned; keep it defined
  lvResponse.StatusCode := 0;
  lvResponse.StatusText := '';
  lvResponse.Headers := '';
  lvResponse.Body := '';
  lvResponse.ContentLength := -1;
  try
    if FDestFileName <> '' then
      lvResponse := FClient.DownloadToFile(FUrl, FDestFileName,
        HandleWorkerProgress, FToken, FHeaders)
    else
      lvResponse := FClient.Download(FUrl, FDestStream,
        HandleWorkerProgress, FToken, FHeaders);

    if BpHttpResponseIsSuccess(lvResponse) then
      lvState := dtsSucceeded
    else
    begin
      lvState := dtsFailed;
      lvHttpStatus := lvResponse.StatusCode;
      lvErrorMessage := BpClassifyHttpError(0, lvResponse.StatusCode);
    end;
  except
    on E: EbpHttpClientCancelled do
    begin
      lvState := dtsCancelled;
      lvErrorMessage := E.Message;
      lvErrorCode := E.WinInetError;
    end;
    on E: EbpHttpClient do
    begin
      lvState := dtsFailed;
      lvErrorMessage := E.Message;
      lvErrorCode := E.WinInetError;
      lvHttpStatus := E.StatusCode;
    end;
    on E: Exception do
    begin
      lvState := dtsFailed;
      lvErrorMessage := E.Message;
    end;
  end;

  // publish results before the state turns terminal, then notify
  EnterCriticalSection(FLock);
  FResponse := lvResponse;
  FErrorMessage := lvErrorMessage;
  FErrorCode := lvErrorCode;
  FHttpStatus := lvHttpStatus;
  FState := lvState;
  LeaveCriticalSection(FLock);

  if FMarshalToMainThread then
    PostMessage(FWnd, gcWmTaskDone, 0, 0)
  else
    FireCompletionEvents;
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
  lvLines: TStringList;
  lvLine, lvPrefix: string;
  i, lvColon: Integer;
begin
  Result := '';
  lvPrefix := LowerCase(aName);
  lvLines := TStringList.Create;
  try
    lvLines.Text := aHeaders;
    for i := 0 to lvLines.Count - 1 do
    begin
      lvLine := lvLines[i];
      lvColon := Pos(':', lvLine);
      if lvColon = 0 then
        Continue;
      if LowerCase(Trim(Copy(lvLine, 1, lvColon - 1))) = lvPrefix then
      begin
        Result := Trim(Copy(lvLine, lvColon + 1, MaxInt));
        Exit;
      end;
    end;
  finally
    lvLines.Free;
  end;
end;

function BpHttpContentLength(const aHeaders: string): Int64;
var
  lvValue: string;
begin
  Result := -1;
  lvValue := BpHttpHeaderValue(aHeaders, 'Content-Length');
  if lvValue = '' then
    Exit;
  Result := StrToInt64Def(lvValue, -1);
  if Result < 0 then
    Result := -1;
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
  lcErrSecureFailure     = 12175;
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
      lcErrCertDateInvalid, lcErrCertCnInvalid, lcErrInvalidCa, lcErrSecureFailure:
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
