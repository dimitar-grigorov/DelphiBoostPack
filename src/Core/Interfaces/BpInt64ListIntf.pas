unit BpInt64ListIntf;

// Interface for TbpInt64List (BpInt64List.pas).

interface

type
  IBpInt64List = interface
    ['{710B301E-4E1B-4F54-959A-22D65BCEE4BC}']
    function GetItem(aIndex: Integer): Int64;
    procedure SetItem(aIndex: Integer; const aValue: Int64);
    function GetDelimitedText: string;
    procedure SetDelimitedText(const aValue: string);
    function GetDelimiter: Char;
    procedure SetDelimiter(const aValue: Char);
    function GetCount: Integer;
    function GetCommaText: string;
    procedure SetCommaText(const aValue: string);
    procedure SetSorted(const aValue: Boolean);

    function Add(const aItem: Int64): Integer;
    procedure Delete(const aIndex: Integer);
    procedure Clear;
    function IndexOf(const aItem: Int64): Integer;
    procedure Insert(aIndex: Integer; const aItem: Int64);
    procedure Sort;
    property Items[aIndex: Integer]: Int64 read GetItem write SetItem; default;
    property CommaText: string read GetCommaText write SetCommaText;
    property Count: Integer read GetCount;
    property Delimiter: Char read GetDelimiter write SetDelimiter;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
  end;

implementation

end.
