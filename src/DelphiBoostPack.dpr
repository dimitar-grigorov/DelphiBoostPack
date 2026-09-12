program DelphiBoostPack;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  BpIntList in 'Core\Classes\BpIntList.pas',
  BpInt64List in 'Core\Classes\BpInt64List.pas',
  BpObjectComparer in 'Core\Classes\BpObjectComparer.pas',
  UniqueIdIntf in 'Core\Interfaces\UniqueIdIntf.pas',
  InterfacedCollectionItem in 'Core\Classes\InterfacedCollectionItem.pas',
  BpHashBobJenkins in 'Core\Classes\BpHashBobJenkins.pas',
  BpStrDictionary in 'Core\Classes\BpStrDictionary.pas',
  BpStringBuilder in 'Core\Classes\BpStringBuilder.pas',
  BpHMACSHA256 in 'Core\Classes\BpHMACSHA256.pas',
  BpCredentials in 'Core\Classes\BpCredentials.pas',
  BpHttpClient in 'Core\Classes\BpHttpClient.pas',
  BpIntDictionary in 'Core\Classes\BpIntDictionary.pas',
  BpJson in 'Core\Classes\BpJson.pas',
  BpMD5 in 'Core\Classes\BpMD5.pas',
  BpPasswordHash in 'Core\Classes\BpPasswordHash.pas',
  BpSHA256 in 'Core\Classes\BpSHA256.pas',
  BpTasks in 'Core\Classes\BpTasks.pas',
  BpBase64 in 'Core\Units\BpBase64.pas',
  BpDateUtils in 'Core\Units\BpDateUtils.pas',
  BpStrUtils in 'Core\Units\BpStrUtils.pas',
  BpSysUtils in 'Core\Units\BpSysUtils.pas',
  BpVariantUtils in 'Core\Units\BpVariantUtils.pas',
  StopWatch in 'Core\Units\StopWatch.pas',
  BpKeyFold in 'Core\Units\BpKeyFold.pas',
  BpPathUtils in 'Core\Units\BpPathUtils.pas',
  BpStringList in 'Core\Classes\BpStringList.pas',
  BpCompat in 'Core\Units\BpCompat.pas',
  BpHttpTrace in 'Core\Classes\BpHttpTrace.pas';

begin
  {$IF CompilerVersion > 15.0}
  System.ReportMemoryLeaksOnShutdown := True;
  {$IFEND}

  Readln;
end.

