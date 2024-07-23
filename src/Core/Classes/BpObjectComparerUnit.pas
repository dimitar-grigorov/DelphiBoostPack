unit BpObjectComparerUnit;

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
    function GetOldId: string;
    function GetNewId: string;

    property OldPropPath: string read GetOldPropPath;
    property NewPropPath: string read GetNewPropPath;
    property OldValue: Variant read GetOldValue;
    property NewValue: Variant read GetNewValue;
    property OldId: string read GetOldId;
    property NewId: string read GetNewId;
  end;

  TPropDifference = class(TInterfacedObject, IPropDifference)
  private
    FOldPropPath: string;
    FNewPropPath: string;
    FOldValue: Variant;
    FNewValue: Variant;
    FOldId: string;
    FNewId: string;
  public
    constructor Create(const aOldPropPath, aNewPropPath: string; const aOldValue,
      aNewValue: Variant; const aOldId, aNewId: string); overload;
    constructor Create(const aPropPath: string; const aOldValue, aNewValue: Variant); overload;
    function GetOldPropPath: string;
    function GetNewPropPath: string;
    function GetOldValue: Variant;
    function GetNewValue: Variant;
    function GetOldId: string;
    function GetNewId: string;
  end;

  TPropDifferences = array of IPropDifference;

type
  TBpObjectComparer = class
  private
    class procedure AppendDifference(var aDiffs: TPropDifferences; const aDiff: IPropDifference);
    class procedure AppendDifferences(var aTargetDiffs: TPropDifferences; const aSourceDiffs: TPropDifferences);
    class function InternalCompareProperties(aOld, aNew: TPersistent; const aPropPath: string): TPropDifferences;
    class procedure CompareCollectionItems(aOldColl, aNewColl: TCollection; const aPropPath: string; var aDiffs: TPropDifferences);
  public
    class function CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
    class function CompareObjectsAsString(aOld, aNew: TPersistent): string;
  end;

implementation

uses
  TypInfo, StrUtils, IUniqueIdUnit;

constructor TPropDifference.Create(const aOldPropPath, aNewPropPath: string; const aOldValue,
  aNewValue: Variant; const aOldId, aNewId: string);
begin
  inherited Create;
  FOldPropPath := aOldPropPath;
  FNewPropPath := aNewPropPath;
  FOldValue := aOldValue;
  FNewValue := aNewValue;
  FOldId := aOldId;
  FNewId := aNewId;
end;

constructor TPropDifference.Create(const aPropPath: string; const aOldValue, aNewValue: Variant);
begin
  Create(aPropPath, aPropPath, aOldValue, aNewValue, '', '');
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

function TPropDifference.GetOldId: string;
begin
  Result := FOldId;
end;

function TPropDifference.GetNewId: string;
begin
  Result := FNewId;
end;

class procedure TBpObjectComparer.AppendDifference(var aDiffs: TPropDifferences; const aDiff: IPropDifference);
begin
  SetLength(aDiffs, Length(aDiffs) + 1);
  aDiffs[High(aDiffs)] := aDiff;
end;

class procedure TBpObjectComparer.AppendDifferences(var aTargetDiffs: TPropDifferences; const aSourceDiffs: TPropDifferences);
var
  i: Integer;
begin
  for i := Low(aSourceDiffs) to High(aSourceDiffs) do
    AppendDifference(aTargetDiffs, aSourceDiffs[i]);
end;

class function TBpObjectComparer.InternalCompareProperties(aOld, aNew: TPersistent; const aPropPath: string): TPropDifferences;
var
  PropList: PPropList;
  PropCount, i: Integer;
  PropInfo: PPropInfo;
  lvOldValue, lvNewValue: Variant;
  NewPropPath: string;
begin
  SetLength(Result, 0);
  PropCount := GetPropList(aOld.ClassInfo, tkProperties, nil);
  GetMem(PropList, PropCount * SizeOf(Pointer));
  try
    GetPropList(aOld.ClassInfo, tkProperties, PropList);
    for i := 0 to PropCount - 1 do
    begin
      PropInfo := PropList^[i];
      NewPropPath := IfThen(aPropPath <> '', aPropPath + '.', '') + PropInfo^.Name;

      case PropInfo^.PropType^.Kind of
        tkInteger, tkEnumeration, tkFloat, tkString, tkSet, tkLString, tkWString, tkVariant:
          begin
            lvOldValue := GetPropValue(aOld, PropInfo^.Name);
            lvNewValue := GetPropValue(aNew, PropInfo^.Name);
          end;
        tkChar, tkWChar:
          begin
            lvOldValue := Char(GetOrdProp(aOld, PropInfo^.Name));
            lvNewValue := Char(GetOrdProp(aNew, PropInfo^.Name));
          end;
        tkClass:
          begin
            if GetObjectProp(aOld, PropInfo) is TCollection then
              CompareCollectionItems(TCollection(GetObjectProp(aOld, PropInfo)),
                TCollection(GetObjectProp(aNew, PropInfo)), NewPropPath, Result);
            Continue; // Skip the AppendDifference call for collections, as CompareCollectionItems handles it.
          end;
      else
        Continue; // Skip properties that don't match any handled types.
      end;

      if (lvOldValue <> lvNewValue) then
        AppendDifference(Result, TPropDifference.Create(NewPropPath, lvOldValue, lvNewValue));
    end;
  finally
    FreeMem(PropList);
  end;
end;

class procedure TBpObjectComparer.CompareCollectionItems(aOldColl, aNewColl: TCollection; const aPropPath: string; var aDiffs: TPropDifferences);
var
  I: Integer;
  lvItem1, lvItem2: TPersistent;
  lvUniqueIdIntf: IUniqueId;
  lvUniqueId: string;

  function _FindItemByUniqueId(aCol: TCollection; const aUniqueId: string): TPersistent;
  var
    J: Integer;
    lvItem: TPersistent;
    lvTestUniqueIdIntf: IUniqueId;
  begin
    Result := nil;
    for J := 0 to aCol.Count - 1 do
    begin
      lvItem := aCol.Items[J] as TPersistent;
      if Supports(lvItem, IUniqueId, lvTestUniqueIdIntf) then
      begin
        if lvTestUniqueIdIntf.GetUniqueId = aUniqueId then
        begin
          Result := lvItem;
          Break;
        end;
      end;
    end;
  end;

begin
  // Check for count difference but do not exit
  if (aOldColl.Count <> aNewColl.Count) then
    AppendDifference(aDiffs, TPropDifference.Create(aPropPath + '.Count', aOldColl.Count, aNewColl.Count));

  // Compare items from the old collection to the new collection
  for I := 0 to aOldColl.Count - 1 do
  begin
    lvItem1 := aOldColl.Items[I] as TPersistent;
    if Supports(lvItem1, IUniqueId, lvUniqueIdIntf) then
    begin
      lvUniqueId := lvUniqueIdIntf.GetUniqueId;
      lvItem2 := _FindItemByUniqueId(aNewColl, lvUniqueId);

      if Assigned(lvItem2) then
      begin
        AppendDifferences(aDiffs, InternalCompareProperties(lvItem1, lvItem2,
          aPropPath + '[' + lvUniqueId + ']'));
      end
      else
      begin
        AppendDifference(aDiffs, TPropDifference.Create(aPropPath +
          '[' + lvUniqueId + ']', 'Exists in old', 'Missing in new'));
      end;
    end;
  end;

  // Check for items in the new collection that are not in the old collection
  for I := 0 to aNewColl.Count - 1 do
  begin
    lvItem2 := aNewColl.Items[I] as TPersistent;
    if Supports(lvItem2, IUniqueId, lvUniqueIdIntf) then
    begin
      lvUniqueId := lvUniqueIdIntf.GetUniqueId;
      lvItem1 := _FindItemByUniqueId(aOldColl, lvUniqueId);

      if not Assigned(lvItem1) then
      begin
        AppendDifference(aDiffs, TPropDifference.Create(aPropPath +
          '[' + lvUniqueId + ']', 'Missing in old', 'Exists in new'));
      end;
    end;
  end;
end;

class function TBpObjectComparer.CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
begin
  Result := InternalCompareProperties(aOld, aNew, '');
end;

class function TBpObjectComparer.CompareObjectsAsString(aOld, aNew: TPersistent): string;
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
      lvStrings.Add(Format('%s; OldValue: %s; NewValue: %s', [
        aOld.ClassName + '.' + lvDiffs[I].OldPropPath,
        VarToStr(lvDiffs[I].OldValue),
        VarToStr(lvDiffs[I].NewValue)]));
    end;
    Result := lvStrings.Text;
  finally
    lvStrings.Free;
  end;
end;

end.

