unit BpSHA256;

// SHA-256 per FIPS 180-4, pure Pascal, for Delphi 7/2007 and later.
//
// Streaming interface (Create or Init, Update in chunks, Final) so large
// inputs such as files never need to fit in memory; class function one-shots
// cover the common buffer/bytes/string/file cases with hex or Base64 output.
// Update compresses full 64-byte blocks straight from the caller's buffer
// (the partial-block copy only happens at chunk boundaries), Final resets the
// state so an instance can be reused for the next message.
//
// Verified in the DUnit suite against the FIPS 180-4 known-answer vectors
// (including the one-million-'a' streaming vector) and cross-checked against
// Windows CryptoAPI on random data.

// hash arithmetic relies on Cardinal wraparound mod 2^32
{$Q-}
{$R-}

interface

uses
  SysUtils;

type
  TbpSHA256Digest = array[0..31] of Byte;

  TbpSHA256 = class
  private
    FHash: array[0..7] of Cardinal;
    FLenBits: Int64;
    FBuffer: array[0..63] of Byte;  // partial input block
    FIndex: Integer;                // filled bytes in FBuffer
    procedure Compress(AData: PByteArray);
  public
    constructor Create;
    // resets to a fresh hash; Final calls it automatically
    procedure Init;
    procedure Update(const AData; ASize: Integer); overload;
    procedure Update(const ABytes: TBytes); overload;
    procedure Update(const AText: AnsiString); overload;
    procedure Final(out ADigest: TbpSHA256Digest);
    class function HashBuffer(const AData; ASize: Integer): TbpSHA256Digest;
    class function HashBytes(const ABytes: TBytes): TbpSHA256Digest;
    class function HashStr(const AText: AnsiString): TbpSHA256Digest;
    class function HashFile(const AFileName: string): TbpSHA256Digest;
    class function HashStrHex(const AText: AnsiString): string;
    class function HashFileHex(const AFileName: string): string;
    class function DigestToHex(const ADigest: TbpSHA256Digest): string;
    class function DigestToBase64(const ADigest: TbpSHA256Digest): string;
  end;

implementation

uses
  Classes, BpBase64;

const
  // FIPS 180-4 round constants: fractional parts of the cube roots of the first 64 primes
  gcK: array[0..63] of Cardinal = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5,
    $D807AA98, $12835B01, $243185BE, $550C7DC3, $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174,
    $E49B69C1, $EFBE4786, $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13, $650A7354, $766A0ABB, $81C2C92E, $92722C85,
    $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A, $5B9CCA4F, $682E6FF3,
    $748F82EE, $78A5636F, $84C87814, $8CC70208, $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);
  gcShaHexDigits = '0123456789abcdef';
  gcShaFileChunkSize = 64 * 1024;

constructor TbpSHA256.Create;
begin
  inherited Create;
  Init;
end;

procedure TbpSHA256.Init;
begin
  // FIPS 180-4 initial hash: fractional parts of the square roots of the first 8 primes
  FHash[0] := $6A09E667;
  FHash[1] := $BB67AE85;
  FHash[2] := $3C6EF372;
  FHash[3] := $A54FF53A;
  FHash[4] := $510E527F;
  FHash[5] := $9B05688C;
  FHash[6] := $1F83D9AB;
  FHash[7] := $5BE0CD19;
  FLenBits := 0;
  FIndex := 0;
  FillChar(FBuffer, SizeOf(FBuffer), 0);
end;

procedure TbpSHA256.Compress(AData: PByteArray);
var
  lvW: array[0..63] of Cardinal;
  lvA, lvB, lvC, lvD, lvE, lvF, lvG, lvH: Cardinal;
  lvT1, lvT2, lvX: Cardinal;
  i: Integer;
begin
  // message schedule: 16 big-endian input words expanded to 64
  for i := 0 to 15 do
    lvW[i] := (Cardinal(AData[i * 4]) shl 24) or (Cardinal(AData[i * 4 + 1]) shl 16) or
              (Cardinal(AData[i * 4 + 2]) shl 8) or Cardinal(AData[i * 4 + 3]);
  for i := 16 to 63 do
  begin
    lvX := lvW[i - 2];
    lvT1 := ((lvX shr 17) or (lvX shl 15)) xor ((lvX shr 19) or (lvX shl 13)) xor (lvX shr 10);
    lvX := lvW[i - 15];
    lvT2 := ((lvX shr 7) or (lvX shl 25)) xor ((lvX shr 18) or (lvX shl 14)) xor (lvX shr 3);
    lvW[i] := lvT1 + lvW[i - 7] + lvT2 + lvW[i - 16];
  end;
  lvA := FHash[0];
  lvB := FHash[1];
  lvC := FHash[2];
  lvD := FHash[3];
  lvE := FHash[4];
  lvF := FHash[5];
  lvG := FHash[6];
  lvH := FHash[7];
  // 64 compression rounds; rotates spelled as shr/shl pairs (no ror intrinsic in D2007)
  for i := 0 to 63 do
  begin
    lvT1 := lvH + (((lvE shr 6) or (lvE shl 26)) xor ((lvE shr 11) or (lvE shl 21)) xor
      ((lvE shr 25) or (lvE shl 7))) + ((lvE and lvF) xor (not lvE and lvG)) + gcK[i] + lvW[i];
    lvT2 := (((lvA shr 2) or (lvA shl 30)) xor ((lvA shr 13) or (lvA shl 19)) xor
      ((lvA shr 22) or (lvA shl 10))) + ((lvA and lvB) xor (lvA and lvC) xor (lvB and lvC));
    lvH := lvG;
    lvG := lvF;
    lvF := lvE;
    lvE := lvD + lvT1;
    lvD := lvC;
    lvC := lvB;
    lvB := lvA;
    lvA := lvT1 + lvT2;
  end;
  Inc(FHash[0], lvA);
  Inc(FHash[1], lvB);
  Inc(FHash[2], lvC);
  Inc(FHash[3], lvD);
  Inc(FHash[4], lvE);
  Inc(FHash[5], lvF);
  Inc(FHash[6], lvG);
  Inc(FHash[7], lvH);
end;

procedure TbpSHA256.Update(const AData; ASize: Integer);
var
  lvSource: PByte;
  lvFree: Integer;
begin
  if ASize <= 0 then
    Exit;
  lvSource := @AData;
  Inc(FLenBits, Int64(ASize) * 8);
  // top up a partially filled block first
  if FIndex > 0 then
  begin
    lvFree := 64 - FIndex;
    if lvFree > ASize then
    begin
      Move(lvSource^, FBuffer[FIndex], ASize);
      Inc(FIndex, ASize);
      Exit;
    end;
    Move(lvSource^, FBuffer[FIndex], lvFree);
    Compress(@FBuffer);
    FIndex := 0;
    Inc(lvSource, lvFree);
    Dec(ASize, lvFree);
  end;
  // full blocks compress straight from the source, no copy
  while ASize >= 64 do
  begin
    Compress(PByteArray(lvSource));
    Inc(lvSource, 64);
    Dec(ASize, 64);
  end;
  if ASize > 0 then
  begin
    Move(lvSource^, FBuffer[0], ASize);
    FIndex := ASize;
  end;
end;

procedure TbpSHA256.Update(const ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    Update(ABytes[0], Length(ABytes));
end;

procedure TbpSHA256.Update(const AText: AnsiString);
begin
  if AText <> '' then
    Update(PAnsiChar(AText)^, Length(AText));
end;

procedure TbpSHA256.Final(out ADigest: TbpSHA256Digest);
var
  lvBits: Int64;
  i: Integer;
begin
  lvBits := FLenBits;
  // pad: a single 1 bit, zeros, then the 64-bit big-endian message bit length
  FBuffer[FIndex] := $80;
  if FIndex < 63 then
    FillChar(FBuffer[FIndex + 1], 63 - FIndex, 0);
  if FIndex >= 56 then
  begin
    // no room for the length in this block, it goes into an extra one
    Compress(@FBuffer);
    FillChar(FBuffer, SizeOf(FBuffer), 0);
  end;
  for i := 0 to 7 do
    FBuffer[63 - i] := Byte(lvBits shr (8 * i));
  Compress(@FBuffer);
  // digest is the hash words in big-endian byte order
  for i := 0 to 7 do
  begin
    ADigest[i * 4] := Byte(FHash[i] shr 24);
    ADigest[i * 4 + 1] := Byte(FHash[i] shr 16);
    ADigest[i * 4 + 2] := Byte(FHash[i] shr 8);
    ADigest[i * 4 + 3] := Byte(FHash[i]);
  end;
  // wipe the state, ready for the next message
  Init;
end;

class function TbpSHA256.HashBuffer(const AData; ASize: Integer): TbpSHA256Digest;
var
  lvHasher: TbpSHA256;
begin
  lvHasher := TbpSHA256.Create;
  try
    lvHasher.Update(AData, ASize);
    lvHasher.Final(Result);
  finally
    lvHasher.Free;
  end;
end;

class function TbpSHA256.HashBytes(const ABytes: TBytes): TbpSHA256Digest;
var
  lvDummy: Byte;
begin
  if Length(ABytes) > 0 then
    Result := HashBuffer(ABytes[0], Length(ABytes))
  else
  begin
    lvDummy := 0;
    Result := HashBuffer(lvDummy, 0);  // any address works for a zero-length hash
  end;
end;

class function TbpSHA256.HashStr(const AText: AnsiString): TbpSHA256Digest;
begin
  Result := HashBuffer(PAnsiChar(AText)^, Length(AText));
end;

class function TbpSHA256.HashFile(const AFileName: string): TbpSHA256Digest;
var
  lvStream: TFileStream;
  lvHasher: TbpSHA256;
  lvChunk: TBytes;
  lvRead: Integer;
begin
  lvStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    lvHasher := TbpSHA256.Create;
    try
      SetLength(lvChunk, gcShaFileChunkSize);
      repeat
        lvRead := lvStream.Read(lvChunk[0], gcShaFileChunkSize);
        if lvRead > 0 then
          lvHasher.Update(lvChunk[0], lvRead);
      until lvRead <= 0;
      lvHasher.Final(Result);
    finally
      lvHasher.Free;
    end;
  finally
    lvStream.Free;
  end;
end;

class function TbpSHA256.HashStrHex(const AText: AnsiString): string;
begin
  Result := DigestToHex(HashStr(AText));
end;

class function TbpSHA256.HashFileHex(const AFileName: string): string;
begin
  Result := DigestToHex(HashFile(AFileName));
end;

class function TbpSHA256.DigestToHex(const ADigest: TbpSHA256Digest): string;
var
  i: Integer;
begin
  SetLength(Result, SizeOf(ADigest) * 2);
  for i := 0 to High(ADigest) do
  begin
    Result[i * 2 + 1] := gcShaHexDigits[(ADigest[i] shr 4) + 1];
    Result[i * 2 + 2] := gcShaHexDigits[(ADigest[i] and $0F) + 1];
  end;
end;

class function TbpSHA256.DigestToBase64(const ADigest: TbpSHA256Digest): string;
begin
  Result := Base64Encode(ADigest, SizeOf(ADigest));
end;

end.
