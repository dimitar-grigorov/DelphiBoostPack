unit BpVariantUtils;

// Strict Variant-to-native conversions shared by the Bp dictionary units.
//
// Contract: a conversion succeeds only when the variant already holds the
// requested kind of data. Nothing is parsed, truncated or implicitly
// widened: no numeric strings, no boolean-to-int, no float-to-int.
// On failure the out parameter is zeroed/emptied and False is returned.

interface

uses
  Variants;

type
  TbpIntegerDynArray = array of Integer;

function BpTryVarToInt(const aValue: Variant; out aResult: Integer): Boolean;
function BpTryVarToInt64(const aValue: Variant; out aResult: Int64): Boolean;
function BpTryVarToStr(const aValue: Variant; out aResult: string): Boolean;
function BpTryVarToBool(const aValue: Variant; out aResult: Boolean): Boolean;
function BpTryVarToFloat(const aValue: Variant; out aResult: Double): Boolean;
function BpTryVarToIntArray(const aValue: Variant; out aResult: TbpIntegerDynArray): Boolean;

implementation

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

end.
