unit BpTestSupport;

// What more than one test unit needs: a message pump for the marshalled task
// tests, and scratch files for the tests that assert on what a download left
// on disk. Every wait here takes a timeout, because an unattended suite must
// fail loudly rather than hang at three in the morning.

interface

// dispatches whatever is already queued; a marshalled task needs this to fire
procedure BpPumpMessages;
// False on timeout, so the caller can fail with its own message
function BpPumpUntilFlag(var aFlag: Boolean; aTimeoutMs: Cardinal): Boolean;
function BpPumpUntilCount(var aCounter: Integer; aTarget: Integer;
  aTimeoutMs: Cardinal): Boolean;
// to prove that nothing arrives
procedure BpPumpFor(aMs: Cardinal);

function BpTempFilePath(const aName: string): string;
// a scratch directory of its own turns "no temp file left behind" into a count
function BpMakeTempDir(const aPrefix: string): string;
procedure BpDeleteTree(const aDir: string);
function BpCountFiles(const aDir: string): Integer;
function BpReadWholeFile(const aFileName: string): AnsiString;
procedure BpWriteWholeFile(const aFileName: string; const aBody: AnsiString);
function BpRepeated(aByte: Byte; aCount: Integer): AnsiString;

implementation

uses
  SysUtils, Classes, Windows;

procedure BpPumpMessages;
var
  lvMsg: TMsg;
begin
  while PeekMessage(lvMsg, 0, 0, 0, PM_REMOVE) do
  begin
    TranslateMessage(lvMsg);
    DispatchMessage(lvMsg);
  end;
end;

function BpPumpUntilFlag(var aFlag: Boolean; aTimeoutMs: Cardinal): Boolean;
var
  lvDeadline: Cardinal;
begin
  lvDeadline := GetTickCount + aTimeoutMs;
  while not aFlag and (GetTickCount < lvDeadline) do
  begin
    BpPumpMessages;
    Sleep(5);
  end;
  Result := aFlag;
end;

function BpPumpUntilCount(var aCounter: Integer; aTarget: Integer;
  aTimeoutMs: Cardinal): Boolean;
var
  lvDeadline: Cardinal;
begin
  lvDeadline := GetTickCount + aTimeoutMs;
  while (aCounter < aTarget) and (GetTickCount < lvDeadline) do
  begin
    BpPumpMessages;
    Sleep(5);
  end;
  Result := aCounter >= aTarget;
end;

procedure BpPumpFor(aMs: Cardinal);
var
  lvDeadline: Cardinal;
begin
  lvDeadline := GetTickCount + aMs;
  while GetTickCount < lvDeadline do
  begin
    BpPumpMessages;
    Sleep(5);
  end;
end;

function BpTempFilePath(const aName: string): string;
var
  lvBuffer: array[0..MAX_PATH] of Char;
begin
  GetTempPath(MAX_PATH, lvBuffer);
  Result := IncludeTrailingPathDelimiter(lvBuffer) + aName;
end;

function BpMakeTempDir(const aPrefix: string): string;
begin
  Result := BpTempFilePath(Format('%s_%d_%d',
    [aPrefix, GetCurrentProcessId, GetTickCount]));
  ForceDirectories(Result);
end;

procedure BpDeleteTree(const aDir: string);
var
  lvSearch: TSearchRec;
  lvPath: string;
begin
  lvPath := IncludeTrailingPathDelimiter(aDir);
  if FindFirst(lvPath + '*', faAnyFile, lvSearch) = 0 then
  try
    repeat
      if (lvSearch.Attr and faDirectory) = 0 then
        SysUtils.DeleteFile(lvPath + lvSearch.Name);
    until FindNext(lvSearch) <> 0;
  finally
    SysUtils.FindClose(lvSearch);
  end;
  RemoveDir(aDir);
end;

function BpCountFiles(const aDir: string): Integer;
var
  lvSearch: TSearchRec;
begin
  Result := 0;
  if FindFirst(IncludeTrailingPathDelimiter(aDir) + '*', faAnyFile,
    lvSearch) <> 0 then
    Exit;
  try
    repeat
      if (lvSearch.Attr and faDirectory) = 0 then
        Inc(Result);
    until FindNext(lvSearch) <> 0;
  finally
    SysUtils.FindClose(lvSearch);
  end;
end;

function BpReadWholeFile(const aFileName: string): AnsiString;
var
  lvStream: TFileStream;
begin
  lvStream := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, lvStream.Size);
    if Result <> '' then
      lvStream.ReadBuffer(Result[1], Length(Result));
  finally
    lvStream.Free;
  end;
end;

procedure BpWriteWholeFile(const aFileName: string; const aBody: AnsiString);
var
  lvStream: TFileStream;
begin
  lvStream := TFileStream.Create(aFileName, fmCreate);
  try
    if aBody <> '' then
      lvStream.WriteBuffer(aBody[1], Length(aBody));
  finally
    lvStream.Free;
  end;
end;

function BpRepeated(aByte: Byte; aCount: Integer): AnsiString;
begin
  SetLength(Result, aCount);
  FillChar(Result[1], aCount, aByte);
end;

end.
