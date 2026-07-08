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
  BpStrDictionary in 'Core\Classes\BpStrDictionary.pas',
  BpStringBuilder in 'Core\Classes\BpStringBuilder.pas',
  BpMD5 in 'Core\Classes\BpMD5.pas',
  BpSHA256 in 'Core\Classes\BpSHA256.pas',
  BpBase64 in 'Core\Units\BpBase64.pas',
  BpStrUtils in 'Core\Units\BpStrUtils.pas',
  BpSysUtils in 'Core\Units\BpSysUtils.pas',
  StopWatch in 'Core\Units\StopWatch.pas';

begin
  System.ReportMemoryLeaksOnShutdown := True;

  Readln;
end.

