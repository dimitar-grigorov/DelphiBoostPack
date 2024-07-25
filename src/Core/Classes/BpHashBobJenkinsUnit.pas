unit BpHashBobJenkinsUnit;

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
  Update(AData, ALength);
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
  Move(FHash, Result[0], 4);  // Direct memory move
end;

class function TbpHashBobJenkins.HashLittle(const Data; Len, InitVal: Integer): Integer;
var
  a, b, c: Cardinal;
  pb, endPtr: PByte;
begin
  a := $DEADBEEF + Cardinal(Len) + Cardinal(InitVal);
  b := a;
  c := a;
  pb := PByte(@Data);
  endPtr := PByte(Cardinal(pb) + Cardinal(Len));

  while Cardinal(pb) + 12 <= Cardinal(endPtr) do
  begin
    Inc(a, PCardinal(pb)^);
    Inc(b, PCardinal(Cardinal(pb) + 4)^);
    Inc(c, PCardinal(Cardinal(pb) + 8)^);

    // Mix(a, b, c) inline
    Dec(a, c); a := a xor ((c shl 4) or (c shr 28)); Inc(c, b);
    Dec(b, a); b := b xor ((a shl 6) or (a shr 26)); Inc(a, c);
    Dec(c, b); c := c xor ((b shl 8) or (b shr 24)); Inc(b, a);
    Dec(a, c); a := a xor ((c shl 16) or (c shr 16)); Inc(c, b);
    Dec(b, a); b := b xor ((a shl 19) or (a shr 13)); Inc(a, c);
    Dec(c, b); c := c xor ((b shl 4) or (b shr 28)); Inc(b, a);

    Inc(pb, 12);
  end;

  Len := Cardinal(endPtr) - Cardinal(pb);
  if Len > 0 then
  begin
    Inc(a, Cardinal(pb^));
    if Len > 1 then Inc(a, Cardinal(PByte(Cardinal(pb) + 1)^) shl 8);
    if Len > 2 then Inc(a, Cardinal(PByte(Cardinal(pb) + 2)^) shl 16);

    if Len > 3 then
    begin
      pb := PByte(Cardinal(pb) + 3);
      Inc(b, Cardinal(pb^));
      if Len > 4 then Inc(b, Cardinal(PByte(Cardinal(pb) + 1)^) shl 8);
      if Len > 5 then Inc(b, Cardinal(PByte(Cardinal(pb) + 2)^) shl 16);
    end;

    if Len > 6 then
    begin
      pb := PByte(Cardinal(pb) + 6);
      Inc(c, Cardinal(pb^));
      if Len > 7 then Inc(c, Cardinal(PByte(Cardinal(pb) + 1)^) shl 8);
      if Len > 8 then Inc(c, Cardinal(PByte(Cardinal(pb) + 2)^) shl 16);
    end;
  end;

  // Final(a, b, c) inline
  c := c xor b; Dec(c, (b shl 14) or (b shr 18));
  a := a xor c; Dec(a, (c shl 11) or (c shr 21));
  b := b xor a; Dec(b, (a shl 25) or (a shr 7));
  c := c xor b; Dec(c, (b shl 16) or (b shr 16));
  a := a xor c; Dec(a, (c shl 4) or (c shr 28));
  b := b xor a; Dec(b, (a shl 14) or (a shr 18));
  c := c xor b; Dec(c, (b shl 24) or (b shr 8));

  Result := Integer(c);
end;

end.
