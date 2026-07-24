unit BpCancellationTokenTests;

{$TYPEINFO ON}

interface

uses
  TestFramework, SysUtils, Classes, Windows, BpCancellationToken;

type
  // all offline; the cross-thread test uses a private worker thread
  TBpCancellationTokenTests = class(TTestCase)
  private
    FToken: TbpCancellationToken;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInitialState;
    procedure TestCancelIsSticky;
    procedure TestCleanupRunsOnCancel;
    procedure TestUnregisterPreventsCleanup;
    procedure TestRegisterAfterCancelRefuses;
    procedure TestCleanupsRunInRegistrationOrder;
    procedure TestCancelFromAnotherThread;
  end;

implementation

const
  // typed constants so a real pointer is passed (PChar('A') on a
  // single-char literal would smuggle the ordinal in as the address)
  gcTagA: PChar = 'A';
  gcTag1: PChar = '1';
  gcTag2: PChar = '2';
  gcTag3: PChar = '3';

var
  // written by the plain-procedure cleanups, inspected by the tests
  gvCleanupLog: string;

procedure AppendCleanupLog(AData: Pointer);
begin
  gvCleanupLog := gvCleanupLog + string(PChar(AData));
end;

type
  TCancelAfterDelayThread = class(TThread)
  private
    FToken: TbpCancellationToken;
  protected
    procedure Execute; override;
  public
    constructor Create(AToken: TbpCancellationToken);
  end;

constructor TCancelAfterDelayThread.Create(AToken: TbpCancellationToken);
begin
  FToken := AToken;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TCancelAfterDelayThread.Execute;
begin
  Sleep(50);
  FToken.Cancel;
end;

{ TBpCancellationTokenTests }

procedure TBpCancellationTokenTests.SetUp;
begin
  inherited;
  FToken := TbpCancellationToken.Create;
  gvCleanupLog := '';
end;

procedure TBpCancellationTokenTests.TearDown;
begin
  FToken.Free;
  inherited;
end;

procedure TBpCancellationTokenTests.TestInitialState;
begin
  CheckFalse(FToken.IsCancellationRequested, 'fresh token must not be cancelled');
end;

procedure TBpCancellationTokenTests.TestCancelIsSticky;
begin
  FToken.Cancel;
  CheckTrue(FToken.IsCancellationRequested);
  // a second cancel is a no-op, not an error
  FToken.Cancel;
  CheckTrue(FToken.IsCancellationRequested);
end;

procedure TBpCancellationTokenTests.TestCleanupRunsOnCancel;
var
  lvId: Integer;
begin
  CheckTrue(FToken.RegisterCleanup(AppendCleanupLog, gcTagA, lvId),
    'registration on a live token must succeed');
  CheckTrue(lvId > 0, 'registration id must be positive');
  CheckEquals('', gvCleanupLog, 'cleanup must not run before Cancel');

  FToken.Cancel;
  CheckEquals('A', gvCleanupLog, 'cleanup must run inside Cancel');
  CheckFalse(FToken.UnregisterCleanup(lvId),
    'after Cancel the registration is gone (already executed)');

  // cancelling again must not run the cleanup a second time
  FToken.Cancel;
  CheckEquals('A', gvCleanupLog);
end;

procedure TBpCancellationTokenTests.TestUnregisterPreventsCleanup;
var
  lvId: Integer;
begin
  CheckTrue(FToken.RegisterCleanup(AppendCleanupLog, gcTagA, lvId));
  CheckTrue(FToken.UnregisterCleanup(lvId), 'pending registration reports True');
  CheckFalse(FToken.UnregisterCleanup(lvId), 'second unregister reports False');

  FToken.Cancel;
  CheckEquals('', gvCleanupLog, 'unregistered cleanup must not run');
end;

procedure TBpCancellationTokenTests.TestRegisterAfterCancelRefuses;
var
  lvId: Integer;
begin
  FToken.Cancel;
  CheckFalse(FToken.RegisterCleanup(AppendCleanupLog, gcTagA, lvId),
    'registration on a cancelled token must refuse');
  CheckEquals(0, lvId);
  CheckEquals('', gvCleanupLog, 'refused cleanup must not run');
end;

procedure TBpCancellationTokenTests.TestCleanupsRunInRegistrationOrder;
var
  lvId1, lvId2, lvId3: Integer;
begin
  CheckTrue(FToken.RegisterCleanup(AppendCleanupLog, gcTag1, lvId1));
  CheckTrue(FToken.RegisterCleanup(AppendCleanupLog, gcTag2, lvId2));
  CheckTrue(FToken.RegisterCleanup(AppendCleanupLog, gcTag3, lvId3));
  CheckTrue(FToken.UnregisterCleanup(lvId2), 'middle one removed');

  FToken.Cancel;
  CheckEquals('13', gvCleanupLog, 'remaining cleanups run in order');
end;

procedure TBpCancellationTokenTests.TestCancelFromAnotherThread;
var
  lvThread: TCancelAfterDelayThread;
  lvDeadline: Cardinal;
begin
  lvThread := TCancelAfterDelayThread.Create(FToken);
  try
    lvDeadline := GetTickCount + 5000;
    while not FToken.IsCancellationRequested and (GetTickCount < lvDeadline) do
      Sleep(10);
    CheckTrue(FToken.IsCancellationRequested,
      'cancel from a worker thread must become visible here');
  finally
    lvThread.WaitFor;
    lvThread.Free;
  end;
end;

initialization
  RegisterTest(TBpCancellationTokenTests.Suite);

end.
