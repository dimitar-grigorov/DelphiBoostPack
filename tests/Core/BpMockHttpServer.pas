unit BpMockHttpServer;

// Scriptable loopback HTTP server for the suite, modelled on okhttp's
// MockWebServer: a FIFO of canned responses, a log of what the client really
// sent, and deliberate socket misbehaviour to drive the failure paths. It
// binds 127.0.0.1 on an ephemeral port, so no firewall prompt and no clash
// between two runs. The server owns every response it is handed and every
// request it records, which keeps the call sites free of try/finally.

interface

uses
  SysUtils, Classes, Windows, WinSock;

type
  // what the connection does once the scripted response is on the wire
  TbpMockSocketEffect = (
    mseNone,        // keep-alive: read the next request on the same socket
    mseCloseAtEnd,  // close after the response, a short body included
    mseNoResponse,  // record the request, send nothing, close
    mseStall);      // send the response, then hold the socket and go quiet

  // one canned reply; Enqueue hands it to the server, which frees it
  TbpMockResponse = class
  private
    FHeaders: TStringList;
  public
    StatusCode: Integer;
    ReasonPhrase: string;
    Body: AnsiString;
    Chunked: Boolean;        // send chunked, which also omits Content-Length
    ChunkSize: Integer;      // bytes per chunk, 0 puts the body in one chunk
    ClaimedLength: Integer;  // see the gcMock*Length sentinels
    Effect: TbpMockSocketEffect;
    constructor Create(aStatusCode: Integer = 200);
    destructor Destroy; override;
    // extra response lines, written verbatim: Add('Location: /next')
    property Headers: TStringList read FHeaders;
  end;

  // what one request looked like on the wire; owned by the server
  TbpRecordedRequest = class
  private
    FHeaders: string;
    procedure ParseHead(const aHead: AnsiString);
  public
    Method: string;
    Path: string;
    HttpVersion: string;
    RequestLine: string;
    RawHead: AnsiString;     // exact bytes up to and including the blank line
    Body: AnsiString;
    ConnectionId: Integer;   // equal ids mean the requests shared a socket
    function HeaderValue(const aName: string): string;
    function HasHeader(const aName: string): Boolean;
    function HeaderCount(const aName: string): Integer;
    // the header block as sent, CRLF separated, without the closing blank line
    property Headers: string read FHeaders;
  end;

  TbpMockHttpServer = class
  private
    FListenSocket: TSocket;
    FPort: Integer;
    FLock: TRTLCriticalSection;
    FArrived: THandle;       // one release per recorded request
    FAcceptor: TThread;
    FConnections: TList;     // TThread, owned, joined by Shutdown
    FRequests: TList;        // TbpRecordedRequest, owned, kept for the test
    FResponses: TList;       // TbpMockResponse, owned
    FTakeIndex: Integer;     // TakeRequest cursor into FRequests
    FServeIndex: Integer;    // dispatch cursor into FResponses
    FRequestCount: Integer;
    FConnectionCount: Integer;
    FShutdown: Boolean;
    procedure Lock;
    procedure Unlock;
    procedure AddConnection(aSocket: TSocket);
    procedure PublishRequest(aRequest: TbpRecordedRequest);
    function NextResponse: TbpMockResponse;
    function GetRequestCount: Integer;
    function GetConnectionCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(aResponse: TbpMockResponse);
    // borrowed, alive until the server dies; nil when nothing arrived in time
    function TakeRequest(aTimeoutMs: DWORD = 5000): TbpRecordedRequest;
    function Url(const aPath: string): string;
    procedure Shutdown;
    property Port: Integer read FPort;
    property RequestCount: Integer read GetRequestCount;
    property ConnectionCount: Integer read GetConnectionCount;
  end;

const
  gcMockRealLength = -1;       // ClaimedLength: frame the body honestly
  gcMockNoContentLength = -2;  // ClaimedLength: emit no framing header at all

// the common replies; every one of them is owned by the server after Enqueue
function BpMockOk(const aBody: AnsiString): TbpMockResponse;
function BpMockStatus(aStatus: Integer;
  const aBody: AnsiString = ''): TbpMockResponse;
function BpMockRedirect(aStatus: Integer;
  const aLocation: string): TbpMockResponse;
function BpMockChunked(const aBody: AnsiString;
  aChunkSize: Integer = 0): TbpMockResponse;

implementation

const
  gcHeadEnd = #13#10#13#10;
  gcReadBuffer = 8192;
  gcSocketTimeoutMs = 10000;  // no blocking socket call may outlive this
  gcStallLimitMs = 30000;     // a forgotten stall must not outlive the test
  // an empty queue is a broken test rather than a scenario, so say so loudly
  gcNoScriptReply: AnsiString =
    'HTTP/1.1 503 Service Unavailable'#13#10 +
    'Content-Length: 32'#13#10#13#10 +
    'BpMockHttpServer: queue is empty';

type
  // one accepted socket, served start to finish on its own thread
  TbpMockConnection = class(TThread)
  private
    FServer: TbpMockHttpServer;
    FSocket: TSocket;
    FId: Integer;
    FInBuf: AnsiString;  // received but not yet consumed
    function Fill: Boolean;
    function ReadBytes(aCount: Integer; out aData: AnsiString): Boolean;
    function ReadRequest: TbpRecordedRequest;
    function SendAll(const aData: AnsiString): Boolean;
    function WriteResponse(aResponse: TbpMockResponse): Boolean;
    procedure Stall;
    procedure CloseOnce;
  protected
    procedure Execute; override;
  public
    constructor Create(aServer: TbpMockHttpServer; aSocket: TSocket; aId: Integer);
    procedure Unblock;
  end;

  TbpMockAcceptor = class(TThread)
  private
    FServer: TbpMockHttpServer;
  protected
    procedure Execute; override;
  public
    constructor Create(aServer: TbpMockHttpServer);
  end;

function MockReason(aStatus: Integer): string;
begin
  case aStatus of
    200: Result := 'OK';
    201: Result := 'Created';
    204: Result := 'No Content';
    301: Result := 'Moved Permanently';
    302: Result := 'Found';
    303: Result := 'See Other';
    304: Result := 'Not Modified';
    307: Result := 'Temporary Redirect';
    308: Result := 'Permanent Redirect';
    400: Result := 'Bad Request';
    401: Result := 'Unauthorized';
    403: Result := 'Forbidden';
    404: Result := 'Not Found';
    500: Result := 'Internal Server Error';
  else
    Result := 'Status';
  end;
end;

// deliberately not BpHttpHeaderValue: a server that reused the parser under
// test could not prove the client actually wrote the header correctly
function MockHeaderScan(const aHeaders, aName: string;
  out aValue: string): Integer;
var
  lvPos, lvEnd, lvColon, lvLen: Integer;
  lvLine: string;
begin
  Result := 0;
  aValue := '';
  lvLen := Length(aHeaders);
  lvPos := 1;
  while lvPos <= lvLen do
  begin
    lvEnd := lvPos;
    while (lvEnd <= lvLen) and (aHeaders[lvEnd] <> #13) and
      (aHeaders[lvEnd] <> #10) do
      Inc(lvEnd);
    lvLine := Copy(aHeaders, lvPos, lvEnd - lvPos);
    lvPos := lvEnd + 1;
    if (lvPos <= lvLen) and (aHeaders[lvEnd] = #13) and
      (aHeaders[lvPos] = #10) then
      Inc(lvPos);
    lvColon := Pos(':', lvLine);
    if (lvColon > 0) and SameText(Trim(Copy(lvLine, 1, lvColon - 1)), aName) then
    begin
      if Result = 0 then
        aValue := Trim(Copy(lvLine, lvColon + 1, MaxInt));
      Inc(Result);
    end;
  end;
end;

function ChunkEncode(const aBody: AnsiString; aChunkSize: Integer): AnsiString;
var
  lvPos, lvCount: Integer;
begin
  Result := '';
  if aChunkSize <= 0 then
    aChunkSize := MaxInt;
  lvPos := 1;
  while lvPos <= Length(aBody) do
  begin
    lvCount := Length(aBody) - lvPos + 1;
    if lvCount > aChunkSize then
      lvCount := aChunkSize;
    Result := Result + AnsiString(IntToHex(lvCount, 1)) + #13#10 +
      Copy(aBody, lvPos, lvCount) + #13#10;
    Inc(lvPos, lvCount);
  end;
  Result := Result + '0' + gcHeadEnd;
end;

{ TbpMockResponse }

constructor TbpMockResponse.Create(aStatusCode: Integer);
begin
  inherited Create;
  FHeaders := TStringList.Create;
  StatusCode := aStatusCode;
  ReasonPhrase := MockReason(aStatusCode);
  ClaimedLength := gcMockRealLength;
end;

destructor TbpMockResponse.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

{ TbpRecordedRequest }

procedure TbpRecordedRequest.ParseHead(const aHead: AnsiString);
var
  lvHead, lvRest: string;
  lvLineEnd, lvSpace: Integer;
begin
  RawHead := aHead;
  lvHead := string(aHead);
  lvLineEnd := Pos(#13#10, lvHead);
  if lvLineEnd = 0 then
    lvLineEnd := Length(lvHead) + 1;
  RequestLine := Copy(lvHead, 1, lvLineEnd - 1);
  FHeaders := Copy(lvHead, lvLineEnd + 2, MaxInt);
  // the closing blank line frames the head, it is not a header
  while (FHeaders <> '') and ((FHeaders[Length(FHeaders)] = #13) or
    (FHeaders[Length(FHeaders)] = #10)) do
    SetLength(FHeaders, Length(FHeaders) - 1);

  lvSpace := Pos(' ', RequestLine);
  if lvSpace = 0 then
  begin
    Method := RequestLine;
    Exit;
  end;
  Method := Copy(RequestLine, 1, lvSpace - 1);
  lvRest := Copy(RequestLine, lvSpace + 1, MaxInt);
  lvSpace := Pos(' ', lvRest);
  if lvSpace = 0 then
    Path := lvRest
  else
  begin
    Path := Copy(lvRest, 1, lvSpace - 1);
    HttpVersion := Copy(lvRest, lvSpace + 1, MaxInt);
  end;
end;

function TbpRecordedRequest.HeaderValue(const aName: string): string;
begin
  MockHeaderScan(FHeaders, aName, Result);
end;

function TbpRecordedRequest.HasHeader(const aName: string): Boolean;
var
  lvValue: string;
begin
  Result := MockHeaderScan(FHeaders, aName, lvValue) > 0;
end;

function TbpRecordedRequest.HeaderCount(const aName: string): Integer;
var
  lvValue: string;
begin
  Result := MockHeaderScan(FHeaders, aName, lvValue);
end;

{ TbpMockConnection }

constructor TbpMockConnection.Create(aServer: TbpMockHttpServer;
  aSocket: TSocket; aId: Integer);
var
  lvTimeout: Integer;
begin
  FServer := aServer;
  FSocket := aSocket;
  FId := aId;
  lvTimeout := gcSocketTimeoutMs;
  setsockopt(FSocket, SOL_SOCKET, SO_RCVTIMEO, PChar(@lvTimeout), SizeOf(lvTimeout));
  setsockopt(FSocket, SOL_SOCKET, SO_SNDTIMEO, PChar(@lvTimeout), SizeOf(lvTimeout));
  FreeOnTerminate := False;
  inherited Create(False);
end;

// closesocket is the only call that reliably ends a blocked recv on Windows,
// and WinInet pools a keep-alive socket well past the handle that opened it,
// so waiting for the peer would cost every test the full receive timeout
procedure TbpMockConnection.CloseOnce;
begin
  FServer.Lock;
  try
    if FSocket <> INVALID_SOCKET then
    begin
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
    end;
  finally
    FServer.Unlock;
  end;
end;

procedure TbpMockConnection.Unblock;
begin
  Terminate;
  CloseOnce;
end;

function TbpMockConnection.Fill: Boolean;
var
  lvBuffer: array[0..gcReadBuffer - 1] of AnsiChar;
  lvCount, lvLen: Integer;
begin
  lvCount := recv(FSocket, lvBuffer[0], SizeOf(lvBuffer), 0);
  Result := lvCount > 0;
  if not Result then
    Exit;
  lvLen := Length(FInBuf);
  SetLength(FInBuf, lvLen + lvCount);
  Move(lvBuffer[0], FInBuf[lvLen + 1], lvCount);
end;

function TbpMockConnection.ReadBytes(aCount: Integer;
  out aData: AnsiString): Boolean;
begin
  Result := True;
  while Length(FInBuf) < aCount do
    if not Fill then
    begin
      Result := False;
      aCount := Length(FInBuf);
      Break;
    end;
  aData := Copy(FInBuf, 1, aCount);
  Delete(FInBuf, 1, aCount);
end;

// nil when the peer closed or timed out before a whole head arrived
function TbpMockConnection.ReadRequest: TbpRecordedRequest;
var
  lvSplit, lvLength: Integer;
  lvValue: string;
begin
  Result := nil;
  lvSplit := Pos(gcHeadEnd, FInBuf);
  while lvSplit = 0 do
  begin
    if Terminated or not Fill then
      Exit;
    lvSplit := Pos(gcHeadEnd, FInBuf);
  end;

  Result := TbpRecordedRequest.Create;
  Result.ParseHead(Copy(FInBuf, 1, lvSplit + 3));
  Result.ConnectionId := FId;
  Delete(FInBuf, 1, lvSplit + 3);

  // this client never chunks a request, so no chunked decoder here; one would
  // desync the connection and fail the test rather than pass it quietly
  if MockHeaderScan(Result.Headers, 'Content-Length', lvValue) > 0 then
  begin
    lvLength := StrToIntDef(lvValue, 0);
    if lvLength > 0 then
      ReadBytes(lvLength, Result.Body);
  end;
end;

function TbpMockConnection.SendAll(const aData: AnsiString): Boolean;
var
  lvSent, lvCount: Integer;
begin
  lvSent := 0;
  while lvSent < Length(aData) do
  begin
    lvCount := send(FSocket, (PAnsiChar(aData) + lvSent)^,
      Length(aData) - lvSent, 0);
    if lvCount <= 0 then
      Break;
    Inc(lvSent, lvCount);
  end;
  Result := lvSent = Length(aData);
end;

procedure TbpMockConnection.Stall;
var
  lvStart: Cardinal;
begin
  lvStart := GetTickCount;
  // the unsigned difference survives the 49 day tick wrap
  while not Terminated and (GetTickCount - lvStart < gcStallLimitMs) do
    Sleep(20);
end;

function TbpMockConnection.WriteResponse(aResponse: TbpMockResponse): Boolean;
var
  lvHead, lvBody: AnsiString;
  i: Integer;
begin
  if aResponse.Effect = mseNoResponse then
  begin
    Result := False;
    Exit;
  end;

  lvHead := AnsiString(Format('HTTP/1.1 %d %s',
    [aResponse.StatusCode, aResponse.ReasonPhrase])) + #13#10;
  for i := 0 to aResponse.Headers.Count - 1 do
    lvHead := lvHead + AnsiString(aResponse.Headers[i]) + #13#10;
  if aResponse.Chunked then
    lvHead := lvHead + 'Transfer-Encoding: chunked'#13#10
  else if aResponse.ClaimedLength >= 0 then
    lvHead := lvHead + AnsiString(Format('Content-Length: %d',
      [aResponse.ClaimedLength])) + #13#10
  else if aResponse.ClaimedLength = gcMockRealLength then
    lvHead := lvHead + AnsiString(Format('Content-Length: %d',
      [Length(aResponse.Body)])) + #13#10;
  lvHead := lvHead + #13#10;

  Result := SendAll(lvHead);
  if Result and (aResponse.Body <> '') then
  begin
    if aResponse.Chunked then
      lvBody := ChunkEncode(aResponse.Body, aResponse.ChunkSize)
    else
      lvBody := aResponse.Body;
    Result := SendAll(lvBody);
  end;

  if aResponse.Effect = mseStall then
    Stall;
end;

procedure TbpMockConnection.Execute;
var
  lvRequest: TbpRecordedRequest;
  lvResponse: TbpMockResponse;
begin
  try
    while not Terminated do
    begin
      lvRequest := ReadRequest;
      if lvRequest = nil then
        Break;
      FServer.PublishRequest(lvRequest);
      lvResponse := FServer.NextResponse;
      if lvResponse = nil then
      begin
        SendAll(gcNoScriptReply);
        Break;
      end;
      if not WriteResponse(lvResponse) then
        Break;
      if lvResponse.Effect <> mseNone then
        Break;
      if SameText(lvRequest.HeaderValue('Connection'), 'close') then
        Break;
    end;
  finally
    CloseOnce;
  end;
end;

{ TbpMockAcceptor }

constructor TbpMockAcceptor.Create(aServer: TbpMockHttpServer);
begin
  FServer := aServer;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TbpMockAcceptor.Execute;
var
  lvSocket: TSocket;
begin
  while not Terminated do
  begin
    lvSocket := accept(FServer.FListenSocket, nil, nil);
    if lvSocket = INVALID_SOCKET then
      Break;  // the listener was closed by Shutdown
    FServer.AddConnection(lvSocket);
  end;
end;

{ TbpMockHttpServer }

constructor TbpMockHttpServer.Create;
var
  lvWsaData: TWSAData;
  lvAddr: TSockAddrIn;
  lvAddrLen: Integer;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FConnections := TList.Create;
  FRequests := TList.Create;
  FResponses := TList.Create;
  FArrived := CreateSemaphore(nil, 0, MaxInt, nil);
  FListenSocket := INVALID_SOCKET;

  if WSAStartup($0202, lvWsaData) <> 0 then
    raise Exception.Create('BpMockHttpServer: WSAStartup failed');
  FListenSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FListenSocket = INVALID_SOCKET then
    raise Exception.Create('BpMockHttpServer: socket() failed');

  FillChar(lvAddr, SizeOf(lvAddr), 0);
  lvAddr.sin_family := AF_INET;
  lvAddr.sin_port := htons(0);  // ephemeral, so two runs cannot collide
  // loopback only: a wildcard bind raises a firewall prompt nobody can click
  lvAddr.sin_addr.S_addr := inet_addr('127.0.0.1');
  if bind(FListenSocket, TSockAddr(lvAddr), SizeOf(lvAddr)) <> 0 then
    raise Exception.Create('BpMockHttpServer: bind() failed');
  if listen(FListenSocket, SOMAXCONN) <> 0 then
    raise Exception.Create('BpMockHttpServer: listen() failed');
  lvAddrLen := SizeOf(lvAddr);
  if getsockname(FListenSocket, TSockAddr(lvAddr), lvAddrLen) <> 0 then
    raise Exception.Create('BpMockHttpServer: getsockname() failed');
  FPort := ntohs(lvAddr.sin_port);

  FAcceptor := TbpMockAcceptor.Create(Self);
end;

destructor TbpMockHttpServer.Destroy;
var
  i: Integer;
begin
  Shutdown;
  for i := 0 to FRequests.Count - 1 do
    TbpRecordedRequest(FRequests[i]).Free;
  for i := 0 to FResponses.Count - 1 do
    TbpMockResponse(FResponses[i]).Free;
  FRequests.Free;
  FResponses.Free;
  FConnections.Free;
  if FArrived <> 0 then
    CloseHandle(FArrived);
  DeleteCriticalSection(FLock);
  WSACleanup;
  inherited;
end;

procedure TbpMockHttpServer.Lock;
begin
  EnterCriticalSection(FLock);
end;

procedure TbpMockHttpServer.Unlock;
begin
  LeaveCriticalSection(FLock);
end;

// the acceptor thread is joined before the connections are, so no connection
// can appear after this has walked the list
procedure TbpMockHttpServer.Shutdown;
var
  i: Integer;
begin
  if FShutdown then
    Exit;
  FShutdown := True;

  if FListenSocket <> INVALID_SOCKET then
  begin
    closesocket(FListenSocket);  // unblocks the pending accept
    FListenSocket := INVALID_SOCKET;
  end;
  if FAcceptor <> nil then
  begin
    FAcceptor.Terminate;
    FAcceptor.WaitFor;
    FreeAndNil(FAcceptor);
  end;

  for i := 0 to FConnections.Count - 1 do
    TbpMockConnection(FConnections[i]).Unblock;
  for i := 0 to FConnections.Count - 1 do
    TbpMockConnection(FConnections[i]).Free;  // TThread.Destroy joins
  FConnections.Clear;
end;

procedure TbpMockHttpServer.AddConnection(aSocket: TSocket);
var
  lvId: Integer;
begin
  Lock;
  try
    Inc(FConnectionCount);
    lvId := FConnectionCount;
  finally
    Unlock;
  end;
  // created outside the lock: the thread body takes it on its very first read
  FConnections.Add(TbpMockConnection.Create(Self, aSocket, lvId));
end;

procedure TbpMockHttpServer.PublishRequest(aRequest: TbpRecordedRequest);
begin
  Lock;
  try
    FRequests.Add(aRequest);
    Inc(FRequestCount);
  finally
    Unlock;
  end;
  ReleaseSemaphore(FArrived, 1, nil);
end;

function TbpMockHttpServer.NextResponse: TbpMockResponse;
begin
  Result := nil;
  Lock;
  try
    if FServeIndex < FResponses.Count then
    begin
      Result := TbpMockResponse(FResponses[FServeIndex]);
      Inc(FServeIndex);
    end;
  finally
    Unlock;
  end;
end;

procedure TbpMockHttpServer.Enqueue(aResponse: TbpMockResponse);
begin
  Lock;
  try
    FResponses.Add(aResponse);
  finally
    Unlock;
  end;
end;

function TbpMockHttpServer.TakeRequest(aTimeoutMs: DWORD): TbpRecordedRequest;
begin
  Result := nil;
  if WaitForSingleObject(FArrived, aTimeoutMs) <> WAIT_OBJECT_0 then
    Exit;
  Lock;
  try
    if FTakeIndex < FRequests.Count then
    begin
      Result := TbpRecordedRequest(FRequests[FTakeIndex]);
      Inc(FTakeIndex);
    end;
  finally
    Unlock;
  end;
end;

function TbpMockHttpServer.Url(const aPath: string): string;
begin
  Result := Format('http://127.0.0.1:%d%s', [FPort, aPath]);
end;

function TbpMockHttpServer.GetRequestCount: Integer;
begin
  Lock;
  try
    Result := FRequestCount;
  finally
    Unlock;
  end;
end;

function TbpMockHttpServer.GetConnectionCount: Integer;
begin
  Lock;
  try
    Result := FConnectionCount;
  finally
    Unlock;
  end;
end;

{ response factories }

function BpMockOk(const aBody: AnsiString): TbpMockResponse;
begin
  Result := TbpMockResponse.Create(200);
  Result.Body := aBody;
end;

function BpMockStatus(aStatus: Integer;
  const aBody: AnsiString): TbpMockResponse;
begin
  Result := TbpMockResponse.Create(aStatus);
  Result.Body := aBody;
end;

function BpMockRedirect(aStatus: Integer;
  const aLocation: string): TbpMockResponse;
begin
  Result := TbpMockResponse.Create(aStatus);
  Result.Headers.Add('Location: ' + aLocation);
  Result.Body := 'redirecting';
end;

function BpMockChunked(const aBody: AnsiString;
  aChunkSize: Integer): TbpMockResponse;
begin
  Result := TbpMockResponse.Create(200);
  Result.Body := aBody;
  Result.Chunked := True;
  Result.ChunkSize := aChunkSize;
end;

end.
