unit BpJson;

// JSON reader/writer for Delphi 7/2007+ (RFC 8259). TbpJsonValue is the whole
// tree, so freeing the root frees it all; FindPath walks 'data.items[0].name'.
// The parser is strict: leading zeros, trailing commas and junk all fail.
// Below Delphi 2009 a string holds UTF-8 bytes, in and out, so a \u escape and
// the raw character it names give the same result.

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

    // the wrong kind raises EbpJson; AsFloat also accepts an int, nothing else converts
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

    // array building; AddArray and AddObject return the new empty container
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

    // dotted path with [n] indexing; nil or the default when a step is missing
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
  lvIdx, lvDigit: Integer;
begin
  Result := 0;
  lvDigit := 0;
  for lvIdx := 1 to 4 do
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

{$IF CompilerVersion < 20.0}
// UTF-8 bytes for one code point. Below Delphi 2009 a string holds bytes, so a
// \u escape has to produce the same UTF-8 a raw literal already passes through.
function BpJsonUtf8Bytes(aCode: Integer): AnsiString;
begin
  if aCode < $80 then
  begin
    SetLength(Result, 1);
    Result[1] := AnsiChar(aCode);
  end
  else if aCode < $800 then
  begin
    SetLength(Result, 2);
    Result[1] := AnsiChar($C0 or (aCode shr 6));
    Result[2] := AnsiChar($80 or (aCode and $3F));
  end
  else if aCode < $10000 then
  begin
    SetLength(Result, 3);
    Result[1] := AnsiChar($E0 or (aCode shr 12));
    Result[2] := AnsiChar($80 or ((aCode shr 6) and $3F));
    Result[3] := AnsiChar($80 or (aCode and $3F));
  end
  else
  begin
    SetLength(Result, 4);
    Result[1] := AnsiChar($F0 or (aCode shr 18));
    Result[2] := AnsiChar($80 or ((aCode shr 12) and $3F));
    Result[3] := AnsiChar($80 or ((aCode shr 6) and $3F));
    Result[4] := AnsiChar($80 or (aCode and $3F));
  end;
end;
// The reverse, for the writer. False when the bytes are not valid UTF-8, which
// leaves the caller free to fall back to the ANSI reading.
function BpJsonWideFromUtf8(const aValue: AnsiString;
  out aWide: WideString): Boolean;
var
  lvIdx, lvLen, lvOut, lvCode, lvExtra, i: Integer;
  lvByte: Byte;
begin
  Result := False;
  lvLen := Length(aValue);
  SetLength(aWide, lvLen);  // never more UTF-16 units than bytes
  lvIdx := 1;
  lvOut := 0;
  while lvIdx <= lvLen do
  begin
    lvByte := Byte(aValue[lvIdx]);
    if lvByte < $80 then
    begin
      lvCode := lvByte;
      lvExtra := 0;
    end
    else if (lvByte and $E0) = $C0 then
    begin
      lvCode := lvByte and $1F;
      lvExtra := 1;
    end
    else if (lvByte and $F0) = $E0 then
    begin
      lvCode := lvByte and $0F;
      lvExtra := 2;
    end
    else if (lvByte and $F8) = $F0 then
    begin
      lvCode := lvByte and $07;
      lvExtra := 3;
    end
    else
      Exit;
    if lvIdx + lvExtra > lvLen then
      Exit;
    for i := 1 to lvExtra do
    begin
      lvByte := Byte(aValue[lvIdx + i]);
      if (lvByte and $C0) <> $80 then
        Exit;
      lvCode := (lvCode shl 6) or (lvByte and $3F);
    end;
    Inc(lvIdx, lvExtra + 1);
    if lvCode < $10000 then
    begin
      Inc(lvOut);
      aWide[lvOut] := WideChar(lvCode);
    end
    else
    begin
      Dec(lvCode, $10000);
      Inc(lvOut);
      aWide[lvOut] := WideChar($D800 or (lvCode shr 10));
      Inc(lvOut);
      aWide[lvOut] := WideChar($DC00 or (lvCode and $3FF));
    end;
  end;
  SetLength(aWide, lvOut);
  Result := True;
end;
{$IFEND}

function BpJsonParseString(var aReader: TbpJsonReader): string;
var
  lvSb: TbpStringBuilder;
  lvSeg: PChar;
  lvW1, lvW2: Integer;

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

  // one code point in whatever a string holds here: UTF-16 on Delphi 2009+,
  // UTF-8 bytes below it
  procedure AppendCodePoint(aCode: Integer);
  begin
{$IF CompilerVersion >= 20.0}
    if aCode < $10000 then
      lvSb.Append(Char(aCode))
    else
    begin
      Dec(aCode, $10000);
      lvSb.Append(Char($D800 or (aCode shr 10)));
      lvSb.Append(Char($DC00 or (aCode and $3FF)));
    end;
{$ELSE}
    lvSb.Append(BpJsonUtf8Bytes(aCode));
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
                      AppendCodePoint($10000 +
                        ((lvW1 - $D800) shl 10) + (lvW2 - $DC00));
                    end
                    else
                      BpJsonFail(aReader, 'Unpaired high surrogate');
                  end
                  else if (lvW1 >= $DC00) and (lvW1 <= $DFFF) then
                    BpJsonFail(aReader, 'Unpaired low surrogate')
                  else
                    AppendCodePoint(lvW1);
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

type
  TbpJsonNumberRange = (jnNormal, jnZero, jnOutOfRange);

// jnZero when the mantissa is zero or the value underflows, jnOutOfRange when
// the exponent is past Double range. Shorter exponents are left to Val.
function BpJsonClassifyExponent(const aToken: string): TbpJsonNumberRange;
var
  i, lvDigits: Integer;
  lvMantissaNonZero, lvNegExp: Boolean;
begin
  Result := jnNormal;
  lvMantissaNonZero := False;
  i := 1;
  while (i <= Length(aToken)) and (aToken[i] <> 'e') and (aToken[i] <> 'E') do
  begin
    if (aToken[i] >= '1') and (aToken[i] <= '9') then
      lvMantissaNonZero := True;
    Inc(i);
  end;
  if i > Length(aToken) then
  begin
    if not lvMantissaNonZero then
      Result := jnZero;
    Exit;
  end;
  Inc(i);
  lvNegExp := (i <= Length(aToken)) and (aToken[i] = '-');
  if (i <= Length(aToken)) and ((aToken[i] = '+') or (aToken[i] = '-')) then
    Inc(i);
  while (i <= Length(aToken)) and (aToken[i] = '0') do
    Inc(i);
  lvDigits := 0;
  while (i <= Length(aToken)) and (aToken[i] >= '0') and (aToken[i] <= '9') do
  begin
    Inc(lvDigits);
    Inc(i);
  end;
  // a Double tops out near 1e308, so six exponent digits is already decisive
  if lvDigits <= 6 then
    Exit;
  if not lvMantissaNonZero then
    Result := jnZero
  else if lvNegExp then
    Result := jnZero
  else
    Result := jnOutOfRange;
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
  // a long exponent wraps inside Val into a plausible wrong value, so settle it here
  case BpJsonClassifyExponent(lvToken) of
    jnZero:
      begin
        Result := TbpJsonValue.CreateFloat(0);
        Exit;
      end;
    jnOutOfRange:
      BpJsonFail(aReader, 'Number out of range');
  end;
  // Val stores through Extended into the Double, so anything past Double range
  // raises EOverflow, which is not EbpJson and would escape Parse and TryParse
  try
    Val(lvToken, lvFloat, lvErr);
  except
    on E: Exception do
      BpJsonFail(aReader, 'Number out of range');
  end;
  if lvErr <> 0 then
    BpJsonFail(aReader, 'Number out of range');
  Result := TbpJsonValue.CreateFloat(lvFloat);
end;

procedure BpJsonExpectWord(var aReader: TbpJsonReader; const aWord: string);
var
  lvIdx: Integer;
begin
  for lvIdx := 1 to Length(aWord) do
  begin
    if aReader.Cur^ <> aWord[lvIdx] then
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

// always '.' whatever the locale says, and shortest round-tripping text wins
function BpJsonFloatToStr(const aValue: Double): string;
var
  lvFs: TFormatSettings;
  lvPrec: Integer;
  lvBack: Double;
  lvParsed: Boolean;
begin
  if IsNan(aValue) or IsInfinite(aValue) then
    raise EbpJson.Create('NaN and Infinity cannot be written as JSON');
  FillChar(lvFs, SizeOf(lvFs), 0);
  lvFs.DecimalSeparator := '.';
  for lvPrec := 15 to 17 do
  begin
    Result := FloatToStrF(aValue, ffGeneral, lvPrec, 0, lvFs);
    // narrowing Extended to Double overflows when the text passes MaxDouble
    lvBack := 0; // D7 flow analysis cannot see the except assignment
    lvParsed := True;
    try
      lvBack := StrToFloat(Result, lvFs);
    except
      lvParsed := False;
    end;
    if lvParsed and (lvBack = aValue) then
      Exit;
  end;
end;

procedure BpJsonAppendQuoted(aSb: TbpStringBuilder; const aValue: string;
  aEscapeNonAscii: Boolean);
var
  lvIdx, lvLen, lvRun: Integer;
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
    for lvIdx := 1 to Length(aValue) do
    begin
      lvC := aValue[lvIdx];
      if (lvC >= #32) and (lvC < #127) and (lvC <> '"') and (lvC <> '\') then
        aSb.Append(lvC)
      else
        AppendEscape(Ord(lvC));
    end;
{$ELSE}
    // the parser hands out UTF-8 here, so decode it as such; input that is not
    // valid UTF-8 is taken as ANSI, the best guess left
    if not BpJsonWideFromUtf8(aValue, lvWide) then
      lvWide := WideString(aValue);
    for lvIdx := 1 to Length(lvWide) do
    begin
      lvWC := lvWide[lvIdx];
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
    for lvIdx := 1 to lvLen do
    begin
      lvC := aValue[lvIdx];
      if (lvC < #32) or (lvC = '"') or (lvC = '\') then
      begin
        if lvIdx > lvRun then
          aSb.Append(Copy(aValue, lvRun, lvIdx - lvRun));
        AppendEscape(Ord(lvC));
        lvRun := lvIdx + 1;
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
  lvIdx: Integer;
begin
  Result := TbpJsonValue.Create;
  try
    Result.FKind := FKind;
    Result.FBool := FBool;
    Result.FInt := FInt;
    Result.FFloat := FFloat;
    Result.FStr := FStr;
    for lvIdx := 0 to FCount - 1 do
      if FKind = bjkObject then
        Result.InternalAdd(FNames[lvIdx], FItems[lvIdx].Clone)
      else
        Result.InternalAdd('', FItems[lvIdx].Clone);
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
  lvIdx: Integer;
begin
  if (aIndex < 0) or (aIndex >= FCount) then
    raise EbpJson.CreateFmt('Index %d out of range (count %d)',
      [aIndex, FCount]);
  FItems[aIndex].Free;
  for lvIdx := aIndex to FCount - 2 do
  begin
    FItems[lvIdx] := FItems[lvIdx + 1];
    if FKind = bjkObject then
      FNames[lvIdx] := FNames[lvIdx + 1];
  end;
  Dec(FCount);
  FItems[FCount] := nil;
  if FKind = bjkObject then
    FNames[FCount] := '';
end;

procedure TbpJsonValue.Clear;
var
  lvIdx: Integer;
begin
  for lvIdx := 0 to FCount - 1 do
    FItems[lvIdx].Free;
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
  // nil rather than a raise, so the whole TryGetX / GetXDef family stays safe
  if FKind <> bjkObject then
  begin
    Result := nil;
    Exit;
  end;
  lvIdx := IndexOfName(aName);
  if lvIdx >= 0 then
    Result := FItems[lvIdx]
  else
    Result := nil;
end;

function TbpJsonValue.Contains(const aName: string): Boolean;
begin
  Result := (FKind = bjkObject) and (IndexOfName(aName) >= 0);
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
            // clamp, or a long run of digits wraps into a plausible index
            if lvIdx > (MaxInt - 9) div 10 then
              lvIdx := MaxInt
            else
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
  lvIdx: Integer;
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
        for lvIdx := 0 to FCount - 1 do
        begin
          if lvIdx > 0 then
            aSb.Append(',');
          if lvPretty then
            Indent(aLevel + 1);
          FItems[lvIdx].WriteTo(aSb, aEscapeNonAscii, aIndentSize, aLevel + 1);
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
        for lvIdx := 0 to FCount - 1 do
        begin
          if lvIdx > 0 then
            aSb.Append(',');
          if lvPretty then
            Indent(aLevel + 1);
          BpJsonAppendQuoted(aSb, FNames[lvIdx], aEscapeNonAscii);
          aSb.Append(':');
          if lvPretty then
            aSb.Append(' ');
          FItems[lvIdx].WriteTo(aSb, aEscapeNonAscii, aIndentSize, aLevel + 1);
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
