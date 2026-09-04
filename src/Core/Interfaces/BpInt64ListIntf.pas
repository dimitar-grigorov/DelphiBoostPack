unit BpInt64ListIntf;

// Interface for TbpInt64List (BpInt64List.pas).

interface

uses
  Classes;

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
    function GetSorted: Boolean;

    function Add(const aItem: Int64): Integer;
    procedure Delete(const aIndex: Integer);
    procedure Clear;
    function IndexOf(const aItem: Int64): Integer;
    function BinarySearch(const aItem: Int64; out aFoundIndex: Integer): Boolean;
    procedure Insert(aIndex: Integer; const aItem: Int64);
    procedure Exchange(aIndex1, aIndex2: Integer);
    procedure Sort;
    procedure LoadFromFile(const aFileName: string);
    procedure LoadFromStream(aStream: TStream);
    procedure SaveToFile(const aFileName: string);
    procedure SaveToStream(aStream: TStream);
    property Items[aIndex: Integer]: Int64 read GetItem write SetItem; default;
    property CommaText: string read GetCommaText write SetCommaText;
    property Count: Integer read GetCount;
    property Delimiter: Char read GetDelimiter write SetDelimiter;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
    property Sorted: Boolean read GetSorted write SetSorted;
  end;

implementation

end.
