unit BpDictionary;

interface

uses
  Windows, Classes;

type

//------------------------------------------------------------------------------

  {$ifdef CPU64} // Delphi XE2 seems stable about those types (not Delphi 2009)
  PtrInt = NativeInt;
  PtrUInt = NativeUInt;
  {$else}
  /// a CPU-dependent signed integer type cast of a pointer / register
  // - used for 64-bit compatibility, native under Free Pascal Compiler
  PtrInt = integer;
  /// a CPU-dependent unsigned integer type cast of a pointer / register
  // - used for 64-bit compatibility, native under Free Pascal Compiler
  PtrUInt = cardinal;
  {$endif}
  /// a CPU-dependent unsigned integer type cast of a pointer of pointer
  // - used for 64-bit compatibility, native under Free Pascal Compiler
  PPtrUInt = ^PtrUInt;
  /// a CPU-dependent signed integer type cast of a pointer of pointer
  // - used for 64-bit compatibility, native under Free Pascal Compiler
  PPtrInt = ^PtrInt;

  /// unsigned Int64 doesn't exist under older Delphi, but is defined in FPC
  // - and UInt64 is buggy as hell under Delphi 2007 when inlining functions:
  // older compilers will fallback to signed Int64 values
  // - anyway, consider using SortDynArrayQWord() to compare QWord values
  // in a safe and efficient way, under a CPUX86
  // - you may use UInt64 explicitly in your computation (like in SynEcc.pas),
  // if you are sure that Delphi 6-2007 compiler handles your code as expected,
  // but mORMot code will expect to use QWord for its internal process
  // (e.g. ORM/SOA serialization)
  {$ifdef UNICODE}
  QWord = UInt64;
  {$else}
  QWord = {$ifndef DELPHI5OROLDER}type{$endif} Int64;
  {$endif}
  /// points to an unsigned Int64
  PQWord = ^QWord;

//------------------------------------------------------------------------------

  /// RawUTF8 is an UTF-8 String stored in an AnsiString
  // - use this type instead of System.UTF8String, which behavior changed
  // between Delphi 2009 compiler and previous versions: our implementation
  // is consistent and compatible with all versions of Delphi compiler
  // - mimic Delphi 2009 UTF8String, without the charset conversion overhead
  // - all conversion to/from AnsiString or RawUnicode must be explicit
  {$ifdef HASCODEPAGE}
  RawUTF8 = type AnsiString(CP_UTF8); // Codepage for an UTF8 string
  {$else}
  RawUTF8 = type AnsiString;
  {$endif}

  /// WinAnsiString is a WinAnsi-encoded AnsiString (code page 1252)
  // - use this type instead of System.String, which behavior changed
  // between Delphi 2009 compiler and previous versions: our implementation
  // is consistent and compatible with all versions of Delphi compiler
  // - all conversion to/from RawUTF8 or RawUnicode must be explicit
  {$ifdef HASCODEPAGE}
  WinAnsiString = type AnsiString(CODEPAGE_US); // WinAnsi Codepage
  {$else}
  WinAnsiString = type AnsiString;
  {$endif}

  {$ifdef HASCODEPAGE}
  {$ifdef FPC}
  // missing declaration
  PRawByteString = ^RawByteString;
  {$endif}
  {$else}
  /// define RawByteString, as it does exist in Delphi 2009+
  // - to be used for byte storage into an AnsiString
  // - use this type if you don't want the Delphi compiler not to do any
  // code page conversions when you assign a typed AnsiString to a RawByteString,
  // i.e. a RawUTF8 or a WinAnsiString
  RawByteString = type AnsiString;
  /// pointer to a RawByteString
  PRawByteString = ^RawByteString;
  {$endif}

//------------------------------------------------------------------------------

  /// a simple wrapper to UTF-8 encoded zero-terminated PAnsiChar
  // - PAnsiChar is used only for Win-Ansi encoded text
  // - the Synopse mORMot framework uses mostly this PUTF8Char type,
  // because all data is internaly stored and expected to be UTF-8 encoded
  PUTF8Char = type PAnsiChar;
  PPUTF8Char = ^PUTF8Char;

//------------------------------------------------------------------------------

  PIntegerDynArray = ^TIntegerDynArray;
  TIntegerDynArray = array of integer;
  TIntegerDynArrayDynArray = array of TIntegerDynArray;
  PCardinalDynArray = ^TCardinalDynArray;
  TCardinalDynArray = array of cardinal;
  PSingleDynArray = ^TSingleDynArray;
  TSingleDynArray = array of Single;
  PInt64DynArray = ^TInt64DynArray;
  TInt64DynArray = array of Int64;
  PQwordDynArray = ^TQwordDynArray;
  TQwordDynArray = array of Qword;
  TPtrUIntDynArray = array of PtrUInt;
  PDoubleDynArray = ^TDoubleDynArray;
  TDoubleDynArray = array of double;
  PCurrencyDynArray = ^TCurrencyDynArray;
  TCurrencyDynArray = array of Currency;
  TWordDynArray = array of word;
  PWordDynArray = ^TWordDynArray;
  TByteDynArray = array of byte;
  PByteDynArray = ^TByteDynArray;

// -----------------------------------------------------------------------------  

  TCardinalArray = array[0..MaxInt div SizeOf(cardinal)-1] of cardinal;
  PCardinalArray = ^TCardinalArray;

// 815 -------------------------------------------------------------------------

  /// implements a stack-based storage of some (UTF-8 or binary) text
  // - avoid temporary memory allocation via the heap for up to 4KB of data
  // - could be used e.g. to make a temporary copy when JSON is parsed in-place
  // - call one of the Init() overloaded methods, then Done to release its memory
  // - all Init() methods will allocate 16 more bytes, for a trailing #0 and
  // to ensure our fast JSON parsing won't trigger any GPF (since it may read
  // up to 4 bytes ahead via its PInteger() trick) or any SSE4.2 function
  {$ifdef USERECORDWITHMETHODS}TSynTempBuffer = record
    {$else}TSynTempBuffer = object{$endif}
  public
    /// the text/binary length, in bytes, excluding the trailing #0
    len: PtrInt;
    /// where the text/binary is available (and any Source has been copied)
    // - equals nil if len=0
    buf: pointer;
    /// initialize a temporary copy of the content supplied as RawByteString
    // - will also allocate and copy the ending #0 (even for binary)
    procedure Init(const Source: RawByteString); overload;
    /// initialize a temporary copy of the supplied text buffer, ending with #0
    function Init(Source: PUTF8Char): PUTF8Char; overload;
    /// initialize a temporary copy of the supplied text buffer
    procedure Init(Source: pointer; SourceLen: PtrInt); overload;
    /// initialize a new temporary buffer of a given number of bytes
    function Init(SourceLen: PtrInt): pointer; overload;
    /// initialize a temporary buffer with the length of the internal stack
    function InitOnStack: pointer;
    /// initialize the buffer returning the internal buffer size (4095 bytes)
    // - could be used e.g. for an API call, first trying with plain temp.Init
    // and using temp.buf and temp.len safely in the call, only calling
    // temp.Init(expectedsize) if the API returned an error about an insufficient
    // buffer space
    function Init: integer; overload; {$ifdef HASINLINE}inline;{$endif}
    /// initialize a new temporary buffer of a given number of random bytes
    // - will fill the buffer via FillRandom() calls
    // - forcegsl is true by default, since Lecuyer's generator has no HW bug
    function InitRandom(RandomLen: integer; forcegsl: boolean=true): pointer;
    /// initialize a new temporary buffer filled with 32-bit integer increasing values
    function InitIncreasing(Count: PtrInt; Start: PtrInt=0): PIntegerArray;
    /// initialize a new temporary buffer of a given number of zero bytes
    function InitZero(ZeroLen: PtrInt): pointer;
    /// finalize the temporary storage
    procedure Done; overload; {$ifdef HASINLINE}inline;{$endif}
    /// finalize the temporary storage, and create a RawUTF8 string from it
    procedure Done(EndBuf: pointer; var Dest: RawUTF8); overload;
  private
    // default 4KB buffer allocated on stack - after the len/buf main fields
    tmp: array[0..4095] of AnsiChar;
  end;

  /// function prototype to be used for hashing of an element
  // - it must return a cardinal hash, with as less collision as possible
  // - TDynArrayHashed.Init will use crc32c() if no custom function is supplied,
  // which will run either as software or SSE4.2 hardware, with good colision
  // for most used kind of data
  THasher = function(crc: cardinal; buf: PAnsiChar; len: cardinal): cardinal;

// 970 -------------------------------------------------------------------------

/// equivalence to SetString(s,nil,len) function
// - faster especially under FPC
procedure FastSetString(var s: RawUTF8; p: pointer; len: PtrInt);
  {$ifndef HASCODEPAGE}{$ifdef HASINLINE}inline;{$endif}{$endif}

/// equivalence to SetString(s,nil,len) function with a specific code page
// - faster especially under FPC
procedure FastSetStringCP(var s; p: pointer; len, codepage: PtrInt);
  {$ifndef HASCODEPAGE}{$ifdef HASINLINE}inline;{$endif}{$endif}  

// 1683 ------------------------------------------------------------------------

type
  /// used e.g. by PointerToHexShort/CardinalToHexShort/Int64ToHexShort/FormatShort16
  // - such result type would avoid a string allocation on heap, so are highly
  // recommended e.g. when logging small pieces of information
  TShort16 = string[16];
  PShort16 = ^TShort16;

// 2360 ------------------------------------------------------------------------

/// slower version of StrLen(), but which will never read beyond the string
// - this version won't access the memory beyond the string, so may be
// preferred to StrLen(), when using e.g. memory mapped files or any memory
// protected buffer
function StrLenPas(S: pointer): PtrInt;

/// our fast version of StrLen(), to be used with PUTF8Char/PAnsiChar
// - if available, a fast SSE2 asm will be used on Intel/AMD CPUs
// - won't use SSE4.2 instructions on supported CPUs by default, which may read
// some bytes beyond the string, so should be avoided e.g. over memory mapped
// files - call explicitely StrLenSSE42() if you are confident on your input
var StrLen: function(S: pointer): PtrInt = StrLenPas;

{$ifdef ABSOLUTEPASCAL}
var FillcharFast: procedure(var Dest; count: PtrInt; Value: byte) = system.FillChar;
var MoveFast: procedure(const Source; var Dest; Count: PtrInt) = system.Move;
{$else}
{$ifdef CPUX64} // will define its own self-dispatched SSE2/AVX functions
type
  /// cpuERMS is slightly slower than cpuAVX so is not available by default
  TX64CpuFeatures = set of(cpuAVX, cpuAVX2 {$ifdef WITH_ERMS}, cpuERMS{$endif});
var
  /// internal flags used by FillCharFast - easier from asm that CpuFeatures
  CPUIDX64: TX64CpuFeatures;
procedure FillcharFast(var dst; cnt: PtrInt; value: byte);
procedure MoveFast(const src; var dst; cnt: PtrInt);
{$else}

/// our fast version of FillChar()
// - on Intel i386/x86_64, will use fast SSE2/ERMS instructions (if available),
// or optimized X87 assembly implementation for older CPUs
// - on non-Intel CPUs, it will fallback to the default RTL FillChar()
// - note: Delphi x86_64 is far from efficient: even ERMS was wrongly
// introduced in latest updates
var FillcharFast: procedure(var Dest; count: PtrInt; Value: byte);

/// our fast version of move()
// - on Delphi Intel i386/x86_64, will use fast SSE2 instructions (if available),
// or optimized X87 assembly implementation for older CPUs
// - on non-Intel CPUs, it will fallback to the default RTL Move()
var MoveFast: procedure(const Source; var Dest; Count: PtrInt);

{$endif CPUX64}
{$endif ABSOLUTEPASCAL}

// 4641 ------------------------------------------------------------------------

/// fill some values with i,i+1,i+2...i+Count-1
procedure FillIncreasing(Values: PIntegerArray; StartValue: integer; Count: PtrUInt);


type
// 5038 -----------------------------------------------------------------------

  /// function prototype to be used for TDynArray Sort and Find method
  // - common functions exist for base types: see e.g. SortDynArrayBoolean,
  // SortDynArrayByte, SortDynArrayWord, SortDynArrayInteger, SortDynArrayCardinal,
  // SortDynArrayInt64, SortDynArrayQWord, SordDynArraySingle, SortDynArrayDouble,
  // SortDynArrayAnsiString, SortDynArrayAnsiStringI, SortDynArrayUnicodeString,
  // SortDynArrayUnicodeStringI, SortDynArrayString, SortDynArrayStringI
  // - any custom type (even records) can be compared then sort by defining
  // such a custom function
  // - must return 0 if A=B, -1 if A<B, 1 if A>B
  TDynArraySortCompare = function(const A,B): integer;

  /// event oriented version of TDynArraySortCompare
  TEventDynArraySortCompare = function(const A,B): integer of object;

  /// optional event called by TDynArray.LoadFrom method after each item load
  // - could be used e.g. for string interning or some custom initialization process
  // - won't be called if the dynamic array has ElemType=nil
  TDynArrayAfterLoadFrom = procedure(var A) of object;

  /// internal enumeration used to specify some standard Delphi arrays
  // - will be used e.g. to match JSON serialization or TDynArray search
  // (see TDynArray and TDynArrayHash InitSpecific method)
  // - djBoolean would generate an array of JSON boolean values
  // - djByte .. djTimeLog match numerical JSON values
  // - djDateTime .. djHash512 match textual JSON values
  // - djVariant will match standard variant JSON serialization (including
  // TDocVariant or other custom types, if any)
  // - djCustom will be used for registered JSON serializer (invalid for
  // InitSpecific methods call)
  // - see also djPointer and djObject constant aliases for a pointer or
  // TObject field hashing / comparison
  // - is used also by TDynArray.InitSpecific() to define the main field type
  TDynArrayKind = (
    djNone,
    djBoolean, djByte, djWord, djInteger, djCardinal, djSingle,
    djInt64, djQWord, djDouble, djCurrency,  djTimeLog,
    djDateTime, djDateTimeMS, djRawUTF8, djWinAnsi, djString,
    djRawByteString, djWideString, djSynUnicode,
    djHash128, djHash256, djHash512,
    djInterface, {$ifndef NOVARIANTS}djVariant,{$endif}
    djCustom);

// 5299 ------------------------------------------------------------------------

  TDynArrayObjArray = (oaUnknown, oaFalse, oaTrue);
 
  /// a wrapper around a dynamic array with one dimension
  // - provide TList-like methods using fast RTTI information
  // - can be used to fast save/retrieve all memory content to a TStream
  // - note that the "const Elem" is not checked at compile time nor runtime:
  // you must ensure that Elem matchs the element type of the dynamic array
  // - can use external Count storage to make Add() and Delete() much faster
  // (avoid most reallocation of the memory buffer)
  // - Note that TDynArray is just a wrapper around an existing dynamic array:
  // methods can modify the content of the associated variable but the TDynArray
  // doesn't contain any data by itself. It is therefore aimed to initialize
  // a TDynArray wrapper on need, to access any existing dynamic array.
  // - is defined as an object or as a record, due to a bug
  // in Delphi 2009/2010 compiler (at least): this structure is not initialized
  // if defined as an object on the stack, but will be as a record :(
  {$ifdef UNDIRECTDYNARRAY}TDynArray = record
  {$else}TDynArray = object {$endif}
  private
    fValue: PPointer;
    fTypeInfo: pointer;
    fElemType{$ifdef DYNARRAYELEMTYPE2}, fElemType2{$endif}: pointer;
    fCountP: PInteger;
    fCompare: TDynArraySortCompare;
    fElemSize: cardinal;
    fKnownSize: integer;
    fParser: integer; // index to GlobalJSONCustomParsers.fParsers[]
    fSorted: boolean;
    fKnownType: TDynArrayKind;
    fIsObjArray: TDynArrayObjArray;
    function GetCount: PtrInt; {$ifdef HASINLINE}inline;{$endif}
    procedure SetCount(aCount: PtrInt);
    function GetCapacity: PtrInt; {$ifdef HASINLINE}inline;{$endif}
    procedure SetCapacity(aCapacity: PtrInt);
    procedure SetCompare(const aCompare: TDynArraySortCompare); {$ifdef HASINLINE}inline;{$endif}
    function FindIndex(const Elem; aIndex: PIntegerDynArray;
      aCompare: TDynArraySortCompare): PtrInt;
    function GetArrayTypeName: RawUTF8;
    function GetArrayTypeShort: PShortString;
    function GetIsObjArray: boolean; {$ifdef HASINLINE}inline;{$endif}
    function ComputeIsObjArray: boolean;
    procedure SetIsObjArray(aValue: boolean); {$ifdef HASINLINE}inline;{$endif}
    function LoadFromHeader(var Source: PByte; SourceMax: PByte): integer;
    function LoadKnownType(Data,Source,SourceMax: PAnsiChar): boolean;
    /// faster than RTL + handle T*ObjArray + ensure unique
    procedure InternalSetLength(OldLength,NewLength: PtrUInt);
  public
    /// initialize the wrapper with a one-dimension dynamic array
    // - the dynamic array must have been defined with its own type
    // (e.g. TIntegerDynArray = array of Integer)
    // - if aCountPointer is set, it will be used instead of length() to store
    // the dynamic array items count - it will be much faster when adding
    // elements to the array, because the dynamic array won't need to be
    // resized each time - but in this case, you should use the Count property
    // instead of length(array) or high(array) when accessing the data: in fact
    // length(array) will store the memory size reserved, not the items count
    // - if aCountPointer is set, its content will be set to 0, whatever the
    // array length is, or the current aCountPointer^ value is
    // - a sample usage may be:
    // !var DA: TDynArray;
    // !    A: TIntegerDynArray;
    // !begin
    // !  DA.Init(TypeInfo(TIntegerDynArray),A);
    // ! (...)
    // - a sample usage may be (using a count variable):
    // !var DA: TDynArray;
    // !    A: TIntegerDynArray;
    // !    ACount: integer;
    // !    i: integer;
    // !begin
    // !  DA.Init(TypeInfo(TIntegerDynArray),A,@ACount);
    // !  for i := 1 to 100000 do
    // !    DA.Add(i); // MUCH faster using the ACount variable
    // ! (...)   // now you should use DA.Count or Count instead of length(A)
    procedure Init(aTypeInfo: pointer; var aValue; aCountPointer: PInteger=nil);
    /// initialize the wrapper with a one-dimension dynamic array
    // - this version accepts to specify how comparison should occur, using
    // TDynArrayKind  kind of first field
    // - djNone and djCustom are too vague, and will raise an exception
    // - no RTTI check is made over the corresponding array layout: you shall
    // ensure that the aKind parameter matches the dynamic array element definition
    // - aCaseInsensitive will be used for djRawUTF8..djHash512 text comparison
    procedure InitSpecific(aTypeInfo: pointer; var aValue; aKind: TDynArrayKind;
      aCountPointer: PInteger=nil; aCaseInsensitive: boolean=false);
    /// define the reference to an external count integer variable
    // - Init and InitSpecific methods will reset the aCountPointer to 0: you
    // can use this method to set the external count variable without overriding
    // the current value
    procedure UseExternalCount(var aCountPointer: Integer);
      {$ifdef HASINLINE}inline;{$endif}
    /// low-level computation of KnownType and KnownSize fields from RTTI
    // - do nothing if has already been set at initialization, or already computed
    function GuessKnownType(exactType: boolean=false): TDynArrayKind;
    /// check this dynamic array from the GlobalJSONCustomParsers list
    // - returns TRUE if this array has a custom JSON parser
    function HasCustomJSONParser: boolean;
    /// initialize the wrapper to point to no dynamic array
    procedure Void;
    /// check if the wrapper points to a dynamic array
    function IsVoid: boolean;
    /// add an element to the dynamic array
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write Add(i+10) e.g.)
    // - returns the index of the added element in the dynamic array
    // - note that because of dynamic array internal memory managment, adding
    // may reallocate the list every time a record is added, unless an external
    // count variable has been specified in Init(...,@Count) method
    function Add(const Elem): PtrInt;
    /// add an element to the dynamic array
    // - this version add a void element to the array, and returns its index
    // - note: if you use this method to add a new item with a reference to the
    // dynamic array, using a local variable is needed under FPC:
    // !    i := DynArray.New;
    // !    with Values[i] do begin // otherwise Values is nil -> GPF
    // !      Field1 := 1;
    // !      ...
    function New: integer;
    /// add an element to the dynamic array at the position specified by Index
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write Insert(10,i+10) e.g.)
    procedure Insert(Index: PtrInt; const Elem);
    /// get and remove the last element stored in the dynamic array
    // - Add + Pop/Peek will implement a LIFO (Last-In-First-Out) stack
    // - warning: Elem must be of the same exact type than the dynamic array
    // - returns true if the item was successfully copied and removed
    // - use Peek() if you don't want to remove the item
    function Pop(var Dest): boolean;
    /// get the last element stored in the dynamic array
    // - Add + Pop/Peek will implement a LIFO (Last-In-First-Out) stack
    // - warning: Elem must be of the same exact type than the dynamic array
    // - returns true if the item was successfully copied into Dest
    // - use Pop() if you also want to remove the item
    function Peek(var Dest): boolean;
    /// delete the whole dynamic array content
    // - this method will recognize T*ObjArray types and free all instances
    procedure Clear; {$ifdef HASINLINE}inline;{$endif}
    /// delete the whole dynamic array content, ignoring exceptions
    // - returns true if no exception occured when calling Clear, false otherwise
    // - you should better not call this method, which will catch and ignore
    // all exceptions - but it may somewhat make sense in a destructor
    // - this method will recognize T*ObjArray types and free all instances
    function ClearSafe: boolean;
    /// delete one item inside the dynamic array
    // - the deleted element is finalized if necessary
    // - this method will recognize T*ObjArray types and free all instances
    function Delete(aIndex: PtrInt): boolean;
    /// search for an element value inside the dynamic array
    // - return the index found (0..Count-1), or -1 if Elem was not found
    // - will search for all properties content of the eLement: TList.IndexOf()
    // searches by address, this method searches by content using the RTTI
    // element description (and not the Compare property function)
    // - use the Find() method if you want the search via the Compare property
    // function, or e.g. to search only with some part of the element content
    // - will work with simple types: binaries (byte, word, integer, Int64,
    // Currency, array[0..255] of byte, packed records with no reference-counted
    // type within...), string types (e.g. array of string), and packed records
    // with binary and string types within (like TFileVersion)
    // - won't work with not packed types (like a shorstring, or a record
    // with byte or word fields with {$A+}): in this case, the padding data
    // (i.e. the bytes between the aligned feeds can be filled as random, and
    // there is no way with standard RTTI do know which they are)
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write IndexOf(i+10) e.g.)
    function IndexOf(const Elem): PtrInt;
    /// search for an element value inside the dynamic array
    // - this method will use the Compare property function for the search
    // - return the index found (0..Count-1), or -1 if Elem was not found
    // - if the array is sorted, it will use fast O(log(n)) binary search
    // - if the array is not sorted, it will use slower O(n) iterating search
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write Find(i+10) e.g.)
    function Find(const Elem): PtrInt; overload;
    /// search for an element value inside the dynamic array, from an external
    // indexed lookup table
    // - return the index found (0..Count-1), or -1 if Elem was not found
    // - this method will use a custom comparison function, with an external
    // integer table, as created by the CreateOrderedIndex() method: it allows
    // multiple search orders in the same dynamic array content
    // - if an indexed lookup is supplied, it must already be sorted:
    // this function will then use fast O(log(n)) binary search
    // - if an indexed lookup is not supplied (i.e aIndex=nil),
    // this function will use slower but accurate O(n) iterating search
    // - warning; the lookup index should be synchronized if array content
    // is modified (in case of adding or deletion)
    function Find(const Elem; const aIndex: TIntegerDynArray;
      aCompare: TDynArraySortCompare): PtrInt; overload;
    /// search for an element value, then fill all properties if match
    // - this method will use the Compare property function for the search,
    // or the supplied indexed lookup table and its associated compare function
    // - if Elem content matches, all Elem fields will be filled with the record
    // - can be used e.g. as a simple dictionary: if Compare will match e.g. the
    // first string field (i.e. set to SortDynArrayString), you can fill the
    // first string field with the searched value (if returned index is >= 0)
    // - return the index found (0..Count-1), or -1 if Elem was not found
    // - if the array is sorted, it will use fast O(log(n)) binary search
    // - if the array is not sorted, it will use slower O(n) iterating search
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write Find(i+10) e.g.)
    function FindAndFill(var Elem; aIndex: PIntegerDynArray=nil;
      aCompare: TDynArraySortCompare=nil): integer;
    /// search for an element value, then delete it if match
    // - this method will use the Compare property function for the search,
    // or the supplied indexed lookup table and its associated compare function
    // - if Elem content matches, this item will be deleted from the array
    // - can be used e.g. as a simple dictionary: if Compare will match e.g. the
    // first string field (i.e. set to SortDynArrayString), you can fill the
    // first string field with the searched value (if returned index is >= 0)
    // - return the index deleted (0..Count-1), or -1 if Elem was not found
    // - if the array is sorted, it will use fast O(log(n)) binary search
    // - if the array is not sorted, it will use slower O(n) iterating search
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write Find(i+10) e.g.)
    function FindAndDelete(const Elem; aIndex: PIntegerDynArray=nil;
      aCompare: TDynArraySortCompare=nil): integer;
    /// search for an element value, then update the item if match
    // - this method will use the Compare property function for the search,
    // or the supplied indexed lookup table and its associated compare function
    // - if Elem content matches, this item will be updated with the supplied value
    // - can be used e.g. as a simple dictionary: if Compare will match e.g. the
    // first string field (i.e. set to SortDynArrayString), you can fill the
    // first string field with the searched value (if returned index is >= 0)
    // - return the index found (0..Count-1), or -1 if Elem was not found
    // - if the array is sorted, it will use fast O(log(n)) binary search
    // - if the array is not sorted, it will use slower O(n) iterating search
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write Find(i+10) e.g.)
    function FindAndUpdate(const Elem; aIndex: PIntegerDynArray=nil;
      aCompare: TDynArraySortCompare=nil): integer;
    /// search for an element value, then add it if none matched
    // - this method will use the Compare property function for the search,
    // or the supplied indexed lookup table and its associated compare function
    // - if no Elem content matches, the item will added to the array
    // - can be used e.g. as a simple dictionary: if Compare will match e.g. the
    // first string field (i.e. set to SortDynArrayString), you can fill the
    // first string field with the searched value (if returned index is >= 0)
    // - return the index found (0..Count-1), or -1 if Elem was not found and
    // the supplied element has been succesfully added
    // - if the array is sorted, it will use fast O(log(n)) binary search
    // - if the array is not sorted, it will use slower O(n) iterating search
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write Find(i+10) e.g.)
    function FindAndAddIfNotExisting(const Elem; aIndex: PIntegerDynArray=nil;
      aCompare: TDynArraySortCompare=nil): integer;
    /// sort the dynamic array elements, using the Compare property function
    // - it will change the dynamic array content, and exchange all elements
    // in order to be sorted in increasing order according to Compare function
    procedure Sort(aCompare: TDynArraySortCompare=nil); overload;
    /// sort some dynamic array elements, using the Compare property function
    // - this method allows to sort only some part of the items
    // - it will change the dynamic array content, and exchange all elements
    // in order to be sorted in increasing order according to Compare function
    procedure SortRange(aStart, aStop: integer; aCompare: TDynArraySortCompare=nil);
    /// sort the dynamic array elements, using a Compare method (not function)
    // - it will change the dynamic array content, and exchange all elements
    // in order to be sorted in increasing order according to Compare function,
    // unless aReverse is true
    // - it won't mark the array as Sorted, since the comparer is local
    procedure Sort(const aCompare: TEventDynArraySortCompare; aReverse: boolean=false); overload;
    /// search the elements range which match a given value in a sorted dynamic array
    // - this method will use the Compare property function for the search
    // - returns TRUE and the matching indexes, or FALSE if none found
    // - if the array is not sorted, returns FALSE
    function FindAllSorted(const Elem; out FirstIndex,LastIndex: Integer): boolean;
    /// search for an element value inside a sorted dynamic array
    // - this method will use the Compare property function for the search
    // - will be faster than a manual FindAndAddIfNotExisting+Sort process
    // - returns TRUE and the index of existing Elem, or FALSE and the index
    // where the Elem is to be inserted so that the array remains sorted
    // - you should then call FastAddSorted() later with the returned Index
    // - if the array is not sorted, returns FALSE and Index=-1
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (no FastLocateSorted(i+10) e.g.)
    function FastLocateSorted(const Elem; out Index: Integer): boolean;
    /// insert a sorted element value at the proper place
    // - the index should have been computed by FastLocateSorted(): false
    // - you may consider using FastLocateOrAddSorted() instead
    procedure FastAddSorted(Index: Integer; const Elem);
    /// search and add an element value inside a sorted dynamic array
    // - this method will use the Compare property function for the search
    // - will be faster than a manual FindAndAddIfNotExisting+Sort process
    // - returns the index of the existing Elem and wasAdded^=false
    // - returns the sorted index of the inserted Elem and wasAdded^=true
    // - if the array is not sorted, returns -1 and wasAdded^=false
    // - is just a wrapper around FastLocateSorted+FastAddSorted
    function FastLocateOrAddSorted(const Elem; wasAdded: PBoolean=nil): integer;
    /// delete a sorted element value at the proper place
    // - plain Delete(Index) would reset the fSorted flag to FALSE, so use
    // this method with a FastLocateSorted/FastAddSorted array
    procedure FastDeleteSorted(Index: Integer);
    /// will reverse all array elements, in place
    procedure Reverse;
    /// sort the dynamic array elements using a lookup array of indexes
    // - in comparison to the Sort method, this CreateOrderedIndex won't change
    // the dynamic array content, but only create (or update) the supplied
    // integer lookup array, using the specified comparison function
    // - if aCompare is not supplied, the method will use fCompare (if defined)
    // - you should provide either a void either a valid lookup table, that is
    // a table with one to one lookup (e.g. created with FillIncreasing)
    // - if the lookup table has less elements than the main dynamic array,
    // its content will be recreated
    procedure CreateOrderedIndex(var aIndex: TIntegerDynArray;
      aCompare: TDynArraySortCompare); overload;
    /// sort the dynamic array elements using a lookup array of indexes
    // - this overloaded method will use the supplied TSynTempBuffer for
    // index storage, so use PIntegerArray(aIndex.buf) to access the values
    // - caller should always make aIndex.Done once done
    procedure CreateOrderedIndex(out aIndex: TSynTempBuffer;
      aCompare: TDynArraySortCompare); overload;
    /// sort using a lookup array of indexes, after a Add()
    // - will resize aIndex if necessary, and set aIndex[Count-1] := Count-1
    procedure CreateOrderedIndexAfterAdd(var aIndex: TIntegerDynArray;
      aCompare: TDynArraySortCompare);
    /// save the dynamic array content into a (memory) stream
    // - will handle array of binaries values (byte, word, integer...), array of
    // strings or array of packed records, with binaries and string properties
    // - will use a proprietary binary format, with some variable-length encoding
    // of the string length - note that if you change the type definition, any
    // previously-serialized content will fail, maybe triggering unexpected GPF:
    // use SaveToTypeInfoHash if you share this binary data accross executables
    // - Stream position will be set just after the added data
    // - is optimized for memory streams, but will work with any kind of TStream
    procedure SaveToStream(Stream: TStream);
    /// load the dynamic array content from a (memory) stream
    // - stream content must have been created using SaveToStream method
    // - will handle array of binaries values (byte, word, integer...), array of
    // strings or array of packed records, with binaries and string properties
    // - will use a proprietary binary format, with some variable-length encoding
    // of the string length - note that if you change the type definition, any
    // previously-serialized content will fail, maybe triggering unexpected GPF:
    // use SaveToTypeInfoHash if you share this binary data accross executables
    procedure LoadFromStream(Stream: TCustomMemoryStream);
    /// save the dynamic array content into an allocated memory buffer
    // - Dest buffer must have been allocated to contain at least the number
    // of bytes returned by the SaveToLength method
    // - return a pointer at the end of the data written in Dest, nil in case
    // of an invalid input buffer
    // - will use a proprietary binary format, with some variable-length encoding
    // of the string length - note that if you change the type definition, any
    // previously-serialized content will fail, maybe triggering unexpected GPF:
    // use SaveToTypeInfoHash if you share this binary data accross executables
    // - this method will raise an ESynException for T*ObjArray types
    // - use TDynArray.LoadFrom or TDynArrayLoadFrom to decode the saved buffer
    function SaveTo(Dest: PAnsiChar): PAnsiChar; overload;
    /// compute the number of bytes needed by SaveTo() to persist a dynamic array
    // - will use a proprietary binary format, with some variable-length encoding
    // of the string length - note that if you change the type definition, any
    // previously-serialized content will fail, maybe triggering unexpected GPF:
    // use SaveToTypeInfoHash if you share this binary data accross executables
    // - this method will raise an ESynException for T*ObjArray types
    function SaveToLength: integer;
    /// save the dynamic array content into a RawByteString
    // - will use a proprietary binary format, with some variable-length encoding
    // of the string length - note that if you change the type definition, any
    // previously-serialized content will fail, maybe triggering unexpected GPF:
    // use SaveToTypeInfoHash if you share this binary data accross executables
    // - this method will raise an ESynException for T*ObjArray types
    // - use TDynArray.LoadFrom or TDynArrayLoadFrom to decode the saved buffer
    function SaveTo: RawByteString; overload;
    /// compute a crc32c-based hash of the RTTI for this dynamic array
    // - can be used to ensure that the TDynArray.SaveTo binary layout
    // is compatible accross executables
    // - won't include the RTTI type kind, as TypeInfoToHash(), but only
    // ElemSize or ElemType information, or any previously registered
    // TTextWriter.RegisterCustomJSONSerializerFromText definition
    function SaveToTypeInfoHash(crc: cardinal=0): cardinal;
    /// unserialize dynamic array content from binary written by TDynArray.SaveTo
    // - return nil if the Source buffer is incorrect: invalid type, wrong
    // checksum, or optional SourceMax overflow
    // - return a non nil pointer just after the Source content on success
    // - this method will raise an ESynException for T*ObjArray types
    // - you can optionally call AfterEach callback for each row loaded
    // - if you don't want to allocate all items on memory, but just want to
    // iterate over all items stored in a TDynArray.SaveTo memory buffer,
    // consider using TDynArrayLoadFrom object
    function LoadFrom(Source: PAnsiChar; AfterEach: TDynArrayAfterLoadFrom=nil;
      NoCheckHash: boolean=false; SourceMax: PAnsiChar=nil): PAnsiChar;
    /// unserialize the dynamic array content from a TDynArray.SaveTo binary string
    // - same as LoadFrom, and will check for any buffer overflow since we
    // know the actual end of input buffer
    function LoadFromBinary(const Buffer: RawByteString;
      NoCheckHash: boolean=false): boolean;

//------------------------------------------------------------------------------

    /// serialize the dynamic array content as JSON
    // - is just a wrapper around TTextWriter.AddDynArrayJSON()
    // - this method will therefore recognize T*ObjArray types
//    function SaveToJSON(EnumSetsAsText: boolean=false;
//      reformat: TTextWriterJSONFormat=jsonCompact): RawUTF8; overload;
//      {$ifdef HASINLINE}inline;{$endif}
    /// serialize the dynamic array content as JSON
    // - is just a wrapper around TTextWriter.AddDynArrayJSON()
    // - this method will therefore recognize T*ObjArray types
//    procedure SaveToJSON(out Result: RawUTF8; EnumSetsAsText: boolean=false;
//      reformat: TTextWriterJSONFormat=jsonCompact); overload;
    /// load the dynamic array content from an UTF-8 encoded JSON buffer
    // - expect the format as saved by TTextWriter.AddDynArrayJSON method, i.e.
    // handling TBooleanDynArray, TIntegerDynArray, TInt64DynArray, TCardinalDynArray,
    // TDoubleDynArray, TCurrencyDynArray, TWordDynArray, TByteDynArray,
    // TRawUTF8DynArray, TWinAnsiDynArray, TRawByteStringDynArray,
    // TStringDynArray, TWideStringDynArray, TSynUnicodeDynArray,
    // TTimeLogDynArray and TDateTimeDynArray as JSON array - or any customized
    // valid JSON serialization as set by TTextWriter.RegisterCustomJSONSerializer
    // - or any other kind of array as Base64 encoded binary stream precessed
    // via JSON_BASE64_MAGIC (UTF-8 encoded \uFFF0 special code)
    // - typical handled content could be
    // ! '[1,2,3,4]' or '["\uFFF0base64encodedbinary"]'
    // - return a pointer at the end of the data read from P, nil in case
    // of an invalid input buffer
    // - this method will recognize T*ObjArray types, and will first free
    // any existing instance before unserializing, to avoid memory leak
    // - warning: the content of P^ will be modified during parsing: please
    // make a local copy if it will be needed later (using e.g. TSynTempBufer)
//    function LoadFromJSON(P: PUTF8Char; aEndOfObject: PUTF8Char=nil{$ifndef NOVARIANTS};
//      CustomVariantOptions: PDocVariantOptions=nil{$endif}): PUTF8Char;

//------------------------------------------------------------------------------

    {$ifndef NOVARIANTS}
    /// load the dynamic array content from a TDocVariant instance
    // - will convert the TDocVariant into JSON, the call LoadFromJSON
    function LoadFromVariant(const DocVariant: variant): boolean;
    {$endif NOVARIANTS}
    ///  select a sub-section (slice) of a dynamic array content
    procedure Slice(var Dest; aCount: Cardinal; aFirstIndex: cardinal=0);
    /// add elements from a given dynamic array variable
    // - the supplied source DynArray MUST be of the same exact type as the
    // current used for this TDynArray - warning: pass here a reference to
    // a "array of ..." variable, not another TDynArray instance; if you
    // want to add another TDynArray, use AddDynArray() method
    // - you can specify the start index and the number of items to take from
    // the source dynamic array (leave as -1 to add till the end)
    // - returns the number of items added to the array
    function AddArray(const DynArrayVar; aStartIndex: integer=0; aCount: integer=-1): integer;
    {$ifndef DELPHI5OROLDER}
    /// fast initialize a wrapper for an existing dynamic array of the same type
    // - is slightly faster than
    // ! Init(aAnother.ArrayType,aValue,nil);
    procedure InitFrom(const aAnother: TDynArray; var aValue);
      {$ifdef HASINLINE}inline;{$endif}
    /// add elements from a given TDynArray
    // - the supplied source TDynArray MUST be of the same exact type as the
    // current used for this TDynArray, otherwise it won't do anything
    // - you can specify the start index and the number of items to take from
    // the source dynamic array (leave as -1 to add till the end)
    procedure AddDynArray(const aSource: TDynArray; aStartIndex: integer=0; aCount: integer=-1);
    /// compare the content of the two arrays, returning TRUE if both match
    // - this method compares using any supplied Compare property (unless
    // ignorecompare=true), or by content using the RTTI element description
    // of the whole array items
    // - will call SaveToJSON to compare T*ObjArray kind of arrays
    function Equals(const B: TDynArray; ignorecompare: boolean=false): boolean;
    /// set all content of one dynamic array to the current array
    // - both must be of the same exact type
    // - T*ObjArray will be reallocated and copied by content (using a temporary
    // JSON serialization), unless ObjArrayByRef is true and pointers are copied
    procedure Copy(const Source: TDynArray; ObjArrayByRef: boolean=false);
    /// set all content of one dynamic array to the current array
    // - both must be of the same exact type
    // - T*ObjArray will be reallocated and copied by content (using a temporary
    // JSON serialization), unless ObjArrayByRef is true and pointers are copied
    procedure CopyFrom(const Source; MaxElem: integer; ObjArrayByRef: boolean=false);
    /// set all content of the current dynamic array to another array variable
    // - both must be of the same exact type
    // - resulting length(Dest) will match the exact items count, even if an
    // external Count integer variable is used by this instance
    // - T*ObjArray will be reallocated and copied by content (using a temporary
    // JSON serialization), unless ObjArrayByRef is true and pointers are copied
    procedure CopyTo(out Dest; ObjArrayByRef: boolean=false);
    {$endif DELPHI5OROLDER}
    /// returns a pointer to an element of the array
    // - returns nil if aIndex is out of range
    // - since TDynArray is just a wrapper around an existing array, you should
    // better use direct access to its wrapped variable, and not using this
    // slower and more error prone method (such pointer access lacks of strong
    // typing abilities), which was designed for TDynArray internal use
    function ElemPtr(index: PtrInt): pointer; {$ifdef HASINLINE}inline;{$endif}
    /// will copy one element content from its index into another variable
    // - do nothing if index is out of range
    procedure ElemCopyAt(index: PtrInt; var Dest); {$ifdef FPC}inline;{$endif}
    /// will move one element content from its index into another variable
    // - will erase the internal item after copy
    // - do nothing if index is out of range
    procedure ElemMoveTo(index: PtrInt; var Dest);
    /// will copy one variable content into an indexed element
    // - do nothing if index is out of range
    // - ClearBeforeCopy will call ElemClear() before the copy, which may be safer
    // if the source item is a copy of Values[index] with some dynamic arrays
    procedure ElemCopyFrom(const Source; index: PtrInt;
      ClearBeforeCopy: boolean=false); {$ifdef FPC}inline;{$endif}
    /// compare the content of two elements, returning TRUE if both values equal
    // - this method compares first using any supplied Compare property,
    // then by content using the RTTI element description of the whole record
    function ElemEquals(const A,B): boolean;
    /// will reset the element content
    procedure ElemClear(var Elem);
    /// will copy one element content
    procedure ElemCopy(const A; var B); {$ifdef FPC}inline;{$endif}
    /// will copy the first field value of an array element
    // - will use the array KnownType to guess the copy routine to use
    // - returns false if the type information is not enough for a safe copy
    function ElemCopyFirstField(Source,Dest: Pointer): boolean;
    /// save an array element into a serialized binary content
    // - use the same layout as TDynArray.SaveTo, but for a single item
    // - you can use ElemLoad method later to retrieve its content
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write ElemSave(i+10) e.g.)
    function ElemSave(const Elem): RawByteString;
    /// load an array element as saved by the ElemSave method into Elem variable
    // - warning: Elem must be of the same exact type than the dynamic array,
    // and must be a reference to a variable (you can't write ElemLoad(P,i+10) e.g.)
    procedure ElemLoad(Source: PAnsiChar; var Elem; SourceMax: PAnsiChar=nil); overload;
    /// load an array element as saved by the ElemSave method
    // - this overloaded method will retrieve the element as a memory buffer,
    // which should be cleared by ElemLoadClear() before release
    function ElemLoad(Source: PAnsiChar; SourceMax: PAnsiChar=nil): RawByteString; overload;
    /// search for an array element as saved by the ElemSave method
    // - same as ElemLoad() + Find()/IndexOf() + ElemLoadClear()
    // - will call Find() method if Compare property is set
    // - will call generic IndexOf() method if no Compare property is set
    function ElemLoadFind(Source: PAnsiChar; SourceMax: PAnsiChar=nil): integer;
    /// finalize a temporary buffer used to store an element via ElemLoad()
    // - will release any managed type referenced inside the RawByteString,
    // then void the variable
    // - is just a wrapper around ElemClear(pointer(ElemTemp)) + ElemTemp := ''
    procedure ElemLoadClear(var ElemTemp: RawByteString);

    /// retrieve or set the number of elements of the dynamic array
    // - same as length(DynArray) or SetLength(DynArray)
    // - this property will recognize T*ObjArray types, so will free any stored
    // instance if the array is sized down
    property Count: PtrInt read GetCount write SetCount;
    /// the internal buffer capacity
    // - if no external Count pointer was set with Init, is the same as Count
    // - if an external Count pointer is set, you can set a value to this
    // property before a massive use of the Add() method e.g.
    // - if no external Count pointer is set, set a value to this property
    // will affect the Count value, i.e. Add() will append after this count
    // - this property will recognize T*ObjArray types, so will free any stored
    // instance if the array is sized down
    property Capacity: PtrInt read GetCapacity write SetCapacity;
    /// the compare function to be used for Sort and Find methods
    // - by default, no comparison function is set
    // - common functions exist for base types: e.g. SortDynArrayByte, SortDynArrayBoolean,
    // SortDynArrayWord, SortDynArrayInteger, SortDynArrayCardinal, SortDynArraySingle,
    // SortDynArrayInt64, SortDynArrayDouble, SortDynArrayAnsiString,
    // SortDynArrayAnsiStringI, SortDynArrayString, SortDynArrayStringI,
    // SortDynArrayUnicodeString, SortDynArrayUnicodeStringI
    property Compare: TDynArraySortCompare read fCompare write SetCompare;
    /// must be TRUE if the array is currently in sorted order according to
    // the compare function
    // - Add/Delete/Insert/Load* methods will reset this property to false
    // - Sort method will set this property to true
    // - you MUST set this property to false if you modify the dynamic array
    // content in your code, so that Find() won't try to wrongly use binary
    // search in an unsorted array, and miss its purpose
    property Sorted: boolean read fSorted write fSorted;
    /// low-level direct access to the storage variable
    property Value: PPointer read fValue;
    /// the first field recognized type
    // - could have been set at initialization, or after a GuessKnownType call
    property KnownType: TDynArrayKind read fKnownType;
    /// the raw storage size of the first field KnownType
    property KnownSize: integer read fKnownSize;
    /// the known RTTI information of the whole array
    property ArrayType: pointer read fTypeInfo;
    /// the known type name of the whole array, as RawUTF8
    property ArrayTypeName: RawUTF8 read GetArrayTypeName;
    /// the known type name of the whole array, as PShortString
    property ArrayTypeShort: PShortString read GetArrayTypeShort;
    /// the internal in-memory size of one element, as retrieved from RTTI
    property ElemSize: cardinal read fElemSize;
    /// the internal type information of one element, as retrieved from RTTI
    property ElemType: pointer read fElemType;
    /// if this dynamic aray is a T*ObjArray
    property IsObjArray: boolean read GetIsObjArray write SetIsObjArray;
  end;
  /// a pointer to a TDynArray wrapper instance
  PDynArray = ^TDynArray;

// 5921 ------------------------------------------------------------------------

   /// function prototype to be used for hashing of a dynamic array element
  // - this function must use the supplied hasher on the Elem data
  TDynArrayHashOne = function(const Elem; Hasher: THasher): cardinal;

  /// event handler to be used for hashing of a dynamic array element
  // - can be set as an alternative to TDynArrayHashOne
  TEventDynArrayHashOne = function(const Elem): cardinal of object;

  {.$define DYNARRAYHASHCOLLISIONCOUNT}

  /// allow O(1) lookup to any dynamic array content
  // - this won't handle the storage process (like add/update), just efficiently
  // maintain a hash table over an existing dynamic array: several TDynArrayHasher
  // could be applied to a single TDynArray wrapper
  // - TDynArrayHashed will use a TDynArrayHasher for its own store
  {$ifdef USERECORDWITHMETHODS}TDynArrayHasher = record
  {$else}TDynArrayHasher = object {$endif}
  private
    DynArray: PDynArray;
    HashElement: TDynArrayHashOne;
    EventHash: TEventDynArrayHashOne;
    Hasher: THasher;
    HashTable: TIntegerDynArray; // store 0 for void entry, or Index+1
    HashTableSize: integer;
    ScanCounter: integer; // Scan()>=0 up to CountTrigger*2
    State: set of (hasHasher, canHash);
    function HashTableIndex(aHashCode: cardinal): cardinal; {$ifdef HASINLINE}inline;{$endif}
    procedure HashAdd(aHashCode: cardinal; var result: integer);
    procedure HashDelete(aArrayIndex, aHashTableIndex: integer; aHashCode: cardinal);
    procedure RaiseFatalCollision(const caller: RawUTF8; aHashCode: cardinal);
  public
    /// associated item comparison - may differ from DynArray^.Compare
    Compare: TDynArraySortCompare;
    /// custom method-based comparison function
    EventCompare: TEventDynArraySortCompare;
    /// after how many FindBeforeAdd() or Scan() the hashing starts - default 32
    CountTrigger: integer;
    {$ifdef DYNARRAYHASHCOLLISIONCOUNT}
    /// low-level access to an hash collisions counter
    FindCollisions: cardinal;
    {$endif}
    /// initialize the hash table for a given dynamic array storage
    // - you can call this method several times, e.g. if aCaseInsensitive changed
    procedure Init(aDynArray: PDynArray; aHashElement: TDynArrayHashOne;
     aEventHash: TEventDynArrayHashOne; aHasher: THasher; aCompare: TDynArraySortCompare;
     aEventCompare: TEventDynArraySortCompare; aCaseInsensitive: boolean);
    /// initialize a known hash table for a given dynamic array storage
    // - you can call this method several times, e.g. if aCaseInsensitive changed
    procedure InitSpecific(aDynArray: PDynArray; aKind: TDynArrayKind; aCaseInsensitive: boolean);
    /// allow custom hashing via a method event
    procedure SetEventHash(const event: TEventDynArrayHashOne);
    /// search for an element value inside the dynamic array without hashing
    // - trigger hashing if ScanCounter reaches CountTrigger*2
    function Scan(Elem: pointer): integer;
    /// search for an element value inside the dynamic array with hashing
    function Find(Elem: pointer): integer; overload;
    /// search for a hashed element value inside the dynamic array with hashing
    function Find(Elem: pointer; aHashCode: cardinal): integer; overload;
    /// search for a hash position inside the dynamic array with hashing
    function Find(aHashCode: cardinal; aForAdd: boolean): integer; overload;
    /// returns position in array, or next void index in HashTable[] as -(index+1)
    function FindOrNew(aHashCode: cardinal; Elem: pointer; aHashTableIndex: PInteger=nil): integer;
    /// search an hashed element value for adding, updating the internal hash table
    // - trigger hashing if Count reaches CountTrigger
    function FindBeforeAdd(Elem: pointer; out wasAdded: boolean; aHashCode: cardinal): integer;
    /// search and delete an element value, updating the internal hash table
    function FindBeforeDelete(Elem: pointer): integer;
    /// reset the hash table - no rehash yet
    procedure Clear;
    /// full computation of the internal hash table
    // - returns the number of duplicated values found
    function ReHash(forced: boolean): integer;
    /// compute the hash of a given item
    function HashOne(Elem: pointer): cardinal; {$ifdef FPC_OR_DELPHIXE4}inline;{$endif}
      { not inlined to circumvent Delphi 2007=C1632, 2010=C1872, XE3=C2130 }
    /// retrieve the low-level hash of a given item
    function GetHashFromIndex(aIndex: PtrInt): cardinal;
  end;

  /// pointer to a TDynArrayHasher instance
  PDynArrayHasher = ^TDynArrayHasher;

  /// used to access any dynamic arrray elements using fast hash
  // - by default, binary sort could be used for searching items for TDynArray:
  // using a hash is faster on huge arrays for implementing a dictionary
  // - in this current implementation, modification (update or delete) of an
  // element is not handled yet: you should rehash all content - only
  // TDynArrayHashed.FindHashedForAdding / FindHashedAndUpdate /
  // FindHashedAndDelete will refresh the internal hash
  // - this object extends the TDynArray type, since presence of Hashs[] dynamic
  // array will increase code size if using TDynArrayHashed instead of TDynArray
  // - in order to have the better performance, you should use an external Count
  // variable, AND set the Capacity property to the expected maximum count (this
  // will avoid most ReHash calls for FindHashedForAdding+FindHashedAndUpdate)
  {$ifdef UNDIRECTDYNARRAY}
  TDynArrayHashed = record
  // pseudo inheritance for most used methods
  private
    function GetCount: PtrInt;                 inline;
    procedure SetCount(aCount: PtrInt) ;       inline;
    procedure SetCapacity(aCapacity: PtrInt);  inline;
    function GetCapacity: PtrInt;              inline;
  public
    InternalDynArray: TDynArray;
    function Value: PPointer;           inline;
    function ElemSize: PtrUInt;         inline;
    function ElemType: Pointer;         inline;
    function KnownType: TDynArrayKind;  inline;
    procedure Clear;                    inline;
    procedure ElemCopy(const A; var B); inline;
    function ElemPtr(index: PtrInt): pointer; inline;
    procedure ElemCopyAt(index: PtrInt; var Dest); inline;
    // warning: you shall call ReHash() after manual Add/Delete
    function Add(const Elem): integer;  inline;
    procedure Delete(aIndex: PtrInt);  inline;
    function SaveTo: RawByteString; overload; inline;
    function SaveTo(Dest: PAnsiChar): PAnsiChar; overload; inline;
    function SaveToJSON(EnumSetsAsText: boolean=false;
      reformat: TTextWriterJSONFormat=jsonCompact): RawUTF8; inline;
    procedure Sort(aCompare: TDynArraySortCompare=nil); inline;
    function LoadFromJSON(P: PUTF8Char; aEndOfObject: PUTF8Char=nil{$ifndef NOVARIANTS};
      CustomVariantOptions: PDocVariantOptions=nil{$endif}): PUTF8Char; inline;
    function SaveToLength: integer; inline;
    function LoadFrom(Source: PAnsiChar; AfterEach: TDynArrayAfterLoadFrom=nil;
      NoCheckHash: boolean=false; SourceMax: PAnsiChar=nil): PAnsiChar;  inline;
    function LoadFromBinary(const Buffer: RawByteString;
      NoCheckHash: boolean=false): boolean; inline;
    procedure CreateOrderedIndex(var aIndex: TIntegerDynArray;
      aCompare: TDynArraySortCompare);
    property Count: PtrInt read GetCount write SetCount;
    property Capacity: PtrInt read GetCapacity write SetCapacity;
  private
  {$else UNDIRECTDYNARRAY}
  TDynArrayHashed = object(TDynArray)
  protected
  {$endif UNDIRECTDYNARRAY}
    fHash: TDynArrayHasher;
    procedure SetEventHash(const event: TEventDynArrayHashOne); {$ifdef HASINLINE}inline;{$endif}
    function GetHashFromIndex(aIndex: PtrInt): Cardinal; {$ifdef HASINLINE}inline;{$endif}
  public
    /// initialize the wrapper with a one-dimension dynamic array
    // - this version accepts some hash-dedicated parameters: aHashElement to
    // set how to hash each element, aCompare to handle hash collision
    // - if no aHashElement is supplied, it will hash according to the RTTI, i.e.
    // strings or binary types, and the first field for records (strings included)
    // - if no aCompare is supplied, it will use default Equals() method
    // - if no THasher function is supplied, it will use the one supplied in
    // DefaultHasher global variable, set to crc32c() by default - using
    // SSE4.2 instruction if available
    // - if CaseInsensitive is set to TRUE, it will ignore difference in 7 bit
    // alphabetic characters (e.g. compare 'a' and 'A' as equal)
    procedure Init(aTypeInfo: pointer; var aValue;
      aHashElement: TDynArrayHashOne=nil; aCompare: TDynArraySortCompare=nil;
      aHasher: THasher=nil; aCountPointer: PInteger=nil; aCaseInsensitive: boolean=false);
    /// initialize the wrapper with a one-dimension dynamic array
    // - this version accepts to specify how both hashing and comparison should
    // occur, setting the TDynArrayKind kind of first/hashed field
    // - djNone and djCustom are too vague, and will raise an exception
    // - no RTTI check is made over the corresponding array layout: you shall
    // ensure that aKind matches the dynamic array element definition
    // - aCaseInsensitive will be used for djRawUTF8..djHash512 text comparison
    procedure InitSpecific(aTypeInfo: pointer; var aValue; aKind: TDynArrayKind;
      aCountPointer: PInteger=nil; aCaseInsensitive: boolean=false);
    /// will compute all hash from the current elements of the dynamic array
    // - is called within the TDynArrayHashed.Init method to initialize the
    // internal hash array
    // - can be called on purpose, when modifications have been performed on
    // the dynamic array content (e.g. in case of element deletion or update,
    // or after calling LoadFrom/Clear method) - this is not necessary after
    // FindHashedForAdding / FindHashedAndUpdate / FindHashedAndDelete methods
    // - returns the number of duplicated items found - which won't be available
    // by hashed FindHashed() by definition
    function ReHash(forAdd: boolean=false): integer;
    /// search for an element value inside the dynamic array using hashing
    // - Elem should be of the type expected by both the hash function and
    // Equals/Compare methods: e.g. if the searched/hashed field in a record is
    // a string as first field, you can safely use a string variable as Elem
    // - Elem must refer to a variable: e.g. you can't write FindHashed(i+10)
    // - will call fHashElement(Elem,fHasher) to compute the needed hash
    // - returns -1 if not found, or the index in the dynamic array if found
    function FindHashed(const Elem): integer;
    /// search for an element value inside the dynamic array using its hash
    // - returns -1 if not found, or the index in the dynamic array if found
    // - aHashCode parameter constains an already hashed value of the item,
    // to be used e.g. after a call to HashFind()
    function FindFromHash(const Elem; aHashCode: cardinal): integer;
    /// search for an element value inside the dynamic array using hashing, and
    // fill Elem with the found content
    // - return the index found (0..Count-1), or -1 if Elem was not found
    // - ElemToFill should be of the type expected by the dynamic array, since
    // all its fields will be set on match
    function FindHashedAndFill(var ElemToFill): integer;
    /// search for an element value inside the dynamic array using hashing, and
    // add a void entry to the array if was not found (unless noAddEntry is set)
    // - this method will use hashing for fast retrieval
    // - Elem should be of the type expected by both the hash function and
    // Equals/Compare methods: e.g. if the searched/hashed field in a record is
    // a string as first field, you can safely use a string variable as Elem
    // - returns either the index in the dynamic array if found (and set wasAdded
    // to false), either the newly created index in the dynamic array (and set
    // wasAdded to true)
    // - for faster process (avoid ReHash), please set the Capacity property
    // - warning: in contrast to the Add() method, if an entry is added to the
    // array (wasAdded=true), the entry is left VOID: you must set the field
    // content to expecting value - in short, Elem is used only for searching,
    // not copied to the newly created entry in the array  - check
    // FindHashedAndUpdate() for a method actually copying Elem fields
    function FindHashedForAdding(const Elem; out wasAdded: boolean;
      noAddEntry: boolean=false): integer; overload;
    /// search for an element value inside the dynamic array using hashing, and
    // add a void entry to the array if was not found (unless noAddEntry is set)
    // - overloaded method acepting an already hashed value of the item, to be used
    // e.g. after a call to HashFind()
    function FindHashedForAdding(const Elem; out wasAdded: boolean;
      aHashCode: cardinal; noAddEntry: boolean=false): integer; overload;
    /// ensure a given element name is unique, then add it to the array
    // - expected element layout is to have a RawUTF8 field at first position
    // - the aName is searched (using hashing) to be unique, and if not the case,
    // an ESynException.CreateUTF8() is raised with the supplied arguments
    // - use internaly FindHashedForAdding method
    // - this version will set the field content with the unique value
    // - returns a pointer to the newly added element (to set other fields)
    function AddUniqueName(const aName: RawUTF8; const ExceptionMsg: RawUTF8;
      const ExceptionArgs: array of const; aNewIndex: PInteger=nil): pointer; overload;
    /// ensure a given element name is unique, then add it to the array
    // - just a wrapper to AddUniqueName(aName,'',[],aNewIndex)
    function AddUniqueName(const aName: RawUTF8; aNewIndex: PInteger=nil): pointer; overload;
    /// search for a given element name, make it unique, and add it to the array
    // - expected element layout is to have a RawUTF8 field at first position
    // - the aName is searched (using hashing) to be unique, and if not the case,
    // some suffix is added to make it unique
    // - use internaly FindHashedForAdding method
    // - this version will set the field content with the unique value
    // - returns a pointer to the newly added element (to set other fields)
    function AddAndMakeUniqueName(aName: RawUTF8): pointer;
    /// search for an element value inside the dynamic array using hashing, then
    // update any matching item, or add the item if none matched
    // - by design, hashed field shouldn't have been modified by this update,
    // otherwise the method won't be able to find and update the old hash: in
    // this case, you should first call FindHashedAndDelete(OldElem) then
    // FindHashedForAdding(NewElem) to properly handle the internal hash table
    // - if AddIfNotExisting is FALSE, returns the index found (0..Count-1),
    // or -1 if Elem was not found - update will force slow rehash all content
    // - if AddIfNotExisting is TRUE, returns the index found (0..Count-1),
    // or the index newly created/added is the Elem value was not matching -
    // add won't rehash all content - for even faster process (avoid ReHash),
    // please set the Capacity property
    // - Elem should be of the type expected by the dynamic array, since its
    // content will be copied into the dynamic array, and it must refer to a
    // variable: e.g. you can't write FindHashedAndUpdate(i+10)
    function FindHashedAndUpdate(const Elem; AddIfNotExisting: boolean): integer;
    /// search for an element value inside the dynamic array using hashing, and
    // delete it if matchs
    // - return the index deleted (0..Count-1), or -1 if Elem was not found
    // - can optionally copy the deleted item to FillDeleted^ before erased
    // - Elem should be of the type expected by both the hash function and
    // Equals/Compare methods, and must refer to a variable: e.g. you can't
    // write FindHashedAndDelete(i+10)
    // - it won't call slow ReHash but refresh the hash table as needed
    function FindHashedAndDelete(const Elem; FillDeleted: pointer=nil;
      noDeleteEntry: boolean=false): integer;
    /// will search for an element value inside the dynamic array without hashing
    // - is used internally when Count < HashCountTrigger
    // - is preferred to Find(), since EventCompare would be used if defined
    // - Elem should be of the type expected by both the hash function and
    // Equals/Compare methods, and must refer to a variable: e.g. you can't
    // write Scan(i+10)
    // - returns -1 if not found, or the index in the dynamic array if found
    // - an internal algorithm can switch to hashing if Scan() is called often,
    // even if the number of items is lower than HashCountTrigger
    function Scan(const Elem): integer;
    /// retrieve the hash value of a given item, from its index
    property Hash[aIndex: PtrInt]: Cardinal read GetHashFromIndex;
    /// alternative event-oriented Compare function to be used for Sort and Find
    // - will be used instead of Compare, to allow object-oriented callbacks
    property EventCompare: TEventDynArraySortCompare read fHash.EventCompare write fHash.EventCompare;
    /// custom hash function to be used for hashing of a dynamic array element
    property HashElement: TDynArrayHashOne read fHash.HashElement;
    /// alternative event-oriented Hash function for ReHash
    // - this object-oriented callback will be used instead of HashElement
    // on each dynamic array entries - HashElement will still be used on
    // const Elem values, since they may be just a sub part of the stored entry
    property EventHash: TEventDynArrayHashOne read fHash.EventHash write SetEventHash;
    /// after how many items the hashing take place
    // - for smallest arrays, O(n) search if faster than O(1) hashing, since
    // maintaining internal hash table has some CPU and memory costs
    // - internal search is able to switch to hashing if it founds out that it
    // may have some benefit, e.g. if Scan() is called 2*HashCountTrigger times
    // - equals 32 by default, i.e. start hashing when Count reaches 32 or
    // manual Scan() is called 64 times
    property HashCountTrigger: integer read fHash.CountTrigger write fHash.CountTrigger;
    /// access to the internal hash table
    // - you can call e.g. Hasher.Clear to invalidate the whole hash table
    property Hasher: TDynArrayHasher read fHash;
  end;  

//6369  ------------------------------------------------------------------------

  /// our own empowered TPersistent-like parent class
  // - TPersistent has an unexpected speed overhead due a giant lock introduced
  // to manage property name fixup resolution (which we won't use outside the VCL)
  // - this class has a virtual constructor, so is a preferred alternative
  // to both TPersistent and TPersistentWithCustomCreate classes
  // - for best performance, any type inheriting from this class will bypass
  // some regular steps: do not implement interfaces or use TMonitor with them!
  TSynPersistent = class(TObject)
  protected
    // this default implementation will call AssignError()
    procedure AssignTo(Dest: TSynPersistent); virtual;
    procedure AssignError(Source: TSynPersistent);
  public
    /// this virtual constructor will be called at instance creation
    // - this constructor does nothing, but is declared as virtual so that
    // inherited classes may safely override this default void implementation
    constructor Create; virtual;
    /// allows to implement a TPersistent-like assignement mechanism
    // - inherited class should override AssignTo() protected method
    // to implement the proper assignment
    procedure Assign(Source: TSynPersistent); virtual;
    /// optimized initialization code
    // - somewhat faster than the regular RTL implementation - especially
    // since rewritten in pure asm on Delphi/x86
    // - warning: this optimized version won't initialize the vmtIntfTable
    // for this class hierarchy: as a result, you would NOT be able to
    // implement an interface with a TSynPersistent descendent (but you should
    // not need to, but inherit from TInterfacedObject)
    // - warning: under FPC, it won't initialize fields management operators
    class function NewInstance: TObject; override;
    {$ifndef FPC_OR_PUREPASCAL}
    /// optimized x86 asm finalization code
    // - warning: this version won't release either any allocated TMonitor
    // (as available since Delphi 2009) - do not use TMonitor with
    // TSynPersistent, but rather the faster TSynPersistentLock class
    procedure FreeInstance; override;
    {$endif}
  end;
  {$M-}

// 6467 ------------------------------------------------------------------------

  /// allow to add cross-platform locking methods to any class instance
  // - typical use is to define a Safe: TSynLocker property, call Safe.Init
  // and Safe.Done in constructor/destructor methods, and use Safe.Lock/UnLock
  // methods in a try ... finally section
  // - in respect to the TCriticalSection class, fix a potential CPU cache line
  // conflict which may degrade the multi-threading performance, as reported by
  // @http://www.delphitools.info/2011/11/30/fixing-tcriticalsection
  // - internal padding is used to safely store up to 7 values protected
  // from concurrent access with a mutex, so that SizeOf(TSynLocker)>128
  // - for object-level locking, see TSynPersistentLock which owns one such
  // instance, or call low-level fSafe := NewSynLocker in your constructor,
  // then fSafe^.DoneAndFreemem in your destructor
  TSynLocker = object
  protected
    fSection: TRTLCriticalSection;
    fLockCount: integer;
    fInitialized: boolean;
    {$ifndef NOVARIANTS}
    function GetVariant(Index: integer): Variant;
    procedure SetVariant(Index: integer; const Value: Variant);
    function GetInt64(Index: integer): Int64;
    procedure SetInt64(Index: integer; const Value: Int64);
    function GetBool(Index: integer): boolean;
    procedure SetBool(Index: integer; const Value: boolean);
    function GetUnlockedInt64(Index: integer): Int64;
    procedure SetUnlockedInt64(Index: integer; const Value: Int64);
    function GetPointer(Index: integer): Pointer;
    procedure SetPointer(Index: integer; const Value: Pointer);
    function GetUTF8(Index: integer): RawUTF8;
    procedure SetUTF8(Index: integer; const Value: RawUTF8);
    function GetIsLocked: boolean; {$ifdef HASINLINE}inline;{$endif}
    {$endif NOVARIANTS}
  public
    /// number of values stored in the internal Padding[] array
    // - equals 0 if no value is actually stored, or a 1..7 number otherwise
    // - you should not have to use this field, but for optimized low-level
    // direct access to Padding[] values, within a Lock/UnLock safe block
    PaddingUsedCount: integer;
    /// internal padding data, also used to store up to 7 variant values
    // - this memory buffer will ensure no CPU cache line mixup occurs
    // - you should not use this field directly, but rather the Locked[],
    // LockedInt64[], LockedUTF8[] or LockedPointer[] methods
    // - if you want to access those array values, ensure you protect them
    // using a Safe.Lock; try ... Padding[n] ... finally Safe.Unlock structure,
    // and maintain the PaddingUsedCount field accurately
    Padding: array[0..6] of TVarData;
    /// initialize the mutex
    // - calling this method is mandatory (e.g. in the class constructor owning
    // the TSynLocker instance), otherwise you may encounter unexpected
    // behavior, like access violations or memory leaks
    procedure Init;
    /// finalize the mutex
    // - calling this method is mandatory (e.g. in the class destructor owning
    // the TSynLocker instance), otherwise you may encounter unexpected
    // behavior, like access violations or memory leaks
    procedure Done;
    /// finalize the mutex, and call FreeMem() on the pointer of this instance
    // - should have been initiazed with a NewSynLocker call
    procedure DoneAndFreeMem;
    /// lock the instance for exclusive access
    // - this method is re-entrant from the same thread (you can nest Lock/UnLock
    // calls in the same thread), but would block any other Lock attempt in
    // another thread
    // - use as such to avoid race condition (from a Safe: TSynLocker property):
    // ! Safe.Lock;
    // ! try
    // !   ...
    // ! finally
    // !   Safe.Unlock;
    // ! end;
    procedure Lock; {$ifdef HASINLINE}inline;{$endif}
    /// will try to acquire the mutex
    // - use as such to avoid race condition (from a Safe: TSynLocker property):
    // ! if Safe.TryLock then
    // !   try
    // !     ...
    // !   finally
    // !     Safe.Unlock;
    // !   end;
    function TryLock: boolean; {$ifdef HASINLINE}inline;{$endif}
    /// will try to acquire the mutex for a given time
    // - use as such to avoid race condition (from a Safe: TSynLocker property):
    // ! if Safe.TryLockMS(100) then
    // !   try
    // !     ...
    // !   finally
    // !     Safe.Unlock;
    // !   end;
    function TryLockMS(retryms: integer): boolean;
    /// release the instance for exclusive access
    // - each Lock/TryLock should have its exact UnLock opposite, so a
    // try..finally block is mandatory for safe code
    procedure UnLock; {$ifdef HASINLINE}inline;{$endif}
    /// will enter the mutex until the IUnknown reference is released
    // - could be used as such under Delphi:
    // !begin
    // !  ... // unsafe code
    // !  Safe.ProtectMethod;
    // !  ... // thread-safe code
    // !end; // local hidden IUnknown will release the lock for the method
    // - warning: under FPC, you should assign its result to a local variable -
    // see bug http://bugs.freepascal.org/view.php?id=26602
    // !var LockFPC: IUnknown;
    // !begin
    // !  ... // unsafe code
    // !  LockFPC := Safe.ProtectMethod;
    // !  ... // thread-safe code
    // !end; // LockFPC will release the lock for the method
    // or
    // !begin
    // !  ... // unsafe code
    // !  with Safe.ProtectMethod do begin
    // !    ... // thread-safe code
    // !  end; // local hidden IUnknown will release the lock for the method
    // !end;
    function ProtectMethod: IUnknown;
    /// returns true if the mutex is currently locked by another thread
    property IsLocked: boolean read GetIsLocked;
    /// returns true if the Init method has been called for this mutex
    // - is only relevant if the whole object has been previously filled with 0,
    // i.e. as part of a class or as global variable, but won't be accurate
    // when allocated on stack
    property IsInitialized: boolean read fInitialized;
    {$ifndef NOVARIANTS}
    /// safe locked access to a Variant value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // LockedBool, LockedInt64, LockedPointer and LockedUTF8 array properties
    // - returns null if the Index is out of range
    property Locked[Index: integer]: Variant read GetVariant write SetVariant;
    /// safe locked access to a Int64 value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUTF8 array properties
    // - Int64s will be stored internally as a varInt64 variant
    // - returns nil if the Index is out of range, or does not store a Int64
    property LockedInt64[Index: integer]: Int64 read GetInt64 write SetInt64;
    /// safe locked access to a boolean value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked, LockedInt64, LockedPointer and LockedUTF8 array properties
    // - value will be stored internally as a varBoolean variant
    // - returns nil if the Index is out of range, or does not store a boolean
    property LockedBool[Index: integer]: boolean read GetBool write SetBool;
    /// safe locked access to a pointer/TObject value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked, LockedBool, LockedInt64 and LockedUTF8 array properties
    // - pointers will be stored internally as a varUnknown variant
    // - returns nil if the Index is out of range, or does not store a pointer
    property LockedPointer[Index: integer]: Pointer read GetPointer write SetPointer;
    /// safe locked access to an UTF-8 string value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedPointer array properties
    // - UTF-8 string will be stored internally as a varString variant
    // - returns '' if the Index is out of range, or does not store a string
    property LockedUTF8[Index: integer]: RawUTF8 read GetUTF8 write SetUTF8;
    /// safe locked in-place increment to an Int64 value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUTF8 array properties
    // - Int64s will be stored internally as a varInt64 variant
    // - returns the newly stored value
    // - if the internal value is not defined yet, would use 0 as default value
    function LockedInt64Increment(Index: integer; const Increment: Int64): Int64;
    /// safe locked in-place exchange of a Variant value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUTF8 array properties
    // - returns the previous stored value, or null if the Index is out of range
    function LockedExchange(Index: integer; const Value: variant): variant;
    /// safe locked in-place exchange of a pointer/TObject value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUTF8 array properties
    // - pointers will be stored internally as a varUnknown variant
    // - returns the previous stored value, nil if the Index is out of range,
    // or does not store a pointer
    function LockedPointerExchange(Index: integer; Value: pointer): pointer;
    /// unsafe access to a Int64 value
    // - you may store up to 7 variables, using an 0..6 index, shared with
    // Locked and LockedUTF8 array properties
    // - Int64s will be stored internally as a varInt64 variant
    // - returns nil if the Index is out of range, or does not store a Int64
    // - you should rather call LockedInt64[] property, or use this property
    // with a Lock; try ... finally UnLock block
    property UnlockedInt64[Index: integer]: Int64 read GetUnlockedInt64 write SetUnlockedInt64;
    {$endif NOVARIANTS}
  end;
  PSynLocker = ^TSynLocker;

  /// adding locking methods to a TSynPersistent with virtual constructor
  // - you may use this class instead of the RTL TCriticalSection, since it
  // would use a TSynLocker which does not suffer from CPU cache line conflit
  TSynPersistentLock = class(TSynPersistent)
  protected
    fSafe: PSynLocker; // TSynLocker would increase inherited fields offset
  public
    /// initialize the instance, and its associated lock
    constructor Create; override;
    /// finalize the instance, and its associated lock
    destructor Destroy; override;
    /// access to the associated instance critical section
    // - call Safe.Lock/UnLock to protect multi-thread access on this storage
    property Safe: PSynLocker read fSafe;
  end;

// 7343 ------------------------------------------------------------------------

/// fill some memory buffer with random values
// - the destination buffer is expected to be allocated as 32-bit items
// - use internally crc32c() with some rough entropy source, and Random32
// gsl_rng_taus2 generator or hardware RDRAND Intel x86/x64 opcode if available
// (and ForceGsl is kept to its default false)
// - consider using instead the cryptographic secure TAESPRNG.Main.FillRandom()
// method from the SynCrypto unit, or set ForceGsl=true - in particular, RDRAND
// is reported as very slow: see https://en.wikipedia.org/wiki/RdRand#Performance
procedure FillRandom(Dest: PCardinalArray; CardinalCount: integer; ForceGsl: boolean=false);

// 9856 ------------------------------------------------------------------------

type
  /// define the implemetation used by TAlgoCompress.Decompress()
  TAlgoCompressLoad = (aclNormal, aclSafeSlow, aclNoCrcFast);

  /// abstract low-level parent class for generic compression/decompression algorithms
  // - will encapsulate the compression algorithm with crc32c hashing
  // - all Algo* abstract methods should be overriden by inherited classes
  TAlgoCompress = class(TSynPersistent)
  public
    /// should return a genuine byte identifier
    // - 0 is reserved for stored, 1 for TAlgoSynLz, 2/3 for TAlgoDeflate/Fast
    // (in mORMot.pas), 4/5/6 for TAlgoLizard/Fast/Huffman (in SynLizard.pas)
    function AlgoID: byte; virtual; abstract;
    /// computes by default the crc32c() digital signature of the buffer
    function AlgoHash(Previous: cardinal; Data: pointer; DataLen: integer): cardinal; virtual;
    /// get maximum possible (worse) compressed size for the supplied length
    function AlgoCompressDestLen(PlainLen: integer): integer; virtual; abstract;
    /// this method will compress the supplied data
    function AlgoCompress(Plain: pointer; PlainLen: integer; Comp: pointer): integer; virtual; abstract;
    /// this method will return the size of the decompressed data
    function AlgoDecompressDestLen(Comp: pointer): integer; virtual; abstract;
    /// this method will decompress the supplied data
    function AlgoDecompress(Comp: pointer; CompLen: integer; Plain: pointer): integer; virtual; abstract;
    /// this method will partially and safely decompress the supplied data
    // - expects PartialLen <= result < PartialLenMax, depending on the algorithm
    function AlgoDecompressPartial(Comp: pointer; CompLen: integer;
      Partial: pointer; PartialLen, PartialLenMax: integer): integer; virtual; abstract;
  public
    /// will register AlgoID in the global list, for Algo() class methods
    // - no need to free this instance, since it will be owned by the global list
    // - raise a ESynException if the class or its AlgoID are already registered
    // - you should never have to call this constructor, but define a global
    // variable holding a reference to a shared instance
    constructor Create; override;
    /// get maximum possible (worse) compressed size for the supplied length
    // - including the crc32c + algo 9 bytes header
    function CompressDestLen(PlainLen: integer): integer;
      {$ifdef HASINLINE}inline;{$endif}
    /// compress a memory buffer with crc32c hashing to a RawByteString
    function Compress(const Plain: RawByteString; CompressionSizeTrigger: integer=100;
      CheckMagicForCompressed: boolean=false; BufferOffset: integer=0): RawByteString; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// compress a memory buffer with crc32c hashing to a RawByteString
    function Compress(Plain: PAnsiChar; PlainLen: integer; CompressionSizeTrigger: integer=100;
      CheckMagicForCompressed: boolean=false; BufferOffset: integer=0): RawByteString; overload;
    /// compress a memory buffer with crc32c hashing
    // - supplied Comp buffer should contain at least CompressDestLen(PlainLen) bytes
    function Compress(Plain, Comp: PAnsiChar; PlainLen, CompLen: integer;
      CompressionSizeTrigger: integer=100; CheckMagicForCompressed: boolean=false): integer; overload;
    /// compress a memory buffer with crc32c hashing to a TByteDynArray
    function CompressToBytes(const Plain: RawByteString; CompressionSizeTrigger: integer=100;
      CheckMagicForCompressed: boolean=false): TByteDynArray; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// compress a memory buffer with crc32c hashing to a TByteDynArray
    function CompressToBytes(Plain: PAnsiChar; PlainLen: integer; CompressionSizeTrigger: integer=100;
      CheckMagicForCompressed: boolean=false): TByteDynArray; overload;
    /// uncompress a RawByteString memory buffer with crc32c hashing
    function Decompress(const Comp: RawByteString; Load: TAlgoCompressLoad=aclNormal;
      BufferOffset: integer=0): RawByteString; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// uncompress a RawByteString memory buffer with crc32c hashing
    // - returns TRUE on success
    function TryDecompress(const Comp: RawByteString; out Dest: RawByteString;
      Load: TAlgoCompressLoad=aclNormal): boolean;
    /// uncompress a memory buffer with crc32c hashing
    procedure Decompress(Comp: PAnsiChar; CompLen: integer; out Result: RawByteString;
      Load: TAlgoCompressLoad=aclNormal; BufferOffset: integer=0); overload;
    /// uncompress a RawByteString memory buffer with crc32c hashing
    function Decompress(const Comp: TByteDynArray): RawByteString; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// uncompress a RawByteString memory buffer with crc32c hashing
    // - returns nil if crc32 hash failed, i.e. if the supplied Comp is not correct
    // - returns a pointer to the uncompressed data and fill PlainLen variable,
    // after crc32c hash
    // - avoid any memory allocation in case of a stored content - otherwise, would
    // uncompress to the tmp variable, and return pointer(tmp) and length(tmp)
    function Decompress(const Comp: RawByteString; out PlainLen: integer;
      var tmp: RawByteString; Load: TAlgoCompressLoad=aclNormal): pointer; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// uncompress a RawByteString memory buffer with crc32c hashing
    // - returns nil if crc32 hash failed, i.e. if the supplied Data is not correct
    // - returns a pointer to an uncompressed data buffer of PlainLen bytes
    // - avoid any memory allocation in case of a stored content - otherwise, would
    // uncompress to the tmp variable, and return pointer(tmp) and length(tmp)
    function Decompress(Comp: PAnsiChar; CompLen: integer; out PlainLen: integer;
      var tmp: RawByteString; Load: TAlgoCompressLoad=aclNormal): pointer; overload;
    /// decode the header of a memory buffer compressed via the Compress() method
    // - validates the crc32c of the compressed data (unless Load=aclNoCrcFast),
    // then return the uncompressed size in bytes, or 0 if the crc32c does not match
    // - should call DecompressBody() later on to actually retrieve the content
    function DecompressHeader(Comp: PAnsiChar; CompLen: integer;
      Load: TAlgoCompressLoad=aclNormal): integer;
    /// decode the content of a memory buffer compressed via the Compress() method
    // - PlainLen has been returned by a previous call to DecompressHeader()
    function DecompressBody(Comp,Plain: PAnsiChar; CompLen,PlainLen: integer;
      Load: TAlgoCompressLoad=aclNormal): boolean;
    /// partial decoding of a memory buffer compressed via the Compress() method
    // - returns 0 on error, or how many bytes have been written to Partial
    // - will call virtual AlgoDecompressPartial() which is slower, but expected
    // to avoid any buffer overflow on the Partial destination buffer
    // - some algorithms (e.g. Lizard) may need some additional bytes in the
    // decode buffer, so PartialLenMax bytes should be allocated in Partial^,
    // with PartialLenMax > expected PartialLen, and returned bytes may be >
    // PartialLen, but always <= PartialLenMax
    function DecompressPartial(Comp,Partial: PAnsiChar; CompLen,PartialLen,PartialLenMax: integer): integer;
    /// get the TAlgoCompress instance corresponding to the AlgoID stored
    // in the supplied compressed buffer
    // - returns nil if no algorithm was identified
    class function Algo(Comp: PAnsiChar; CompLen: integer): TAlgoCompress; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// get the TAlgoCompress instance corresponding to the AlgoID stored
    // in the supplied compressed buffer
    // - returns nil if no algorithm was identified
    // - also identifies "stored" content in IsStored variable
    class function Algo(Comp: PAnsiChar; CompLen: integer; out IsStored: boolean): TAlgoCompress; overload;
    /// get the TAlgoCompress instance corresponding to the AlgoID stored
    // in the supplied compressed buffer
    // - returns nil if no algorithm was identified
    class function Algo(const Comp: RawByteString): TAlgoCompress; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// get the TAlgoCompress instance corresponding to the AlgoID stored
    // in the supplied compressed buffer
    // - returns nil if no algorithm was identified
    class function Algo(const Comp: TByteDynArray): TAlgoCompress; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// get the TAlgoCompress instance corresponding to the supplied AlgoID
    // - returns nil if no algorithm was identified
    // - stored content is identified as TAlgoSynLZ
    class function Algo(AlgoID: byte): TAlgoCompress; overload;
    /// quickly validate a compressed buffer content, without uncompression
    // - extract the TAlgoCompress, and call DecompressHeader() to check the
    // hash of the compressed data, and return then uncompressed size
    // - returns 0 on error (e.g. unknown algorithm or incorrect hash)
    class function UncompressedSize(const Comp: RawByteString): integer;
    /// returns the algorithm name, from its classname
    // - e.g. TAlgoSynLZ->'synlz' TAlgoLizard->'lizard' nil->'none'
    function AlgoName: TShort16;
  end;

// 100038 ----------------------------------------------------------------------

  // internal flag, used only by TSynDictionary.InArray protected method
  TSynDictionaryInArray = (
    iaFind, iaFindAndDelete, iaFindAndUpdate, iaFindAndAddIfNotExisting, iaAdd);

  /// event called by TSynDictionary.ForEach methods to iterate over stored items
  // - if the implementation method returns TRUE, will continue the loop
  // - if the implementation method returns FALSE, will stop values browsing
  // - aOpaque is a custom value specified at ForEach() method call
  TSynDictionaryEvent = function(const aKey; var aValue; aIndex,aCount: integer;
    aOpaque: pointer): boolean of object;

  /// event called by TSynDictionary.DeleteDeprecated
  // - called just before deletion: return false to by-pass this item
  TSynDictionaryCanDeleteEvent = function(const aKey, aValue; aIndex: integer): boolean of object;

  /// thread-safe dictionary to store some values from associated keys
  // - will maintain a dynamic array of values, associated with a hash table
  // for the keys, so that setting or retrieving values would be O(1)
  // - all process is protected by a TSynLocker, so will be thread-safe
  // - TDynArray is a wrapper which do not store anything, whereas this class
  // is able to store both keys and values, and provide convenient methods to
  // access the stored data, including JSON serialization and binary storage
  TSynDictionary = class(TSynPersistentLock)
  protected
    fKeys: TDynArrayHashed;
    fValues: TDynArray;
    fTimeOut: TCardinalDynArray;
    fTimeOuts: TDynArray;
    fCompressAlgo: TAlgoCompress;
    fOnCanDelete: TSynDictionaryCanDeleteEvent;
    function InArray(const aKey,aArrayValue; aAction: TSynDictionaryInArray): boolean;
    procedure SetTimeouts;
    function ComputeNextTimeOut: cardinal;
    function KeyFullHash(const Elem): cardinal;
    function KeyFullCompare(const A,B): integer;
    function GetCapacity: integer;
    procedure SetCapacity(const Value: integer);
    function GetTimeOutSeconds: cardinal;
  public
    /// initialize the dictionary storage, specifyng dynamic array keys/values
    // - aKeyTypeInfo should be a dynamic array TypeInfo() RTTI pointer, which
    // would store the keys within this TSynDictionary instance
    // - aValueTypeInfo should be a dynamic array TypeInfo() RTTI pointer, which
    // would store the values within this TSynDictionary instance
    // - by default, string keys would be searched following exact case, unless
    // aKeyCaseInsensitive is TRUE
    // - you can set an optional timeout period, in seconds - you should call
    // DeleteDeprecated periodically to search for deprecated items
    constructor Create(aKeyTypeInfo,aValueTypeInfo: pointer;
      aKeyCaseInsensitive: boolean=false; aTimeoutSeconds: cardinal=0;
      aCompressAlgo: TAlgoCompress=nil); reintroduce; virtual;
    /// finalize the storage
    // - would release all internal stored values
    destructor Destroy; override;
    /// try to add a value associated with a primary key
    // - returns the index of the inserted item, -1 if aKey is already existing
    // - this method is thread-safe, since it will lock the instance
    function Add(const aKey, aValue): integer;
    /// store a value associated with a primary key
    // - returns the index of the matching item
    // - if aKey does not exist, a new entry is added
    // - if aKey does exist, the existing entry is overriden with aValue
    // - this method is thread-safe, since it will lock the instance
    function AddOrUpdate(const aKey, aValue): integer;
    /// clear the value associated via aKey
    // - does not delete the entry, but reset its value
    // - returns the index of the matching item, -1 if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function Clear(const aKey): integer;
    /// delete all key/value stored in the current instance
    procedure DeleteAll;
    /// delete a key/value association from its supplied aKey
    // - this would delete the entry, i.e. matching key and value pair
    // - returns the index of the deleted item, -1 if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function Delete(const aKey): integer;
    /// delete a key/value association from its internal index
    // - this method is not thread-safe: you should use fSafe.Lock/Unlock
    // e.g. then Find/FindValue to retrieve the index value
    function DeleteAt(aIndex: integer): boolean;
    /// search and delete all deprecated items according to TimeoutSeconds
    // - returns how many items have been deleted
    // - you can call this method very often: it will ensure that the
    // search process will take place at most once every second
    // - this method is thread-safe, but blocking during the process
    function DeleteDeprecated: integer;
    /// search of a primary key within the internal hashed dictionary
    // - returns the index of the matching item, -1 if aKey was not found
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - aUpdateTimeOut will update the associated timeout value of the entry
    function Find(const aKey; aUpdateTimeOut: boolean=false): integer;
    /// search of a primary key within the internal hashed dictionary
    // - returns a pointer to the matching item, nil if aKey was not found
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - aUpdateTimeOut will update the associated timeout value of the entry
    function FindValue(const aKey; aUpdateTimeOut: boolean=false; aIndex: PInteger=nil): pointer;
    /// search of a primary key within the internal hashed dictionary
    // - returns a pointer to the matching or already existing item
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - will update the associated timeout value of the entry, if applying
    function FindValueOrAdd(const aKey; var added: boolean; aIndex: PInteger=nil): pointer;
    /// search of a stored value by its primary key, and return a local copy
    // - so this method is thread-safe
    // - returns TRUE if aKey was found, FALSE if no match exists
    // - will update the associated timeout value of the entry, unless
    // aUpdateTimeOut is set to false
    function FindAndCopy(const aKey; out aValue; aUpdateTimeOut: boolean=true): boolean;
    /// search of a stored value by its primary key, then delete and return it
    // - returns TRUE if aKey was found, fill aValue with its content,
    // and delete the entry in the internal storage
    // - so this method is thread-safe
    // - returns FALSE if no match exists
    function FindAndExtract(const aKey; out aValue): boolean;
    /// search for a primary key presence
    // - returns TRUE if aKey was found, FALSE if no match exists
    // - this method is thread-safe
    function Exists(const aKey): boolean;
    /// apply a specified event over all items stored in this dictionnary
    // - would browse the list in the adding order
    // - returns the number of times OnEach has been called
    // - this method is thread-safe, since it will lock the instance
    function ForEach(const OnEach: TSynDictionaryEvent; Opaque: pointer=nil): integer; overload;
    /// apply a specified event over matching items stored in this dictionnary
    // - would browse the list in the adding order, comparing each key and/or
    // value item with the supplied comparison functions and aKey/aValue content
    // - returns the number of times OnMatch has been called, i.e. how many times
    // KeyCompare(aKey,Keys[#])=0 or ValueCompare(aValue,Values[#])=0
    // - this method is thread-safe, since it will lock the instance
    function ForEach(const OnMatch: TSynDictionaryEvent;
      KeyCompare,ValueCompare: TDynArraySortCompare; const aKey,aValue;
      Opaque: pointer=nil): integer; overload;
    /// touch the entry timeout field so that it won't be deprecated sooner
    // - this method is not thread-safe, and is expected to be execute e.g.
    // from a ForEach() TSynDictionaryEvent callback
    procedure SetTimeoutAtIndex(aIndex: integer);
    /// search aArrayValue item in a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.Find
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue
    // were not found
    // - this method is thread-safe, since it will lock the instance
    function FindInArray(const aKey, aArrayValue): boolean;
    /// search of a stored key by its associated key, and return a key local copy
    // - won't use any hashed index but TDynArray.IndexOf over fValues,
    // so is much slower than FindAndCopy()
    // - will update the associated timeout value of the entry, unless
    // aUpdateTimeOut is set to false
    // - so this method is thread-safe
    // - returns TRUE if aValue was found, FALSE if no match exists
    function FindKeyFromValue(const aValue; out aKey; aUpdateTimeOut: boolean=true): boolean;
    /// add aArrayValue item within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.Add
    // to add aArrayValue to the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function AddInArray(const aKey, aArrayValue): boolean;
    /// add once aArrayValue within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use
    // TDynArray.FindAndAddIfNotExisting to add once aArrayValue to the
    // associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    function AddOnceInArray(const aKey, aArrayValue): boolean;
    /// clear aArrayValue item of a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.FindAndDelete
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue were
    // not found
    // - this method is thread-safe, since it will lock the instance
    function DeleteInArray(const aKey, aArrayValue): boolean;
    /// replace aArrayValue item of a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.FindAndUpdate
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue were
    // not found
    // - this method is thread-safe, since it will lock the instance
    function UpdateInArray(const aKey, aArrayValue): boolean;
    {$ifndef DELPHI5OROLDER}
    /// make a copy of the stored values
    // - this method is thread-safe, since it will lock the instance during copy
    // - resulting length(Dest) will match the exact values count
    // - T*ObjArray will be reallocated and copied by content (using a temporary
    // JSON serialization), unless ObjArrayByRef is true and pointers are copied
    procedure CopyValues(out Dest; ObjArrayByRef: boolean=false);
    {$endif DELPHI5OROLDER}

//------------------------------------------------------------------------------

    /// serialize the content as a "key":value JSON object
    //procedure SaveToJSON(W: TTextWriter; EnumSetsAsText: boolean=false); overload;
    /// serialize the content as a "key":value JSON object
    //function SaveToJSON(EnumSetsAsText: boolean=false): RawUTF8; overload;
    /// serialize the Values[] as a JSON array
    //function SaveValuesToJSON(EnumSetsAsText: boolean=false): RawUTF8;
    /// unserialize the content from "key":value JSON object
    // - if the JSON input may not be correct (i.e. if not coming from SaveToJSON),
    // you may set EnsureNoKeyCollision=TRUE for a slow but safe keys validation
    //function LoadFromJSON(const JSON: RawUTF8 {$ifndef NOVARIANTS};
    //  CustomVariantOptions: PDocVariantOptions=nil{$endif}): boolean; overload;
    /// unserialize the content from "key":value JSON object
    // - note that input JSON buffer is not modified in place: no need to create
    // a temporary copy if the buffer is about to be re-used
    //function LoadFromJSON(JSON: PUTF8Char {$ifndef NOVARIANTS};
    //  CustomVariantOptions: PDocVariantOptions=nil{$endif}): boolean; overload;

//------------------------------------------------------------------------------

    /// save the content as SynLZ-compressed raw binary data
    // - warning: this format is tied to the values low-level RTTI, so if you
    // change the value/key type definitions, LoadFromBinary() would fail
    function SaveToBinary(NoCompression: boolean=false): RawByteString;
    /// load the content from SynLZ-compressed raw binary data
    // - as previously saved by SaveToBinary method
    function LoadFromBinary(const binary: RawByteString): boolean;
    /// can be assigned to OnCanDeleteDeprecated to check TSynPersistentLock(aValue).Safe.IsLocked
    class function OnCanDeleteSynPersistentLock(const aKey, aValue; aIndex: integer): boolean;
    /// can be assigned to OnCanDeleteDeprecated to check TSynPersistentLock(aValue).Safe.IsLocked
    class function OnCanDeleteSynPersistentLocked(const aKey, aValue; aIndex: integer): boolean;
    /// returns how many items are currently stored in this dictionary
    // - this method is thread-safe
    function Count: integer;
    /// fast returns how many items are currently stored in this dictionary
    // - this method is NOT thread-safe so should be protected by fSafe.Lock/UnLock
    function RawCount: integer; {$ifdef HASINLINE}inline;{$endif}
    /// direct access to the primary key identifiers
    // - if you want to access the keys, you should use fSafe.Lock/Unlock
    property Keys: TDynArrayHashed read fKeys;
    /// direct access to the associated stored values
    // - if you want to access the values, you should use fSafe.Lock/Unlock
    property Values: TDynArray read fValues;
    /// defines how many items are currently stored in Keys/Values internal arrays
    property Capacity: integer read GetCapacity write SetCapacity;
    /// direct low-level access to the internal access tick (GetTickCount64 shr 10)
    // - may be nil if TimeOutSeconds=0
    property TimeOut: TCardinalDynArray read fTimeOut;
    /// returns the aTimeOutSeconds parameter value, as specified to Create()
    property TimeOutSeconds: cardinal read GetTimeOutSeconds;
    /// the compression algorithm used for binary serialization
    property CompressAlgo: TAlgoCompress read fCompressAlgo write fCompressAlgo;
    /// callback to by-pass DeleteDeprecated deletion by returning false
    // - can be assigned e.g. to OnCanDeleteSynPersistentLock if Value is a
    // TSynPersistentLock instance, to avoid any potential access violation
    property OnCanDeleteDeprecated: TSynDictionaryCanDeleteEvent read fOnCanDelete write fOnCanDelete;
  end;

implementation

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------


// 17023 -----------------------------------------------------------------------

{ TSynTempBuffer }

procedure TSynTempBuffer.Init(Source: pointer; SourceLen: PtrInt);
begin
  len := SourceLen;
  if len<=0 then
    buf := nil else begin
    if len<=SizeOf(tmp)-16 then
      buf := @tmp else
      GetMem(buf,len+16); // +16 for trailing #0 and for PInteger() parsing
    if Source<>nil then begin
      MoveFast(Source^,buf^,len);
      PPtrInt(PAnsiChar(buf)+len)^ := 0; // init last 4/8 bytes (makes valgrid happy)
    end;
  end;
end;

function TSynTempBuffer.InitOnStack: pointer;
begin
  buf := @tmp;
  len := SizeOf(tmp);
  result := @tmp;
end;

procedure TSynTempBuffer.Init(const Source: RawByteString);
begin
  Init(pointer(Source),length(Source));
end;

function TSynTempBuffer.Init(Source: PUTF8Char): PUTF8Char;
begin
  Init(Source,StrLen(Source));
  result := buf;
end;

function TSynTempBuffer.Init(SourceLen: PtrInt): pointer;
begin
  len := SourceLen;
  if len<=0 then
    buf := nil else begin
    if len<=SizeOf(tmp)-16 then
      buf := @tmp else
      GetMem(buf,len+16); // +16 for trailing #0 and for PInteger() parsing
  end;
  result := buf;
end;

function TSynTempBuffer.Init: integer;
begin
  buf := @tmp;
  result := SizeOf(tmp)-16;
  len := result;
end;

function TSynTempBuffer.InitRandom(RandomLen: integer; forcegsl: boolean): pointer;
begin
  Init(RandomLen);
  if RandomLen>0 then
    FillRandom(buf,(RandomLen shr 2)+1,forcegsl);
  result := buf;
end;

function TSynTempBuffer.InitIncreasing(Count, Start: PtrInt): PIntegerArray;
begin
  Init((Count-Start)*4);
  FillIncreasing(buf,Start,Count);
  result := buf;
end;

function TSynTempBuffer.InitZero(ZeroLen: PtrInt): pointer;
begin
  Init(ZeroLen-16);
  FillCharFast(buf^,ZeroLen,0);
  result := buf;
end;

procedure TSynTempBuffer.Done;
begin
  if (buf<>@tmp) and (buf<>nil) then
    FreeMem(buf);
end;

procedure TSynTempBuffer.Done(EndBuf: pointer; var Dest: RawUTF8);
begin
  if EndBuf=nil then
    Dest := '' else
    FastSetString(Dest,buf,PAnsiChar(EndBuf)-PAnsiChar(buf));
  if (buf<>@tmp) and (buf<>nil) then
    FreeMem(buf);
end;


// 21269 -----------------------------------------------------------------------

{$ifdef HASCODEPAGE}
procedure FastSetStringCP(var s; p: pointer; len, codepage: PtrInt);
var r: pointer;
begin
  r := FastNewString(len,codepage);
  if p<>nil then
    MoveFast(p^,r^,len);
  FastAssignNew(s,r);
end;

procedure FastSetString(var s: RawUTF8; p: pointer; len: PtrInt);
var r: pointer;
begin
  r := FastNewString(len,CP_UTF8);
  if p<>nil then
    MoveFast(p^,r^,len);
  FastAssignNew(s,r);
end;
{$else not HASCODEPAGE}
procedure FastSetStringCP(var s; p: pointer; len, codepage: PtrInt);
begin
  SetString(RawByteString(s),PAnsiChar(p),len);
end;
procedure FastSetString(var s: RawUTF8; p: pointer; len: PtrInt);
begin
  SetString(RawByteString(s),PAnsiChar(p),len);
end;
{$endif HASCODEPAGE}


// 24875 -----------------------------------------------------------------------

function StrLenPas(S: pointer): PtrInt;
label
  _0, _1, _2, _3; // ugly but faster
begin
  result := PtrUInt(S);
  if S<>nil then begin
    while true do
      if PAnsiChar(result)[0]=#0 then
        goto _0
      else if PAnsiChar(result)[1]=#0 then
        goto _1
      else if PAnsiChar(result)[2]=#0 then
        goto _2
      else if PAnsiChar(result)[3]=#0 then
        goto _3
      else
        inc(result, 4);
_3: inc(result);
_2: inc(result);
_1: inc(result);
_0: dec(result,PtrUInt(S)); // return length
  end;
end;

// 31866 ----------------------------------------------------------------------

procedure FillIncreasing(Values: PIntegerArray; StartValue: integer; Count: PtrUInt);
var i: PtrUInt;
begin
  if Count>0 then
    if StartValue=0 then
      for i := 0 to Count-1 do
        Values[i] := i else
      for i := 0 to Count-1 do begin
        Values[i] := StartValue;
        inc(StartValue);
      end;
end;

//------------------------------------------------------------------------------


end.
