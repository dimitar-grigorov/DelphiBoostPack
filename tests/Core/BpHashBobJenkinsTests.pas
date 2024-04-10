unit BpHashBobJenkinsTests;

interface

uses
  TestFramework, SysUtils, Classes, BpHashBobJenkinsUnit;

type
  TestTMyHashBobJenkins = class(TTestCase)
  private
    FHashBobJenkins: TbpHashBobJenkins;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestHashUniqueness;
    procedure TestHashConsistency;
    procedure StressTest;
  end;

implementation

{ TestTMyHashBobJenkins }

procedure TestTMyHashBobJenkins.SetUp;
begin
  FHashBobJenkins := TbpHashBobJenkins.Create;
end;

procedure TestTMyHashBobJenkins.TearDown;
begin
  FHashBobJenkins.Free;
end;

procedure TestTMyHashBobJenkins.TestHashUniqueness;
var
  i: Integer;
  hashValue: Integer;
  uniqueHashes: TStringList;
  index: Integer;
begin
  uniqueHashes := TStringList.Create;
  try
    uniqueHashes.Sorted := True;
    for i := 1 to 60000 do
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

procedure TestTMyHashBobJenkins.TestHashConsistency;
var
  hashValue1, hashValue2: Integer;
begin
  hashValue1 := FHashBobJenkins.GetHashValue('Consistency Test');
  hashValue2 := FHashBobJenkins.GetHashValue('Consistency Test');
  CheckEquals(hashValue1, hashValue2, 'Hash values for the same input should be consistent');
end;

procedure TestTMyHashBobJenkins.StressTest;
var
  i: Integer;
begin
  for i := 1 to 100000 do
    FHashBobJenkins.GetHashValue('Stress Test ' + IntToStr(i));
end;

initialization
  RegisterTest(TestTMyHashBobJenkins.Suite);

end.
