unit BpCompat;

// Types the older compilers are missing. 18.5 is Delphi 2007; 18.0 is Delphi
// 2006, which has no TBytes either.

interface

type
{$IF CompilerVersion < 23.0}
  // no NativeUInt before D2007 and no 64-bit target before XE2, so Cardinal fits
  TbpUIntPtr = Cardinal;
{$ELSE}
  TbpUIntPtr = NativeUInt;
{$IFEND}

{$IF CompilerVersion < 18.5}
  TBytes = array of Byte;
{$IFEND}

implementation

end.
