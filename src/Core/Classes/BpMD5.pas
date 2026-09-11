unit BpMD5;

// MD5 (RFC 1321), pure Pascal, for Delphi 7/2007+. Same interface as
// BpSHA256: streaming Update plus one-shot class functions, hex or Base64.
// Broken for signatures; fine for checksums, ETags and fingerprints.
// The string overloads hash raw bytes: UTF8Encode first on Delphi 2009+, or
// the digest follows the machine's ANSI code page.

// hash arithmetic relies on Cardinal wraparound mod 2^32
{$Q-}
{$R-}

interface

uses
  SysUtils, BpCompat;

type
  TbpMD5Digest = array[0..15] of Byte;

  TbpMD5 = class
  private
    FHash: array[0..3] of Cardinal;
    FLenBits: Int64;
    FBuffer: array[0..63] of Byte;  // partial input block
    FIndex: Integer;                // filled bytes in FBuffer
    procedure Compress(aData: PByteArray);
  public
    constructor Create;
    // resets to a fresh hash; Final calls it automatically
    procedure Init;
    procedure Update(const aData; aSize: Integer); overload;
    procedure Update(const aBytes: TBytes); overload;
    procedure Update(const aText: AnsiString); overload;
    procedure Final(out aDigest: TbpMD5Digest);
    class function HashBuffer(const aData; aSize: Integer): TbpMD5Digest;
    class function HashBytes(const aBytes: TBytes): TbpMD5Digest;
    class function HashStr(const aText: AnsiString): TbpMD5Digest;
    class function HashFile(const aFileName: string): TbpMD5Digest;
    class function HashStrHex(const aText: AnsiString): string;
    class function HashFileHex(const aFileName: string): string;
    class function DigestToHex(const aDigest: TbpMD5Digest): string;
    class function DigestToBase64(const aDigest: TbpMD5Digest): string;
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

procedure TbpMD5.Compress(aData: PByteArray);
var
  lvW: array[0..15] of Cardinal;
  lvA, lvB, lvC, lvD, lvF, lvX, lvTemp: Cardinal;
  i, lvK, lvS: Integer;
begin
  // 16 little-endian input words
  for i := 0 to 15 do
    lvW[i] := Cardinal(aData[i * 4]) or (Cardinal(aData[i * 4 + 1]) shl 8) or
              (Cardinal(aData[i * 4 + 2]) shl 16) or (Cardinal(aData[i * 4 + 3]) shl 24);
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

procedure TbpMD5.Update(const aData; aSize: Integer);
var
  lvSource: PByte;
  lvFree: Integer;
begin
  if aSize <= 0 then
    Exit;
  lvSource := @aData;
  Inc(FLenBits, Int64(aSize) * 8);
  // top up a partially filled block first
  if FIndex > 0 then
  begin
    lvFree := 64 - FIndex;
    if lvFree > aSize then
    begin
      Move(lvSource^, FBuffer[FIndex], aSize);
      Inc(FIndex, aSize);
      Exit;
    end;
    Move(lvSource^, FBuffer[FIndex], lvFree);
    Compress(@FBuffer);
    FIndex := 0;
    Inc(lvSource, lvFree);
    Dec(aSize, lvFree);
  end;
  // full blocks compress straight from the source, no copy
  while aSize >= 64 do
  begin
    Compress(PByteArray(lvSource));
    Inc(lvSource, 64);
    Dec(aSize, 64);
  end;
  if aSize > 0 then
  begin
    Move(lvSource^, FBuffer[0], aSize);
    FIndex := aSize;
  end;
end;

procedure TbpMD5.Update(const aBytes: TBytes);
begin
  if Length(aBytes) > 0 then
    Update(aBytes[0], Length(aBytes));
end;

procedure TbpMD5.Update(const aText: AnsiString);
begin
  if aText <> '' then
    Update(PAnsiChar(aText)^, Length(aText));
end;

procedure TbpMD5.Final(out aDigest: TbpMD5Digest);
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
    aDigest[i * 4] := Byte(FHash[i]);
    aDigest[i * 4 + 1] := Byte(FHash[i] shr 8);
    aDigest[i * 4 + 2] := Byte(FHash[i] shr 16);
    aDigest[i * 4 + 3] := Byte(FHash[i] shr 24);
  end;
  // wipe the state, ready for the next message
  Init;
end;

class function TbpMD5.HashBuffer(const aData; aSize: Integer): TbpMD5Digest;
var
  lvHasher: TbpMD5;
begin
  lvHasher := TbpMD5.Create;
  try
    lvHasher.Update(aData, aSize);
    lvHasher.Final(Result);
  finally
    lvHasher.Free;
  end;
end;

class function TbpMD5.HashBytes(const aBytes: TBytes): TbpMD5Digest;
var
  lvDummy: Byte;
begin
  if Length(aBytes) > 0 then
    Result := HashBuffer(aBytes[0], Length(aBytes))
  else
  begin
    lvDummy := 0;
    Result := HashBuffer(lvDummy, 0);  // any address works for a zero-length hash
  end;
end;

class function TbpMD5.HashStr(const aText: AnsiString): TbpMD5Digest;
begin
  Result := HashBuffer(PAnsiChar(aText)^, Length(aText));
end;

class function TbpMD5.HashFile(const aFileName: string): TbpMD5Digest;
var
  lvStream: TFileStream;
  lvHasher: TbpMD5;
  lvChunk: TBytes;
  lvRead: Integer;
  lvTotal, lvSize: Int64;
begin
  lvStream := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyWrite);
  try
    lvSize := lvStream.Size;
    lvHasher := TbpMD5.Create;
    try
      SetLength(lvChunk, gcMd5FileChunkSize);
      lvTotal := 0;
      repeat
        lvRead := lvStream.Read(lvChunk[0], gcMd5FileChunkSize);
        if lvRead > 0 then
        begin
          lvHasher.Update(lvChunk[0], lvRead);
          Inc(lvTotal, lvRead);
        end;
      until lvRead <= 0;
      // a short read is an I/O error, not the end of the file
      if lvTotal <> lvSize then
        raise EReadError.CreateFmt('MD5: read %d of %d bytes from %s',
          [lvTotal, lvSize, aFileName]);
      lvHasher.Final(Result);
    finally
      lvHasher.Free;
    end;
  finally
    lvStream.Free;
  end;
end;

class function TbpMD5.HashStrHex(const aText: AnsiString): string;
begin
  Result := DigestToHex(HashStr(aText));
end;

class function TbpMD5.HashFileHex(const aFileName: string): string;
begin
  Result := DigestToHex(HashFile(aFileName));
end;

class function TbpMD5.DigestToHex(const aDigest: TbpMD5Digest): string;
var
  i: Integer;
begin
  SetLength(Result, SizeOf(aDigest) * 2);
  for i := 0 to High(aDigest) do
  begin
    Result[i * 2 + 1] := gcMd5HexDigits[(aDigest[i] shr 4) + 1];
    Result[i * 2 + 2] := gcMd5HexDigits[(aDigest[i] and $0F) + 1];
  end;
end;

class function TbpMD5.DigestToBase64(const aDigest: TbpMD5Digest): string;
begin
  Result := Base64Encode(aDigest, SizeOf(aDigest));
end;

end.
