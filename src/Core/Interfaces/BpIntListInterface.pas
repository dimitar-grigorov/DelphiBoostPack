unit BpIntListInterface;

interface

type
  IBpIntList = interface
    function Get(Index: Integer): Integer;
    procedure Put(Index: Integer; const Item: Integer);
    function GetCount: Integer;
    function Add(const Item: Integer): Integer;
    procedure Delete(Index: Integer);
    procedure Clear;
    function IndexOf(const Item: Integer): Integer;
    procedure Insert(Index: Integer; const Item: Integer);
    property Items[Index: Integer]: Integer read Get write Put; default;
    property Count: Integer read GetCount;
  end;


implementation

end.
