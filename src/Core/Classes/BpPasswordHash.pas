unit BpPasswordHash;

// Password hashing with PBKDF2-HMAC-SHA256 (RFC 2898), built on BpHMACSHA256.
// Salt from the Windows CSPRNG, constant-time verify, and a self-describing
// record so the work factor can grow without breaking old hashes:
//   lvStored := BpHashPassword('hunter2');  // $pbkdf2-sha256$600000$<salt>$<hash>
//   if BpVerifyPassword('hunter2', lvStored) then ...
// Takes bytes, not text: on Delphi 2009+ pass AnsiString(UTF8Encode(lvPassword)),
// or the ANSI conversion makes the hash lossy and locale-dependent.

interface

uses
  SysUtils, BpSHA256, BpHMACSHA256;

const
  // OWASP recommendation for PBKDF2-HMAC-SHA256 as of 2023+
  gcBpPasswordHashIterations = 600000;
  gcBpPasswordHashSaltLen = 16;
  gcBpPasswordHashKeyLen = 32;
  // ceilings for a stored record: 10 million rounds is already ~40 s per verify
  gcBpPasswordHashMaxIterations = 10000000;
  gcBpPasswordHashMaxKeyLen = 64;
  // a truncated record must not authenticate: one hash byte matches 1 in 256
  gcBpPasswordHashMinKeyLen = 16;

type
  EbpPasswordHash = class(Exception);

// raw derived key bytes in an AnsiString, plus a lowercase hex convenience wrapper
function BpPBKDF2SHA256(const aPassword, aSalt: AnsiString;
  aIterations, aKeyLen: Integer): AnsiString;
function BpPBKDF2SHA256Hex(const aPassword, aSalt: AnsiString;
  aIterations, aKeyLen: Integer): string;
// aLen random bytes from CryptGenRandom; raises on CSPRNG failure, never falls back
function BpGenerateSalt(aLen: Integer): AnsiString;
// no early exit on mismatch, so timing does not leak where the strings differ
function BpConstantTimeEquals(const A, B: AnsiString): Boolean;
// salt + derive + format in one call; the overload picks the iteration count
function BpHashPassword(const aPassword: AnsiString): string; overload;
function BpHashPassword(const aPassword: AnsiString; aIterations: Integer): string; overload;
// re-derives and compares in constant time; malformed input is False, not a raise
function BpVerifyPassword(const aPassword: AnsiString; const aStored: string): Boolean;

implementation

uses
  Windows, BpBase64;

const
  gcBpPasswordHashScheme = 'pbkdf2-sha256';
  gcBpProvRsaFull = 1;
  gcBpCryptVerifyContext = DWORD($F0000000);

// CryptoAPI CSPRNG, straight from advapi32 so Delphi 7 needs no import unit
function CryptAcquireContextA(var aProv: THandle; aContainer, aProvider: PAnsiChar;
  aProvType, aFlags: DWORD): BOOL; stdcall; external 'advapi32.dll';
function CryptReleaseContext(aProv: THandle; aFlags: DWORD): BOOL; stdcall;
  external 'advapi32.dll';
function CryptGenRandom(aProv: THandle; aLen: DWORD; aBuffer: PAnsiChar): BOOL; stdcall;
  external 'advapi32.dll';

function BpPBKDF2SHA256(const aPassword, aSalt: AnsiString;
  aIterations, aKeyLen: Integer): AnsiString;
var
  lvHmac: TbpHMACSHA256;
  lvU, lvT: TbpSHA256Digest;
  lvCounter: array[0..3] of Byte;
  lvBlock, lvBlocks, lvIter, lvOffset, lvTake, i: Integer;
begin
  if (aIterations < 1) or (aKeyLen < 1) then
    raise EbpPasswordHash.Create(
      'BpPBKDF2SHA256: iterations and key length must be positive');
  SetLength(Result, aKeyLen);
  lvBlocks := (aKeyLen + 31) div 32;
  lvOffset := 0;
  // one HMAC instance for the whole derivation: Final re-arms it with the same key
  lvHmac := TbpHMACSHA256.Create(aPassword);
  try
    for lvBlock := 1 to lvBlocks do
    begin
      // U1 = HMAC(password, salt || INT_32_BE(block))
      lvCounter[0] := Byte(lvBlock shr 24);
      lvCounter[1] := Byte(lvBlock shr 16);
      lvCounter[2] := Byte(lvBlock shr 8);
      lvCounter[3] := Byte(lvBlock);
      lvHmac.Update(aSalt);
      lvHmac.Update(lvCounter, SizeOf(lvCounter));
      lvHmac.Final(lvU);
      lvT := lvU;
      // Un = HMAC(password, Un-1); the block is U1 xor U2 xor ... xor Uc
      for lvIter := 2 to aIterations do
      begin
        lvHmac.Update(lvU, SizeOf(lvU));
        lvHmac.Final(lvU);
        for i := 0 to High(lvU) do
          lvT[i] := lvT[i] xor lvU[i];
      end;
      // the last block may be partial when aKeyLen is not a multiple of 32
      lvTake := aKeyLen - lvOffset;
      if lvTake > SizeOf(lvT) then
        lvTake := SizeOf(lvT);
      Move(lvT, Result[lvOffset + 1], lvTake);
      Inc(lvOffset, lvTake);
    end;
  finally
    // wipe intermediates holding key material
    FillChar(lvU, SizeOf(lvU), 0);
    FillChar(lvT, SizeOf(lvT), 0);
    lvHmac.Free;
  end;
end;

function BpPBKDF2SHA256Hex(const aPassword, aSalt: AnsiString;
  aIterations, aKeyLen: Integer): string;
const
  lcHexDigits = '0123456789abcdef';
var
  lvKey: AnsiString;
  i: Integer;
begin
  lvKey := BpPBKDF2SHA256(aPassword, aSalt, aIterations, aKeyLen);
  SetLength(Result, Length(lvKey) * 2);
  for i := 1 to Length(lvKey) do
  begin
    Result[i * 2 - 1] := lcHexDigits[(Ord(lvKey[i]) shr 4) + 1];
    Result[i * 2] := lcHexDigits[(Ord(lvKey[i]) and $0F) + 1];
  end;
end;

function BpGenerateSalt(aLen: Integer): AnsiString;
var
  lvProv: THandle;
begin
  Result := '';
  if aLen <= 0 then
    Exit;
  SetLength(Result, aLen);
  // CRYPT_VERIFYCONTEXT: ephemeral context, no key container touched on disk
  if not CryptAcquireContextA(lvProv, nil, nil, gcBpProvRsaFull, gcBpCryptVerifyContext) then
    raise EbpPasswordHash.CreateFmt(
      'BpGenerateSalt: CryptAcquireContext failed, error %d', [GetLastError]);
  try
    if not CryptGenRandom(lvProv, aLen, PAnsiChar(Result)) then
      raise EbpPasswordHash.CreateFmt(
        'BpGenerateSalt: CryptGenRandom failed, error %d', [GetLastError]);
  finally
    CryptReleaseContext(lvProv, 0);
  end;
end;

function BpConstantTimeEquals(const A, B: AnsiString): Boolean;
var
  lvDiff, i: Integer;
begin
  // length is not secret; the loop below never exits early on content
  if Length(A) <> Length(B) then
  begin
    Result := False;
    Exit;
  end;
  lvDiff := 0;
  for i := 1 to Length(A) do
    lvDiff := lvDiff or (Ord(A[i]) xor Ord(B[i]));
  Result := lvDiff = 0;
end;

function BpHashPassword(const aPassword: AnsiString): string;
begin
  Result := BpHashPassword(aPassword, gcBpPasswordHashIterations);
end;

function BpHashPassword(const aPassword: AnsiString; aIterations: Integer): string;
var
  lvSalt, lvKey: AnsiString;
begin
  // past the ceiling the record would mint here and never verify again
  if (aIterations < 1) or (aIterations > gcBpPasswordHashMaxIterations) then
    raise EbpPasswordHash.CreateFmt('BpHashPassword: iterations must be 1..%d',
      [gcBpPasswordHashMaxIterations]);
  lvSalt := BpGenerateSalt(gcBpPasswordHashSaltLen);
  lvKey := BpPBKDF2SHA256(aPassword, lvSalt, aIterations, gcBpPasswordHashKeyLen);
  Result := Format('$%s$%d$%s$%s', [gcBpPasswordHashScheme, aIterations,
    Base64Encode(lvSalt), Base64Encode(lvKey)]);
end;

function BpVerifyPassword(const aPassword: AnsiString; const aStored: string): Boolean;

  // pops the next $-terminated field off aRest; False when no separator remains
  function NextField(var aRest: string; out aField: string): Boolean;
  var
    lvPos: Integer;
  begin
    lvPos := Pos('$', aRest);
    Result := lvPos > 0;
    if Result then
    begin
      aField := Copy(aRest, 1, lvPos - 1);
      aRest := Copy(aRest, lvPos + 1, MaxInt);
    end;
  end;

var
  lvRest, lvScheme, lvIterStr: string;
  lvSaltB64, lvHashB64: string;
  lvSaltBytes, lvHashBytes: TBytes;
  lvSalt, lvHash, lvDerived: AnsiString;
  lvIterations: Integer;
begin
  Result := False;
  // above the early exits: Delphi 7 counts the implicit finalisation as a use
  lvSaltBytes := nil;
  lvHashBytes := nil;
  try
    // expected shape: $pbkdf2-sha256$<iterations>$<saltB64>$<hashB64>
    if (aStored = '') or (aStored[1] <> '$') then
      Exit;
    lvRest := Copy(aStored, 2, MaxInt);
    if not NextField(lvRest, lvScheme) then
      Exit;
    if lvScheme <> gcBpPasswordHashScheme then
      Exit;
    if not NextField(lvRest, lvIterStr) then
      Exit;
    if not NextField(lvRest, lvSaltB64) then
      Exit;
    // the hash is the final field; a fifth separator means a malformed record
    lvHashB64 := lvRest;
    if (lvHashB64 = '') or (Pos('$', lvHashB64) > 0) then
      Exit;
    lvIterations := StrToIntDef(lvIterStr, 0);
    if (lvIterations < 1) or (lvIterations > gcBpPasswordHashMaxIterations) then
      Exit;
    // Base64Decode raises on garbage; the except below turns that into False
    lvSaltBytes := Base64Decode(lvSaltB64);
    lvHashBytes := Base64Decode(lvHashB64);
    if Length(lvSaltBytes) = 0 then
      Exit;
    // a floor as well as a ceiling, or a cut-off record verifies by chance
    if (Length(lvHashBytes) < gcBpPasswordHashMinKeyLen) or
      (Length(lvHashBytes) > gcBpPasswordHashMaxKeyLen) then
      Exit;
    SetString(lvSalt, PAnsiChar(@lvSaltBytes[0]), Length(lvSaltBytes));
    SetString(lvHash, PAnsiChar(@lvHashBytes[0]), Length(lvHashBytes));
    lvDerived := BpPBKDF2SHA256(aPassword, lvSalt, lvIterations, Length(lvHash));
    Result := BpConstantTimeEquals(lvDerived, lvHash);
  except
    Result := False;
  end;
end;

end.
