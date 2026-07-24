unit BpCancellationToken;

// Cooperative cancellation for Delphi 7/2007 and later, modeled on the
// C# CancellationToken / JS AbortController pair.
//
// One party holds the token and calls Cancel; the working party polls
// IsCancellationRequested at convenient points and unwinds when it turns
// True. Both sides may live on different threads: Cancel and the query are
// thread-safe, and a token is one-shot by design (no Reset), so a stale
// True can never flip back to False under the worker's feet.
//
// RegisterCleanup is the analogue of C#'s CancellationToken.Register: it
// arranges a callback to run inside Cancel, which is how a blocking
// operation gets aborted promptly instead of at the next poll. The HTTP
// client registers a callback that closes its WinInet request handle, so a
// thread stuck in HttpSendRequest or InternetReadFile fails over
// immediately with ERROR_INTERNET_OPERATION_CANCELLED. Cleanups fire
// inside the canceller's thread while the token lock is held; keep them
// short and never call back into the token from one.
//
// The token must outlive every operation it was handed to; the usual
// owner is whoever calls Cancel (a UI form, a download task).

interface

uses
  Windows;

type
  // plain procedure on purpose: usable from any code without an object
  TbpCancelCleanupProc = procedure(AData: Pointer);

  TbpCancellationToken = class
  private
    FLock: TRTLCriticalSection;
    FCancelled: Integer;          // 0/1, written under the lock
    FCleanupProcs: array of TbpCancelCleanupProc;
    FCleanupData: array of Pointer;
    FCleanupIds: array of Integer;
    FNextId: Integer;
    function IndexOfId(AId: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;

    // one-shot; safe to call repeatedly and from any thread
    procedure Cancel;
    function IsCancellationRequested: Boolean;

    // registers a cleanup that Cancel will invoke; returns False without
    // registering when the token is already cancelled (mirrors C#, where a
    // late Register runs the callback immediately - the caller reacts by
    // aborting instead)
    function RegisterCleanup(AProc: TbpCancelCleanupProc; AData: Pointer;
      out AId: Integer): Boolean;
    // removes a registration; True when it was still pending, False when
    // Cancel already ran it (the resource is gone, do not touch it again)
    function UnregisterCleanup(AId: Integer): Boolean;
  end;

implementation

constructor TbpCancellationToken.Create;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FNextId := 1;
end;

destructor TbpCancellationToken.Destroy;
begin
  DeleteCriticalSection(FLock);
  inherited;
end;

function TbpCancellationToken.IsCancellationRequested: Boolean;
begin
  // aligned 32-bit read is atomic; the lock is only needed on the write
  // side to order the flag against the cleanup list
  Result := FCancelled <> 0;
end;

function TbpCancellationToken.IndexOfId(AId: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FCleanupIds) do
    if FCleanupIds[i] = AId then
    begin
      Result := i;
      Exit;
    end;
end;

procedure TbpCancellationToken.Cancel;
var
  i: Integer;
begin
  EnterCriticalSection(FLock);
  try
    if FCancelled <> 0 then
      Exit;
    FCancelled := 1;
    // run in registration order, then drop everything so a later
    // UnregisterCleanup reports the cleanup as already executed
    for i := 0 to High(FCleanupProcs) do
      FCleanupProcs[i](FCleanupData[i]);
    SetLength(FCleanupProcs, 0);
    SetLength(FCleanupData, 0);
    SetLength(FCleanupIds, 0);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TbpCancellationToken.RegisterCleanup(AProc: TbpCancelCleanupProc;
  AData: Pointer; out AId: Integer): Boolean;
var
  lvCount: Integer;
begin
  AId := 0;
  Result := False;
  EnterCriticalSection(FLock);
  try
    if FCancelled <> 0 then
      Exit;
    lvCount := Length(FCleanupProcs);
    SetLength(FCleanupProcs, lvCount + 1);
    SetLength(FCleanupData, lvCount + 1);
    SetLength(FCleanupIds, lvCount + 1);
    FCleanupProcs[lvCount] := AProc;
    FCleanupData[lvCount] := AData;
    FCleanupIds[lvCount] := FNextId;
    AId := FNextId;
    Inc(FNextId);
    Result := True;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TbpCancellationToken.UnregisterCleanup(AId: Integer): Boolean;
var
  lvIndex, i: Integer;
begin
  EnterCriticalSection(FLock);
  try
    lvIndex := IndexOfId(AId);
    Result := lvIndex >= 0;
    if not Result then
      Exit;
    for i := lvIndex to High(FCleanupProcs) - 1 do
    begin
      FCleanupProcs[i] := FCleanupProcs[i + 1];
      FCleanupData[i] := FCleanupData[i + 1];
      FCleanupIds[i] := FCleanupIds[i + 1];
    end;
    SetLength(FCleanupProcs, Length(FCleanupProcs) - 1);
    SetLength(FCleanupData, Length(FCleanupData) - 1);
    SetLength(FCleanupIds, Length(FCleanupIds) - 1);
  finally
    LeaveCriticalSection(FLock);
  end;
end;

end.
