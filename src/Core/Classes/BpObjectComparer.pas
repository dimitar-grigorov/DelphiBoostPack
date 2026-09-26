unit BpObjectComparer;

// Diffs two objects by RTTI and reports the changed published properties, nested objects and collections included.

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

  // raised by CompareObjects for a nil argument or two arguments of different classes
  EbpObjectComparer = class(Exception);

  TbpObjectComparer = class
  public
    class function CompareObjects(aOld, aNew: TPersistent): TPropDifferences; overload;
    // a tolerance of 0 is exact and dates are always exact; a bare excluded name skips at any depth,
    // a dotted path from the root ('Lines.ModifiedOn', no item indexes) only there
    class function CompareObjects(aOld, aNew: TPersistent; aFloatTolerance: Double;
      const aExcludedProps: array of string): TPropDifferences; overload;
    class function CompareObjectsAsString(aOld, aNew: TPersistent): string; overload;
    class function CompareObjectsAsString(aOld, aNew: TPersistent; aFloatTolerance: Double;
      const aExcludedProps: array of string): string; overload;
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
    Path: TList; // the old-side objects open on the current descent, so a cycle is skipped, not followed
    FloatTolerance: Double;
    Excluded: array of string; // a handful of names, scanned linearly with nothing to free
    ExcludesPaths: Boolean;    // an entry has a dot, so the stripped path is worth building
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

// a tolerance on a date would hide a change of up to that many days
function IsDateTimeType(aTypeInfo: PTypeInfo): Boolean;
var
  lvName: string;
begin
  lvName := string(aTypeInfo^.Name);
  Result := SameText(lvName, 'TDateTime') or SameText(lvName, 'TDate') or SameText(lvName, 'TTime');
end;

function FloatsDiffer(const aOld, aNew, aTolerance: Extended): Boolean;
begin
  // the equality test first keeps Inf - Inf, an invalid operation, out of the subtraction
  Result := (aOld <> aNew) and (Abs(aOld - aNew) > aTolerance);
end;

// property names are identifiers, so the match ignores case
function InList(const aList: array of string; const aValue: string): Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := 0 to High(aList) do
    if SameText(aList[i], aValue) then
      Exit;
  Result := False;
end;

function IsExcluded(const aState: TCompareState; const aName, aPath: string): Boolean;
begin
  Result := InList(aState.Excluded, aName) or
    (aState.ExcludesPaths and InList(aState.Excluded, TbpObjectComparer.StripIndexFromProperty(aPath)));
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

procedure CompareProps(aOld, aNew: TObject; const aOldPath, aNewPath, aIdx: string;
  var aState: TCompareState); forward;

function ComponentName(aComponent: TComponent): string;
begin
  Result := aComponent.Name;
  if Result = '' then
    Result := aComponent.ClassName;
end;

// nil and a changed class are differences at the object's own path; only equal classes are walked
procedure ComparePair(aOld, aNew: TObject; const aOldPath, aNewPath, aIdx: string;
  var aState: TCompareState);
begin
  if aNew = nil then
  begin
    if aOld <> nil then
      AddDiff(aState, TPropDifference.Create(aOldPath, aNewPath, 'Exists in old', 'Missing in new', aIdx));
  end
  else if aOld = nil then
    AddDiff(aState, TPropDifference.Create(aOldPath, aNewPath, 'Missing in old', 'Exists in new', aIdx))
  else if aOld.ClassType <> aNew.ClassType then
    AddDiff(aState, TPropDifference.Create(aOldPath, aNewPath, aOld.ClassName, aNew.ClassName, aIdx))
  else if (aOld is TComponent) and not (csSubComponent in TComponent(aOld).ComponentStyle) then
  begin
    // a reference, as in streaming: identity is the value, the name is what the log can show
    if aOld <> aNew then
      AddDiff(aState, TPropDifference.Create(aOldPath, aNewPath,
        ComponentName(TComponent(aOld)), ComponentName(TComponent(aNew)), aIdx));
  end
  else if aState.Path.IndexOf(aOld) < 0 then
  begin
    aState.Path.Add(aOld);
    try
      if aOld is TCollection then
        CompareCollections(TCollection(aOld), TCollection(aNew), aOldPath, aNewPath, aState)
      else if aOld.ClassInfo <> nil then
        CompareProps(aOld, aNew, aOldPath, aNewPath, aIdx, aState);
    finally
      aState.Path.Delete(aState.Path.Count - 1);
    end;
  end;
end;

procedure CompareProps(aOld, aNew: TObject; const aOldPath, aNewPath, aIdx: string;
  var aState: TCompareState);
var
  lvPropList: PPropList;
  lvPropCount, i: Integer;
  lvPropInfo: PPropInfo;
  lvOldValue, lvNewValue: Variant;
  lvOldPropPath, lvNewPropPath: string;
  lvOldWide, lvNewWide: WideString;
  lvDiffers: Boolean;
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
      if IsExcluded(aState, string(lvPropInfo^.Name), lvOldPropPath) then
        Continue;

      case lvPropInfo^.PropType^.Kind of
        // tkUString exists from Delphi 2009 on; without it every string property is skipped
        {$IF Declared(tkUString)}
        tkUString,
        {$IFEND}
        tkInteger, tkInt64, tkEnumeration, tkFloat, tkString, tkSet, tkLString, tkWString, tkVariant:
          begin
            lvOldValue := GetPropValue(aOld, string(lvPropInfo^.Name));
            lvNewValue := GetPropValue(aNew, string(lvPropInfo^.Name));
          end;
        tkChar:
          begin
            lvOldValue := Char(GetOrdProp(aOld, lvPropInfo));
            lvNewValue := Char(GetOrdProp(aNew, lvPropInfo));
          end;
        tkWChar:
          begin
            // via WideString, or Char drops the high byte before Delphi 2009
            lvOldWide := WideChar(GetOrdProp(aOld, lvPropInfo));
            lvNewWide := WideChar(GetOrdProp(aNew, lvPropInfo));
            lvOldValue := lvOldWide;
            lvNewValue := lvNewWide;
          end;
        tkClass:
          begin
            ComparePair(GetObjectProp(aOld, lvPropInfo), GetObjectProp(aNew, lvPropInfo),
              lvOldPropPath, lvNewPropPath, aIdx, aState);
            Continue;
          end;
      else
        Continue; // unhandled property kinds are ignored, not diffed
      end;

      if (lvPropInfo^.PropType^.Kind = tkFloat) and (aState.FloatTolerance > 0) and
        not IsDateTimeType(lvPropInfo^.PropType^) then
        lvDiffers := FloatsDiffer(GetFloatProp(aOld, lvPropInfo), GetFloatProp(aNew, lvPropInfo),
          aState.FloatTolerance)
      else
        lvDiffers := VarsDiffer(lvOldValue, lvNewValue);
      if lvDiffers then
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
        ComparePair(lvOldItem, aNew.Items[lvNewIdx], ItemPath(aOldPath, i),
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
begin
  Result := CompareObjects(aOld, aNew, 0, []);
end;

class function TbpObjectComparer.CompareObjects(aOld, aNew: TPersistent; aFloatTolerance: Double;
  const aExcludedProps: array of string): TPropDifferences;
var
  lvState: TCompareState;
  i: Integer;
begin
  if (aOld = nil) or (aNew = nil) then
    raise EbpObjectComparer.Create('Cannot compare a nil object');
  if aOld.ClassType <> aNew.ClassType then
    raise EbpObjectComparer.CreateFmt('Cannot compare a %s with a %s', [aOld.ClassName, aNew.ClassName]);
  if aFloatTolerance < 0 then
    raise EbpObjectComparer.Create('The float tolerance cannot be negative');
  lvState.Count := 0;
  lvState.FloatTolerance := aFloatTolerance;
  lvState.ExcludesPaths := False;
  SetLength(lvState.Excluded, Length(aExcludedProps));
  for i := 0 to High(aExcludedProps) do
  begin
    lvState.Excluded[i] := aExcludedProps[i];
    if Pos('.', aExcludedProps[i]) > 0 then
      lvState.ExcludesPaths := True;
  end;
  lvState.Path := TList.Create;
  try
    ComparePair(aOld, aNew, '', '', '', lvState);
  finally
    lvState.Path.Free;
  end;
  SetLength(lvState.Diffs, lvState.Count);
  Result := lvState.Diffs;
end;

class function TbpObjectComparer.CompareObjectsAsString(aOld, aNew: TPersistent): string;
begin
  Result := CompareObjectsAsString(aOld, aNew, 0, []);
end;

class function TbpObjectComparer.CompareObjectsAsString(aOld, aNew: TPersistent; aFloatTolerance: Double;
  const aExcludedProps: array of string): string;
var
  lvDiffs: TPropDifferences;
  lvStrings: TStringList;
  I: Integer;
begin
  lvDiffs := CompareObjects(aOld, aNew, aFloatTolerance, aExcludedProps);
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
  lvChar: Char;
  lvInBrackets: Boolean;
  I, lvLen: Integer;
begin
  // sized once and trimmed, not grown a char at a time
  SetLength(Result, Length(aProp));
  lvLen := 0;
  lvInBrackets := False;
  for I := 1 to Length(aProp) do
  begin
    lvChar := aProp[I];
    if lvChar = '[' then
      lvInBrackets := True
    else if lvChar = ']' then
      lvInBrackets := False
    else if not lvInBrackets then
    begin
      Inc(lvLen);
      Result[lvLen] := lvChar;
    end;
  end;
  SetLength(Result, lvLen);
end;

end.
