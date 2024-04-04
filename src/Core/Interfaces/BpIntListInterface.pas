unit BpIntListInterface;

interface

type
  IBpIntList = interface
    function GetItem(Index: Integer): Integer;
    procedure SetItem(Index: Integer; const Value: Integer);
    
    function GetCount: Integer;
    function Add(const Item: Integer): Integer;
    procedure Delete(const Index: Integer);
    procedure Clear;
    function IndexOf(const Item: Integer): Integer;
    procedure Insert(Index: Integer; const Item: Integer);
    property Items[Index: Integer]: Integer read GetItem write SetItem; default;
    property Count: Integer read GetCount;
  end;


implementation

end.
