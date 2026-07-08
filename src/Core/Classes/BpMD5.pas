unit BpMD5;

// MD5 per RFC 1321, pure Pascal, for Delphi 7/2007 and later.
//
// Same interface as BpSHA256: streaming (Create or Init, Update in chunks,
// Final) plus class function one-shots for buffer/bytes/string/file with hex
// or Base64 output. MD5 is cryptographically broken for signatures but stays
// useful for legacy checksums, ETags and content fingerprints.
//
// Verified in the DUnit suite against the RFC 1321 test vectors and
// cross-checked against Windows CryptoAPI on random data.

// hash arithmetic relies on Cardinal wraparound mod 2^32
{$Q-}
{$R-}

interface

uses
  SysUtils;

type
  TbpMD5Digest = array[0..15] of Byte;

  TbpMD5 = class
  private
    FHash: array[0..3] of Cardinal;
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
    procedure Final(out ADigest: TbpMD5Digest);
    class function HashBuffer(const AData; ASize: Integer): TbpMD5Digest;
    class function HashBytes(const ABytes: TBytes): TbpMD5Digest;
    class function HashStr(const AText: AnsiString): TbpMD5Digest;
    class function HashFile(const AFileName: string): TbpMD5Digest;
    class function HashStrHex(const AText: AnsiString): string;
    class function HashFileHex(const AFileName: string): string;
    class function DigestToHex(const ADigest: TbpMD5Digest): string;
    class function DigestToBase64(const ADigest: TbpMD5Digest): string;
  end;

implementation

uses
  Classes, BpBase64;

const
  // RFC 1321 sine table: T[i] = floor(2^32 * abs(sin(i + 1)))
  gcT: array[0..63] of Cardinal = (
    $D76AA478, $E8C7B756, $242070DB, $C1BDCEEE, $F57C0FAF, $4787C62A, $A8304613, $FD469501,
    $698098D8, $8B44F7AF, $FFFF5BB1, $895CD7BE, $6B901122, $FD987193, $A679438E, $49B40821,
    $F61E2562, $C040B340, $265E5A51, $E9B6C7AA, $D62F105D, $02441453, $D8A1E681, $E7D3FBC8,
    $21E1CDE6, $C33707D6, $F4D50D87, $455A14ED, $A9E3E905, $FCEFA3F8, $676F02D9, $8D2A4C8A,
    $FFFA3942, $8771F681, $6D9D6122, $FDE5380C, $A4BEEA44, $4BDECFA9, $F6BB4B60, $BEBFBC70,
    $289B7EC6, $EAA127FA, $D4EF3085, $04881D05, $D9D4D039, $E6DB99E5, $1FA27CF8, $C4AC5665,
    $F4292244, $432AFF97, $AB9423A7, $FC93A039, $655B59C3, $8F0CCC92, $FFEFF47D, $85845DD1,
    $6FA87E4F, $FE2CE6E0, $A3014314, $4E0811A1, $F7537E82, $BD3AF235, $2AD7D2BB, $EB86D391);
  // per-round left-rotation amounts, one row per round group
  gcShifts: array[0..3, 0..3] of Byte = (
    (7, 12, 17, 22), (5, 9, 14, 20), (4, 11, 16, 23), (6, 10, 15, 21));
  gcMd5HexDigits = '0123456789abcdef';
  gcMd5FileChunkSize = 64 * 1024;

constructor TbpMD5.Create;
begin
  inherited Create;
  Init;
end;

procedure TbpMD5.Init;
begin
  // RFC 1321 initial state
  FHash[0] := $67452301;
  FHash[1] := $EFCDAB89;
  FHash[2] := $98BADCFE;
  FHash[3] := $10325476;
  FLenBits := 0;
  FIndex := 0;
  FillChar(FBuffer, SizeOf(FBuffer), 0);
end;

procedure TbpMD5.Compress(AData: PByteArray);
var
  lvW: array[0..15] of Cardinal;
  lvA, lvB, lvC, lvD, lvF, lvX, lvTemp: Cardinal;
  i, lvK, lvS: Integer;
begin
  // 16 little-endian input words
  for i := 0 to 15 do
    lvW[i] := Cardinal(AData[i * 4]) or (Cardinal(AData[i * 4 + 1]) shl 8) or
              (Cardinal(AData[i * 4 + 2]) shl 16) or (Cardinal(AData[i * 4 + 3]) shl 24);
  lvA := FHash[0];
  lvB := FHash[1];
  lvC := FHash[2];
  lvD := FHash[3];
  // 64 rounds in 4 groups; each group has its own mix function and word order
  for i := 0 to 63 do
  begin
    if i < 16 then
    begin
      lvF := (lvB and lvC) or (not lvB and lvD);
      lvK := i;
    end
    else if i < 32 then
    begin
      lvF := (lvD and lvB) or (not lvD and lvC);
      lvK := (5 * i + 1) and 15;
    end
    else if i < 48 then
    begin
      lvF := lvB xor lvC xor lvD;
      lvK := (3 * i + 5) and 15;
    end
    else
    begin
      lvF := lvC xor (lvB or not lvD);
      lvK := (7 * i) and 15;
    end;
    lvS := gcShifts[i shr 4, i and 3];
    lvTemp := lvD;
    lvD := lvC;
    lvC := lvB;
    lvX := lvA + lvF + gcT[i] + lvW[lvK];
    lvB := lvB + ((lvX shl lvS) or (lvX shr (32 - lvS)));
    lvA := lvTemp;
  end;
  Inc(FHash[0], lvA);
  Inc(FHash[1], lvB);
  Inc(FHash[2], lvC);
  Inc(FHash[3], lvD);
end;

procedure TbpMD5.Update(const AData; ASize: Integer);
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

procedure TbpMD5.Update(const ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    Update(ABytes[0], Length(ABytes));
end;

procedure TbpMD5.Update(const AText: AnsiString);
begin
  if AText <> '' then
    Update(PAnsiChar(AText)^, Length(AText));
end;

procedure TbpMD5.Final(out ADigest: TbpMD5Digest);
var
  lvBits: Int64;
  i: Integer;
begin
  lvBits := FLenBits;
  // pad: a single 1 bit, zeros, then the 64-bit little-endian message bit length
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
    FBuffer[56 + i] := Byte(lvBits shr (8 * i));
  Compress(@FBuffer);
  // digest is the state words in little-endian byte order
  for i := 0 to 3 do
  begin
    ADigest[i * 4] := Byte(FHash[i]);
    ADigest[i * 4 + 1] := Byte(FHash[i] shr 8);
    ADigest[i * 4 + 2] := Byte(FHash[i] shr 16);
    ADigest[i * 4 + 3] := Byte(FHash[i] shr 24);
  end;
  // wipe the state, ready for the next message
  Init;
end;

class function TbpMD5.HashBuffer(const AData; ASize: Integer): TbpMD5Digest;
var
  lvHasher: TbpMD5;
begin
  lvHasher := TbpMD5.Create;
  try
    lvHasher.Update(AData, ASize);
    lvHasher.Final(Result);
  finally
    lvHasher.Free;
  end;
end;

class function TbpMD5.HashBytes(const ABytes: TBytes): TbpMD5Digest;
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

class function TbpMD5.HashStr(const AText: AnsiString): TbpMD5Digest;
begin
  Result := HashBuffer(PAnsiChar(AText)^, Length(AText));
end;

class function TbpMD5.HashFile(const AFileName: string): TbpMD5Digest;
var
  lvStream: TFileStream;
  lvHasher: TbpMD5;
  lvChunk: TBytes;
  lvRead: Integer;
begin
  lvStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    lvHasher := TbpMD5.Create;
    try
      SetLength(lvChunk, gcMd5FileChunkSize);
      repeat
        lvRead := lvStream.Read(lvChunk[0], gcMd5FileChunkSize);
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

class function TbpMD5.HashStrHex(const AText: AnsiString): string;
begin
  Result := DigestToHex(HashStr(AText));
end;

class function TbpMD5.HashFileHex(const AFileName: string): string;
begin
  Result := DigestToHex(HashFile(AFileName));
end;

class function TbpMD5.DigestToHex(const ADigest: TbpMD5Digest): string;
var
  i: Integer;
begin
  SetLength(Result, SizeOf(ADigest) * 2);
  for i := 0 to High(ADigest) do
  begin
    Result[i * 2 + 1] := gcMd5HexDigits[(ADigest[i] shr 4) + 1];
    Result[i * 2 + 2] := gcMd5HexDigits[(ADigest[i] and $0F) + 1];
  end;
end;

class function TbpMD5.DigestToBase64(const ADigest: TbpMD5Digest): string;
begin
  Result := Base64Encode(ADigest, SizeOf(ADigest));
end;

end.
