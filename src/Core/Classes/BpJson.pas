unit BpJson;

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

interface

uses
  SysUtils, BpStringBuilder;

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
    function GetItem(AIndex: Integer): TbpJsonValue;
    function GetName(AIndex: Integer): string;
    procedure RequireKind(AKind: TbpJsonKind);
    function IndexOfName(const AName: string): Integer;
    procedure InternalAdd(const AName: string; AChild: TbpJsonValue);
    procedure InternalPut(const AName: string; AChild: TbpJsonValue);
    function MemberOrFail(const AName: string): TbpJsonValue;
    procedure WriteTo(ASb: TbpStringBuilder; AEscapeNonAscii: Boolean;
      AIndentSize, ALevel: Integer);
  public
    constructor Create;  // a null value
    destructor Destroy; override;

    // building blocks; add the result to a container or free it yourself
    class function CreateNull: TbpJsonValue;
    class function CreateBool(AValue: Boolean): TbpJsonValue;
    class function CreateInt(AValue: Int64): TbpJsonValue;
    class function CreateFloat(AValue: Double): TbpJsonValue;
    class function CreateStr(const AValue: string): TbpJsonValue;
    class function CreateArray: TbpJsonValue;
    class function CreateObject: TbpJsonValue;

    // Parse raises EbpJson with line/position, TryParse returns False
    class function Parse(const AJson: string): TbpJsonValue;
    class function TryParse(const AJson: string;
      out AValue: TbpJsonValue): Boolean;

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
    property Items[AIndex: Integer]: TbpJsonValue read GetItem;
    property Names[AIndex: Integer]: string read GetName;
    procedure Delete(AIndex: Integer);
    procedure Clear;

    // array building; the value must be an array,
    // AddArray and AddObject return the new empty container
    procedure AddNull;
    procedure AddBool(AValue: Boolean);
    procedure AddInt(AValue: Int64);
    procedure AddFloat(AValue: Double);
    procedure AddStr(const AValue: string);
    function AddArray: TbpJsonValue;
    function AddObject: TbpJsonValue;

    // object member access; the value must be an object
    function Find(const AName: string): TbpJsonValue;  // nil when missing
    function Contains(const AName: string): Boolean;
    function Remove(const AName: string): Boolean;

    function GetBool(const AName: string): Boolean;
    function GetBoolDef(const AName: string; ADefault: Boolean): Boolean;
    function TryGetBool(const AName: string; out AValue: Boolean): Boolean;
    function GetInt(const AName: string): Int64;
    function GetIntDef(const AName: string; ADefault: Int64): Int64;
    function TryGetInt(const AName: string; out AValue: Int64): Boolean;
    function GetFloat(const AName: string): Double;
    function GetFloatDef(const AName: string; ADefault: Double): Double;
    function TryGetFloat(const AName: string; out AValue: Double): Boolean;
    function GetStr(const AName: string): string;
    function GetStrDef(const AName, ADefault: string): string;
    function TryGetStr(const AName: string; out AValue: string): Boolean;

    // create-or-replace member; SetArray and SetObject return the container
    procedure SetNull(const AName: string);
    procedure SetBool(const AName: string; AValue: Boolean);
    procedure SetInt(const AName: string; AValue: Int64);
    procedure SetFloat(const AName: string; AValue: Double);
    procedure SetStr(const AName, AValue: string);
    function SetArray(const AName: string): TbpJsonValue;
    function SetObject(const AName: string): TbpJsonValue;

    // dotted path with [n] indexing, e.g. 'data.items[0].name';
    // nil (or the default) when any step is missing or of the wrong kind
    function FindPath(const APath: string): TbpJsonValue;
    function PathBoolDef(const APath: string; ADefault: Boolean): Boolean;
    function PathIntDef(const APath: string; ADefault: Int64): Int64;
    function PathFloatDef(const APath: string; ADefault: Double): Double;
    function PathStrDef(const APath, ADefault: string): string;

    // writers; AEscapeNonAscii escapes every char above #127 as \uXXXX
    function ToJson(AEscapeNonAscii: Boolean = False): string;
    function ToJsonPretty(AIndentSize: Integer = 2;
      AEscapeNonAscii: Boolean = False): string;
  end;

implementation

uses
  Math;

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

procedure BpJsonFail(const AReader: TbpJsonReader; const AMsg: string);
var
  lvP: PChar;
  lvLine, lvPos: Integer;
begin
  lvLine := 1;
  lvPos := 1;
  lvP := AReader.Start;
  while lvP < AReader.Cur do
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
  raise EbpJson.CreateFmt('%s at line %d, position %d', [AMsg, lvLine, lvPos]);
end;

procedure BpJsonSkipWhite(var AReader: TbpJsonReader);
begin
  while True do
    case AReader.Cur^ of
      #9, #10, #13, ' ': Inc(AReader.Cur);
    else
      Break;
    end;
end;

// parses exactly four hex digits, the XXXX of a \uXXXX escape
function BpJsonHexQuad(var AReader: TbpJsonReader): Integer;
var
  lvI, lvDigit: Integer;
begin
  Result := 0;
  lvDigit := 0;
  for lvI := 1 to 4 do
  begin
    case AReader.Cur^ of
      '0'..'9': lvDigit := Ord(AReader.Cur^) - Ord('0');
      'a'..'f': lvDigit := Ord(AReader.Cur^) - Ord('a') + 10;
      'A'..'F': lvDigit := Ord(AReader.Cur^) - Ord('A') + 10;
    else
      BpJsonFail(AReader, 'Invalid \u escape');
    end;
    Result := Result * 16 + lvDigit;
    Inc(AReader.Cur);
  end;
end;

function BpJsonParseString(var AReader: TbpJsonReader): string;
var
  lvSb: TbpStringBuilder;
  lvSeg: PChar;
  lvW1, lvW2: Integer;
{$IF CompilerVersion < 20.0}
  lvWide: WideString;
{$IFEND}

  procedure FlushSeg(AUpTo: PChar);
  var
    lvChunk: string;
  begin
    if AUpTo > lvSeg then
    begin
      SetString(lvChunk, lvSeg, AUpTo - lvSeg);
      lvSb.Append(lvChunk);
    end;
  end;

  procedure AppendWideChar(AOrd: Integer);
  begin
{$IF CompilerVersion >= 20.0}
    lvSb.Append(Char(AOrd));
{$ELSE}
    SetLength(lvWide, 1);
    lvWide[1] := WideChar(AOrd);
    lvSb.Append(string(lvWide));
{$IFEND}
  end;

  procedure AppendSurrogatePair(AHi, ALo: Integer);
  begin
{$IF CompilerVersion >= 20.0}
    lvSb.Append(Char(AHi));
    lvSb.Append(Char(ALo));
{$ELSE}
    SetLength(lvWide, 2);
    lvWide[1] := WideChar(AHi);
    lvWide[2] := WideChar(ALo);
    lvSb.Append(string(lvWide));
{$IFEND}
  end;

begin
  Result := '';
  // AReader.Cur is on the opening quote
  Inc(AReader.Cur);
  lvSeg := AReader.Cur;
  // fast path: a string without escapes is one SetString
  while True do
    case AReader.Cur^ of
      '"':
        begin
          SetString(Result, lvSeg, AReader.Cur - lvSeg);
          Inc(AReader.Cur);
          Exit;
        end;
      '\': Break;
      #0: BpJsonFail(AReader, 'Unterminated string');
      #1..#31: BpJsonFail(AReader, 'Unescaped control character in string');
    else
      Inc(AReader.Cur);
    end;
  // slow path: copy segments between escapes and decode the escapes
  lvSb := TbpStringBuilder.Create(64);
  try
    while True do
      case AReader.Cur^ of
        '"':
          begin
            FlushSeg(AReader.Cur);
            Inc(AReader.Cur);
            Result := lvSb.ToString;
            Exit;
          end;
        '\':
          begin
            FlushSeg(AReader.Cur);
            Inc(AReader.Cur);
            case AReader.Cur^ of
              '"', '\', '/':
                begin
                  lvSb.Append(Char(AReader.Cur^));
                  Inc(AReader.Cur);
                end;
              'b': begin lvSb.Append(#8); Inc(AReader.Cur); end;
              't': begin lvSb.Append(#9); Inc(AReader.Cur); end;
              'n': begin lvSb.Append(#10); Inc(AReader.Cur); end;
              'f': begin lvSb.Append(#12); Inc(AReader.Cur); end;
              'r': begin lvSb.Append(#13); Inc(AReader.Cur); end;
              'u':
                begin
                  Inc(AReader.Cur);
                  lvW1 := BpJsonHexQuad(AReader);
                  if (lvW1 >= $D800) and (lvW1 <= $DBFF) then
                  begin
                    // a high surrogate must be followed by an escaped low one
                    if (AReader.Cur^ = '\') and (AReader.Cur[1] = 'u') then
                    begin
                      Inc(AReader.Cur, 2);
                      lvW2 := BpJsonHexQuad(AReader);
                      if (lvW2 < $DC00) or (lvW2 > $DFFF) then
                        BpJsonFail(AReader, 'Invalid surrogate pair');
                      AppendSurrogatePair(lvW1, lvW2);
                    end
                    else
                      BpJsonFail(AReader, 'Unpaired high surrogate');
                  end
                  else if (lvW1 >= $DC00) and (lvW1 <= $DFFF) then
                    BpJsonFail(AReader, 'Unpaired low surrogate')
                  else
                    AppendWideChar(lvW1);
                end;
            else
              BpJsonFail(AReader, 'Invalid escape sequence');
            end;
            lvSeg := AReader.Cur;
          end;
        #0: BpJsonFail(AReader, 'Unterminated string');
        #1..#31: BpJsonFail(AReader, 'Unescaped control character in string');
      else
        Inc(AReader.Cur);
      end;
  finally
    lvSb.Free;
  end;
end;

function BpJsonParseNumber(var AReader: TbpJsonReader): TbpJsonValue;
var
  lvStart: PChar;
  lvToken: string;
  lvIsFloat: Boolean;
  lvInt: Int64;
  lvFloat: Double;
  lvErr: Integer;
begin
  lvStart := AReader.Cur;
  if AReader.Cur^ = '-' then
    Inc(AReader.Cur);
  case AReader.Cur^ of
    '0':
      begin
        Inc(AReader.Cur);
        if (AReader.Cur^ >= '0') and (AReader.Cur^ <= '9') then
          BpJsonFail(AReader, 'Leading zeros are not allowed');
      end;
    '1'..'9':
      while (AReader.Cur^ >= '0') and (AReader.Cur^ <= '9') do
        Inc(AReader.Cur);
  else
    BpJsonFail(AReader, 'Invalid number');
  end;
  lvIsFloat := False;
  if AReader.Cur^ = '.' then
  begin
    Inc(AReader.Cur);
    if (AReader.Cur^ < '0') or (AReader.Cur^ > '9') then
      BpJsonFail(AReader, 'Digit expected after decimal point');
    while (AReader.Cur^ >= '0') and (AReader.Cur^ <= '9') do
      Inc(AReader.Cur);
    lvIsFloat := True;
  end;
  if (AReader.Cur^ = 'e') or (AReader.Cur^ = 'E') then
  begin
    Inc(AReader.Cur);
    if (AReader.Cur^ = '+') or (AReader.Cur^ = '-') then
      Inc(AReader.Cur);
    if (AReader.Cur^ < '0') or (AReader.Cur^ > '9') then
      BpJsonFail(AReader, 'Digit expected in exponent');
    while (AReader.Cur^ >= '0') and (AReader.Cur^ <= '9') do
      Inc(AReader.Cur);
    lvIsFloat := True;
  end;
  SetString(lvToken, lvStart, AReader.Cur - lvStart);
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
    BpJsonFail(AReader, 'Number out of range');
  Result := TbpJsonValue.CreateFloat(lvFloat);
end;

procedure BpJsonExpectWord(var AReader: TbpJsonReader; const AWord: string);
var
  lvI: Integer;
begin
  for lvI := 1 to Length(AWord) do
  begin
    if AReader.Cur^ <> AWord[lvI] then
      BpJsonFail(AReader, 'Invalid JSON value');
    Inc(AReader.Cur);
  end;
end;

function BpJsonParseValue(var AReader: TbpJsonReader): TbpJsonValue; forward;

function BpJsonParseObject(var AReader: TbpJsonReader): TbpJsonValue;
var
  lvName: string;
begin
  // AReader.Cur is on the '{'
  Inc(AReader.Cur);
  Inc(AReader.Depth);
  if AReader.Depth > gcBpJsonMaxDepth then
    BpJsonFail(AReader, 'JSON nested too deeply');
  Result := TbpJsonValue.CreateObject;
  try
    BpJsonSkipWhite(AReader);
    if AReader.Cur^ = '}' then
      Inc(AReader.Cur)
    else
      while True do
      begin
        BpJsonSkipWhite(AReader);
        if AReader.Cur^ <> '"' then
          BpJsonFail(AReader, 'Member name expected');
        lvName := BpJsonParseString(AReader);
        BpJsonSkipWhite(AReader);
        if AReader.Cur^ <> ':' then
          BpJsonFail(AReader, '":" expected');
        Inc(AReader.Cur);
        Result.InternalPut(lvName, BpJsonParseValue(AReader));
        BpJsonSkipWhite(AReader);
        case AReader.Cur^ of
          ',': Inc(AReader.Cur);
          '}': begin Inc(AReader.Cur); Break; end;
        else
          BpJsonFail(AReader, '"," or "}" expected');
        end;
      end;
    Dec(AReader.Depth);
  except
    Result.Free;
    raise;
  end;
end;

function BpJsonParseArray(var AReader: TbpJsonReader): TbpJsonValue;
begin
  // AReader.Cur is on the '['
  Inc(AReader.Cur);
  Inc(AReader.Depth);
  if AReader.Depth > gcBpJsonMaxDepth then
    BpJsonFail(AReader, 'JSON nested too deeply');
  Result := TbpJsonValue.CreateArray;
  try
    BpJsonSkipWhite(AReader);
    if AReader.Cur^ = ']' then
      Inc(AReader.Cur)
    else
      while True do
      begin
        Result.InternalAdd('', BpJsonParseValue(AReader));
        BpJsonSkipWhite(AReader);
        case AReader.Cur^ of
          ',': Inc(AReader.Cur);
          ']': begin Inc(AReader.Cur); Break; end;
        else
          BpJsonFail(AReader, '"," or "]" expected');
        end;
      end;
    Dec(AReader.Depth);
  except
    Result.Free;
    raise;
  end;
end;

function BpJsonParseValue(var AReader: TbpJsonReader): TbpJsonValue;
begin
  Result := nil;
  BpJsonSkipWhite(AReader);
  case AReader.Cur^ of
    '{': Result := BpJsonParseObject(AReader);
    '[': Result := BpJsonParseArray(AReader);
    '"': Result := TbpJsonValue.CreateStr(BpJsonParseString(AReader));
    't':
      begin
        BpJsonExpectWord(AReader, 'true');
        Result := TbpJsonValue.CreateBool(True);
      end;
    'f':
      begin
        BpJsonExpectWord(AReader, 'false');
        Result := TbpJsonValue.CreateBool(False);
      end;
    'n':
      begin
        BpJsonExpectWord(AReader, 'null');
        Result := TbpJsonValue.CreateNull;
      end;
    '-', '0'..'9': Result := BpJsonParseNumber(AReader);
    #0: BpJsonFail(AReader, 'Unexpected end of JSON');
  else
    BpJsonFail(AReader, 'Unexpected character');
  end;
end;

// JSON floats always use '.' no matter what the locale says
function BpJsonFloatToStr(const AValue: Double): string;
var
  lvFs: TFormatSettings;
begin
  if IsNan(AValue) or IsInfinite(AValue) then
    raise EbpJson.Create('NaN and Infinity cannot be written as JSON');
  FillChar(lvFs, SizeOf(lvFs), 0);
  lvFs.DecimalSeparator := '.';
  Result := FloatToStr(AValue, lvFs);
end;

procedure BpJsonAppendQuoted(ASb: TbpStringBuilder; const AValue: string;
  AEscapeNonAscii: Boolean);
var
  lvI, lvLen, lvRun: Integer;
  lvC: Char;
{$IF CompilerVersion < 20.0}
  lvWide: WideString;
  lvWC: WideChar;
{$IFEND}

  procedure AppendEscape(AOrd: Integer);
  begin
    case AOrd of
      Ord('"'): ASb.Append('\"');
      Ord('\'): ASb.Append('\\');
      8: ASb.Append('\b');
      9: ASb.Append('\t');
      10: ASb.Append('\n');
      12: ASb.Append('\f');
      13: ASb.Append('\r');
    else
      ASb.Append('\u').Append(IntToHex(AOrd, 4));
    end;
  end;

begin
  ASb.Append('"');
  if AEscapeNonAscii then
  begin
    // escape everything outside printable ASCII, output needs no codepage
{$IF CompilerVersion >= 20.0}
    for lvI := 1 to Length(AValue) do
    begin
      lvC := AValue[lvI];
      if (lvC >= #32) and (lvC < #127) and (lvC <> '"') and (lvC <> '\') then
        ASb.Append(lvC)
      else
        AppendEscape(Ord(lvC));
    end;
{$ELSE}
    lvWide := WideString(AValue);
    for lvI := 1 to Length(lvWide) do
    begin
      lvWC := lvWide[lvI];
      if (lvWC >= #32) and (lvWC < #127) and (lvWC <> '"') and (lvWC <> '\') then
        ASb.Append(Char(lvWC))
      else
        AppendEscape(Ord(lvWC));
    end;
{$IFEND}
  end
  else
  begin
    // copy runs of plain chars, escape only what RFC 8259 requires
    lvLen := Length(AValue);
    lvRun := 1;
    for lvI := 1 to lvLen do
    begin
      lvC := AValue[lvI];
      if (lvC < #32) or (lvC = '"') or (lvC = '\') then
      begin
        if lvI > lvRun then
          ASb.Append(Copy(AValue, lvRun, lvI - lvRun));
        AppendEscape(Ord(lvC));
        lvRun := lvI + 1;
      end;
    end;
    if lvLen >= lvRun then
      ASb.Append(Copy(AValue, lvRun, lvLen - lvRun + 1));
  end;
  ASb.Append('"');
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

class function TbpJsonValue.CreateBool(AValue: Boolean): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkBool;
  Result.FBool := AValue;
end;

class function TbpJsonValue.CreateInt(AValue: Int64): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkInt;
  Result.FInt := AValue;
end;

class function TbpJsonValue.CreateFloat(AValue: Double): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkFloat;
  Result.FFloat := AValue;
end;

class function TbpJsonValue.CreateStr(const AValue: string): TbpJsonValue;
begin
  Result := TbpJsonValue.Create;
  Result.FKind := bjkString;
  Result.FStr := AValue;
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

class function TbpJsonValue.Parse(const AJson: string): TbpJsonValue;
var
  lvReader: TbpJsonReader;
begin
  lvReader.Start := PChar(AJson);
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

class function TbpJsonValue.TryParse(const AJson: string;
  out AValue: TbpJsonValue): Boolean;
begin
  try
    AValue := Parse(AJson);
    Result := True;
  except
    on EbpJson do
    begin
      AValue := nil;
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

procedure TbpJsonValue.RequireKind(AKind: TbpJsonKind);
begin
  if FKind <> AKind then
    raise EbpJson.CreateFmt('Value is %s, %s expected',
      [gcBpJsonKindNames[FKind], gcBpJsonKindNames[AKind]]);
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

function TbpJsonValue.GetItem(AIndex: Integer): TbpJsonValue;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EbpJson.CreateFmt('Index %d out of range (count %d)',
      [AIndex, FCount]);
  Result := FItems[AIndex];
end;

function TbpJsonValue.GetName(AIndex: Integer): string;
begin
  RequireKind(bjkObject);
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EbpJson.CreateFmt('Index %d out of range (count %d)',
      [AIndex, FCount]);
  Result := FNames[AIndex];
end;

function TbpJsonValue.IndexOfName(const AName: string): Integer;
begin
  for Result := 0 to FCount - 1 do
    if FNames[Result] = AName then
      Exit;
  Result := -1;
end;

procedure TbpJsonValue.InternalAdd(const AName: string; AChild: TbpJsonValue);
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
  FItems[FCount] := AChild;
  if FKind = bjkObject then
    FNames[FCount] := AName;
  Inc(FCount);
end;

procedure TbpJsonValue.InternalPut(const AName: string; AChild: TbpJsonValue);
var
  lvIdx: Integer;
begin
  lvIdx := IndexOfName(AName);
  if lvIdx >= 0 then
  begin
    FItems[lvIdx].Free;
    FItems[lvIdx] := AChild;
  end
  else
    InternalAdd(AName, AChild);
end;

function TbpJsonValue.MemberOrFail(const AName: string): TbpJsonValue;
begin
  Result := Find(AName);
  if Result = nil then
    raise EbpJson.CreateFmt('Member "%s" not found', [AName]);
end;

procedure TbpJsonValue.Delete(AIndex: Integer);
var
  lvI: Integer;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
    raise EbpJson.CreateFmt('Index %d out of range (count %d)',
      [AIndex, FCount]);
  FItems[AIndex].Free;
  for lvI := AIndex to FCount - 2 do
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

procedure TbpJsonValue.AddBool(AValue: Boolean);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateBool(AValue));
end;

procedure TbpJsonValue.AddInt(AValue: Int64);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateInt(AValue));
end;

procedure TbpJsonValue.AddFloat(AValue: Double);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateFloat(AValue));
end;

procedure TbpJsonValue.AddStr(const AValue: string);
begin
  RequireKind(bjkArray);
  InternalAdd('', CreateStr(AValue));
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

function TbpJsonValue.Find(const AName: string): TbpJsonValue;
var
  lvIdx: Integer;
begin
  RequireKind(bjkObject);
  lvIdx := IndexOfName(AName);
  if lvIdx >= 0 then
    Result := FItems[lvIdx]
  else
    Result := nil;
end;

function TbpJsonValue.Contains(const AName: string): Boolean;
begin
  RequireKind(bjkObject);
  Result := IndexOfName(AName) >= 0;
end;

function TbpJsonValue.Remove(const AName: string): Boolean;
var
  lvIdx: Integer;
begin
  RequireKind(bjkObject);
  lvIdx := IndexOfName(AName);
  Result := lvIdx >= 0;
  if Result then
    Delete(lvIdx);
end;

function TbpJsonValue.GetBool(const AName: string): Boolean;
begin
  Result := MemberOrFail(AName).AsBool;
end;

function TbpJsonValue.GetBoolDef(const AName: string;
  ADefault: Boolean): Boolean;
begin
  if not TryGetBool(AName, Result) then
    Result := ADefault;
end;

function TbpJsonValue.TryGetBool(const AName: string;
  out AValue: Boolean): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(AName);
  Result := (lvValue <> nil) and (lvValue.FKind = bjkBool);
  if Result then
    AValue := lvValue.FBool
  else
    AValue := False;
end;

function TbpJsonValue.GetInt(const AName: string): Int64;
begin
  Result := MemberOrFail(AName).AsInt;
end;

function TbpJsonValue.GetIntDef(const AName: string; ADefault: Int64): Int64;
begin
  if not TryGetInt(AName, Result) then
    Result := ADefault;
end;

function TbpJsonValue.TryGetInt(const AName: string;
  out AValue: Int64): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(AName);
  Result := (lvValue <> nil) and (lvValue.FKind = bjkInt);
  if Result then
    AValue := lvValue.FInt
  else
    AValue := 0;
end;

function TbpJsonValue.GetFloat(const AName: string): Double;
begin
  Result := MemberOrFail(AName).AsFloat;
end;

function TbpJsonValue.GetFloatDef(const AName: string;
  ADefault: Double): Double;
begin
  if not TryGetFloat(AName, Result) then
    Result := ADefault;
end;

function TbpJsonValue.TryGetFloat(const AName: string;
  out AValue: Double): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(AName);
  Result := (lvValue <> nil) and
    ((lvValue.FKind = bjkFloat) or (lvValue.FKind = bjkInt));
  if Result then
    AValue := lvValue.AsFloat
  else
    AValue := 0;
end;

function TbpJsonValue.GetStr(const AName: string): string;
begin
  Result := MemberOrFail(AName).AsStr;
end;

function TbpJsonValue.GetStrDef(const AName, ADefault: string): string;
begin
  if not TryGetStr(AName, Result) then
    Result := ADefault;
end;

function TbpJsonValue.TryGetStr(const AName: string;
  out AValue: string): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := Find(AName);
  Result := (lvValue <> nil) and (lvValue.FKind = bjkString);
  if Result then
    AValue := lvValue.FStr
  else
    AValue := '';
end;

procedure TbpJsonValue.SetNull(const AName: string);
begin
  RequireKind(bjkObject);
  InternalPut(AName, CreateNull);
end;

procedure TbpJsonValue.SetBool(const AName: string; AValue: Boolean);
begin
  RequireKind(bjkObject);
  InternalPut(AName, CreateBool(AValue));
end;

procedure TbpJsonValue.SetInt(const AName: string; AValue: Int64);
begin
  RequireKind(bjkObject);
  InternalPut(AName, CreateInt(AValue));
end;

procedure TbpJsonValue.SetFloat(const AName: string; AValue: Double);
begin
  RequireKind(bjkObject);
  InternalPut(AName, CreateFloat(AValue));
end;

procedure TbpJsonValue.SetStr(const AName, AValue: string);
begin
  RequireKind(bjkObject);
  InternalPut(AName, CreateStr(AValue));
end;

function TbpJsonValue.SetArray(const AName: string): TbpJsonValue;
begin
  RequireKind(bjkObject);
  Result := CreateArray;
  InternalPut(AName, Result);
end;

function TbpJsonValue.SetObject(const AName: string): TbpJsonValue;
begin
  RequireKind(bjkObject);
  Result := CreateObject;
  InternalPut(AName, Result);
end;

function TbpJsonValue.FindPath(const APath: string): TbpJsonValue;
var
  lvPos, lvLen, lvStart, lvIdx: Integer;
  lvName: string;
begin
  Result := Self;
  lvLen := Length(APath);
  if lvLen = 0 then
  begin
    Result := nil;
    Exit;
  end;
  lvPos := 1;
  while (lvPos <= lvLen) and (Result <> nil) do
    case APath[lvPos] of
      '.': Inc(lvPos);
      '[':
        begin
          // numeric index into an array
          Inc(lvPos);
          lvStart := lvPos;
          lvIdx := 0;
          while (lvPos <= lvLen) and (APath[lvPos] >= '0') and
            (APath[lvPos] <= '9') do
          begin
            lvIdx := lvIdx * 10 + Ord(APath[lvPos]) - Ord('0');
            Inc(lvPos);
          end;
          if (lvPos > lvLen) or (APath[lvPos] <> ']') or (lvPos = lvStart) then
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
        while (lvPos <= lvLen) and (APath[lvPos] <> '.') and
          (APath[lvPos] <> '[') do
          Inc(lvPos);
        lvName := Copy(APath, lvStart, lvPos - lvStart);
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

function TbpJsonValue.PathBoolDef(const APath: string;
  ADefault: Boolean): Boolean;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(APath);
  if (lvValue <> nil) and (lvValue.FKind = bjkBool) then
    Result := lvValue.FBool
  else
    Result := ADefault;
end;

function TbpJsonValue.PathIntDef(const APath: string; ADefault: Int64): Int64;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(APath);
  if (lvValue <> nil) and (lvValue.FKind = bjkInt) then
    Result := lvValue.FInt
  else
    Result := ADefault;
end;

function TbpJsonValue.PathFloatDef(const APath: string;
  ADefault: Double): Double;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(APath);
  if (lvValue <> nil) and
    ((lvValue.FKind = bjkFloat) or (lvValue.FKind = bjkInt)) then
    Result := lvValue.AsFloat
  else
    Result := ADefault;
end;

function TbpJsonValue.PathStrDef(const APath, ADefault: string): string;
var
  lvValue: TbpJsonValue;
begin
  lvValue := FindPath(APath);
  if (lvValue <> nil) and (lvValue.FKind = bjkString) then
    Result := lvValue.FStr
  else
    Result := ADefault;
end;

procedure TbpJsonValue.WriteTo(ASb: TbpStringBuilder;
  AEscapeNonAscii: Boolean; AIndentSize, ALevel: Integer);
var
  lvI: Integer;
  lvPretty: Boolean;

  procedure Indent(ADepth: Integer);
  begin
    ASb.Append(#13#10);
    if ADepth * AIndentSize > 0 then
      ASb.Append(' ', ADepth * AIndentSize);
  end;

begin
  lvPretty := AIndentSize >= 0;
  case FKind of
    bjkNull: ASb.Append('null');
    bjkBool:
      if FBool then
        ASb.Append('true')
      else
        ASb.Append('false');
    bjkInt: ASb.Append(FInt);
    bjkFloat: ASb.Append(BpJsonFloatToStr(FFloat));
    bjkString: BpJsonAppendQuoted(ASb, FStr, AEscapeNonAscii);
    bjkArray:
      if FCount = 0 then
        ASb.Append('[]')
      else
      begin
        ASb.Append('[');
        for lvI := 0 to FCount - 1 do
        begin
          if lvI > 0 then
            ASb.Append(',');
          if lvPretty then
            Indent(ALevel + 1);
          FItems[lvI].WriteTo(ASb, AEscapeNonAscii, AIndentSize, ALevel + 1);
        end;
        if lvPretty then
          Indent(ALevel);
        ASb.Append(']');
      end;
    bjkObject:
      if FCount = 0 then
        ASb.Append('{}')
      else
      begin
        ASb.Append('{');
        for lvI := 0 to FCount - 1 do
        begin
          if lvI > 0 then
            ASb.Append(',');
          if lvPretty then
            Indent(ALevel + 1);
          BpJsonAppendQuoted(ASb, FNames[lvI], AEscapeNonAscii);
          ASb.Append(':');
          if lvPretty then
            ASb.Append(' ');
          FItems[lvI].WriteTo(ASb, AEscapeNonAscii, AIndentSize, ALevel + 1);
        end;
        if lvPretty then
          Indent(ALevel);
        ASb.Append('}');
      end;
  end;
end;

function TbpJsonValue.ToJson(AEscapeNonAscii: Boolean): string;
var
  lvSb: TbpStringBuilder;
begin
  lvSb := TbpStringBuilder.Create(256);
  try
    WriteTo(lvSb, AEscapeNonAscii, -1, 0);
    Result := lvSb.ToString;
  finally
    lvSb.Free;
  end;
end;

function TbpJsonValue.ToJsonPretty(AIndentSize: Integer;
  AEscapeNonAscii: Boolean): string;
var
  lvSb: TbpStringBuilder;
begin
  if AIndentSize < 0 then
    AIndentSize := 0;
  lvSb := TbpStringBuilder.Create(256);
  try
    WriteTo(lvSb, AEscapeNonAscii, AIndentSize, 0);
    Result := lvSb.ToString;
  finally
    lvSb.Free;
  end;
end;

end.
