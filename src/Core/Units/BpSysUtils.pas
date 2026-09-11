unit BpSysUtils;

// Small shims for pre-2009 compilers, e.g. CharInSet, which SysUtils only
// gained in Delphi 2009.

interface

{$IF CompilerVersion < 20.0}  // below Delphi 2009

uses
  SysUtils;

function CharInSet(aChar: WideChar; const aCharSet: TSysCharSet): Boolean; overload;

function CharInSet(aChar: Byte; const aCharSet: TSysCharSet): Boolean; overload;

function CharInSet(aChar: Char; const aCharSet: TSysCharSet): Boolean; overload;

{$IFEND}

implementation

{$IF CompilerVersion < 20.0}

function CharInSet(aChar: WideChar; const aCharSet: TSysCharSet): Boolean;
var
  I: AnsiChar;
begin
  Result := False;
  for I := Low(AnsiChar) to High(AnsiChar) do
  begin
    if I in aCharSet then
    begin
      if aChar = WideChar(I) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
end;

function CharInSet(aChar: Byte; const aCharSet: TSysCharSet): Boolean;
begin
  Result := AnsiChar(aChar) in aCharSet;
end;

function CharInSet(aChar: Char; const aCharSet: TSysCharSet): Boolean;
begin
  Result := AnsiChar(aChar) in aCharSet;
end;

{$IFEND}

end.

