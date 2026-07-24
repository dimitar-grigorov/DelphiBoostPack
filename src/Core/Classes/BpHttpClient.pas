unit BpHttpClient;

// HTTP/HTTPS client over WinInet for Delphi 7/2007 and later.
// TLS comes from Schannel, so no OpenSSL DLLs are needed.
//
// TbpHttpClient wraps the session/connection/request handle dance behind
// Get/Post/Put/Delete returning a TbpHttpResponse record. Persistent custom
// headers (AddHeader), a BearerToken property and a SetBasicAuth helper cover
// the common API auth schemes; PostJson sets the Content-Type for the typical
// JSON endpoint call. Username/Password go through the WinInet option instead
// of a header, so they also answer proxy and 401 challenges.
// Failures raise EbpHttpClient carrying the WinInet error code, and
// BpClassifyHttpError turns either error dimension into a user-facing string.
//
// Download/DownloadToFile stream a body of any size to a TStream or file in
// constant memory, reporting Int64 progress and honouring cooperative
// cancellation through TbpCancellationToken (see BpCancellationToken.pas).
// A cancel closes the WinInet request handle, so even a thread blocked in
// connect or read aborts promptly; the failure surfaces as the typed
// EbpHttpClientCancelled. For the non-blocking wrapper that runs a download
// on a worker thread see BpHttpDownloadTask.pas.

interface

uses
  Classes, SysUtils, Windows, WinInet, BpCancellationToken;

type
  TbpHttpMethod = (hmGet, hmPost, hmPut, hmDelete);

  EbpHttpClient = class(Exception)
  private
    FStatusCode: Integer;
    FWinInetError: DWORD;
  public
    constructor Create(const AMessage: string; AStatusCode: Integer = 0;
      AWinInetError: DWORD = 0);
    property StatusCode: Integer read FStatusCode;
    property WinInetError: DWORD read FWinInetError;
  end;

  // raised when a download is aborted through a token or a progress callback;
  // WinInetError is gcErrOperationCancelled
  EbpHttpClientCancelled = class(EbpHttpClient);

  TbpHttpResponse = record
    StatusCode: Integer;
    StatusText: string;
    Headers: string;         // raw response headers, CRLF separated
    Body: AnsiString;        // raw bytes as received; empty for Download
    ContentLength: Int64;    // from the Content-Length header, -1 when absent
  end;

  // progress callback for downloads, fired synchronously on the thread that
  // runs the download: once after the headers arrive (AReceived = 0) and then
  // after every chunk. ATotal is -1 when the server sent no Content-Length
  // (chunked transfer). Set ACancel to True to abort; the download raises
  // EbpHttpClientCancelled and, for DownloadToFile, deletes the partial file.
  TbpHttpProgressEvent = procedure(ASender: TObject; const AReceived,
    ATotal: Int64; var ACancel: Boolean) of object;

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
    function GetWinInetErrorMessage(AErrorCode: DWORD): string;
    function CreateSession: HINTERNET;
    function CreateConnection(ASession: HINTERNET; const AServerName: string;
      APort: Integer): HINTERNET;
    function CreateRequest(AConnection: HINTERNET; const AMethod, AResource: string;
      ASecure: Boolean): HINTERNET;
    procedure ApplyTimeouts(AHandle: HINTERNET);
    procedure ApplyAuthentication(ARequest: HINTERNET);
    procedure SendHttpRequest(ARequest: HINTERNET; const AHeaders: string;
      const ABody: AnsiString);
    function ReadResponseStatus(ARequest: HINTERNET): Integer;
    function ReadResponseHeaders(ARequest: HINTERNET): string;
    function ReadResponseBody(ARequest: HINTERNET): AnsiString;
    procedure ReadBodyToStream(ARequest: HINTERNET; ADest: TStream;
      const ATotal: Int64; AProgress: TbpHttpProgressEvent;
      AToken: TbpCancellationToken);
  public
    constructor Create;
    destructor Destroy; override;

    function Execute(const AUrl: string; AMethod: TbpHttpMethod = hmGet;
      const AHeaders: string = ''; const ABody: AnsiString = ''): TbpHttpResponse;
    function Get(const AUrl: string; const AHeaders: string = ''): TbpHttpResponse;
    function Post(const AUrl: string; const ABody: AnsiString;
      const AHeaders: string = ''): TbpHttpResponse;
    function PostJson(const AUrl: string; const AJson: AnsiString): TbpHttpResponse;
    function Put(const AUrl: string; const ABody: AnsiString;
      const AHeaders: string = ''): TbpHttpResponse;
    function Delete(const AUrl: string; const AHeaders: string = ''): TbpHttpResponse;
    class function FetchUrl(const AUrl: string; const AHeaders: string = ''): AnsiString;

    // streams the response body to ADest in constant memory; the returned
    // record carries status/headers with an empty Body. The body is written
    // to ADest whatever the status code, so check BpHttpResponseIsSuccess.
    // Cancellation (token or ACancel in the progress callback) raises
    // EbpHttpClientCancelled; ADest keeps whatever arrived before the abort.
    // Resume/Range: pass e.g. 'Range: bytes=1024-' in AHeaders and expect 206.
    function Download(const AUrl: string; ADest: TStream;
      AProgress: TbpHttpProgressEvent = nil; AToken: TbpCancellationToken = nil;
      const AHeaders: string = ''; const AMethod: string = 'GET'): TbpHttpResponse;
    // Download convenience that manages the file itself: the file only
    // survives when the download completed with a 2xx status; on any error,
    // cancel or non-success status the partial file is deleted
    function DownloadToFile(const AUrl, AFileName: string;
      AProgress: TbpHttpProgressEvent = nil; AToken: TbpCancellationToken = nil;
      const AHeaders: string = ''): TbpHttpResponse;

    // persistent headers sent with every request; setting a name again replaces it
    procedure AddHeader(const AName, AValue: string);
    procedure ClearHeaders;
    // preemptive Basic auth header via Base64; clears BearerToken
    procedure SetBasicAuth(const AUser, APassword: AnsiString);

    // exposed for testing; also useful on their own
    function ParseUrl(const AUrl: string; out AServerName, AResource: string;
      out APort: Integer; out ASecure: Boolean): Boolean;
    function BuildHeaders(const ARequestHeaders: string): string;
    class function MethodToString(AMethod: TbpHttpMethod): string;

    property UserAgent: string read FUserAgent write FUserAgent;
    property Username: AnsiString read FUsername write FUsername;
    property Password: AnsiString read FPassword write FPassword;
    // sent as 'Authorization: Bearer <token>' when not empty
    property BearerToken: string read FBearerToken write FBearerToken;
    property ConnectTimeout: DWORD read FConnectTimeout write FConnectTimeout;
    property SendTimeout: DWORD read FSendTimeout write FSendTimeout;
    property ReceiveTimeout: DWORD read FReceiveTimeout write FReceiveTimeout;
    property FollowRedirects: Boolean read FFollowRedirects write FFollowRedirects;
  end;

function BpHttpResponseIsSuccess(const AResponse: TbpHttpResponse): Boolean;
// decodes the body as UTF-8 (invalid input yields an empty string)
function BpHttpResponseBodyAsUtf8(const AResponse: TbpHttpResponse): WideString;
// value of a header line from a raw CRLF header block, '' when absent
function BpHttpHeaderValue(const AHeaders, AName: string): string;
// Content-Length parsed from a raw header block; -1 when absent or invalid
function BpHttpContentLength(const AHeaders: string): Int64;
// whole percent 0..100 for a progress pair; -1 when the total is unknown
function BpHttpProgressPercent(const AReceived, ATotal: Int64): Integer;
// user-facing categorization; pass 0 for the dimension that does not apply
function BpClassifyHttpError(AWinInetError: DWORD; AHttpStatus: Integer): string;

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

// registered with a TbpCancellationToken so Cancel aborts a blocked WinInet
// call by closing its request handle (fails over with error 12017)
procedure BpCloseInetHandleCleanup(AData: Pointer);
begin
  InternetCloseHandle(HINTERNET(AData));
end;

procedure RaiseDownloadCancelled;
begin
  raise EbpHttpClientCancelled.Create('Operation cancelled', 0,
    gcErrOperationCancelled);
end;

// appends a header line with a CRLF separator between lines
procedure AppendHeaderLine(var AHeaders: string; const ALine: string);
begin
  if ALine = '' then
    Exit;
  if AHeaders <> '' then
    AHeaders := AHeaders + #13#10;
  AHeaders := AHeaders + ALine;
end;

{ EbpHttpClient }

constructor EbpHttpClient.Create(const AMessage: string; AStatusCode: Integer;
  AWinInetError: DWORD);
begin
  inherited Create(AMessage);
  FStatusCode := AStatusCode;
  FWinInetError := AWinInetError;
end;

{ TbpHttpResponse helpers }

function BpHttpResponseIsSuccess(const AResponse: TbpHttpResponse): Boolean;
begin
  Result := (AResponse.StatusCode >= 200) and (AResponse.StatusCode < 300);
end;

function BpHttpResponseBodyAsUtf8(const AResponse: TbpHttpResponse): WideString;
var
  lvLen: Integer;
begin
  Result := '';
  if AResponse.Body = '' then
    Exit;
  // convert straight from the raw bytes so no ANSI codepage round trip happens
  lvLen := MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(AResponse.Body),
    Length(AResponse.Body), nil, 0);
  if lvLen = 0 then
    Exit;
  SetLength(Result, lvLen);
  MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(AResponse.Body),
    Length(AResponse.Body), PWideChar(Result), lvLen);
end;

function BpHttpHeaderValue(const AHeaders, AName: string): string;
var
  lvLines: TStringList;
  lvLine, lvPrefix: string;
  i, lvColon: Integer;
begin
  Result := '';
  lvPrefix := LowerCase(AName);
  lvLines := TStringList.Create;
  try
    lvLines.Text := AHeaders;
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

function BpHttpContentLength(const AHeaders: string): Int64;
var
  lvValue: string;
begin
  Result := -1;
  lvValue := BpHttpHeaderValue(AHeaders, 'Content-Length');
  if lvValue = '' then
    Exit;
  Result := StrToInt64Def(lvValue, -1);
  if Result < 0 then
    Result := -1;
end;

function BpHttpProgressPercent(const AReceived, ATotal: Int64): Integer;
begin
  if ATotal <= 0 then
    Result := -1
  else if AReceived <= 0 then
    Result := 0
  else if AReceived >= ATotal then
    Result := 100
  else
    Result := (AReceived * 100) div ATotal;
end;

function BpClassifyHttpError(AWinInetError: DWORD; AHttpStatus: Integer): string;
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
  if AWinInetError <> 0 then
  begin
    case AWinInetError of
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

  case AHttpStatus of
    401: Result := 'Authentication failed (invalid credentials or token?)';
    403: Result := 'Access denied (missing permission or scope?)';
    404: Result := 'Endpoint not found (check URL)';
    429: Result := 'Rate limited by server';
  else
    if (AHttpStatus >= 500) and (AHttpStatus <= 599) then
      Result := 'Server error'
    else if AHttpStatus > 0 then
      Result := Format('HTTP error %d', [AHttpStatus])
    else
      Result := 'Unknown error';
  end;
end;

{ TbpHttpClient }

constructor TbpHttpClient.Create;
begin
  inherited Create;
  FUserAgent := gcDefaultUserAgent;
  FConnectTimeout := gcDefaultTimeout;
  FSendTimeout := gcDefaultTimeout;
  FReceiveTimeout := gcDefaultTimeout;
  FFollowRedirects := True;
  FHeaders := TStringList.Create;
end;

destructor TbpHttpClient.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

procedure TbpHttpClient.AddHeader(const AName, AValue: string);
begin
  FHeaders.Values[AName] := AValue;
end;

procedure TbpHttpClient.ClearHeaders;
begin
  FHeaders.Clear;
end;

procedure TbpHttpClient.SetBasicAuth(const AUser, APassword: AnsiString);
begin
  FBearerToken := '';
  AddHeader('Authorization', 'Basic ' + Base64Encode(AUser + ':' + APassword));
end;

class function TbpHttpClient.MethodToString(AMethod: TbpHttpMethod): string;
begin
  case AMethod of
    hmGet: Result := 'GET';
    hmPost: Result := 'POST';
    hmPut: Result := 'PUT';
    hmDelete: Result := 'DELETE';
  else
    Result := 'GET';
  end;
end;

function TbpHttpClient.GetWinInetErrorMessage(AErrorCode: DWORD): string;
var
  lvBuffer: array[0..1023] of Char;
  lvLen: DWORD;
begin
  lvLen := FormatMessage(
    FORMAT_MESSAGE_FROM_HMODULE or FORMAT_MESSAGE_FROM_SYSTEM,
    Pointer(GetModuleHandle('wininet.dll')),
    AErrorCode,
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
    Result := Format('WinInet error %d', [AErrorCode]);
end;

function TbpHttpClient.ParseUrl(const AUrl: string; out AServerName,
  AResource: string; out APort: Integer; out ASecure: Boolean): Boolean;
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

  if not InternetCrackUrl(PChar(AUrl), Length(AUrl), 0, lvComponents) then
    Exit;

  AServerName := lvComponents.lpszHostName;
  // keep the query string attached to the resource
  AResource := string(lvComponents.lpszUrlPath) + string(lvComponents.lpszExtraInfo);
  if AResource = '' then
    AResource := '/';

  APort := lvComponents.nPort;
  ASecure := lvComponents.nScheme = INTERNET_SCHEME_HTTPS;

  if APort = 0 then
  begin
    if ASecure then
      APort := INTERNET_DEFAULT_HTTPS_PORT
    else
      APort := INTERNET_DEFAULT_HTTP_PORT;
  end;

  Result := True;
end;

function TbpHttpClient.BuildHeaders(const ARequestHeaders: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to FHeaders.Count - 1 do
    AppendHeaderLine(Result, FHeaders.Names[i] + ': ' + FHeaders.ValueFromIndex[i]);
  if FBearerToken <> '' then
    AppendHeaderLine(Result, 'Authorization: Bearer ' + FBearerToken);
  AppendHeaderLine(Result, Trim(ARequestHeaders));
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

function TbpHttpClient.CreateConnection(ASession: HINTERNET;
  const AServerName: string; APort: Integer): HINTERNET;
var
  lvErr: DWORD;
begin
  Result := InternetConnect(
    ASession,
    PChar(AServerName),
    APort,
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
        [AServerName, APort, GetWinInetErrorMessage(lvErr)]),
      0, lvErr);
  end;
end;

function TbpHttpClient.CreateRequest(AConnection: HINTERNET;
  const AMethod, AResource: string; ASecure: Boolean): HINTERNET;
var
  lvFlags, lvErr: DWORD;
begin
  lvFlags := INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE;

  if ASecure then
    lvFlags := lvFlags or INTERNET_FLAG_SECURE;

  if not FFollowRedirects then
    lvFlags := lvFlags or INTERNET_FLAG_NO_AUTO_REDIRECT;

  Result := HttpOpenRequest(
    AConnection,
    PChar(AMethod),
    PChar(AResource),
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
        [AResource, GetWinInetErrorMessage(lvErr)]),
      0, lvErr);
  end;
end;

procedure TbpHttpClient.ApplyTimeouts(AHandle: HINTERNET);
begin
  if FConnectTimeout > 0 then
    InternetSetOption(AHandle, INTERNET_OPTION_CONNECT_TIMEOUT,
      @FConnectTimeout, SizeOf(FConnectTimeout));

  if FSendTimeout > 0 then
    InternetSetOption(AHandle, INTERNET_OPTION_SEND_TIMEOUT,
      @FSendTimeout, SizeOf(FSendTimeout));

  if FReceiveTimeout > 0 then
    InternetSetOption(AHandle, INTERNET_OPTION_RECEIVE_TIMEOUT,
      @FReceiveTimeout, SizeOf(FReceiveTimeout));
end;

procedure TbpHttpClient.ApplyAuthentication(ARequest: HINTERNET);
begin
  // WinInet-level credentials, also used for proxy and 401 challenges
  if FUsername <> '' then
    InternetSetOption(ARequest, INTERNET_OPTION_USERNAME,
      @FUsername[1], Length(FUsername));

  if FPassword <> '' then
    InternetSetOption(ARequest, INTERNET_OPTION_PASSWORD,
      @FPassword[1], Length(FPassword));
end;

procedure TbpHttpClient.SendHttpRequest(ARequest: HINTERNET;
  const AHeaders: string; const ABody: AnsiString);
var
  lvHeadersPtr: PChar;
  lvHeadersLen: DWORD;
  lvBodyPtr: Pointer;
  lvBodyLen, lvErr: DWORD;
begin
  if AHeaders <> '' then
  begin
    lvHeadersPtr := PChar(AHeaders);
    lvHeadersLen := Length(AHeaders);
  end
  else
  begin
    lvHeadersPtr := nil;
    lvHeadersLen := 0;
  end;

  if Length(ABody) > 0 then
  begin
    lvBodyPtr := @ABody[1];
    lvBodyLen := Length(ABody);
  end
  else
  begin
    lvBodyPtr := nil;
    lvBodyLen := 0;
  end;

  if not HttpSendRequest(ARequest, lvHeadersPtr, lvHeadersLen,
    lvBodyPtr, lvBodyLen) then
  begin
    lvErr := GetLastError;
    raise EbpHttpClient.Create(
      'Failed to send HTTP request: ' + GetWinInetErrorMessage(lvErr),
      0, lvErr);
  end;
end;

function TbpHttpClient.ReadResponseStatus(ARequest: HINTERNET): Integer;
var
  lvStatusCode, lvBufferLen, lvReserved, lvErr: DWORD;
begin
  lvBufferLen := SizeOf(lvStatusCode);
  lvReserved := 0;

  if not HttpQueryInfo(
    ARequest,
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

function TbpHttpClient.ReadResponseHeaders(ARequest: HINTERNET): string;
var
  lvSize, lvReserved: DWORD;
begin
  Result := '';
  lvSize := 0;
  lvReserved := 0;

  // first call just reports the required buffer size
  if HttpQueryInfo(ARequest, HTTP_QUERY_RAW_HEADERS_CRLF, nil, lvSize, lvReserved) then
    Exit;
  if GetLastError <> ERROR_INSUFFICIENT_BUFFER then
    Exit;

  SetLength(Result, lvSize div SizeOf(Char));
  if HttpQueryInfo(ARequest, HTTP_QUERY_RAW_HEADERS_CRLF, PChar(Result),
    lvSize, lvReserved) then
    SetLength(Result, lvSize div SizeOf(Char))
  else
    Result := '';
end;

function TbpHttpClient.ReadResponseBody(ARequest: HINTERNET): AnsiString;
var
  lvBuffer: array[0..gcBufferSize - 1] of Byte;
  lvBytesRead, lvErr: DWORD;
  lvStream: TMemoryStream;
begin
  lvStream := TMemoryStream.Create;
  try
    repeat
      if not InternetReadFile(ARequest, @lvBuffer[0], gcBufferSize, lvBytesRead) then
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

procedure TbpHttpClient.ReadBodyToStream(ARequest: HINTERNET; ADest: TStream;
  const ATotal: Int64; AProgress: TbpHttpProgressEvent;
  AToken: TbpCancellationToken);
var
  lvBuffer: array[0..gcDownloadBufferSize - 1] of Byte;
  lvBytesRead, lvErr: DWORD;
  lvReceived: Int64;
  lvCancel: Boolean;
begin
  lvReceived := 0;
  if Assigned(AProgress) then
  begin
    // headers are in; announce the total before the first byte
    lvCancel := False;
    AProgress(Self, 0, ATotal, lvCancel);
    if lvCancel then
      RaiseDownloadCancelled;
  end;

  repeat
    if (AToken <> nil) and AToken.IsCancellationRequested then
      RaiseDownloadCancelled;

    if not InternetReadFile(ARequest, @lvBuffer[0], gcDownloadBufferSize,
      lvBytesRead) then
    begin
      lvErr := GetLastError;
      raise EbpHttpClient.Create(
        'Failed to read HTTP response: ' + GetWinInetErrorMessage(lvErr),
        0, lvErr);
    end;

    if lvBytesRead > 0 then
    begin
      ADest.WriteBuffer(lvBuffer[0], lvBytesRead);
      Inc(lvReceived, lvBytesRead);
      if Assigned(AProgress) then
      begin
        lvCancel := False;
        AProgress(Self, lvReceived, ATotal, lvCancel);
        if lvCancel then
          RaiseDownloadCancelled;
      end;
    end;
  until lvBytesRead = 0;
end;

function TbpHttpClient.Download(const AUrl: string; ADest: TStream;
  AProgress: TbpHttpProgressEvent; AToken: TbpCancellationToken;
  const AHeaders: string; const AMethod: string): TbpHttpResponse;
var
  lvSession, lvConnection, lvRequest: HINTERNET;
  lvServerName, lvResource: string;
  lvPort: Integer;
  lvSecure, lvOwnsRequest: Boolean;
  lvCleanupId: Integer;
begin
  if ADest = nil then
    raise EbpHttpClient.Create('Download destination stream is nil');
  if (AToken <> nil) and AToken.IsCancellationRequested then
    RaiseDownloadCancelled;
  if not ParseUrl(AUrl, lvServerName, lvResource, lvPort, lvSecure) then
    raise EbpHttpClient.Create('Invalid URL: ' + AUrl);

  lvSession := CreateSession;
  try
    lvConnection := CreateConnection(lvSession, lvServerName, lvPort);
    try
      lvRequest := CreateRequest(lvConnection, AMethod, lvResource, lvSecure);
      // hand the request handle to the token: Cancel closes it, which makes
      // a blocked connect/read fail over immediately with error 12017
      lvOwnsRequest := True;
      lvCleanupId := 0;
      if AToken <> nil then
        if not AToken.RegisterCleanup(BpCloseInetHandleCleanup, lvRequest,
          lvCleanupId) then
        begin
          // cancelled between the check above and here
          InternetCloseHandle(lvRequest);
          RaiseDownloadCancelled;
        end;
      try
        try
          ApplyAuthentication(lvRequest);
          SendHttpRequest(lvRequest, BuildHeaders(AHeaders), '');

          Result.StatusCode := ReadResponseStatus(lvRequest);
          Result.Headers := ReadResponseHeaders(lvRequest);
          Result.StatusText := Format('HTTP %d', [Result.StatusCode]);
          Result.Body := '';
          Result.ContentLength := BpHttpContentLength(Result.Headers);

          ReadBodyToStream(lvRequest, ADest, Result.ContentLength, AProgress,
            AToken);
        except
          // a WinInet failure caused by Cancel closing the handle surfaces
          // as the typed cancellation, not as a generic network error
          on E: EbpHttpClient do
            if (AToken <> nil) and AToken.IsCancellationRequested and
              not (E is EbpHttpClientCancelled) then
              RaiseDownloadCancelled
            else
              raise;
        end;
      finally
        if AToken <> nil then
          lvOwnsRequest := AToken.UnregisterCleanup(lvCleanupId);
        if lvOwnsRequest then
          InternetCloseHandle(lvRequest);
      end;
    finally
      InternetCloseHandle(lvConnection);
    end;
  finally
    InternetCloseHandle(lvSession);
  end;
end;

function TbpHttpClient.DownloadToFile(const AUrl, AFileName: string;
  AProgress: TbpHttpProgressEvent; AToken: TbpCancellationToken;
  const AHeaders: string): TbpHttpResponse;
var
  lvFile: TFileStream;
  lvKeep: Boolean;
begin
  lvKeep := False;
  lvFile := TFileStream.Create(AFileName, fmCreate);
  try
    Result := Download(AUrl, lvFile, AProgress, AToken, AHeaders);
    lvKeep := BpHttpResponseIsSuccess(Result);
  finally
    lvFile.Free;
    // never leave a partial or error-page file behind
    if not lvKeep then
      SysUtils.DeleteFile(AFileName);
  end;
end;

function TbpHttpClient.Execute(const AUrl: string; AMethod: TbpHttpMethod;
  const AHeaders: string; const ABody: AnsiString): TbpHttpResponse;
var
  lvSession, lvConnection, lvRequest: HINTERNET;
  lvServerName, lvResource: string;
  lvPort: Integer;
  lvSecure: Boolean;
begin
  if not ParseUrl(AUrl, lvServerName, lvResource, lvPort, lvSecure) then
    raise EbpHttpClient.Create('Invalid URL: ' + AUrl);

  lvSession := CreateSession;
  try
    lvConnection := CreateConnection(lvSession, lvServerName, lvPort);
    try
      lvRequest := CreateRequest(lvConnection, MethodToString(AMethod),
        lvResource, lvSecure);
      try
        ApplyAuthentication(lvRequest);
        SendHttpRequest(lvRequest, BuildHeaders(AHeaders), ABody);

        Result.StatusCode := ReadResponseStatus(lvRequest);
        Result.Headers := ReadResponseHeaders(lvRequest);
        Result.ContentLength := BpHttpContentLength(Result.Headers);
        Result.Body := ReadResponseBody(lvRequest);
        Result.StatusText := Format('HTTP %d', [Result.StatusCode]);
      finally
        InternetCloseHandle(lvRequest);
      end;
    finally
      InternetCloseHandle(lvConnection);
    end;
  finally
    InternetCloseHandle(lvSession);
  end;
end;

function TbpHttpClient.Get(const AUrl: string;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmGet, AHeaders, '');
end;

function TbpHttpClient.Post(const AUrl: string; const ABody: AnsiString;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmPost, AHeaders, ABody);
end;

function TbpHttpClient.PostJson(const AUrl: string;
  const AJson: AnsiString): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmPost, 'Content-Type: application/json', AJson);
end;

function TbpHttpClient.Put(const AUrl: string; const ABody: AnsiString;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmPut, AHeaders, ABody);
end;

function TbpHttpClient.Delete(const AUrl: string;
  const AHeaders: string): TbpHttpResponse;
begin
  Result := Execute(AUrl, hmDelete, AHeaders, '');
end;

class function TbpHttpClient.FetchUrl(const AUrl: string;
  const AHeaders: string): AnsiString;
var
  lvClient: TbpHttpClient;
  lvResponse: TbpHttpResponse;
begin
  lvClient := TbpHttpClient.Create;
  try
    lvResponse := lvClient.Get(AUrl, AHeaders);
    Result := lvResponse.Body;
  finally
    lvClient.Free;
  end;
end;

end.
