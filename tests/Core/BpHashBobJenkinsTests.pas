unit BpHashBobJenkinsTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, BpHashBobJenkins;

type
  TBpHashBobJenkinsTests = class(TTestCase)
  private
    FHashBobJenkins: TbpHashBobJenkins;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHashUniqueness;
    procedure TestHashConsistency;
    procedure TestSmallChangesImpact;
    procedure TestKnownAnswers;
    procedure TestKnownAnswersUnaligned;
    procedure TestChainedUpdate;
    procedure TestTailBytesAffectHash;
  end;

implementation

{ TestTMyHashBobJenkins }

procedure TBpHashBobJenkinsTests.SetUp;
begin
  FHashBobJenkins := TbpHashBobJenkins.Create;
end;

procedure TBpHashBobJenkinsTests.TearDown;
begin
  FHashBobJenkins.Free;
end;

procedure TBpHashBobJenkinsTests.TestHashUniqueness;
var
  i: Integer;
  hashValue: Integer;
  uniqueHashes: TStringList;
  index: Integer;
begin
  uniqueHashes := TStringList.Create;
  try
    uniqueHashes.Sorted := True;
    for i := 1 to 50000 do
    begin
      hashValue := FHashBobJenkins.GetHashValue('Sample Text ' + IntToStr(i));
      if uniqueHashes.Find(IntToStr(hashValue), index) then  // Check if hashValue is already in the list
        Fail('Hash collision detected for value ' + IntToStr(i))
      else
        uniqueHashes.Add(IntToStr(hashValue));
    end;
  finally
    uniqueHashes.Free;
  end;
end;

procedure TBpHashBobJenkinsTests.TestHashConsistency;
var
  hashValue1, hashValue2: Integer;
begin
  hashValue1 := FHashBobJenkins.GetHashValue('Consistency Test');
  hashValue2 := FHashBobJenkins.GetHashValue('Consistency Test');
  CheckEquals(hashValue1, hashValue2, 'Hash values for the same input should be consistent');
end;

procedure TBpHashBobJenkinsTests.TestSmallChangesImpact;
var
  hashValue1, hashValue2: Integer;
begin
  hashValue1 := FHashBobJenkins.GetHashValue('Small Change 1');
  hashValue2 := FHashBobJenkins.GetHashValue('Small Change 2');
  Check(hashValue1 <> hashValue2, 'Small changes in input should produce different hashes');
end;

// Known-answer vectors generated from a reference implementation of
// Delphi XE6 System.Generics.Defaults.HashLittle (incl. the Len shl 2 quirk).
// Byte-oriented (AnsiString + untyped overload) so they hold on every
// Delphi version regardless of the size of Char.
procedure TBpHashBobJenkinsTests.TestKnownAnswers;

  procedure CheckHash(Expected: Integer; const Data: AnsiString);
  begin
    CheckEquals(Expected, TbpHashBobJenkins.GetHashValue(Pointer(Data)^, Length(Data)),
      'Hash mismatch for ' + IntToStr(Length(Data)) + '-byte input');
  end;

var
  lvAllBytes: AnsiString;
  i: Integer;
begin
  CheckHash(-559038737, '');              // len 0 - early exit, no Final ($DEADBEEF)
  CheckHash(549663901, 'a');              // len 1
  CheckHash(1080066015, 'abc');           // len 3
  CheckHash(-997923095, 'abcd');          // len 4
  CheckHash(1395184943, 'abcdefg');       // len 7 - OOB zone of the old implementation
  CheckHash(2101329462, 'abcdefgh');      // len 8
  CheckHash(618214406, 'abcdefghi');      // len 9
  CheckHash(-646327670, 'abcdefghijkl');  // len 12 - last block must NOT be mixed in the loop
  CheckHash(507390348, 'abcdefghijklm');  // len 13
  CheckHash(99275851, 'Hello, World!');
  CheckHash(-1051846834, 'The quick brown fox jumps over the lazy dog');

  SetLength(lvAllBytes, 256);
  for i := 0 to 255 do
    lvAllBytes[i + 1] := AnsiChar(i);
  CheckHash(221389405, lvAllBytes);       // all byte values, multi-block
end;

procedure TBpHashBobJenkinsTests.TestKnownAnswersUnaligned;
const
  lcSample: AnsiString = 'abcdefg';
var
  lvBuffer: array[0..31] of Byte;
  lvStart: Cardinal;
begin
  // place the same bytes at an odd address to exercise the unaligned path;
  // both paths must produce identical hashes
  FillChar(lvBuffer, SizeOf(lvBuffer), 0);
  lvStart := 1 + (4 - ((Cardinal(@lvBuffer[1])) and 3)) mod 4; // force misalignment
  if (Cardinal(@lvBuffer[lvStart]) and 3) = 0 then
    Inc(lvStart);
  Move(Pointer(lcSample)^, lvBuffer[lvStart], Length(lcSample));
  CheckEquals(1395184943,
    TbpHashBobJenkins.GetHashValue(lvBuffer[lvStart], Length(lcSample)),
    'Unaligned hash must match the aligned reference value');
end;

procedure TBpHashBobJenkinsTests.TestChainedUpdate;
const
  lcPart1: AnsiString = 'Hello, ';
  lcPart2: AnsiString = 'World!';
begin
  // Update chains by re-seeding with the previous hash (RTL semantics)
  FHashBobJenkins.Reset;
  FHashBobJenkins.Update(Pointer(lcPart1)^, Length(lcPart1));
  FHashBobJenkins.Update(Pointer(lcPart2)^, Length(lcPart2));
  CheckEquals(-1506960798, FHashBobJenkins.HashAsInteger,
    'Chained Update must equal HashLittle(part2, HashLittle(part1, 0))');
end;

procedure TBpHashBobJenkinsTests.TestTailBytesAffectHash;
var
  lvKey1, lvKey2: AnsiString;
begin
  // regression for the old bug where tail bytes 6..8 were never read:
  // 19-byte keys differing only at byte 19 (tail byte 7) hashed equal
  lvKey1 := 'PREFIX-12345-SUF-Ax';
  lvKey2 := 'PREFIX-12345-SUF-Bx';
  lvKey1[19] := 'A';
  lvKey2[19] := 'B';
  Check(TbpHashBobJenkins.GetHashValue(Pointer(lvKey1)^, Length(lvKey1)) <>
        TbpHashBobJenkins.GetHashValue(Pointer(lvKey2)^, Length(lvKey2)),
    'Keys differing only in tail bytes must hash differently');
end;

initialization
  RegisterTest(TBpHashBobJenkinsTests.Suite);

end.
