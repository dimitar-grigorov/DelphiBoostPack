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

function BpTryVarToInt(const AValue: Variant; out AResult: Integer): Boolean;
function BpTryVarToInt64(const AValue: Variant; out AResult: Int64): Boolean;
function BpTryVarToStr(const AValue: Variant; out AResult: string): Boolean;
function BpTryVarToBool(const AValue: Variant; out AResult: Boolean): Boolean;
function BpTryVarToFloat(const AValue: Variant; out AResult: Double): Boolean;
function BpTryVarToIntArray(const AValue: Variant; out AResult: TbpIntegerDynArray): Boolean;

implementation

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

end.
