program SmokeBpJsonStandalone;

// smoke test for dist\BpJsonStandalone.pas: parse, path access and write,
// compiled against the bundle only (see tools\VerifyBundles.cmd)

{$APPTYPE CONSOLE}

uses
  SysUtils, BpJsonStandalone;

var
  lvRoot, lvBuilt: TbpJsonValue;
begin
  ExitCode := 1;
  lvRoot := TbpJsonValue.Parse(
    '{"name":"boost","nested":{"items":[{"id":1},{"id":2}]},"ratio":0.5}');
  try
    if lvRoot.GetStr('name') <> 'boost' then
      Writeln('FAIL: member access')
    else if lvRoot.FindPath('nested.items[1].id').AsInt <> 2 then
      Writeln('FAIL: path access')
    else if Abs(lvRoot.PathFloatDef('ratio', 0) - 0.5) > 1E-12 then
      Writeln('FAIL: float path')
    else
    begin
      lvBuilt := TbpJsonValue.CreateObject;
      try
        lvBuilt.SetStr('k', 'v');
        lvBuilt.SetInt('n', 7);
        if lvBuilt.ToJson <> '{"k":"v","n":7}' then
          Writeln('FAIL: writer')
        else
        begin
          Writeln('OK: BpJsonStandalone');
          ExitCode := 0;
        end;
      finally
        lvBuilt.Free;
      end;
    end;
  finally
    lvRoot.Free;
  end;
end.
