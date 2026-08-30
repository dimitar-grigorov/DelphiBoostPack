unit BpVariantUtils;

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
function BpTryVarToDate(const aValue: Variant; out aResult: TDateTime): Boolean;
function BpTryVarToIntArray(const aValue: Variant; out aResult: TbpIntegerDynArray): Boolean;

implementation

uses
  Windows;

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

end.
