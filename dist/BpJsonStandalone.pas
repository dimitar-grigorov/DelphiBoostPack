unit BpJsonStandalone;

// BpJsonStandalone.pas - GENERATED FILE, DO NOT EDIT.
// Single-file bundle amalgamated from the DelphiBoostPack modular units:
//   src\Core\Classes\BpStringBuilder.pas
//   src\Core\Classes\BpJson.pas
// Source commit 2677e2a, generated 2026-07-24 by tools\Amalgamate.ps1.
// Fix bugs in the modular units, then regenerate with:
//   powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1
// Notes:
// - use at most one bundle per project; two bundles embedding the same
//   helper unit would declare duplicate identifiers
// - unit-wide compiler directives of embedded units (e.g. {$Q-} in the
//   hash units) apply from their position to the end of this file

interface

uses
  SysUtils, Math;

// ==================================================================
// BpStringBuilder.pas - interface
// ==================================================================

// Fast string builder for Delphi 7/2007 and later, API modeled on the XE6
// SysUtils.TStringBuilder (itself a port of the .NET StringBuilder API).
//
// Storage is one contiguous string used as a raw character buffer with the
// logical length tracked separately, so an append is a capacity check, one
// Move and a cursor bump. Capacity doubles on growth (minimum 16). The RTL
// version funnels every Append through the Length property setter, which is
// the main reason it is slow; this one writes through a cached raw pointer.
//
// Integers are formatted backward into a small stack buffer (the mORMot
// TTextWriter trick), so Append(Integer) and Append(Int64) never allocate.
//
// Chars and Insert use 0-based indexes, matching the XE6 TStringBuilder
// convention. Clear keeps the allocated capacity so a builder can be reused
// in a loop without reallocating.

type
  // raised for out-of-range indexes and invalid capacity or length values
  EbpStringBuilder = class(Exception);

  TbpStringBuilder = class
  private
    FBuffer: string;  // raw storage, logical content is the first FLength chars
    FData: PChar;     // cached Pointer(FBuffer), refreshed on every reallocation
    FLength: Integer;
    procedure Grow(aMinCapacity: Integer);
    procedure AppendBuffer(aSource: PChar; aCount: Integer);
    function GetCapacity: Integer;
    procedure SetCapacity(aValue: Integer);
    function GetChar(aIndex: Integer): Char;
    procedure SetChar(aIndex: Integer; aValue: Char);
    procedure SetLength(aValue: Integer);
  public
    constructor Create; overload;
    constructor Create(aCapacity: Integer); overload;
    constructor Create(const aValue: string); overload;
    // all Append overloads return Self so calls can be chained
    function Append(const aValue: string): TbpStringBuilder; overload;
    function Append(aValue: Char): TbpStringBuilder; overload;
    function Append(aValue: Char; aRepeatCount: Integer): TbpStringBuilder; overload;
    function Append(aValue: Integer): TbpStringBuilder; overload;
    function Append(aValue: Int64): TbpStringBuilder; overload;
    function Append(aValue: Double): TbpStringBuilder; overload;
    function Append(aValue: Boolean): TbpStringBuilder; overload;
    function AppendLine: TbpStringBuilder; overload;
    function AppendLine(const aValue: string): TbpStringBuilder; overload;
    function AppendFormat(const aFormat: string; const aArgs: array of const): TbpStringBuilder;
    function Insert(aIndex: Integer; const aValue: string): TbpStringBuilder;
    procedure Clear;
    function ToString: string; {$IF CompilerVersion >= 20.0} override; {$IFEND}
    // Length is writable: shrinking truncates, extending pads with #0
    property Length: Integer read FLength write SetLength;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Chars[aIndex: Integer]: Char read GetChar write SetChar; default;
  end;

// ==================================================================
// BpJson.pas - interface
// ==================================================================

// JSON reader and writer for Delphi 7/2007 and later (RFC 8259), no
// dependencies outside the RTL and BpStringBuilder.
//
// One class models the whole tree: a TbpJsonValue is a null, bool, int,
// float, string, array or object depending on Kind. Parse returns the root
// and freeing the root frees the entire tree (a parent owns its children).
// The API shape mines XE6 System.JSON and superobject: typed object
// accessors follow the TbpStrDictionary convention (GetStr / GetStrDef /
// TryGetStr / SetStr) and FindPath walks dotted paths with [n] indexing,
// e.g. Root.PathStrDef('data.items[0].name', '').
//
// The reader is a strict single-pass recursive descent parser over PChar:
// leading zeros, control characters in strings, trailing commas and text
// after the value all fail with a line/position message. Numbers without
// '.' or exponent become Int64 (bjkInt), everything else Double (bjkFloat);
// Int64 overflow falls back to float. \uXXXX escapes handle surrogate
// pairs. Nesting depth is capped so hostile input cannot blow the stack.
// Duplicate member names keep the last value, like JavaScript.
//
// On pre-Unicode compilers strings are AnsiString in the system codepage:
// \uXXXX escapes convert through WideString (chars outside the codepage
// become '?') and the parser assumes a single-byte codepage such as 1251.
// ToJson(True) escapes every char above #127 as \uXXXX, producing pure
// ASCII output that is safe to send anywhere regardless of codepage.

type
  // raised on parse errors, kind mismatches and missing object members
  EbpJson = class(Exception);

  TbpJsonKind = (bjkNull, bjkBool, bjkInt, bjkFloat, bjkString, bjkArray,
    bjkObject);

  TbpJsonValue = class
  private
    FKind: TbpJsonKind;
    FBool: Boolean;
    FInt: Int64;
    FFloat: Double;
    FStr: string;
    FItems: array of TbpJsonValue;  // array elements or object member values
    FNames: array of string;        // object member names, parallel to FItems
    FCount: Integer;
    function GetItem(aIndex: Integer): TbpJsonValue;
    function GetName(aIndex: Integer): string;
    procedure RequireKind(aKind: TbpJsonKind);
    function IndexOfName(const aName: string): Integer;
    procedure InternalAdd(const aName: string; aChild: TbpJsonValue);
    procedure InternalPut(const aName: string; aChild: TbpJsonValue);
    function MemberOrFail(const aName: string): TbpJsonValue;
    procedure WriteTo(aSb: TbpStringBuilder; aEscapeNonAscii: Boolean;
      aIndentSize, aLevel: Integer);
  public
    constructor Create;  // a null value
    destructor Destroy; override;

    // building blocks; add the result to a container or free it yourself
    class function CreateNull: TbpJsonValue;
    class function CreateBool(aValue: Boolean): TbpJsonValue;
    class function CreateInt(aValue: Int64): TbpJsonValue;
    class function CreateFloat(aValue: Double): TbpJsonValue;
    class function CreateStr(const aValue: string): TbpJsonValue;
    class function CreateArray: TbpJsonValue;
    class function CreateObject: TbpJsonValue;

    // Parse raises EbpJson with line/position, TryParse returns False
    class function Parse(const aJson: string): TbpJsonValue;
    class function TryParse(const aJson: string;
      out aValue: TbpJsonValue): Boolean;

    function Clone: TbpJsonValue;  // deep copy, caller owns the result
    function KindName: string;
    function IsNull: Boolean;
    property Kind: TbpJsonKind read FKind;

    // strict scalar access: the wrong kind raises EbpJson;
    // AsFloat also accepts int, nothing else converts
    function AsBool: Boolean;
    function AsInt: Int64;
    function AsFloat: Double;
    function AsStr: string;

    // Count and Items serve both arrays and objects, Names only objects
    property Count: Integer read FCount;
    property Items[aIndex: Integer]: TbpJsonValue read GetItem;
    property Names[aIndex: Integer]: string read GetName;
    procedure Delete(aIndex: Integer);
    procedure Clear;

    // array building; the value must be an array,
    // AddArray and AddObject return the new empty container
    procedure AddNull;
    procedure AddBool(aValue: Boolean);
    procedure AddInt(aValue: Int64);
    procedure AddFloat(aValue: Double);
    procedure AddStr(const aValue: string);
    function AddArray: TbpJsonValue;
    function AddObject: TbpJsonValue;

    // object member access; the value must be an object
    function Find(const aName: string): TbpJsonValue;  // nil when missing
    function Contains(const aName: string): Boolean;
    function Remove(const aName: string): Boolean;

    function GetBool(const aName: string): Boolean;
    function GetBoolDef(const aName: string; aDefault: Boolean): Boolean;
    function TryGetBool(const aName: string; out aValue: Boolean): Boolean;
    function GetInt(const aName: string): Int64;
    function GetIntDef(const aName: string; aDefault: Int64): Int64;
    function TryGetInt(const aName: string; out aValue: Int64): Boolean;
    function GetFloat(const aName: string): Double;
    function GetFloatDef(const aName: string; aDefault: Double): Double;
    function TryGetFloat(const aName: string; out aValue: Double): Boolean;
    function GetStr(const aName: string): string;
    function GetStrDef(const aName, aDefault: string): string;
    function TryGetStr(const aName: string; out aValue: string): Boolean;

    // create-or-replace member; SetArray and SetObject return the container
    procedure SetNull(const aName: string);
    procedure SetBool(const aName: string; aValue: Boolean);
    procedure SetInt(const aName: string; aValue: Int64);
    procedure SetFloat(const aName: string; aValue: Double);
    procedure SetStr(const aName, aValue: string);
    function SetArray(const aName: string): TbpJsonValue;
    function SetObject(const aName: string): TbpJsonValue;

    // dotted path with [n] indexing, e.g. 'data.items[0].name';
    // nil (or the default) when any step is missing or of the wrong kind
    function FindPath(const aPath: string): TbpJsonValue;
    function PathBoolDef(const aPath: string; aDefault: Boolean): Boolean;
    function PathIntDef(const aPath: string; aDefault: Int64): Int64;
    function PathFloatDef(const aPath: string; aDefault: Double): Double;
    function PathStrDef(const aPath, aDefault: string): string;

    // writers; aEscapeNonAscii escapes every char above #127 as \uXXXX
    function ToJson(aEscapeNonAscii: Boolean = False): string;
    function ToJsonPretty(aIndentSize: Integer = 2;
      aEscapeNonAscii: Boolean = False): string;
  end;

implementation

// ==================================================================
// BpStringBuilder.pas - implementation
// ==================================================================

const
  gcDefaultCapacity = 16;
  // Low(Int64) has no positive counterpart, appended as a literal instead
  gcMinInt64Text = '-9223372036854775808';

constructor TbpStringBuilder.Create;
begin
  inherited Create;
  // no allocation here, the first append grows to gcDefaultCapacity
end;

constructor TbpStringBuilder.Create(aCapacity: Integer);
begin
  inherited Create;
  if aCapacity < 0 then
    raise EbpStringBuilder.CreateFmt('Capacity cannot be negative (%d)', [aCapacity]);
  if aCapacity > 0 then
    SetCapacity(aCapacity);
end;

constructor TbpStringBuilder.Create(const aValue: string);
begin
  inherited Create;
  Append(aValue);
end;

procedure TbpStringBuilder.Grow(aMinCapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  lvNewCapacity := System.Length(FBuffer) * 2;
  if lvNewCapacity < gcDefaultCapacity then
    lvNewCapacity := gcDefaultCapacity;
  if lvNewCapacity < aMinCapacity then
    lvNewCapacity := aMinCapacity;
  System.SetLength(FBuffer, lvNewCapacity);
  FData := Pointer(FBuffer);
end;

procedure TbpStringBuilder.AppendBuffer(aSource: PChar; aCount: Integer);
begin
  if aCount <= 0 then
    Exit;
  if FLength + aCount > System.Length(FBuffer) then
    Grow(FLength + aCount);
  Move(aSource^, FData[FLength], aCount * SizeOf(Char));
  Inc(FLength, aCount);
end;

function TbpStringBuilder.Append(const aValue: string): TbpStringBuilder;
begin
  AppendBuffer(Pointer(aValue), System.Length(aValue));
  Result := Self;
end;

function TbpStringBuilder.Append(aValue: Char): TbpStringBuilder;
begin
  // single char fast path, direct store instead of a Move
  if FLength >= System.Length(FBuffer) then
    Grow(FLength + 1);
  FData[FLength] := aValue;
  Inc(FLength);
  Result := Self;
end;

function TbpStringBuilder.Append(aValue: Char; aRepeatCount: Integer): TbpStringBuilder;
var
  i: Integer;
begin
  if aRepeatCount < 0 then
    raise EbpStringBuilder.CreateFmt('RepeatCount cannot be negative (%d)', [aRepeatCount]);
  if aRepeatCount > 0 then
  begin
    if FLength + aRepeatCount > System.Length(FBuffer) then
      Grow(FLength + aRepeatCount);
    for i := 0 to aRepeatCount - 1 do
      FData[FLength + i] := aValue;
    Inc(FLength, aRepeatCount);
  end;
  Result := Self;
end;

function TbpStringBuilder.Append(aValue: Integer): TbpStringBuilder;
var
  lvBuf: array[0..11] of Char;
  lvPos: Integer;
  lvRemaining: Cardinal;
begin
  // digits are written backward from the end of the stack buffer, no allocation
  if aValue < 0 then
    lvRemaining := Cardinal(-Int64(aValue)) // Int64 negation, -Low(Integer) overflows Integer
  else
    lvRemaining := Cardinal(aValue);
  lvPos := High(lvBuf) + 1;
  repeat
    Dec(lvPos);
    lvBuf[lvPos] := Char(Ord('0') + lvRemaining mod 10);
    lvRemaining := lvRemaining div 10;
  until lvRemaining = 0;
  if aValue < 0 then
  begin
    Dec(lvPos);
    lvBuf[lvPos] := '-';
  end;
  AppendBuffer(@lvBuf[lvPos], High(lvBuf) + 1 - lvPos);
  Result := Self;
end;

function TbpStringBuilder.Append(aValue: Int64): TbpStringBuilder;
var
  lvBuf: array[0..19] of Char;
  lvPos: Integer;
  lvRemaining: Int64;
begin
  if aValue = Low(Int64) then
  begin
    Result := Append(gcMinInt64Text);
    Exit;
  end;
  lvRemaining := aValue;
  if lvRemaining < 0 then
    lvRemaining := -lvRemaining;
  lvPos := High(lvBuf) + 1;
  repeat
    Dec(lvPos);
    lvBuf[lvPos] := Char(Ord('0') + lvRemaining mod 10);
    lvRemaining := lvRemaining div 10;
  until lvRemaining = 0;
  if aValue < 0 then
  begin
    Dec(lvPos);
    lvBuf[lvPos] := '-';
  end;
  AppendBuffer(@lvBuf[lvPos], High(lvBuf) + 1 - lvPos);
  Result := Self;
end;

function TbpStringBuilder.Append(aValue: Double): TbpStringBuilder;
begin
  Result := Append(FloatToStr(aValue));
end;

function TbpStringBuilder.Append(aValue: Boolean): TbpStringBuilder;
begin
  if aValue then
    Result := Append('True')
  else
    Result := Append('False');
end;

function TbpStringBuilder.AppendLine: TbpStringBuilder;
begin
  Result := Append(sLineBreak);
end;

function TbpStringBuilder.AppendLine(const aValue: string): TbpStringBuilder;
begin
  Append(aValue);
  Result := Append(sLineBreak);
end;

function TbpStringBuilder.AppendFormat(const aFormat: string;
  const aArgs: array of const): TbpStringBuilder;
begin
  Result := Append(Format(aFormat, aArgs));
end;

function TbpStringBuilder.Insert(aIndex: Integer; const aValue: string): TbpStringBuilder;
var
  lvLen: Integer;
begin
  if (aIndex < 0) or (aIndex > FLength) then
    raise EbpStringBuilder.CreateFmt('Insert index %d out of bounds (0..%d)',
      [aIndex, FLength]);
  lvLen := System.Length(aValue);
  if lvLen > 0 then
  begin
    if FLength + lvLen > System.Length(FBuffer) then
      Grow(FLength + lvLen);
    if aIndex < FLength then
      Move(FData[aIndex], FData[aIndex + lvLen], (FLength - aIndex) * SizeOf(Char));
    Move(Pointer(aValue)^, FData[aIndex], lvLen * SizeOf(Char));
    Inc(FLength, lvLen);
  end;
  Result := Self;
end;

procedure TbpStringBuilder.Clear;
begin
  // capacity is kept on purpose so a reused builder does not reallocate
  FLength := 0;
end;

function TbpStringBuilder.ToString: string;
begin
  SetString(Result, FData, FLength);
end;

function TbpStringBuilder.GetCapacity: Integer;
begin
  Result := System.Length(FBuffer);
end;

procedure TbpStringBuilder.SetCapacity(aValue: Integer);
begin
  if (aValue < 0) or (aValue < FLength) then
    raise EbpStringBuilder.CreateFmt('Capacity %d is invalid (current length %d)',
      [aValue, FLength]);
  System.SetLength(FBuffer, aValue);
  FData := Pointer(FBuffer);
end;

function TbpStringBuilder.GetChar(aIndex: Integer): Char;
begin
  if (aIndex < 0) or (aIndex >= FLength) then
    raise EbpStringBuilder.CreateFmt('Index %d out of bounds (0..%d)',
      [aIndex, FLength - 1]);
  Result := FData[aIndex];
end;

procedure TbpStringBuilder.SetChar(aIndex: Integer; aValue: Char);
begin
  if (aIndex < 0) or (aIndex >= FLength) then
    raise EbpStringBuilder.CreateFmt('Index %d out of bounds (0..%d)',
      [aIndex, FLength - 1]);
  FData[aIndex] := aValue;
end;

procedure TbpStringBuilder.SetLength(aValue: Integer);
var
  i: Integer;
begin
  if aValue < 0 then
    raise EbpStringBuilder.CreateFmt('Length cannot be negative (%d)', [aValue]);
  if aValue > System.Length(FBuffer) then
    Grow(aValue);
  // extending pads with #0 so the new region is deterministic
  for i := FLength to aValue - 1 do
    FData[i] := #0;
  FLength := aValue;
end;

// ==================================================================
// BpJson.pas - implementation
// ==================================================================

const
  // recursion guard, far deeper than any sane document
  gcBpJsonMaxDepth = 512;
  gcBpJsonKindNames: array[TbpJsonKind] of string =
    ('null', 'bool', 'int', 'float', 'string', 'array', 'object');

type
  TbpJsonReader = record
    Start: PChar;
    Cur: PChar;
    Depth: Integer;
  end;

procedure BpJsonFail(const aReader: TbpJsonReader; const aMsg: string);
var
  lvP: PChar;
  lvLine, lvPos: Integer;
begin
  lvLine := 1;
  lvPos := 1;
  lvP := aReader.Start;
  while lvP < aReader.Cur do
  begin
    if lvP^ = #10 then
    begin
      Inc(lvLine);
      lvPos := 1;
    end
    else if lvP^ <> #13 then
      Inc(lvPos);
    Inc(lvP);
  end;
  raise EbpJson.CreateFmt('%s at line %d, position %d', [aMsg, lvLine, lvPos]);
end;

procedure BpJsonSkipWhite(var aReader: TbpJsonReader);
begin
  while True do
    case aReader.Cur^ of
      #9, #10, #13, ' ': Inc(aReader.Cur);
    else
      Break;
    end;
end;

// parses exactly four hex digits, the XXXX of a \uXXXX escape
function BpJsonHexQuad(var aReader: TbpJsonReader): Integer;
var
  lvI, lvDigit: Integer;
begin
  Result := 0;
  lvDigit := 0;
  for lvI := 1 to 4 do
  begin
    case aReader.Cur^ of
      '0'..'9': lvDigit := Ord(aReader.Cur^) - Ord('0');
      'a'..'f': lvDigit := Ord(aReader.Cur^) - Ord('a') + 10;
      'A'..'F': lvDigit := Ord(aReader.Cur^) - Ord('A') + 10;
    else
      BpJsonFail(aReader, 'Invalid \u escape');
    end;
    Result := Result * 16 + lvDigit;
    Inc(aReader.Cur);
  end;
end;

function BpJsonParseString(var aReader: TbpJsonReader): string;
var
  lvSb: TbpStringBuilder;
  lvSeg: PChar;
  lvW1, lvW2: Integer;
{$IF CompilerVersion < 20.0}
  lvWide: WideString;
{$IFEND}

  procedure FlushSeg(aUpTo: PChar);
  var
    lvChunk: string;
  begin
    if aUpTo > lvSeg then
    begin
      SetString(lvChunk, lvSeg, aUpTo - lvSeg);
      lvSb.Append(lvChunk);
    end;
  end;

  procedure AppendWideChar(aOrd: Integer);
  begin
{$IF CompilerVersion >= 20.0}
    lvSb.Append(Char(aOrd));
{$ELSE}
    SetLength(lvWide, 1);
    lvWide[1] := WideChar(aOrd);
    lvSb.Append(string(lvWide));
{$IFEND}
  end;

  procedure AppendSurrogatePair(aHi, aLo: Integer);
  begin
{$IF CompilerVersion >= 20.0}
    lvSb.Append(Char(aHi));
    lvSb.Append(Char(aLo));
{$ELSE}
    SetLength(lvWide, 2);
    lvWide[1] := WideChar(aHi);
    lvWide[2] := WideChar(aLo);
    lvSb.Append(string(lvWide));
{$IFEND}
  end;

begin
  Result := '';
  // aReader.Cur is on the opening quote
  Inc(aReader.Cur);
  lvSeg := aReader.Cur;
  // fast path: a string without escapes is one SetString
  while True do
    case aReader.Cur^ of
      '"':
        begin
          SetString(Result, lvSeg, aReader.Cur - lvSeg);
          Inc(aReader.Cur);
          Exit;
        end;
      '\': Break;
      #0: BpJsonFail(aReader, 'Unterminated string');
      #1..#31: BpJsonFail(aReader, 'Unescaped control character in string');
    else
      Inc(aReader.Cur);
    end;
  // slow path: copy segments between escapes and decode the escapes
  lvSb := TbpStringBuilder.Create(64);
  try
    while True do
      case aReader.Cur^ of
        '"':
          begin
            FlushSeg(aReader.Cur);
            Inc(aReader.Cur);
            Result := lvSb.ToString;
            Exit;
          end;
        '\':
          begin
            FlushSeg(aReader.Cur);
            Inc(aReader.Cur);
            case aReader.Cur^ of
              '"', '\', '/':
                begin
                  lvSb.Append(Char(aReader.Cur^));
                  Inc(aReader.Cur);
                end;
              'b': begin lvSb.Append(#8); Inc(aReader.Cur); end;
              't': begin lvSb.Append(#9); Inc(aReader.Cur); end;
              'n': begin lvSb.Append(#10); Inc(aReader.Cur); end;
              'f': begin lvSb.Append(#12); Inc(aReader.Cur); end;
              'r': begin lvSb.Append(#13); Inc(aReader.Cur); end;
              'u':
                begin
                  Inc(aReader.Cur);
                  lvW1 := BpJsonHexQuad(aReader);
                  if (lvW1 >= $D800) and (lvW1 <= $DBFF) then
                  begin
                    // a high surrogate must be followed by an escaped low one
                    if (aReader.Cur^ = '\') and (aReader.Cur[1] = 'u') then
                    begin
                      Inc(aReader.Cur, 2);
                      lvW2 := BpJsonHexQuad(aReader);
                      if (lvW2 < $DC00) or (lvW2 > $DFFF) then
                        BpJsonFail(aReader, 'Invalid surrogate pair');
                      AppendSurrogatePair(lvW1, lvW2);
                    end
                    else
                      BpJsonFail(aReader, 'Unpaired high surrogate');
                  end
                  else if (lvW1 >= $DC00) and (lvW1 <= $DFFF) then
                    BpJsonFail(aReader, 'Unpaired low surrogate')
                  else
                    AppendWideChar(lvW1);
                end;
            else
              BpJsonFail(aReader, 'Invalid escape sequence');
            end;
            lvSeg := aReader.Cur;
          end;
        #0: BpJsonFail(aReader, 'Unterminated string');
        #1..#31: BpJsonFail(aReader, 'Unescaped control character in string');
      else
        Inc(aReader.Cur);
      end;
  finally
    lvSb.Free;
  end;
end;

function BpJsonParseNumber(var aReader: TbpJsonReader): TbpJsonValue;
var
  lvStart: PChar;
  lvToken: string;
  lvIsFloat: Boolean;
  lvInt: Int64;
  lvFloat: Double;
  lvErr: Integer;
begin
  lvStart := aReader.Cur;
  if aReader.Cur^ = '-' then
    Inc(aReader.Cur);
  case aReader.Cur^ of
    '0':
      begin
        Inc(aReader.Cur);
        if (aReader.Cur^ >= '0') and (aReader.Cur^ <= '9') then
          BpJsonFail(aReader, 'Leading zeros are not allowed');
      end;
    '1'..'9':
      while (aReader.Cur^ >= '0') and (aReader.Cur^ <= '9') do
        Inc(aReader.Cur);
  else
    BpJsonFail(aReader, 'Invalid number');
  end;
  lvIsFloat := False;
  if aReader.Cur^ = '.' then
  begin
    Inc(aReader.Cur);
    if (aReader.Cur^ < '0') or (aReader.Cur^ > '9') then
      BpJsonFail(aReader, 'Digit expected after decimal point');
    while (aReader.Cur^ >= '0') and (aReader.Cur^ <= '9') do
      Inc(aReader.Cur);
    lvIsFloat := True;
  end;
  if (aReader.Cur^ = 'e') or (aReader.Cur^ = 'E') then
  begin
    Inc(aReader.Cur);
    if (aReader.Cur^ = '+') or (aReader.Cur^ = '-') then
      Inc(aReader.Cur);
    if (aReader.Cur^ < '0') or (aReader.Cur^ > '9') then
      BpJsonFail(aReader, 'Digit expected in exponent');
    while (aReader.Cur^ >= '0') and (aReader.Cur^ <= '9') do
      Inc(aReader.Cur);
    lvIsFloat := True;
  end;
  SetString(lvToken, lvStart, aReader.Cur - lvStart);
  if not lvIsFloat then
  begin
    Val(lvToken, lvInt, lvErr);
    if lvErr = 0 then
    begin
      Result := TbpJsonValue.CreateInt(lvInt);
      Exit;
    end;
    // too big for Int64, keep the value as a float
  end;
  Val(lvToken, lvFloat, lvErr);
  if lvErr <> 0 then
    BpJsonFail(aReader, 'Number out of range');
  Result := TbpJsonValue.CreateFloat(lvFloat);
end;

procedure BpJsonExpectWord(var aReader: TbpJsonReader; const aWord: string);
var
  lvI: Integer;
begin
  for lvI := 1 to Length(aWord) do
  begin
    if aReader.Cur^ <> aWord[lvI] then
      BpJsonFail(aReader, 'Invalid JSON value');
    Inc(aReader.Cur);
  end;
end;

function BpJsonParseValue(var aReader: TbpJsonReader): TbpJsonValue; forward;

function BpJsonParseObject(var aReader: TbpJsonReader): TbpJsonValue;
var
  lvName: string;
begin
  // aReader.Cur is on the '{'
  Inc(aReader.Cur);
  Inc(aReader.Depth);
  if aReader.Depth > gcBpJsonMaxDepth then
    BpJsonFail(aReader, 'JSON nested too deeply');
  Result := TbpJsonValue.CreateObject;
  try
    BpJsonSkipWhite(aReader);
    if aReader.Cur^ = '}' then
      Inc(aReader.Cur)
    else
      while True do
      begin
        BpJsonSkipWhite(aReader);
        if aReader.Cur^ <> '"' then
          BpJsonFail(aReader, 'Member name expected');
        lvName := BpJsonParseString(aReader);
        BpJsonSkipWhite(aReader);
        if aReader.Cur^ <> ':' then
          BpJsonFail(aReader, '":" expected');
        Inc(aReader.Cur);
        Result.InternalPut(lvName, BpJsonParseValue(aReader));
        BpJsonSkipWhite(aReader);
        case aReader.Cur^ of
          ',': Inc(aReader.Cur);
          '}': begin Inc(aReader.Cur); Break; end;
        else
          BpJsonFail(aReader, '"," or "}" expected');
        end;
      end;
    Dec(aReader.Depth);
  except
    Result.Free;
    raise;
  end;
end;

function BpJsonParseArray(var aReader: TbpJsonReader): TbpJsonValue;
begin
  // aReader.Cur is on the '['
  Inc(aReader.Cur);
  Inc(aReader.Depth);
  if aReader.Depth > gcBpJsonMaxDepth then
    BpJsonFail(aReader, 'JSON nested too deeply');
  Result := TbpJsonValue.CreateArray;
  try
    BpJsonSkipWhite(aReader);
    if aReader.Cur^ = ']' then
      Inc(aReader.Cur)
    else
      while True do
      begin
        Result.InternalAdd('', BpJsonParseValue(aReader));
        BpJsonSkipWhite(aReader);
        case aReader.Cur^ of
          ',': Inc(aReader.Cur);
          ']': begin Inc(aReader.Cur); Break; end;
        else
          BpJsonFail(aReader, '"," or "]" expected');
        end;
      end;
    Dec(aReader.Depth);
  except
    Result.Free;
    raise;
  end;
end;

function BpJsonParseValue(var aReader: TbpJsonReader): TbpJsonValue;
begin
  Result := nil;
  BpJsonSkipWhite(aReader);
  case aReader.Cur^ of
    '{': Result := BpJsonParseObject(aReader);
    '[': Result := BpJsonParseArray(aReader);
    '"': Result := TbpJsonValue.CreateStr(BpJsonParseString(aReader));
    't':
      begin
        BpJsonExpectWord(aReader, 'true');
        Result := TbpJsonValue.CreateBool(True);
      end;
    'f':
      begin
        BpJsonExpectWord(aReader, 'false');
        Result := TbpJsonValue.CreateBool(False);
      end;
    'n':
      begin
        BpJsonExpectWord(aReader, 'null');
        Result := TbpJsonValue.CreateNull;
      end;
    '-', '0'..'9': Result := BpJsonParseNumber(aReader);
    #0: BpJsonFail(aReader, 'Unexpected end of JSON');
  else
    BpJsonFail(aReader, 'Unexpected character');
  end;
end;

// JSON floats always use '.' no matter what the locale says
function BpJsonFloatToStr(const aValue: Double): string;
var
  lvFs: TFormatSettings;
begin
  if IsNan(aValue) or IsInfinite(aValue) then
    raise EbpJson.Create('NaN and Infinity cannot be written as JSON');
  FillChar(lvFs, SizeOf(lvFs), 0);
  lvFs.DecimalSeparator := '.';
  Result := FloatToStr(aValue, lvFs);
end;

procedure BpJsonAppendQuoted(aSb: TbpStringBuilder; const aValue: string;
  aEscapeNonAscii: Boolean);
var
  lvI, lvLen, lvRun: Integer;
  lvC: Char;
{$IF CompilerVersion < 20.0}
  lvWide: WideString;
  lvWC: WideChar;
{$IFEND}

  procedure AppendEscape(aOrd: Integer);
  begin
    case aOrd of
      Ord('"'): aSb.Append('\"');
      Ord('\'): aSb.Append('\\');
      8: aSb.Append('\b');
      9: aSb.Append('\t');
      10: aSb.Append('\n');
      12: aSb.Append('\f');
      13: aSb.Append('\r');
    else
      aSb.Append('\u').Append(IntToHex(aOrd, 4));
    end;
  end;

begin
  aSb.Append('"');
  if aEscapeNonAscii then
  begin
    // escape everything outside printable ASCII, output needs no codepage
{$IF CompilerVersion >= 20.0}
    for lvI := 1 to Length(aValue) do
    begin
      lvC := aValue[lvI];
      if (lvC >= #32) and (lvC < #127) and (lvC <> '"') and (lvC <> '\') then
        aSb.Append(lvC)
      else
        AppendEscape(Ord(lvC));
    end;
{$ELSE}
    lvWide := WideString(aValue);
    for lvI := 1 to Length(lvWide) do
    begin
      lvWC := lvWide[lvI];
      if (lvWC >= #32) and (lvWC < #127) and (lvWC <> '"') and (lvWC <> '\') then
        aSb.Append(Char(lvWC))
      else
        AppendEscape(Ord(lvWC));
    end;
{$IFEND}
  end
  else
  begin
    // copy runs of plain chars, escape only what RFC 8259 requires
    lvLen := Length(aValue);
    lvRun := 1;
    for lvI := 1 to lvLen do
    begin
      lvC := aValue[lvI];
      if (lvC < #32) or (lvC = '"') or (lvC = '\') then
      begin
        if lvI > lvRun then
          aSb.Append(Copy(aValue, lvRun, lvI - lvRun));
        AppendEscape(Ord(lvC));
        lvRun := lvI + 1;
      end;
    end;
    if lvLen >= lvRun then
      aSb.Append(Copy(aValue, lvRun, lvLen - lvRun + 1));
  end;
  aSb.Append('"');
end;

{ TbpJsonValue }

constructor TbpJsonValue.Create;
begin
  inherited Create;
  FKind := bjkNull;
end;

destructor TbpJsonValue.Destroy;
begin
  Clear;
  inherited Destroy;
end;

class function TbpJsonValue.CreateNull: TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
end;

class function TbpJsonValue.CreateBool(aValue: Boolean): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkBool;
  Result.FBool := aValue;
end;

class function TbpJsonValue.CreateInt(aValue: Int64): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkInt;
  Result.FInt := aValue;
end;

class function TbpJsonValue.CreateFloat(aValue: Double): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkFloat;
  Result.FFloat := aValue;
end;

class function TbpJsonValue.CreateStr(const aValue: string): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkString;
  Result.FStr := aValue;
end;

class function TbpJsonValue.CreateArray: TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkArray;
end;

class function TbpJsonValue.CreateObject: TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkObject;
end;

class function TbpJsonValue.Parse(const aJson: string): TbpJsonValue;
var
  lvReader: TbpJsonReader;
begin
  lvReader.Start := PChar(aJson);
  lvReader.Cur := lvReader.Start;
  lvReader.Depth := 0;
  // tolerate a leading BOM
{$IF CompilerVersion >= 20.0}
  if lvReader.Cur^ = #$FEFF then
    Inc(lvReader.Cur);
{$ELSE}
  if (lvReader.Cur^ = #$EF) and (lvReader.Cur[1] = #$BB) and
    (lvReader.Cur[2] = #$BF) then
    Inc(lvReader.Cur, 3);
{$IFEND}
  Result := BpJsonParseValue(lvReader);
  try
    BpJsonSkipWhite(lvReader);
    if lvReader.Cur^ <> #0 then
      BpJsonFail(lvReader, 'Unexpected text after the JSON value');
  except
    Result.Free;
    raise;
  end;
end;

class function TbpJsonValue.TryParse(const aJson: string;
  out aValue: TbpJsonValue): Boolean;
begin
  try
    aValue := Parse(aJson);
    Result := True;
  except
    on EbpJson do
    begin
      aValue := nil;
      Result := False;
    end;
  end;
end;

function TbpJsonValue.Clone: TbpJsonValue;
var
  lvI: Integer;
begin
  Result := TbpJsonValue.Create;
  try
    Result.FKind := FKind;
    Result.FBool := FBool;
    Result.FInt := FInt;
    Result.FFloat := FFloat;
    Result.FStr := FStr;
    for lvI := 0 to FCount - 1 do
      if FKind = bjkObject then
        Result.InternalAdd(FNames[lvI], FItems[lvI].Clone)
      else
        Result.InternalAdd('', FItems[lvI].Clone);
  except
    Result.Free;
    raise;
  end;
end;

function TbpJsonValue.KindName: string;
begin
  Result := gcBpJsonKindNames[FKind];
end;

function TbpJsonValue.IsNull: Boolean;
begin
  Result := FKind = bjkNull;
end;

procedure TbpJsonValue.RequireKind(aKind: TbpJsonKind);
begin
  if FKind <> aKind then
    raise EbpJson.CreateFmt('Value is %s, %s expected',
      [gcBpJsonKindNames[FKind], gcBpJsonKindNames[aKind]]);
end;

function TbpJsonValue.AsBool: Boolean;
begin
  RequireKind(bjkBool);
  Result := FBool;
end;

function TbpJsonValue.AsInt: Int64;
begin
  RequireKind(bjkInt);
  Result := FInt;
end;

function TbpJsonValue.AsFloat: Double;
begin
  if FKind = bjkInt then
    Result := FInt
  else
  begin
    RequireKind(bjkFloat);
    Result := FFloat;
  end;
end;

function TbpJsonValue.AsStr: string;
begin
  RequireKind(bjkString);
  Result := FStr;
end;

function TbpJsonValue.GetItem(aIndex: Integer): TbpJsonValue;
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EbpJson.CreateFmt('Index %d out of range (count %d)',
      [aIndex, FCount]);
  Result := FItems[aIndex];
end;

function TbpJsonValue.GetName(aIndex: Integer): string;
begin
  RequireKind(bjkObject);
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EbpJson.CreateFmt('Index %d out of range (count %d)',
      [aIndex, FCount]);
  Result := FNames[aIndex];
end;

function TbpJsonValue.IndexOfName(const aName: string): Integer;
begin
  for Result := 0 to FCount - 1 do
    if FNames[Result] = aName then
      Exit;
  Result := -1;
end;

procedure TbpJsonValue.InternalAdd(const aName: string; aChild: TbpJsonValue);
var
  lvCap: Integer;
begin
  if FCount = Length(FItems) then
  begin
    lvCap := Length(FItems) * 2;
    if lvCap < 4 then
      lvCap := 4;
    SetLength(FItems, lvCap);
    if FKind = bjkObject then
      SetLength(FNames, lvCap);
  end;
  FItems[FCount] := aChild;
  if FKind = bjkObject then
    FNames[FCount] := aName;
  Inc(FCount);
end;

procedure TbpJsonValue.InternalPut(const aName: string; aChild: TbpJsonValue);
var
  lvIdx: Integer;
begin
  lvIdx := IndexOfName(aName);
  if lvIdx >= 0 then
  begin
    FItems[lvIdx].Free;
    FItems[lvIdx] := aChild;
  end
  else
    InternalAdd(aName, aChild);
end;

function TbpJsonValue.MemberOrFail(const aName: string): TbpJsonValue;
begin
  Result := Find(aName);
  if Result = nil then
    raise EbpJson.CreateFmt('Member "%s" not found', [aName]);
end;

procedure TbpJsonValue.Delete(aIndex: Integer);
var
  lvI: Integer;
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EbpJson.CreateFmt('Index %d out of range (count %d)',
      [aIndex, FCount]);
  FItems[aIndex].Free;
  for lvI := aIndex to FCount - 2 do
  begin
    FItems[lvI] := FItems[lvI + 1];
    if FKind = bjkObject then
      FNames[lvI] := FNames[lvI + 1];
  end;
  Dec(FCount);
  FItems[FCount] := nil;
  if FKind = bjkObject then
    FNames[FCount] := '';
end;

procedure TbpJsonValue.Clear;
var
  lvI: Integer;
begin
  for lvI := 0 to FCount - 1 do
    FItems[lvI].Free;
  FCount := 0;
  SetLength(FItems, 0);
  SetLength(FNames, 0);
end;

procedure TbpJsonValue.AddNull;
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateNull);
end;

procedure TbpJsonValue.AddBool(aValue: Boolean);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateBool(aValue));
end;

procedure TbpJsonValue.AddInt(aValue: Int64);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateInt(aValue));
end;

procedure TbpJsonValue.AddFloat(aValue: Double);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateFloat(aValue));
end;

procedure TbpJsonValue.AddStr(const aValue: string);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateStr(aValue));
end;

function TbpJsonValue.AddArray: TbpJsonValue;
begin
  RequireKind(bjkArray);
  Result := CreateArray;
  InternalAdd('', Result);
end;

function TbpJsonValue.AddObject: TbpJsonValue;
begin
  RequireKind(bjkArray);
  Result := CreateObject;
  InternalAdd('', Result);
end;

function TbpJsonValue.Find(const aName: string): TbpJsonValue;
var
  lvIdx: Integer;
begin
  RequireKind(bjkObject);
  lvIdx := IndexOfName(aName);
  if lvIdx >= 0 then
    Result := FItems[lvIdx]
  else
    Result := nil;
end;

function TbpJsonValue.Contains(const aName: string): Boolean;
begin
  RequireKind(bjkObject);
  Result := IndexOfName(aName) >= 0;
end;

function TbpJsonValue.Remove(const aName: string): Boolean;
var
  lvIdx: Integer;
begin
  RequireKind(bjkObject);
  lvIdx := IndexOfName(aName);
  Result := lvIdx >= 0;
  if Result then
    Delete(lvIdx);
end;

function TbpJsonValue.GetBool(const aName: string): Boolean;
begin
  Result := MemberOrFail(aName).AsBool;
end;

function TbpJsonValue.GetBoolDef(const aName: string;
  aDefault: Boolean): Boolean;
begin
  if not TryGetBool(aName, Result) then
    Result := aDefault;
end;

function TbpJsonValue.TryGetBool(const aName: string;
  out aValue: Boolean): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(aName);
  Result := (lvValue <> nil) and (lvValue.FKind = bjkBool);
  if Result then
    aValue := lvValue.FBool
  else
    aValue := False;
end;

function TbpJsonValue.GetInt(const aName: string): Int64;
begin
  Result := MemberOrFail(aName).AsInt;
end;

function TbpJsonValue.GetIntDef(const aName: string; aDefault: Int64): Int64;
begin
  if not TryGetInt(aName, Result) then
    Result := aDefault;
end;

function TbpJsonValue.TryGetInt(const aName: string;
  out aValue: Int64): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(aName);
  Result := (lvValue <> nil) and (lvValue.FKind = bjkInt);
  if Result then
    aValue := lvValue.FInt
  else
    aValue := 0;
end;

function TbpJsonValue.GetFloat(const aName: string): Double;
begin
  Result := MemberOrFail(aName).AsFloat;
end;

function TbpJsonValue.GetFloatDef(const aName: string;
  aDefault: Double): Double;
begin
  if not TryGetFloat(aName, Result) then
    Result := aDefault;
end;

function TbpJsonValue.TryGetFloat(const aName: string;
  out aValue: Double): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(aName);
  Result := (lvValue <> nil) and
    ((lvValue.FKind = bjkFloat) or (lvValue.FKind = bjkInt));
  if Result then
    aValue := lvValue.AsFloat
  else
    aValue := 0;
end;

function TbpJsonValue.GetStr(const aName: string): string;
begin
  Result := MemberOrFail(aName).AsStr;
end;

function TbpJsonValue.GetStrDef(const aName, aDefault: string): string;
begin
  if not TryGetStr(aName, Result) then
    Result := aDefault;
end;

function TbpJsonValue.TryGetStr(const aName: string;
  out aValue: string): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(aName);
  Result := (lvValue <> nil) and (lvValue.FKind = bjkString);
  if Result then
    aValue := lvValue.FStr
  else
    aValue := '';
end;

procedure TbpJsonValue.SetNull(const aName: string);
begin
  RequireKind(bjkObject);
  InternalPut(aName, CreateNull);
end;

procedure TbpJsonValue.SetBool(const aName: string; aValue: Boolean);
begin
  RequireKind(bjkObject);
  InternalPut(aName, CreateBool(aValue));
end;

procedure TbpJsonValue.SetInt(const aName: string; aValue: Int64);
begin
  RequireKind(bjkObject);
  InternalPut(aName, CreateInt(aValue));
end;

procedure TbpJsonValue.SetFloat(const aName: string; aValue: Double);
begin
  RequireKind(bjkObject);
  InternalPut(aName, CreateFloat(aValue));
end;

procedure TbpJsonValue.SetStr(const aName, aValue: string);
begin
  RequireKind(bjkObject);
  InternalPut(aName, CreateStr(aValue));
end;

function TbpJsonValue.SetArray(const aName: string): TbpJsonValue;
begin
  RequireKind(bjkObject);
  Result := CreateArray;
  InternalPut(aName, Result);
end;

function TbpJsonValue.SetObject(const aName: string): TbpJsonValue;
begin
  RequireKind(bjkObject);
  Result := CreateObject;
  InternalPut(aName, Result);
end;

function TbpJsonValue.FindPath(const aPath: string): TbpJsonValue;
var
  lvPos, lvLen, lvStart, lvIdx: Integer;
  lvName: string;
begin
  Result := Self;
  lvLen := Length(aPath);
  if lvLen = 0 then
  begin
    Result := nil;
    Exit;
  end;
  lvPos := 1;
  while (lvPos <= lvLen) and (Result <> nil) do
    case aPath[lvPos] of
      '.': Inc(lvPos);
      '[':
        begin
          // numeric index into an array
          Inc(lvPos);
          lvStart := lvPos;
          lvIdx := 0;
          while (lvPos <= lvLen) and (aPath[lvPos] >= '0') and
            (aPath[lvPos] <= '9') do
          begin
            lvIdx := lvIdx * 10 + Ord(aPath[lvPos]) - Ord('0');
            Inc(lvPos);
          end;
          if (lvPos > lvLen) or (aPath[lvPos] <> ']') or (lvPos = lvStart) then
          begin
            Result := nil;
            Exit;
          end;
          Inc(lvPos);
          if (Result.FKind = bjkArray) and (lvIdx < Result.FCount) then
            Result := Result.FItems[lvIdx]
          else
            Result := nil;
        end;
    else
      begin
        // member name up to the next '.' or '['
        lvStart := lvPos;
        while (lvPos <= lvLen) and (aPath[lvPos] <> '.') and
          (aPath[lvPos] <> '[') do
          Inc(lvPos);
        lvName := Copy(aPath, lvStart, lvPos - lvStart);
        if Result.FKind = bjkObject then
        begin
          lvIdx := Result.IndexOfName(lvName);
          if lvIdx >= 0 then
            Result := Result.FItems[lvIdx]
          else
            Result := nil;
        end
        else
          Result := nil;
      end;
    end;
end;

function TbpJsonValue.PathBoolDef(const aPath: string;
  aDefault: Boolean): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(aPath);
  if (lvValue <> nil) and (lvValue.FKind = bjkBool) then
    Result := lvValue.FBool
  else
    Result := aDefault;
end;

function TbpJsonValue.PathIntDef(const aPath: string; aDefault: Int64): Int64;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(aPath);
  if (lvValue <> nil) and (lvValue.FKind = bjkInt) then
    Result := lvValue.FInt
  else
    Result := aDefault;
end;

function TbpJsonValue.PathFloatDef(const aPath: string;
  aDefault: Double): Double;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(aPath);
  if (lvValue <> nil) and
    ((lvValue.FKind = bjkFloat) or (lvValue.FKind = bjkInt)) then
    Result := lvValue.AsFloat
  else
    Result := aDefault;
end;

function TbpJsonValue.PathStrDef(const aPath, aDefault: string): string;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(aPath);
  if (lvValue <> nil) and (lvValue.FKind = bjkString) then
    Result := lvValue.FStr
  else
    Result := aDefault;
end;

procedure TbpJsonValue.WriteTo(aSb: TbpStringBuilder;
  aEscapeNonAscii: Boolean; aIndentSize, aLevel: Integer);
var
  lvI: Integer;
  lvPretty: Boolean;

  procedure Indent(aDepth: Integer);
  begin
    aSb.Append(#13#10);
    if aDepth * aIndentSize > 0 then
      aSb.Append(' ', aDepth * aIndentSize);
  end;

begin
  lvPretty := aIndentSize >= 0;
  case FKind of
    bjkNull: aSb.Append('null');
    bjkBool:
      if FBool then
        aSb.Append('true')
      else
        aSb.Append('false');
    bjkInt: aSb.Append(FInt);
    bjkFloat: aSb.Append(BpJsonFloatToStr(FFloat));
    bjkString: BpJsonAppendQuoted(aSb, FStr, aEscapeNonAscii);
    bjkArray:
      if FCount = 0 then
        aSb.Append('[]')
      else
      begin
        aSb.Append('[');
        for lvI := 0 to FCount - 1 do
        begin
          if lvI > 0 then
            aSb.Append(',');
          if lvPretty then
            Indent(aLevel + 1);
          FItems[lvI].WriteTo(aSb, aEscapeNonAscii, aIndentSize, aLevel + 1);
        end;
        if lvPretty then
          Indent(aLevel);
        aSb.Append(']');
      end;
    bjkObject:
      if FCount = 0 then
        aSb.Append('{}')
      else
      begin
        aSb.Append('{');
        for lvI := 0 to FCount - 1 do
        begin
          if lvI > 0 then
            aSb.Append(',');
          if lvPretty then
            Indent(aLevel + 1);
          BpJsonAppendQuoted(aSb, FNames[lvI], aEscapeNonAscii);
          aSb.Append(':');
          if lvPretty then
            aSb.Append(' ');
          FItems[lvI].WriteTo(aSb, aEscapeNonAscii, aIndentSize, aLevel + 1);
        end;
        if lvPretty then
          Indent(aLevel);
        aSb.Append('}');
      end;
  end;
end;

function TbpJsonValue.ToJson(aEscapeNonAscii: Boolean): string;
var
  lvSb: TbpStringBuilder;
begin
  lvSb := TbpStringBuilder.Create(256);
  try
    WriteTo(lvSb, aEscapeNonAscii, -1, 0);
    Result := lvSb.ToString;
  finally
    lvSb.Free;
  end;
end;

function TbpJsonValue.ToJsonPretty(aIndentSize: Integer;
  aEscapeNonAscii: Boolean): string;
var
  lvSb: TbpStringBuilder;
begin
  if aIndentSize < 0 then
    aIndentSize := 0;
  lvSb := TbpStringBuilder.Create(256);
  try
    WriteTo(lvSb, aEscapeNonAscii, aIndentSize, 0);
    Result := lvSb.ToString;
  finally
    lvSb.Free;
  end;
end;

end.
