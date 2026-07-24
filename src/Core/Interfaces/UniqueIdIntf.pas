unit UniqueIdIntf;

// Implemented by collection items that can be matched across two collection
// snapshots by a stable id instead of by index; BpObjectComparer uses it.

interface

type
  IUniqueId = interface
    ['{3C43BE0B-C5A3-4C7E-949C-E15DF5E082A4}']
    function GetUniqueId: string;
  end;

implementation

end.
