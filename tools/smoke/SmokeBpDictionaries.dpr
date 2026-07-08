program SmokeBpDictionaries;

// smoke test for dist\BpDictionaries.pas: one exercise per embedded piece,
// compiled against the bundle only (see tools\VerifyBundles.cmd)

{$APPTYPE CONSOLE}

uses
  SysUtils, BpDictionaries;

var
  lvStr: TbpStrDictionary;
  lvInt: TbpIntDictionary;
begin
  ExitCode := 1;
  lvStr := TbpStrDictionary.Create;
  lvInt := TbpIntDictionary.Create;
  try
    lvStr.SetInt('answer', 42);
    lvStr.SetStr('name', 'boost');
    lvInt.SetStr(1000000042, 'answer');
    if lvStr.GetInt('answer') <> 42 then
      Writeln('FAIL: str dictionary int roundtrip')
    else if not lvStr.Remove('name') or lvStr.ContainsKey('name') then
      Writeln('FAIL: str dictionary remove')
    else if lvInt.GetStr(1000000042) <> 'answer' then
      Writeln('FAIL: int dictionary str roundtrip')
    else if BpHashInt64(12345) = BpHashInt64(12346) then
      Writeln('FAIL: BpHashInt64 collides on neighbors')
    else
    begin
      Writeln('OK: BpDictionaries');
      ExitCode := 0;
    end;
  finally
    lvInt.Free;
    lvStr.Free;
  end;
end.
