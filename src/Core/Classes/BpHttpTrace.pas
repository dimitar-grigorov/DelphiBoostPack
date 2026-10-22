unit BpHttpTrace;

// An in-process 'ssh -v' for TbpHttpClient, one sink per client: each request gets an id, each step its time, and one summary line.
// Detach waits out a sink in flight by holding the lock across the call, so a sink that waits on the thread calling Detach (Synchronize, SendMessage) deadlocks it.

interface

uses
  Windows, BpHttpClient;

type
  // runs on the thread doing the I/O, one call at a time across all clients, so keep it quick
  TbpHttpTraceProc = procedure(aHandle: Pointer; const aLine: string);

  TbpHttpTrace = class
  public
    // one sink per client, a second Attach replaces it; False means WinInet refused it
    class function Attach(aClient: TbpHttpClient; aProc: TbpHttpTraceProc): Boolean;
    // returns only once no thread is inside the sink, so it is safe to free then
    class procedure Detach(aClient: TbpHttpClient);

    // '' for the statuses a wire trace skips
    class function StatusText(aStatus: DWORD; aInfo: Pointer;
      aInfoLen: DWORD): string;
    // drops user:password@ from a url
    class function SanitizeUrl(const aUrl: string): string;
  end;

implementation

uses
  SysUtils, Classes, WinInet, BpCompat;

// the unsuffixed name binds the wide entry point on Unicode compilers
function InternetSetStatusCallbackA(hInet: HINTERNET;
  lpfnInternetCallback: PFNInternetStatusCallback): PFNInternetStatusCallback;
  stdcall; external 'wininet.dll' name 'InternetSetStatusCallbackA';

const
  gcStatusDetectingProxy = 80;   // missing from D2007's WinInet.pas
  gcStatusCookieFirst    = 320;  // the cookie, P3P and privacy family
  gcStatusCookieLast     = 327;

type
  // one request handle between its first status and its close; times are counter ticks, 0 unseen
  TbpTraceRequest = record
    Handle: Pointer;
    Id: Integer;
    Start, Resolved, Connected, Sent, FirstByte: Int64;
    Received: Int64;
    Address: string;
    Failed: Boolean;
  end;
  PbpTraceRequest = ^TbpTraceRequest;

  TbpTraceSink = class
  private
    FContextId: Cardinal;
    FProc: TbpHttpTraceProc;
    FLastId: Integer;
    FRequests: array of TbpTraceRequest;
    function IndexOf(aHandle: Pointer): Integer;
    function Open(aHandle: Pointer): Integer;
    procedure Close(aIndex: Integer);
    procedure Emit(aHandle: Pointer; const aLine: string);
    function Summary(const aRequest: TbpTraceRequest; const aNow: Int64): string;
    procedure Status(aHandle: Pointer; aStatus: DWORD; aInfo: Pointer;
      aInfoLen: DWORD);
    procedure Failure(aRequest: Pointer; const aMessage: string);
  end;

var
  // guards gvSinks and every sink in it; held across the sink call, so Detach can wait the callback out
  gvSinkLock: TRTLCriticalSection;
  gvSinks: TList;
  gvFrequency: Int64;

function Now64: Int64;
begin
  QueryPerformanceCounter(Result);
end;

function Millis(const aFrom, aTo: Int64): Int64;
begin
  if gvFrequency = 0 then
    Result := 0
  else
    Result := ((aTo - aFrom) * 1000) div gvFrequency;
end;

// NUL terminated; the reported length is only an upper bound
function InfoText(aInfo: Pointer; aInfoLen: DWORD): string;
const
  lcMaxChars = 512;
var
  lvChars: PAnsiChar;
  lvAnsi: AnsiString;
  lvMax, i: Integer;
begin
  Result := '';
  if aInfo = nil then
    Exit;
  // WinInet hands over bytes; aInfoLen counts bytes, not characters
  lvChars := PAnsiChar(aInfo);
  lvMax := lcMaxChars;
  if (aInfoLen > 0) and (aInfoLen < DWORD(lvMax)) then
    lvMax := aInfoLen;
  i := 0;
  while (i < lvMax) and (lvChars[i] <> #0) do
    Inc(i);
  SetString(lvAnsi, lvChars, i);
  Result := string(lvAnsi);
  // say it was cut rather than print a short url as if it were whole
  if i = lcMaxChars then
    Result := Result + '...';
end;

function InfoNumber(aInfo: Pointer; aInfoLen: DWORD): DWORD;
begin
  if (aInfo = nil) or (aInfoLen < SizeOf(DWORD)) then
    Result := 0
  else
    Result := PDWORD(aInfo)^;
end;

// caller holds gvSinkLock
function FindSink(aContextId: Cardinal): TbpTraceSink;
var
  i: Integer;
begin
  for i := 0 to gvSinks.Count - 1 do
  begin
    Result := TbpTraceSink(gvSinks[i]);
    if Result.FContextId = aContextId then
      Exit;
  end;
  Result := nil;
end;

{ TbpTraceSink }

function TbpTraceSink.IndexOf(aHandle: Pointer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FRequests) do
    if FRequests[i].Handle = aHandle then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
end;

function TbpTraceSink.Open(aHandle: Pointer): Integer;
begin
  Result := IndexOf(aHandle);
  if Result >= 0 then
    Exit;
  // SetLength zeroes the new record
  Result := Length(FRequests);
  SetLength(FRequests, Result + 1);
  Inc(FLastId);
  FRequests[Result].Handle := aHandle;
  FRequests[Result].Id := FLastId;
  FRequests[Result].Start := Now64;
end;

procedure TbpTraceSink.Close(aIndex: Integer);
var
  lvLast: Integer;
begin
  lvLast := High(FRequests);
  // the string field needs a proper assignment, not a move
  FRequests[aIndex] := FRequests[lvLast];
  SetLength(FRequests, lvLast);
end;

procedure TbpTraceSink.Emit(aHandle: Pointer; const aLine: string);
begin
  // a diagnostic must never unwind through wininet and abort the request
  try
    FProc(aHandle, aLine);
  except
  end;
end;

function TbpTraceSink.Summary(const aRequest: TbpTraceRequest;
  const aNow: Int64): string;

  procedure AddStep(const aName: string; const aAt: Int64);
  begin
    if aAt <> 0 then
      Result := Result + Format(', %s %d', [aName, Millis(aRequest.Start, aAt)]);
  end;

begin
  if aRequest.Failed then
    Result := 'failed'
  else
    Result := 'done';
  Result := Format('#%d %s in %d ms, %d bytes received', [aRequest.Id, Result,
    Millis(aRequest.Start, aNow), aRequest.Received]);
  AddStep('resolve', aRequest.Resolved);
  AddStep('connect', aRequest.Connected);
  AddStep('sent', aRequest.Sent);
  AddStep('first byte', aRequest.FirstByte);
  if aRequest.Address <> '' then
    Result := Result + ', ' + aRequest.Address;
  // WinInet reports no connect step on a pooled connection
  if aRequest.Connected <> 0 then
    Result := Result + ', new connection'
  else
    Result := Result + ', reused connection';
end;

procedure TbpTraceSink.Status(aHandle: Pointer; aStatus: DWORD;
  aInfo: Pointer; aInfoLen: DWORD);
var
  lvLine, lvAddress: string;
  lvIndex: Integer;
  lvNow: Int64;
  lvRequest: PbpTraceRequest;
begin
  lvNow := Now64;
  if aStatus = INTERNET_STATUS_HANDLE_CLOSING then
  begin
    // the connection handle closes too, and has no record
    lvIndex := IndexOf(aHandle);
    if lvIndex < 0 then
      Exit;
    lvLine := Summary(FRequests[lvIndex], lvNow);
    Close(lvIndex);
    Emit(aHandle, lvLine);
    Exit;
  end;

  lvLine := TbpHttpTrace.StatusText(aStatus, aInfo, aInfoLen);
  if lvLine = '' then
    Exit;
  lvRequest := @FRequests[Open(aHandle)];
  case aStatus of
    INTERNET_STATUS_NAME_RESOLVED:
      begin
        lvRequest.Resolved := lvNow;
        lvRequest.Address := InfoText(aInfo, aInfoLen);
      end;
    INTERNET_STATUS_CONNECTED_TO_SERVER:
      begin
        lvRequest.Connected := lvNow;
        lvAddress := InfoText(aInfo, aInfoLen);
        if lvAddress <> '' then
          lvRequest.Address := lvAddress;
      end;
    INTERNET_STATUS_REQUEST_SENT:
      if lvRequest.Sent = 0 then
        lvRequest.Sent := lvNow;
    INTERNET_STATUS_RESPONSE_RECEIVED:
      begin
        if lvRequest.FirstByte = 0 then
          lvRequest.FirstByte := lvNow;
        Inc(lvRequest.Received, InfoNumber(aInfo, aInfoLen));
      end;
  end;
  Emit(aHandle, Format('#%d +%d ms %s', [lvRequest.Id,
    Millis(lvRequest.Start, lvNow), lvLine]));
end;

procedure TbpTraceSink.Failure(aRequest: Pointer; const aMessage: string);
var
  lvIndex: Integer;
begin
  lvIndex := -1;
  if aRequest <> nil then
    lvIndex := IndexOf(aRequest);
  if lvIndex < 0 then
    Emit(aRequest, 'failed: ' + aMessage)
  else
  begin
    FRequests[lvIndex].Failed := True;
    Emit(aRequest, Format('#%d failed: %s', [FRequests[lvIndex].Id, aMessage]));
  end;
end;

{ callbacks }

procedure TraceStatusCallback(aInternet: HINTERNET; aContext, aStatus: DWORD;
  aInfo: Pointer; aInfoLen: DWORD); stdcall;
var
  lvSink: TbpTraceSink;
begin
  EnterCriticalSection(gvSinkLock);
  try
    // a handle opened before Detach still calls in, and finds no sink
    lvSink := FindSink(aContext);
    if lvSink <> nil then
      lvSink.Status(Pointer(aInternet), aStatus, aInfo, aInfoLen);
  finally
    LeaveCriticalSection(gvSinkLock);
  end;
end;

procedure TraceFailure(aContextId: Cardinal; aRequest: Pointer;
  const aMessage: string; aError: DWORD);
var
  lvSink: TbpTraceSink;
begin
  EnterCriticalSection(gvSinkLock);
  try
    lvSink := FindSink(aContextId);
    if lvSink <> nil then
      lvSink.Failure(aRequest, aMessage);
  finally
    LeaveCriticalSection(gvSinkLock);
  end;
end;

{ TbpHttpTrace }

class function TbpHttpTrace.Attach(aClient: TbpHttpClient;
  aProc: TbpHttpTraceProc): Boolean;
var
  lvSession: HINTERNET;
  lvSink: TbpTraceSink;
begin
  // opening the session can raise, which must not disturb a live trace
  lvSession := aClient.SessionHandle;
  EnterCriticalSection(gvSinkLock);
  try
    lvSink := FindSink(aClient.ContextId);
    if lvSink = nil then
    begin
      lvSink := TbpTraceSink.Create;
      lvSink.FContextId := aClient.ContextId;
      gvSinks.Add(lvSink);
    end;
    lvSink.FProc := aProc;
  finally
    LeaveCriticalSection(gvSinkLock);
  end;
  // the sentinel is -1 widened to a pointer, not a callback address
  Result := Pointer(InternetSetStatusCallbackA(lvSession,
    PFNInternetStatusCallback(@TraceStatusCallback))) <>
    Pointer(TbpUIntPtr(INTERNET_INVALID_STATUS_CALLBACK));
  // a failed attach must not leave the sink armed
  if not Result then
    Detach(aClient);
end;

class procedure TbpHttpTrace.Detach(aClient: TbpHttpClient);
var
  lvSink: TbpTraceSink;
begin
  // the lock is a barrier: a thread already inside the sink has left by now
  EnterCriticalSection(gvSinkLock);
  try
    lvSink := FindSink(aClient.ContextId);
    if lvSink <> nil then
    begin
      gvSinks.Remove(lvSink);
      lvSink.Free;
    end;
  finally
    LeaveCriticalSection(gvSinkLock);
  end;
  // no session means nothing to detach from; opening one here would raise
  if aClient.SessionActive then
    InternetSetStatusCallbackA(aClient.SessionHandle, nil);
end;

class function TbpHttpTrace.StatusText(aStatus: DWORD; aInfo: Pointer;
  aInfoLen: DWORD): string;
begin
  case aStatus of
    INTERNET_STATUS_RESOLVING_NAME:
      Result := 'resolving ' + InfoText(aInfo, aInfoLen);
    INTERNET_STATUS_NAME_RESOLVED:
      Result := 'resolved -> ' + InfoText(aInfo, aInfoLen);
    INTERNET_STATUS_CONNECTING_TO_SERVER:
      Result := 'connecting to ' + InfoText(aInfo, aInfoLen);
    INTERNET_STATUS_CONNECTED_TO_SERVER:
      Result := 'connected to ' + InfoText(aInfo, aInfoLen);
    INTERNET_STATUS_SENDING_REQUEST:
      Result := 'sending request';
    INTERNET_STATUS_REQUEST_SENT:
      Result := Format('request sent (%d bytes)', [InfoNumber(aInfo, aInfoLen)]);
    INTERNET_STATUS_RECEIVING_RESPONSE:
      Result := 'waiting for response';
    INTERNET_STATUS_RESPONSE_RECEIVED:
      Result := Format('response received (%d bytes)',
        [InfoNumber(aInfo, aInfoLen)]);
    INTERNET_STATUS_CLOSING_CONNECTION:
      Result := 'closing connection';
    INTERNET_STATUS_CONNECTION_CLOSED:
      Result := 'connection closed';
    gcStatusDetectingProxy:
      Result := 'detecting proxy';
    INTERNET_STATUS_REDIRECT:
      Result := 'redirect -> ' + SanitizeUrl(InfoText(aInfo, aInfoLen));
    INTERNET_STATUS_INTERMEDIATE_RESPONSE:
      Result := 'intermediate response';
    INTERNET_STATUS_HANDLE_CREATED, INTERNET_STATUS_HANDLE_CLOSING,
    INTERNET_STATUS_REQUEST_COMPLETE, INTERNET_STATUS_STATE_CHANGE,
    gcStatusCookieFirst..gcStatusCookieLast:
      Result := '';  // noise
  else
    Result := Format('status %d', [aStatus]);
  end;
end;

class function TbpHttpTrace.SanitizeUrl(const aUrl: string): string;
begin
  Result := BpHttpStripUserInfo(aUrl);
end;

procedure FreeSinks;
var
  i: Integer;
begin
  for i := 0 to gvSinks.Count - 1 do
    TbpTraceSink(gvSinks[i]).Free;
  gvSinks.Free;
end;

initialization
  InitializeCriticalSection(gvSinkLock);
  gvSinks := TList.Create;
  if not QueryPerformanceFrequency(gvFrequency) then
    gvFrequency := 0;
  BpSetHttpFailureHook(TraceFailure);

finalization
  BpSetHttpFailureHook(nil);
  FreeSinks;
  DeleteCriticalSection(gvSinkLock);

end.
