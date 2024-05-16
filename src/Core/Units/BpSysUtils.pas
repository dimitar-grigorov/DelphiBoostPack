unit BpSysUtils;

interface

{$IF CompilerVersion < 20.0}  // CompilerVersion 20.0 corresponds to Delphi 2009

uses
  SysUtils;

function CharInSet(C: WideChar; const CharSet: TSysCharSet): Boolean; overload;

function CharInSet(C: Byte; const CharSet: TSysCharSet): Boolean; overload;

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean; overload;

{$IFEND}

implementation

{$IF CompilerVersion < 20.0}

function CharInSet(C: WideChar; const CharSet: TSysCharSet): Boolean;
var
  I: AnsiChar;
begin
  Result := False;
  for I := Low(AnsiChar) to High(AnsiChar) do
  begin
    if I in CharSet then
    begin
      if C = WideChar(I) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
end;

function CharInSet(C: Byte; const CharSet: TSysCharSet): Boolean;
begin
  Result := AnsiChar(C) in CharSet;
end;

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := AnsiChar(C) in CharSet;
end;

{$IFEND}

end.

