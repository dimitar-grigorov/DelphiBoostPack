unit BpPathUtils;

// The Windows path relation - same path, under that path - and the arithmetic
// around it. Case folds through BpKeyFold, never SameText. Textual throughout:
// nothing resolves '.' or '..', and only BpPathCanonicalCase reads the disk.
// A URL is not a path and gets no shape here; BpHttpClient parses those.

interface

type
  // the nine shapes a Windows path takes
  TBpPathKind = (
    pkRelative,       // x\y
    pkRooted,         // \x, the current drive's root
    pkDriveRelative,  // C:x, the current directory on C: and not C:\x
    pkDisk,           // C:\x
    pkUnc,            // \\server\share\x
    pkVerbatim,       // \\?\x and \??\x, where Windows parses nothing
    pkVerbatimDisk,   // \\?\C:\x
    pkVerbatimUnc,    // \\?\UNC\server\share\x
    pkDevice          // \\.\PhysicalDrive0
  );

// the shape, and in aRootLen the root with its closing separator: C:\x is 3
function BpPathClassify(const aPath: string; out aRootLen: Integer): TBpPathKind;

// '\' -> '/', one trailing separator dropped; no case change, nothing resolved
function BpPathNormalize(const aPath: string): string;

function BpPathSame(const aPathA, aPathB: string): Boolean;

// strict: equal is not under, and C:\Src\App never matches C:\Src\AppData
function BpPathIsUnder(const aPath, aRoot: string): Boolean;

function BpPathIsSameOrUnder(const aPath, aRoot: string): Boolean;

// True when aPath is strictly under any of aRoots; a blank root matches nothing
function BpPathUnderAnyRoot(const aPath: string;
  const aRoots: array of string): Boolean;

// aPath's tail below aRoot in aPath's own case, '' when not strictly under
function BpPathRelativeTo(const aPath, aRoot: string): string;

// the form git, GitLab and every other wire protocol expects
function BpPathToSlash(const aPath: string): string;

// the form the Win32 API and the shell expect
function BpPathToBackslash(const aPath: string): string;

// aBase and aRelative joined; a rooted aRelative wins and aBase is dropped
function BpPathCombine(const aBase, aRelative: string): string;

// aPath as the file system spells it; the only function here that reads the disk
function BpPathCanonicalCase(const aPath: string): string;

implementation

uses
  Windows, SysUtils, BpKeyFold;

const
  // the shapes Windows parses nothing inside, where '/' is a filename character
  cDeviceKinds = [pkVerbatim, pkVerbatimDisk, pkVerbatimUnc, pkDevice];

function IsSep(aCh: Char): Boolean;
begin
  Result := (aCh = '\') or (aCh = '/');
end;

// ASCII only; no Windows volume designator has ever been anything else
function IsDriveLetter(aCh: Char): Boolean;
begin
  Result := ((aCh >= 'A') and (aCh <= 'Z')) or ((aCh >= 'a') and (aCh <= 'z'));
end;

// only the canonical backslashes skip normalisation, so //?/C:/x is not verbatim
function HasExtendedPrefix(const aPath: string): Boolean;
begin
  Result := (Length(aPath) >= 4) and (aPath[1] = '\') and
    ((aPath[2] = '\') or (aPath[2] = '?')) and (aPath[3] = '?') and
    (aPath[4] = '\');
end;

function HasDevicePrefix(const aPath: string): Boolean;
begin
  Result := (Length(aPath) >= 4) and IsSep(aPath[1]) and IsSep(aPath[2]) and
    ((aPath[3] = '.') or (aPath[3] = '?')) and IsSep(aPath[4]);
end;

// the object manager's UNC symlink is case-insensitive, so \\?\unc\ is one too
function HasVerbatimUncPrefix(const aPath: string): Boolean;
begin
  Result := (Length(aPath) >= 8) and (UpCase(aPath[5]) = 'U') and
    (UpCase(aPath[6]) = 'N') and (UpCase(aPath[7]) = 'C') and IsSep(aPath[8]);
end;

// '/' does not separate inside a verbatim path, so only a backslash ends a drive
function HasVerbatimDrive(const aPath: string): Boolean;
begin
  Result := (Length(aPath) >= 6) and IsDriveLetter(aPath[5]) and
    (aPath[6] = ':') and ((Length(aPath) = 6) or (aPath[7] = '\'));
end;

// only a backslash separates inside a verbatim path, where '/' is a name character
function IsSepIn(aCh: Char; aVerbatim: Boolean): Boolean;
begin
  if aVerbatim then
    Result := aCh = '\'
  else
    Result := IsSep(aCh);
end;

// aStart is the first character past the prefix; the root spans server and share
function UncRootLen(const aPath: string; aStart: Integer;
  aVerbatim: Boolean): Integer;
var
  lvIdx, lvLeft: Integer;
begin
  lvIdx := aStart;
  lvLeft := 2;
  while lvIdx <= Length(aPath) do
  begin
    if IsSepIn(aPath[lvIdx], aVerbatim) then
    begin
      Dec(lvLeft);
      if lvLeft = 0 then
        Break;
    end;
    Inc(lvIdx);
  end;
  if lvIdx <= Length(aPath) then
    Result := lvIdx
  else
    Result := Length(aPath);
end;

function BpPathClassify(const aPath: string; out aRootLen: Integer): TBpPathKind;
var
  lvIdx: Integer;
begin
  aRootLen := 0;
  if aPath = '' then
  begin
    Result := pkRelative;
    Exit;
  end;

  if HasExtendedPrefix(aPath) then
  begin
    if HasVerbatimUncPrefix(aPath) then
    begin
      Result := pkVerbatimUnc;
      aRootLen := UncRootLen(aPath, 9, True);
      Exit;
    end;
    if HasVerbatimDrive(aPath) then
    begin
      Result := pkVerbatimDisk;
      if Length(aPath) >= 7 then
        aRootLen := 7
      else
        aRootLen := 6;
      Exit;
    end;
    Result := pkVerbatim;
  end
  else if HasDevicePrefix(aPath) then
    Result := pkDevice
  else if IsSep(aPath[1]) then
  begin
    if (Length(aPath) >= 2) and IsSep(aPath[2]) then
    begin
      Result := pkUnc;
      aRootLen := UncRootLen(aPath, 3, False);
    end
    else
    begin
      Result := pkRooted;
      aRootLen := 1;
    end;
    Exit;
  end
  else if (Length(aPath) >= 2) and (aPath[2] = ':') and
    IsDriveLetter(aPath[1]) then
  begin
    if (Length(aPath) >= 3) and IsSep(aPath[3]) then
    begin
      Result := pkDisk;
      aRootLen := 3;
    end
    else
    begin
      Result := pkDriveRelative;
      aRootLen := 2;
    end;
    Exit;
  end
  else
  begin
    Result := pkRelative;
    Exit;
  end;

  // pkVerbatim and pkDevice root on the prefix plus one non-empty component
  lvIdx := 5;
  while (lvIdx <= Length(aPath)) and
    not IsSepIn(aPath[lvIdx], Result = pkVerbatim) do
    Inc(lvIdx);
  if (lvIdx <= Length(aPath)) and (lvIdx > 5) then
    Inc(lvIdx);
  aRootLen := lvIdx - 1;
end;

function IsDeviceShape(const aPath: string): Boolean;
var
  lvRootLen: Integer;
begin
  Result := BpPathClassify(aPath, lvRootLen) in cDeviceKinds;
end;

function BpPathToSlash(const aPath: string): string;
begin
  if IsDeviceShape(aPath) then
    Result := aPath
  else
    Result := StringReplace(aPath, '\', '/', [rfReplaceAll]);
end;

function BpPathToBackslash(const aPath: string): string;
begin
  if IsDeviceShape(aPath) then
    Result := aPath
  else
    Result := StringReplace(aPath, '/', '\', [rfReplaceAll]);
end;

function BpPathNormalize(const aPath: string): string;
begin
  Result := BpPathToSlash(aPath);
  // '/' and '//' are their own root, and trimming that changes the path's shape
  if (Length(Result) > 1) and (Result[Length(Result)] = '/') and
    not IsSep(Result[Length(Result) - 1]) then
    SetLength(Result, Length(Result) - 1);
end;

function BpPathSame(const aPathA, aPathB: string): Boolean;
begin
  Result := BpFoldedSame(BpPathNormalize(aPathA), BpPathNormalize(aPathB));
end;

// where aPath's tail below aRoot starts, 0 when aPath is not strictly under it
function UnderTailStart(const aNormPath, aNormRoot: string): Integer;
begin
  Result := 0;
  if (aNormPath = '') or (aNormRoot = '') then
    Exit;
  if Length(aNormPath) <= Length(aNormRoot) then
    Exit;
  if IsSep(aNormRoot[Length(aNormRoot)]) then
    // a root ending in its own separator, like '/' or \\?\C:\, needs no second
    Result := Length(aNormRoot) + 1
  else if IsSep(aNormPath[Length(aNormRoot) + 1]) then
    Result := Length(aNormRoot) + 2
  else
    Exit;
  if Result > Length(aNormPath) then
  begin
    Result := 0;
    Exit;
  end;
  // buffer compare: the prefix is folded in place, without copying it out
  if not BpKeyEqualsBuf(aNormRoot, PChar(aNormPath), Length(aNormRoot), True) then
    Result := 0;
end;

function BpPathIsUnder(const aPath, aRoot: string): Boolean;
begin
  Result := UnderTailStart(BpPathNormalize(aPath), BpPathNormalize(aRoot)) > 0;
end;

function BpPathIsSameOrUnder(const aPath, aRoot: string): Boolean;
begin
  Result := BpPathSame(aPath, aRoot) or BpPathIsUnder(aPath, aRoot);
end;

function BpPathUnderAnyRoot(const aPath: string;
  const aRoots: array of string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := Low(aRoots) to High(aRoots) do
    // a root read out of a settings file arrives with the user's spaces on it
    if BpPathIsUnder(aPath, Trim(aRoots[i])) then
    begin
      Result := True;
      Exit;
    end;
end;

function BpPathRelativeTo(const aPath, aRoot: string): string;
var
  lvStart: Integer;
begin
  lvStart := UnderTailStart(BpPathNormalize(aPath), BpPathNormalize(aRoot));
  if lvStart = 0 then
    Result := ''
  else
    // off the untrimmed form, so a directory argument keeps its trailing slash
    Result := Copy(BpPathToSlash(aPath), lvStart, MaxInt);
end;

function BpPathCombine(const aBase, aRelative: string): string;
var
  lvRootLen, i: Integer;
  lvSep: Char;
begin
  if aRelative = '' then
  begin
    Result := aBase;
    Exit;
  end;
  BpPathClassify(aRelative, lvRootLen);
  // a rooted tail replaces the base; the popular convention, and the safer one
  if (aBase = '') or (lvRootLen > 0) then
  begin
    Result := aRelative;
    Exit;
  end;
  if IsSep(aBase[Length(aBase)]) then
  begin
    Result := aBase + aRelative;
    Exit;
  end;
  // the base's own separator, so a '/' base does not come back mixed
  lvSep := '\';
  for i := Length(aBase) downto 1 do
    if IsSep(aBase[i]) then
    begin
      lvSep := aBase[i];
      Break;
    end;
  Result := aBase + lvSep + aRelative;
end;

function BpPathCanonicalCase(const aPath: string): string;
var
  lvRootLen, lvPos, i: Integer;
  lvRest, lvComp, lvProbe: string;
  lvSep: Char;
  lvFind: TWin32FindData;
  lvHandle: THandle;
begin
  Result := aPath;
  // only a drive-rooted path has an anchor to walk down from
  if BpPathClassify(aPath, lvRootLen) <> pkDisk then
    Exit;

  // Windows reports the volume designator upper case; not doing so was the bug
  Result := UpCase(aPath[1]) + Copy(aPath, 2, lvRootLen - 1);
  // lvProbe looks up in the caller's case; Result takes the names echoed back
  lvProbe := Result;
  lvRest := Copy(aPath, lvRootLen + 1, MaxInt);

  while lvRest <> '' do
  begin
    lvPos := 0;
    for i := 1 to Length(lvRest) do
      if IsSep(lvRest[i]) then
      begin
        lvPos := i;
        Break;
      end;
    if lvPos > 0 then
    begin
      lvComp := Copy(lvRest, 1, lvPos - 1);
      lvSep := lvRest[lvPos];
      lvRest := Copy(lvRest, lvPos + 1, MaxInt);
    end
    else
    begin
      lvComp := lvRest;
      lvSep := #0;
      lvRest := '';
    end;

    if lvComp <> '' then
    begin
      // GetLongPathName expands 8.3 names and not case, so FindFirstFile echoes
      lvHandle := FindFirstFile(PChar(lvProbe + lvComp), lvFind);
      if lvHandle <> INVALID_HANDLE_VALUE then
      begin
        Windows.FindClose(lvHandle);
        Result := Result + lvFind.cFileName;
      end
      else
        Result := Result + lvComp;
      lvProbe := lvProbe + lvComp + '\';
    end;
    if lvSep <> #0 then
      Result := Result + lvSep;
  end;
end;

end.
