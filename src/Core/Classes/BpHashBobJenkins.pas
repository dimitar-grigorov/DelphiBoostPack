unit BpHashBobJenkins;

// Bob Jenkins lookup3 hash (http://burtleburtle.net/bob/c/lookup3.c) for
// Delphi 7/2007 and later.
//
// The implementation is a faithful port of HashLittle from Delphi XE6
// System.Generics.Defaults (the engine behind BobJenkinsHash and, later,
// System.Hash.THashBobJenkins), including Embarcadero's deviation from
// canonical lookup3: the initial state uses (Len shl 2) instead of Len.
// This keeps hash values byte-for-byte identical with the modern RTL, so
// results can be verified against any Delphi XE+ installation.
//
// Note for cross-version use: hashing a *string* hashes its bytes, so an
// AnsiString on Delphi 2007 and a UnicodeString on XE6 produce different
// hashes for the same text. Byte-oriented known-answer tests must use the
// untyped-buffer overload of GetHashValue.

interface

{$IF CompilerVersion >= 18}
  {$DEFINE Delphi_2007_UP}
{$IFEND}

uses
  SysUtils;

type
  {$IFNDEF Delphi_2007_UP}
  TBytes = array of Byte;
  {$ENDIF}

  TbpHashBobJenkins = class
  private
    FHash: Integer;
    function GetDigest: TBytes;
    class function HashLittle(const Data; Len, InitVal: Integer): Integer;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
  public
    constructor Create;
    procedure Reset(AInitialValue: Integer = 0);
    procedure Update(const AData; ALength: Cardinal); overload;
    procedure Update(const AData: TBytes; ALength: Cardinal = 0); overload;
    procedure Update(const Input: string); overload;
    function HashAsBytes: TBytes;
    function HashAsInteger: Integer;
    function HashAsString: string;
    class function GetHashBytes(const AData: string): TBytes;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashString(const AString: string): string;
      {$IFDEF Delphi_2007_UP} static; {$ENDIF}
    class function GetHashValue(const AData: string): Integer; overload;
      {$IFDEF Delphi_2007_UP} static; inline; {$ENDIF}
    class function GetHashValue(const AData; ALength: Integer; AInitialValue: Integer = 0): Integer; overload;
      {$IFDEF Delphi_2007_UP} static; inline; {$ENDIF}
  end;

implementation

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

procedure TbpHashBobJenkins.Reset(AInitialValue: Integer = 0);
begin
  FHash := AInitialValue;
end;

procedure TbpHashBobJenkins.Update(const AData; ALength: Cardinal);
begin
  FHash := HashLittle(AData, ALength, FHash);
end;

procedure TbpHashBobJenkins.Update(const AData: TBytes; ALength: Cardinal);
begin
  if ALength = 0 then
    ALength := Length(AData);
  Update(Pointer(AData)^, ALength);
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

class function TbpHashBobJenkins.GetHashBytes(const AData: string): TBytes;
begin
  SetLength(Result, 4);
  PCardinal(@Result[0])^ := Cardinal(GetHashValue(AData));
end;

class function TbpHashBobJenkins.GetHashString(const AString: string): string;
begin
  Result := IntToHex(GetHashValue(AString), 8);
end;

class function TbpHashBobJenkins.GetHashValue(const AData: string): Integer;
begin
  Result := HashLittle(Pointer(AData)^, Length(AData) * SizeOf(Char), 0);
end;

class function TbpHashBobJenkins.GetHashValue(const AData; ALength: Integer; AInitialValue: Integer): Integer;
begin
  Result := HashLittle(AData, ALength, AInitialValue);
end;

function TbpHashBobJenkins.GetDigest: TBytes;
begin
  SetLength(Result, 4);
  Move(FHash, Result[0], 4);
end;

// Port of Delphi XE6 System.Generics.Defaults.HashLittle.
// - the last full 12-byte block is NOT mixed in the loop: it is added to
//   a/b/c and folded by Final(), exactly like the reference
// - Len = 0 exits early WITHOUT Final(), exactly like the reference
// - the tail never reads past Data: the aligned path uses masked 32-bit
//   reads (cannot cross a page boundary), the unaligned path reads only
//   the remaining bytes one by one
class function TbpHashBobJenkins.HashLittle(const Data; Len, InitVal: Integer): Integer;
var
  a, b, c: Cardinal;
  pd: PCardinalTriple;
  pb: PByteArray;
begin
  a := Cardinal($DEADBEEF) + Cardinal(Len shl 2) + Cardinal(InitVal);
  b := a;
  c := a;

  if (Cardinal(@Data) and 3) = 0 then
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
      pd := PCardinalTriple(Cardinal(pd) + 12);
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
      pb := PByteArray(Cardinal(pb) + 12);
    end;

    if Len = 0 then
    begin
      Result := Integer(c);
      Exit;
    end;

    // cumulative tail: byte i goes to word (i div 4), shifted (i mod 4)*8 -
    // the same fall-through mapping as the reference goto chain
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
