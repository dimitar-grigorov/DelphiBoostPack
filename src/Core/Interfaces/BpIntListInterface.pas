unit BpIntListInterface;

interface

type
  IBpIntList = interface
    function GetItem(Index: Integer): Integer;
    procedure SetItem(Index: Integer; const Value: Integer);
    function GetDelimitedText: string;
    procedure SetDelimitedText(const Value: string);
    function GetDelimiter: Char;
    procedure SetDelimiter(const Value: Char);
    function GetCount: Integer;
    function GetCommaText: string;
    procedure SetCommaText(const Value: string);
    procedure SetSorted(const Value: Boolean);
    
    function Add(const Item: Integer): Integer;
    procedure Delete(const Index: Integer);
    procedure Clear;
    function IndexOf(const Item: Integer): Integer;
    procedure Insert(Index: Integer; const Item: Integer);
    procedure Sort;
    property Items[Index: Integer]: Integer read GetItem write SetItem; default;
    property CommaText: string read GetCommaText write SetCommaText;
    property Count: Integer read GetCount;
    property Delimiter: Char read GetDelimiter write SetDelimiter;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
    //property Sorted: Boolean read FSorted write SetSorted;
  end;

implementation

end.
