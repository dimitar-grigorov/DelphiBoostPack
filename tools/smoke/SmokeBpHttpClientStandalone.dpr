program SmokeBpHttpClientStandalone;

// smoke test for dist\BpHttpClientStandalone.pas: offline checks only,
// compiled against the bundle only (see tools\VerifyBundles.cmd)

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, BpHttpClientStandalone;

// cleanup callback for the cancellation token check
var
  gvCleanupRan: Boolean = False;

procedure MarkCleanupRan(AData: Pointer);
begin
  gvCleanupRan := True;
end;

function CheckClient: Boolean;
var
  lvClient: TbpHttpClient;
  lvServer, lvResource, lvHeaders: string;
  lvPort: Integer;
  lvSecure: Boolean;
begin
  Result := False;
  lvClient := TbpHttpClient.Create;
  try
    if not lvClient.ParseUrl('https://api.example.com:8443/v1/items?page=2',
      lvServer, lvResource, lvPort, lvSecure) then
      Writeln('FAIL: ParseUrl rejected a valid url')
    else if (lvServer <> 'api.example.com') or (lvPort <> 8443) or
      not lvSecure or (lvResource <> '/v1/items?page=2') then
      Writeln('FAIL: ParseUrl fields')
    else
    begin
      lvClient.SetBasicAuth('user', 'pass');
      lvHeaders := lvClient.BuildHeaders('');
      if Pos('Authorization: Basic dXNlcjpwYXNz', lvHeaders) = 0 then
        Writeln('FAIL: basic auth header (embedded Base64)')
      else
        Result := True;
    end;
  finally
    lvClient.Free;
  end;
end;

function CheckDownloadHelpers: Boolean;
const
  lcHeaders = 'HTTP/1.1 200 OK'#13#10'Content-Length: 5368709120'#13#10;
begin
  Result := False;
  if BpHttpContentLength(lcHeaders) <> Int64(5) * 1024 * 1024 * 1024 then
    Writeln('FAIL: BpHttpContentLength on a 5 GB header')
  else if BpHttpContentLength('') <> -1 then
    Writeln('FAIL: BpHttpContentLength on empty headers')
  else if BpHttpProgressPercent(500, 1000) <> 50 then
    Writeln('FAIL: BpHttpProgressPercent midpoint')
  else if BpHttpProgressPercent(1, -1) <> -1 then
    Writeln('FAIL: BpHttpProgressPercent unknown total')
  else if BpClassifyHttpError(gcErrOperationCancelled, 0) <> 'Operation cancelled' then
    Writeln('FAIL: BpClassifyHttpError for a cancel')
  else
    Result := True;
end;

function CheckCancellationToken: Boolean;
var
  lvToken: TbpCancellationToken;
  lvId: Integer;
begin
  Result := False;
  lvToken := TbpCancellationToken.Create;
  try
    if lvToken.IsCancellationRequested then
      Writeln('FAIL: fresh token already cancelled')
    else if not lvToken.RegisterCleanup(MarkCleanupRan, nil, lvId) then
      Writeln('FAIL: cleanup registration refused')
    else
    begin
      lvToken.Cancel;
      if not lvToken.IsCancellationRequested then
        Writeln('FAIL: Cancel did not stick')
      else if not gvCleanupRan then
        Writeln('FAIL: cleanup did not run on Cancel')
      else
        Result := True;
    end;
  finally
    lvToken.Free;
  end;
end;

// a pre-cancelled token stops a verb before any network access, so this
// checks the token parameter reached the bundle without going online
function CheckRequestCancellation: Boolean;
var
  lvClient: TbpHttpClient;
  lvToken: TbpCancellationToken;
begin
  Result := False;
  lvClient := TbpHttpClient.Create;
  lvToken := TbpCancellationToken.Create;
  try
    lvToken.Cancel;
    try
      lvClient.Post('https://example.com/graphql', '{}', '', lvToken);
      Writeln('FAIL: cancelled token did not stop Post');
    except
      on E: EbpHttpClientCancelled do
        if E.WinInetError = gcErrOperationCancelled then
          Result := True
        else
          Writeln('FAIL: cancelled Post carries the wrong WinInet error');
      on EbpHttpClient do
        Writeln('FAIL: cancelled Post raised the generic error');
    end;
  finally
    lvToken.Free;
    lvClient.Free;
  end;
end;

function CheckAsyncTask: Boolean;
var
  lvClient: TbpHttpClient;
  lvTask: IbpHttpTask;
begin
  Result := False;
  lvClient := TbpHttpClient.Create;
  try
    // events on the worker: no message loop in a console smoke test
    lvClient.MarshalTaskEvents := False;
    // an unparsable url fails the task on the worker, never reaching the network
    lvTask := lvClient.BeginGet('not a url at all', nil);
    if not lvTask.WaitFor(5000) then
      Writeln('FAIL: async task did not finish')
    else if lvTask.State <> htsFailed then
      Writeln('FAIL: async task with a bad url did not fail')
    else
      try
        lvTask.Response;
        Writeln('FAIL: Response of a failed task did not raise');
      except
        on EbpHttpClient do
          Result := True;
      end;
    lvTask := nil;
  finally
    lvClient.Free;
  end;
end;

begin
  ExitCode := 1;
  if CheckClient and CheckDownloadHelpers and CheckCancellationToken and
    CheckRequestCancellation and CheckAsyncTask then
  begin
    Writeln('OK: BpHttpClientStandalone');
    ExitCode := 0;
  end;
end.
