unit BpDictionaries;

// BpDictionaries.pas - GENERATED FILE, DO NOT EDIT.
// Single-file bundle amalgamated from the DelphiBoostPack modular units:
//   src\Core\Units\BpCompat.pas
//   src\Core\Units\BpKeyFold.pas
//   src\Core\Units\BpVariantUtils.pas
//   src\Core\Classes\BpStrDictionary.pas
//   src\Core\Classes\BpIntDictionary.pas
// Source commit 77a27be, generated 2026-09-05 by tools\Amalgamate.ps1.
// Fix bugs in the modular units, then regenerate with:
//   pwsh -NoProfile -File tools\Amalgamate.ps1
// One bundle per project: two that share a helper declare it twice.

{$DEFINE BPAMALGAMATION}

interface

uses
  Windows, SysUtils, Variants, Classes;

// Range and overflow checking as the consumer set it: a unit that turns
// either off is bracketed, so its setting ends where the unit does.
{$IFOPT R+}{$DEFINE BPAMALG_R}{$ELSE}{$UNDEF BPAMALG_R}{$ENDIF}
{$IFOPT Q+}{$DEFINE BPAMALG_Q}{$ELSE}{$UNDEF BPAMALG_Q}{$ENDIF}

// ------------------ begin BpCompat.pas interface ------------------

// Types the older compilers are missing; 18.5 is Delphi 2007, 18.0 is 2006.

type
{$IF CompilerVersion < 23.0}
  // no NativeUInt before D2007 and no 64-bit target before XE2, so Cardinal fits
  TbpUIntPtr = Cardinal;
{$ELSE}
  TbpUIntPtr = NativeUInt;
{$IFEND}

{$IF CompilerVersion < 18.5}
  TBytes = array of Byte;
{$IFEND}
// ------------------- end BpCompat.pas interface -------------------

// ----------------- begin BpKeyFold.pas interface ------------------

// One ordinal relation for string keys: hash, equality and order read the same
// folded characters, so a hash table and a binary search cannot disagree. The
// fold is upper casing through a table built once, over the active code page on
// Delphi 7 and 2007 and over the BMP on a Unicode compiler. A DBCS code page
// cannot fold a byte at a time and takes the RTL path, which allocates.

// True when the table applies; False only on a DBCS code page before Unicode
function BpKeyFoldUsable: Boolean;

// one character, upper cased through the table, unchanged when it does not apply
function BpFoldChar(aCh: Char): Char;

// 32-bit hash of the key, folded when aFold; equal keys hash equal
function BpKeyHash(const aKey: string; aFold: Boolean): Cardinal;

// the same hash over a character buffer, so a slice needs no Copy
function BpKeyHashBuf(aBuf: PChar; aLen: Integer; aFold: Boolean): Cardinal;

// equality under the relation
function BpKeyEquals(const aA, aB: string; aFold: Boolean): Boolean;

// equality of a key against a character buffer
function BpKeyEqualsBuf(const aKey: string; aBuf: PChar; aLen: Integer; aFold: Boolean): Boolean;

// ordinal order under the relation: negative, zero or positive like CompareStr
function BpKeyCompare(const aA, aB: string; aFold: Boolean): Integer;

// case-insensitive equality, BpKeyEquals(aA, aB, True)
function BpFoldedSame(const aA, aB: string): Boolean;

// folds aKey into aBuf; the folded length, or -1 when it does not apply
function BpFoldInto(const aKey: string; var aBuf; aBufChars: Integer): Integer;
{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}
// ------------------ end BpKeyFold.pas interface -------------------

// --------------- begin BpVariantUtils.pas interface ---------------

// Strict Variant-to-native conversions shared by the Bp dictionary units.
//
// Contract: a conversion succeeds only when the variant already holds the
// requested kind of data. Nothing is parsed, truncated or implicitly
// widened: no numeric strings, no boolean-to-int, no float-to-int.
// On failure the out parameter is zeroed/emptied and False is returned.
//
// varDate is a kind of its own here, not a float: use BpTryVarToDate.
// Below Delphi 2009 a varOleStr converts only when the ANSI code page
// carries every character, otherwise the call fails instead of writing '?'.

type
  TbpIntegerDynArray = array of Integer;

function BpTryVarToInt(const aValue: Variant; out aResult: Integer): Boolean;
function BpTryVarToInt64(const aValue: Variant; out aResult: Int64): Boolean;
function BpTryVarToStr(const aValue: Variant; out aResult: string): Boolean;
function BpTryVarToBool(const aValue: Variant; out aResult: Boolean): Boolean;
function BpTryVarToFloat(const aValue: Variant; out aResult: Double): Boolean;
function BpTryVarToDate(const aValue: Variant; out aResult: TDateTime): Boolean;
function BpTryVarToIntArray(const aValue: Variant; out aResult: TbpIntegerDynArray): Boolean;
// ---------------- end BpVariantUtils.pas interface ----------------

// -------------- begin BpStrDictionary.pas interface ---------------

// String-key dictionary for Delphi 7/2007+ (no generics), TDictionary-style API.
// Open addressing with linear probing, power-of-two capacity and backward-shift
// deletion. Hash and equality are the one ordinal relation from BpKeyFold, so a
// case-insensitive key folds as it is hashed instead of through a copy.

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
    FIterating: Boolean;
    procedure CheckNotIterating;
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
{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}
// --------------- end BpStrDictionary.pas interface ----------------

// -------------- begin BpIntDictionary.pas interface ---------------

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
    FIterating: Boolean;
    procedure CheckNotIterating;
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
{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}
// --------------- end BpIntDictionary.pas interface ----------------

implementation

// --------------- begin BpCompat.pas implementation ----------------


// ---------------- end BpCompat.pas implementation -----------------

// --------------- begin BpKeyFold.pas implementation ---------------

{$Q-}

type
  {$IFDEF UNICODE}
  TKfTable = array[Word] of WideChar;
  {$ELSE}
  TKfTable = array[Byte] of AnsiChar;
  {$ENDIF}
  PKfTable = ^TKfTable;

var
  // a static table, so the unit needs no finalization and can be bundled
  gvKfUpcase: TKfTable;
  gvKfUsable: Boolean;
  gvKfReady: Boolean;

// built aside and published whole, so no thread folds through a half-built table
procedure KfBuildTable;
var
  i: Integer;
  lvNew: PKfTable;
  {$IFNDEF UNICODE}
  lvInfo: TCPInfo;
  {$ENDIF}
begin
  New(lvNew);
  try
    for i := Low(lvNew^) to High(lvNew^) do
      lvNew^[i] := Char(i);
    {$IFDEF UNICODE}
    // simple case mapping is one to one, so a table is exact for the BMP
    CharUpperBuffW(@lvNew^[1], High(lvNew^));
    gvKfUsable := True;
    {$ELSE}
    CharUpperBuffA(@lvNew^[1], High(lvNew^));
    gvKfUsable := GetCPInfo(CP_ACP, lvInfo) and (lvInfo.MaxCharSize = 1);
    {$ENDIF}
    gvKfUpcase := lvNew^;
  finally
    Dispose(lvNew);
  end;
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
    Result := gvKfUpcase[Ord(aCh)]
  else
    Result := aCh;
end;

// FNV-1a then the murmur3 finaliser, so a bucket index depends on every character
function KfHash(aBuf: PChar; aLen: Integer; aFold: Boolean): Cardinal;
var
  i: Integer;
begin
  Result := 2166136261;
  if aFold then
    for i := 0 to aLen - 1 do
      Result := (Result xor Cardinal(Ord(gvKfUpcase[Ord(aBuf[i])]))) * 16777619
  else
    for i := 0 to aLen - 1 do
      Result := (Result xor Cardinal(Ord(aBuf[i]))) * 16777619;
  Result := Result xor (Result shr 16);
  Result := Result * $85EBCA6B;
  Result := Result xor (Result shr 13);
  Result := Result * $C2B2AE35;
  Result := Result xor (Result shr 16);
end;

function BpKeyHashBuf(aBuf: PChar; aLen: Integer; aFold: Boolean): Cardinal;
var
  lvUpper: string;
begin
  if aFold and not BpKeyFoldUsable then
  begin
    // DBCS: the RTL knows the lead bytes, the table does not
    SetString(lvUpper, aBuf, aLen);
    lvUpper := AnsiUpperCase(lvUpper);
    Result := KfHash(PChar(lvUpper), Length(lvUpper), False);
    Exit;
  end;
  if aFold and not gvKfReady then
    KfBuildTable;
  Result := KfHash(aBuf, aLen, aFold);
end;

function BpKeyHash(const aKey: string; aFold: Boolean): Cardinal;
begin
  Result := BpKeyHashBuf(PChar(aKey), Length(aKey), aFold);
end;

function BpKeyEqualsBuf(const aKey: string; aBuf: PChar; aLen: Integer; aFold: Boolean): Boolean;
var
  i: Integer;
  lvKey: PChar;
  lvOther: string;
begin
  if aFold and not BpKeyFoldUsable then
  begin
    // the same relation the DBCS hash and compare take: upper case, then ordinal
    SetString(lvOther, aBuf, aLen);
    Result := CompareStr(AnsiUpperCase(aKey), AnsiUpperCase(lvOther)) = 0;
    Exit;
  end;
  Result := Length(aKey) = aLen;
  if not Result then
    Exit;
  lvKey := PChar(aKey);
  if aFold then
  begin
    for i := 0 to aLen - 1 do
      if gvKfUpcase[Ord(lvKey[i])] <> gvKfUpcase[Ord(aBuf[i])] then
      begin
        Result := False;
        Exit;
      end;
  end
  else
    Result := CompareMem(lvKey, aBuf, aLen * SizeOf(Char));
end;

function BpKeyEquals(const aA, aB: string; aFold: Boolean): Boolean;
begin
  // unfolded is plain ordinal equality, and the RTL compares a word at a time
  if aFold then
    Result := BpKeyEqualsBuf(aA, PChar(aB), Length(aB), True)
  else
    Result := aA = aB;
end;

function BpKeyCompare(const aA, aB: string; aFold: Boolean): Integer;
var
  i, lvLen: Integer;
  lvA, lvB: PChar;
  lvChA, lvChB: Char;
begin
  if not aFold then
  begin
    Result := CompareStr(aA, aB);
    Exit;
  end;
  if not BpKeyFoldUsable then
  begin
    Result := CompareStr(AnsiUpperCase(aA), AnsiUpperCase(aB));
    Exit;
  end;
  lvLen := Length(aA);
  if Length(aB) < lvLen then
    lvLen := Length(aB);
  lvA := PChar(aA);
  lvB := PChar(aB);
  for i := 0 to lvLen - 1 do
  begin
    lvChA := gvKfUpcase[Ord(lvA[i])];
    lvChB := gvKfUpcase[Ord(lvB[i])];
    if lvChA <> lvChB then
    begin
      Result := Ord(lvChA) - Ord(lvChB);
      Exit;
    end;
  end;
  Result := Length(aA) - Length(aB);
end;

function BpFoldedSame(const aA, aB: string): Boolean;
begin
  Result := BpKeyEquals(aA, aB, True);
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
    lvOut[i - 1] := gvKfUpcase[Ord(aKey[i])];
  Result := lvLen;
end;
{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}
// ---------------- end BpKeyFold.pas implementation ----------------

// ------------ begin BpVariantUtils.pas implementation -------------

{$IF CompilerVersion < 20}
const
  varUString = $0102;  // UnicodeString variant type, first defined in Delphi 2009
{$IFEND}

const
  gcVarWord64 = $0015; // UInt64 variant type (varWord64/varUInt64, missing in D2007)
  gcTwoPow64  = 18446744073709551616.0; // to read an unsigned Int64 payload as a float

{$IF CompilerVersion < 20}
const
  gcNoBestFit = $00000400; // WC_NO_BEST_FIT_CHARS, missing in D7's Windows.pas

// True when every character survives the ANSI code page, so a code point it
// cannot carry fails instead of arriving as '?'.
function TryWideToAnsi(const aValue: WideString; out aResult: AnsiString): Boolean;
var
  lvLen: Integer;
  lvUsedDefault: BOOL;
begin
  aResult := '';
  Result := True;
  if aValue = '' then
    Exit;
  lvLen := WideCharToMultiByte(CP_ACP, gcNoBestFit, PWideChar(aValue),
    Length(aValue), nil, 0, nil, nil);
  if lvLen <= 0 then
  begin
    Result := False;
    Exit;
  end;
  SetLength(aResult, lvLen);
  lvUsedDefault := False;
  lvLen := WideCharToMultiByte(CP_ACP, gcNoBestFit, PWideChar(aValue),
    Length(aValue), PAnsiChar(aResult), lvLen, nil, @lvUsedDefault);
  Result := (lvLen > 0) and (not lvUsedDefault);
  if Result then
    SetLength(aResult, lvLen)
  else
    aResult := '';
end;
{$IFEND}

function BpTryVarToInt64(const aValue: Variant; out aResult: Int64): Boolean;
begin
  case VarType(aValue) of
    varShortInt, varSmallint, varInteger, varByte, varWord, varLongWord,
    varInt64:
    begin
      aResult := aValue;
      Result := True;
    end;
    gcVarWord64:
    begin
      // raw payload: a variant assignment goes through Double on D2007 and
      // loses bits. Negative means bit 63 set, so it is past High(Int64).
      aResult := TVarData(aValue).VInt64;
      Result := aResult >= 0;
      if not Result then
        aResult := 0;
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
    varOleStr:
    begin
{$IF CompilerVersion < 20}
      Result := TryWideToAnsi(WideString(aValue), aResult);
{$ELSE}
      aResult := aValue;
      Result := True;
{$IFEND}
    end;
    varString, varUString:
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
var
  lvInt64: Int64;
begin
  case VarType(aValue) of
    varShortInt, varSmallint, varInteger, varByte, varWord, varLongWord,
    varInt64, varSingle, varDouble, varCurrency:
    begin
      aResult := aValue;
      Result := True;
    end;
    gcVarWord64:
    begin
      // same raw reading as above, put back on the unsigned side when negative
      lvInt64 := TVarData(aValue).VInt64;
      if lvInt64 >= 0 then
        aResult := lvInt64
      else
        aResult := lvInt64 + gcTwoPow64;
      Result := True;
    end;
  else
    aResult := 0;
    Result := False;
  end;
end;

function BpTryVarToDate(const aValue: Variant; out aResult: TDateTime): Boolean;
begin
  Result := VarType(aValue) = varDate;
  if Result then
    aResult := TVarData(aValue).VDate
  else
    aResult := 0;
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
// ------------- end BpVariantUtils.pas implementation --------------

// ------------ begin BpStrDictionary.pas implementation ------------

{$Q-}

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

// one relation with KeysEqual and with TbpStringList: equal keys hash equal
function TbpStrDictionary.HashOf(const aKey: string): Integer;
begin
  Result := Integer(BpKeyHash(aKey, FCaseInsensitive));
  // force the hash into 0..MaxInt so it can never collide with gcStrEmptyHash
  Result := gcStrPositiveMask and ((gcStrPositiveMask and Result) + 1);
end;

function TbpStrDictionary.KeysEqual(const aKey1, aKey2: string): Boolean;
begin
  Result := BpKeyEquals(aKey1, aKey2, FCaseInsensitive);
end;

// a callback that adds or removes would make the scan skip or revisit entries
procedure TbpStrDictionary.CheckNotIterating;
begin
  if FIterating then
    raise EbpStrDictionary.Create('The dictionary cannot be changed while ForEach runs');
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
  // above the early exits: Delphi 7 counts the implicit finalisation as a use
  lvOldItems := nil;
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
  // reinsert on the cached hash codes, moving each entry as raw bits: a field
  // copy would pay a refcount pair per string and deep-copy every variant array
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcStrEmptyHash then
    begin
      lvIndex := not GetBucketIndex(lvOldItems[i].Key, lvOldItems[i].HashCode);
      System.Move(lvOldItems[i], FItems[lvIndex], SizeOf(TbpStrDictItem));
      // the old slot must forget what it no longer owns, or finalisation frees it
      FillChar(lvOldItems[i], SizeOf(TbpStrDictItem), 0);
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
  CheckNotIterating;
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
  CheckNotIterating;
  lvHashCode := HashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpStrDictionary.CreateFmt('Duplicate key: "%s"', [aKey]);
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(aKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

procedure TbpStrDictionary.AddOrSet(const aKey: string; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  CheckNotIterating;
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
  CheckNotIterating;
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
  CheckNotIterating;
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
  FIterating := True;
  try
    for i := 0 to Length(FItems) - 1 do
      if FItems[i].HashCode <> gcStrEmptyHash then
      begin
        aCallback(FItems[i].Key, FItems[i].Value, lvStop);
        if lvStop then
          Exit;
      end;
  finally
    FIterating := False;
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
{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}
// ------------- end BpStrDictionary.pas implementation -------------

// ------------ begin BpIntDictionary.pas implementation ------------

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

// a callback that adds or removes would make the scan skip or revisit entries
procedure TbpIntDictionary.CheckNotIterating;
begin
  if FIterating then
    raise EbpIntDictionary.Create('The dictionary cannot be changed while ForEach runs');
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
  // above the early exits: Delphi 7 counts the implicit finalisation as a use
  lvOldItems := nil;
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
  // reinsert on the cached hash codes, moving each entry as raw bits: a field
  // copy would pay a VarCopy per item and deep-copy every variant array
  for i := 0 to Length(lvOldItems) - 1 do
    if lvOldItems[i].HashCode <> gcIntEmptyHash then
    begin
      lvIndex := not GetBucketIndex(lvOldItems[i].Key, lvOldItems[i].HashCode);
      System.Move(lvOldItems[i], FItems[lvIndex], SizeOf(TbpIntDictItem));
      // the old slot must forget what it no longer owns, or finalisation frees it
      FillChar(lvOldItems[i], SizeOf(TbpIntDictItem), 0);
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
  CheckNotIterating;
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
  CheckNotIterating;
  lvHashCode := PositiveHashOf(aKey);
  lvIndex := GetBucketIndex(aKey, lvHashCode);
  if lvIndex >= 0 then
    raise EbpIntDictionary.CreateFmt('Duplicate key: %d', [aKey]);
  // grow only on a genuine new insert; the array moves, so probe again
  if FCount >= FGrowThreshold then
  begin
    Grow;
    lvIndex := GetBucketIndex(aKey, lvHashCode);
  end;
  DoAdd(lvHashCode, not lvIndex, aKey, aValue);
end;

procedure TbpIntDictionary.AddOrSet(aKey: Int64; const aValue: Variant);
var
  lvHashCode, lvIndex: Integer;
begin
  CheckNotIterating;
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
  CheckNotIterating;
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
  CheckNotIterating;
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
  FIterating := True;
  try
    for i := 0 to Length(FItems) - 1 do
      if FItems[i].HashCode <> gcIntEmptyHash then
      begin
        aCallback(FItems[i].Key, FItems[i].Value, lvStop);
        if lvStop then
          Exit;
      end;
  finally
    FIterating := False;
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
{$IFDEF BPAMALG_R}{$R+}{$ELSE}{$R-}{$ENDIF}{$IFDEF BPAMALG_Q}{$Q+}{$ELSE}{$Q-}{$ENDIF}
// ------------- end BpIntDictionary.pas implementation -------------

end.
