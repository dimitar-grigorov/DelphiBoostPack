unit BpIntListIntf;

// Interface for TbpIntList (BpIntList.pas).

interface

uses
  Classes;

type
  IBpIntList = interface
    function GetItem(aIndex: Integer): Integer;
    procedure SetItem(aIndex: Integer; const aValue: Integer);
    function GetDelimitedText: string;
    procedure SetDelimitedText(const aValue: string);
    function GetDelimiter: Char;
    procedure SetDelimiter(const aValue: Char);
    function GetCount: Integer;
    function GetCommaText: string;
    procedure SetCommaText(const aValue: string);
    procedure SetSorted(const aValue: Boolean);
    function GetSorted: Boolean;

    function Add(const aItem: Integer): Integer;
    procedure Delete(const aIndex: Integer);
    procedure Clear;
    function IndexOf(const aItem: Integer): Integer;
    function BinarySearch(const aItem: Integer; out aFoundIndex: Integer): Boolean;
    procedure Insert(aIndex: Integer; const aItem: Integer);
    procedure Exchange(aIndex1, aIndex2: Integer);
    procedure Sort;
    procedure LoadFromFile(const aFileName: string);
    procedure LoadFromStream(aStream: TStream);
    procedure SaveToFile(const aFileName: string);
    procedure SaveToStream(aStream: TStream);
    property Items[aIndex: Integer]: Integer read GetItem write SetItem; default;
    property CommaText: string read GetCommaText write SetCommaText;
    property Count: Integer read GetCount;
    property Delimiter: Char read GetDelimiter write SetDelimiter;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
    property Sorted: Boolean read GetSorted write SetSorted;
  end;

implementation

end.
