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
    procedure TestKnownAnswersWithInitialValue;
    procedure TestKnownAnswersUnaligned;
    procedure TestUpdateBytesWholeArray;
    procedure TestUpdateBytesExplicitZero;
    procedure TestUpdateBytesLengthPastEndRaises;
    procedure TestNegativeLengthHashesNothing;
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
const
  lcCount = 50000;
  // birthday bound: lcCount^2 / 2^33 is about 0.3 expected collisions for a
  // perfect 32-bit hash, so a budget, not zero
  lcMaxCollisions = 5;
var
  i, index, lvCollisions: Integer;
  hashValue: Integer;
  uniqueHashes: TStringList;
begin
  lvCollisions := 0;
  uniqueHashes := TStringList.Create;
  try
    uniqueHashes.Sorted := True;
    for i := 1 to lcCount do
    begin
      hashValue := FHashBobJenkins.GetHashValue('Sample Text ' + IntToStr(i));
      if uniqueHashes.Find(IntToStr(hashValue), index) then
        Inc(lvCollisions)
      else
        uniqueHashes.Add(IntToStr(hashValue));
    end;
  finally
    uniqueHashes.Free;
  end;
  Check(lvCollisions <= lcMaxCollisions,
    Format('%d collisions in %d hashes, budget is %d',
      [lvCollisions, lcCount, lcMaxCollisions]));
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

// Known-answer vectors, byte-oriented so they hold on every Delphi version
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
  // the published lookup3 self-test vector, the anchor that proves interop
  // rather than mere self consistency: hashlittle('Four score...', 30, 0)
  CheckHash(Integer($17770551), 'Four score and seven years ago');

  CheckHash(-559038737, '');              // len 0 - early exit, no Final ($DEADBEEF)
  CheckHash(1490454280, 'a');             // len 1
  CheckHash(238646833, 'abc');            // len 3
  CheckHash(-1242265444, 'abcd');         // len 4
  CheckHash(-1323641691, 'abcdefg');      // len 7 - OOB zone of the old implementation
  CheckHash(697680830, 'abcdefgh');       // len 8
  CheckHash(-1402637644, 'abcdefghi');    // len 9
  CheckHash(1074985083, 'abcdefghijkl');  // len 12 - last block must NOT be mixed in the loop
  CheckHash(-1837029127, 'abcdefghijklm');// len 13
  CheckHash(-1026949535, 'Hello, World!');
  CheckHash(1688390982, 'The quick brown fox jumps over the lazy dog');

  SetLength(lvAllBytes, 256);
  for i := 0 to 255 do
    lvAllBytes[i + 1] := AnsiChar(i);
  CheckHash(-502396877, lvAllBytes);      // all byte values, multi-block
end;

// the second published lookup3 vector: the same text with initval 1, which is
// the only test that pins the seeding of a non-zero initial value
procedure TBpHashBobJenkinsTests.TestKnownAnswersWithInitialValue;
const
  lcText: AnsiString = 'Four score and seven years ago';
begin
  CheckEquals(Integer($CD628161),
    TbpHashBobJenkins.GetHashValue(Pointer(lcText)^, Length(lcText), 1),
    'hashlittle(text, 30, 1) must be $CD628161');
  CheckEquals(Integer($27D04005),
    TbpHashBobJenkins.GetHashValue(Pointer(lcText)^, Length(lcText), 2),
    'hashlittle(text, 30, 2) must be $27D04005');
end;

procedure TBpHashBobJenkinsTests.TestUpdateBytesWholeArray;
var
  lvBytes: TBytes;
  i: Integer;
begin
  SetLength(lvBytes, 20);
  for i := 0 to High(lvBytes) do
    lvBytes[i] := i * 7;
  FHashBobJenkins.Reset;
  FHashBobJenkins.Update(lvBytes);
  CheckEquals(TbpHashBobJenkins.GetHashValue(lvBytes[0], Length(lvBytes)),
    FHashBobJenkins.HashAsInteger,
    'the default length must hash the whole array');
end;

// an explicit 0 means zero bytes, it is not a request for the whole array
procedure TBpHashBobJenkinsTests.TestUpdateBytesExplicitZero;
var
  lvBytes: TBytes;
begin
  SetLength(lvBytes, 8);
  FillChar(lvBytes[0], Length(lvBytes), $AB);
  FHashBobJenkins.Reset;
  FHashBobJenkins.Update(lvBytes, 0);
  CheckEquals(-559038737, FHashBobJenkins.HashAsInteger,
    'zero bytes must leave the $DEADBEEF seed, not hash the array');
end;

procedure TBpHashBobJenkinsTests.TestUpdateBytesLengthPastEndRaises;
var
  lvBytes: TBytes;
begin
  SetLength(lvBytes, 4);
  FHashBobJenkins.Reset;
  try
    FHashBobJenkins.Update(lvBytes, 5);
    Fail('Expected ERangeError when aLength runs past the array');
  except
    on E: ERangeError do
      ;
  end;
end;

procedure TBpHashBobJenkinsTests.TestKnownAnswersUnaligned;
const
  lcSample: AnsiString = 'abcdefg';
var
  lvBuffer: array[0..31] of Byte;
  lvStart: Cardinal;
begin
  // the same bytes at an odd address; both paths must hash identically
  FillChar(lvBuffer, SizeOf(lvBuffer), 0);
  lvStart := 1 + (4 - ((Cardinal(@lvBuffer[1])) and 3)) mod 4; // force misalignment
  if (Cardinal(@lvBuffer[lvStart]) and 3) = 0 then
    Inc(lvStart);
  Move(Pointer(lcSample)^, lvBuffer[lvStart], Length(lcSample));
  CheckEquals(-1323641691,
    TbpHashBobJenkins.GetHashValue(lvBuffer[lvStart], Length(lcSample)),
    'Unaligned hash must match the aligned reference value');
end;

// the aligned and unaligned branches used to disagree on a negative length,
// and the unaligned one read a byte it was never given
procedure TBpHashBobJenkinsTests.TestNegativeLengthHashesNothing;
var
  lvBuffer: array[0..31] of Byte;
  lvStart: Cardinal;
  lvEmpty: Integer;
begin
  FillChar(lvBuffer, SizeOf(lvBuffer), $AB);
  lvEmpty := TbpHashBobJenkins.GetHashValue(lvBuffer[0], 0);
  CheckEquals(lvEmpty, TbpHashBobJenkins.GetHashValue(lvBuffer[0], -1),
    'aligned, negative length');
  CheckEquals(lvEmpty, TbpHashBobJenkins.GetHashValue(lvBuffer[0], -1000),
    'aligned, far negative length');

  lvStart := 1;
  while (Cardinal(@lvBuffer[lvStart]) and 3) = 0 do
    Inc(lvStart);
  CheckEquals(lvEmpty, TbpHashBobJenkins.GetHashValue(lvBuffer[lvStart], -1),
    'unaligned, negative length');
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
  CheckEquals(568380734, FHashBobJenkins.HashAsInteger,
    'Chained Update must equal HashLittle(part2, HashLittle(part1, 0))');
end;

procedure TBpHashBobJenkinsTests.TestTailBytesAffectHash;
var
  lvKey1, lvKey2: AnsiString;
begin
  // regression: tail bytes 6..8 were once never read, so 19-byte keys collided
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
