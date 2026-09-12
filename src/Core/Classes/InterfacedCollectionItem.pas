unit InterfacedCollectionItem;

// A TCollectionItem with interface support whose reference counts go to the
// owner of its collection, as in TInterfacedPersistent: an interface reference
// to an item keeps the owner alive, and without a counted owner the item is
// not reference counted at all.

interface

uses
  Classes;

type
  TInterfacedCollectionItem = class(TCollectionItem, IInterface)
  private
    FOwnerIntf: Pointer; // IInterface held uncounted, or the item would pin a refcounted owner in a cycle
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
var
  lvOwner: TPersistent;
  lvEntry: PInterfaceEntry;
begin
  FOwnerIntf := nil;
  if Collection = nil then
    Exit;
  lvOwner := Collection.Owner;
  if lvOwner = nil then
    Exit;
  // through the interface table, not GetInterface, whose AddRef and Release pair would free an owner nobody holds yet
  lvEntry := lvOwner.GetInterfaceEntry(IInterface);
  if (lvEntry <> nil) and (lvEntry^.IOffset <> 0) then
    FOwnerIntf := Pointer(PAnsiChar(lvOwner) + lvEntry^.IOffset);
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
  if FOwnerIntf <> nil then
    Result := IInterface(FOwnerIntf)._AddRef
  else
    Result := -1;
end;

function TInterfacedCollectionItem._Release: Integer;
begin
  if FOwnerIntf <> nil then
    Result := IInterface(FOwnerIntf)._Release
  else
    Result := -1;
end;

end.
