unit BpDictionaries;

// BpDictionaries.pas - GENERATED FILE, DO NOT EDIT.
// Single-file bundle amalgamated from the DelphiBoostPack modular units:
//   src\Core\Classes\BpHashBobJenkins.pas
//   src\Core\Units\BpVariantUtils.pas
//   src\Core\Classes\BpStrDictionary.pas
//   src\Core\Classes\BpIntDictionary.pas
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
  SysUtils, Variants, Windows, Classes;

// ==================================================================
// BpHashBobJenkins.pas - interface
// ==================================================================

// Bob Jenkins lookup3 hash (http://burtleburtle.net/bob/c/lookup3.c) for
// Delphi 7/2007 and later.
//
// The implementation is a faithful port of HashLittle from Delphi XE6
// System.Generics.Defaults (the engine behind BobJenkinsHash and, later,
// System.Hash.THashBobJenkins), including Embarcadero's deviation from
// canonical lookup3: the initial state uses (Len shl 2) instead of Len.
// This keeps hash values byte-for-byte identical with the modern RTL, so
// results can be verified against any Delphi XE+ installation.
//
// Note for cross-version use: hashing a *string* hashes its bytes, so an
// AnsiString on Delphi 2007 and a UnicodeString on XE6 produce different
// hashes for the same text. Byte-oriented known-answer tests must use the
// untyped-buffer overload of GetHashValue.

{$IF CompilerVersion >= 18}
  {$DEFINE Delphi_2007_UP}
{$IFEND}


type
  {$IFNDEF Delphi_2007_UP}
  TBytes = array of Byte;
  {$ENDIF}

  TbpHashBobJenkins = class
  private
    FHash: Integer;
    function GetDigest: TBytes;
    class function HashLittle(const Data; Len, InitVal: Integer): Integer;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
  public
    constructor Create;
    procedure Reset(AInitialValue: Integer = 0);
    procedure Update(const AData; ALength: Cardinal); overload;
    procedure Update(const AData: TBytes; ALength: Cardinal = 0); overload;
    procedure Update(const Input: string); overload;
    function HashAsBytes: TBytes;
    function HashAsInteger: Integer;
    function HashAsString: string;
    class function GetHashBytes(const AData: string): TBytes;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashString(const AString: string): string;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashValue(const AData: string): Integer; overload;
      {$IFDEF Delphi_2007_UP} static; inline; {$ENDIF}
    class function GetHashValue(const AData; ALength: Integer; AInitialValue: Integer = 0): Integer; overload;
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

function BpTryVarToInt(const AValue: Variant; out AResult: Integer): Boolean;
function BpTryVarToInt64(const AValue: Variant; out AResult: Int64): Boolean;
function BpTryVarToStr(const AValue: Variant; out AResult: string): Boolean;
function BpTryVarToBool(const AValue: Variant; out AResult: Boolean): Boolean;
function BpTryVarToFloat(const AValue: Variant; out AResult: Double): Boolean;
function BpTryVarToIntArray(const AValue: Variant; out AResult: TbpIntegerDynArray): Boolean;

// ==================================================================
// BpStrDictionary.pas - interface
// ==================================================================

// Lightweight string-key dictionary for Delphi 7/2007 and later (no generics).
//
// Design follows Delphi XE6 System.Generics.Collections.TDictionary:
// open addressing with linear probing over a single flat item array,
// power-of-two capacity, cached hash codes (EMPTY_HASH sentinel marks free
// slots), growth at 75% load and tombstone-free backward-shift deletion.
// Keys are hashed with the Bob Jenkins lookup3 port in BpHashBobJenkins.
//
// Values are stored as Variant. Typed accessors with validation live in
// the same class (GetInt, TryGetInt, GetIntDef, SetInt and friends).
//
// Case sensitivity: keys are case-sensitive by default; pass True to the
// constructor for case-insensitive mode (keys are then hashed over their
// AnsiUpperCase form and compared with AnsiSameText, locale-aware).

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpStrDictionary = class(Exception);

  // ForEach callback; set AStop to True to break the iteration
  TbpStrDictForEach = procedure(const AKey: string; const AValue: Variant;
    var AStop: Boolean) of object;

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
    function HashOf(const AKey: string): Integer;
    function KeysEqual(const AKey1, AKey2: string): Boolean;
    // returns the slot index (>= 0) when found, otherwise the bitwise
    // complement of the first empty slot (always negative), XE6-style
    function GetBucketIndex(const AKey: string; AHashCode: Integer): Integer;
    procedure DoAdd(AHashCode, AIndex: Integer; const AKey: string; const AValue: Variant);
    procedure Grow;
    procedure Rehash(ANewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(const AKey: string): Variant;
    procedure SetItem(const AKey: string; const AValue: Variant);
  public
    constructor Create(ACaseInsensitive: Boolean = False; AInitialCapacity: Integer = 0);
    // core operations
    procedure Add(const AKey: string; const AValue: Variant);
    procedure AddOrSet(const AKey: string; const AValue: Variant);
    function TryGetValue(const AKey: string; out AValue: Variant): Boolean;
    function ContainsKey(const AKey: string): Boolean;
    function Remove(const AKey: string): Boolean;
    procedure Clear;
    procedure SetCapacity(ACapacity: Integer);
    procedure ForEach(ACallback: TbpStrDictForEach);
    procedure GetKeys(AList: TStrings);
    // typed accessors with validation. GetX raises on a missing key or a
    // wrong stored type, GetXDef returns ADefault instead, TryGetX never
    // raises. Conversion is strict: no boolean-to-int, no numeric strings,
    // no float-to-int truncation
    procedure SetInt(const AKey: string; AValue: Integer);
    function GetInt(const AKey: string): Integer;
    function GetIntDef(const AKey: string; ADefault: Integer): Integer;
    function TryGetInt(const AKey: string; out AValue: Integer): Boolean;
    procedure SetInt64(const AKey: string; AValue: Int64);
    function GetInt64(const AKey: string): Int64;
    function GetInt64Def(const AKey: string; ADefault: Int64): Int64;
    function TryGetInt64(const AKey: string; out AValue: Int64): Boolean;
    procedure SetStr(const AKey, AValue: string);
    function GetStr(const AKey: string): string;
    function GetStrDef(const AKey, ADefault: string): string;
    function TryGetStr(const AKey: string; out AValue: string): Boolean;
    procedure SetBool(const AKey: string; AValue: Boolean);
    function GetBool(const AKey: string): Boolean;
    function GetBoolDef(const AKey: string; ADefault: Boolean): Boolean;
    function TryGetBool(const AKey: string; out AValue: Boolean): Boolean;
    procedure SetFloat(const AKey: string; AValue: Double);
    function GetFloat(const AKey: string): Double;
    function GetFloatDef(const AKey: string; ADefault: Double): Double;
    function TryGetFloat(const AKey: string; out AValue: Double): Boolean;
    procedure SetIntArray(const AKey: string; const AValues: array of Integer);
    function GetIntArray(const AKey: string): TbpIntegerDynArray;
    function TryGetIntArray(const AKey: string; out AValues: TbpIntegerDynArray): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    property CaseInsensitive: Boolean read FCaseInsensitive;
    // raises EbpStrDictionary on read of a missing key; write acts as AddOrSet
    property Items[const AKey: string]: Variant read GetItem write SetItem; default;
  end;

// ==================================================================
// BpIntDictionary.pas - interface
// ==================================================================

// Lightweight Int64-key dictionary for Delphi 7/2007 and later (no generics).
//
// Same engine as TbpStrDictionary (which follows Delphi XE6
// System.Generics.Collections.TDictionary): open addressing with linear
// probing over a single flat item array, power-of-two capacity, cached hash
// codes (EMPTY_HASH sentinel marks free slots), growth at 75% load and
// tombstone-free backward-shift deletion.
// Keys are hashed with the Thomas Wang 64-bit to 32-bit integer mix, which
// spreads sequential ids (the typical database key pattern) across buckets.
//
// Values are stored as Variant with the same strict typed accessors as
// TbpStrDictionary (GetInt, TryGetInt, GetIntDef, SetInt and friends).
//
// Typical use: an in-memory index over a TDataSet or an id-to-data cache,
//   lvIndex.SetInt(lvQuery.FieldByName('ID').AsInteger, lvQuery.RecNo);

type
  // raised for missing keys, duplicate keys and failed typed conversions
  EbpIntDictionary = class(Exception);

  TbpInt64DynArray = array of Int64;

  // ForEach callback; set AStop to True to break the iteration
  TbpIntDictForEach = procedure(AKey: Int64; const AValue: Variant;
    var AStop: Boolean) of object;

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
    // returns the slot index (>= 0) when found, otherwise the bitwise
    // complement of the first empty slot (always negative), XE6-style
    function GetBucketIndex(AKey: Int64; AHashCode: Integer): Integer;
    procedure DoAdd(AHashCode, AIndex: Integer; AKey: Int64; const AValue: Variant);
    procedure Grow;
    procedure Rehash(ANewCapacity: Integer);
    function GetCapacity: Integer;
    function GetItem(AKey: Int64): Variant;
    procedure SetItem(AKey: Int64; const AValue: Variant);
  public
    constructor Create(AInitialCapacity: Integer = 0);
    // core operations
    procedure Add(AKey: Int64; const AValue: Variant);
    procedure AddOrSet(AKey: Int64; const AValue: Variant);
    function TryGetValue(AKey: Int64; out AValue: Variant): Boolean;
    function ContainsKey(AKey: Int64): Boolean;
    function Remove(AKey: Int64): Boolean;
    procedure Clear;
    procedure SetCapacity(ACapacity: Integer);
    procedure ForEach(ACallback: TbpIntDictForEach);
    function GetKeys: TbpInt64DynArray;
    // typed accessors with validation. GetX raises on a missing key or a
    // wrong stored type, GetXDef returns ADefault instead, TryGetX never
    // raises. Conversion is strict: no boolean-to-int, no numeric strings,
    // no float-to-int truncation
    procedure SetInt(AKey: Int64; AValue: Integer);
    function GetInt(AKey: Int64): Integer;
    function GetIntDef(AKey: Int64; ADefault: Integer): Integer;
    function TryGetInt(AKey: Int64; out AValue: Integer): Boolean;
    procedure SetInt64(AKey: Int64; AValue: Int64);
    function GetInt64(AKey: Int64): Int64;
    function GetInt64Def(AKey: Int64; ADefault: Int64): Int64;
    function TryGetInt64(AKey: Int64; out AValue: Int64): Boolean;
    procedure SetStr(AKey: Int64; const AValue: string);
    function GetStr(AKey: Int64): string;
    function GetStrDef(AKey: Int64; const ADefault: string): string;
    function TryGetStr(AKey: Int64; out AValue: string): Boolean;
    procedure SetBool(AKey: Int64; AValue: Boolean);
    function GetBool(AKey: Int64): Boolean;
    function GetBoolDef(AKey: Int64; ADefault: Boolean): Boolean;
    function TryGetBool(AKey: Int64; out AValue: Boolean): Boolean;
    procedure SetFloat(AKey: Int64; AValue: Double);
    function GetFloat(AKey: Int64): Double;
    function GetFloatDef(AKey: Int64; ADefault: Double): Double;
    function TryGetFloat(AKey: Int64; out AValue: Double): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read GetCapacity;
    // raises EbpIntDictionary on read of a missing key; write acts as AddOrSet
    property Items[AKey: Int64]: Variant read GetItem write SetItem; default;
  end;

// Thomas Wang 64-bit to 32-bit hash, exposed for reuse and benchmarking
function BpHashInt64(AKey: Int64): Integer;

implementation

// ==================================================================
// BpHashBobJenkins.pas - implementation
// ==================================================================

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

procedure TbpHashBobJenkins.Reset(AInitialValue: Integer = 0);
begin
  FHash := AInitialValue;
end;

procedure TbpHashBobJenkins.Update(const AData; ALength: Cardinal);
begin
  FHash := HashLittle(AData, ALength, FHash);
end;

procedure TbpHashBobJenkins.Update(const AData: TBytes; ALength: Cardinal);
begin
  if ALength = 0 then
    ALength := Length(AData);
  Update(Pointer(AData)^, ALength);
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

class function TbpHashBobJenkins.GetHashBytes(const AData: string): TBytes;
begin
  SetLength(Result, 4);
  PCardinal(@Result[0])^ := Cardinal(GetHashValue(AData));
end;

class function TbpHashBobJenkins.GetHashString(const AString: string): string;
begin
  Result := IntToHex(GetHashValue(AString), 8);
end;

class function TbpHashBobJenkins.GetHashValue(const AData: string): Integer;
begin
  Result := HashLittle(Pointer(AData)^, Length(AData) * SizeOf(Char), 0);
end;

class function TbpHashBobJenkins.GetHashValue(const AData; ALength: Integer; AInitialValue: Integer): Integer;
begin
  Result := HashLittle(AData, ALength, AInitialValue);
end;

function TbpHashBobJenkins.GetDigest: TBytes;
begin
  SetLength(Result, 4);
  Move(FHash, Result[0], 4);
end;

// Port of Delphi XE6 System.Generics.Defaults.HashLittle.
// - the last full 12-byte block is NOT mixed in the loop: it is added to
//   a/b/c and folded by Final(), exactly like the reference
// - Len = 0 exits early WITHOUT Final(), exactly like the reference
// - the tail never reads past Data: the aligned path uses masked 32-bit
//   reads (cannot cross a page boundary), the unaligned path reads only
//   the remaining bytes one by one
class function TbpHashBobJenkins.HashLittle(const Data; Len, InitVal: Integer): Integer;
var
  a, b, c: Cardinal;
  pd: PCardinalTriple;
  pb: PByteArray;
begin
  a := Cardinal($DEADBEEF) + Cardinal(Len shl 2) + Cardinal(InitVal);
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

    // cumulative tail: byte i goes to word (i div 4), shifted (i mod 4)*8 -
    // the same fall-through mapping as the reference goto chain
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

function BpTryVarToInt64(const AValue: Variant; out AResult: Int64): Boolean;
begin
  case VarType(AValue) of
    varShortInt, varSmallint, varInteger, varByte, varWord, varLongWord,
    varInt64, gcVarWord64:
    begin
      AResult := AValue;
      Result := True;
    end;
  else
    AResult := 0;
    Result := False;
  end;
end;

function BpTryVarToInt(const AValue: Variant; out AResult: Integer): Boolean;
var
  lvInt64: Int64;
begin
  Result := BpTryVarToInt64(AValue, lvInt64) and
    (lvInt64 >= Low(Integer)) and (lvInt64 <= High(Integer));
  if Result then
    AResult := Integer(lvInt64)
  else
    AResult := 0;
end;

function BpTryVarToStr(const AValue: Variant; out AResult: string): Boolean;
begin
  case VarType(AValue) of
    varOleStr, varString, varUString:
    begin
      AResult := AValue;
      Result := True;
    end;
  else
    AResult := '';
    Result := False;
  end;
end;

function BpTryVarToBool(const AValue: Variant; out AResult: Boolean): Boolean;
begin
  Result := VarType(AValue) = varBoolean;
  if Result then
    AResult := AValue
  else
    AResult := False;
end;

function BpTryVarToFloat(const AValue: Variant; out AResult: Double): Boolean;
begin
  case VarType(AValue) of
    varShortInt, varSmallint, varInteger, varByte, varWord, varLongWord,
    varInt64, gcVarWord64, varSingle, varDouble, varCurrency:
    begin
      AResult := AValue;
      Result := True;
    end;
  else
    AResult := 0;
    Result := False;
  end;
end;

function BpTryVarToIntArray(const AValue: Variant; out AResult: TbpIntegerDynArray): Boolean;
var
  lvLow, lvHigh, i: Integer;
begin
  Result := False;
  AResult := nil;
  if (not VarIsArray(AValue)) or (VarArrayDimCount(AValue) <> 1) then
    Exit;
  lvLow := VarArrayLowBound(AValue, 1);
  lvHigh := VarArrayHighBound(AValue, 1);
  SetLength(AResult, lvHigh - lvLow + 1);
  for i := lvLow to lvHigh do
    if not BpTryVarToInt(AValue[i], AResult[i - lvLow]) then
    begin
      AResult := nil;
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

constructor TbpStrDictionary.Create(ACaseInsensitive: Boolean; AInitialCapacity: Integer);
begin
  inherited Create;
  FCaseInsensitive := ACaseInsensitive;
  if AInitialCapacity < 0 then
    raise EbpStrDictionary.Create('Initial capacity must not be negative');
  if AInitialCapacity > 0 then
    SetCapacity(AInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpStrDictionary.HashOf(const AKey: string): Integer;
var
  lvFolded: string;
begin
  if FCaseInsensitive then
  begin
    lvFolded := AnsiUpperCase(AKey);
    Result := TbpHashBobJenkins.GetHashValue(Pointer(lvFolded)^, Length(lvFolded) * SizeOf(Char), 0);
  end
  else
    Result := TbpHashBobJenkins.GetHashValue(Pointer(AKey)^, Length(AKey) * SizeOf(Char), 0);
  // force the hash into 0..MaxInt so it can never collide with gcStrEmptyHash
  Result := gcStrPositiveMask and ((gcStrPositiveMask and Result) + 1);
end;

function TbpStrDictionary.KeysEqual(const AKey1, AKey2: string): Boolean;
begin
  if FCaseInsensitive then
    Result := AnsiSameText(AKey1, AKey2)
  else
    Result := AKey1 = AKey2;
end;

function TbpStrDictionary.GetBucketIndex(const AKey: string; AHashCode: Integer): Integer;
var
  lvLen, lvIndex, lvHC: Integer;
begin
  lvLen := Length(FItems);
  if lvLen = 0 then
  begin
    Result := not High(Integer);
    Exit;
  end;
  lvIndex := AHashCode and (lvLen - 1);
  while True do
  begin
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcStrEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, string compare only on hash match
    if (lvHC = AHashCode) and KeysEqual(FItems[lvIndex].Key, AKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpStrDictionary.DoAdd(AHashCode, AIndex: Integer; const AKey: string; const AValue: Variant);
begin
  FItems[AIndex].HashCode := AHashCode;
  FItems[AIndex].Key := AKey;
  FItems[AIndex].Value := AValue;
  Inc(FCount);
end;

procedure TbpStrDictionary.Rehash(ANewCapacity: Integer);
var
  lvOldItems: TbpStrDictItemArray;
  lvIndex: Integer;
  i: Integer;
begin
  if ANewCapacity = Length(FItems) then
    Exit;
  if ANewCapacity < 0 then
    OutOfMemoryError;
  lvOldItems := FItems;
  FItems := nil;
  SetLength(FItems, ANewCapacity);
  for i := 0 to ANewCapacity - 1 do
    FItems[i].HashCode := gcStrEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := ANewCapacity shr 1 + ANewCapacity shr 2;
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

procedure TbpStrDictionary.SetCapacity(ACapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  if ACapacity < FCount then
    raise EbpStrDictionary.Create('Capacity cannot be less than Count');
  if ACapacity = 0 then
    Rehash(0)
  else
  begin
    // round up to a power of two, minimum 4
    lvNewCapacity := 4;
    while lvNewCapacity < ACapacity do
      lvNewCapacity := lvNewCapacity shl 1;
    Rehash(lvNewCapacity);
  end;
end;

function TbpStrDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpStrDictionary.Add(const AKey: string; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  if FCount >= FGrowThreshold then
    Grow;
  lvHashCode := HashOf(AKey);
  lvIndex := GetBucketIndex(AKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpStrDictionary.CreateFmt('Duplicate key: "%s"', [AKey]);
  DoAdd(lvHashCode, not lvIndex, AKey, AValue);
end;

procedure TbpStrDictionary.AddOrSet(const AKey: string; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  lvHashCode := HashOf(AKey);
  lvIndex := GetBucketIndex(AKey, lvHashCode);
  if lvIndex >= 0 then
  begin
    FItems[lvIndex].Value := AValue;
    Exit;
  end;
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(AKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, AKey, AValue);
end;

function TbpStrDictionary.TryGetValue(const AKey: string; out AValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, HashOf(AKey));
  Result := lvIndex >= 0;
  if Result then
    AValue := FItems[lvIndex].Value
  else
    AValue := Unassigned;
end;

function TbpStrDictionary.ContainsKey(const AKey: string): Boolean;
begin
  Result := GetBucketIndex(AKey, HashOf(AKey)) >= 0;
end;

function TbpStrDictionary.Remove(const AKey: string): Boolean;
var
  lvGap, lvIndex, lvHC, lvBucket, lvLen: Integer;

  // wrap-aware test whether AItem's home bucket lies in (ABottom, ATopInc],
  // decides if an entry may slide back into the gap; nested (not unit-level)
  // so amalgamated bundles can embed both dictionaries without a name clash
  function InCircularRange(ABottom, AItem, ATopInc: Integer): Boolean;
  begin
    Result := ((ABottom < AItem) and (AItem <= ATopInc)) or
      ((ATopInc < ABottom) and (AItem > ABottom)) or
      ((ATopInc < ABottom) and (AItem <= ATopInc));
  end;

begin
  lvIndex := GetBucketIndex(AKey, HashOf(AKey));
  Result := lvIndex >= 0;
  if not Result then
    Exit;
  // backward-shift deletion (Knuth 6.4 Algorithm R): slide the following
  // cluster entries into the gap unless that would pass their home bucket
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

procedure TbpStrDictionary.ForEach(ACallback: TbpStrDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(ACallback) then
    Exit;
  lvStop := False;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcStrEmptyHash then
    begin
      ACallback(FItems[i].Key, FItems[i].Value, lvStop);
      if lvStop then
        Exit;
    end;
end;

procedure TbpStrDictionary.GetKeys(AList: TStrings);
var
  i: Integer;
begin
  AList.BeginUpdate;
  try
    AList.Clear;
    for i := 0 to Length(FItems) - 1 do
      if FItems[i].HashCode <> gcStrEmptyHash then
        AList.Add(FItems[i].Key);
  finally
    AList.EndUpdate;
  end;
end;

function TbpStrDictionary.GetItem(const AKey: string): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, HashOf(AKey));
  if lvIndex < 0 then
    raise EbpStrDictionary.CreateFmt('Key not found: "%s"', [AKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpStrDictionary.SetItem(const AKey: string; const AValue: Variant);
begin
  AddOrSet(AKey, AValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseStrTypeError(const AKey, AExpected: string; const AValue: Variant);
begin
  raise EbpStrDictionary.CreateFmt('Value for key "%s" is not %s (stored type: %s)',
    [AKey, AExpected, VarTypeAsText(VarType(AValue))]);
end;

procedure TbpStrDictionary.SetInt(const AKey: string; AValue: Integer);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetInt(const AKey: string): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseStrTypeError(AKey, 'an Integer', lvValue);
end;

function TbpStrDictionary.GetIntDef(const AKey: string; ADefault: Integer): Integer;
begin
  if not TryGetInt(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetInt(const AKey: string; out AValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpStrDictionary.SetInt64(const AKey: string; AValue: Int64);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetInt64(const AKey: string): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseStrTypeError(AKey, 'an Int64', lvValue);
end;

function TbpStrDictionary.GetInt64Def(const AKey: string; ADefault: Int64): Int64;
begin
  if not TryGetInt64(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetInt64(const AKey: string; out AValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt64(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpStrDictionary.SetStr(const AKey, AValue: string);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetStr(const AKey: string): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseStrTypeError(AKey, 'a string', lvValue);
end;

function TbpStrDictionary.GetStrDef(const AKey, ADefault: string): string;
begin
  if not TryGetStr(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetStr(const AKey: string; out AValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToStr(lvValue, AValue);
  if not Result then
    AValue := '';
end;

procedure TbpStrDictionary.SetBool(const AKey: string; AValue: Boolean);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetBool(const AKey: string): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseStrTypeError(AKey, 'a Boolean', lvValue);
end;

function TbpStrDictionary.GetBoolDef(const AKey: string; ADefault: Boolean): Boolean;
begin
  if not TryGetBool(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetBool(const AKey: string; out AValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToBool(lvValue, AValue);
  if not Result then
    AValue := False;
end;

procedure TbpStrDictionary.SetFloat(const AKey: string; AValue: Double);
begin
  AddOrSet(AKey, AValue);
end;

function TbpStrDictionary.GetFloat(const AKey: string): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseStrTypeError(AKey, 'a Float', lvValue);
end;

function TbpStrDictionary.GetFloatDef(const AKey: string; ADefault: Double): Double;
begin
  if not TryGetFloat(AKey, Result) then
    Result := ADefault;
end;

function TbpStrDictionary.TryGetFloat(const AKey: string; out AValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToFloat(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpStrDictionary.SetIntArray(const AKey: string; const AValues: array of Integer);
var
  lvArray: Variant;
  i: Integer;
begin
  lvArray := VarArrayCreate([0, Length(AValues) - 1], varInteger);
  for i := 0 to Length(AValues) - 1 do
    lvArray[i] := AValues[i];
  AddOrSet(AKey, lvArray);
end;

function TbpStrDictionary.GetIntArray(const AKey: string): TbpIntegerDynArray;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToIntArray(lvValue, Result) then
    RaiseStrTypeError(AKey, 'an Integer array', lvValue);
end;

function TbpStrDictionary.TryGetIntArray(const AKey: string; out AValues: TbpIntegerDynArray): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToIntArray(lvValue, AValues);
  if not Result then
    AValues := nil;
end;

// ==================================================================
// BpIntDictionary.pas - implementation
// ==================================================================

// per-unit names so amalgamated bundles can embed both dictionaries
const
  gcIntEmptyHash = -1;                         // sentinel: slot is free
  gcIntPositiveMask = not Integer($80000000);  // $7FFFFFFF

{$Q-} // the hash mix relies on wrapping 64-bit arithmetic
function BpHashInt64(AKey: Int64): Integer;
begin
  // Thomas Wang's hash64shift: avalanche mix of all 64 key bits.
  // masks guard against sign-fill quirks of shr on Int64 in older compilers
  AKey := (not AKey) + (AKey shl 18);
  AKey := AKey xor ((AKey shr 31) and $00000001FFFFFFFF);
  AKey := AKey * 21;
  AKey := AKey xor ((AKey shr 11) and $001FFFFFFFFFFFFF);
  AKey := AKey + (AKey shl 6);
  AKey := AKey xor ((AKey shr 22) and $000003FFFFFFFFFF);
  Result := Integer(AKey);
end;

// forces a hash into 0..MaxInt so it can never collide with gcIntEmptyHash
function PositiveHashOf(AKey: Int64): Integer;
begin
  Result := gcIntPositiveMask and ((gcIntPositiveMask and BpHashInt64(AKey)) + 1);
end;

constructor TbpIntDictionary.Create(AInitialCapacity: Integer);
begin
  inherited Create;
  if AInitialCapacity < 0 then
    raise EbpIntDictionary.Create('Initial capacity must not be negative');
  if AInitialCapacity > 0 then
    SetCapacity(AInitialCapacity);
  // with capacity 0 the grow threshold is 0, so the first Add grows to 4
end;

function TbpIntDictionary.GetBucketIndex(AKey: Int64; AHashCode: Integer): Integer;
var
  lvLen, lvIndex, lvHC: Integer;
begin
  lvLen := Length(FItems);
  if lvLen = 0 then
  begin
    Result := not High(Integer);
    Exit;
  end;
  lvIndex := AHashCode and (lvLen - 1);
  while True do
  begin
    lvHC := FItems[lvIndex].HashCode;
    if lvHC = gcIntEmptyHash then
    begin
      Result := not lvIndex;
      Exit;
    end;
    // cached hash comparison first, key compare only on hash match
    if (lvHC = AHashCode) and (FItems[lvIndex].Key = AKey) then
    begin
      Result := lvIndex;
      Exit;
    end;
    lvIndex := (lvIndex + 1) and (lvLen - 1);
  end;
end;

procedure TbpIntDictionary.DoAdd(AHashCode, AIndex: Integer; AKey: Int64; const AValue: Variant);
begin
  FItems[AIndex].HashCode := AHashCode;
  FItems[AIndex].Key := AKey;
  FItems[AIndex].Value := AValue;
  Inc(FCount);
end;

procedure TbpIntDictionary.Rehash(ANewCapacity: Integer);
var
  lvOldItems: TbpIntDictItemArray;
  lvIndex: Integer;
  i: Integer;
begin
  if ANewCapacity = Length(FItems) then
    Exit;
  if ANewCapacity < 0 then
    OutOfMemoryError;
  lvOldItems := FItems;
  FItems := nil;
  SetLength(FItems, ANewCapacity);
  for i := 0 to ANewCapacity - 1 do
    FItems[i].HashCode := gcIntEmptyHash;
  // grow at 75% load; guarantees at least one always-empty slot
  FGrowThreshold := ANewCapacity shr 1 + ANewCapacity shr 2;
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

procedure TbpIntDictionary.SetCapacity(ACapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  if ACapacity < FCount then
    raise EbpIntDictionary.Create('Capacity cannot be less than Count');
  if ACapacity = 0 then
    Rehash(0)
  else
  begin
    // round up to a power of two, minimum 4
    lvNewCapacity := 4;
    while lvNewCapacity < ACapacity do
      lvNewCapacity := lvNewCapacity shl 1;
    Rehash(lvNewCapacity);
  end;
end;

function TbpIntDictionary.GetCapacity: Integer;
begin
  Result := Length(FItems);
end;

procedure TbpIntDictionary.Add(AKey: Int64; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  if FCount >= FGrowThreshold then
    Grow;
  lvHashCode := PositiveHashOf(AKey);
  lvIndex := GetBucketIndex(AKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpIntDictionary.CreateFmt('Duplicate key: %d', [AKey]);
  DoAdd(lvHashCode, not lvIndex, AKey, AValue);
end;

procedure TbpIntDictionary.AddOrSet(AKey: Int64; const AValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  lvHashCode := PositiveHashOf(AKey);
  lvIndex := GetBucketIndex(AKey, lvHashCode);
  if lvIndex >= 0 then
  begin
    FItems[lvIndex].Value := AValue;
    Exit;
  end;
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(AKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, AKey, AValue);
end;

function TbpIntDictionary.TryGetValue(AKey: Int64; out AValue: Variant): Boolean;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, PositiveHashOf(AKey));
  Result := lvIndex >= 0;
  if Result then
    AValue := FItems[lvIndex].Value
  else
    AValue := Unassigned;
end;

function TbpIntDictionary.ContainsKey(AKey: Int64): Boolean;
begin
  Result := GetBucketIndex(AKey, PositiveHashOf(AKey)) >= 0;
end;

function TbpIntDictionary.Remove(AKey: Int64): Boolean;
var
  lvGap, lvIndex, lvHC, lvBucket, lvLen: Integer;

  // wrap-aware test whether AItem's home bucket lies in (ABottom, ATopInc],
  // decides if an entry may slide back into the gap; nested (not unit-level)
  // so amalgamated bundles can embed both dictionaries without a name clash
  function InCircularRange(ABottom, AItem, ATopInc: Integer): Boolean;
  begin
    Result := ((ABottom < AItem) and (AItem <= ATopInc)) or
      ((ATopInc < ABottom) and (AItem > ABottom)) or
      ((ATopInc < ABottom) and (AItem <= ATopInc));
  end;

begin
  lvIndex := GetBucketIndex(AKey, PositiveHashOf(AKey));
  Result := lvIndex >= 0;
  if not Result then
    Exit;
  // backward-shift deletion (Knuth 6.4 Algorithm R): slide the following
  // cluster entries into the gap unless that would pass their home bucket
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

procedure TbpIntDictionary.ForEach(ACallback: TbpIntDictForEach);
var
  i: Integer;
  lvStop: Boolean;
begin
  if not Assigned(ACallback) then
    Exit;
  lvStop := False;
  for i := 0 to Length(FItems) - 1 do
    if FItems[i].HashCode <> gcIntEmptyHash then
    begin
      ACallback(FItems[i].Key, FItems[i].Value, lvStop);
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

function TbpIntDictionary.GetItem(AKey: Int64): Variant;
var
  lvIndex: Integer;
begin
  lvIndex := GetBucketIndex(AKey, PositiveHashOf(AKey));
  if lvIndex < 0 then
    raise EbpIntDictionary.CreateFmt('Key not found: %d', [AKey]);
  Result := FItems[lvIndex].Value;
end;

procedure TbpIntDictionary.SetItem(AKey: Int64; const AValue: Variant);
begin
  AddOrSet(AKey, AValue);
end;

// raises a descriptive conversion error naming the key and the stored type
procedure RaiseIntTypeError(AKey: Int64; const AExpected: string; const AValue: Variant);
begin
  raise EbpIntDictionary.CreateFmt('Value for key %d is not %s (stored type: %s)',
    [AKey, AExpected, VarTypeAsText(VarType(AValue))]);
end;

procedure TbpIntDictionary.SetInt(AKey: Int64; AValue: Integer);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetInt(AKey: Int64): Integer;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt(lvValue, Result) then
    RaiseIntTypeError(AKey, 'an Integer', lvValue);
end;

function TbpIntDictionary.GetIntDef(AKey: Int64; ADefault: Integer): Integer;
begin
  if not TryGetInt(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetInt(AKey: Int64; out AValue: Integer): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpIntDictionary.SetInt64(AKey: Int64; AValue: Int64);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetInt64(AKey: Int64): Int64;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToInt64(lvValue, Result) then
    RaiseIntTypeError(AKey, 'an Int64', lvValue);
end;

function TbpIntDictionary.GetInt64Def(AKey: Int64; ADefault: Int64): Int64;
begin
  if not TryGetInt64(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetInt64(AKey: Int64; out AValue: Int64): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToInt64(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

procedure TbpIntDictionary.SetStr(AKey: Int64; const AValue: string);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetStr(AKey: Int64): string;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToStr(lvValue, Result) then
    RaiseIntTypeError(AKey, 'a string', lvValue);
end;

function TbpIntDictionary.GetStrDef(AKey: Int64; const ADefault: string): string;
begin
  if not TryGetStr(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetStr(AKey: Int64; out AValue: string): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToStr(lvValue, AValue);
  if not Result then
    AValue := '';
end;

procedure TbpIntDictionary.SetBool(AKey: Int64; AValue: Boolean);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetBool(AKey: Int64): Boolean;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToBool(lvValue, Result) then
    RaiseIntTypeError(AKey, 'a Boolean', lvValue);
end;

function TbpIntDictionary.GetBoolDef(AKey: Int64; ADefault: Boolean): Boolean;
begin
  if not TryGetBool(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetBool(AKey: Int64; out AValue: Boolean): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToBool(lvValue, AValue);
  if not Result then
    AValue := False;
end;

procedure TbpIntDictionary.SetFloat(AKey: Int64; AValue: Double);
begin
  AddOrSet(AKey, AValue);
end;

function TbpIntDictionary.GetFloat(AKey: Int64): Double;
var
  lvValue: Variant;
begin
  lvValue := GetItem(AKey);
  if not BpTryVarToFloat(lvValue, Result) then
    RaiseIntTypeError(AKey, 'a Float', lvValue);
end;

function TbpIntDictionary.GetFloatDef(AKey: Int64; ADefault: Double): Double;
begin
  if not TryGetFloat(AKey, Result) then
    Result := ADefault;
end;

function TbpIntDictionary.TryGetFloat(AKey: Int64; out AValue: Double): Boolean;
var
  lvValue: Variant;
begin
  Result := TryGetValue(AKey, lvValue) and BpTryVarToFloat(lvValue, AValue);
  if not Result then
    AValue := 0;
end;

end.
