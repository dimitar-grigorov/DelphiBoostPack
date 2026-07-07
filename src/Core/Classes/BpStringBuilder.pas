unit BpStringBuilder;

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
    procedure Grow(AMinCapacity: Integer);
    procedure AppendBuffer(ASource: PChar; ACount: Integer);
    function GetCapacity: Integer;
    procedure SetCapacity(AValue: Integer);
    function GetChar(AIndex: Integer): Char;
    procedure SetChar(AIndex: Integer; AValue: Char);
    procedure SetLength(AValue: Integer);
  public
    constructor Create; overload;
    constructor Create(ACapacity: Integer); overload;
    constructor Create(const AValue: string); overload;
    // all Append overloads return Self so calls can be chained
    function Append(const AValue: string): TbpStringBuilder; overload;
    function Append(AValue: Char): TbpStringBuilder; overload;
    function Append(AValue: Char; ARepeatCount: Integer): TbpStringBuilder; overload;
    function Append(AValue: Integer): TbpStringBuilder; overload;
    function Append(AValue: Int64): TbpStringBuilder; overload;
    function Append(AValue: Double): TbpStringBuilder; overload;
    function Append(AValue: Boolean): TbpStringBuilder; overload;
    function AppendLine: TbpStringBuilder; overload;
    function AppendLine(const AValue: string): TbpStringBuilder; overload;
    function AppendFormat(const AFormat: string; const AArgs: array of const): TbpStringBuilder;
    function Insert(AIndex: Integer; const AValue: string): TbpStringBuilder;
    procedure Clear;
    function ToString: string; {$IF CompilerVersion >= 20.0} override; {$IFEND}
    // Length is writable: shrinking truncates, extending pads with #0
    property Length: Integer read FLength write SetLength;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Chars[AIndex: Integer]: Char read GetChar write SetChar; default;
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

constructor TbpStringBuilder.Create(ACapacity: Integer);
begin
  inherited Create;
  if ACapacity < 0 then
    raise EbpStringBuilder.CreateFmt('Capacity cannot be negative (%d)', [ACapacity]);
  if ACapacity > 0 then
    SetCapacity(ACapacity);
end;

constructor TbpStringBuilder.Create(const AValue: string);
begin
  inherited Create;
  Append(AValue);
end;

procedure TbpStringBuilder.Grow(AMinCapacity: Integer);
var
  lvNewCapacity: Integer;
begin
  lvNewCapacity := System.Length(FBuffer) * 2;
  if lvNewCapacity < gcDefaultCapacity then
    lvNewCapacity := gcDefaultCapacity;
  if lvNewCapacity < AMinCapacity then
    lvNewCapacity := AMinCapacity;
  System.SetLength(FBuffer, lvNewCapacity);
  FData := Pointer(FBuffer);
end;

procedure TbpStringBuilder.AppendBuffer(ASource: PChar; ACount: Integer);
begin
  if ACount <= 0 then
    Exit;
  if FLength + ACount > System.Length(FBuffer) then
    Grow(FLength + ACount);
  Move(ASource^, FData[FLength], ACount * SizeOf(Char));
  Inc(FLength, ACount);
end;

function TbpStringBuilder.Append(const AValue: string): TbpStringBuilder;
begin
  AppendBuffer(Pointer(AValue), System.Length(AValue));
  Result := Self;
end;

function TbpStringBuilder.Append(AValue: Char): TbpStringBuilder;
begin
  // single char fast path, direct store instead of a Move
  if FLength >= System.Length(FBuffer) then
    Grow(FLength + 1);
  FData[FLength] := AValue;
  Inc(FLength);
  Result := Self;
end;

function TbpStringBuilder.Append(AValue: Char; ARepeatCount: Integer): TbpStringBuilder;
var
  i: Integer;
begin
  if ARepeatCount < 0 then
    raise EbpStringBuilder.CreateFmt('RepeatCount cannot be negative (%d)', [ARepeatCount]);
  if ARepeatCount > 0 then
  begin
    if FLength + ARepeatCount > System.Length(FBuffer) then
      Grow(FLength + ARepeatCount);
    for i := 0 to ARepeatCount - 1 do
      FData[FLength + i] := AValue;
    Inc(FLength, ARepeatCount);
  end;
  Result := Self;
end;

function TbpStringBuilder.Append(AValue: Integer): TbpStringBuilder;
var
  lvBuf: array[0..11] of Char;
  lvPos: Integer;
  lvRemaining: Cardinal;
begin
  // digits are written backward from the end of the stack buffer, no allocation
  if AValue < 0 then
    lvRemaining := Cardinal(-Int64(AValue)) // Int64 negation, -Low(Integer) overflows Integer
  else
    lvRemaining := Cardinal(AValue);
  lvPos := High(lvBuf) + 1;
  repeat
    Dec(lvPos);
    lvBuf[lvPos] := Char(Ord('0') + lvRemaining mod 10);
    lvRemaining := lvRemaining div 10;
  until lvRemaining = 0;
  if AValue < 0 then
  begin
    Dec(lvPos);
    lvBuf[lvPos] := '-';
  end;
  AppendBuffer(@lvBuf[lvPos], High(lvBuf) + 1 - lvPos);
  Result := Self;
end;

function TbpStringBuilder.Append(AValue: Int64): TbpStringBuilder;
var
  lvBuf: array[0..19] of Char;
  lvPos: Integer;
  lvRemaining: Int64;
begin
  if AValue = Low(Int64) then
  begin
    Result := Append(gcMinInt64Text);
    Exit;
  end;
  lvRemaining := AValue;
  if lvRemaining < 0 then
    lvRemaining := -lvRemaining;
  lvPos := High(lvBuf) + 1;
  repeat
    Dec(lvPos);
    lvBuf[lvPos] := Char(Ord('0') + lvRemaining mod 10);
    lvRemaining := lvRemaining div 10;
  until lvRemaining = 0;
  if AValue < 0 then
  begin
    Dec(lvPos);
    lvBuf[lvPos] := '-';
  end;
  AppendBuffer(@lvBuf[lvPos], High(lvBuf) + 1 - lvPos);
  Result := Self;
end;

function TbpStringBuilder.Append(AValue: Double): TbpStringBuilder;
begin
  Result := Append(FloatToStr(AValue));
end;

function TbpStringBuilder.Append(AValue: Boolean): TbpStringBuilder;
begin
  if AValue then
    Result := Append('True')
  else
    Result := Append('False');
end;

function TbpStringBuilder.AppendLine: TbpStringBuilder;
begin
  Result := Append(sLineBreak);
end;

function TbpStringBuilder.AppendLine(const AValue: string): TbpStringBuilder;
begin
  Append(AValue);
  Result := Append(sLineBreak);
end;

function TbpStringBuilder.AppendFormat(const AFormat: string;
  const AArgs: array of const): TbpStringBuilder;
begin
  Result := Append(Format(AFormat, AArgs));
end;

function TbpStringBuilder.Insert(AIndex: Integer; const AValue: string): TbpStringBuilder;
var
  lvLen: Integer;
begin
  if (AIndex < 0) or (AIndex > FLength) then
    raise EbpStringBuilder.CreateFmt('Insert index %d out of bounds (0..%d)',
      [AIndex, FLength]);
  lvLen := System.Length(AValue);
  if lvLen > 0 then
  begin
    if FLength + lvLen > System.Length(FBuffer) then
      Grow(FLength + lvLen);
    if AIndex < FLength then
      Move(FData[AIndex], FData[AIndex + lvLen], (FLength - AIndex) * SizeOf(Char));
    Move(Pointer(AValue)^, FData[AIndex], lvLen * SizeOf(Char));
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

procedure TbpStringBuilder.SetCapacity(AValue: Integer);
begin
  if (AValue < 0) or (AValue < FLength) then
    raise EbpStringBuilder.CreateFmt('Capacity %d is invalid (current length %d)',
      [AValue, FLength]);
  System.SetLength(FBuffer, AValue);
  FData := Pointer(FBuffer);
end;

function TbpStringBuilder.GetChar(AIndex: Integer): Char;
begin
  if (AIndex < 0) or (AIndex >= FLength) then
    raise EbpStringBuilder.CreateFmt('Index %d out of bounds (0..%d)',
      [AIndex, FLength - 1]);
  Result := FData[AIndex];
end;

procedure TbpStringBuilder.SetChar(AIndex: Integer; AValue: Char);
begin
  if (AIndex < 0) or (AIndex >= FLength) then
    raise EbpStringBuilder.CreateFmt('Index %d out of bounds (0..%d)',
      [AIndex, FLength - 1]);
  FData[AIndex] := AValue;
end;

procedure TbpStringBuilder.SetLength(AValue: Integer);
var
  i: Integer;
begin
  if AValue < 0 then
    raise EbpStringBuilder.CreateFmt('Length cannot be negative (%d)', [AValue]);
  if AValue > System.Length(FBuffer) then
    Grow(AValue);
  // extending pads with #0 so the new region is deterministic
  for i := FLength to AValue - 1 do
    FData[i] := #0;
  FLength := AValue;
end;

end.
