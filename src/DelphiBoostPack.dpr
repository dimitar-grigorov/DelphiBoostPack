program DelphiBoostPack;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  BpIntList in 'Core\Classes\BpIntList.pas',
  BpIntListIntf in 'Core\Interfaces\BpIntListIntf.pas',
  BpObjectComparer in 'Core\Classes\BpObjectComparer.pas',
  UniqueIdIntf in 'Core\Interfaces\UniqueIdIntf.pas',
  InterfacedCollectionItem in 'Core\Classes\InterfacedCollectionItem.pas',
  BpHashBobJenkins in 'Core\Classes\BpHashBobJenkins.pas',
  BpSysUtils in 'Core\Units\BpSysUtils.pas',
  StopWatch in 'Core\Units\StopWatch.pas';
  //BpDictionary in 'Core\Classes\BpDictionary.pas';

begin
  System.ReportMemoryLeaksOnShutdown := True;

  Readln;
end.

