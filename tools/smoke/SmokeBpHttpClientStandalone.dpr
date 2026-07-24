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

function CheckDownloadTask: Boolean;
var
  lvTask: TbpHttpDownloadTask;
  lvRaised: Boolean;
begin
  Result := False;
  // events on this thread: no message loop in a console smoke test
  lvTask := TbpHttpDownloadTask.Create(False);
  try
    if lvTask.State <> dtsPending then
      Writeln('FAIL: fresh task not pending')
    else if lvTask.Total <> -1 then
      Writeln('FAIL: fresh task total not unknown')
    else
    begin
      lvRaised := False;
      try
        lvTask.Start;  // no Url, no destination
      except
        on EbpHttpClient do
          lvRaised := True;
      end;
      if not lvRaised then
        Writeln('FAIL: Start accepted a misconfigured task')
      else if lvTask.State <> dtsPending then
        Writeln('FAIL: failed validation changed the task state')
      else
        Result := True;
    end;
  finally
    lvTask.Free;
  end;
end;

begin
  ExitCode := 1;
  if CheckClient and CheckDownloadHelpers and CheckCancellationToken and
    CheckDownloadTask then
  begin
    Writeln('OK: BpHttpClientStandalone');
    ExitCode := 0;
  end;
end.
