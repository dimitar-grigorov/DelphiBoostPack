unit BpHttpTrace;

// An in-process 'ssh -v' for TbpHttpClient: DNS, connect, byte counts,
// redirects. Optional - nothing references this unit.
//
//   TbpHttpTrace.Attach(FClient, MyTrace);
//   TbpHttpTrace.Detach(FClient);

interface

uses
  Windows, BpHttpClient;

type
  // runs on the thread doing the I/O, so keep it quick
  TbpHttpTraceProc = procedure(aHandle: Pointer; const aLine: string);

  TbpHttpTrace = class
  public
    // one sink per process; the last Attach wins
    class procedure Attach(aClient: TbpHttpClient; aProc: TbpHttpTraceProc);
    class procedure Detach(aClient: TbpHttpClient);

    // '' for the statuses a wire trace skips
    class function StatusText(aStatus: DWORD; aInfo: Pointer;
      aInfoLen: DWORD): string;
    // drops user:password@ from a url
    class function SanitizeUrl(const aUrl: string): string;
  end;

implementation

uses
  SysUtils, WinInet;

const
  gcStatusDetectingProxy = 80;   // missing from D2007's WinInet.pas
  gcStatusCookieFirst    = 320;  // the cookie, P3P and privacy family
  gcStatusCookieLast     = 327;

var
  gvTraceProc: TbpHttpTraceProc = nil;

procedure TraceStatusCallback(aInternet: HINTERNET; aContext, aStatus: DWORD;
  aInfo: Pointer; aInfoLen: DWORD); stdcall;
var
  lvProc: TbpHttpTraceProc;
  lvLine: string;
begin
  lvProc := gvTraceProc;  // one read: Detach can run at any time
  if not Assigned(lvProc) then
    Exit;
  lvLine := TbpHttpTrace.StatusText(aStatus, aInfo, aInfoLen);
  if lvLine = '' then
    Exit;
  // a diagnostic must never unwind through wininet and abort the request
  try
    lvProc(Pointer(aInternet), lvLine);
  except
  end;
end;

{ TbpHttpTrace }

class procedure TbpHttpTrace.Attach(aClient: TbpHttpClient;
  aProc: TbpHttpTraceProc);
begin
  gvTraceProc := aProc;
  InternetSetStatusCallback(aClient.SessionHandle,
    PFNInternetStatusCallback(@TraceStatusCallback));
end;

class procedure TbpHttpTrace.Detach(aClient: TbpHttpClient);
begin
  InternetSetStatusCallback(aClient.SessionHandle, nil);
  gvTraceProc := nil;
end;

class function TbpHttpTrace.StatusText(aStatus: DWORD; aInfo: Pointer;
  aInfoLen: DWORD): string;

  // NUL terminated; the reported length is only an upper bound
  function InfoText: string;
  const
    lcMaxChars = 512;
  var
    lvChars: PChar;
    lvMax, i: Integer;
  begin
    Result := '';
    if aInfo = nil then
      Exit;
    lvChars := PChar(aInfo);
    lvMax := lcMaxChars;
    if (aInfoLen > 0) and (aInfoLen < DWORD(lvMax)) then
      lvMax := aInfoLen;
    i := 0;
    while (i < lvMax) and (lvChars[i] <> #0) do
      Inc(i);
    SetString(Result, lvChars, i);
  end;

  function InfoNumber: DWORD;
  begin
    if (aInfo = nil) or (aInfoLen < SizeOf(DWORD)) then
      Result := 0
    else
      Result := PDWORD(aInfo)^;
  end;

begin
  case aStatus of
    INTERNET_STATUS_RESOLVING_NAME:
      Result := 'resolving ' + InfoText;
    INTERNET_STATUS_NAME_RESOLVED:
      Result := 'resolved -> ' + InfoText;
    INTERNET_STATUS_CONNECTING_TO_SERVER:
      Result := 'connecting to ' + InfoText;
    INTERNET_STATUS_CONNECTED_TO_SERVER:
      Result := 'connected to ' + InfoText;
    INTERNET_STATUS_SENDING_REQUEST:
      Result := 'sending request';
    INTERNET_STATUS_REQUEST_SENT:
      Result := Format('request sent (%d bytes)', [InfoNumber]);
    INTERNET_STATUS_RECEIVING_RESPONSE:
      Result := 'waiting for response';
    INTERNET_STATUS_RESPONSE_RECEIVED:
      Result := Format('response received (%d bytes)', [InfoNumber]);
    INTERNET_STATUS_CLOSING_CONNECTION:
      Result := 'closing connection';
    INTERNET_STATUS_CONNECTION_CLOSED:
      Result := 'connection closed';
    gcStatusDetectingProxy:
      Result := 'detecting proxy';
    INTERNET_STATUS_REDIRECT:
      Result := 'redirect -> ' + SanitizeUrl(InfoText);
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
var
  lvStart, lvAt, i: Integer;
begin
  Result := aUrl;
  lvStart := Pos('://', Result);
  if lvStart = 0 then
    Exit;
  Inc(lvStart, 3);

  // userinfo sits before the first @ of the authority
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

end.
