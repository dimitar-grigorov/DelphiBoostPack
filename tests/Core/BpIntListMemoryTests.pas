unit BpIntListMemoryTests;

interface

uses
  TestFramework, BpIntListInterface, BpIntList, SysUtils, Classes;

type
  TestTBpIntListMemoryTests = class(TTestCase)
  private
    procedure TestList(aList: IBpIntList);
  public
    procedure SetUp; override;
  published
    procedure TestMemoryLeak;
  end;

implementation

procedure TestTBpIntListMemoryTests.SetUp;
begin
  inherited;
  System.ReportMemoryLeaksOnShutdown := True;
end;

procedure TestTBpIntListMemoryTests.TestMemoryLeak;
var
  il: IBpIntList;
begin
  il := TBpIntList.Create;
  il.Add(1);
  il.Add(2);
  TestList(il);
end;

procedure TestTBpIntListMemoryTests.TestList(aList: IBpIntList);
begin
  Status(Format('IBpIntList.Count: %d', [aList.Count]));
end;

initialization
  RegisterTest(TestTBpIntListMemoryTests.Suite);

end.

