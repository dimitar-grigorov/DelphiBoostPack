program DelphiBoostPack;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  BpIntListUnit in 'Core\Classes\BpIntListUnit.pas',
  IBpIntListUnit in 'Core\Interfaces\IBpIntListUnit.pas',
  BpObjectComparerUnit in 'Core\Classes\BpObjectComparerUnit.pas',
  IUniqueIdUnit in 'Core\Interfaces\IUniqueIdUnit.pas',
  InterfacedCollectionItemUnit in 'Core\Classes\InterfacedCollectionItemUnit.pas',
  BpHashBobJenkinsUnit in 'Core\Classes\BpHashBobJenkinsUnit.pas';

begin
  System.ReportMemoryLeaksOnShutdown := True;

  Readln;
end.

