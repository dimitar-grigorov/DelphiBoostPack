unit BpLeakGate;

// Turns a leaked block into a red console run. Listed first in the project uses
// clause, so it initializes right after the RTL and finalizes after every other
// unit: the one moment when what is still allocated is exactly what leaked.
// The RTL's own report is a modal MessageBox, which on an unattended runner
// blocks until somebody clicks OK, so the project leaves it to the GUI runner.

interface

implementation

// no uses clause on purpose: a unit named here finalizes first and reads as a leak

var
  vBlocks: Integer;
  vBytes: Int64;

procedure Snapshot(out aBlocks: Integer; out aBytes: Int64);
var
  lvState: TMemoryManagerState;
  I: Integer;
begin
  GetMemoryManagerState(lvState);
  aBlocks := lvState.AllocatedMediumBlockCount + lvState.AllocatedLargeBlockCount;
  aBytes := Int64(lvState.TotalAllocatedMediumBlockSize) +
    Int64(lvState.TotalAllocatedLargeBlockSize);
  for I := 0 to High(lvState.SmallBlockTypeStates) do
    with lvState.SmallBlockTypeStates[I] do
    begin
      Inc(aBlocks, AllocatedBlockCount);
      Inc(aBytes, Int64(UseableBlockSize) * AllocatedBlockCount);
    end;
end;

procedure ReportLeaks;
var
  lvBlocks: Integer;
  lvBytes: Int64;
begin
  Snapshot(lvBlocks, lvBytes);
  Dec(lvBlocks, vBlocks);
  Dec(lvBytes, vBytes);
  if lvBlocks <= 0 then
    Exit;
  Writeln;
  Writeln('Memory leak: ', lvBytes, ' bytes in ', lvBlocks,
    ' block(s) still allocated at shutdown.');
  ExitCode := 1;
end;

initialization
  if IsConsole then
    Snapshot(vBlocks, vBytes);

finalization
  if IsConsole then
    ReportLeaks;

end.
