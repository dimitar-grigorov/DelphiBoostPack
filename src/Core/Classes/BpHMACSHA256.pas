unit BpHMACSHA256;

// HMAC-SHA256 (RFC 2104), built on BpSHA256, for keyed message
// authentication (API signatures, webhook verification, JWT HS256).
// Streaming like the hash classes: Create with the key, Update, Final;
// Final re-arms with the same key. One-shot class functions too.
// Key and text are raw bytes: UTF8Encode first, or a Unicode compiler signs
// the ANSI conversion instead of the bytes the peer signed.

interface

uses
  SysUtils, BpSHA256;

type
  TbpHMACSHA256 = class
  private
    FHasher: TbpSHA256;  // the message in progress, inner then outer
    FInner: TbpSHA256;   // key xor $36 already compressed, once per key
    FOuter: TbpSHA256;   // key xor $5C already compressed, once per key
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
  lvInnerPad, lvOuterPad: array[0..63] of Byte;
  lvKeyBytes: PByte;
  lvKeyLen, i: Integer;
begin
  // a negative size would leave the pads at $36/$5C, a MAC with no key in it
  if aKeySize < 0 then
    raise ERangeError.CreateFmt('SetKey: aKeySize %d is negative', [aKeySize]);
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
      lvInnerPad[i] := lvKeyBytes^ xor $36;
      lvOuterPad[i] := lvKeyBytes^ xor $5C;
      Inc(lvKeyBytes);
    end
    else
    begin
      lvInnerPad[i] := $36;
      lvOuterPad[i] := $5C;
    end;
  end;
  // each pad is a whole block and depends only on the key, so compress it once
  FInner.Update(lvInnerPad, SizeOf(lvInnerPad));
  FOuter.Update(lvOuterPad, SizeOf(lvOuterPad));
  FillChar(lvInnerPad, SizeOf(lvInnerPad), 0);
  FillChar(lvOuterPad, SizeOf(lvOuterPad), 0);
  FillChar(lvHashedKey, SizeOf(lvHashedKey), 0);
  FHasher.Assign(FInner);
end;

constructor TbpHMACSHA256.Create(const aKey; aKeySize: Integer);
begin
  inherited Create;
  FHasher := TbpSHA256.Create;
  FInner := TbpSHA256.Create;
  FOuter := TbpSHA256.Create;
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

// the pad midstates are key material, and TbpSHA256.Destroy wipes its own
destructor TbpHMACSHA256.Destroy;
begin
  FInner.Free;
  FOuter.Free;
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
  FHasher.Final(lvInnerDigest);
  // resuming from the pad midstates halves the compressions per message
  FHasher.Assign(FOuter);
  FHasher.Update(lvInnerDigest, SizeOf(lvInnerDigest));
  FHasher.Final(aDigest);
  // re-armed for the next message with the same key
  FHasher.Assign(FInner);
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
