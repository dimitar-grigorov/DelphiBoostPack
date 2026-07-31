unit BpObjectComparer;

// Diffs two objects by RTTI and reports which published properties changed,
// collections included.

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
  private
    class procedure AppendDifference(var aDiffs: TPropDifferences; const aDiff: IPropDifference);
    class procedure AppendDifferences(var aTargetDiffs: TPropDifferences; const aSourceDiffs: TPropDifferences);
    class function InternalCompareProperties(aOld, aNew: TPersistent; const aOldPropPath, aNewPropPath: string; const aIdx: string = ''): TPropDifferences;
    class procedure CompareCollectionItems(aOldColl, aNewColl: TCollection; const aOldPropPath, aNewPropPath: string; var aDiffs: TPropDifferences);
  public
    class function CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
    class function CompareObjectsAsString(aOld, aNew: TPersistent): string;
    class function StripIndexFromProperty(const aProp: string): string;
  end;

implementation

uses
  TypInfo, StrUtils, UniqueIdIntf, Math;

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

class procedure TbpObjectComparer.AppendDifference(var aDiffs: TPropDifferences; const aDiff: IPropDifference);
begin
  SetLength(aDiffs, Length(aDiffs) + 1);
  aDiffs[High(aDiffs)] := aDiff;
end;

class procedure TbpObjectComparer.AppendDifferences(var aTargetDiffs: TPropDifferences; const aSourceDiffs: TPropDifferences);
var
  i: Integer;
begin
  for i := Low(aSourceDiffs) to High(aSourceDiffs) do
    AppendDifference(aTargetDiffs, aSourceDiffs[i]);
end;

class function TbpObjectComparer.InternalCompareProperties(aOld, aNew: TPersistent; const aOldPropPath, aNewPropPath: string; const aIdx: string = ''): TPropDifferences;
var
  lvPropList: PPropList;
  lvPropCount, i: Integer;
  lvPropInfo: PPropInfo;
  lvOldValue, lvNewValue: Variant;
  lvOldPropPath, lvNewPropPath: string;
begin
  SetLength(Result, 0);
  lvPropCount := GetPropList(aOld.ClassInfo, tkProperties, nil);
  GetMem(lvPropList, lvPropCount * SizeOf(Pointer));
  try
    GetPropList(aOld.ClassInfo, tkProperties, lvPropList);
    for i := 0 to lvPropCount - 1 do
    begin
      lvPropInfo := lvPropList^[i];
      lvOldPropPath := IfThen(aOldPropPath <> '', aOldPropPath + '.', '') + string(lvPropInfo^.Name);
      if (aNewPropPath = EmptyStr) then
        lvNewPropPath := lvOldPropPath
      else
        lvNewPropPath := aNewPropPath + '.' + string(lvPropInfo^.Name);

      case lvPropInfo^.PropType^.Kind of
        tkInteger, tkEnumeration, tkFloat, tkString, tkSet, tkLString, tkWString, tkVariant:
          begin
            lvOldValue := GetPropValue(aOld, string(lvPropInfo^.Name));
            lvNewValue := GetPropValue(aNew, string(lvPropInfo^.Name));
          end;
        tkChar, tkWChar:
          begin
            lvOldValue := Char(GetOrdProp(aOld, string(lvPropInfo^.Name)));
            lvNewValue := Char(GetOrdProp(aNew, string(lvPropInfo^.Name)));
          end;
        tkClass:
          begin
            if GetObjectProp(aOld, lvPropInfo) is TCollection then
            begin
              CompareCollectionItems(TCollection(GetObjectProp(aOld, lvPropInfo)),
                TCollection(GetObjectProp(aNew, lvPropInfo)), lvOldPropPath, lvNewPropPath, Result);
            end;
            Continue; // CompareCollectionItems already appended these, not AppendDifference
          end;
      else
        Continue; // unhandled property kinds are ignored, not diffed
      end;

      if (lvOldValue <> lvNewValue) then
        AppendDifference(Result, TPropDifference.Create(lvOldPropPath, lvNewPropPath, lvOldValue, lvNewValue, aIdx));
    end;
  finally
    FreeMem(lvPropList);
  end;
end;

class procedure TbpObjectComparer.CompareCollectionItems(aOldColl, aNewColl: TCollection;
  const aOldPropPath, aNewPropPath: string; var aDiffs: TPropDifferences);
var
  I, lvFoundItemIdx: Integer;
  lvItem1, lvItem2: TPersistent;
  lvUniqueIdIntf: IUniqueId;
  lvUniqueId: string;
  lvProcessedItems: TStringList;

  function _GetPropIdx(const aProp: string; const aIdx: Integer): string;
  begin
    Result := Format('%s[%d]', [aProp, aIdx]);
  end;

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
  if (aOldColl.Count <> aNewColl.Count) then
    AppendDifference(aDiffs, TPropDifference.Create(aOldPropPath + '.Count', aOldColl.Count, aNewColl.Count));

  lvProcessedItems := TStringList.Create; // new-collection indices already matched, so leftovers can be reported below
  try
    for I := 0 to aOldColl.Count - 1 do
    begin
      lvItem1 := aOldColl.Items[I] as TPersistent;
      if Supports(lvItem1, IUniqueId, lvUniqueIdIntf) then
      begin
        lvUniqueId := lvUniqueIdIntf.GetUniqueId;
        lvItem2 := _FindItemByUniqueId(aNewColl, lvUniqueId, lvFoundItemIdx);
        if Assigned(lvItem2) then
        begin
          AppendDifferences(aDiffs, InternalCompareProperties(lvItem1, lvItem2,
            _GetPropIdx(aOldPropPath, I),
            _GetPropIdx(aNewPropPath, lvFoundItemIdx), lvUniqueId));
          lvProcessedItems.Add(IntToStr(lvFoundItemIdx));
        end
        else
        begin
          AppendDifference(aDiffs, TPropDifference.Create(_GetPropIdx(aOldPropPath, I),
            'Exists in old', 'Missing in new', lvUniqueId));
        end;
      end
      else  // index based comparison
      begin
        if (I < aNewColl.Count) then
        begin
          lvItem2 := aNewColl.Items[I] as TPersistent;
          AppendDifferences(aDiffs, InternalCompareProperties(lvItem1, lvItem2,
            _GetPropIdx(aOldPropPath, I),
            _GetPropIdx(aNewPropPath, I), IntToStr(I)));
          lvProcessedItems.Add(IntToStr(I));
        end
        else
        begin
          AppendDifference(aDiffs, TPropDifference.Create(_GetPropIdx(aOldPropPath, I),
            'Exists in old', 'Missing in new', IntToStr(I)));
        end;
      end;
    end;

    for I := 0 to aNewColl.Count - 1 do
    begin
      if lvProcessedItems.IndexOf(IntToStr(I)) = -1 then
      begin
        AppendDifference(aDiffs, TPropDifference.Create(_GetPropIdx(aNewPropPath, I),
          'Missing in old', 'Exists in new', IntToStr(I)));
      end;
    end;
  finally
    lvProcessedItems.Free;
  end;
end;

class function TbpObjectComparer.CompareObjects(aOld, aNew: TPersistent): TPropDifferences;
begin
  Result := InternalCompareProperties(aOld, aNew, '', '');
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

