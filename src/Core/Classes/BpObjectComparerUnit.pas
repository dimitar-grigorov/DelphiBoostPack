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
    
    property OldPropPath: string read GetOldPropPath;
    property NewPropPath: string read GetNewPropPath;
    property OldValue: Variant read GetOldValue;
    property NewValue: Variant read GetNewValue;
  end;

  TPropDifference = class(TInterfacedObject, IPropDifference)
  private
    FOldPropPath: string;
    FNewPropPath: string;
    FOldValue: Variant;
    FNewValue: Variant;
  public
    constructor Create(const aOldPropPath, aNewPropPath: string; const aOldValue,
      aNewValue: Variant); overload;
    constructor Create(const aPropPath: string; const aOldValue, aNewValue: Variant); overload;
    function GetOldPropPath: string;
    function GetNewPropPath: string;
    function GetOldValue: Variant;
    function GetNewValue: Variant;
  end;

  TPropDifferences = array of IPropDifference;

type
  TBpObjectComparer = class
  private
    class procedure AppendDifference(var aDiffs: TPropDifferences; const aDiff: IPropDifference);
    class procedure AppendDifferences(var aTargetDiffs: TPropDifferences; const aSourceDiffs: TPropDifferences);
    class function InternalCompareProperties(aOld, aNew: TPersistent; const aOldPropPath, aNewPropPath: string): TPropDifferences;
    class procedure CompareCollectionItems(aOldColl, aNewColl: TCollection; const aOldPropPath, aNewPropPath: string; var aDiffs: TPropDifferences);
  public
    class function CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
    class function CompareObjectsAsString(aOld, aNew: TPersistent): string;
  end;

implementation

uses
  TypInfo, StrUtils, IUniqueIdUnit, Math;

constructor TPropDifference.Create(const aOldPropPath, aNewPropPath: string; const aOldValue,
  aNewValue: Variant);
begin
  inherited Create;
  FOldPropPath := aOldPropPath;
  FNewPropPath := aNewPropPath;
  FOldValue := aOldValue;
  FNewValue := aNewValue;
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

class function TBpObjectComparer.InternalCompareProperties(aOld, aNew: TPersistent; const aOldPropPath, aNewPropPath: string): TPropDifferences;
var
  PropList: PPropList;
  PropCount, i: Integer;
  PropInfo: PPropInfo;
  lvOldValue, lvNewValue: Variant;
  lvOldPropPath, lvNewPropPath: string;
begin
  SetLength(Result, 0);
  PropCount := GetPropList(aOld.ClassInfo, tkProperties, nil);
  GetMem(PropList, PropCount * SizeOf(Pointer));
  try
    GetPropList(aOld.ClassInfo, tkProperties, PropList);
    for i := 0 to PropCount - 1 do
    begin
      PropInfo := PropList^[i];
      lvOldPropPath := IfThen(aOldPropPath <> '', aOldPropPath + '.', '') + PropInfo^.Name;
      if (aNewPropPath = EmptyStr) then
        lvNewPropPath := lvOldPropPath
      else
        lvNewPropPath := aNewPropPath + '.' + PropInfo^.Name;

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
            begin
              CompareCollectionItems(TCollection(GetObjectProp(aOld, PropInfo)),
                TCollection(GetObjectProp(aNew, PropInfo)), lvOldPropPath, lvNewPropPath, Result);
            end;
            Continue; // Skip the AppendDifference call for collections, as CompareCollectionItems handles it.
          end;
      else
        Continue; // Skip properties that don't match any handled types.
      end;

      if (lvOldValue <> lvNewValue) then
        AppendDifference(Result, TPropDifference.Create(lvOldPropPath, lvOldValue, lvNewValue));
    end;
  finally
    FreeMem(PropList);
  end;
end;

class procedure TBpObjectComparer.CompareCollectionItems(aOldColl, aNewColl: TCollection; const aOldPropPath, aNewPropPath: string; var aDiffs: TPropDifferences);
var
  I, lvFoundItemIdx: Integer;
  lvItem1, lvItem2: TPersistent;
  lvUniqueIdIntf: IUniqueId;
  lvUniqueId: string;
  lvProcessedItems: TStringList;
const
  lcColItemFmt = '%s[%d]';

  function _FindItemByUniqueId(aCol: TCollection; const aUniqueId: string; out outItemIndex: Integer): TPersistent;
  var
    J: Integer;
    lvItem: TPersistent;
    lvTestUniqueIdIntf: IUniqueId;
  begin
    Result := nil;
    outItemIndex := -1;
    for J := 0 to aCol.Count - 1 do
    begin
      lvItem := aCol.Items[J] as TPersistent;
      if Supports(lvItem, IUniqueId, lvTestUniqueIdIntf) then
      begin
        if lvTestUniqueIdIntf.GetUniqueId = aUniqueId then
        begin
          Result := lvItem;
          outItemIndex := J;
          Break;
        end;
      end;
    end;
  end;

begin
  // Compare collection item counts
  if (aOldColl.Count <> aNewColl.Count) then
    AppendDifference(aDiffs, TPropDifference.Create(aOldPropPath + '.Count', aOldColl.Count, aNewColl.Count));

  // Initialize a list to track processed items in the new collection
  lvProcessedItems := TStringList.Create;
  try
    // Compare items from the old collection to the new collection
    for I := 0 to aOldColl.Count - 1 do
    begin
      lvItem1 := aOldColl.Items[I] as TPersistent;
      // IUniqueId
      if Supports(lvItem1, IUniqueId, lvUniqueIdIntf) then
      begin
        lvUniqueId := lvUniqueIdIntf.GetUniqueId;
        lvItem2 := _FindItemByUniqueId(aNewColl, lvUniqueId, lvFoundItemIdx);
        if Assigned(lvItem2) then
        begin
          AppendDifferences(aDiffs, InternalCompareProperties(lvItem1, lvItem2,
            Format(lcColItemFmt, [aOldPropPath, I]), Format(lcColItemFmt, [aNewPropPath, lvFoundItemIdx])));
          lvProcessedItems.Add(IntToStr(lvFoundItemIdx));
        end
        else
        begin
          AppendDifference(aDiffs, TPropDifference.Create(Format(lcColItemFmt, [aOldPropPath, I]),
            'Exists in old', 'Missing in new'));
        end;
      end
      else  // Index based comparison
      begin
        if (I < aNewColl.Count) then
        begin
          lvItem2 := aNewColl.Items[I] as TPersistent;
          AppendDifferences(aDiffs, InternalCompareProperties(lvItem1, lvItem2,
            Format(lcColItemFmt, [aOldPropPath, I]), Format(lcColItemFmt, [aNewPropPath, I])));
          lvProcessedItems.Add(IntToStr(I));
        end
        else
        begin
          AppendDifference(aDiffs, TPropDifference.Create(Format(lcColItemFmt, [aOldPropPath, I]),
            'Exists in old', 'Missing in new'));
        end;
      end;
    end;

    // Check for items in the new collection that are not in the old collection
    for I := 0 to aNewColl.Count - 1 do
    begin
      if lvProcessedItems.IndexOf(IntToStr(I)) = -1 then
      begin
        AppendDifference(aDiffs, TPropDifference.Create(Format(lcColItemFmt, [aNewPropPath, I]),
          'Missing in old', 'Exists in new'));
      end;
    end;
  finally
    lvProcessedItems.Free;
  end;
end;


class function TBpObjectComparer.CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
begin
  Result := InternalCompareProperties(aOld, aNew, '', '');
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

