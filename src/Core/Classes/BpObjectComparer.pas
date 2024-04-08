unit BpObjectComparer;

interface

uses
  Classes;

type
  IUniqueId = interface
    ['{3C43BE0B-C5A3-4C7E-949C-E15DF5E082A4}']
    function GetUniqueId: string;
  end;

  TPropertyDifference = record
    PropPath: string;
    OldValue, NewValue: Variant;
    class function Create(const aPropPath: string; const aOldValue, aNewValue: Variant): TPropertyDifference; static;
  end;

  TPropertyDifferences = array of TPropertyDifference;

type
  TBpObjectComparer = class
  private
    procedure AppendDifference(var Differences: TPropertyDifferences; const Diff: TPropertyDifference);
    procedure AppendDifferences(var TargetDiffs: TPropertyDifferences; const SourceDiffs: TPropertyDifferences);
    function InternalCompareProperties(aOld, aNew: TPersistent; const aPropPath: string): TPropertyDifferences;
    procedure CompareCollectionItems(aOldColl, aNewColl: TCollection; const aPropPath: string; var aDifferences: TPropertyDifferences);
  public
    function CompareObjects(aOld, aNew: TPersistent): TPropertyDifferences;
    function CompareObjectsAsString(aOld, aNew: TPersistent): string;
  end;

implementation

uses
  TypInfo, StrUtils, SysUtils, Variants;

class function TPropertyDifference.Create(const aPropPath: string; const aOldValue, aNewValue: Variant): TPropertyDifference;
begin
  Result.PropPath := aPropPath;
  Result.OldValue := aOldValue;
  Result.NewValue := aNewValue;
end;

procedure TBpObjectComparer.AppendDifference(var Differences: TPropertyDifferences; const Diff: TPropertyDifference);
begin
  SetLength(Differences, Length(Differences) + 1);
  Differences[High(Differences)] := Diff;
end;

procedure TBpObjectComparer.AppendDifferences(var TargetDiffs: TPropertyDifferences; const SourceDiffs: TPropertyDifferences);
var
  i: Integer;
begin
  for i := Low(SourceDiffs) to High(SourceDiffs) do
    AppendDifference(TargetDiffs, SourceDiffs[i]);
end;

function TBpObjectComparer.InternalCompareProperties(aOld, aNew: TPersistent; const aPropPath: string): TPropertyDifferences;
var
  PropList: PPropList;
  PropCount, i: Integer;
  PropInfo: PPropInfo;
  NewValue, OldValue: Variant;
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
      NewPropPath := IfThen(aPropPath <> '', aPropPath + '.', '') + string(PropInfo^.Name);

      if PropInfo^.PropType^.Kind in [tkInteger, tkChar, tkEnumeration, tkFloat, tkString, tkSet, tkWChar, tkLString, tkWString, tkVariant] then
      begin
        NewValue := GetPropValue(aOld, PropInfo^.Name);
        OldValue := GetPropValue(aNew, PropInfo^.Name);
        if NewValue <> OldValue then
          AppendDifference(Result, TPropertyDifference.Create(NewPropPath, OldValue, NewValue))
      end
      else if (PropInfo^.PropType^.Kind = tkClass) and (GetObjectProp(aOld, PropInfo) is TCollection) then
      begin
        CompareCollectionItems(TCollection(GetObjectProp(aOld, PropInfo)), TCollection(GetObjectProp(aNew, PropInfo)), NewPropPath, Result);
      end;
    end;
  finally
    FreeMem(PropList);
  end;
end;

procedure TBpObjectComparer.CompareCollectionItems(aOldColl, aNewColl: TCollection; const aPropPath: string; var aDifferences: TPropertyDifferences);
var
  I: Integer;
  lvItem1, lvItem2: TPersistent;
  lvUniqueIdIntf: IUniqueId;
  lvUniqueId: string;
  lvFound: Boolean;

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
  if aOldColl.Count <> aNewColl.Count then
  begin
    AppendDifference(aDifferences, TPropertyDifference.Create(aPropPath, aOldColl.Count, aNewColl.Count));
    Exit;
  end;

  for I := 0 to aOldColl.Count - 1 do
  begin
    lvItem1 := aOldColl.Items[I] as TPersistent;
    lvFound := False;
    if Supports(lvItem1, IUniqueId, lvUniqueIdIntf) then
    begin
      lvUniqueId := lvUniqueIdIntf.GetUniqueId;
      // Find the matching item in aCol2 by UniqueId
      lvItem2 := _FindItemByUniqueId(aNewColl, lvUniqueId);
      if Assigned(lvItem2) then
      begin
        AppendDifferences(aDifferences, InternalCompareProperties(lvItem1, lvItem2, aPropPath + '[' + lvUniqueId + ']'));
        lvFound := True;
      end;
    end;
    if not lvFound then
    begin
      // Handle the case where no unique identifier is available or matching item not found
      // This could involve logging, raising an error, or appending a specific difference indicating the mismatch.
    end;
  end;
end;

function TBpObjectComparer.CompareObjects(aOld, aNew: TPersistent): TPropertyDifferences;
begin
  Result := InternalCompareProperties(aOld, aNew, '');
end;

function TBpObjectComparer.CompareObjectsAsString(aOld, aNew: TPersistent): string;
var
  lvDiffs: TPropertyDifferences;
  lvStrings: TStringList;
  I: Integer;
begin
  lvDiffs := CompareObjects(aOld, aNew);
  lvStrings := TStringList.Create;
  try
    for I := 0 to High(lvDiffs) do
    begin
      lvStrings.Add(Format('%s; OldValue: %s; NewValue: %s',
        [lvDiffs[I].PropPath, VarToStr(lvDiffs[I].OldValue), VarToStr(lvDiffs[I].NewValue)]));
    end;
    Result := lvStrings.Text;
  finally
    lvStrings.Free;
  end;
end;

end.

