unit BpHashBobJenkinsTests;

interface

uses
  TestFramework, SysUtils, Classes, BpHashBobJenkinsUnit;

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

initialization
  RegisterTest(TBpHashBobJenkinsTests.Suite);

end.
