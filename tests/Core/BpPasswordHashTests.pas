unit BpPasswordHashTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, BpPasswordHash;

type
  TBpPasswordHashTests = class(TTestCase)
  private
    procedure CheckPbkdf2(const aExpectedHex: string; const aPassword, aSalt: AnsiString;
      aIterations, aKeyLen: Integer; const aCase: string);
  published
    procedure TestPbkdf2Vectors;
    procedure TestPbkdf2HexMatchesRaw;
    procedure TestPbkdf2BadArgs;
    procedure TestHashVerifyRoundTrip;
    procedure TestVerifyExternalRecord;
    procedure TestVerifyWrongPassword;
    procedure TestVerifyTamperedRecord;
    procedure TestVerifyMalformedInput;
    procedure TestRecordFormat;
    procedure TestSaltUniqueness;
    procedure TestConstantTimeEquals;
  end;

implementation

procedure TBpPasswordHashTests.CheckPbkdf2(const aExpectedHex: string;
  const aPassword, aSalt: AnsiString; aIterations, aKeyLen: Integer; const aCase: string);
begin
  CheckEquals(aExpectedHex,
    BpPBKDF2SHA256Hex(aPassword, aSalt, aIterations, aKeyLen), aCase);
end;

procedure TBpPasswordHashTests.TestPbkdf2Vectors;
begin
  // published PBKDF2-HMAC-SHA256 vectors, cross-checked against python hashlib
  CheckPbkdf2('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    'password', 'salt', 1, 32, 'c=1');
  CheckPbkdf2('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    'password', 'salt', 2, 32, 'c=2');
  CheckPbkdf2('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    'password', 'salt', 4096, 32, 'c=4096');
  // 40-byte key exercises the multi-block path with a partial last block
  CheckPbkdf2('348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9',
    'passwordPASSWORDpassword', 'saltSALTsaltSALTsaltSALTsaltSALTsalt', 4096, 40,
    'long password and salt');
  // embedded zero bytes must be hashed, not treated as terminators
  CheckPbkdf2('89b69d0516f829893c696226650a8687',
    AnsiString('pass') + #0 + 'word', AnsiString('sa') + #0 + 'lt', 4096, 16,
    'zero bytes');
end;

procedure TBpPasswordHashTests.TestPbkdf2HexMatchesRaw;
var
  lvRaw: AnsiString;
  lvHex: string;
  i: Integer;
begin
  lvRaw := BpPBKDF2SHA256('hunter2', '0123456789abcdef', 1000, 32);
  lvHex := BpPBKDF2SHA256Hex('hunter2', '0123456789abcdef', 1000, 32);
  // value cross-checked against python hashlib.pbkdf2_hmac
  CheckEquals('a63e13df90f6bf8b58982d6c4c9d72e6d70c00339db67406bee1e6c980d08768', lvHex);
  CheckEquals(32, Length(lvRaw), 'raw length');
  for i := 1 to Length(lvRaw) do
    CheckEquals(Ord(lvRaw[i]),
      StrToInt('$' + Copy(lvHex, i * 2 - 1, 2)), Format('byte %d', [i]));
end;

procedure TBpPasswordHashTests.TestPbkdf2BadArgs;
begin
  try
    BpPBKDF2SHA256('p', 's', 0, 32);
    Fail('zero iterations must raise');
  except
    on E: Exception do
      Check(True);
  end;
  try
    BpPBKDF2SHA256('p', 's', 1000, 0);
    Fail('zero key length must raise');
  except
    on E: Exception do
      Check(True);
  end;
end;

procedure TBpPasswordHashTests.TestHashVerifyRoundTrip;
var
  lvStored: string;
begin
  // small iteration count keeps the suite fast; the format is identical
  lvStored := BpHashPassword('correct horse battery staple', 1000);
  CheckTrue(BpVerifyPassword('correct horse battery staple', lvStored), 'right password');
  // empty password round-trips too
  lvStored := BpHashPassword('', 500);
  CheckTrue(BpVerifyPassword('', lvStored), 'empty password');
  CheckFalse(BpVerifyPassword('x', lvStored), 'empty record vs non-empty password');
end;

procedure TBpPasswordHashTests.TestVerifyExternalRecord;
const
  // produced by .NET Rfc2898DeriveBytes (password 'p', salt 'salt', c=1000),
  // never by our own code, so this pins cross-implementation interop
  lcRecord = '$pbkdf2-sha256$1000$c2FsdA==$rs96FmOyNUg3Gy2NJydDTZnhjENOrJOcqeTzVD0qDf0=';
begin
  CheckTrue(BpVerifyPassword('p', lcRecord), 'external record verifies');
  CheckFalse(BpVerifyPassword('q', lcRecord), 'wrong password against external record');
end;

procedure TBpPasswordHashTests.TestVerifyWrongPassword;
var
  lvStored: string;
begin
  lvStored := BpHashPassword('secret', 1000);
  CheckFalse(BpVerifyPassword('Secret', lvStored), 'case differs');
  CheckFalse(BpVerifyPassword('secret ', lvStored), 'trailing space');
  CheckFalse(BpVerifyPassword('', lvStored), 'empty password');
end;

procedure TBpPasswordHashTests.TestVerifyTamperedRecord;
var
  lvStored, lvTampered: string;
  lvPos: Integer;
begin
  lvStored := BpHashPassword('secret', 1000);
  CheckTrue(BpVerifyPassword('secret', lvStored), 'untampered sanity');
  // flip a character in the middle of the hash field
  lvTampered := lvStored;
  lvPos := Length(lvTampered) - 10;
  if lvTampered[lvPos] = 'A' then
    lvTampered[lvPos] := 'B'
  else
    lvTampered[lvPos] := 'A';
  CheckFalse(BpVerifyPassword('secret', lvTampered), 'tampered hash');
  // flip a character in the middle of the salt field
  lvTampered := lvStored;
  lvPos := Pos('$1000$', lvTampered) + 8;
  if lvTampered[lvPos] = 'A' then
    lvTampered[lvPos] := 'B'
  else
    lvTampered[lvPos] := 'A';
  CheckFalse(BpVerifyPassword('secret', lvTampered), 'tampered salt');
  // raise the claimed iteration count
  lvTampered := StringReplace(lvStored, '$1000$', '$1001$', []);
  CheckFalse(BpVerifyPassword('secret', lvTampered), 'tampered iterations');
end;

procedure TBpPasswordHashTests.TestVerifyMalformedInput;
begin
  // anything that does not parse returns False and must never raise
  CheckFalse(BpVerifyPassword('p', ''), 'empty');
  CheckFalse(BpVerifyPassword('p', 'plaintext'), 'no separators');
  CheckFalse(BpVerifyPassword('p', '$'), 'lone separator');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$'), 'scheme only');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$1000$'), 'missing salt and hash');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$1000$c2FsdA==$'), 'empty hash');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha1$1000$c2FsdA==$c2FsdA=='), 'wrong scheme');
  CheckFalse(BpVerifyPassword('p', 'pbkdf2-sha256$1000$c2FsdA==$c2FsdA=='), 'no leading $');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$abc$c2FsdA==$c2FsdA=='), 'bad iterations');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$0$c2FsdA==$c2FsdA=='), 'zero iterations');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$-5$c2FsdA==$c2FsdA=='), 'negative iterations');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$1000$!!!$c2FsdA=='), 'bad salt base64');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$1000$c2FsdA==$!!!'), 'bad hash base64');
  CheckFalse(BpVerifyPassword('p', '$pbkdf2-sha256$1000$c2FsdA==$c2FsdA==$extra'), 'extra field');
end;

procedure TBpPasswordHashTests.TestRecordFormat;
var
  lvStored: string;
begin
  // defaults are pinned here; the record itself is built with a small count
  CheckEquals(600000, gcBpPasswordHashIterations, 'default iterations');
  CheckEquals(16, gcBpPasswordHashSaltLen, 'default salt length');
  CheckEquals(32, gcBpPasswordHashKeyLen, 'default key length');
  lvStored := BpHashPassword('pw', 1000);
  CheckEquals('$pbkdf2-sha256$1000$', Copy(lvStored, 1, 20), 'record prefix');
  // 16 salt bytes -> 24 base64 chars, 32 key bytes -> 44, plus 4 separators
  CheckEquals(Length('$pbkdf2-sha256$1000$') + 24 + 1 + 44, Length(lvStored), 'record length');
end;

procedure TBpPasswordHashTests.TestSaltUniqueness;
var
  lvSalts: array[0..19] of AnsiString;
  i, j: Integer;
begin
  CheckEquals(0, Length(BpGenerateSalt(0)), 'zero length');
  for i := 0 to High(lvSalts) do
  begin
    lvSalts[i] := BpGenerateSalt(16);
    CheckEquals(16, Length(lvSalts[i]), Format('salt %d length', [i]));
  end;
  for i := 0 to High(lvSalts) - 1 do
    for j := i + 1 to High(lvSalts) do
      CheckFalse(lvSalts[i] = lvSalts[j], Format('salts %d and %d collide', [i, j]));
end;

procedure TBpPasswordHashTests.TestConstantTimeEquals;
begin
  CheckTrue(BpConstantTimeEquals('', ''), 'both empty');
  CheckTrue(BpConstantTimeEquals('abc', 'abc'), 'equal');
  CheckTrue(BpConstantTimeEquals(AnsiString('a') + #0 + 'b', AnsiString('a') + #0 + 'b'),
    'equal with zero byte');
  CheckFalse(BpConstantTimeEquals('abc', 'abd'), 'differs at end');
  CheckFalse(BpConstantTimeEquals('abc', 'xbc'), 'differs at start');
  CheckFalse(BpConstantTimeEquals('abc', 'ab'), 'shorter');
  CheckFalse(BpConstantTimeEquals('ab', 'abc'), 'longer');
  CheckFalse(BpConstantTimeEquals('', 'a'), 'empty vs non-empty');
end;

initialization
  RegisterTest(TBpPasswordHashTests.Suite);

end.
