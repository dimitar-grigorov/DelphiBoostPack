unit BpHMACSHA256;

// HMAC-SHA256 per RFC 2104 / FIPS 198-1, built on BpSHA256.
//
// HMAC is a keyed hash: only someone holding the shared secret can produce
// (or verify) the code, which is what API signature schemes use (AWS SigV4,
// webhook signatures, JWT HS256). Result = SHA256(opad || SHA256(ipad || msg))
// where ipad/opad are the key xor $36 / $5C; keys longer than the 64-byte
// block are hashed down first, shorter ones are zero-padded.
//
// Streaming like the hash classes: Create with the key, Update in chunks,
// Final; Final re-arms the instance for the next message with the same key.
// Class function one-shots cover the common string/bytes cases.
//
// Verified in the DUnit suite against the RFC 4231 test vectors and against
// a by-definition construction over BpSHA256 on random keys and messages.

interface

uses
  SysUtils, BpSHA256;

type
  TbpHMACSHA256 = class
  private
    FHasher: TbpSHA256;                // inner hash while streaming, outer in Final
    FInnerPad: array[0..63] of Byte;   // key xor $36
    FOuterPad: array[0..63] of Byte;   // key xor $5C
    procedure SetKey(const AKey; AKeySize: Integer);
  public
    constructor Create(const AKey; AKeySize: Integer); overload;
    constructor Create(const AKey: AnsiString); overload;
    constructor Create(const AKey: TBytes); overload;
    destructor Destroy; override;
    procedure Update(const AData; ASize: Integer); overload;
    procedure Update(const ABytes: TBytes); overload;
    procedure Update(const AText: AnsiString); overload;
    procedure Final(out ADigest: TbpSHA256Digest);
    class function Compute(const AKey, AText: AnsiString): TbpSHA256Digest; overload;
    class function Compute(const AKey, AData: TBytes): TbpSHA256Digest; overload;
    class function ComputeHex(const AKey, AText: AnsiString): string;
    class function ComputeBase64(const AKey, AText: AnsiString): string;
  end;

implementation

procedure TbpHMACSHA256.SetKey(const AKey; AKeySize: Integer);
var
  lvHashedKey: TbpSHA256Digest;
  lvKeyBytes: PByte;
  lvKeyLen, i: Integer;
begin
  lvKeyBytes := @AKey;
  lvKeyLen := AKeySize;
  // a key longer than the block is replaced by its hash (RFC 2104)
  if lvKeyLen > 64 then
  begin
    lvHashedKey := TbpSHA256.HashBuffer(AKey, AKeySize);
    lvKeyBytes := @lvHashedKey;
    lvKeyLen := SizeOf(lvHashedKey);
  end;
  // shorter keys are zero-padded to the block size by the xor below
  for i := 0 to 63 do
  begin
    if i < lvKeyLen then
    begin
      FInnerPad[i] := lvKeyBytes^ xor $36;
      FOuterPad[i] := lvKeyBytes^ xor $5C;
      Inc(lvKeyBytes);
    end
    else
    begin
      FInnerPad[i] := $36;
      FOuterPad[i] := $5C;
    end;
  end;
  // start the inner hash: SHA256(ipad || ...)
  FHasher.Update(FInnerPad, SizeOf(FInnerPad));
end;

constructor TbpHMACSHA256.Create(const AKey; AKeySize: Integer);
begin
  inherited Create;
  FHasher := TbpSHA256.Create;
  SetKey(AKey, AKeySize);
end;

constructor TbpHMACSHA256.Create(const AKey: AnsiString);
begin
  Create(PAnsiChar(AKey)^, Length(AKey));
end;

constructor TbpHMACSHA256.Create(const AKey: TBytes);
var
  lvDummy: Byte;
begin
  if Length(AKey) > 0 then
    Create(AKey[0], Length(AKey))
  else
  begin
    lvDummy := 0;
    Create(lvDummy, 0);
  end;
end;

destructor TbpHMACSHA256.Destroy;
begin
  // the pads hold key material, wipe them
  FillChar(FInnerPad, SizeOf(FInnerPad), 0);
  FillChar(FOuterPad, SizeOf(FOuterPad), 0);
  FHasher.Free;
  inherited Destroy;
end;

procedure TbpHMACSHA256.Update(const AData; ASize: Integer);
begin
  FHasher.Update(AData, ASize);
end;

procedure TbpHMACSHA256.Update(const ABytes: TBytes);
begin
  FHasher.Update(ABytes);
end;

procedure TbpHMACSHA256.Update(const AText: AnsiString);
begin
  FHasher.Update(AText);
end;

procedure TbpHMACSHA256.Final(out ADigest: TbpSHA256Digest);
var
  lvInnerDigest: TbpSHA256Digest;
begin
  // inner Final resets the hasher, so the same instance runs the outer pass
  FHasher.Final(lvInnerDigest);
  FHasher.Update(FOuterPad, SizeOf(FOuterPad));
  FHasher.Update(lvInnerDigest, SizeOf(lvInnerDigest));
  FHasher.Final(ADigest);
  // re-arm the inner hash for the next message with the same key
  FHasher.Update(FInnerPad, SizeOf(FInnerPad));
end;

class function TbpHMACSHA256.Compute(const AKey, AText: AnsiString): TbpSHA256Digest;
var
  lvHmac: TbpHMACSHA256;
begin
  lvHmac := TbpHMACSHA256.Create(AKey);
  try
    lvHmac.Update(AText);
    lvHmac.Final(Result);
  finally
    lvHmac.Free;
  end;
end;

class function TbpHMACSHA256.Compute(const AKey, AData: TBytes): TbpSHA256Digest;
var
  lvHmac: TbpHMACSHA256;
begin
  lvHmac := TbpHMACSHA256.Create(AKey);
  try
    lvHmac.Update(AData);
    lvHmac.Final(Result);
  finally
    lvHmac.Free;
  end;
end;

class function TbpHMACSHA256.ComputeHex(const AKey, AText: AnsiString): string;
begin
  Result := TbpSHA256.DigestToHex(Compute(AKey, AText));
end;

class function TbpHMACSHA256.ComputeBase64(const AKey, AText: AnsiString): string;
begin
  Result := TbpSHA256.DigestToBase64(Compute(AKey, AText));
end;

end.
