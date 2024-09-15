unit BpDictionary;

{$I Synopse.inc}

interface

uses
{$ifdef MSWINDOWS}
  Windows,
  Messages,
{$else MSWINDOWS}
  {$ifdef KYLIX3}
    Types,
    LibC,
    SynKylix,
  {$endif KYLIX3}
  {$ifdef FPC}
    BaseUnix,
  {$endif FPC}
{$endif MSWINDOWS}
  Classes,
{$ifndef LVCL}
  SyncObjs, // for TEvent and TCriticalSection
  Contnrs,  // for TObjectList
  {$ifdef HASINLINE}
    Types,
  {$endif HASINLINE}
{$endif LVCL}
{$ifndef NOVARIANTS}
  Variants,
{$endif NOVARIANTS}
//  SynLZ, // needed for TSynMapFile .mab format
  SysUtils;

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

  /// RawJSON will indicate that this variable content would stay in raw JSON
  // - i.e. won't be serialized into values
  // - could be any JSON content: number, string, object or array
  // - e.g. interface-based service will use it for efficient and AJAX-ready
  // transmission of TSQLTableJSON result
//  RawJSON = type RawUTF8;

  /// SynUnicode is the fastest available Unicode native string type, depending
  //  on the compiler used
  // - this type is native to the compiler, so you can use Length() Copy() and
  //   such functions with it (this is not possible with RawUnicodeString type)
  // - before Delphi 2009+, it uses slow OLE compatible WideString
  //   (with our Enhanced RTL, WideString allocation can be made faster by using
  //   an internal caching mechanism of allocation buffers - WideString allocation
  //   has been made much faster since Windows Vista/Seven)
  // - starting with Delphi 2009, it uses fastest UnicodeString type, which
  //   allow Copy On Write, Reference Counting and fast heap memory allocation
  {$ifdef HASVARUSTRING}
  SynUnicode = UnicodeString;
  {$else}
  SynUnicode = WideString;
  {$endif HASVARUSTRING}  

//------------------------------------------------------------------------------

  /// a simple wrapper to UTF-8 encoded zero-terminated PAnsiChar
  // - PAnsiChar is used only for Win-Ansi encoded text
  // - the Synopse mORMot framework uses mostly this PUTF8Char type,
  // because all data is internaly stored and expected to be UTF-8 encoded
  PUTF8Char = type PAnsiChar;
  PPUTF8Char = ^PUTF8Char;

// 396 -------------------------------------------------------------------------

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
  {$ifndef ISDELPHI2007ANDUP}
  TBytes = array of byte;
  {$endif}
  TObjectDynArray = array of TObject;
  PObjectDynArray = ^TObjectDynArray;
  TPersistentDynArray = array of TPersistent;
  PPersistentDynArray = ^TPersistentDynArray;
  TPointerDynArray = array of pointer;
  PPointerDynArray = ^TPointerDynArray;
  TPPointerDynArray = array of PPointer;
  PPPointerDynArray = ^TPPointerDynArray;
  TMethodDynArray = array of TMethod;
  PMethodDynArray = ^TMethodDynArray;
  TObjectListDynArray = array of TObjectList;
  PObjectListDynArray = ^TObjectListDynArray;
  TFileNameDynArray = array of TFileName;
  PFileNameDynArray = ^TFileNameDynArray;
  TBooleanDynArray = array of boolean;
  PBooleanDynArray = ^TBooleanDynArray;
  TClassDynArray = array of TClass;
  TWinAnsiDynArray = array of WinAnsiString;
  PWinAnsiDynArray = ^TWinAnsiDynArray;
  TRawByteStringDynArray = array of RawByteString;
  TStringDynArray = array of string;
  PStringDynArray = ^TStringDynArray;
  PShortStringDynArray = array of PShortString;
  PPShortStringArray = ^PShortStringArray;
  TShortStringDynArray = array of ShortString;
  TDateTimeDynArray = array of TDateTime;
  PDateTimeDynArray = ^TDateTimeDynArray;
  {$ifndef FPC_OR_UNICODE}
  TDate = type TDateTime;
  TTime = type TDateTime;
  {$endif FPC_OR_UNICODE}
  TDateDynArray = array of TDate;
  PDateDynArray = ^TDateDynArray;
  TTimeDynArray = array of TTime;
  PTimeDynArray = ^TTimeDynArray;
  TWideStringDynArray = array of WideString;
  PWideStringDynArray = ^TWideStringDynArray;
  TSynUnicodeDynArray = array of SynUnicode;
  PSynUnicodeDynArray = ^TSynUnicodeDynArray;
  TGUIDDynArray = array of TGUID;

  PObject = ^TObject;
  PClass = ^TClass;
  PByteArray = ^TByteArray;
  TByteArray = array[0..MaxInt-1] of Byte; // redefine here with {$R-}
  PBooleanArray = ^TBooleanArray;
  TBooleanArray = array[0..MaxInt-1] of Boolean;
  TWordArray  = array[0..MaxInt div SizeOf(word)-1] of word;
  PWordArray = ^TWordArray;
  TIntegerArray = array[0..MaxInt div SizeOf(integer)-1] of integer;
  PIntegerArray = ^TIntegerArray;
  PIntegerArrayDynArray = array of PIntegerArray;
  TPIntegerArray = array[0..MaxInt div SizeOf(PIntegerArray)-1] of PInteger;
  PPIntegerArray = ^TPIntegerArray;
  TCardinalArray = array[0..MaxInt div SizeOf(cardinal)-1] of cardinal;
  PCardinalArray = ^TCardinalArray;
  TInt64Array = array[0..MaxInt div SizeOf(Int64)-1] of Int64;
  PInt64Array = ^TInt64Array;
  TQWordArray = array[0..MaxInt div SizeOf(QWord)-1] of QWord;
  PQWordArray = ^TQWordArray;
  TPtrUIntArray = array[0..MaxInt div SizeOf(PtrUInt)-1] of PtrUInt;
  PPtrUIntArray = ^TPtrUIntArray;
  TSmallIntArray = array[0..MaxInt div SizeOf(SmallInt)-1] of SmallInt;
  PSmallIntArray = ^TSmallIntArray;
  TSingleArray = array[0..MaxInt div SizeOf(Single)-1] of Single;
  PSingleArray = ^TSingleArray;
  TDoubleArray = array[0..MaxInt div SizeOf(Double)-1] of Double;
  PDoubleArray = ^TDoubleArray;
  TDateTimeArray = array[0..MaxInt div SizeOf(TDateTime)-1] of TDateTime;
  PDateTimeArray = ^TDateTimeArray;
  TPAnsiCharArray = array[0..MaxInt div SizeOf(PAnsiChar)-1] of PAnsiChar;
  PPAnsiCharArray = ^TPAnsiCharArray;
  TRawUTF8Array = array[0..MaxInt div SizeOf(RawUTF8)-1] of RawUTF8;
  PRawUTF8Array = ^TRawUTF8Array;
  TRawByteStringArray = array[0..MaxInt div SizeOf(RawByteString)-1] of RawByteString;
  PRawByteStringArray = ^TRawByteStringArray;
  PShortStringArray = array[0..MaxInt div SizeOf(pointer)-1] of PShortString;
  PointerArray = array [0..MaxInt div SizeOf(Pointer)-1] of Pointer;
  PPointerArray = ^PointerArray;
  TObjectArray = array [0..MaxInt div SizeOf(TObject)-1] of TObject;
  PObjectArray = ^TObjectArray;
  TPtrIntArray = array[0..MaxInt div SizeOf(PtrInt)-1] of PtrInt;
  PPtrIntArray = ^TPtrIntArray;
  PInt64Rec = ^Int64Rec;
  PPShortString = ^PShortString;

  {$ifndef DELPHI5OROLDER}
  PIInterface = ^IInterface;
  TInterfaceDynArray = array of IInterface;
  PInterfaceDynArray = ^TInterfaceDynArray;
  {$endif}  

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

// 4783 ------------------------------------------------------------------------

/// convert a cardinal into a 32-bit variable-length integer buffer
function ToVarUInt32(Value: cardinal; Dest: PByte): PByte;

// 4791 ------------------------------------------------------------------------

/// return the number of bytes necessary to store some data with a its
// 32-bit variable-length integer legnth
function ToVarUInt32LengthWithData(Value: PtrUInt): PtrUInt;
  {$ifdef HASINLINE}inline;{$endif}

// 4930 ------------------------------------------------------------------------
type
  /// specify ordinal (tkInteger and tkEnumeration) storage size and sign
  // - note: Int64 is stored as its own TTypeKind, not as tkInteger
  TOrdType = (otSByte,otUByte,otSWord,otUWord,otSLong,otULong
    {$ifdef FPC_NEWRTTI},otSQWord,otUQWord{$endif});

  /// specify floating point (ftFloat) storage size and precision
  // - here ftDouble is renamed ftDoub to avoid confusion with TSQLDBFieldType
  TFloatType = (ftSingle,ftDoub,ftExtended,ftComp,ftCurr);

// 4991 ------------------------------------------------------------------------

  /// available type families for Delphi 6 and up, similar to typinfo.pas
  // - redefined here to be shared between SynCommons.pas and mORMot.pas,
  // also leveraging FPC compatibility as much as possible (FPC's typinfo.pp
  // is not convenient to share code with Delphi - see e.g. its tkLString)
  TTypeKind = (tkUnknown, tkInteger, tkChar, tkEnumeration, tkFloat,
    tkString, tkSet, tkClass, tkMethod, tkWChar, tkLString, tkWString,
    tkVariant, tkArray, tkRecord, tkInterface, tkInt64, tkDynArray
    {$ifdef UNICODE}, tkUString, tkClassRef, tkPointer, tkProcedure{$endif});

const
  /// maps record or object in TTypeKind RTTI enumerate
  tkRecordTypes = [tkRecord];
  /// maps record or object in TTypeKind RTTI enumerate
  tkRecordKinds = tkRecord;    

// 5021 ------------------------------------------------------------------------

type
  PTypeKind = ^TTypeKind;
  TTypeKinds = set of TTypeKind;

// 5038 ------------------------------------------------------------------------

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

  /// internal set to specify some standard Delphi arrays
  TDynArrayKinds = set of TDynArrayKind;

  /// cross-compiler type used for string reference counter
  // - FPC and Delphi don't always use the same type
  TStrCnt = {$ifdef STRCNT32} longint {$else} SizeInt {$endif};
  /// pointer to cross-compiler type used for string reference counter
  PStrCnt = ^TStrCnt;

  /// cross-compiler type used for dynarray reference counter
  // - FPC uses PtrInt/SizeInt, Delphi uses longint even on CPU64
  TDACnt = {$ifdef DACNT32} longint {$else} SizeInt {$endif};
  /// pointer to cross-compiler type used for dynarray reference counter
  PDACnt = ^TDACnt;

  /// internal integer type used for string header length field
  TStrLen = {$ifdef FPC}SizeInt{$else}longint{$endif};
  /// internal pointer integer type used for string header length field
  PStrLen = ^TStrLen;

  /// internal pointer integer type used for dynamic array header length field
  PDALen = PPtrInt;


// 5110-------------------------------------------------------------------------

const
  /// cross-compiler negative offset to TStrRec.length field
  // - to be used inlined e.g. as PStrLen(p-_STRLEN)^
  _STRLEN = SizeOf(TStrLen);
  /// cross-compiler negative offset to TStrRec.refCnt field
  // - to be used inlined e.g. as PStrCnt(p-_STRREFCNT)^
  _STRREFCNT = Sizeof(TStrCnt)+_STRLEN;

  /// cross-compiler negative offset to TDynArrayRec.high/length field
  // - to be used inlined e.g. as PDALen(PtrUInt(Values)-_DALEN)^{$ifdef FPC}+1{$endif}
  _DALEN = SizeOf(PtrInt);
  /// cross-compiler negative offset to TDynArrayRec.refCnt field
  // - to be used inlined e.g. as PDACnt(PtrUInt(Values)-_DAREFCNT)^
  _DAREFCNT = Sizeof(TDACnt)+_DALEN;

// 5299 ------------------------------------------------------------------------

type

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

// 7414 ------------------------------------------------------------------------

/// save a record content into a RawByteString
// - will handle packed records, with binaries (byte, word, integer...) and
// string types properties (but not with internal raw pointers, of course)
// - will use a proprietary binary format, with some variable-length encoding
// of the string length - note that if you change the type definition, any
// previously-serialized content will fail, maybe triggering unexpected GPF: you
// may use TypeInfoToHash() if you share this binary data accross executables
// - warning: will encode generic string fields as AnsiString (one byte per char)
// prior to Delphi 2009, and as UnicodeString (two bytes per char) since Delphi
// 2009: if you want to use this function between UNICODE and NOT UNICODE
// versions of Delphi, you should use some explicit types like RawUTF8,
// WinAnsiString, SynUnicode or even RawUnicode/WideString
function RecordSave(const Rec; TypeInfo: pointer): RawByteString; overload;

/// save a record content into a TBytes dynamic array
// - could be used as an alternative to RawByteString's RecordSave()
function RecordSaveBytes(const Rec; TypeInfo: pointer): TBytes;

/// save a record content into a destination memory buffer
// - Dest must be at least RecordSaveLength() bytes long
// - will return the Rec size, in bytes, into Len reference variable
// - will handle packed records, with binaries (byte, word, integer...) and
// string types properties (but not with internal raw pointers, of course)
// - will use a proprietary binary format, with some variable-length encoding
// of the string length - note that if you change the type definition, any
// previously-serialized content will fail, maybe triggering unexpected GPF: you
// may use TypeInfoToHash() if you share this binary data accross executables
// - warning: will encode generic string fields as AnsiString (one byte per char)
// prior to Delphi 2009, and as UnicodeString (two bytes per char) since Delphi
// 2009: if you want to use this function between UNICODE and NOT UNICODE
// versions of Delphi, you should use some explicit types like RawUTF8,
// WinAnsiString, SynUnicode or even RawUnicode/WideString
function RecordSave(const Rec; Dest: PAnsiChar; TypeInfo: pointer;
  out Len: integer): PAnsiChar; overload;

/// save a record content into a destination memory buffer
// - Dest must be at least RecordSaveLength() bytes long
// - will handle packed records, with binaries (byte, word, integer...) and
// string types properties (but not with internal raw pointers, of course)
// - will use a proprietary binary format, with some variable-length encoding
// of the string length - note that if you change the type definition, any
// previously-serialized content will fail, maybe triggering unexpected GPF: you
// may use TypeInfoToHash() if you share this binary data accross executables
// - warning: will encode generic string fields as AnsiString (one byte per char)
// prior to Delphi 2009, and as UnicodeString (two bytes per char) since Delphi
// 2009: if you want to use this function between UNICODE and NOT UNICODE
// versions of Delphi, you should use some explicit types like RawUTF8,
// WinAnsiString, SynUnicode or even RawUnicode/WideString
function RecordSave(const Rec; Dest: PAnsiChar; TypeInfo: pointer): PAnsiChar; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// save a record content into a destination memory buffer
// - caller should make Dest.Done once finished with Dest.buf/Dest.len buffer
procedure RecordSave(const Rec; var Dest: TSynTempBuffer; TypeInfo: pointer); overload;

// 7473 ------------------------------------------------------------------------

/// compute the number of bytes needed to save a record content
// using the RecordSave() function
// - will return 0 in case of an invalid (not handled) record type (e.g. if
// it contains an unknown variant)
// - optional Len parameter will contain the Rec memory buffer length, in bytes
function RecordSaveLength(const Rec; TypeInfo: pointer; Len: PInteger=nil): integer;

// 7541 ------------------------------------------------------------------------

/// clear a record content
// - this unit includes a fast optimized asm version for x86 on Delphi
procedure RecordClear(var Dest; TypeInfo: pointer); {$ifdef FPC}inline;{$endif}

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

// 11030 -----------------------------------------------------------------------

  {$M+}
  /// generic parent class of all custom Exception types of this unit
  // - all our classes inheriting from ESynException are serializable,
  // so you could use ObjectToJSONDebug(anyESynException) to retrieve some
  // extended information
  ESynException = class(Exception)
  protected
    fRaisedAt: pointer;
  public
    /// constructor which will use FormatUTF8() instead of Format()
    // - expect % as delimiter, so is less error prone than %s %d %g
    // - will handle vtPointer/vtClass/vtObject/vtVariant kind of arguments,
    // appending class name for any class or object, the hexa value for a
    // pointer, or the JSON representation of any supplied TDocVariant
    constructor CreateUTF8(const Format: RawUTF8; const Args: array of const);
    /// constructor appending some FormatUTF8() content to the GetLastError
    // - message will contain GetLastError value followed by the formatted text
    // - expect % as delimiter, so is less error prone than %s %d %g
    // - will handle vtPointer/vtClass/vtObject/vtVariant kind of arguments,
    // appending class name for any class or object, the hexa value for a
    // pointer, or the JSON representation of any supplied TDocVariant
    constructor CreateLastOSError(const Format: RawUTF8; const Args: array of const;
      const Trailer: RawUtf8 = 'OSError');
    {$ifndef NOEXCEPTIONINTERCEPT}
    /// can be used to customize how the exception is logged
    // - this default implementation will call the DefaultSynLogExceptionToStr()
    // function or the TSynLogExceptionToStrCustom global callback, if defined
    // - override this method to provide a custom logging content
    // - should return TRUE if Context.EAddr and Stack trace is not to be
    // written (i.e. as for any TSynLogExceptionToStr callback)
//TODO: FIX    function CustomLog(WR: TTextWriter; const Context: TSynLogExceptionContext): boolean; virtual;
    {$endif}
    /// the code location when this exception was triggered
    // - populated by SynLog unit, during interception - so may be nil
    // - you can use TSynMapFile.FindLocation(ESynException) class function to
    // guess the corresponding source code line
    // - will be serialized as "Address": hexadecimal and source code location
    // (using TSynMapFile .map/.mab information) in TJSONSerializer.WriteObject
    // when woStorePointer option is defined - e.g. with ObjectToJSONDebug()
    property RaisedAt: pointer read fRaisedAt write fRaisedAt;
  published
    property Message;
  end;
  {$M-}
  ESynExceptionClass = class of ESynException;

// 12169 -----------------------------------------------------------------------

var
  /// compute CRC32C checksum on the supplied buffer
  // - result is not compatible with zlib's crc32() - Intel/SCSI CRC32C is not
  // the same polynom - but will use the fastest mean available, e.g. SSE 4.2,
  // to achieve up to 16GB/s with the optimized implementation from SynCrypto.pas
  // - you should use this function instead of crc32cfast() or crc32csse42()
  crc32c: THasher;


// 13859 -----------------------------------------------------------------------

const
  /// unsigned 64bit integer variant type
  // - currently called varUInt64 in Delphi (not defined in older versions),
  // and varQWord in FPC
  varWord64 = 21;

// 13878 -----------------------------------------------------------------------

/// same as Dest := TVarData(Source) for simple values
// - will return TRUE for all simple values after varByRef unreference, and
// copying the unreferenced Source value into Dest raw storage
// - will return FALSE for not varByRef values, or complex values (e.g. string)
function SetVariantUnRefSimpleValue(const Source: variant; var Dest: TVarData): boolean;
  {$ifdef HASINLINE}inline;{$endif}

// 14070 -----------------------------------------------------------------------

/// compute the number of bytes needed to save a Variant content
// using the VariantSave() function
// - will return 0 in case of an invalid (not handled) Variant type
function VariantSaveLength(const Value: variant): integer;

/// save a Variant content into a destination memory buffer
// - Dest must be at least VariantSaveLength() bytes long
// - will handle standard Variant types and custom types (serialized as JSON)
// - will return nil in case of an invalid (not handled) Variant type
// - will use a proprietary binary format, with some variable-length encoding
// of the string length
// - warning: will encode generic string fields as within the variant type
// itself: using this function between UNICODE and NOT UNICODE
// versions of Delphi, will propably fail - you have been warned!
function VariantSave(const Value: variant; Dest: PAnsiChar): PAnsiChar; overload;

/// save a Variant content into a binary buffer
// - will handle standard Variant types and custom types (serialized as JSON)
// - will return '' in case of an invalid (not handled) Variant type
// - just a wrapper around VariantSaveLength()+VariantSave()
// - warning: will encode generic string fields as within the variant type
// itself: using this function between UNICODE and NOT UNICODE
// versions of Delphi, will propably fail - you have been warned!
function VariantSave(const Value: variant): RawByteString; overload;

// 16947  
implementation

//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------


// 17007 -----------------------------------------------------------------------

procedure MoveSmall(Source, Dest: Pointer; Count: PtrUInt);
var c: AnsiChar; // better FPC inlining
begin
  inc(PtrUInt(Source),Count);
  inc(PtrUInt(Dest),Count);
  PtrInt(Count) := -PtrInt(Count);
  repeat
    c := PAnsiChar(Source)[Count];
    PAnsiChar(Dest)[Count] := c;
    inc(Count);
  until Count=0;
end;

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

// 20204 -----------------------------------------------------------------------

procedure ExchgVariant(v1,v2: PPtrIntArray); {$ifdef CPU64}inline;{$endif}
var c: PtrInt; // 32-bit:16bytes=4ptr 64-bit:24bytes=3ptr
begin
  c := v2[0];
  v2[0] := v1[0];
  v1[0] := c;
  c := v2[1];
  v2[1] := v1[1];
  v1[1] := c;
  c := v2[2];
  v2[2] := v1[2];
  v1[2] := c;
  {$ifdef CPU32}
  c := v2[3];
  v2[3] := v1[3];
  v1[3] := c;
  {$endif}
end;

{$ifdef CPU64}
procedure Exchg16(P1,P2: PPtrIntArray); inline;
var c: PtrInt;
begin
  c := P1[0];
  P1[0] := P2[0];
  P2[0] := c;
  c := P1[1];
  P1[1] := P2[1];
  P2[1] := c;
end;
{$endif}

procedure Exchg(P1,P2: PAnsiChar; count: PtrInt);
  {$ifdef PUREPASCAL} {$ifdef HASINLINE}inline;{$endif}
var i, c: PtrInt;
    u: AnsiChar;
begin
  for i := 1 to count shr POINTERSHR do begin
    c := PPtrInt(P1)^;
    PPtrInt(P1)^ := PPtrInt(P2)^;
    PPtrInt(P2)^ := c;
    inc(P1,SizeOf(c));
    inc(P2,SizeOf(c));
  end;
  for i := 0 to (count and POINTERAND)-1 do begin
    u := P1[i];
    P1[i] := P2[i];
    P2[i] := u;
  end;
end;
{$else} {$ifdef FPC} nostackframe; assembler; {$endif}
asm // eax=P1, edx=P2, ecx=count
        push    ebx
        push    esi
        push    ecx
        shr     ecx, 2
        jz      @2
@4:     mov     ebx, [eax]
        mov     esi, [edx]
        mov     [eax], esi
        mov     [edx], ebx
        add     eax, 4
        add     edx, 4
        dec     ecx
        jnz     @4
@2:     pop     ecx
        and     ecx, 3
        jz      @0
@1:     mov     bl, [eax]
        mov     bh, [edx]
        mov     [eax], bh
        mov     [edx], bl
        inc     eax
        inc     edx
        dec     ecx
        jnz     @1
@0:     pop     esi
        pop     ebx
end;
{$endif}


// 20523 -----------------------------------------------------------------------
type
  PTypeInfo = ^TTypeInfo;
  {$ifdef HASDIRECTTYPEINFO} // for old FPC (<=3.0)
  PTypeInfoStored = PTypeInfo;
  {$else} // e.g. for Delphi and newer FPC
  PTypeInfoStored = ^PTypeInfo; // = TypeInfoPtr macro in FPC typinfo.pp
  {$endif}

  // note: FPC TRecInitData is taken from typinfo.pp via SynFPCTypInfo
  // since this information is evolving/breaking a lot in the current FPC trunk

  /// map the Delphi/FPC record field RTTI
  TFieldInfo =
    {$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
    packed
    {$endif FPC_REQUIRES_PROPER_ALIGNMENT}
    record
    TypeInfo: PTypeInfoStored;
    {$ifdef FPC}
    Offset: sizeint;
    {$else}
    Offset: PtrUInt;
    {$endif FPC}
  end;
  PFieldInfo = ^TFieldInfo;  

// 20568 -----------------------------------------------------------------------

  TTypeInfo =
    {$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
    packed
    {$endif FPC_REQUIRES_PROPER_ALIGNMENT}
    record
    kind: TTypeKind;
    NameLen: byte;
    case TTypeKind of
    tkUnknown: (
      NameFirst: AnsiChar;
    );
    tkDynArray: (
      {$ifdef FPC}
      elSize: SizeUInt; // and $7FFFFFFF = item/record size
      elType2: PTypeInfoStored;
      varType: LongInt;
      elType: PTypeInfoStored;
      //DynUnitName: ShortStringBase;
      {$else}
      // storage byte count for this field
      elSize: Longint;
      // nil for unmanaged field
      elType: PTypeInfoStored;
      // OleAuto compatible type
      varType: Integer;
      // also unmanaged field
      elType2: PTypeInfoStored;
      {$endif FPC}
    );
    tkArray: (
      {$ifdef FPC}
      // warning: in VER2_6, this is the element size, not full array size
      arraySize: SizeInt;
      // product of lengths of all dimensions
      elCount: SizeInt;
      {$else}
      arraySize: Integer;
      // product of lengths of all dimensions
      elCount: Integer;
      {$endif FPC}
      arrayType: PTypeInfoStored;
      dimCount: Byte;
      dims: array[0..255 {DimCount-1}] of PTypeInfoStored;
    );
    {$ifdef FPC}
    tkRecord, tkObject:(
      {$ifdef FPC_NEWRTTI}
      RecInitInfo: Pointer; // call GetManagedFields() to use FPC's TypInfo.pp
      recSize: longint;
      {$else}
      ManagedCount: longint;
      ManagedFields: array[0..0] of TFieldInfo;
      // note: FPC for 3.0.x and previous generates RTTI for unmanaged fields (as in TEnhancedFieldInfo)
      {$endif FPC_NEWRTTI}
    {$else}
    tkRecord: (
      recSize: cardinal;
      ManagedCount: integer;
      ManagedFields: array[0..0] of TFieldInfo;
    {$ifdef ISDELPHI2010} // enhanced RTTI containing info about all fields
      NumOps: Byte;
      //RecOps: array[0..0] of Pointer;
      AllCount: Integer; // !!!! may need $RTTI EXPLICIT FIELDS([vcPublic])
      AllFields: array[0..0] of TEnhancedFieldInfo;
    {$endif ISDELPHI2010}
    {$endif FPC}
    );
    tkEnumeration: (
      EnumType: TOrdType;
      {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
      EnumDummy: DWORD; // needed on ARM for correct alignment
      {$endif}
      {$ifdef FPC_ENUMHASINNER} inner:
      {$ifndef FPC_REQUIRES_PROPER_ALIGNMENT} packed {$endif} record
      {$endif FPC_ENUMHASINNER}
      MinValue: longint;
      MaxValue: longint;
      EnumBaseType: PTypeInfoStored; // BaseTypeRef in FPC TypInfo.pp
      {$ifdef FPC_ENUMHASINNER} end; {$endif FPC_ENUMHASINNER}
      NameList: string[255];
    );
    tkInteger: (
      IntegerType: TOrdType;
    );
    tkInt64: (
      MinInt64Value, MaxInt64Value: Int64;
    );
    tkSet: (
      SetType: TOrdType;
      {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
      SetDummy: DWORD; // needed on ARM for correct alignment
      {$endif}
      {$ifdef FPC}
      {$ifndef VER3_0}
      SetSize: SizeInt;
      {$endif VER3_0}
      {$endif FPC}
      SetBaseType: PTypeInfoStored; // CompTypeRef in FPC TypInfo.pp
    );
    tkFloat: (
      FloatType: TFloatType;
    );
    tkClass: (
      ClassType: TClass;
      ParentInfo: PTypeInfoStored; // ParentInfoRef in FPC TypInfo.pp
      PropCount: SmallInt;
      UnitNameLen: byte;
    );
  end;

// 20704 -----------------------------------------------------------------------

{$ifdef HASDIRECTTYPEINFO}
type
  Deref = PTypeInfo;
{$else}
function Deref(Info: PTypeInfoStored): PTypeInfo; // for Delphi and newer FPC
{$ifdef HASINLINE} inline;
begin
  result := pointer(Info);
  if Info<>nil then
    result := Info^;
end;
{$else}
asm // Delphi is so bad at compiling above code...
        or      eax, eax
        jz      @z
        mov     eax, [eax]
        ret
@z:     db      $f3 // rep ret
end;
{$endif HASINLINE}
{$endif HASDIRECTTYPEINFO}

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


// 21376 -----------------------------------------------------------------------

function GetTypeInfo(aTypeInfo: pointer; aExpectedKind: TTypeKind): PTypeInfo; overload;
{$ifdef HASINLINE} inline;
begin
  result := aTypeInfo;
  if result<>nil then
    if result^.Kind=aExpectedKind then
      {$ifdef HASALIGNTYPEDATA}
      result := FPCTypeInfoOverName(result)
      {$else}
      inc(PByte(result),result^.NameLen)
      {$endif}
    else
      result := nil;
end;
{$else}
asm
        test    eax, eax
        jz      @n
        movzx   ecx, byte ptr[eax + TTypeInfo.NameLen]
        cmp     dl, [eax]
        jne     @n
        add     eax, ecx
        ret
@n:     xor     eax, eax
end;
{$endif HASINLINE}

function GetTypeInfo(aTypeInfo: pointer; const aExpectedKind: TTypeKinds): PTypeInfo; overload;
{$ifdef HASINLINE} inline;
begin
  result := aTypeInfo;
  if result<>nil then
    if result^.Kind in aExpectedKind then
      {$ifdef HASALIGNTYPEDATA}
      result := FPCTypeInfoOverName(result)
      {$else}
      inc(PByte(result),result^.NameLen)
      {$endif}
    else
      result := nil;
end;
{$else}
asm // eax=aTypeInfo edx=aExpectedKind
        test    eax, eax
        jz      @n
        movzx   ecx, byte ptr[eax]
        bt      edx, ecx
        movzx   ecx, byte ptr[eax + TTypeInfo.NameLen]
        jnb     @n
        add     eax, ecx
        ret
@n:     xor     eax, eax
end;
{$endif HASINLINE}

function GetTypeInfo(aTypeInfo: pointer): PTypeInfo; overload;
{$ifdef HASINLINE} inline;
begin
  {$ifdef HASALIGNTYPEDATA}
  result := FPCTypeInfoOverName(aTypeInfo);
  {$else}
  result := @PAnsiChar(aTypeInfo)[PTypeInfo(aTypeInfo)^.NameLen];
  {$endif}
end;
{$else}
asm
        movzx   ecx, byte ptr[eax + TTypeInfo.NameLen]
        add     eax, ecx
end;
{$endif HASINLINE}

// 21470 -----------------------------------------------------------------------

function TypeInfoToShortString(aTypeInfo: pointer): PShortString;
begin
  if aTypeInfo<>nil then
    result := @PTypeInfo(aTypeInfo)^.NameLen else
    result := nil;
end;

// 21971 -----------------------------------------------------------------------

{ note: those low-level VariantTo*() functions are expected to be there
        even if NOVARIANTS conditional is defined (used e.g. by SynDB.TQuery) }

function SetVariantUnRefSimpleValue(const Source: variant; var Dest: TVarData): boolean;
var typ: cardinal;
begin
  result := false;
  typ := TVarData(Source).VType;
  if typ and varByRef=0 then
    exit;
  typ := typ and not varByRef;
  case typ of
  varVariant:
    if integer(PVarData(TVarData(Source).VPointer)^.VType) in
        [varEmpty..varDate,varBoolean,varShortInt..varWord64] then begin
      Dest := PVarData(TVarData(Source).VPointer)^;
      result := true;
    end;
  varEmpty..varDate,varBoolean,varShortInt..varWord64: begin
    Dest.VType := typ;
    Dest.VInt64 :=  PInt64(TVarData(Source).VAny)^;
    result := true;
  end;
  end;
end;

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

// 26398 -----------------------------------------------------------------------

function ToVarUInt32(Value: PtrUInt; Dest: PByte): PByte;
{$ifdef FPC} nostackframe; assembler; {$endif}
asm
        cmp     eax, $7f
        jbe     @0
        cmp     eax, $00004000
        jb      @1
        cmp     eax, $00200000
        jb      @2
        cmp     eax, $10000000
        jb      @3
        mov     ecx, eax
        shr     eax, 7
        and     cl, $7f
        or      cl, $80
        mov     [edx], cl
        inc     edx
@3:     mov     ecx, eax
        shr     eax, 7
        and     cl, $7f
        or      cl, $80
        mov     [edx], cl
        inc     edx
@2:     mov     ecx, eax
        shr     eax, 7
        and     cl, $7f
        or      cl, $80
        mov     [edx], cl
        inc     edx
@1:     mov     ecx, eax
        shr     eax, 7
        and     cl, $7f
        or      cl, $80
        mov     [edx], cl
        inc     edx
@0:     mov     [edx], al
        lea     eax, [edx + 1]
end;

// 31866 -----------------------------------------------------------------------

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

// 41477 -----------------------------------------------------------------------

function ToVarUInt32LengthWithData(Value: PtrUInt): PtrUInt;
begin
  if Value<=$7f then
    result := Value+1 else
  if Value<$80 shl 7 then
    result := Value+2 else
  if Value<$80 shl 14 then
    result := Value+3 else
  if Value<$80 shl 21 then
    result := Value+4 else
    result := Value+5;
end;

// 42060 -----------------------------------------------------------------------

procedure CopyArray(dest, source, typeInfo: Pointer; cnt: PtrUInt);
asm
{$ifdef CPU64}
        .noframe
        jmp     System.@CopyArray
{$else} push    dword ptr[EBP + 8]
        call    System.@CopyArray // RTL is fast enough for this
{$endif}
end;

procedure _DynArrayClear(var a: Pointer; typeInfo: Pointer);
asm
  {$ifdef CPU64}
  .noframe
  {$endif}
  jmp System.@DynArrayClear
end;

procedure _FinalizeArray(p: Pointer; typeInfo: Pointer; elemCount: PtrUInt);
asm
  {$ifdef CPU64}
  .noframe
  {$endif}
  jmp System.@FinalizeArray
end;

procedure _Finalize(Data: Pointer; TypeInfo: Pointer);
asm
{$ifdef CPU64}
        .noframe
        mov     r8, 1 // rcx=p rdx=typeInfo r8=ElemCount
        jmp     System.@FinalizeArray
{$else} // much faster than FinalizeArray(Data,TypeInfo,1)
        movzx   ecx, byte ptr[edx]  // eax=ptr edx=typeinfo ecx=datatype
        sub     cl, tkLString
        {$ifdef UNICODE}
        cmp     cl, tkUString - tkLString + 1
        {$else}
        cmp     cl, tkDynArray - tkLString + 1
        {$endif}
        jnb     @@err
        jmp     dword ptr[@@Tab + ecx * 4]
        nop
        nop // for @@Tab alignment
@@Tab:  dd      System.@LStrClr
{$IFDEF LINUX} // under Linux, WideString are refcounted as AnsiString
        dd      System.@LStrClr
{$else} dd      System.@WStrClr
{$endif LINUX}
{$ifdef LVCL}
        dd      @@err
{$else} dd      System.@VarClr
{$endif LVCL}
        dd      @@ARRAY
        dd      RecordClear
        dd      System.@IntfClear
        dd      @@err
        dd      System.@DynArrayClear
        {$ifdef UNICODE}
        dd      System.@UStrClr
        {$endif}
@@err:  mov     al, reInvalidPtr
        {$ifdef DELPHI5OROLDER}
        jmp     System.@RunError
        {$else}
        jmp     System.Error
        {$endif}
@@array:movzx   ecx, [edx].TTypeInfo.NameLen
        add     ecx, edx
        mov     edx, dword ptr[ecx].TTypeInfo.ManagedFields[0] // Fields[0].TypeInfo^
        mov     ecx, [ecx].TTypeInfo.ManagedCount
        mov     edx, [edx]
        jmp     System.@FinalizeArray
{$endif CPU64}
end;
//{$endif FPC}

// 42152 -----------------------------------------------------------------------

function ArrayItemType(var info: PTypeInfo; out len: integer): PTypeInfo;
  {$ifdef HASINLINE}inline;{$endif}
begin
  {$ifdef HASALIGNTYPEDATA} // inlined info := GetTypeInfo(info)
  info := FPCTypeInfoOverName(info);
  {$else}
  info := @PAnsiChar(info)[info^.NameLen];
  {$endif}
  result := nil;
  if (info=nil) or (info^.dimCount<>1) then begin
    len := 0;
    info := nil; // supports single dimension static array only
  end else begin
    len := info^.arraySize{$ifdef VER2_6}*info^.elCount{$endif};
    {$ifdef HASDIRECTTYPEINFO} // inlined result := DeRef(info^.arrayType)
    result := info^.arrayType;
    {$else}
    if info^.arrayType=nil then
      exit;
    result := info^.arrayType^;
    {$endif}
    {$ifdef FPC}
    if (result<>nil) and not(result^.Kind in tkManagedTypes) then
      result := nil; // as with Delphi
    {$endif}
  end;
end;

// 42243 -----------------------------------------------------------------------

function ManagedTypeSaveLength(data: PAnsiChar; info: PTypeInfo;
  out len: integer): integer;
// returns 0 on error, or saved bytes + len=data^ length
var DynArray: TDynArray;
    itemtype: PTypeInfo;
    itemsize,size,i: integer;
    P: PPtrUInt absolute data;
begin // info is expected to come from a DeRef() if retrieved from RTTI
  case info^.Kind of // should match tkManagedTypes
  tkLString{$ifdef FPC},tkLStringOld{$endif}: begin
    len := SizeOf(pointer);
    if P^=0 then
      result := 1 else
      result := ToVarUInt32LengthWithData(PStrLen(P^-_STRLEN)^);
  end;
  tkWString: begin // PStrRec doesn't match on Widestring for FPC
    len := SizeOf(pointer);
    result := ToVarUInt32LengthWithData(length(PWideString(P)^)*2);
  end;
  {$ifdef HASVARUSTRING}
  tkUString: begin
    len := SizeOf(pointer);
    if P^=0 then
      result := 1 else
      result := ToVarUInt32LengthWithData(PStrLen(P^-_STRLEN)^*2);
  end;
  {$endif}
  tkRecord{$ifdef FPC},tkObject{$endif}:
    result := RecordSaveLength(data^,info,@len);
  tkArray: begin
    itemtype := ArrayItemType(info,len);
    result := 0;
    if info<>nil then
      if itemtype=nil then
        result := len else
        for i := 1 to info^.elCount do begin
          size := ManagedTypeSaveLength(data,itemtype,itemsize);
          if size=0 then begin
            result := 0;
            exit;
          end;
          inc(result,size);
          inc(data,itemsize);
        end;
  end;
  {$ifndef NOVARIANTS}
  tkVariant: begin
    len := SizeOf(variant);
    result := VariantSaveLength(PVariant(data)^);
  end;
  {$endif}
  tkDynArray: begin
    DynArray.Init(info,data^);
    len := SizeOf(pointer);
    result := DynArray.SaveToLength;
  end;
  tkInterface: begin
    len := SizeOf(Int64); // consume 64-bit even on CPU32
    result := SizeOf(PtrUInt);
  end;
  else
    result := 0; // invalid/unhandled record content
  end;
end;

function ManagedTypeSave(data, dest: PAnsiChar; info: PTypeInfo;
  out len: integer): PAnsiChar;
// returns nil on error, or final dest + len=data^ length
var DynArray: TDynArray;
    itemtype: PTypeInfo;
    itemsize,i: integer;
    P: PPtrUInt absolute data;
begin // info is expected to come from a DeRef() if retrieved from RTTI
  case info^.Kind of
  tkLString {$ifdef HASVARUSTRING},tkUString{$endif} {$ifdef FPC},tkLStringOld{$endif}: begin
    if P^=0 then begin
      dest^ := #0;
      result := dest+1;
    end else begin
      itemsize := PStrLen(P^-_STRLEN)^;
      {$ifdef HASVARUSTRING} // UnicodeString length in WideChars
      if info^.Kind=tkUString then
        itemsize := itemsize*2;
      {$endif}
      result := pointer(ToVarUInt32(itemsize,pointer(dest)));
      MoveFast(pointer(P^)^,result^,itemsize);
      inc(result,itemsize);
    end;
    len := SizeOf(PtrUInt); // size of tkLString/tkUString in record
  end;
  tkWString: begin
    itemsize := length(PWideString(P)^)*2; // PStrRec doesn't match on FPC
    result := pointer(ToVarUInt32(itemsize,pointer(dest)));
    MoveFast(pointer(P^)^,result^,itemsize);
    inc(result,itemsize);
    len := SizeOf(PtrUInt);
  end;
  tkRecord{$ifdef FPC},tkObject{$endif}:
    result := RecordSave(data^,dest,info,len);
  tkArray: begin
    itemtype := ArrayItemType(info,len);
    if info=nil then
      result := nil else
      if itemtype=nil then begin
        MoveSmall(data,dest,len);
        result := dest+len;
      end else begin
        for i := 1 to info^.elCount do begin
          dest := ManagedTypeSave(data,dest,itemtype,itemsize);
          if dest=nil then
            break; // invalid/unhandled content
          inc(data,itemsize)
        end;
        result := dest;
      end;
  end;
  {$ifndef NOVARIANTS}
  tkVariant: begin
    result := VariantSave(PVariant(data)^,dest);
    len := SizeOf(Variant); // size of tkVariant in record
  end;
  {$endif}
  tkDynArray: begin
    DynArray.Init(info,data^);
    result := DynArray.SaveTo(dest);
    len := SizeOf(PtrUInt); // size of tkDynArray in record
  end;
  {$ifndef DELPHI5OROLDER}
  tkInterface: begin
    PIInterface(dest)^ := PIInterface(data)^; // with proper refcount
    result := dest+SizeOf(Int64); // consume 64-bit even on CPU32
    len := SizeOf(PtrUInt);
  end;
  {$endif}
  else
    result := nil; // invalid/unhandled record content
  end;
end;

// 42465 -----------------------------------------------------------------------

function GetManagedFields(info: PTypeInfo; out firstfield: PFieldInfo): integer;
{$ifdef HASINLINE}inline;{$endif}
{$ifdef FPC_NEWRTTI}
var
  recInitData: PFPCRecInitData; // low-level type redirected from SynFPCTypInfo
  aPointer:pointer;
begin
  if Assigned(info^.RecInitInfo) then
    recInitData := PFPCRecInitData(AlignTypeDataClean(PTypeInfo(info^.RecInitInfo+2+PByte(info^.RecInitInfo+1)^)))
  else begin
    aPointer:=@info^.RecInitInfo;
    {$ifdef FPC_PROVIDE_ATTR_TABLE}
    dec(PByte(aPointer),SizeOf(Pointer));
    {$ifdef FPC_REQUIRES_PROPER_ALIGNMENT}
    {$ifdef CPUARM}
    dec(PByte(aPointer),SizeOf(Pointer));
    {$endif CPUARM}
    {$endif}
    {$endif}
    recInitData := PFPCRecInitData(aPointer);
  end;
  firstfield := PFieldInfo(PtrUInt(@recInitData^.ManagedFieldCount));
  inc(PByte(firstfield),SizeOf(recInitData^.ManagedFieldCount));
  firstfield := AlignPTypeInfo(firstfield);
  result := recInitData^.ManagedFieldCount;
{$else}
begin
  firstfield := @info^.ManagedFields[0];
  result := info^.ManagedCount;
{$endif FPC_NEWRTTI}
end;

// 42547 -----------------------------------------------------------------------

function RecordSaveLength(const Rec; TypeInfo: pointer; Len: PInteger): integer;
var info,fieldinfo: PTypeInfo;
    F, recsize,saved: integer;
    field: PFieldInfo;
    R: PAnsiChar;
begin
  R := @Rec;
  info := GetTypeInfo(TypeInfo,tkRecordKinds);
  if (R=nil) or (info=nil) then begin
    result := 0; // should have been checked before
    exit;
  end;
  result := info^.recSize;
  if Len<>nil then
    Len^ := result;
  for F := 1 to GetManagedFields(info,field) do begin
    fieldinfo := DeRef(field^.TypeInfo);
    {$ifdef FPC_OLDRTTI} // old FPC did include RTTI for unmanaged fields! :)
    if not (fieldinfo^.Kind in tkManagedTypes) then begin
      inc(field);
      continue; // as with Delphi
    end;
    {$endif};
    saved := ManagedTypeSaveLength(R+field^.Offset,fieldinfo,recsize);
    if saved=0 then begin
      result := 0; // invalid type
      exit;
    end;
    inc(result,saved-recsize); // extract recsize from info^.recSize
    inc(field);
  end;
end;

function RecordSave(const Rec; Dest: PAnsiChar; TypeInfo: pointer;
  out Len: integer): PAnsiChar;
var info,fieldinfo: PTypeInfo;
    F, offset: integer;
    field: PFieldInfo;
    R: PAnsiChar;
begin
  R := @Rec;
  info := GetTypeInfo(TypeInfo,tkRecordKinds);
  if (R=nil) or (info=nil) then begin
    result := nil; // should have been checked before
    exit;
  end;
  Len := info^.recSize;
  offset := 0;
  for F := 1 to GetManagedFields(info,field) do begin
    {$ifdef HASDIRECTTYPEINFO} // inlined DeRef()
    fieldinfo := field^.TypeInfo;
    {$else}
    {$ifdef CPUINTEL}
    fieldinfo := PPointer(field^.TypeInfo)^;
    {$else}
    fieldinfo := DeRef(field^.TypeInfo);
    {$endif}
    {$endif}
    {$ifdef FPC_OLDRTTI} // old FPC did include RTTI for unmanaged fields! :)
    if not (fieldinfo^.Kind in tkManagedTypes) then begin
      inc(field);
      continue; // as with Delphi
    end;
    {$endif};
    offset := integer(field^.Offset)-offset;
    if offset>0 then begin
      MoveFast(R^,Dest^,offset);
      inc(R,offset);
      inc(Dest,offset);
    end;
    Dest := ManagedTypeSave(R,Dest,fieldinfo,offset);
    if Dest=nil then begin
      result := nil; // invalid/unhandled record content
      exit;
    end;
    inc(R,offset);
    inc(offset,field.Offset);
    inc(field);
  end;
  offset := integer(info^.recSize)-offset;
  if offset<0 then
    raise ESynException.Create('RecordSave offset<0') else
  if offset<>0 then begin
    MoveFast(R^,Dest^,offset);
    result := Dest+offset;
  end else
    result := Dest;
end;

function RecordSave(const Rec; Dest: PAnsiChar; TypeInfo: pointer): PAnsiChar;
var dummylen: integer;
begin
  result := RecordSave(Rec,Dest,TypeInfo,dummylen);
end;

function RecordSave(const Rec; TypeInfo: pointer): RawByteString;
var destlen,dummylen: integer;
    dest: PAnsiChar;
begin
  destlen := RecordSaveLength(Rec,TypeInfo);
  SetString(result,nil,destlen);
  if destlen<>0 then begin
    dest := RecordSave(Rec,pointer(result),TypeInfo,dummylen);
    if (dest=nil) or (dest-pointer(result)<>destlen) then // paranoid check
      raise ESynException.CreateUTF8('RecordSave % len=%<>%',
        [TypeInfoToShortString(TypeInfo)^,dest-pointer(result),destlen]);
  end;
end;

function RecordSaveBytes(const Rec; TypeInfo: pointer): TBytes;
var destlen,dummylen: integer;
    dest: PAnsiChar;
begin
  destlen := RecordSaveLength(Rec,TypeInfo);
  result := nil; // don't reallocate TBytes data from a previous call
  SetLength(result,destlen);
  if destlen<>0 then begin
    dest := RecordSave(Rec,pointer(result),TypeInfo,dummylen);
    if (dest=nil) or (dest-pointer(result)<>destlen) then // paranoid check
      raise ESynException.CreateUTF8('RecordSave % len=%<>%',
        [TypeInfoToShortString(TypeInfo)^,dest-pointer(result),destlen]);
  end;
end;

procedure RecordSave(const Rec; var Dest: TSynTempBuffer; TypeInfo: pointer);
var dummylen: integer;
    P: PAnsiChar;
begin
  Dest.Init(RecordSaveLength(Rec,TypeInfo));
  P := RecordSave(Rec,Dest.buf,TypeInfo,dummylen);
  if (P=nil) or (P-Dest.buf<>Dest.len) then begin // paranoid check
    Dest.Done;
    raise ESynException.CreateUTF8('RecordSave TSynTempBuffer %',[TypeInfoToShortString(TypeInfo)^]);
  end;
end;

// 43887 -----------------------------------------------------------------------

function ManagedTypeSaveRTTIHash(info: PTypeInfo; var crc: cardinal): integer;
var itemtype: PTypeInfo;
    i, unmanagedsize: integer;
    field: PFieldInfo;
    dynarray: TDynArray;
begin // info is expected to come from a DeRef() if retrieved from RTTI
  result := 0;
  if info=nil then
    exit;
  {$ifdef FPC} // storage binary layout as Delphi's ordinal value
  crc := crc32c(crc,@FPCTODELPHI[info^.Kind],1);
  {$else}
  crc := crc32c(crc,@info^.Kind,1); // hash RTTI kind, but not name
  {$endif}
  case info^.Kind of // handle nested RTTI
  tkLString,{$ifdef FPC}tkLStringOld,{$endif}{$ifdef HASVARUSTRING}tkUString,{$endif}
  tkWString,tkInterface:
    result := SizeOf(pointer);
  {$ifndef NOVARIANTS}
  tkVariant:
    result := SizeOf(variant);
  {$endif}
  tkRecord{$ifdef FPC},tkObject{$endif}: // first search from custom RTTI text
  //TODO: FIX!!!  if not GlobalJSONCustomParsers.RecordRTTITextHash(info,crc,result) then
  begin
      itemtype := GetTypeInfo(info,tkRecordKinds);
      if itemtype<>nil then begin
        unmanagedsize := itemtype^.recsize;
        for i := 1 to GetManagedFields(itemtype,field) do begin
          info := DeRef(field^.TypeInfo);
          {$ifdef FPC_OLDRTTI} // old FPC did include RTTI for unmanaged fields
          if info^.Kind in tkManagedTypes then // as with Delphi
          {$endif}
            dec(unmanagedsize,ManagedTypeSaveRTTIHash(info,crc));
          inc(field);
        end;
        crc := crc32c(crc,@unmanagedsize,4);
        result := itemtype^.recSize;
      end;
  end;
  tkArray: begin
    itemtype := ArrayItemType(info,result);
    if info=nil then
      exit;
    unmanagedsize := result;
    if itemtype<>nil then
      for i := 1 to info^.elCount do
        dec(unmanagedsize,ManagedTypeSaveRTTIHash(itemtype,crc));
    crc := crc32c(crc,@unmanagedsize,4);
  end;
  tkDynArray: begin
    dynarray.Init(info,field); // fake void array pointer
    crc := dynarray.SaveToTypeInfoHash(crc);
    result := SizeOf(pointer);
  end;
  end;
end;

// 45685 -----------------------------------------------------------------------

function VariantSaveLength(const Value: variant): integer;
var tmp: TVarData;
    v: TVarData absolute Value;
begin // match VariantSave() storage
  if v.VType and varByRef<>0 then
    if v.VType=varVariant or varByRef then begin
      result := VariantSaveLength(PVariant(v.VPointer)^);
      exit;
    end else
    if SetVariantUnRefSimpleValue(Value,tmp) then begin
      result := VariantSaveLength(variant(tmp));
      exit;
    end;
  case v.VType of
  varEmpty, varNull:
    result := SizeOf(tmp.VType);
  varShortInt, varByte:
    result := SizeOf(tmp.VByte)+SizeOf(tmp.VType);
  varSmallint, varWord, varBoolean:
    result := SizeOf(tmp.VSmallint)+SizeOf(tmp.VType);
  varSingle, varLongWord, varInteger:
    result := SizeOf(tmp.VInteger)+SizeOf(tmp.VType);
  varInt64, varWord64, varDouble, varDate, varCurrency:
    result := SizeOf(tmp.VInt64)+SizeOf(tmp.VType);
  varString, varOleStr:
    if PtrUInt(v.VAny)=0 then
      result := 1+SizeOf(tmp.VType) else
      result := ToVarUInt32LengthWithData(
        PStrLen(PtrUInt(v.VAny)-_STRLEN)^)+SizeOf(tmp.VType);
  {$ifdef HASVARUSTRING}
  varUString:
    if PtrUInt(v.VAny)=0 then // stored length is in bytes, not (wide)chars
      result := 1+SizeOf(tmp.VType) else
      result := ToVarUInt32LengthWithData(
        PStrLen(PtrUInt(v.VAny)-_STRLEN)^*2)+SizeOf(tmp.VType);
  {$endif}
  else
    try // complex types will be stored as JSON
// TODO: FIX result := ToVarUInt32LengthWithData(VariantSaveJSONLength(Value))+SizeOf(tmp.VType);
    except
      on Exception do
        result := 0; // notify invalid/unhandled variant content
    end;
  end;
end;

// 49672 -----------------------------------------------------------------------

{ TDynArray }

function TDynArray.GetCount: PtrInt;
begin
  result := PtrUInt(fCountP);
  if result<>0 then
    result := PInteger(result)^ else begin
    result := PtrUInt(fValue);
    if result<>0 then begin
      result := PPtrInt(result)^;
      if result<>0 then
        result := PDALen(result-_DALEN)^{$ifdef FPC}+1{$endif};
    end;
  end;
end;

procedure TDynArray.ElemCopy(const A; var B);
begin
  if ElemType=nil then
    MoveFast(A,B,ElemSize) else begin
    {$ifdef FPC}
    {$ifdef FPC_OLDRTTI}
    FPCFinalize(@B,ElemType); // inlined CopyArray()
    Move(A,B,ElemSize);
    FPCRecordAddRef(B,ElemType);
    {$else}
    FPCRecordCopy(A,B,ElemType); // works for any kind of ElemTyp
    {$endif FPC_OLDRTTI}
    {$else}
    CopyArray(@B,@A,ElemType,1);
    {$endif FPC}
  end;
end;

function TDynArray.Add(const Elem): PtrInt;
var p: PtrUInt;
begin
  result := GetCount;
  if fValue=nil then
    exit; // avoid GPF if void
  SetCount(result+1);
  p := PtrUInt(fValue^)+PtrUInt(result)*ElemSize;
  if ElemType=nil then
    MoveFast(Elem,pointer(p)^,ElemSize) else
    {$ifdef FPC}
    FPCRecordCopy(Elem,pointer(p)^,ElemType);
    {$else}
    CopyArray(pointer(p),@Elem,ElemType,1);
    {$endif}
end;

function TDynArray.New: integer;
begin
  result := GetCount;
  if fValue=nil then
    exit; // avoid GPF if void
  SetCount(result+1);
end;

function TDynArray.Peek(var Dest): boolean;
var index: PtrInt;
begin
  index := GetCount-1;
  result := index>=0;
  if result then
    ElemCopy(pointer(PtrUInt(fValue^)+PtrUInt(index)*ElemSize)^,Dest);
end;

function TDynArray.Pop(var Dest): boolean;
var index: integer;
begin
  index := GetCount-1;
  result := index>=0;
  if result then begin
    ElemMoveTo(index,Dest);
    SetCount(index);
  end;
end;

procedure TDynArray.Insert(Index: PtrInt; const Elem);
var n: PtrInt;
    P: PByteArray;
begin
  if fValue=nil then
    exit; // avoid GPF if void
  n := GetCount;
  SetCount(n+1);
  if PtrUInt(Index)<PtrUInt(n) then begin
    P := pointer(PtrUInt(fValue^)+PtrUInt(Index)*ElemSize);
    MoveFast(P[0],P[ElemSize],PtrUInt(n-Index)*ElemSize);
    if ElemType<>nil then // avoid GPF in ElemCopy() below
      FillCharFast(P^,ElemSize,0);
  end else
    // Index>=Count -> add at the end
    P := pointer(PtrUInt(fValue^)+PtrUInt(n)*ElemSize);
  ElemCopy(Elem,P^);
end;

procedure TDynArray.Clear;
begin
  SetCount(0);
end;

function TDynArray.ClearSafe: boolean;
begin
  try
    SetCount(0);
    result := true;
  except // weak code, but may be a good idea in a destructor
    result := false;
  end;
end;

function TDynArray.GetIsObjArray: boolean;
begin
  result := (fIsObjArray=oaTrue) or ((fIsObjArray=oaUnknown) and ComputeIsObjArray);
end;

function TDynArray.Delete(aIndex: PtrInt): boolean;
var n, len: PtrInt;
    P: PAnsiChar;
begin
  result := false;
  if fValue=nil then
    exit; // avoid GPF if void
  n := GetCount;
  if PtrUInt(aIndex)>=PtrUInt(n) then
    exit; // out of range
  if PDACnt(PtrUInt(fValue^)-_DAREFCNT)^>1 then
    InternalSetLength(n,n); // unique
  dec(n);
  P := pointer(PtrUInt(fValue^)+PtrUInt(aIndex)*ElemSize);
  if ElemType<>nil then
    {$ifdef FPC}FPCFinalize{$else}_Finalize{$endif}(P,ElemType) else
    if (fIsObjArray=oaTrue) or ((fIsObjArray=oaUnknown) and ComputeIsObjArray) then
      FreeAndNil(PObject(P)^);
  if n>aIndex then begin
    len := PtrUInt(n-aIndex)*ElemSize;
    MoveFast(P[ElemSize],P[0],len);
    FillCharFast(P[len],ElemSize,0);
  end else
    FillCharFast(P^,ElemSize,0);
  SetCount(n);
  result := true;
end;

function TDynArray.ElemPtr(index: PtrInt): pointer;
var c: PtrUInt;
begin // no goto/label, because it does not properly inline on modern Delphi
  result := pointer(fValue);
  if result=nil then
    exit;
  result := PPointer(result)^;
  if result=nil then
    exit;
  c := PtrUInt(fCountP);
  if c<>0 then
    if PtrUInt(index)<PCardinal(c)^ then
      inc(PByte(result),PtrUInt(index)*ElemSize) else
      result := nil
  else
    {$ifdef FPC}
    if PtrUInt(index)<=PPtrUInt(PtrUInt(result)-_DALEN)^ then
    {$else}
    if PtrUInt(index)<PPtrUInt(PtrUInt(result)-_DALEN)^ then
    {$endif FPC}
      inc(PByte(result),PtrUInt(index)*ElemSize) else
      result := nil;
end;

procedure TDynArray.ElemCopyAt(index: PtrInt; var Dest);
var p: pointer;
begin
  p := ElemPtr(index);
  if p<>nil then
    if ElemType=nil then
      MoveFast(p^,Dest,ElemSize) else
      {$ifdef FPC}
      FPCRecordCopy(p^,Dest,ElemType); // works for any kind of ElemTyp
      {$else}
      CopyArray(@Dest,p,ElemType,1);
      {$endif}
end;

procedure TDynArray.ElemMoveTo(index: PtrInt; var Dest);
var p: pointer;
begin
  p := ElemPtr(index);
  if (p=nil) or (@Dest=nil) then
    exit;
  ElemClear(Dest);
  MoveFast(p^,Dest,ElemSize);
  FillCharFast(p^,ElemSize,0); // ElemType=nil for ObjArray
end;

procedure TDynArray.ElemCopyFrom(const Source; index: PtrInt; ClearBeforeCopy: boolean);
var p: pointer;
begin
  p := ElemPtr(index);
  if p<>nil then
    if ElemType=nil then
      MoveFast(Source,p^,ElemSize) else begin
      if ClearBeforeCopy then // safer if Source is a copy of p^
        {$ifdef FPC}FPCFinalize{$else}_Finalize{$endif}(p,ElemType);
      {$ifdef FPC}
      FPCRecordCopy(Source,p^,ElemType);
      {$else}
      CopyArray(p,@Source,ElemType,1);
      {$endif}
    end;
end;

procedure TDynArray.Reverse;
var n, siz: PtrInt;
    P1, P2: PAnsiChar;
    c: AnsiChar;
    i32: integer;
    i64: Int64;
begin
  n := GetCount-1;
  if n>0 then begin
    siz := ElemSize;
    P1 := fValue^;
    case siz of
    1: begin // optimized version for TByteDynArray and such
      P2 := P1+n;
      while P1<P2 do begin
        c := P1^;
        P1^ := P2^;
        P2^ := c;
        inc(P1);
        dec(P2);
      end;
    end;
    4: begin // optimized version for TIntegerDynArray and such
      P2 := P1+n*SizeOf(Integer);
      while P1<P2 do begin
        i32 := PInteger(P1)^;
        PInteger(P1)^ := PInteger(P2)^;
        PInteger(P2)^ := i32;
        inc(P1,4);
        dec(P2,4);
      end;
    end;
    8: begin // optimized version for TInt64DynArray + TDoubleDynArray and such
      P2 := P1+n*SizeOf(Int64);
      while P1<P2 do begin
        i64 := PInt64(P1)^;
        PInt64(P1)^ := PInt64(P2)^;
        PInt64(P2)^ := i64;
        inc(P1,8);
        dec(P2,8);
      end;
    end;
    16: begin // optimized version for 32-bit TVariantDynArray and such
      P2 := P1+n*16;
      while P1<P2 do begin
        {$ifdef CPU64}Exchg16{$else}ExchgVariant{$endif}(Pointer(P1),Pointer(P2));
        inc(P1,16);
        dec(P2,16);
      end;
    end;
    {$ifdef CPU64}
    24: begin // optimized version for 64-bit TVariantDynArray and such
      P2 := P1+n*24;
      while P1<P2 do begin
        ExchgVariant(Pointer(P1),Pointer(P2));
        inc(P1,24);
        dec(P2,24);
      end;
    end;
    {$endif CPU64}
    else begin // generic version
      P2 := P1+n*siz;
      while P1<P2 do begin
        Exchg(P1,P2,siz);
        inc(P1,siz);
        dec(P2,siz);
      end;
    end;
    end;
  end;
end;

procedure TDynArray.SaveToStream(Stream: TStream);
var Posi, PosiEnd: Integer;
    MemStream: TCustomMemoryStream absolute Stream;
    tmp: RawByteString;
begin
  if (fValue=nil) or (Stream=nil) then
    exit; // avoid GPF if void
  if Stream.InheritsFrom(TCustomMemoryStream) then begin
    Posi := MemStream.Seek(0,soFromCurrent);
    PosiEnd := Posi+SaveToLength;
    if PosiEnd>MemStream.Size then
      MemStream.Size := PosiEnd;
    if SaveTo(PAnsiChar(MemStream.Memory)+Posi)-MemStream.Memory<>PosiEnd then
      raise EStreamError.Create('TDynArray.SaveToStream: SaveTo');
    MemStream.Seek(PosiEnd,soBeginning);
  end else begin
    tmp := SaveTo;
    if Stream.Write(pointer(tmp)^,length(tmp))<>length(tmp) then
      raise EStreamError.Create('TDynArray.SaveToStream: Write error');
  end;
end;

procedure TDynArray.LoadFromStream(Stream: TCustomMemoryStream);
var P: PAnsiChar;
begin
  P := PAnsiChar(Stream.Memory)+Stream.Seek(0,soCurrent);
  Stream.Seek(LoadFrom(P,nil,false,PAnsiChar(Stream.Memory)+Stream.Size)-P,soCurrent);
end;

function TDynArray.SaveToTypeInfoHash(crc: cardinal): cardinal;
begin
  if ElemType=nil then // hash fElemSize only if no pointer within
    result := crc32c(crc,@fElemSize,4) else begin
    result := crc;
    ManagedTypeSaveRTTIHash(ElemType,result);
  end;
end;

function TDynArray.SaveTo(Dest: PAnsiChar): PAnsiChar;
var i, n, LenBytes: integer;
    P: PAnsiChar;
begin
  if fValue=nil then begin
    result := Dest;
    exit; // avoid GPF if void
  end;
  // store the element size+type to check for the format (name='' mostly)
  Dest := PAnsiChar(ToVarUInt32(ElemSize,pointer(Dest)));
  if ElemType=nil then
    Dest^ := #0 else
    {$ifdef FPC}
    Dest^ := AnsiChar(FPCTODELPHI[PTypeKind(ElemType)^]);
    {$else}
    Dest^ := PAnsiChar(ElemType)^;
    {$endif}
  inc(Dest);
  // store dynamic array count
  n := GetCount;
  Dest := PAnsiChar(ToVarUInt32(n,pointer(Dest)));
  if n=0 then begin
    result := Dest;
    exit;
  end;
  inc(Dest,SizeOf(Cardinal)); // leave space for Hash32 checksum
  result := Dest;
  // store dynamic array elements content
  P := fValue^;
  if ElemType=nil then // FPC: nil also if not Kind in tkManagedTypes
    if GetIsObjArray then
      raise ESynException.CreateUTF8('TDynArray.SaveTo(%) is a T*ObjArray',
        [ArrayTypeShort^]) else begin
      n := n*integer(ElemSize); // binary types: store as one
      MoveFast(P^,Dest^,n);
      inc(Dest,n);
    end else
    if PTypeKind(ElemType)^ in tkRecordTypes then
      for i := 1 to n do begin
        Dest := RecordSave(P^,Dest,ElemType,LenBytes);
        inc(P,LenBytes);
      end else
      for i := 1 to n do begin
        Dest := ManagedTypeSave(P,Dest,ElemType,LenBytes);
        if Dest=nil then
          break;
        inc(P,LenBytes);
      end;
  // store Hash32 checksum
  if Dest<>nil then  // may be nil if RecordSave/ManagedTypeSave failed
    PCardinal(result-SizeOf(Cardinal))^ := Hash32(pointer(result),Dest-result);
  result := Dest;
end;

function TDynArray.SaveToLength: integer;
var i,n,L,size: integer;
    P: PAnsiChar;
begin
  if fValue=nil then begin
    result := 0;
    exit; // avoid GPF if void
  end;
  n := GetCount;
  result := ToVarUInt32Length(ElemSize)+ToVarUInt32Length(n)+1;
  if n=0 then
    exit;
  if ElemType=nil then // FPC: nil also if not Kind in tkManagedTypes
    if GetIsObjArray then
      raise ESynException.CreateUTF8('TDynArray.SaveToLength(%) is a T*ObjArray',
        [ArrayTypeShort^]) else
      inc(result,integer(ElemSize)*n) else begin
    P := fValue^;
    case PTypeKind(ElemType)^ of // inlined the most used kind of items
    tkLString{$ifdef FPC},tkLStringOld{$endif}:
      for i := 1 to n do begin
        if PPtrUInt(P)^=0 then
          inc(result) else
          inc(result,ToVarUInt32LengthWithData(PStrLen(PPtrUInt(P)^-_STRLEN)^));
        inc(P,SizeOf(pointer));
      end;
    tkRecord{$ifdef FPC},tkObject{$endif}:
      for i := 1 to n do begin
        inc(result,RecordSaveLength(P^,ElemType));
        inc(P,ElemSize);
      end;
    else
      for i := 1 to n do begin
        L := ManagedTypeSaveLength(P,ElemType,size);
        if L=0 then
          break; // invalid record type (wrong field type)
        inc(result,L);
        inc(P,size);
      end;
    end;
  end;
  inc(result,SizeOf(Cardinal)); // Hash32 checksum
end;

function TDynArray.SaveTo: RawByteString;
var Len: integer;
begin
  Len := SaveToLength;
  SetString(result,nil,Len);
  if Len<>0 then
    if SaveTo(pointer(result))-pointer(result)<>Len then
      raise ESynException.Create('TDynArray.SaveTo len concern');
end;

//------------------------------------------------------------------------------

{function TDynArray.SaveToJSON(EnumSetsAsText: boolean; reformat: TTextWriterJSONFormat): RawUTF8;
begin
  SaveToJSON(result,EnumSetsAsText,reformat);
end;

procedure TDynArray.SaveToJSON(out Result: RawUTF8; EnumSetsAsText: boolean;
  reformat: TTextWriterJSONFormat);
var temp: TTextWriterStackBuffer;
begin
  with DefaultTextWriterSerializer.CreateOwnedStream(temp) do
  try
    if EnumSetsAsText then
      CustomOptions := CustomOptions+[twoEnumSetsAsTextInRecord];
    AddDynArrayJSON(self);
    SetText(result,reformat);
  finally
    Free;
  end;
end;}

//------------------------------------------------------------------------------

const
  PTRSIZ = SizeOf(Pointer);
  KNOWNTYPE_SIZE: array[TDynArrayKind] of byte = (
    0, 1,1, 2, 4,4,4, 8,8,8,8,8,8,8, PTRSIZ,PTRSIZ,PTRSIZ,PTRSIZ,PTRSIZ,PTRSIZ,
    16,32,64, PTRSIZ,
    {$ifndef NOVARIANTS}SizeOf(Variant),{$endif} 0);
  DYNARRAY_PARSERUNKNOWN = -2;

var // for TDynArray.LoadKnownType
  KINDTYPE_INFO: array[TDynArrayKind] of pointer;

function TDynArray.GetArrayTypeName: RawUTF8;
begin
  TypeInfoToName(fTypeInfo,result);
end;

function TDynArray.GetArrayTypeShort: PShortString;
begin // not inlined since PTypeInfo is private to implementation section
  if fTypeInfo=nil then
    result := @NULCHAR else
    result := PShortString(@PTypeInfo(fTypeInfo).NameLen);
end;

function TDynArray.GuessKnownType(exactType: boolean): TDynArrayKind;
const
  RTTI: array[TJSONCustomParserRTTIType] of TDynArrayKind = (
    djNone, djBoolean, djByte, djCardinal, djCurrency, djDouble, djNone, djInt64,
    djInteger, djQWord, djRawByteString, djNone, djRawUTF8, djNone, djSingle,
    djString, djSynUnicode, djDateTime, djDateTimeMS, djHash128, djInt64, djTimeLog,
    {$ifdef HASVARUSTRING} {$ifdef UNICODE}djSynUnicode{$else}djNone{$endif}, {$endif}
    {$ifndef NOVARIANTS} djVariant, {$endif} djWideString, djWord, djNone);
var info: PTypeInfo;
    field: PFieldInfo;
label bin, rec;
begin
  result := fKnownType;
  if result<>djNone then
    exit;
  info := fTypeInfo;
  case ElemSize of // very fast guess of most known exact dynarray types
  1: if info=TypeInfo(TBooleanDynArray) then
       result := djBoolean;
  4: if info=TypeInfo(TCardinalDynArray) then
       result := djCardinal else
     if info=TypeInfo(TSingleDynArray) then
       result := djSingle
  {$ifdef CPU64} ; 8: {$else} else {$endif}
    if info=TypeInfo(TRawUTF8DynArray) then
      result := djRawUTF8 else
    if info=TypeInfo(TStringDynArray) then
      result := djString else
    if info=TypeInfo(TWinAnsiDynArray) then
      result := djWinAnsi else
    if info=TypeInfo(TRawByteStringDynArray) then
      result := djRawByteString else
    if info=TypeInfo(TSynUnicodeDynArray) then
      result := djSynUnicode else
    if (info=TypeInfo(TClassDynArray)) or
       (info=TypeInfo(TPointerDynArray)) then
      result := djPointer else
    {$ifndef DELPHI5OROLDER}
    if info=TypeInfo(TInterfaceDynArray) then
      result := djInterface
    {$endif DELPHI5OROLDER}
  {$ifdef CPU64} else {$else} ; 8: {$endif}
     if info=TypeInfo(TDoubleDynArray) then
       result := djDouble else
     if info=TypeInfo(TCurrencyDynArray) then
       result := djCurrency else
     if info=TypeInfo(TTimeLogDynArray) then
       result := djTimeLog else
     if info=TypeInfo(TDateTimeDynArray) then
       result := djDateTime else
     if info=TypeInfo(TDateTimeMSDynArray) then
       result := djDateTimeMS;
  end;
  if result=djNone then begin // guess from RTTU
    fKnownSize := 0;
    if fElemType=nil then begin
      {$ifdef DYNARRAYELEMTYPE2} // not backward compatible - disabled
      if fElemType2<>nil then // try if a simple type known by extended RTTI
        result := RTTI[TJSONCustomParserRTTI.TypeInfoToSimpleRTTIType(fElemType2)];
      if result=djNone then
      {$endif}
bin:  case fElemSize of
      1: result := djByte;
      2: result := djWord;
      4: result := djInteger;
      8: result := djInt64;
      16: result := djHash128;
      32: result := djHash256;
      64: result := djHash512;
      else fKnownSize := fElemSize;
      end;
    end else // try to guess from 1st record/object field
    if not exacttype and (PTypeKind(fElemType)^ in tkRecordTypes) then begin
      info := fElemType; // inlined GetTypeInfo()
rec:  {$ifdef HASALIGNTYPEDATA}
      info := FPCTypeInfoOverName(info);
      {$else}
      inc(PByte(info),info^.NameLen);
      {$endif}
      {$ifdef FPC_OLDRTTI}
      field := OldRTTIFirstManagedField(info);
      if field=nil then
      {$else}
      if GetManagedFields(info,field)=0 then // only binary content
      {$endif}
        goto Bin;
      case field^.Offset of
      0: begin
        info := DeRef(field^.TypeInfo);
        if info=nil then // paranoid check
          goto bin else
        if info^.kind in tkRecordTypes then
          goto rec; // nested records
        result := RTTI[TJSONCustomParserRTTI.TypeInfoToSimpleRTTIType(info)];
        if result=djNone then
          goto Bin;
      end;
      1:  result := djByte;
      2:  result := djWord;
      4:  result := djInteger;
      8:  result := djInt64;
      16: result := djHash128;
      32: result := djHash256;
      64: result := djHash512;
      else fKnownSize := field^.Offset;
      end;
    end else
    // will recognize simple arrays from PTypeKind(fElemType)^
    result := RTTI[TJSONCustomParserRTTI.TypeInfoToSimpleRTTIType(fElemType)];
  end;
  if KNOWNTYPE_SIZE[result]<>0 then
    fKnownSize := KNOWNTYPE_SIZE[result];
  fKnownType := result;
end;

function TDynArray.ElemCopyFirstField(Source,Dest: Pointer): boolean;
begin
  if fKnownType=djNone then
    GuessKnownType(false);
  case fKnownType of
  djBoolean..djDateTimeMS,djHash128..djHash512: // no managed field
    MoveFast(Source^,Dest^,fKnownSize);
  djRawUTF8, djWinAnsi, djRawByteString:
    PRawByteString(Dest)^ := PRawByteString(Source)^;
  djSynUnicode:
    PSynUnicode(Dest)^ := PSynUnicode(Source)^;
  djString:
    PString(Dest)^ := PString(Source)^;
  djWideString:
    PWideString(Dest)^ := PWideString(Source)^;
  {$ifndef NOVARIANTS}djVariant: PVariant(Dest)^ := PVariant(Source)^;{$endif}
  else begin // djNone, djInterface, djCustom
    result := false;
    exit;
  end;
  end;
  result := true;
end;

function TDynArray.LoadKnownType(Data,Source,SourceMax: PAnsiChar): boolean;
var info: PTypeInfo;
begin
  if fKnownType=djNone then
    GuessKnownType({exacttype=}false); // set fKnownType and fKnownSize
  if fKnownType in [djBoolean..djDateTimeMS,djHash128..djHash512] then
    if (SourceMax<>nil) and (Source+fKnownSize>SourceMax) then
      result := false else begin
      MoveFast(Source^,Data^,fKnownSize);
      result := true;
    end else begin
    info := KINDTYPE_INFO[fKnownType];
    if info=nil then
      result := false else
      result := (ManagedTypeLoad(Data,Source,info,SourceMax)<>0) and (Source<>nil);
  end;
end;


//------------------------------------------------------------------------------

(*
const // kind of types which are serialized as JSON text
  DJ_STRING = [djTimeLog..djHash512];

function TDynArray.LoadFromJSON(P: PUTF8Char; aEndOfObject: PUTF8Char{$ifndef NOVARIANTS};
  CustomVariantOptions: PDocVariantOptions{$endif}): PUTF8Char;
var n, i, ValLen: integer;
    T: TDynArrayKind;
    wasString, expectedString, isValid: boolean;
    EndOfObject: AnsiChar;
    Val: PUTF8Char;
    V: pointer;
    CustomReader: TDynArrayJSONCustomReader;
    NestedDynArray: TDynArray;
begin // code below must match TTextWriter.AddDynArrayJSON()
  result := nil;
  if (P=nil) or (fValue=nil) then
    exit;
  P := GotoNextNotSpace(P);
  if P^<>'[' then begin
    if (PInteger(P)^=NULL_LOW) and (jcEndOfJSONValueField in JSON_CHARS[P[4]]) then begin
      SetCount(0);
      result := P+4; // handle 'null' as void array
    end;
    exit;
  end;
  repeat inc(P) until not(P^ in [#1..' ']);
  n := JSONArrayCount(P);
  if n<0 then
    exit; // invalid array content
  if n=0 then begin
    if NextNotSpaceCharIs(P,']') then begin
      SetCount(0);
      result := P;
    end;
    exit; // handle '[]' array
  end;
  {$ifndef NOVARIANTS}
  if CustomVariantOptions=nil then
    CustomVariantOptions := @JSON_OPTIONS[true];
  {$endif}
  if HasCustomJSONParser then
    CustomReader := GlobalJSONCustomParsers.fParser[fParser].Reader else
    CustomReader := nil;
  if Assigned(CustomReader) then
    T := djCustom else
    T := GuessKnownType({exacttype=}true);
  if (T=djNone) and (P^='[') and (PTypeKind(ElemType)^=tkDynArray) then begin
    Count := n; // fast allocation of the whole dynamic array memory at once
    for i := 0 to n-1 do begin
      NestedDynArray.Init(ElemType,PPointerArray(fValue^)^[i]);
      P := NestedDynArray.LoadFromJSON(P,@EndOfObject{$ifndef NOVARIANTS},
        CustomVariantOptions{$endif});
      if P=nil then
        exit;
      EndOfObject := P^; // ',' or ']' for the last item of the array
      inc(P);
    end;
  end else
  if (T=djNone) or
     (PCardinal(P)^=JSON_BASE64_MAGIC_QUOTE) then begin
    if n<>1 then
      exit; // expect one Base64 encoded string value preceded by \uFFF0
    Val := GetJSONField(P,P,@wasString,@EndOfObject,@ValLen);
    if (Val=nil) or (ValLen<3) or not wasString or
       (PInteger(Val)^ and $00ffffff<>JSON_BASE64_MAGIC) or
       not LoadFromBinary(Base64ToBin(PAnsiChar(Val)+3,ValLen-3)) then
      exit; // invalid content
  end else begin
    if GetIsObjArray then
      for i := 0 to Count-1 do // force release any previous instance
        FreeAndNil(PObjectArray(fValue^)^[i]);
    SetCount(n); // fast allocation of the whole dynamic array memory at once
    case T of
    {$ifndef NOVARIANTS}
    djVariant:
      for i := 0 to n-1 do
        P := VariantLoadJSON(PVariantArray(fValue^)^[i],P,@EndOfObject,CustomVariantOptions);
    {$endif}
    djCustom: begin
      Val := fValue^;
      for i := 1 to n do begin
        P := CustomReader(P,Val^,isValid{$ifndef NOVARIANTS},CustomVariantOptions{$endif});
        if not isValid then
          exit;
        EndOfObject := P^; // ',' or ']' for the last item of the array
        inc(P);
        inc(Val,ElemSize);
      end;
    end;
    else begin
      V := fValue^;
      expectedString := T in DJ_STRING;
      for i := 0 to n-1 do begin
        Val := GetJSONField(P,P,@wasString,@EndOfObject,@ValLen);
        if (Val=nil) or (wasString<>expectedString) then
          exit;
        case T of
        djBoolean:  PBooleanArray(V)^[i] := GetBoolean(Val);
        djByte:     PByteArray(V)^[i] := GetCardinal(Val);
        djWord:     PWordArray(V)^[i] := GetCardinal(Val);
        djInteger:  PIntegerArray(V)^[i] := GetInteger(Val);
        djCardinal: PCardinalArray(V)^[i] := GetCardinal(Val);
        djSingle:   PSingleArray(V)^[i] := GetExtended(Val);
        djInt64:    SetInt64(Val,PInt64Array(V)^[i]);
        djQWord:    SetQWord(Val,PQWordArray(V)^[i]);
        djTimeLog:  PInt64Array(V)^[i] := Iso8601ToTimeLogPUTF8Char(Val,ValLen);
        djDateTime, djDateTimeMS:
          Iso8601ToDateTimePUTF8CharVar(Val,ValLen,PDateTimeArray(V)^[i]);
        djDouble:   PDoubleArray(V)^[i] := GetExtended(Val);
        djCurrency: PInt64Array(V)^[i] := StrToCurr64(Val);
        djRawUTF8:  FastSetString(PRawUTF8Array(V)^[i],Val,ValLen);
        djRawByteString:
          if not Base64MagicCheckAndDecode(Val,ValLen,PRawByteStringArray(V)^[i]) then
            FastSetString(PRawUTF8Array(V)^[i],Val,ValLen);
        djWinAnsi:  WinAnsiConvert.UTF8BufferToAnsi(Val,ValLen,PRawByteStringArray(V)^[i]);
        djString:   UTF8DecodeToString(Val,ValLen,string(PPointerArray(V)^[i]));
        djWideString: UTF8ToWideString(Val,ValLen,WideString(PPointerArray(V)^[i]));
        djSynUnicode: UTF8ToSynUnicode(Val,ValLen,SynUnicode(PPointerArray(V)^[i]));
        djHash128:  if ValLen<>SizeOf(THash128)*2 then FillZero(PHash128Array(V)^[i]) else
                      HexDisplayToBin(pointer(Val),@PHash128Array(V)^[i],SizeOf(THash128));
        djHash256:  if ValLen<>SizeOf(THash256)*2 then FillZero(PHash256Array(V)^[i]) else
                      HexDisplayToBin(pointer(Val),@PHash256Array(V)^[i],SizeOf(THash256));
        djHash512:  if ValLen<>SizeOf(THash512)*2 then FillZero(PHash512Array(V)^[i]) else
                      HexDisplayToBin(pointer(Val),@PHash512Array(V)^[i],SizeOf(THash512));
        else raise ESynException.CreateUTF8('% not readable',[ToText(T)^]);
        end;
      end;
    end;
    end;
  end;
  if aEndOfObject<>nil then
    aEndOfObject^ := EndOfObject;
  if EndOfObject=']' then
    if P=nil then
      result := @NULCHAR else
      result := P;
end;
*)

//------------------------------------------------------------------------------

{$ifndef NOVARIANTS}
function TDynArray.LoadFromVariant(const DocVariant: variant): boolean;
begin
  with _Safe(DocVariant)^ do
    if dvoIsArray in Options then
      result := LoadFromJSON(pointer(_Safe(DocVariant)^.ToJSON))<>nil else
      result := false;
end;
{$endif NOVARIANTS}

function TDynArray.LoadFromBinary(const Buffer: RawByteString;
  NoCheckHash: boolean): boolean;
var P: PAnsiChar;
    len: PtrInt;
begin
  len := length(Buffer);
  P := LoadFrom(pointer(Buffer),nil,NoCheckHash,PAnsiChar(pointer(Buffer))+len);
  result := (P<>nil) and (P-pointer(Buffer)=len);
end;

function TDynArray.LoadFromHeader(var Source: PByte; SourceMax: PByte): integer;
var n: cardinal;
begin
  // check context
  result := -1; // to notify error
  if (Source=nil) or (fValue=nil) then
    exit;
  // ignore legacy element size for cross-platform compatibility
  if not FromVarUInt32(Source,SourceMax,n) or // n=0 from mORMot 2 anyway
     ((SourceMax<>nil) and (PAnsiChar(Source)>=PAnsiChar(SourceMax))) then
    exit;
  // check stored element type
  if ElemType=nil then begin
    if Source^<>0 then
      exit;
  end else
    if Source^<>{$ifdef FPC}ord(FPCTODELPHI[PTypeKind(ElemType)^]){$else}
        PByte(ElemType)^{$endif} then
      exit;
  inc(Source);
  // retrieve dynamic array count
  if FromVarUInt32(Source,SourceMax,n) then
    if (n=0) or (SourceMax=nil) or
       (PAnsiChar(Source)+SizeOf(cardinal)<PAnsiChar(SourceMax)) then
      result := n;
end;

function TDynArray.LoadFrom(Source: PAnsiChar; AfterEach: TDynArrayAfterLoadFrom;
  NoCheckHash: boolean; SourceMax: PAnsiChar): PAnsiChar;
var i, n: integer;
    P: PAnsiChar;
    Hash: PCardinalArray;
begin
  // validate and unserialize binary header
  result := nil;
  SetCapacity(0); // clear current values, and reset growing factor
  n := LoadFromHeader(PByte(Source),PByte(SourceMax));
  if n<=0 then begin
    if n=0 then
      result := Source;
    exit;
  end;
  SetCount(n);
  // retrieve security checksum
  Hash := pointer(Source);
  inc(Source,SizeOf(cardinal));
  // retrieve dynamic array elements content
  P := fValue^;
  if ElemType=nil then // FPC: nil also if not Kind in tkManagedTypes
    if GetIsObjArray then
      raise ESynException.CreateUTF8('TDynArray.LoadFrom: % is a T*ObjArray',
        [ArrayTypeShort^]) else begin
      // binary type was stored directly
      n := n*integer(ElemSize);
      if (SourceMax<>nil) and (Source+n>SourceMax) then exit;
      MoveFast(Source^,P^,n);
      inc(Source,n);
    end else
    if PTypeKind(ElemType)^ in tkRecordTypes then
      for i := 1 to n do begin
        Source := RecordLoad(P^,Source,ElemType,nil,SourceMax);
        if Source=nil then exit;
        if Assigned(AfterEach) then
          AfterEach(P^);
        inc(P,ElemSize);
      end else
      for i := 1 to n do begin
        ManagedTypeLoad(P,Source,ElemType,SourceMax);
        if Source=nil then exit;
        if Assigned(AfterEach) then
          AfterEach(P^);
        inc(P,ElemSize);
      end;
  // check security checksum (Hash[0]=0 from mORMot2 DynArraySave)
  if NoCheckHash or (Source=nil) or (Hash[0]=0) or
     (Hash32(@Hash[1],Source-PAnsiChar(@Hash[1]))=Hash[0]) then
    result := Source;
end;

function TDynArray.Find(const Elem; const aIndex: TIntegerDynArray;
  aCompare: TDynArraySortCompare): PtrInt;
var n, L: PtrInt;
    cmp: integer;
    P: PAnsiChar;
begin
  n := GetCount;
  if (@aCompare<>nil) and (n>0) then begin
    dec(n);
    P := fValue^;
    if (n>10) and (length(aIndex)>=n) then begin
      // array should be sorted via aIndex[] -> use fast O(log(n)) binary search
      L := 0;
      repeat
        result := (L+n) shr 1;
        cmp := aCompare(P[cardinal(aIndex[result])*ElemSize],Elem);
        if cmp=0 then begin
          result := aIndex[result]; // returns index in TDynArray
          exit;
        end;
        if cmp<0 then
          L := result+1 else
          n := result-1;
      until L>n;
    end else
      // array is not sorted, or aIndex=nil -> use O(n) iterating search
      for result := 0 to n do
        if aCompare(P^,Elem)=0 then
          exit else
          inc(P,ElemSize);
  end;
  result := -1;
end;

function TDynArray.FindIndex(const Elem; aIndex: PIntegerDynArray;
  aCompare: TDynArraySortCompare): PtrInt;
begin
  if aIndex<>nil then
    result := Find(Elem,aIndex^,aCompare) else
  if Assigned(aCompare) then
    result := Find(Elem,nil,aCompare) else
    result := Find(Elem);
end;

function TDynArray.FindAndFill(var Elem; aIndex: PIntegerDynArray;
  aCompare: TDynArraySortCompare): integer;
begin
  result := FindIndex(Elem,aIndex,aCompare);
  if result>=0 then // if found, fill Elem with the matching item
    ElemCopy(PAnsiChar(fValue^)[cardinal(result)*ElemSize],Elem);
end;

function TDynArray.FindAndDelete(const Elem; aIndex: PIntegerDynArray;
  aCompare: TDynArraySortCompare): integer;
begin
  result := FindIndex(Elem,aIndex,aCompare);
  if result>=0 then
    Delete(result);
end;

function TDynArray.FindAndUpdate(const Elem; aIndex: PIntegerDynArray;
  aCompare: TDynArraySortCompare): integer;
begin
  result := FindIndex(Elem,aIndex,aCompare);
  if result>=0 then // if found, fill Elem with the matching item
    ElemCopy(Elem,PAnsiChar(fValue^)[cardinal(result)*ElemSize]);
end;

function TDynArray.FindAndAddIfNotExisting(const Elem; aIndex: PIntegerDynArray;
  aCompare: TDynArraySortCompare): integer;
begin
  result := FindIndex(Elem,aIndex,aCompare);
  if result<0 then
    Add(Elem); // -1 will mark success
end;

function TDynArray.Find(const Elem): PtrInt;
var n, L: PtrInt;
    cmp: integer;
    P: PAnsiChar;
begin
  n := GetCount;
  if (@fCompare<>nil) and (n>0) then begin
    dec(n);
    P := fValue^;
    if fSorted and (n>10) then begin
      // array is sorted -> use fast O(log(n)) binary search
      L := 0;
      repeat
        result := (L+n) shr 1;
        cmp := fCompare(P[cardinal(result)*ElemSize],Elem);
        if cmp=0 then
          exit;
        if cmp<0 then
          L := result+1 else
          n := result-1;
      until L>n;
    end else // array is very small, or not sorted
      for result := 0 to n do
        if fCompare(P^,Elem)=0 then // O(n) search
          exit else
          inc(P,ElemSize);
  end;
  result := -1;
end;

function TDynArray.FindAllSorted(const Elem; out FirstIndex,LastIndex: Integer): boolean;
var found,last: integer;
    P: PAnsiChar;
begin
  result := FastLocateSorted(Elem,found);
  if not result then
    exit;
  FirstIndex := found;
  P := fValue^;
  while (FirstIndex>0) and (fCompare(P[cardinal(FirstIndex-1)*ElemSize],Elem)=0) do
    dec(FirstIndex);
  last := GetCount-1;
  LastIndex := found;
  while (LastIndex<last) and (fCompare(P[cardinal(LastIndex+1)*ElemSize],Elem)=0) do
    inc(LastIndex);
end;

function TDynArray.FastLocateSorted(const Elem; out Index: Integer): boolean;
var n, i, cmp: integer;
    P: PAnsiChar;
begin
  result := False;
  n := GetCount;
  if @fCompare<>nil then
    if n=0 then // a void array is always sorted
      Index := 0 else
    if fSorted then begin
      P := fValue^;
      dec(n);
      cmp := fCompare(Elem,P[cardinal(n)*ElemSize]);
      if cmp>=0 then begin // greater than last sorted item
        Index := n;
        if cmp=0 then
          result := true else // returns true + index of existing Elem
          inc(Index); // returns false + insert after last position
        exit;
      end;
      Index := 0;
      while Index<=n do begin // O(log(n)) binary search of the sorted position
        i := (Index+n) shr 1;
        cmp := fCompare(P[cardinal(i)*ElemSize],Elem);
        if cmp=0 then begin
          Index := i; // returns true + index of existing Elem
          result := True;
          exit;
        end else
          if cmp<0 then
            Index := i+1 else
            n := i-1;
      end;
      // Elem not found: returns false + the index where to insert
    end else
      Index := -1 else // not Sorted
    Index := -1; // no fCompare()
end;

procedure TDynArray.FastAddSorted(Index: Integer; const Elem);
begin
  Insert(Index,Elem);
  fSorted := true; // Insert -> SetCount -> fSorted := false
end;

procedure TDynArray.FastDeleteSorted(Index: Integer);
begin
  Delete(Index);
  fSorted := true; // Delete -> SetCount -> fSorted := false
end;

function TDynArray.FastLocateOrAddSorted(const Elem; wasAdded: PBoolean): integer;
var toInsert: boolean;
begin
  toInsert := not FastLocateSorted(Elem,result) and (result>=0);
  if toInsert then begin
    Insert(result,Elem);
    fSorted := true; // Insert -> SetCount -> fSorted := false
  end;
  if wasAdded<>nil then
    wasAdded^ := toInsert;
end;

type
  // internal structure used to make QuickSort faster & with less stack usage
  TDynArrayQuickSort = object
    Compare: TDynArraySortCompare;
    CompareEvent: TEventDynArraySortCompare;
    Pivot: pointer;
    Index: PCardinalArray;
    ElemSize: cardinal;
    P: PtrInt;
    Value: PAnsiChar;
    IP, JP: PAnsiChar;
    procedure QuickSort(L, R: PtrInt);
    procedure QuickSortIndexed(L, R: PtrInt);
    procedure QuickSortEvent(L, R: PtrInt);
    procedure QuickSortEventReverse(L, R: PtrInt);
  end;

procedure QuickSortIndexedPUTF8Char(Values: PPUtf8CharArray; Count: Integer;
  var SortedIndexes: TCardinalDynArray; CaseSensitive: boolean);
var QS: TDynArrayQuickSort;
begin
  if CaseSensitive then
    QS.Compare := SortDynArrayPUTF8Char else
    QS.Compare := SortDynArrayPUTF8CharI;
  QS.Value := pointer(Values);
  QS.ElemSize := SizeOf(PUTF8Char);
  SetLength(SortedIndexes,Count);
  FillIncreasing(pointer(SortedIndexes),0,Count);
  QS.Index := pointer(SortedIndexes);
  QS.QuickSortIndexed(0,Count-1);
end;

procedure DynArraySortIndexed(Values: pointer; ElemSize, Count: Integer;
  out Indexes: TSynTempBuffer; Compare: TDynArraySortCompare);
var QS: TDynArrayQuickSort;
begin
  QS.Compare := Compare;
  QS.Value := Values;
  QS.ElemSize := ElemSize;
  QS.Index := pointer(Indexes.InitIncreasing(Count));
  QS.QuickSortIndexed(0,Count-1);
end;

procedure TDynArrayQuickSort.QuickSort(L, R: PtrInt);
var I, J: PtrInt;
    {$ifndef PUREPASCAL}tmp: pointer;{$endif}
begin
  if L<R then
  repeat
    I := L; J := R;
    P := (L + R) shr 1;
    repeat
      Pivot := Value+PtrUInt(P)*ElemSize;
      IP := Value+PtrUInt(I)*ElemSize;
      JP := Value+PtrUInt(J)*ElemSize;
      while Compare(IP^,Pivot^)<0 do begin
        inc(I);
        inc(IP,ElemSize);
      end;
      while Compare(JP^,Pivot^)>0 do begin
        dec(J);
        dec(JP,ElemSize);
      end;
      if I <= J then begin
        if I<>J then
          {$ifndef PUREPASCAL} // inlined Exchg() is just fine
          if ElemSize=SizeOf(pointer) then begin
            // optimized version e.g. for TRawUTF8DynArray/TObjectDynArray
            tmp := PPointer(IP)^;
            PPointer(IP)^ := PPointer(JP)^;
            PPointer(JP)^ := tmp;
          end else
          {$endif}
            // generic exchange of row element data
            Exchg(IP,JP,ElemSize);
        if P = I then P := J else
        if P = J then P := I;
        Inc(I); Dec(J);
      end;
    until I > J;
    if J - L < R - I then begin // use recursion only for smaller range
      if L < J then
        QuickSort(L, J);
      L := I;
    end else begin
      if I < R then
        QuickSort(I, R);
      R := J;
    end;
  until L >= R;
end;

procedure TDynArrayQuickSort.QuickSortEvent(L, R: PtrInt);
var I, J: PtrInt;
begin
  if L<R then
  repeat
    I := L; J := R;
    P := (L + R) shr 1;
    repeat
      Pivot := Value+PtrUInt(P)*ElemSize;
      IP := Value+PtrUInt(I)*ElemSize;
      JP := Value+PtrUInt(J)*ElemSize;
      while CompareEvent(IP^,Pivot^)<0 do begin
        inc(I);
        inc(IP,ElemSize);
      end;
      while CompareEvent(JP^,Pivot^)>0 do begin
        dec(J);
        dec(JP,ElemSize);
      end;
      if I <= J then begin
        if I<>J then
          Exchg(IP,JP,ElemSize);
        if P = I then P := J else
        if P = J then P := I;
        Inc(I); Dec(J);
      end;
    until I > J;
    if J - L < R - I then begin // use recursion only for smaller range
      if L < J then
        QuickSortEvent(L, J);
      L := I;
    end else begin
      if I < R then
        QuickSortEvent(I, R);
      R := J;
    end;
  until L >= R;
end;

procedure TDynArrayQuickSort.QuickSortEventReverse(L, R: PtrInt);
var I, J: PtrInt;
begin
  if L<R then
  repeat
    I := L; J := R;
    P := (L + R) shr 1;
    repeat
      Pivot := Value+PtrUInt(P)*ElemSize;
      IP := Value+PtrUInt(I)*ElemSize;
      JP := Value+PtrUInt(J)*ElemSize;
      while CompareEvent(IP^,Pivot^)>0 do begin
        inc(I);
        inc(IP,ElemSize);
      end;
      while CompareEvent(JP^,Pivot^)<0 do begin
        dec(J);
        dec(JP,ElemSize);
      end;
      if I <= J then begin
        if I<>J then
          Exchg(IP,JP,ElemSize);
        if P = I then P := J else
        if P = J then P := I;
        Inc(I); Dec(J);
      end;
    until I > J;
    if J - L < R - I then begin // use recursion only for smaller range
      if L < J then
        QuickSortEventReverse(L, J);
      L := I;
    end else begin
      if I < R then
        QuickSortEventReverse(I, R);
      R := J;
    end;
  until L >= R;
end;

procedure TDynArrayQuickSort.QuickSortIndexed(L, R: PtrInt);
var I, J: PtrInt;
    tmp: integer;
begin
  if L<R then
  repeat
    I := L; J := R;
    P := (L + R) shr 1;
    repeat
      Pivot := Value+Index[P]*ElemSize;
      while Compare(Value[Index[I]*ElemSize],Pivot^)<0 do inc(I);
      while Compare(Value[Index[J]*ElemSize],Pivot^)>0 do dec(J);
      if I <= J then begin
        if I<>J then begin
          tmp := Index[I];
          Index[I] := Index[J];
          Index[J] := tmp;
        end;
        if P = I then P := J else
        if P = J then P := I;
        Inc(I); Dec(J);
      end;
    until I > J;
    if J - L < R - I then begin // use recursion only for smaller range
      if L < J then
        QuickSortIndexed(L, J);
      L := I;
    end else begin
      if I < R then
        QuickSortIndexed(I, R);
      R := J;
    end;
  until L >= R;
end;

procedure TDynArray.Sort(aCompare: TDynArraySortCompare);
begin
  SortRange(0,Count-1,aCompare);
  fSorted := true;
end;

procedure QuickSortPtr(L, R: PtrInt; Compare: TDynArraySortCompare; V: PPointerArray);
var I, J, P: PtrInt;
    tmp: pointer;
begin
  if L<R then
  repeat
    I := L; J := R;
    P := (L + R) shr 1;
    repeat
      while Compare(V[I], V[P])<0 do
        inc(I);
      while Compare(V[J], V[P])>0 do
        dec(J);
      if I <= J then begin
        tmp := V[I];
        V[I] := V[J];
        V[J] := tmp;
        if P = I then P := J else
        if P = J then P := I;
        Inc(I); Dec(J);
      end;
    until I > J;
    if J - L < R - I then begin // use recursion only for smaller range
      if L < J then
        QuickSortPtr(L, J, Compare, V);
      L := I;
    end else begin
      if I < R then
        QuickSortPtr(I, R, Compare, V);
      R := J;
    end;
  until L >= R;
end;

procedure TDynArray.SortRange(aStart, aStop: integer; aCompare: TDynArraySortCompare);
var QuickSort: TDynArrayQuickSort;
begin
  if aStop<=aStart then
    exit; // nothing to sort
  if @aCompare=nil then
    Quicksort.Compare := @fCompare else
    Quicksort.Compare := aCompare;
  if (@Quicksort.Compare<>nil) and (fValue<>nil) and (fValue^<>nil) then
    if ElemSize=SizeOf(pointer) then
      QuickSortPtr(aStart,aStop,QuickSort.Compare,fValue^) else begin
      Quicksort.Value := fValue^;
      Quicksort.ElemSize := ElemSize;
      Quicksort.QuickSort(aStart,aStop);
    end;
end;

procedure TDynArray.Sort(const aCompare: TEventDynArraySortCompare; aReverse: boolean);
var QuickSort: TDynArrayQuickSort;
    R: PtrInt;
begin
  if not Assigned(aCompare) or (fValue = nil) or (fValue^=nil) then
    exit; // nothing to sort
  Quicksort.CompareEvent := aCompare;
  Quicksort.Value := fValue^;
  Quicksort.ElemSize := ElemSize;
  R := Count-1;
  if aReverse then
    Quicksort.QuickSortEventReverse(0,R) else
    Quicksort.QuickSortEvent(0,R);
end;

procedure TDynArray.CreateOrderedIndex(var aIndex: TIntegerDynArray;
  aCompare: TDynArraySortCompare);
var QuickSort: TDynArrayQuickSort;
    n: integer;
begin
  if @aCompare=nil then
    Quicksort.Compare := @fCompare else
    Quicksort.Compare := aCompare;
  if (@QuickSort.Compare<>nil) and (fValue<>nil) and (fValue^<>nil) then begin
    n := GetCount;
    if length(aIndex)<n then begin
      SetLength(aIndex,n);
      FillIncreasing(pointer(aIndex),0,n);
    end;
    Quicksort.Value := fValue^;
    Quicksort.ElemSize := ElemSize;
    Quicksort.Index := pointer(aIndex);
    Quicksort.QuickSortIndexed(0,n-1);
  end;
end;

procedure TDynArray.CreateOrderedIndex(out aIndex: TSynTempBuffer;
  aCompare: TDynArraySortCompare);
var QuickSort: TDynArrayQuickSort;
    n: integer;
begin
  if @aCompare=nil then
    Quicksort.Compare := @fCompare else
    Quicksort.Compare := aCompare;
  if (@QuickSort.Compare<>nil) and (fValue<>nil) and (fValue^<>nil) then begin
    n := GetCount;
    Quicksort.Value := fValue^;
    Quicksort.ElemSize := ElemSize;
    Quicksort.Index := PCardinalArray(aIndex.InitIncreasing(n));
    Quicksort.QuickSortIndexed(0,n-1);
  end else
    aIndex.buf := nil; // avoid GPF in aIndex.Done
end;

procedure TDynArray.CreateOrderedIndexAfterAdd(var aIndex: TIntegerDynArray;
  aCompare: TDynArraySortCompare);
var ndx: integer;
begin
  ndx := GetCount-1;
  if ndx<0 then
    exit;
  if aIndex<>nil then begin // whole FillIncreasing(aIndex[]) for first time
    if ndx>=length(aIndex) then
      SetLength(aIndex,NextGrow(ndx)); // grow aIndex[] if needed
    aIndex[ndx] := ndx;
  end;
  CreateOrderedIndex(aIndex,aCompare);
end;

function TDynArray.ElemEquals(const A,B): boolean;
begin
  if @fCompare<>nil then
    result := fCompare(A,B)=0 else
    if ElemType=nil then
      case ElemSize of // optimized versions for arrays of common types
        1: result := byte(A)=byte(B);
        2: result := word(A)=word(B);
        4: result := cardinal(A)=cardinal(B);
        8: result := Int64(A)=Int64(B);
        16: result := IsEqual(THash128(A),THash128(B));
      else result := CompareMemFixed(@A,@B,ElemSize); // binary comparison
      end else
      if PTypeKind(ElemType)^ in tkRecordTypes then // most likely
        result := RecordEquals(A,B,ElemType) else
        result := ManagedTypeCompare(@A,@B,ElemType)>0; // other complex types
end;

{$ifndef DELPHI5OROLDER} // disabled for Delphi 5 buggy compiler
procedure TDynArray.InitFrom(const aAnother: TDynArray; var aValue);
begin
  self := aAnother;
  fValue := @aValue;
  fCountP := nil;
end;

procedure TDynArray.AddDynArray(const aSource: TDynArray; aStartIndex: integer;
  aCount: integer);
var SourceCount: integer;
begin
  if (aSource.fValue<>nil) and (ArrayType=aSource.ArrayType) then begin
    SourceCount := aSource.Count;
    if (aCount<0) or (aCount>SourceCount) then
      aCount := SourceCount; // force use of external Source.Count, if any
    AddArray(aSource.fValue^,aStartIndex,aCount);
  end;
end;

function TDynArray.Equals(const B: TDynArray; ignorecompare: boolean): boolean;
var i, n: integer;
    P1,P2: PAnsiChar;
    A1: PPointerArray absolute P1;
    A2: PPointerArray absolute P2;
  function HandleObjArray: boolean;
  var tmp1,tmp2: RawUTF8;
  begin
    SaveToJSON(tmp1);
    B.SaveToJSON(tmp2);
    result := tmp1=tmp2;
  end;
begin
  result := false;
  if ArrayType<>B.ArrayType then
    exit; // array types should match exactly
  n := GetCount;
  if n<>B.Count then
    exit;
  if GetIsObjArray then begin
    result := HandleObjArray;
    exit;
  end;
  P1 := fValue^;
  P2 := B.fValue^;
  if (@fCompare<>nil) and not ignorecompare then // use customized comparison
    for i := 1 to n do
      if fCompare(P1^,P2^)<>0 then
        exit else begin
        inc(P1,ElemSize);
        inc(P2,ElemSize);
      end else
  if ElemType=nil then begin // binary type is compared as a whole
    result := CompareMem(P1,P2,ElemSize*cardinal(n));
    exit;
  end else
  case PTypeKind(ElemType)^ of // some optimized versions for most used types
  tkLString{$ifdef FPC},tkLStringOld{$endif}:
    for i := 0 to n-1 do
      if AnsiString(A1^[i])<>AnsiString(A2^[i]) then
        exit;
  tkWString:
    for i := 0 to n-1 do
      if WideString(A1^[i])<>WideString(A2^[i]) then
        exit;
  {$ifdef HASVARUSTRING}
  tkUString:
    for i := 0 to n-1 do
      if UnicodeString(A1^[i])<>UnicodeString(A2^[i]) then
        exit;
  {$endif}
  tkRecord{$ifdef FPC},tkObject{$endif}:
    for i := 1 to n do
      if not RecordEquals(P1^,P2^,ElemType) then
        exit else begin
        inc(P1,ElemSize);
        inc(P2,ElemSize);
      end;
  else // generic TypeInfoCompare() use
    for i := 1 to n do
      if ManagedTypeCompare(P1,P2,ElemType)<=0 then
        exit else begin // A^<>B^ or unexpected type
        inc(P1,ElemSize);
        inc(P2,ElemSize);
      end;
  end;
  result := true;
end;

procedure TDynArray.Copy(const Source: TDynArray; ObjArrayByRef: boolean);
var n: Cardinal;
begin
  if (fValue=nil) or (ArrayType<>Source.ArrayType) then
    exit;
  if (fCountP<>nil) and (Source.fCountP<>nil) then
    SetCapacity(Source.GetCapacity);
  n := Source.Count;
  SetCount(n);
  if n<>0 then
    if ElemType=nil then
      if not ObjArrayByRef and GetIsObjArray then
        LoadFromJSON(pointer(Source.SaveToJSON)) else
        MoveFast(Source.fValue^^,fValue^^,n*ElemSize) else
      CopyArray(fValue^,Source.fValue^,ElemType,n);
end;

procedure TDynArray.CopyFrom(const Source; MaxElem: integer; ObjArrayByRef: boolean);
var SourceDynArray: TDynArray;
begin
  SourceDynArray.Init(fTypeInfo,pointer(@Source)^);
  SourceDynArray.fCountP := @MaxElem; // would set Count=0 at Init()
  Copy(SourceDynArray,ObjArrayByRef);
end;

procedure TDynArray.CopyTo(out Dest; ObjArrayByRef: boolean);
var DestDynArray: TDynArray;
begin
  DestDynArray.Init(fTypeInfo,Dest);
  DestDynArray.Copy(self,ObjArrayByRef);
end;
{$endif DELPHI5OROLDER}

function TDynArray.IndexOf(const Elem): PtrInt;
var P: PPointerArray;
    max: PtrInt;
begin
  if fValue<>nil then begin
    max := GetCount-1;
    P := fValue^;
    if @Elem<>nil then
    if ElemType=nil then begin
      result := AnyScanIndex(P,@Elem,max+1,ElemSize);
      exit;
    end else
    case PTypeKind(ElemType)^ of
    tkLString{$ifdef FPC},tkLStringOld{$endif}:
      for result := 0 to max do
        if AnsiString(P^[result])=AnsiString(Elem) then exit;
    tkWString:
      for result := 0 to max do
        if WideString(P^[result])=WideString(Elem) then exit;
    {$ifdef HASVARUSTRING}
    tkUString:
      for result := 0 to max do
        if UnicodeString(P^[result])=UnicodeString(Elem) then exit;
    {$endif}
    {$ifndef NOVARIANTS}
    tkVariant:
      for result := 0 to max do
        if SortDynArrayVariantComp(PVarDataStaticArray(P)^[result],
          TVarData(Elem),false)=0 then exit;
    {$endif}
    tkRecord{$ifdef FPC},tkObject{$endif}:
      // RecordEquals() works with packed records containing binary and string types
      for result := 0 to max do
        if RecordEquals(P^,Elem,ElemType) then
          exit else
          inc(PByte(P),ElemSize);
    tkInterface:
      for result := 0 to max do
        if P^[result]=pointer(Elem) then exit;
    else
      for result := 0 to max do
        if ManagedTypeCompare(pointer(P),@Elem,ElemType)>0 then
          exit else
          inc(PByte(P),ElemSize);
    end;
  end;
  result := -1;
end;

procedure TDynArray.Init(aTypeInfo: pointer; var aValue; aCountPointer: PInteger);
begin
  fValue := @aValue;
  fTypeInfo := aTypeInfo;
  if PTypeKind(aTypeInfo)^<>tkDynArray then // inlined GetTypeInfo()
    raise ESynException.CreateUTF8('TDynArray.Init: % is %, expected tkDynArray',
      [ArrayTypeShort^,ToText(PTypeKind(aTypeInfo)^)^]);
  {$ifdef HASALIGNTYPEDATA}
  aTypeInfo := FPCTypeInfoOverName(aTypeInfo);
  {$else}
  inc(PByte(aTypeInfo),PTypeInfo(aTypeInfo)^.NameLen);
  {$endif}
  fElemSize := PTypeInfo(aTypeInfo)^.elSize {$ifdef FPC}and $7FFFFFFF{$endif};
  fElemType := PTypeInfo(aTypeInfo)^.elType;
  if fElemType<>nil then begin // inlined DeRef()
    {$ifndef HASDIRECTTYPEINFO}
    // FPC compatibility: if you have a GPF here at startup, your 3.1 trunk
    // revision seems older than June 2016
    // -> enable HASDIRECTTYPEINFO conditional below $ifdef VER3_1 in Synopse.inc
    // or in your project's options
    fElemType := PPointer(fElemType)^;
    {$endif HASDIRECTTYPEINFO}
    {$ifdef FPC}
    if not (PTypeKind(fElemType)^ in tkManagedTypes) then
      fElemType := nil; // as with Delphi
    {$endif FPC}
  end;
  {$ifdef DYNARRAYELEMTYPE2} // disabled not to break backward compatibility
  fElemType2 := PTypeInfo(aTypeInfo)^.elType2;
  {$endif}
  fCountP := aCountPointer;
  if fCountP<>nil then
    fCountP^ := 0;
  fCompare := nil;
  fParser := DYNARRAY_PARSERUNKNOWN;
  fKnownSize := 0;
  fSorted := false;
  fKnownType := djNone;
  fIsObjArray := oaUnknown;
end;

procedure TDynArray.InitSpecific(aTypeInfo: pointer; var aValue; aKind: TDynArrayKind;
  aCountPointer: PInteger; aCaseInsensitive: boolean);
var Comp: TDynArraySortCompare;
begin
  Init(aTypeInfo,aValue,aCountPointer);
  Comp := DYNARRAY_SORTFIRSTFIELD[aCaseInsensitive,aKind];
  if @Comp=nil then
    raise ESynException.CreateUTF8('TDynArray.InitSpecific(%) wrong aKind=%',
      [ArrayTypeShort^,ToText(aKind)^]);
  fCompare := Comp;
  fKnownType := aKind;
  fKnownSize := KNOWNTYPE_SIZE[aKind];
end;

procedure TDynArray.UseExternalCount(var aCountPointer: Integer);
begin
  fCountP := @aCountPointer;
end;

function TDynArray.HasCustomJSONParser: boolean;
begin
  if fParser=DYNARRAY_PARSERUNKNOWN then
    fParser := GlobalJSONCustomParsers.DynArraySearch(ArrayType,ElemType);
  result := cardinal(fParser)<cardinal(GlobalJSONCustomParsers.fParsersCount);
end;

procedure TDynArray.Void;
begin
  fValue := nil;
end;

function TDynArray.IsVoid: boolean;
begin
  result := fValue=nil;
end;

function TDynArray.ComputeIsObjArray: boolean;
begin
  result := (fElemSize=SizeOf(pointer)) and (fElemType=nil) and
     Assigned(DynArrayIsObjArray) and (DynArrayIsObjArray(fTypeInfo)<>nil);
  if result then
    fIsObjArray := oaTrue else
    fIsObjArray := oaFalse;
end;

procedure TDynArray.SetIsObjArray(aValue: boolean);
begin
  if aValue then
    fIsObjArray := oaTrue else
    fIsObjArray := oaFalse;
end;

procedure TDynArray.InternalSetLength(OldLength,NewLength: PtrUInt);
var p: PDynArrayRec;
    NeededSize, minLength: PtrUInt;
    pp: pointer;
begin // this method is faster than default System.DynArraySetLength() function
  p := fValue^;
  // check that new array length is not just a finalize in disguise
  if NewLength=0 then begin
    if p<>nil then begin // FastDynArrayClear() with ObjArray support
      dec(p);
      if (p^.refCnt>=0) and DACntDecFree(p^.refCnt) then begin
        if OldLength<>0 then
          if ElemType<>nil then
            FastFinalizeArray(fValue^,ElemType,OldLength) else
            if GetIsObjArray then
              RawObjectsClear(fValue^,OldLength);
        FreeMem(p);
      end;
      fValue^ := nil;
    end;
    exit;
  end;
  // calculate the needed size of the resulting memory structure on heap
  NeededSize := NewLength*ElemSize+SizeOf(TDynArrayRec);
  {$ifndef CPU64}
  if NeededSize>1024*1024*1024 then // max workable memory block is 1 GB
    raise ERangeError.CreateFmt('TDynArray SetLength(%s,%d) size concern',
      [ArrayTypeShort^,NewLength]);
  {$endif}
  // if not shared (refCnt=1), resize; if shared, create copy (not thread safe)
  if p=nil then begin
    p := AllocMem(NeededSize); // RTL/OS will return zeroed memory
    OldLength := NewLength;    // no FillcharFast() below
  end else begin
    dec(PtrUInt(p),SizeOf(TDynArrayRec)); // p^ = start of heap object
    if (p^.refCnt>=0) and DACntDecFree(p^.refCnt) then begin
      if NewLength<OldLength then // reduce array in-place
        if ElemType<>nil then // release managed types in trailing items
          FastFinalizeArray(pointer(PAnsiChar(p)+NeededSize),ElemType,OldLength-NewLength) else
          if GetIsObjArray then // FreeAndNil() of resized objects list
            RawObjectsClear(pointer(PAnsiChar(p)+NeededSize),OldLength-NewLength);
      ReallocMem(p,NeededSize);
    end else begin // make copy
      GetMem(p,NeededSize);
      minLength := OldLength;
      if minLength>NewLength then
        minLength := NewLength;
      pp := PAnsiChar(p)+SizeOf(TDynArrayRec);
      if ElemType<>nil then begin
        FillCharFast(pp^,minLength*elemSize,0);
        CopyArray(pp,fValue^,ElemType,minLength);
      end else
        MoveFast(fValue^^,pp^,minLength*elemSize);
    end;
  end;
  // set refCnt=1 and new length to the heap header
  with p^ do begin
    refCnt := 1;
    {$ifdef FPC}
    high := newLength-1;
    {$else}
    length := newLength;
    {$endif}
  end;
  inc(PByte(p),SizeOf(p^)); // p^ = start of dynamic aray items
  fValue^ := p;
  // reset new allocated elements content to zero
  if NewLength>OldLength then begin
    OldLength := OldLength*elemSize;
    FillCharFast(PAnsiChar(p)[OldLength],NewLength*ElemSize-OldLength,0);
  end;
end;

procedure TDynArray.SetCount(aCount: PtrInt);
const MINIMUM_SIZE = 64;
var oldlen, extcount, arrayptr, capa, delta: PtrInt;
begin
  arrayptr := PtrInt(fValue);
  extcount := PtrInt(fCountP);
  fSorted := false;
  if arrayptr=0 then
    exit; // avoid GPF if void
  arrayptr := PPtrInt(arrayptr)^;
  if extcount<>0 then begin // fCountP^ as external capacity
    oldlen := PInteger(extcount)^;
    delta := aCount-oldlen;
    if delta=0 then
      exit;
    PInteger(extcount)^ := aCount; // store new length
    if arrayptr=0 then begin // void array
      if (delta>0) and (aCount<MINIMUM_SIZE) then
        aCount := MINIMUM_SIZE; // reserve some minimal (64) items for Add()
    end else begin
      capa := PDALen(arrayptr-_DALEN)^{$ifdef FPC}+1{$endif};
      if delta>0 then begin  // size-up
        if capa>=aCount then
          exit; // no need to grow
        capa := NextGrow(capa);
        if capa>aCount then
          aCount := capa; // grow by chunks
      end else  // size-down
      if (aCount>0) and ((capa<=MINIMUM_SIZE) or (capa-aCount<capa shr 3)) then
        exit; // reallocate memory only if worth it (for faster Delete)
    end;
  end else // no external capacity: use length()
  if arrayptr=0 then
    oldlen := arrayptr else begin
    oldlen := PDALen(arrayptr-_DALEN)^{$ifdef FPC}+1{$endif};
    if oldlen=aCount then
      exit;  // InternalSetLength(samecount) would make a private copy
  end;
  // no external Count, array size-down or array up-grow -> realloc
  InternalSetLength(oldlen,aCount);
end;

function TDynArray.GetCapacity: PtrInt;
begin // capacity = length(DynArray)
  result := PtrInt(fValue);
  if result<>0 then begin
    result := PPtrInt(result)^;
    if result<>0 then
      result := PDALen(result-_DALEN)^{$ifdef FPC}+1{$endif};
  end;
end;

procedure TDynArray.SetCapacity(aCapacity: PtrInt);
var oldlen,capa: PtrInt;
begin
  if fValue=nil then
    exit;
  capa := GetCapacity;
  if fCountP<>nil then begin
    oldlen := fCountP^;
    if oldlen>aCapacity then
      fCountP^ := aCapacity;
  end else
    oldlen := capa;
  if capa<>aCapacity then
    InternalSetLength(oldlen,aCapacity);
end;

procedure TDynArray.SetCompare(const aCompare: TDynArraySortCompare);
begin
  if @aCompare<>@fCompare then begin
    @fCompare := @aCompare;
    fSorted := false;
  end;
end;

procedure TDynArray.Slice(var Dest; aCount, aFirstIndex: cardinal);
var n: Cardinal;
    D: PPointer;
    P: PAnsiChar;
begin
  if fValue=nil then
    exit; // avoid GPF if void
  n := GetCount;
  if aFirstIndex>=n then
    aCount := 0 else
  if aCount>=n-aFirstIndex then
    aCount := n-aFirstIndex;
  DynArray(ArrayType,Dest).SetCapacity(aCount);
  if aCount>0 then begin
    D := @Dest;
    P := PAnsiChar(fValue^)+aFirstIndex*ElemSize;
    if ElemType=nil then
      MoveFast(P^,D^^,aCount*ElemSize) else
      CopyArray(D^,P,ElemType,aCount);
  end;
end;

function TDynArray.AddArray(const DynArrayVar; aStartIndex, aCount: integer): integer;
var c, n: integer;
    PS,PD: pointer;
begin
  result := 0;
  if fValue=nil then
    exit; // avoid GPF if void
  c := DynArrayLength(pointer(DynArrayVar));
  if aStartIndex>=c then
    exit; // nothing to copy
  if (aCount<0) or (cardinal(aStartIndex+aCount)>cardinal(c)) then
    aCount := c-aStartIndex;
  if aCount<=0 then
    exit;
  result := aCount;
  n := GetCount;
  SetCount(n+aCount);
  PS := pointer(PtrUInt(DynArrayVar)+cardinal(aStartIndex)*ElemSize);
  PD := pointer(PtrUInt(fValue^)+cardinal(n)*ElemSize);
  if ElemType=nil then
    MoveFast(PS^,PD^,cardinal(aCount)*ElemSize) else
    CopyArray(PD,PS,ElemType,aCount);
end;

procedure TDynArray.ElemClear(var Elem);
begin
  if @Elem=nil then
    exit; // avoid GPF
  if ElemType<>nil then
    {$ifdef FPC}FPCFinalize{$else}_Finalize{$endif}(@Elem,ElemType) else
    if (fIsObjArray=oaTrue) or ((fIsObjArray=oaUnknown) and ComputeIsObjArray) then
      TObject(Elem).Free;
  FillCharFast(Elem,ElemSize,0); // always
end;

function TDynArray.ElemLoad(Source,SourceMax: PAnsiChar): RawByteString;
begin
  if (Source<>nil) and (ElemType=nil) then
    SetString(result,Source,ElemSize) else begin
    SetString(result,nil,ElemSize);
    FillCharFast(pointer(result)^,ElemSize,0);
    ElemLoad(Source,pointer(result)^);
  end;
end;

procedure TDynArray.ElemLoadClear(var ElemTemp: RawByteString);
begin
  ElemClear(pointer(ElemTemp));
  ElemTemp := '';
end;

procedure TDynArray.ElemLoad(Source: PAnsiChar; var Elem; SourceMax: PAnsiChar);
begin
  if Source<>nil then // avoid GPF
    if ElemType=nil then begin
      if (SourceMax=nil) or (Source+ElemSize<=SourceMax) then
        MoveFast(Source^,Elem,ElemSize);
    end else
      ManagedTypeLoad(@Elem,Source,ElemType,SourceMax);
end;

function TDynArray.ElemSave(const Elem): RawByteString;
var itemsize: integer;
begin
  if ElemType=nil then
    SetString(result,PAnsiChar(@Elem),ElemSize) else begin
    SetString(result,nil,ManagedTypeSaveLength(@Elem,ElemType,itemsize));
    if result<>'' then
      ManagedTypeSave(@Elem,pointer(result),ElemType,itemsize);
  end;
end;

function TDynArray.ElemLoadFind(Source, SourceMax: PAnsiChar): integer;
var tmp: array[0..2047] of byte;
    data: pointer;
begin
  result := -1;
  if (Source=nil) or (ElemSize>SizeOf(tmp)) then
    exit;
  if ElemType=nil then
    data := Source else begin
    FillCharFast(tmp,ElemSize,0);
    ManagedTypeLoad(@tmp,Source,ElemType,SourceMax);
    if Source=nil then
      exit;
    data := @tmp;
  end;
  try
    if @fCompare=nil then
      result := IndexOf(data^) else
      result := Find(data^);
  finally
    if ElemType<>nil then
      {$ifdef FPC}FPCFinalize{$else}_Finalize{$endif}(data,ElemType);
  end;
end;

//------------------------------------------------------------------------------

end.
