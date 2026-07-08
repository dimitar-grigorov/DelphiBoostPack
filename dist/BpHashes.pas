unit BpHashes;

// BpHashes.pas - GENERATED FILE, DO NOT EDIT.
// Single-file bundle amalgamated from the DelphiBoostPack modular units:
//   src\Core\Units\BpBase64.pas
//   src\Core\Classes\BpSHA256.pas
//   src\Core\Classes\BpMD5.pas
//   src\Core\Classes\BpHMACSHA256.pas
// Source commit 0b8d571, generated 2026-07-08 by tools\Amalgamate.ps1.
// Fix bugs in the modular units, then regenerate with:
//   powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1
// Notes:
// - use at most one bundle per project; two bundles embedding the same
//   helper unit would declare duplicate identifiers
// - unit-wide compiler directives of embedded units (e.g. {$Q-} in the
//   hash units) apply from their position to the end of this file

interface

uses
  SysUtils, Classes;

// ==================================================================
// BpBase64.pas - interface
// ==================================================================

// Base64 encode/decode per RFC 4648, standard and url-safe alphabets.
// Encoding computes the exact output size and builds the result with a single
// allocation. Standard encode pads with '='; Base64url encode omits padding
// (the common form in tokens, e.g. JWT).
// Decoding uses one shared reverse lookup table that accepts both alphabets,
// tolerates missing padding and skips whitespace (so MIME output with CRLF
// line breaks decodes fine). Any other character raises EbpBase64.

type
  EbpBase64 = class(Exception);

function Base64Encode(const AData; ASize: Integer): string; overload;
function Base64Encode(const ABytes: TBytes): string; overload;
function Base64Encode(const AText: AnsiString): string; overload;
function Base64UrlEncode(const AData; ASize: Integer): string; overload;
function Base64UrlEncode(const ABytes: TBytes): string; overload;
function Base64UrlEncode(const AText: AnsiString): string; overload;
function Base64Decode(const ABase64: string): TBytes;
function Base64DecodeStr(const ABase64: string): AnsiString;

// ==================================================================
// BpSHA256.pas - interface
// ==================================================================

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

// ==================================================================
// BpMD5.pas - interface
// ==================================================================

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

// ==================================================================
// BpHMACSHA256.pas - interface
// ==================================================================

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

// ==================================================================
// BpBase64.pas - implementation
// ==================================================================

const
  gcBase64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  gcBase64UrlChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  // reverse table markers
  gcInvalid = -1;
  gcWhitespace = -2;
  gcPadding = -3;

var
  gvDecodeTable: array[0..255] of ShortInt;

procedure InitDecodeTable;
var
  i: Integer;
begin
  for i := 0 to 255 do
    gvDecodeTable[i] := gcInvalid;
  for i := 1 to 64 do
    gvDecodeTable[Ord(gcBase64Chars[i])] := i - 1;
  // url-safe alphabet decodes with the same table
  gvDecodeTable[Ord('-')] := 62;
  gvDecodeTable[Ord('_')] := 63;
  gvDecodeTable[9] := gcWhitespace;
  gvDecodeTable[10] := gcWhitespace;
  gvDecodeTable[13] := gcWhitespace;
  gvDecodeTable[32] := gcWhitespace;
  gvDecodeTable[Ord('=')] := gcPadding;
end;

function EncodeBuffer(ASource: PByte; ASize: Integer; const AAlphabet: string;
  APadded: Boolean): string;
var
  lvDest: PChar;
  lvB0, lvB1, lvB2: Byte;
  lvFull, lvRest, lvOutLen, i: Integer;
begin
  Result := '';
  if ASize <= 0 then
    Exit;
  lvFull := ASize div 3;
  lvRest := ASize mod 3;
  lvOutLen := lvFull * 4;
  if lvRest > 0 then
  begin
    if APadded then
      Inc(lvOutLen, 4)
    else
      Inc(lvOutLen, lvRest + 1);
  end;
  SetLength(Result, lvOutLen);
  lvDest := Pointer(Result);
  for i := 1 to lvFull do
  begin
    lvB0 := ASource^; Inc(ASource);
    lvB1 := ASource^; Inc(ASource);
    lvB2 := ASource^; Inc(ASource);
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := AAlphabet[(((lvB1 and $0F) shl 2) or (lvB2 shr 6)) + 1];
    lvDest[3] := AAlphabet[(lvB2 and $3F) + 1];
    Inc(lvDest, 4);
  end;
  if lvRest = 1 then
  begin
    lvB0 := ASource^;
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[((lvB0 and $03) shl 4) + 1];
    if APadded then
    begin
      lvDest[2] := '=';
      lvDest[3] := '=';
    end;
  end
  else if lvRest = 2 then
  begin
    lvB0 := ASource^; Inc(ASource);
    lvB1 := ASource^;
    lvDest[0] := AAlphabet[(lvB0 shr 2) + 1];
    lvDest[1] := AAlphabet[(((lvB0 and $03) shl 4) or (lvB1 shr 4)) + 1];
    lvDest[2] := AAlphabet[((lvB1 and $0F) shl 2) + 1];
    if APadded then
      lvDest[3] := '=';
  end;
end;

function Base64Encode(const AData; ASize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@AData), ASize, gcBase64Chars, True);
end;

function Base64Encode(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@ABytes[0], Length(ABytes), gcBase64Chars, True);
end;

function Base64Encode(const AText: AnsiString): string;
begin
  if AText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(AText), Length(AText), gcBase64Chars, True);
end;

function Base64UrlEncode(const AData; ASize: Integer): string;
begin
  Result := EncodeBuffer(PByte(@AData), ASize, gcBase64UrlChars, False);
end;

function Base64UrlEncode(const ABytes: TBytes): string;
begin
  if Length(ABytes) = 0 then
    Result := ''
  else
    Result := EncodeBuffer(@ABytes[0], Length(ABytes), gcBase64UrlChars, False);
end;

function Base64UrlEncode(const AText: AnsiString): string;
begin
  if AText = '' then
    Result := ''
  else
    Result := EncodeBuffer(Pointer(AText), Length(AText), gcBase64UrlChars, False);
end;

function Base64Decode(const ABase64: string): TBytes;
var
  lvLen, lvOutPos, lvAccum, lvGroup, i: Integer;
  lvCode: ShortInt;
  lvCh: Char;
  lvSeenPad: Boolean;
begin
  Result := nil;
  lvLen := Length(ABase64);
  if lvLen = 0 then
    Exit;
  // upper bound, trimmed to the real size at the end
  SetLength(Result, (lvLen div 4) * 3 + 3);
  lvOutPos := 0;
  lvAccum := 0;
  lvGroup := 0;
  lvSeenPad := False;
  for i := 1 to lvLen do
  begin
    lvCh := ABase64[i];
    {$IF SizeOf(Char) > 1}
    if Ord(lvCh) > 255 then
      raise EbpBase64.CreateFmt('Invalid Base64 character at position %d', [i]);
    {$IFEND}
    lvCode := gvDecodeTable[Ord(lvCh)];
    if lvCode = gcWhitespace then
      Continue;
    if lvCode = gcPadding then
    begin
      lvSeenPad := True;
      Continue;
    end;
    if lvCode = gcInvalid then
      raise EbpBase64.CreateFmt('Invalid Base64 character at position %d', [i]);
    if lvSeenPad then
      raise EbpBase64.Create('Base64 data continues after padding');
    lvAccum := (lvAccum shl 6) or lvCode;
    Inc(lvGroup);
    if lvGroup = 4 then
    begin
      Result[lvOutPos] := (lvAccum shr 16) and $FF;
      Result[lvOutPos + 1] := (lvAccum shr 8) and $FF;
      Result[lvOutPos + 2] := lvAccum and $FF;
      Inc(lvOutPos, 3);
      lvAccum := 0;
      lvGroup := 0;
    end;
  end;
  // 2 or 3 leftover chars carry 1 or 2 bytes; a single leftover is impossible
  case lvGroup of
    1: raise EbpBase64.Create('Truncated Base64 data');
    2:
      begin
        Result[lvOutPos] := (lvAccum shr 4) and $FF;
        Inc(lvOutPos);
      end;
    3:
      begin
        Result[lvOutPos] := (lvAccum shr 10) and $FF;
        Result[lvOutPos + 1] := (lvAccum shr 2) and $FF;
        Inc(lvOutPos, 2);
      end;
  end;
  SetLength(Result, lvOutPos);
end;

function Base64DecodeStr(const ABase64: string): AnsiString;
var
  lvBytes: TBytes;
begin
  Result := '';
  lvBytes := Base64Decode(ABase64);
  if Length(lvBytes) = 0 then
    Exit;
  SetLength(Result, Length(lvBytes));
  Move(lvBytes[0], Pointer(Result)^, Length(lvBytes));
end;

// ==================================================================
// BpSHA256.pas - implementation
// ==================================================================

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

// ==================================================================
// BpMD5.pas - implementation
// ==================================================================

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

// ==================================================================
// BpHMACSHA256.pas - implementation
// ==================================================================

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

initialization
  // from BpBase64.pas
  InitDecodeTable;

end.
