unit BpIntListMemoryTests;

interface

uses
  TestFramework, IBpIntListUnit, BpIntListUnit, SysUtils, Classes;

type
  TBpIntListMemoryTests = class(TTestCase)
  private
    procedure TestList(aList: IBpIntList);
  public
    procedure SetUp; override;
  published
    procedure TestMemoryLeak;
  end;

implementation

procedure TBpIntListMemoryTests.SetUp;
begin
  inherited;
  System.ReportMemoryLeaksOnShutdown := True;
end;

procedure TBpIntListMemoryTests.TestMemoryLeak;
var
  il: IBpIntList;
begin
  il := TBpIntList.Create;
  il.Add(1);
  il.Add(2);
  TestList(il);
end;

procedure TBpIntListMemoryTests.TestList(aList: IBpIntList);
begin
  Status(Format('IBpIntList.Count: %d', [aList.Count]));
end;

initialization
  RegisterTest(TBpIntListMemoryTests.Suite);

end.

