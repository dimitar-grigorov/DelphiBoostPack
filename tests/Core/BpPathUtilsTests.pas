unit BpPathUtilsTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, Windows, SysUtils, BpPathUtils;

type
  TBpPathUtilsTests = class(TTestCase)
  private
    FTempDir: string;
    function NonAsciiCasePair(out aLower, aUpper: Char): Boolean;
    procedure CheckKind(const aPath: string; aKind: TBpPathKind;
      aRootLen: Integer);
    procedure CheckIsDisk(const aPath, aMsg: string);
  protected
    procedure TearDown; override;
  published
    procedure TestClassifyTheNineShapes;
    procedure TestClassifyRootLengthAtTheEdges;
    procedure TestNormalizeMapsSeparatorsAndTrimsOne;
    procedure TestNormalizeLeavesARootAlone;
    procedure TestNormalizeLeavesADevicePathUntouched;
    procedure TestSameIgnoresSeparatorTrailingSlashAndCase;
    procedure TestSameFoldsOutsideAscii;
    procedure TestIsUnderIsStrictAtBothEnds;
    procedure TestIsUnderOnAPathEqualToItsRoot;
    procedure TestIsUnderAcrossMixedSeparators;
    procedure TestIsUnderOfADriveRoot;
    procedure TestRelativeToKeepsTheCallersCase;
    procedure TestRelativeToOutsideTheRootIsEmpty;
    procedure TestRelativeToKeepsATrailingSlash;
    procedure TestUnderAnyRootSkipsBlankRoots;
    procedure TestSeparatorConversionRoundTrips;
    procedure TestSeparatorConversionLeavesADevicePathAlone;
    procedure TestCombineJoinsAndLetsARootedTailWin;
    procedure TestEveryPathResultKeepsTheShapeItWasGiven;
    procedure TestCanonicalCaseSpellsComponentsAsTheDiskDoes;
    procedure TestCanonicalCaseUpperCasesTheDriveLetter;
    procedure TestCanonicalCaseReturnsWhatItCannotAnchor;
  end;

implementation

uses
  BpTestSupport;

procedure TBpPathUtilsTests.TearDown;
begin
  if FTempDir <> '' then
  begin
    BpDeleteTree(FTempDir + '\MiXeD');
    BpDeleteTree(FTempDir);
    FTempDir := '';
  end;
  inherited;
end;

// a cased pair outside ASCII, so the test means the same on a Greek install
function TBpPathUtilsTests.NonAsciiCasePair(out aLower, aUpper: Char): Boolean;
var
  i: Integer;
  lvLower, lvUpper: string;
begin
  Result := False;
  for i := 128 to 255 do
  begin
    lvLower := Chr(i);
    lvUpper := AnsiUpperCase(lvLower);
    if (Length(lvUpper) = 1) and (lvUpper[1] <> lvLower[1]) and
      (AnsiLowerCase(lvUpper) = lvLower) then
    begin
      aLower := lvLower[1];
      aUpper := lvUpper[1];
      Result := True;
      Exit;
    end;
  end;
end;

procedure TBpPathUtilsTests.CheckKind(const aPath: string; aKind: TBpPathKind;
  aRootLen: Integer);
var
  lvRootLen: Integer;
begin
  CheckEquals(Ord(aKind), Ord(BpPathClassify(aPath, lvRootLen)),
    'kind of ' + aPath);
  CheckEquals(aRootLen, lvRootLen, 'root length of ' + aPath);
end;

procedure TBpPathUtilsTests.CheckIsDisk(const aPath, aMsg: string);
var
  lvRootLen: Integer;
begin
  CheckEquals(Ord(pkDisk), Ord(BpPathClassify(aPath, lvRootLen)),
    aMsg + ' returned ' + aPath);
end;

procedure TBpPathUtilsTests.TestClassifyTheNineShapes;
begin
  CheckKind('x\y', pkRelative, 0);
  CheckKind('\x', pkRooted, 1);
  CheckKind('C:x', pkDriveRelative, 2);
  CheckKind('C:\x', pkDisk, 3);
  CheckKind('\\server\share\x', pkUnc, 15);
  CheckKind('\\?\x\y', pkVerbatim, 6);
  CheckKind('\\?\C:\x', pkVerbatimDisk, 7);
  CheckKind('\\?\UNC\server\share\x', pkVerbatimUnc, 21);
  CheckKind('\\.\PhysicalDrive0', pkDevice, 18);
end;

procedure TBpPathUtilsTests.TestClassifyRootLengthAtTheEdges;
begin
  CheckKind('', pkRelative, 0);
  CheckKind('C:', pkDriveRelative, 2);
  CheckKind('\\server\share', pkUnc, 14);
  CheckKind('\\?\UNC\server\share', pkVerbatimUnc, 20);
  CheckKind('\\?\C:', pkVerbatimDisk, 6);
  // '/' does not separate inside a verbatim path, so C:/x is one component
  CheckKind('\\?\C:/x', pkVerbatim, 8);
  CheckKind('\\?\UNC\server/share\x', pkVerbatimUnc, 22);
  // the NT spelling of the same prefix
  CheckKind('\??\x', pkVerbatim, 5);
  // normalisation is skipped only for the canonical backslashes
  CheckKind('//?/C:/x', pkDevice, 7);
  // 4: the component after the prefix is empty, so no separator is taken
  CheckKind('\\?\\', pkVerbatim, 4);
end;

procedure TBpPathUtilsTests.TestNormalizeMapsSeparatorsAndTrimsOne;
begin
  CheckEquals('C:/a/b', BpPathNormalize('C:\a\b'), 'backslashes map to slashes');
  CheckEquals('C:/a/b', BpPathNormalize('C:\a\b\'), 'one trailing separator goes');
  CheckEquals('C:/a/b', BpPathNormalize('C:/a/b/'), 'either kind of trailing separator');
  CheckEquals('C:/a/b', BpPathNormalize('C:/a\b'), 'mixed separators');
  CheckEquals('', BpPathNormalize(''), 'the empty path');
  CheckEquals('a/b', BpPathNormalize('a\b'), 'a relative path');
end;

procedure TBpPathUtilsTests.TestNormalizeLeavesARootAlone;
begin
  CheckEquals('C:', BpPathNormalize('C:\'), 'a drive root keeps no separator');
  CheckEquals('/', BpPathNormalize('\'), 'the current drive root is its separator');
  CheckEquals('//', BpPathNormalize('\\'), 'and so is a bare UNC prefix');
  CheckEquals('//server/share', BpPathNormalize('\\server\share\'), 'a share');
end;

procedure TBpPathUtilsTests.TestNormalizeLeavesADevicePathUntouched;
begin
  CheckEquals('\\?\C:\x', BpPathNormalize('\\?\C:\x'), 'a verbatim disk path');
  CheckEquals('\\?\C:\x\', BpPathNormalize('\\?\C:\x\'),
    'even its trailing separator, which is a real character there');
  CheckEquals('\\?\UNC\server\share\x', BpPathNormalize('\\?\UNC\server\share\x'),
    'a verbatim UNC path');
  CheckEquals('\\.\PhysicalDrive0', BpPathNormalize('\\.\PhysicalDrive0'),
    'a device path');
end;

procedure TBpPathUtilsTests.TestSameIgnoresSeparatorTrailingSlashAndCase;
begin
  CheckTrue(BpPathSame('C:\a\b', 'C:/a/b'), 'separators');
  CheckTrue(BpPathSame('C:\a\b', 'C:\a\b\'), 'a trailing separator');
  CheckTrue(BpPathSame('C:\A\B', 'c:\a\b'), 'case');
  CheckTrue(BpPathSame('', ''), 'two empty paths');
  CheckFalse(BpPathSame('C:\a\b', 'C:\a\c'), 'different paths');
  CheckFalse(BpPathSame('C:\a\b', ''), 'a path against nothing');
end;

procedure TBpPathUtilsTests.TestSameFoldsOutsideAscii;
var
  lvLower, lvUpper: Char;
  lvPathA, lvPathB: string;
begin
  if not NonAsciiCasePair(lvLower, lvUpper) then
  begin
    Check(True, 'this code page has no cased character outside ASCII');
    Exit;
  end;
  lvPathA := 'C:\' + lvLower + lvLower + '\Unit.pas';
  lvPathB := 'C:\' + lvUpper + lvUpper + '\Unit.pas';
  CheckTrue(BpPathSame(lvPathA, lvPathB),
    'a case-only difference outside ASCII is still the same path');
  CheckEquals(AnsiSameText(lvPathA, lvPathB), BpPathSame(lvPathA, lvPathB),
    'the relation agrees with the RTL');
  CheckTrue(BpPathIsUnder(lvPathB, 'C:\' + lvLower + lvLower),
    'and a root in the other case still contains it');
  {$IF CompilerVersion < 20.0}
  // the regression this relation exists for: SameText folds 'A'..'Z' only
  CheckFalse(SameText(lvPathA, lvPathB), 'SameText is ASCII only before Delphi 2009');
  {$IFEND}
end;

procedure TBpPathUtilsTests.TestIsUnderIsStrictAtBothEnds;
begin
  CheckTrue(BpPathIsUnder('C:\Src\App\Unit.pas', 'C:\Src\App'), 'a file below the root');
  CheckFalse(BpPathIsUnder('C:\Src\AppData', 'C:\Src\App'),
    'a sibling that merely starts with the root');
  CheckFalse(BpPathIsUnder('C:\Src\App', 'C:\Src\AppData'), 'and the other way round');
  CheckFalse(BpPathIsUnder('C:\Src\App', ''), 'an empty root');
  CheckFalse(BpPathIsUnder('', 'C:\Src\App'), 'an empty path');
end;

procedure TBpPathUtilsTests.TestIsUnderOnAPathEqualToItsRoot;
begin
  CheckFalse(BpPathIsUnder('C:\Src\App', 'C:\Src\App'), 'equal is not under');
  CheckFalse(BpPathIsUnder('C:\Src\App\', 'C:\Src\App'), 'nor with a trailing separator');
  CheckTrue(BpPathIsSameOrUnder('C:\Src\App', 'C:\Src\App'), 'but it is same-or-under');
  CheckTrue(BpPathIsSameOrUnder('C:\Src\App\Unit.pas', 'C:\Src\App'), 'and so is a child');
  CheckFalse(BpPathIsSameOrUnder('C:\Src\AppData', 'C:\Src\App'), 'the sibling is neither');
end;

procedure TBpPathUtilsTests.TestIsUnderAcrossMixedSeparators;
begin
  CheckTrue(BpPathIsUnder('C:/Src/App/Unit.pas', 'C:\Src\App'), 'slashes below backslashes');
  CheckTrue(BpPathIsUnder('C:\Src\App\Unit.pas', 'C:/Src/App'), 'and the other way round');
  CheckTrue(BpPathIsUnder('C:\Src\App\Unit.pas', 'C:\Src\App\'), 'a trailing separator on the root');
  CheckTrue(BpPathIsUnder('C:\Src\App\Sub\', 'C:\Src\App'), 'a trailing separator on the path');
  CheckTrue(BpPathIsUnder('c:\src\app\Unit.pas', 'C:\SRC\APP'), 'and case on both');
end;

procedure TBpPathUtilsTests.TestIsUnderOfADriveRoot;
begin
  CheckTrue(BpPathIsUnder('C:\Src', 'C:\'), 'everything on the drive is under its root');
  CheckFalse(BpPathIsUnder('C:\', 'C:\'), 'except the root itself');
  CheckTrue(BpPathIsUnder('\Src', '\'), 'the current drive root does the same');
  CheckTrue(BpPathIsUnder('\\server\share\x', '\\server\share'),
    'a share is a directory for this question');
  CheckTrue(BpPathIsUnder('\\?\C:\a\b', '\\?\C:\a'), 'and a verbatim root works too');
end;

procedure TBpPathUtilsTests.TestRelativeToKeepsTheCallersCase;
begin
  CheckEquals('Sub/Unit.PAS', BpPathRelativeTo('C:\Src\App\Sub\Unit.PAS', 'c:\src\app'),
    'the tail comes back in the caller''s case, not the folded one');
  CheckEquals('Unit.pas', BpPathRelativeTo('C:\Src\App\Unit.pas', 'C:\Src\App\'),
    'a root with a trailing separator');
  CheckEquals('x', BpPathRelativeTo('\x', '\'), 'below the current drive root');
end;

procedure TBpPathUtilsTests.TestRelativeToOutsideTheRootIsEmpty;
begin
  CheckEquals('', BpPathRelativeTo('C:\Other\Unit.pas', 'C:\Src\App'), 'a different root');
  CheckEquals('', BpPathRelativeTo('C:\Src\App', 'C:\Src\App'), 'the root itself');
  CheckEquals('', BpPathRelativeTo('C:\Src\AppData\x', 'C:\Src\App2'), 'a sibling');
  CheckEquals('', BpPathRelativeTo('D:\Src\App\x', 'C:\Src\App'), 'another drive');
end;

procedure TBpPathUtilsTests.TestRelativeToKeepsATrailingSlash;
begin
  CheckEquals('Sub/', BpPathRelativeTo('C:\Src\App\Sub\', 'C:\Src\App'),
    'a directory argument keeps the separator it was given');
end;

procedure TBpPathUtilsTests.TestUnderAnyRootSkipsBlankRoots;
begin
  CheckTrue(BpPathUnderAnyRoot('C:\a\b\Unit.pas', ['C:\z', '', 'C:\a\b']),
    'one root out of several matches');
  CheckTrue(BpPathUnderAnyRoot('C:\a\b\Unit.pas', ['  C:\a\b  ']),
    'a root out of a settings file keeps its spaces');
  CheckFalse(BpPathUnderAnyRoot('C:\a\b\Unit.pas', ['C:\z', 'D:\a\b']), 'no root matches');
  CheckFalse(BpPathUnderAnyRoot('C:\a\b\Unit.pas', ['', '   ']),
    'a blank root matches nothing rather than everything');
  CheckFalse(BpPathUnderAnyRoot('C:\a\b\Unit.pas', []), 'no root at all');
end;

procedure TBpPathUtilsTests.TestSeparatorConversionRoundTrips;
begin
  CheckEquals('C:/a/b', BpPathToSlash('C:\a\b'), 'to the wire');
  CheckEquals('C:\a\b', BpPathToBackslash('C:/a/b'), 'and back to Windows');
  CheckEquals('C:\a\b', BpPathToBackslash(BpPathToSlash('C:\a\b')), 'a round trip');
  CheckEquals('C:/a/b', BpPathToSlash(BpPathToBackslash('C:/a/b')), 'the other round trip');
  CheckEquals('C:/a/b', BpPathToSlash('C:/a\b'), 'mixed separators to the wire');
  CheckEquals('', BpPathToSlash(''), 'the empty path');
end;

procedure TBpPathUtilsTests.TestSeparatorConversionLeavesADevicePathAlone;
begin
  CheckEquals('\\?\C:\a\b', BpPathToSlash('\\?\C:\a\b'),
    'inside a verbatim path a slash is a filename character');
  CheckEquals('\\?\C:\a/b', BpPathToBackslash('\\?\C:\a/b'), 'so it is not a separator either');
  CheckEquals('\\.\PhysicalDrive0', BpPathToSlash('\\.\PhysicalDrive0'), 'a device path');
end;

procedure TBpPathUtilsTests.TestCombineJoinsAndLetsARootedTailWin;
begin
  CheckEquals('C:\a\b', BpPathCombine('C:\a', 'b'), 'the base gets its separator');
  CheckEquals('C:\a\b', BpPathCombine('C:\a\', 'b'), 'and keeps the one it has');
  CheckEquals('C:/a/b', BpPathCombine('C:/a', 'b'), 'a slash base joins with a slash');
  CheckEquals('C:\a\b\c', BpPathCombine('C:\a', 'b\c'), 'a relative tail of several parts');
  CheckEquals('D:\b', BpPathCombine('C:\a', 'D:\b'), 'a rooted tail wins');
  CheckEquals('\b', BpPathCombine('C:\a', '\b'), 'so does one rooted on the current drive');
  CheckEquals('C:b', BpPathCombine('D:\a', 'C:b'), 'and a drive-relative one');
  CheckEquals('C:\a', BpPathCombine('C:\a', ''), 'an empty tail changes nothing');
  CheckEquals('b', BpPathCombine('', 'b'), 'and an empty base is not a separator');
end;

procedure TBpPathUtilsTests.TestEveryPathResultKeepsTheShapeItWasGiven;
var
  lvRootLen: Integer;
begin
  CheckIsDisk(BpPathNormalize('C:\a\b'), 'Normalize');
  CheckIsDisk(BpPathToSlash('C:\a\b'), 'ToSlash');
  CheckIsDisk(BpPathToBackslash('C:/a/b'), 'ToBackslash');
  CheckIsDisk(BpPathCombine('C:\a', 'b'), 'Combine');
  CheckIsDisk(BpPathCanonicalCase('C:\a\b'), 'CanonicalCase');
  // RelativeTo is the one that is meant to change the shape, to exactly this
  CheckEquals(Ord(pkRelative),
    Ord(BpPathClassify(BpPathRelativeTo('C:\a\b', 'C:\a'), lvRootLen)),
    'RelativeTo returns a relative path');
end;

procedure TBpPathUtilsTests.TestCanonicalCaseSpellsComponentsAsTheDiskDoes;
var
  lvBase: string;
begin
  FTempDir := BpMakeTempDir('BpPath');
  CreateDir(FTempDir + '\MiXeD');
  BpWriteWholeFile(FTempDir + '\MiXeD\FiLe.TxT', 'x');
  // the scratch root itself may be an 8.3 alias, so both sides walk it
  lvBase := BpPathCanonicalCase(FTempDir);

  CheckEquals(lvBase + '\MiXeD\FiLe.TxT',
    BpPathCanonicalCase(FTempDir + '\mixed\file.txt'),
    'each component comes back spelled the way the disk spells it');
  CheckEquals(lvBase + '\MiXeD\',
    BpPathCanonicalCase(FTempDir + '\MIXED\'),
    'a trailing separator survives the walk');
  CheckEquals(lvBase + '\MiXeD\Absent.txt',
    BpPathCanonicalCase(FTempDir + '\mixed\Absent.txt'),
    'a component that cannot be resolved keeps the case it came in');
end;

procedure TBpPathUtilsTests.TestCanonicalCaseUpperCasesTheDriveLetter;
var
  lvLowered, lvResult: string;
begin
  FTempDir := BpMakeTempDir('BpPath');
  CreateDir(FTempDir + '\MiXeD');
  lvLowered := LowerCase(Copy(FTempDir, 1, 1)) + Copy(FTempDir, 2, MaxInt);

  lvResult := BpPathCanonicalCase(lvLowered + '\mixed');
  CheckEquals(BpPathCanonicalCase(FTempDir) + '\MiXeD', lvResult,
    'a lower-case drive letter must not leave the path uncanonical');
  CheckEquals(UpCase(FTempDir[1]), lvResult[1],
    'the volume designator is the one component FindFirstFile cannot echo back');
end;

procedure TBpPathUtilsTests.TestCanonicalCaseReturnsWhatItCannotAnchor;
begin
  CheckEquals('a\b', BpPathCanonicalCase('a\b'), 'a relative path');
  CheckEquals('\a\b', BpPathCanonicalCase('\a\b'), 'a path rooted on the current drive');
  CheckEquals('C:a', BpPathCanonicalCase('C:a'), 'a drive-relative path');
  CheckEquals('\\server\share\x', BpPathCanonicalCase('\\server\share\x'), 'a UNC path');
  CheckEquals('\\?\C:\x', BpPathCanonicalCase('\\?\C:\x'), 'a verbatim path');
  CheckEquals('', BpPathCanonicalCase(''), 'nothing at all');
end;

initialization
  RegisterTest(TBpPathUtilsTests.Suite);

end.
