unit BpSysUtilsTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, TypInfo;

type
  TBpSysUtilsTests = class(TTestCase)
  published
    procedure TestCharInSetAnsiChar;
    procedure TestCharInSetWideChar;
    procedure TestCharInSetByte;
    procedure TestMethodsExistence;
  end;

implementation

uses
  BpSysUtils;

procedure TBpSysUtilsTests.TestCharInSetAnsiChar;
begin
  {$IF CompilerVersion < 20.0}
  CheckTrue(CharInSet('A', ['A', 'B', 'C']));
  CheckFalse(CharInSet('D', ['A', 'B', 'C']));
  {$IFEND}
end;

procedure TBpSysUtilsTests.TestCharInSetWideChar;
begin
  {$IF CompilerVersion < 20.0}
  CheckTrue(CharInSet(WideChar('A'), ['A', 'B', 'C']));
  CheckFalse(CharInSet(WideChar('D'), ['A', 'B', 'C']));
  {$IFEND}
end;

procedure TBpSysUtilsTests.TestCharInSetByte;
begin
  {$IF CompilerVersion < 20.0}
  CheckTrue(CharInSet(Byte(65), ['A', 'B', 'C']));
  CheckFalse(CharInSet(Byte(68), ['A', 'B', 'C']));
  {$IFEND}
end;

procedure TBpSysUtilsTests.TestMethodsExistence;
var
  Method: Pointer;
begin
  {$IF CompilerVersion >= 20.0}
  Method := @CharInSet;
  CheckFalse(Assigned(Method), 'CharInSet function should not be assigned in newer Delphi versions.');
  {$ELSE}
  Method := @CharInSet;
  CheckTrue(Assigned(Method), 'CharInSet function should be assigned in Delphi 2007 and earlier.');
  {$IFEND}
end;

initialization
  RegisterTest(TBpSysUtilsTests.Suite);

end.

