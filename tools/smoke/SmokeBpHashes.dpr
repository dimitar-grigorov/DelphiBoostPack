program SmokeBpHashes;

// smoke test for dist\BpHashes.pas: known-answer vector per embedded hash,
// compiled against the bundle only (see tools\VerifyBundles.cmd)

{$APPTYPE CONSOLE}

uses
  SysUtils, BpHashes;

begin
  ExitCode := 1;
  if TbpSHA256.HashStrHex('abc') <>
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' then
    Writeln('FAIL: SHA-256 vector')
  else if TbpMD5.HashStrHex('abc') <> '900150983cd24fb0d6963f7d28e17f72' then
    Writeln('FAIL: MD5 vector')
  else if TbpHMACSHA256.ComputeHex('key',
    'The quick brown fox jumps over the lazy dog') <>
    'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8' then
    Writeln('FAIL: HMAC-SHA256 vector')
  else if Base64Encode(AnsiString('foobar')) <> 'Zm9vYmFy' then
    Writeln('FAIL: Base64 vector')
  else
  begin
    Writeln('OK: BpHashes');
    ExitCode := 0;
  end;
end.
