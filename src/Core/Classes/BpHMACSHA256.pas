unit BpHMACSHA256;

// HMAC-SHA256 (RFC 2104), built on BpSHA256, for keyed message
// authentication (API signatures, webhook verification, JWT HS256).
// Streaming like the hash classes: Create with the key, Update, Final;
// Final re-arms with the same key. One-shot class functions too.

interface

uses
  SysUtils, BpSHA256, BpCompat;

type
  TbpHMACSHA256 = class
  private
    FHasher: TbpSHA256;                // inner hash while streaming, outer in Final
    FInnerPad: array[0..63] of Byte;   // key xor $36
    FOuterPad: array[0..63] of Byte;   // key xor $5C
    procedure SetKey(const aKey; aKeySize: Integer);
  public
    constructor Create(const aKey; aKeySize: Integer); overload;
    constructor Create(const aKey: AnsiString); overload;
    constructor Create(const aKey: TBytes); overload;
    destructor Destroy; override;
    procedure Update(const aData; aSize: Integer); overload;
    procedure Update(const aBytes: TBytes); overload;
    procedure Update(const aText: AnsiString); overload;
    procedure Final(out aDigest: TbpSHA256Digest);
    class function Compute(const aKey, aText: AnsiString): TbpSHA256Digest; overload;
    class function Compute(const aKey, aData: TBytes): TbpSHA256Digest; overload;
    class function ComputeHex(const aKey, aText: AnsiString): string;
    class function ComputeBase64(const aKey, aText: AnsiString): string;
  end;

implementation

procedure TbpHMACSHA256.SetKey(const aKey; aKeySize: Integer);
var
  lvHashedKey: TbpSHA256Digest;
  lvKeyBytes: PByte;
  lvKeyLen, i: Integer;
begin
  lvKeyBytes := @aKey;
  lvKeyLen := aKeySize;
  // a key longer than the block is replaced by its hash (RFC 2104)
  if lvKeyLen > 64 then
  begin
    lvHashedKey := TbpSHA256.HashBuffer(aKey, aKeySize);
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

constructor TbpHMACSHA256.Create(const aKey; aKeySize: Integer);
begin
  inherited Create;
  FHasher := TbpSHA256.Create;
  SetKey(aKey, aKeySize);
end;

constructor TbpHMACSHA256.Create(const aKey: AnsiString);
begin
  Create(PAnsiChar(aKey)^, Length(aKey));
end;

constructor TbpHMACSHA256.Create(const aKey: TBytes);
var
  lvDummy: Byte;
begin
  if Length(aKey) > 0 then
    Create(aKey[0], Length(aKey))
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

procedure TbpHMACSHA256.Update(const aData; aSize: Integer);
begin
  FHasher.Update(aData, aSize);
end;

procedure TbpHMACSHA256.Update(const aBytes: TBytes);
begin
  FHasher.Update(aBytes);
end;

procedure TbpHMACSHA256.Update(const aText: AnsiString);
begin
  FHasher.Update(aText);
end;

procedure TbpHMACSHA256.Final(out aDigest: TbpSHA256Digest);
var
  lvInnerDigest: TbpSHA256Digest;
begin
  // inner Final resets the hasher, so the same instance runs the outer pass
  FHasher.Final(lvInnerDigest);
  FHasher.Update(FOuterPad, SizeOf(FOuterPad));
  FHasher.Update(lvInnerDigest, SizeOf(lvInnerDigest));
  FHasher.Final(aDigest);
  // re-arm the inner hash for the next message with the same key
  FHasher.Update(FInnerPad, SizeOf(FInnerPad));
end;

class function TbpHMACSHA256.Compute(const aKey, aText: AnsiString): TbpSHA256Digest;
var
  lvHmac: TbpHMACSHA256;
begin
  lvHmac := TbpHMACSHA256.Create(aKey);
  try
    lvHmac.Update(aText);
    lvHmac.Final(Result);
  finally
    lvHmac.Free;
  end;
end;

class function TbpHMACSHA256.Compute(const aKey, aData: TBytes): TbpSHA256Digest;
var
  lvHmac: TbpHMACSHA256;
begin
  lvHmac := TbpHMACSHA256.Create(aKey);
  try
    lvHmac.Update(aData);
    lvHmac.Final(Result);
  finally
    lvHmac.Free;
  end;
end;

class function TbpHMACSHA256.ComputeHex(const aKey, aText: AnsiString): string;
begin
  Result := TbpSHA256.DigestToHex(Compute(aKey, aText));
end;

class function TbpHMACSHA256.ComputeBase64(const aKey, aText: AnsiString): string;
begin
  Result := TbpSHA256.DigestToBase64(Compute(aKey, aText));
end;

end.
