unit BpHashBobJenkins;

// Bob Jenkins lookup3 hash (public domain) for Delphi 7/2007+, seeded to
// interoperate with the RTL's BobJenkinsHash. Hashing a string hashes its
// bytes, so Ansi and Unicode builds differ: use the buffer overload.

interface

{$IF CompilerVersion >= 18}
  {$DEFINE Delphi_2007_UP}
{$IFEND}

uses
  SysUtils, BpCompat;

type
  TbpHashBobJenkins = class
  private
    FHash: Integer;
    function GetDigest: TBytes;
    class function HashLittle(const Data; Len, InitVal: Integer): Integer;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
  public
    constructor Create;
    procedure Reset(aInitialValue: Integer = 0);
    procedure Update(const aData; aLength: Cardinal); overload;
    // aLength < 0 means the whole array; an explicit 0 hashes nothing
    procedure Update(const aData: TBytes; aLength: Integer = -1); overload;
    procedure Update(const Input: string); overload;
    function HashAsBytes: TBytes;
    function HashAsInteger: Integer;
    function HashAsString: string;
    class function GetHashBytes(const aData: string): TBytes;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashString(const aString: string): string;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashValue(const aData: string): Integer; overload;
      {$IFDEF Delphi_2007_UP} static; inline; {$ENDIF}
    class function GetHashValue(const aData; aLength: Integer; aInitialValue: Integer = 0): Integer; overload;
      {$IFDEF Delphi_2007_UP} static; inline; {$ENDIF}
  end;

implementation

// lookup3 is defined on wrapping arithmetic, so the checks stay off here
{$Q-}
{$R-}

type
  // three consecutive 32-bit words, for aligned block reads
  TCardinalTriple = array[0..2] of Cardinal;
  PCardinalTriple = ^TCardinalTriple;

function Rot(x, k: Cardinal): Cardinal; {$IFDEF Delphi_2007_UP} inline; {$ENDIF}
begin
  Result := (x shl k) or (x shr (32 - k));
end;

procedure Mix(var a, b, c: Cardinal); {$IFDEF Delphi_2007_UP} inline; {$ENDIF}
begin
  Dec(a, c); a := a xor Rot(c, 4); Inc(c, b);
  Dec(b, a); b := b xor Rot(a, 6); Inc(a, c);
  Dec(c, b); c := c xor Rot(b, 8); Inc(b, a);
  Dec(a, c); a := a xor Rot(c, 16); Inc(c, b);
  Dec(b, a); b := b xor Rot(a, 19); Inc(a, c);
  Dec(c, b); c := c xor Rot(b, 4); Inc(b, a);
end;

procedure Final(var a, b, c: Cardinal); {$IFDEF Delphi_2007_UP} inline; {$ENDIF}
begin
  c := c xor b; Dec(c, Rot(b, 14));
  a := a xor c; Dec(a, Rot(c, 11));
  b := b xor a; Dec(b, Rot(a, 25));
  c := c xor b; Dec(c, Rot(b, 16));
  a := a xor c; Dec(a, Rot(c, 4));
  b := b xor a; Dec(b, Rot(a, 14));
  c := c xor b; Dec(c, Rot(b, 24));
end;

constructor TbpHashBobJenkins.Create;
begin
  inherited Create;
  FHash := 0;
end;

procedure TbpHashBobJenkins.Reset(aInitialValue: Integer = 0);
begin
  FHash := aInitialValue;
end;

procedure TbpHashBobJenkins.Update(const aData; aLength: Cardinal);
begin
  FHash := HashLittle(aData, aLength, FHash);
end;

procedure TbpHashBobJenkins.Update(const aData: TBytes; aLength: Integer);
begin
  if aLength < 0 then
    aLength := Length(aData);
  if aLength > Length(aData) then
    raise ERangeError.CreateFmt('Update: aLength %d exceeds the %d bytes available',
      [aLength, Length(aData)]);
  Update(Pointer(aData)^, Cardinal(aLength));
end;

procedure TbpHashBobJenkins.Update(const Input: string);
begin
  Update(Pointer(Input)^, Length(Input) * SizeOf(Char));
end;

function TbpHashBobJenkins.HashAsBytes: TBytes;
begin
  Result := GetDigest;
end;

function TbpHashBobJenkins.HashAsInteger: Integer;
begin
  Result := FHash;
end;

function TbpHashBobJenkins.HashAsString: string;
begin
  Result := IntToHex(FHash, 8);
end;

class function TbpHashBobJenkins.GetHashBytes(const aData: string): TBytes;
begin
  SetLength(Result, 4);
  PCardinal(@Result[0])^ := Cardinal(GetHashValue(aData));
end;

class function TbpHashBobJenkins.GetHashString(const aString: string): string;
begin
  Result := IntToHex(GetHashValue(aString), 8);
end;

class function TbpHashBobJenkins.GetHashValue(const aData: string): Integer;
begin
  Result := HashLittle(Pointer(aData)^, Length(aData) * SizeOf(Char), 0);
end;

class function TbpHashBobJenkins.GetHashValue(const aData; aLength: Integer; aInitialValue: Integer): Integer;
begin
  Result := HashLittle(aData, aLength, aInitialValue);
end;

function TbpHashBobJenkins.GetDigest: TBytes;
begin
  SetLength(Result, 4);
  Move(FHash, Result[0], 4);
end;

// lookup3 mix and final. The last 12-byte block is folded by Final rather
// than in the loop, Len = 0 exits early, and the tail never reads past Data.
class function TbpHashBobJenkins.HashLittle(const Data; Len, InitVal: Integer): Integer;
var
  a, b, c: Cardinal;
  pd: PCardinalTriple;
  pb: PByteArray;
begin
  // seed with the byte length: hashword counts words, hashlittle bytes
  // clamped first, or the two branches below disagree and the unaligned one
  // reads a byte that was never asked for
  if Len < 0 then
    Len := 0;
  a := Cardinal($DEADBEEF) + Cardinal(Len) + Cardinal(InitVal);
  b := a;
  c := a;

  if (TbpUIntPtr(@Data) and 3) = 0 then
  begin
    // 4-byte aligned data
    pd := PCardinalTriple(@Data);
    while Len > 12 do
    begin
      Inc(a, pd^[0]);
      Inc(b, pd^[1]);
      Inc(c, pd^[2]);
      Mix(a, b, c);
      Dec(Len, 12);
      Inc(pd); // one 12-byte block
    end;

    case Len of
      0:
      begin
        Result := Integer(c);
        Exit;
      end;
      1: Inc(a, pd^[0] and $FF);
      2: Inc(a, pd^[0] and $FFFF);
      3: Inc(a, pd^[0] and $FFFFFF);
      4: Inc(a, pd^[0]);
      5:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1] and $FF);
      end;
      6:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1] and $FFFF);
      end;
      7:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1] and $FFFFFF);
      end;
      8:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
      end;
      9:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2] and $FF);
      end;
      10:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2] and $FFFF);
      end;
      11:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2] and $FFFFFF);
      end;
      12:
      begin
        Inc(a, pd^[0]);
        Inc(b, pd^[1]);
        Inc(c, pd^[2]);
      end;
    end;
  end
  else
  begin
    // unaligned data: byte-by-byte reads, never past the end
    pb := PByteArray(@Data);
    while Len > 12 do
    begin
      Inc(a, Cardinal(pb^[0]) + Cardinal(pb^[1]) shl 8 + Cardinal(pb^[2]) shl 16 + Cardinal(pb^[3]) shl 24);
      Inc(b, Cardinal(pb^[4]) + Cardinal(pb^[5]) shl 8 + Cardinal(pb^[6]) shl 16 + Cardinal(pb^[7]) shl 24);
      Inc(c, Cardinal(pb^[8]) + Cardinal(pb^[9]) shl 8 + Cardinal(pb^[10]) shl 16 + Cardinal(pb^[11]) shl 24);
      Mix(a, b, c);
      Dec(Len, 12);
      pb := PByteArray(TbpUIntPtr(pb) + 12);
    end;

    if Len = 0 then
    begin
      Result := Integer(c);
      Exit;
    end;

    // cumulative tail: byte i goes to word i div 4, shifted (i mod 4) * 8
    if Len >= 12 then Inc(c, Cardinal(pb^[11]) shl 24);
    if Len >= 11 then Inc(c, Cardinal(pb^[10]) shl 16);
    if Len >= 10 then Inc(c, Cardinal(pb^[9]) shl 8);
    if Len >= 9 then Inc(c, Cardinal(pb^[8]));
    if Len >= 8 then Inc(b, Cardinal(pb^[7]) shl 24);
    if Len >= 7 then Inc(b, Cardinal(pb^[6]) shl 16);
    if Len >= 6 then Inc(b, Cardinal(pb^[5]) shl 8);
    if Len >= 5 then Inc(b, Cardinal(pb^[4]));
    if Len >= 4 then Inc(a, Cardinal(pb^[3]) shl 24);
    if Len >= 3 then Inc(a, Cardinal(pb^[2]) shl 16);
    if Len >= 2 then Inc(a, Cardinal(pb^[1]) shl 8);
    Inc(a, Cardinal(pb^[0]));
  end;

  Final(a, b, c);
  Result := Integer(c);
end;

end.
