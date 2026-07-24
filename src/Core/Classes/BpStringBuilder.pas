unit BpStringBuilder;

// Fast string builder for Delphi 7/2007+, API modeled on XE6 TStringBuilder.
// It writes through a cached buffer pointer rather than routing every append
// through the Length setter, which is what makes the RTL version slow.
// Chars and Insert use 0-based indexes; Clear keeps capacity for reuse.

interface

uses
  SysUtils;

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

implementation

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

end.
