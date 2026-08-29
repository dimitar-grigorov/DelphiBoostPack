unit BpDictionaries;

// BpDictionaries.pas - GENERATED FILE, DO NOT EDIT.
// Single-file bundle amalgamated from the DelphiBoostPack modular units:
//   src\Core\Units\BpCompat.pas
//   src\Core\Units\BpKeyFold.pas
//   src\Core\Classes\BpHashBobJenkins.pas
//   src\Core\Units\BpVariantUtils.pas
//   src\Core\Classes\BpStrDictionary.pas
//   src\Core\Classes\BpIntDictionary.pas
// Source commit 3fbb305, generated 2026-08-29 by tools\Amalgamate.ps1.
// Fix bugs in the modular units, then regenerate with:
//   powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1
// Notes:
// - use at most one bundle per project; two bundles embedding the same
//   helper unit would declare duplicate identifiers
// - unit-wide compiler directives of embedded units (e.g. {$Q-} in the
//   hash units) apply from their position to the end of this file

interface

uses
  Windows, SysUtils, Variants, Classes;

// ==================================================================
// BpCompat.pas - interface
// ==================================================================

// TBytes for compilers before Delphi 2007, whose SysUtils has no such type.

{$IF CompilerVersion < 18.0}
type
  TBytes = array of Byte;
{$IFEND}

// ==================================================================
// BpKeyFold.pas - interface
// ==================================================================

// Case folding for hash keys without the AnsiUpperCase temporary: a table
// built once from the active code page. Byte-at-a-time folding is only valid
// on a single byte code page, so DBCS and Unicode fall back to the RTL.

// True when the table applies: a single byte code page on a pre-Unicode compiler
function BpKeyFoldUsable: Boolean;

// upper cased through the table when that is valid, otherwise unchanged
function BpFoldChar(aCh: Char): Char;

// FNV-1a over the folded key; never returns a negative value
function BpFoldedHash(const aKey: string): Integer;

// case-insensitive equality, equivalent to AnsiSameText
function BpFoldedSame(const aA, aB: string): Boolean;

// folds aKey into aBuf for a caller running its own hash; the folded length,
// or -1 when it will not fit or the table does not apply
function BpFoldInto(const aKey: string; var aBuf; aBufChars: Integer): Integer;

// ==================================================================
// BpHashBobJenkins.pas - interface
// ==================================================================

// Bob Jenkins lookup3 hash (public domain) for Delphi 7/2007+, seeded to
// interoperate with the RTL's BobJenkinsHash. Hashing a string hashes its
// bytes, so Ansi and Unicode builds differ: use the buffer overload.

{$IF CompilerVersion >= 18}
  {$DEFINE Delphi_2007_UP}
{$IFEND}


type
  TbpHashBobJenkins = class
  private
    FHash: Integer;
    function GetDigest: TBytes;
    class function HashLittle(const Data; Len, InitVal: Integer): Integer;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
  public
    constructor Create;
    procedure Reset(aInitialValue: Integer = 0);
    procedure Update(const aData; aLength: Cardinal); overload;
    procedure Update(const aData: TBytes; aLength: Cardinal = 0); overload;
    procedure Update(const Input: string); overload;
    function HashAsBytes: TBytes;
    function HashAsInteger: Integer;
    function HashAsString: string;
    class function GetHashBytes(const aData: string): TBytes;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashString(const aString: string): string;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashValue(const aData: string): Integer; overload;
      {$IFDEF Delphi_2007_UP} static; inline; {$ENDIF}
    class function GetHashValue(const aData; aLength: Integer; aInitialValue: Integer = 0): Integer; overload;
      {$IFDEF Delphi_2007_UP} static; inline; {$ENDIF}
  end;

// ==================================================================
// BpVariantUtils.pas - interface
// ==================================================================

// Strict Variant-to-native conversions shared by the Bp dictionary units.
//
// Contract: a conversion succeeds only when the variant already holds the
// requested kind of data. Nothing is parsed, truncated or implicitly
// widened: no numeric strings, no boolean-to-int, no float-to-int.
// On failure the out parameter is zeroed/emptied and False is returned.

type
  TbpIntegerDynArray = array of Integer;

function BpTryVarToInt(const aValue: Variant; out aResult: Integer): Boolean;
function BpTryVarToInt64(const aValue: Variant; out aResult: Int64): Boolean;
function BpTryVarToStr(const aValue: Variant; out aResult: string): Boolean;
function BpTryVarToBool(const aValue: Variant; out aResult: Boolean): Boolean;
function BpTryVarToFloat(const aValue: Variant; out aResult: Double): Boolean;
function BpTryVarToIntArray(const aValue: Variant; out aResult: TbpIntegerDynArray): Boolean;

// ==================================================================
// BpStrDictionary.pas - interface
// ==================================================================

// String-key dictionary for Delphi 7/2007+ (no generics), TDictionary-style API.
// Open addressing with linear probing, power-of-two capacity, backward-shift
// deletion, BpHashBobJenkins hashing and opt-in case-insensitive keys.

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpStrDictionary = class(Exception);

  // ForEach callback; set aStop to True to break the iteration
  TbpStrDictForEach = procedure(const aKey: string; const aValue: Variant;
    var aStop: Boolean) of object;

  TbpStrDictItem = record
    HashCode: Integer;
    Key: string;
    Value: Variant;
  end;
  TbpStrDictItemArray = array of TbpStrDictItem;

  TbpStrDictionary = class
  private
    FItems: TbpStrDictItemArray;
    FCount: Integer;
    FGrowThreshold: Integer;
    FCaseInsensitive: Boolean;
    function HashOf(const aKey: string): Integer;
    function KeysEqual(const aKey1, aKey2: string): Boolean;
    // the slot index when found, else the complement of the first empty slot
    function GetBucketIndex(const aKey: string; aHashCode: Integer): Integer;
    procedure DoAdd(aHashCode, aIndex: Integer; const aKey: string; const aValue: Variant);
    procedure Grow;
    procedure Rehash(aNewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(const aKey: string): Variant;
    procedure SetItem(const aKey: string; const aValue: Variant);
  public
    constructor Create(aCaseInsensitive: Boolean = False; aInitialCapacity: Integer = 0);
    // core operations
    procedure Add(const aKey: string; const aValue: Variant);
    procedure AddOrSet(const aKey: string; const aValue: Variant);
    function TryGetValue(const aKey: string; out aValue: Variant): Boolean;
    function ContainsKey(const aKey: string): Boolean;
    function Remove(const aKey: string): Boolean;
    procedure Clear;
    procedure SetCapacity(aCapacity: Integer);
    procedure ForEach(aCallback: TbpStrDictForEach);
    procedure GetKeys(aList: TStrings);
    // GetX raises on a missing key or wrong type, GetXDef defaults, TryGetX never raises
    procedure SetInt(const aKey: string; aValue: Integer);
    function GetInt(const aKey: string): Integer;
    function GetIntDef(const aKey: string; aDefault: Integer): Integer;
    function TryGetInt(const aKey: string; out aValue: Integer): Boolean;
    procedure SetInt64(const aKey: string; aValue: Int64);
    function GetInt64(const aKey: string): Int64;
    function GetInt64Def(const aKey: string; aDefault: Int64): Int64;
    function TryGetInt64(const aKey: string; out aValue: Int64): Boolean;
    procedure SetStr(const aKey, aValue: string);
    function GetStr(const aKey: string): string;
    function GetStrDef(const aKey, aDefault: string): string;
    function TryGetStr(const aKey: string; out aValue: string): Boolean;
    procedure SetBool(const aKey: string; aValue: Boolean);
    function GetBool(const aKey: string): Boolean;
    function GetBoolDef(const aKey: string; aDefault: Boolean): Boolean;
    function TryGetBool(const aKey: string; out aValue: Boolean): Boolean;
    procedure SetFloat(const aKey: string; aValue: Double);
    function GetFloat(const aKey: string): Double;
    function GetFloatDef(const aKey: string; aDefault: Double): Double;
    function TryGetFloat(const aKey: string; out aValue: Double): Boolean;
    procedure SetIntArray(const aKey: string; const aValues: array of Integer);
    function GetIntArray(const aKey: string): TbpIntegerDynArray;
    function TryGetIntArray(const aKey: string; out aValues: TbpIntegerDynArray): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    property CaseInsensitive: Boolean read FCaseInsensitive;
    // raises EbpStrDictionary on read of a missing key; write acts as AddOrSet
    property Items[const aKey: string]: Variant read GetItem write SetItem; default;
  end;

// ==================================================================
// BpIntDictionary.pas - interface
// ==================================================================

// Int64-key dictionary for Delphi 7/2007+ (no generics), same open-addressing
// engine as TbpStrDictionary. Keys go through the Thomas Wang 64-bit mix;
// values are Variant with the same strict typed accessors.

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpIntDictionary = class(Exception);

  TbpInt64DynArray = array of Int64;

  // ForEach callback; set aStop to True to break the iteration
  TbpIntDictForEach = procedure(aKey: Int64; const aValue: Variant;
    var aStop: Boolean) of object;

  TbpIntDictItem = record
    HashCode: Integer;
    Key: Int64;
    Value: Variant;
  end;
  TbpIntDictItemArray = array of TbpIntDictItem;

  TbpIntDictionary = class
  private
    FItems: TbpIntDictItemArray;
    FCount: Integer;
    FGrowThreshold: Integer;
    // the slot index when found, else the complement of the first empty slot
    function GetBucketIndex(aKey: Int64; aHashCode: Integer): Integer;
    procedure DoAdd(aHashCode, aIndex: Integer; aKey: Int64; const aValue: Variant);
    procedure Grow;
    procedure Rehash(aNewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(aKey: Int64): Variant;
    procedure SetItem(aKey: Int64; const aValue: Variant);
  public
    constructor Create(aInitialCapacity: Integer = 0);
    // core operations
    procedure Add(aKey: Int64; const aValue: Variant);
    procedure AddOrSet(aKey: Int64; const aValue: Variant);
    function TryGetValue(aKey: Int64; out aValue: Variant): Boolean;
    function ContainsKey(aKey: Int64): Boolean;
    function Remove(aKey: Int64): Boolean;
    procedure Clear;
    procedure SetCapacity(aCapacity: Integer);
    procedure ForEach(aCallback: TbpIntDictForEach);
    function GetKeys: TbpInt64DynArray;
    // GetX raises on a missing key or wrong type, GetXDef defaults, TryGetX never raises
    procedure SetInt(aKey: Int64; aValue: Integer);
    function GetInt(aKey: Int64): Integer;
    function GetIntDef(aKey: Int64; aDefault: Integer): Integer;
    function TryGetInt(aKey: Int64; out aValue: Integer): Boolean;
    procedure SetInt64(aKey: Int64; aValue: Int64);
    function GetInt64(aKey: Int64): Int64;
    function GetInt64Def(aKey: Int64; aDefault: Int64): Int64;
    function TryGetInt64(aKey: Int64; out aValue: Int64): Boolean;
    procedure SetStr(aKey: Int64; const aValue: string);
    function GetStr(aKey: Int64): string;
    function GetStrDef(aKey: Int64; const aDefault: string): string;
    function TryGetStr(aKey: Int64; out aValue: string): Boolean;
    procedure SetBool(aKey: Int64; aValue: Boolean);
    function GetBool(aKey: Int64): Boolean;
    function GetBoolDef(aKey: Int64; aDefault: Boolean): Boolean;
    function TryGetBool(aKey: Int64; out aValue: Boolean): Boolean;
    procedure SetFloat(aKey: Int64; aValue: Double);
    function GetFloat(aKey: Int64): Double;
    function GetFloatDef(aKey: Int64; aDefault: Double): Double;
    function TryGetFloat(aKey: Int64; out aValue: Double): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    // raises EbpIntDictionary on read of a missing key; write acts as AddOrSet
    property Items[aKey: Int64]: Variant read GetItem write SetItem; default;
  end;

// Thomas Wang 64-bit to 32-bit hash, exposed for reuse and benchmarking
function BpHashInt64(aKey: Int64): Integer;

implementation

// ==================================================================
// BpCompat.pas - implementation
// ==================================================================



// ==================================================================
// BpKeyFold.pas - implementation
// ==================================================================

var
  gvKfUpcase: array[0..255] of Char;
  gvKfUsable: Boolean;
  gvKfReady: Boolean;

procedure KfBuildTable;
var
  i: Integer;
  lvBuf: array[0..255] of Char;
  lvInfo: TCPInfo;
begin
  for i := 0 to 255 do
    lvBuf[i] := Chr(i);
  CharUpperBuff(@lvBuf[0], 256);
  for i := 0 to 255 do
    gvKfUpcase[i] := lvBuf[i];
  {$IFDEF UNICODE}
  gvKfUsable := False;
  {$ELSE}
  gvKfUsable := GetCPInfo(CP_ACP, lvInfo) and (lvInfo.MaxCharSize = 1);
  {$ENDIF}
  gvKfReady := True;
end;

function BpKeyFoldUsable: Boolean;
begin
  if not gvKfReady then
    KfBuildTable;
  Result := gvKfUsable;
end;

function BpFoldChar(aCh: Char): Char;
begin
  if BpKeyFoldUsable then
    Result := gvKfUpcase[Ord(aCh) and $FF]
  else
    Result := aCh;
end;

function BpFoldedHash(const aKey: string): Integer;
var
  i: Integer;
  lvH: Cardinal;
  lvFolded: string;
begin
  lvH := 2166136261;
  if BpKeyFoldUsable then
  begin
    for i := 1 to Length(aKey) do
      lvH := (lvH xor Cardinal(Ord(gvKfUpcase[Ord(aKey[i]) and $FF]))) * 16777619;
  end
  else
  begin
    lvFolded := AnsiUpperCase(aKey);
    for i := 1 to Length(lvFolded) do
      lvH := (lvH xor Cardinal(Ord(lvFolded[i]))) * 16777619;
  end;
  Result := Integer(lvH and $7FFFFFFF);
end;

function BpFoldedSame(const aA, aB: string): Boolean;
var
  i: Integer;
begin
  if not BpKeyFoldUsable then
  begin
    Result := AnsiSameText(aA, aB);
    Exit;
  end;
  Result := Length(aA) = Length(aB);
  if not Result then
    Exit;
  for i := 1 to Length(aA) do
    if gvKfUpcase[Ord(aA[i]) and $FF] <> gvKfUpcase[Ord(aB[i]) and $FF] then
    begin
      Result := False;
      Exit;
    end;
end;

function BpFoldInto(const aKey: string; var aBuf; aBufChars: Integer): Integer;
var
  i, lvLen: Integer;
  lvOut: PChar;
begin
  lvLen := Length(aKey);
  if (not BpKeyFoldUsable) or (lvLen > aBufChars) then
  begin
    Result := -1;
    Exit;
  end;
  lvOut := PChar(@aBuf);
  for i := 1 to lvLen do
    lvOut[i - 1] := gvKfUpcase[Ord(aKey[i]) and $FF];
  Result := lvLen;
end;

// ==================================================================
// BpHashBobJenkins.pas - implementation
// ==================================================================

// lookup3 is defined on wrapping arithmetic, so the checks stay off here
{$Q-}
{$R-}

type
  // three consecutive 32-bit words, for aligned block reads
  TCardinalTriple = array[0..2] of Cardinal;
  PCardinalTriple = ^TCardinalTriple;

function Rot(x, k: Cardinal): Cardinal; {$IFDEF Delphi_2007_UP} inline; {$ENDIF}
begin
  Result := (x shl k) or (x shr (32 - k));
end;

procedure Mix(var a, b, c: Cardinal); {$IFDEF Delphi_2007_UP} inline; {$ENDIF}
begin
  Dec(a, c); a := a xor Rot(c, 4); Inc(c, b);
  Dec(b, a); b := b xor Rot(a, 6); Inc(a, c);
  Dec(c, b); c := c xor Rot(b, 8); Inc(b, a);
  Dec(a, c); a := a xor Rot(c, 16); Inc(c, b);
  Dec(b, a); b := b xor Rot(a, 19); Inc(a, c);
  Dec(c, b); c := c xor Rot(b, 4); Inc(b, a);
end;

procedure Final(var a, b, c: Cardinal); {$IFDEF Delphi_2007_UP} inline; {$ENDIF}
begin
  c := c xor b; Dec(c, Rot(b, 14));
  a := a xor c; Dec(a, Rot(c, 11));
  b := b xor a; Dec(b, Rot(a, 25));
  c := c xor b; Dec(c, Rot(b, 16));
  a := a xor c; Dec(a, Rot(c, 4));
  b := b xor a; Dec(b, Rot(a, 14));
  c := c xor b; Dec(c, Rot(b, 24));
end;

constructor TbpHashBobJenkins.Create;
begin
  inherited Create;
  FHash := 0;
end;

procedure TbpHashBobJenkins.Reset(aInitialValue: Integer = 0);
begin
  FHash := aInitialValue;
end;

procedure TbpHashBobJenkins.Update(const aData; aLength: Cardinal);
begin
  FHash := HashLittle(aData, aLength, FHash);
end;

procedure TbpHashBobJenkins.Update(const aData: TBytes; aLength: Cardinal);
begin
  if aLength = 0 then
    aLength := Length(aData);
  Update(Pointer(aData)^, aLength);
end;

procedure TbpHashBobJenkins.Update(const Input: string);
begin
  Update(Pointer(Input)^, Length(Input) * SizeOf(Char));
end;

function TbpHashBobJenkins.HashAsBytes: TBytes;
begin
  Result := GetDigest;
end;

function TbpHashBobJenkins.HashAsInteger: Integer;
begin
  Result := FHash;
end;

function TbpHashBobJenkins.HashAsString: string;
begin
  Result := IntToHex(FHash, 8);
end;

class function TbpHashBobJenkins.GetHashBytes(const aData: string): TBytes;
begin
  SetLength(Result, 4);
  PCardinal(@Result[0])^ := Cardinal(GetHashValue(aData));
end;

class function TbpHashBobJenkins.GetHashString(const aString: string): string;
begin
  Result := IntToHex(GetHashValue(aString), 8);
end;

class function TbpHashBobJenkins.GetHashValue(const aData: string): Integer;
begin
  Result := HashLittle(Pointer(aData)^, Length(aData) * SizeOf(Char), 0);
end;

class function TbpHashBobJenkins.GetHashValue(const aData; aLength: Integer; aInitialValue: Integer): Integer;
begin
  Result := HashLittle(aData, aLength, aInitialValue);
end;

function TbpHashBobJenkins.GetDigest: TBytes;
begin
  SetLength(Result, 4);
  Move(FHash, Result[0], 4);
end;

// lookup3 mix and final. The last 12-byte block is folded by Final rather
// than in the loop, Len = 0 exits early, and the tail never reads past Data.
class function TbpHashBobJenkins.HashLittle(const Data; Len, InitVal: Integer): Integer;
var
  a, b, c: Cardinal;
  pd: PCardinalTriple;
  pb: PByteArray;
begin
  // seed with the byte length: hashword counts words, hashlittle bytes
  a := Cardinal($DEADBEEF) + Cardinal(Len) + Cardinal(InitVal);
  b := a;
  c := a;

  if (Cardinal(@Data) and 3) = 0 then
  begin
    // 4-byte aligned data
    pd := PCardinalTriple(@Data);
    while Len > 12 do
    begin
      Inc(a, pd^[0]);
      Inc(b, pd^[1]);
      Inc(c, pd^[2]);
      Mix(a, b, c);
      Dec(Len, 12);
      pd := PCardinalTriple(Cardinal(pd) + 12);
    end;

    case Len of
      0:
      begin
        Result := Integer(c);
        Exit;
      end;
      1: Inc(a, pd^[0] and $FF);
      2: Inc(a, pd^[0] and $FFFF);
      3: Inc(a, pd^[0] and $FFFFFF);
      4: Inc(a, pd^[0]);
      5:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1] and $FF);
      end;
      6:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1] and $FFFF);
      end;
      7:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1] and $FFFFFF);
      end;
      8:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
      end;
      9:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2] and $FF);
      end;
      10:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2] and $FFFF);
      end;
      11:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2] and $FFFFFF);
      end;
      12:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2]);
      end;
    end;
  end
  else
  begin
    // unaligned data: byte-by-byte reads, never past the end
    pb := PByteArray(@Data);
    while Len > 12 do
    begin
      Inc(a, Cardinal(pb^[0]) + Cardinal(pb^[1]) shl 8 + Cardinal(pb^[2]) shl 16 + Cardinal(pb^[3]) shl 24);
      Inc(b, Cardinal(pb^[4]) + Cardinal(pb^[5]) shl 8 + Cardinal(pb^[6]) shl 16 + Cardinal(pb^[7]) shl 24);
      Inc(c, Cardinal(pb^[8]) + Cardinal(pb^[9]) shl 8 + Cardinal(pb^[10]) shl 16 + Cardinal(pb^[11]) shl 24);
      Mix(a, b, c);
      Dec(Len, 12);
      pb := PByteArray(Cardinal(pb) + 12);
    end;

    if Len = 0 then
    begin
      Result := Integer(c);
      Exit;
    end;

    // cumulative tail: byte i goes to word i div 4, shifted (i mod 4) * 8
    if Len >= 12 then Inc(c, Cardinal(pb^[11]) shl 24);
    if Len >= 11 then Inc(c, Cardinal(pb^[10]) shl 16);
    if Len >= 10 then Inc(c, Cardinal(pb^[9]) shl 8);
    if Len >= 9 then Inc(c, Cardinal(pb^[8]));
    if Len >= 8 then Inc(b, Cardinal(pb^[7]) shl 24);
    if Len >= 7 then Inc(b, Cardinal(pb^[6]) shl 16);
    if Len >= 6 then Inc(b, Cardinal(pb^[5]) shl 8);
    if Len >= 5 then Inc(b, Cardinal(pb^[4]));
    if Len >= 4 then Inc(a, Cardinal(pb^[3]) shl 24);
    if Len >= 3 then Inc(a, Cardinal(pb^[2]) shl 16);
    if Len >= 2 then Inc(a, Cardinal(pb^[1]) shl 8);
    Inc(a, Cardinal(pb^[0]));
  end;

  Final(a, b, c);
  Result := Integer(c);
end;

// ==================================================================
// BpVariantUtils.pas - implementation
// ==================================================================

{$IF CompilerVersion < 20}
const
  varUString = $0102;  // UnicodeString variant type, first defined in Delphi 2009
{$IFEND}

const
  gcVarWord64 = $0015; // UInt64 variant type (varWord64/varUInt64, missing in D2007)

function BpTryVarToInt64(const aValue: Variant; out aResult: Int64): Boolean;
begin
  case VarType(aValue) of
    varShortInt, varSmallint, varInteger, varByte, varWord, varLongWord,
    varInt64, gcVarWord64:
    begin
      aResult := aValue;
      Result := True;
    end;
  else
    aResult := 0;
    Result := False;
  end;
end;

function BpTryVarToInt(const aValue: Variant; out aResult: Integer): Boolean;
var
  lvInt64: Int64;
begin
  Result := BpTryVarToInt64(aValue, lvInt64) and
    (lvInt64 >= Low(Integer)) and (lvInt64 <= High(Integer));
  if Result then
    aResult := Integer(lvInt64)
  else
    aResult := 0;
end;

function BpTryVarToStr(const aValue: Variant; out aResult: string): Boolean;
begin
  case VarType(aValue) of
    varOleStr, varString, varUString:
    begin
      aResult := aValue;
      Result := True;
    end;
  else
    aResult := '';
    Result := False;
  end;
end;

function BpTryVarToBool(const aValue: Variant; out aResult: Boolean): Boolean;
begin
  Result := VarType(aValue) = varBoolean;
  if Result then
    aResult := aValue
  else
    aResult := False;
end;

function BpTryVarToFloat(const aValue: Variant; out aResult: Double): Boolean;
begin
  case VarType(aValue) of
    varShortInt, varSmallint, varInteger, varByte, varWord, varLongWord,
    varInt64, gcVarWord64, varSingle, varDouble, varCurrency:
    begin
      aResult := aValue;
      Result := True;
    end;
  else
    aResult := 0;
    Result := False;
  end;
end;

function BpTryVarToIntArray(const aValue: Variant; out aResult: TbpIntegerDynArray): Boolean;
var
  lvLow, lvHigh, i: Integer;
begin
  Result := False;
  aResult := nil;
  if (not VarIsArray(aValue)) or (VarArrayDimCount(aValue) <> 1) then
    Exit;
  lvLow := VarArrayLowBound(aValue, 1);
  lvHigh := VarArrayHighBound(aValue, 1);
  SetLength(aResult, lvHigh - lvLow + 1);
  for i := lvLow to lvHigh do
    if not BpTryVarToInt(aValue[i], aResult[i - lvLow]) then
    begin
      aResult := nil;
      Exit;
    end;
  Result := True;
end;

// ==================================================================
// BpStrDictionary.pas - implementation
// ==================================================================

// per-unit names so amalgamated bundles can embed both dictionaries
const
  gcStrEmptyHash = -1;                         // sentinel: slot is free
  gcStrPositiveMask = not Integer($80000000);  // $7FFFFFFF


constructor TbpStrDictionary.Create(aCaseInsensitive: Boolean; aInitialCapacity: Integer);
begin
  inherited Create;
  FCaseInsensitive := aCaseInsensitive;
  if aInitialCapacity < 0 then
    raise EbpStrDictionary.Create('Initial capacity must not be negative');
  if aInitialCapacity > 0 then
    SetCapacity(aInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpStrDictionary.HashOf(const aKey: string): Integer;
var
  lvStack: array[0..255] of Char;
  lvFoldedLen: Integer;
  lvFolded: string;
begin
  if FCaseInsensitive then
  begin
    lvFoldedLen := BpFoldInto(aKey, lvStack, Length(lvStack));
    if lvFoldedLen >= 0 then
      Result := TbpHashBobJenkins.GetHashValue(lvStack, lvFoldedLen * SizeOf(Char), 0)
    else
    begin
      // key too long for the buffer, or a code page the table cannot fold
      lvFolded := AnsiUpperCase(aKey);
      Result := TbpHashBobJenkins.GetHashValue(Pointer(lvFolded)^, Length(lvFolded) * SizeOf(Char), 0);
    end;
  end
  else
    Result := TbpHashBobJenkins.GetHashValue(Pointer(aKey)^, Length(aKey) * SizeOf(Char), 0);
  // force the hash into 0..MaxInt so it can never collide with gcStrEmptyHash
  Result := gcStrPositiveMask and ((gcStrPositiveMask and Result) + 1);
end;

function TbpStrDictionary.KeysEqual(const aKey1, aKey2: string): Boolean;
begin
  if FCaseInsensitive then
    Result := BpFoldedSame(aKey1, aKey2)
  else
    Result := aKey1 = aKey2;
end;

function TbpStrDictionary.GetBucketIndex(const aKey: string; aHashCode: Integer): Integer;
var
  lvLen, lvIndex, lvHC: Integer;
begin
  lvLen := Length(FItems);
  if lvLen = 0 then
  begin
    Result := not High(Integer);
    Exit;
  end;
  lvIndex := aHashCode and (lvLen - 1);
  while True do
  begin
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcStrEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, string compare only on hash match
    if (lvHC = aHashCode) and KeysEqual(FItems[lvIndex].Key, aKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpStrDictionary.DoAdd(aHashCode, aIndex: Integer; const aKey: string; const aValue: Variant);
begin
  FItems[aIndex].HashCode := aHashCode;
  FItems[aIndex].Key := aKey;
  FItems[aIndex].Value := aValue;
  Inc(FCount);
end;

procedure TbpStrDictionary.Rehash(aNewCapacity: Integer);
var
  lvOldItems: TbpStrDictItemArray;
  lvIndex: Integer;
  i: Integer;
begin
  if aNewCapacity = Length(FItems) then
    Exit;
  if aNewCapacity < 0 then
    OutOfMemoryError;
  lvOldItems := FItems;
  FItems := nil;
  SetLength(FItems, aNewCapacity);
  for i := 0 to aNewCapacity - 1 do
    FItems[i].HashCode := gcStrEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := aNewCapacity shr 1 + aNewCapacity shr 2;
  // reinsert using the cached hash codes, no rehashing of the keys
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcStrEmptyHash then
    begin
      lvIndex := not GetBucketIndex(lvOldItems[i].Key, lvOldItems[i].HashCode);
      FItems[lvIndex].HashCode := lvOldItems[i].HashCode;
      FItems[lvIndex].Key := lvOldItems[i].Key;
      FItems[lvIndex].Value := lvOldItems[i].Value;
    end;
end;

procedure TbpStrDictionary.Grow;
var
  lvNewCapacity: Integer;
begin
  lvNewCapacity := Length(FItems) * 2;
  if lvNewCapacity = 0 then
    lvNewCapacity := 4;
  Rehash(lvNewCapacity);
end;

procedure TbpStrDictionary.SetCapacity(aCapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  if aCapacity < FCount then
    raise EbpStrDictionary.Create('Capacity cannot be less than Count');
  if aCapacity = 0 then
    Rehash(0)
  else
  begin
    // a power of two, at least 4, and never full: the probe loop needs a free slot
    lvNewCapacity := 4;
    while (lvNewCapacity > 0) and ((lvNewCapacity < aCapacity) or
      (FCount > lvNewCapacity shr 1 + lvNewCapacity shr 2)) do
      lvNewCapacity := lvNewCapacity shl 1;
    if lvNewCapacity <= 0 then
      OutOfMemoryError;
    Rehash(lvNewCapacity);
  end;
end;

function TbpStrDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpStrDictionary.Add(const aKey: string; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  if FCount >= FGrowThreshold then
    Grow;
  lvHashCode := HashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpStrDictionary.CreateFmt('Duplicate key: "%s"', [aKey]);
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

procedure TbpStrDictionary.AddOrSet(const aKey: string; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  lvHashCode := HashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
  begin
    FItems[lvIndex].Value := aValue;
    Exit;
  end;
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(aKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

function TbpStrDictionary.TryGetValue(const aKey: string; out aValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, HashOf(aKey));
  Result := lvIndex >= 0;
  if Result then
    aValue := FItems[lvIndex].Value
  else
    aValue := Unassigned;
end;

function TbpStrDictionary.ContainsKey(const aKey: string): Boolean;
begin
  Result := GetBucketIndex(aKey, HashOf(aKey)) >= 0;
end;

function TbpStrDictionary.Remove(const aKey: string): Boolean;
var
  lvGap, lvIndex, lvHC, lvBucket, lvLen: Integer;

  // wrap-aware test for a home bucket in (aBottom, aTopInc]; nested to keep bundles clash free
  function InCircularRange(aBottom, aItem, aTopInc: Integer): Boolean;
  begin
    Result := ((aBottom < aItem) and (aItem <= aTopInc)) or
      ((aTopInc < aBottom) and (aItem > aBottom)) or
      ((aTopInc < aBottom) and (aItem <= aTopInc));
  end;

begin
  lvIndex := GetBucketIndex(aKey, HashOf(aKey));
  Result := lvIndex >= 0;
  if not Result then
    Exit;
  // backward-shift deletion (Knuth 6.4 R): slide cluster entries into the gap
  lvLen := Length(FItems);
  lvGap := lvIndex;
  while True do
  begin
    lvIndex := (lvIndex + 1) and (lvLen - 1);
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcStrEmptyHash then
      Break;
    lvBucket := lvHC and (lvLen - 1);
    if not InCircularRange(lvGap, lvBucket, lvIndex) then
    begin
      FItems[lvGap] := FItems[lvIndex];
      lvGap := lvIndex;
    end;
  end;
  FItems[lvGap].HashCode := gcStrEmptyHash;
  FItems[lvGap].Key := '';
  FItems[lvGap].Value := Unassigned;
  Dec(FCount);
end;

procedure TbpStrDictionary.Clear;
begin
  FItems := nil;
  FCount := 0;
  FGrowThreshold := 0;
end;

procedure TbpStrDictionary.ForEach(aCallback: TbpStrDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(aCallback) then
    Exit;
  lvStop := False;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcStrEmptyHash then
    begin
      aCallback(FItems[i].Key, FItems[i].Value, lvStop);
      if lvStop then
        Exit;
    end;
end;

procedure TbpStrDictionary.GetKeys(aList: TStrings);
var
  i: Integer;
begin
  aList.BeginUpdate;
  try
    aList.Clear;
    for i := 0 to Length(FItems) - 1 do
      if FItems[i].HashCode <> gcStrEmptyHash then
        aList.Add(FItems[i].Key);
  finally
    aList.EndUpdate;
  end;
end;

function TbpStrDictionary.GetItem(const aKey: string): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, HashOf(aKey));
  if lvIndex < 0 then
    raise EbpStrDictionary.CreateFmt('Key not found: "%s"', [aKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpStrDictionary.SetItem(const aKey: string; const aValue: Variant);
begin
  AddOrSet(aKey, aValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseStrTypeError(const aKey, aExpected: string; const aValue: Variant);
begin
  raise EbpStrDictionary.CreateFmt('Value for key "%s" is not %s (stored type: %s)',
    [aKey, aExpected, VarTypeAsText(VarType(aValue))]);
end;

procedure TbpStrDictionary.SetInt(const aKey: string; aValue: Integer);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetInt(const aKey: string): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseStrTypeError(aKey, 'an Integer', lvValue);
end;

function TbpStrDictionary.GetIntDef(const aKey: string; aDefault: Integer): Integer;
begin
  if not TryGetInt(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetInt(const aKey: string; out aValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpStrDictionary.SetInt64(const aKey: string; aValue: Int64);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetInt64(const aKey: string): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseStrTypeError(aKey, 'an Int64', lvValue);
end;

function TbpStrDictionary.GetInt64Def(const aKey: string; aDefault: Int64): Int64;
begin
  if not TryGetInt64(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetInt64(const aKey: string; out aValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt64(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpStrDictionary.SetStr(const aKey, aValue: string);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetStr(const aKey: string): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseStrTypeError(aKey, 'a string', lvValue);
end;

function TbpStrDictionary.GetStrDef(const aKey, aDefault: string): string;
begin
  if not TryGetStr(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetStr(const aKey: string; out aValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToStr(lvValue, aValue);
  if not Result then
    aValue := '';
end;

procedure TbpStrDictionary.SetBool(const aKey: string; aValue: Boolean);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetBool(const aKey: string): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseStrTypeError(aKey, 'a Boolean', lvValue);
end;

function TbpStrDictionary.GetBoolDef(const aKey: string; aDefault: Boolean): Boolean;
begin
  if not TryGetBool(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetBool(const aKey: string; out aValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToBool(lvValue, aValue);
  if not Result then
    aValue := False;
end;

procedure TbpStrDictionary.SetFloat(const aKey: string; aValue: Double);
begin
  AddOrSet(aKey, aValue);
end;

function TbpStrDictionary.GetFloat(const aKey: string): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseStrTypeError(aKey, 'a Float', lvValue);
end;

function TbpStrDictionary.GetFloatDef(const aKey: string; aDefault: Double): Double;
begin
  if not TryGetFloat(aKey, Result) then
    Result := aDefault;
end;

function TbpStrDictionary.TryGetFloat(const aKey: string; out aValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToFloat(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpStrDictionary.SetIntArray(const aKey: string; const aValues: array of Integer);
var
  lvArray: Variant;
  i: Integer;
begin
  lvArray := VarArrayCreate([0, Length(aValues) - 1], varInteger);
  for i := 0 to Length(aValues) - 1 do
    lvArray[i] := aValues[i];
  AddOrSet(aKey, lvArray);
end;

function TbpStrDictionary.GetIntArray(const aKey: string): TbpIntegerDynArray;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToIntArray(lvValue, Result) then
    RaiseStrTypeError(aKey, 'an Integer array', lvValue);
end;

function TbpStrDictionary.TryGetIntArray(const aKey: string; out aValues: TbpIntegerDynArray): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToIntArray(lvValue, aValues);
  if not Result then
    aValues := nil;
end;

// ==================================================================
// BpIntDictionary.pas - implementation
// ==================================================================

// per-unit names so amalgamated bundles can embed both dictionaries
const
  gcIntEmptyHash = -1;                         // sentinel: slot is free
  gcIntPositiveMask = not Integer($80000000);  // $7FFFFFFF

{$Q-} // the hash mix relies on wrapping 64-bit arithmetic
function BpHashInt64(aKey: Int64): Integer;
begin
  // Thomas Wang hash64shift; the masks guard shr sign-fill on older compilers
  aKey := (not aKey) + (aKey shl 18);
  aKey := aKey xor ((aKey shr 31) and $00000001FFFFFFFF);
  aKey := aKey * 21;
  aKey := aKey xor ((aKey shr 11) and $001FFFFFFFFFFFFF);
  aKey := aKey + (aKey shl 6);
  aKey := aKey xor ((aKey shr 22) and $000003FFFFFFFFFF);
  Result := Integer(aKey);
end;

// forces a hash into 0..MaxInt so it can never collide with gcIntEmptyHash
function PositiveHashOf(aKey: Int64): Integer;
begin
  Result := gcIntPositiveMask and ((gcIntPositiveMask and BpHashInt64(aKey)) + 1);
end;

constructor TbpIntDictionary.Create(aInitialCapacity: Integer);
begin
  inherited Create;
  if aInitialCapacity < 0 then
    raise EbpIntDictionary.Create('Initial capacity must not be negative');
  if aInitialCapacity > 0 then
    SetCapacity(aInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpIntDictionary.GetBucketIndex(aKey: Int64; aHashCode: Integer): Integer;
var
  lvLen, lvIndex, lvHC: Integer;
begin
  lvLen := Length(FItems);
  if lvLen = 0 then
  begin
    Result := not High(Integer);
    Exit;
  end;
  lvIndex := aHashCode and (lvLen - 1);
  while True do
  begin
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcIntEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, key compare only on hash match
    if (lvHC = aHashCode) and (FItems[lvIndex].Key = aKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpIntDictionary.DoAdd(aHashCode, aIndex: Integer; aKey: Int64; const aValue: Variant);
begin
  FItems[aIndex].HashCode := aHashCode;
  FItems[aIndex].Key := aKey;
  FItems[aIndex].Value := aValue;
  Inc(FCount);
end;

procedure TbpIntDictionary.Rehash(aNewCapacity: Integer);
var
  lvOldItems: TbpIntDictItemArray;
  lvIndex: Integer;
  i: Integer;
begin
  if aNewCapacity = Length(FItems) then
    Exit;
  if aNewCapacity < 0 then
    OutOfMemoryError;
  lvOldItems := FItems;
  FItems := nil;
  SetLength(FItems, aNewCapacity);
  for i := 0 to aNewCapacity - 1 do
    FItems[i].HashCode := gcIntEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := aNewCapacity shr 1 + aNewCapacity shr 2;
  // reinsert using the cached hash codes, no rehashing of the keys
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcIntEmptyHash then
    begin
      lvIndex := not GetBucketIndex(lvOldItems[i].Key, lvOldItems[i].HashCode);
      FItems[lvIndex].HashCode := lvOldItems[i].HashCode;
      FItems[lvIndex].Key := lvOldItems[i].Key;
      FItems[lvIndex].Value := lvOldItems[i].Value;
    end;
end;

procedure TbpIntDictionary.Grow;
var
  lvNewCapacity: Integer;
begin
  lvNewCapacity := Length(FItems) * 2;
  if lvNewCapacity = 0 then
    lvNewCapacity := 4;
  Rehash(lvNewCapacity);
end;

procedure TbpIntDictionary.SetCapacity(aCapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  if aCapacity < FCount then
    raise EbpIntDictionary.Create('Capacity cannot be less than Count');
  if aCapacity = 0 then
    Rehash(0)
  else
  begin
    // a power of two, at least 4, and never full: the probe loop needs a free slot
    lvNewCapacity := 4;
    while (lvNewCapacity > 0) and ((lvNewCapacity < aCapacity) or
      (FCount > lvNewCapacity shr 1 + lvNewCapacity shr 2)) do
      lvNewCapacity := lvNewCapacity shl 1;
    if lvNewCapacity <= 0 then
      OutOfMemoryError;
    Rehash(lvNewCapacity);
  end;
end;

function TbpIntDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpIntDictionary.Add(aKey: Int64; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  if FCount >= FGrowThreshold then
    Grow;
  lvHashCode := PositiveHashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpIntDictionary.CreateFmt('Duplicate key: %d', [aKey]);
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

procedure TbpIntDictionary.AddOrSet(aKey: Int64; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  lvHashCode := PositiveHashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
  begin
    FItems[lvIndex].Value := aValue;
    Exit;
  end;
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(aKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

function TbpIntDictionary.TryGetValue(aKey: Int64; out aValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, PositiveHashOf(aKey));
  Result := lvIndex >= 0;
  if Result then
    aValue := FItems[lvIndex].Value
  else
    aValue := Unassigned;
end;

function TbpIntDictionary.ContainsKey(aKey: Int64): Boolean;
begin
  Result := GetBucketIndex(aKey, PositiveHashOf(aKey)) >= 0;
end;

function TbpIntDictionary.Remove(aKey: Int64): Boolean;
var
  lvGap, lvIndex, lvHC, lvBucket, lvLen: Integer;

  // wrap-aware test for a home bucket in (aBottom, aTopInc]; nested to keep bundles clash free
  function InCircularRange(aBottom, aItem, aTopInc: Integer): Boolean;
  begin
    Result := ((aBottom < aItem) and (aItem <= aTopInc)) or
      ((aTopInc < aBottom) and (aItem > aBottom)) or
      ((aTopInc < aBottom) and (aItem <= aTopInc));
  end;

begin
  lvIndex := GetBucketIndex(aKey, PositiveHashOf(aKey));
  Result := lvIndex >= 0;
  if not Result then
    Exit;
  // backward-shift deletion (Knuth 6.4 R): slide cluster entries into the gap
  lvLen := Length(FItems);
  lvGap := lvIndex;
  while True do
  begin
    lvIndex := (lvIndex + 1) and (lvLen - 1);
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcIntEmptyHash then
      Break;
    lvBucket := lvHC and (lvLen - 1);
    if not InCircularRange(lvGap, lvBucket, lvIndex) then
    begin
      FItems[lvGap] := FItems[lvIndex];
      lvGap := lvIndex;
    end;
  end;
  FItems[lvGap].HashCode := gcIntEmptyHash;
  FItems[lvGap].Key := 0;
  FItems[lvGap].Value := Unassigned;
  Dec(FCount);
end;

procedure TbpIntDictionary.Clear;
begin
  FItems := nil;
  FCount := 0;
  FGrowThreshold := 0;
end;

procedure TbpIntDictionary.ForEach(aCallback: TbpIntDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(aCallback) then
    Exit;
  lvStop := False;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcIntEmptyHash then
    begin
      aCallback(FItems[i].Key, FItems[i].Value, lvStop);
      if lvStop then
        Exit;
    end;
end;

function TbpIntDictionary.GetKeys: TbpInt64DynArray;
var
  i, lvOut: Integer;
begin
  SetLength(Result, FCount);
  lvOut := 0;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcIntEmptyHash then
    begin
      Result[lvOut] := FItems[i].Key;
      Inc(lvOut);
    end;
end;

function TbpIntDictionary.GetItem(aKey: Int64): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(aKey, PositiveHashOf(aKey));
  if lvIndex < 0 then
    raise EbpIntDictionary.CreateFmt('Key not found: %d', [aKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpIntDictionary.SetItem(aKey: Int64; const aValue: Variant);
begin
  AddOrSet(aKey, aValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseIntTypeError(aKey: Int64; const aExpected: string; const aValue: Variant);
begin
  raise EbpIntDictionary.CreateFmt('Value for key %d is not %s (stored type: %s)',
    [aKey, aExpected, VarTypeAsText(VarType(aValue))]);
end;

procedure TbpIntDictionary.SetInt(aKey: Int64; aValue: Integer);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetInt(aKey: Int64): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseIntTypeError(aKey, 'an Integer', lvValue);
end;

function TbpIntDictionary.GetIntDef(aKey: Int64; aDefault: Integer): Integer;
begin
  if not TryGetInt(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetInt(aKey: Int64; out aValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpIntDictionary.SetInt64(aKey: Int64; aValue: Int64);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetInt64(aKey: Int64): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseIntTypeError(aKey, 'an Int64', lvValue);
end;

function TbpIntDictionary.GetInt64Def(aKey: Int64; aDefault: Int64): Int64;
begin
  if not TryGetInt64(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetInt64(aKey: Int64; out aValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToInt64(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

procedure TbpIntDictionary.SetStr(aKey: Int64; const aValue: string);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetStr(aKey: Int64): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseIntTypeError(aKey, 'a string', lvValue);
end;

function TbpIntDictionary.GetStrDef(aKey: Int64; const aDefault: string): string;
begin
  if not TryGetStr(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetStr(aKey: Int64; out aValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToStr(lvValue, aValue);
  if not Result then
    aValue := '';
end;

procedure TbpIntDictionary.SetBool(aKey: Int64; aValue: Boolean);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetBool(aKey: Int64): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseIntTypeError(aKey, 'a Boolean', lvValue);
end;

function TbpIntDictionary.GetBoolDef(aKey: Int64; aDefault: Boolean): Boolean;
begin
  if not TryGetBool(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetBool(aKey: Int64; out aValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToBool(lvValue, aValue);
  if not Result then
    aValue := False;
end;

procedure TbpIntDictionary.SetFloat(aKey: Int64; aValue: Double);
begin
  AddOrSet(aKey, aValue);
end;

function TbpIntDictionary.GetFloat(aKey: Int64): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(aKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseIntTypeError(aKey, 'a Float', lvValue);
end;

function TbpIntDictionary.GetFloatDef(aKey: Int64; aDefault: Double): Double;
begin
  if not TryGetFloat(aKey, Result) then
    Result := aDefault;
end;

function TbpIntDictionary.TryGetFloat(aKey: Int64; out aValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(aKey, lvValue) and BpTryVarToFloat(lvValue, aValue);
  if not Result then
    aValue := 0;
end;

end.
