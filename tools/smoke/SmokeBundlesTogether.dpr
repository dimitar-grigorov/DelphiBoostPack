program SmokeBundlesTogether;

// two bundles in one program: BpHashes exports Base64, BpHttpClientStandalone
// keeps its mirrored copy private, so nothing is declared twice. That is the
// pairing README calls out, and this is what makes the claim testable.

{$APPTYPE CONSOLE}

uses
  SysUtils, BpHashes, BpHttpClientStandalone;

function CheckNoCollision: Boolean;
var
  lvClient: TbpHttpClient;
begin
  Result := False;
  // unqualified: it must resolve to BpHashes without the uses order mattering
  if Base64Encode(AnsiString('foobar')) <> 'Zm9vYmFy' then
  begin
    Writeln('FAIL: Base64Encode from BpHashes');
    Exit;
  end;
  lvClient := TbpHttpClient.Create;
  try
    lvClient.SetBasicAuth('user', 'pass');
    // the same bytes from the copy the http bundle carries instead
    if Pos('Authorization: Basic dXNlcjpwYXNz', lvClient.BuildHeaders('')) = 0 then
      Writeln('FAIL: basic auth header from BpHttpClientStandalone')
    else
      Result := True;
  finally
    lvClient.Free;
  end;
end;

function CheckExceptionIdentity: Boolean;
begin
  // one EbpBase64 in the program now, so BpHashes errors are catchable as it
  Result := False;
  try
    Base64Decode('a*b');
    Writeln('FAIL: invalid Base64 was accepted');
  except
    on EbpBase64 do
      Result := True;
  end;
end;

begin
  ExitCode := 1;
  if CheckNoCollision and CheckExceptionIdentity then
  begin
    Writeln('OK: BundlesTogether');
    ExitCode := 0;
  end;
end.
