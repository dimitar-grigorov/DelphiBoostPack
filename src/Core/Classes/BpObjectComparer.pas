unit BpObjectComparer;

// Diffs two objects by RTTI and reports the changed published properties, collections included.

interface

uses
  Classes, SysUtils, Variants;

type
  IPropDifference = interface
    ['{A8F6F896-B688-429D-9531-DA9095E3D983}']
    function GetOldPropPath: string;
    function GetNewPropPath: string;
    function GetOldValue: Variant;
    function GetNewValue: Variant;
    function GetIdx: string;

    property OldPropPath: string read GetOldPropPath;
    property NewPropPath: string read GetNewPropPath;
    property OldValue: Variant read GetOldValue;
    property NewValue: Variant read GetNewValue;
    property Idx: string read GetIdx;
  end;

  TPropDifference = class(TInterfacedObject, IPropDifference)
  private
    // old and new paths differ only for IUniqueId collection items, where the item moved index
    FOldPropPath: string;
    FNewPropPath: string;
    FOldValue: Variant;
    FNewValue: Variant;
    FIdx: string;
  public
    constructor Create(const aPropPath: string; const aOldValue, aNewValue: Variant); overload;
    // used for collection item differences
    constructor Create(const aOldPropPath, aNewPropPath: string; const aOldValue, aNewValue: Variant; const aIdx: string = ''); overload;
    function GetOldPropPath: string;
    function GetNewPropPath: string;
    function GetOldValue: Variant;
    function GetNewValue: Variant;
    function GetIdx: string;
  end;

  TPropDifferences = array of IPropDifference;

type
  TbpObjectComparer = class
  public
    class function CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
    class function CompareObjectsAsString(aOld, aNew: TPersistent): string;
    class function StripIndexFromProperty(const aProp: string): string;
  end;

implementation

uses
  TypInfo, StrUtils, UniqueIdIntf, BpStrDictionary;

type
  // Diffs grows by doubling and is trimmed to Count once, not on every append
  TCompareState = record
    Diffs: TPropDifferences;
    Count: Integer;
  end;

constructor TPropDifference.Create(const aOldPropPath, aNewPropPath: string; const aOldValue,
  aNewValue: Variant; const aIdx: string);
begin
  inherited Create;
  FOldPropPath := aOldPropPath;
  FNewPropPath := aNewPropPath;
  FOldValue := aOldValue;
  FNewValue := aNewValue;
  FIdx := aIdx;
end;

constructor TPropDifference.Create(const aPropPath: string; const aOldValue, aNewValue: Variant);
begin
  Create(aPropPath, aPropPath, aOldValue, aNewValue);
end;

function TPropDifference.GetOldPropPath: string;
begin
  Result := FOldPropPath;
end;

function TPropDifference.GetNewPropPath: string;
begin
  Result := FNewPropPath;
end;

function TPropDifference.GetOldValue: Variant;
begin
  Result := FOldValue;
end;

function TPropDifference.GetNewValue: Variant;
begin
  Result := FNewValue;
end;

function TPropDifference.GetIdx: string;
begin
  Result := FIdx;
end;

// a pair the RTL cannot convert is a difference, not EVariantTypeCastError
function VarsDiffer(const aOld, aNew: Variant): Boolean;
begin
  try
    Result := aOld <> aNew;
  except
    on EVariantError do
      Result := True;
  end;
end;

procedure AddDiff(var aState: TCompareState; const aDiff: IPropDifference);
begin
  if aState.Count = Length(aState.Diffs) then
    SetLength(aState.Diffs, 8 + aState.Count * 2);
  aState.Diffs[aState.Count] := aDiff;
  Inc(aState.Count);
end;

function ItemPath(const aPath: string; aIndex: Integer): string;
begin
  Result := Format('%s[%d]', [aPath, aIndex]);
end;

procedure CompareCollections(aOld, aNew: TCollection; const aOldPath, aNewPath: string;
  var aState: TCompareState); forward;

procedure CompareProps(aOld, aNew: TPersistent; const aOldPath, aNewPath, aIdx: string;
  var aState: TCompareState);
var
  lvPropList: PPropList;
  lvPropCount, i: Integer;
  lvPropInfo: PPropInfo;
  lvOldValue, lvNewValue: Variant;
  lvOldPropPath, lvNewPropPath: string;
  lvOldWide, lvNewWide: WideString;
  lvOldObj, lvNewObj: TObject;
begin
  lvPropCount := GetPropList(aOld.ClassInfo, tkProperties, nil);
  GetMem(lvPropList, lvPropCount * SizeOf(Pointer));
  try
    GetPropList(aOld.ClassInfo, tkProperties, lvPropList);
    for i := 0 to lvPropCount - 1 do
    begin
      lvPropInfo := lvPropList^[i];
      lvOldPropPath := IfThen(aOldPath <> '', aOldPath + '.', '') + string(lvPropInfo^.Name);
      lvNewPropPath := IfThen(aNewPath <> '', aNewPath + '.', '') + string(lvPropInfo^.Name);

      case lvPropInfo^.PropType^.Kind of
        // tkUString exists from Delphi 2009 on; without it every string property is skipped
        {$IF Declared(tkUString)}
        tkUString,
        {$IFEND}
        tkInteger, tkEnumeration, tkFloat, tkString, tkSet, tkLString, tkWString, tkVariant:
          begin
            lvOldValue := GetPropValue(aOld, string(lvPropInfo^.Name));
            lvNewValue := GetPropValue(aNew, string(lvPropInfo^.Name));
          end;
        tkChar:
          begin
            lvOldValue := Char(GetOrdProp(aOld, string(lvPropInfo^.Name)));
            lvNewValue := Char(GetOrdProp(aNew, string(lvPropInfo^.Name)));
          end;
        tkWChar:
          begin
            // via WideString, or Char drops the high byte before Delphi 2009
            lvOldWide := WideChar(GetOrdProp(aOld, string(lvPropInfo^.Name)));
            lvNewWide := WideChar(GetOrdProp(aNew, string(lvPropInfo^.Name)));
            lvOldValue := lvOldWide;
            lvNewValue := lvNewWide;
          end;
        tkClass:
          begin
            lvOldObj := GetObjectProp(aOld, lvPropInfo);
            lvNewObj := GetObjectProp(aNew, lvPropInfo);
            if (lvOldObj is TCollection) and (lvNewObj is TCollection) then
              CompareCollections(TCollection(lvOldObj), TCollection(lvNewObj),
                lvOldPropPath, lvNewPropPath, aState)
            // one side nil is a real difference, not a reason to dereference nil
            else if (lvOldObj is TCollection) then
              AddDiff(aState, TPropDifference.Create(lvOldPropPath,
                lvNewPropPath, 'Exists in old', 'Missing in new', aIdx))
            else if (lvNewObj is TCollection) then
              AddDiff(aState, TPropDifference.Create(lvOldPropPath,
                lvNewPropPath, 'Missing in old', 'Exists in new', aIdx));
            Continue;
          end;
      else
        Continue; // unhandled property kinds are ignored, not diffed
      end;

      if VarsDiffer(lvOldValue, lvNewValue) then
        AddDiff(aState, TPropDifference.Create(lvOldPropPath, lvNewPropPath, lvOldValue, lvNewValue, aIdx));
    end;
  finally
    FreeMem(lvPropList);
  end;
end;

procedure CompareCollections(aOld, aNew: TCollection; const aOldPath, aNewPath: string;
  var aState: TCompareState);
var
  i, lvNewIdx: Integer;
  lvOldItem: TCollectionItem;
  lvIdIntf: IUniqueId;
  lvId: string;
  lvById: TbpStrDictionary;       // id to the lowest new index still carrying it unmatched
  lvNextSameId: array of Integer; // chains the new indices that share an id, so duplicates pair up in order
  lvMatched: array of Boolean;
begin
  if aOld.Count <> aNew.Count then
    AddDiff(aState, TPropDifference.Create(aOldPath + '.Count', aNewPath + '.Count', aOld.Count, aNew.Count));

  SetLength(lvMatched, aNew.Count);
  SetLength(lvNextSameId, aNew.Count);
  lvById := nil;
  try
    for i := aNew.Count - 1 downto 0 do
      if Supports(aNew.Items[i], IUniqueId, lvIdIntf) then
      begin
        if lvById = nil then
          lvById := TbpStrDictionary.Create;
        lvId := lvIdIntf.GetUniqueId;
        lvNextSameId[i] := lvById.GetIntDef(lvId, -1);
        lvById[lvId] := i;
      end;

    for i := 0 to aOld.Count - 1 do
    begin
      lvOldItem := aOld.Items[i];
      if Supports(lvOldItem, IUniqueId, lvIdIntf) then
      begin
        lvId := lvIdIntf.GetUniqueId;
        if lvById <> nil then
          lvNewIdx := lvById.GetIntDef(lvId, -1)
        else
          lvNewIdx := -1;
        if lvNewIdx >= 0 then
          lvById[lvId] := lvNextSameId[lvNewIdx];
      end
      else
      begin
        lvId := IntToStr(i);
        // by position, unless an id item of a mixed collection already took that slot
        if (i < aNew.Count) and not lvMatched[i] then
          lvNewIdx := i
        else
          lvNewIdx := -1;
      end;

      if lvNewIdx >= 0 then
      begin
        lvMatched[lvNewIdx] := True;
        CompareProps(lvOldItem, aNew.Items[lvNewIdx], ItemPath(aOldPath, i),
          ItemPath(aNewPath, lvNewIdx), lvId, aState);
      end
      else
        AddDiff(aState, TPropDifference.Create(ItemPath(aOldPath, i), ItemPath(aOldPath, i),
          'Exists in old', 'Missing in new', lvId));
    end;

    for i := 0 to aNew.Count - 1 do
      if not lvMatched[i] then
        AddDiff(aState, TPropDifference.Create(ItemPath(aNewPath, i), ItemPath(aNewPath, i),
          'Missing in old', 'Exists in new', IntToStr(i)));
  finally
    lvById.Free;
  end;
end;

class function TbpObjectComparer.CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
var
  lvState: TCompareState;
begin
  lvState.Count := 0;
  CompareProps(aOld, aNew, '', '', '', lvState);
  SetLength(lvState.Diffs, lvState.Count);
  Result := lvState.Diffs;
end;

class function TbpObjectComparer.CompareObjectsAsString(aOld, aNew: TPersistent): string;
var
  lvDiffs: TPropDifferences;
  lvStrings: TStringList;
  I: Integer;
begin
  lvDiffs := CompareObjects(aOld, aNew);
  lvStrings := TStringList.Create;
  try
    for I := 0 to High(lvDiffs) do
    begin
      lvStrings.Add(Format('%s; OldValue: %s; NewValue: %s; Idx: %s', [
        aOld.ClassName + '.' + lvDiffs[I].OldPropPath,
        VarToStr(lvDiffs[I].OldValue),
        VarToStr(lvDiffs[I].NewValue),
        lvDiffs[I].Idx]));
    end;
    Result := lvStrings.Text;
  finally
    lvStrings.Free;
  end;
end;

class function TbpObjectComparer.StripIndexFromProperty(const aProp: string): string;
var
  lvResult: string;
  lvChar: Char;
  lvInBrackets: Boolean;
  I: Integer;
begin
  lvResult := '';
  lvInBrackets := False;

  for I := 1 to Length(aProp) do
  begin
    lvChar := aProp[I];
    if lvChar = '[' then
      lvInBrackets := True
    else if lvChar = ']' then
      lvInBrackets := False
    else if not lvInBrackets then
      lvResult := lvResult + lvChar;
  end;

  Result := lvResult;
end;

end.
