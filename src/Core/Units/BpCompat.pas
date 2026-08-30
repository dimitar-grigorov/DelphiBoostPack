unit BpCompat;

// TBytes for compilers before Delphi 2007, whose SysUtils has no such type.
// 18.5 is Delphi 2007; 18.0 is Delphi 2006, which does not have it either.

interface

{$IF CompilerVersion < 18.5}
type
  TBytes = array of Byte;
{$IFEND}

implementation

end.
