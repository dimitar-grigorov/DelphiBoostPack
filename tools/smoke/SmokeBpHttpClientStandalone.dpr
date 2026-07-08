program SmokeBpHttpClientStandalone;

// smoke test for dist\BpHttpClientStandalone.pas: offline checks only,
// compiled against the bundle only (see tools\VerifyBundles.cmd)

{$APPTYPE CONSOLE}

uses
  SysUtils, BpHttpClientStandalone;

var
  lvClient: TbpHttpClient;
  lvServer, lvResource, lvHeaders: string;
  lvPort: Integer;
  lvSecure: Boolean;
begin
  ExitCode := 1;
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
      begin
        Writeln('OK: BpHttpClientStandalone');
        ExitCode := 0;
      end;
    end;
  finally
    lvClient.Free;
  end;
end.
