unit BpCompat;

// TBytes for compilers before Delphi 2007, whose SysUtils has no such type.

interface

{$IF CompilerVersion < 18.0}
type
  TBytes = array of Byte;
{$IFEND}

implementation

end.
