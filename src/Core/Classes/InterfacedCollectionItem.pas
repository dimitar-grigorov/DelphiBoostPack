unit InterfacedCollectionItemUnit;

interface

uses
  Classes;

type
  TInterfacedCollectionItem = class(TCollectionItem, IInterface)
  private
    FOwnerInterface: IInterface;
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    procedure SetOwnerInterface;
  public
    procedure AfterConstruction; override;
  end;

implementation

procedure TInterfacedCollectionItem.AfterConstruction;
begin
  inherited;
  SetOwnerInterface;
end;

procedure TInterfacedCollectionItem.SetOwnerInterface;
begin
  if Assigned(Collection) and (Collection.Owner <> nil) then
    Collection.Owner.GetInterface(IInterface, FOwnerInterface);
end;

function TInterfacedCollectionItem.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TInterfacedCollectionItem._AddRef: Integer;
begin
  if Assigned(FOwnerInterface) then
    Result := FOwnerInterface._AddRef
  else
    Result := -1;
end;

function TInterfacedCollectionItem._Release: Integer;
begin
  if Assigned(FOwnerInterface) then
    Result := FOwnerInterface._Release
  else
    Result := -1;
end;

end.

