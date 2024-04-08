program DelphiBoostPack;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  BpIntList in 'Core\Classes\BpIntList.pas',
  BpIntListInterface in 'Core\Interfaces\BpIntListInterface.pas',
  BpObjectComparer in 'Core\Classes\BpObjectComparer.pas';

begin
  System.ReportMemoryLeaksOnShutdown := True;

  Readln;
end.

