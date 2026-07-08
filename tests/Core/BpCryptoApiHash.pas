unit BpCryptoApiHash;

// Thin Windows CryptoAPI wrapper (advapi32, PROV_RSA_AES provider) used by the
// hash tests and benchmarks as an independent reference implementation.
// Test-suite helper only; the library hashes themselves are pure Pascal.

interface

uses
  SysUtils;

const
  CALG_MD5 = $00008003;
  CALG_SHA_256 = $0000800C;

// hashes ASize bytes of AData with the given CryptoAPI algorithm id
function CryptoApiHash(AAlgId: Cardinal; const AData; ASize: Integer): TBytes;
function CryptoApiHashHex(AAlgId: Cardinal; const AData; ASize: Integer): string;

implementation

uses
  Windows;

const
  PROV_RSA_AES = 24;
  CRYPT_VERIFYCONTEXT = $F0000000;
  HP_HASHVAL = $0002;

// minimal declarations, D2007 ships no wincrypt import unit
function CryptAcquireContextA(phProv: PCardinal; pszContainer, pszProvider: PAnsiChar;
  dwProvType, dwFlags: Cardinal): BOOL; stdcall; external 'advapi32.dll';
function CryptReleaseContext(hProv: Cardinal; dwFlags: Cardinal): BOOL; stdcall;
  external 'advapi32.dll';
function CryptCreateHash(hProv, AAlgId, hKey, dwFlags: Cardinal;
  phHash: PCardinal): BOOL; stdcall; external 'advapi32.dll';
function CryptHashData(hHash: Cardinal; pbData: Pointer;
  dwDataLen, dwFlags: Cardinal): BOOL; stdcall; external 'advapi32.dll';
function CryptGetHashParam(hHash, dwParam: Cardinal; pbData: Pointer;
  var pdwDataLen: Cardinal; dwFlags: Cardinal): BOOL; stdcall; external 'advapi32.dll';
function CryptDestroyHash(hHash: Cardinal): BOOL; stdcall; external 'advapi32.dll';

function CryptoApiHash(AAlgId: Cardinal; const AData; ASize: Integer): TBytes;
var
  lvProv, lvHash, lvLen: Cardinal;
begin
  Result := nil;
  if not CryptAcquireContextA(@lvProv, nil, nil, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) then
    raise Exception.Create('CryptAcquireContext failed');
  try
    if not CryptCreateHash(lvProv, AAlgId, 0, 0, @lvHash) then
      raise Exception.Create('CryptCreateHash failed');
    try
      if (ASize > 0) and not CryptHashData(lvHash, @AData, ASize, 0) then
        raise Exception.Create('CryptHashData failed');
      lvLen := 0;
      if not CryptGetHashParam(lvHash, HP_HASHVAL, nil, lvLen, 0) then
        raise Exception.Create('CryptGetHashParam size query failed');
      SetLength(Result, lvLen);
      if not CryptGetHashParam(lvHash, HP_HASHVAL, @Result[0], lvLen, 0) then
        raise Exception.Create('CryptGetHashParam failed');
    finally
      CryptDestroyHash(lvHash);
    end;
  finally
    CryptReleaseContext(lvProv, 0);
  end;
end;

function CryptoApiHashHex(AAlgId: Cardinal; const AData; ASize: Integer): string;
var
  lvDigest: TBytes;
  i: Integer;
begin
  lvDigest := CryptoApiHash(AAlgId, AData, ASize);
  Result := '';
  for i := 0 to High(lvDigest) do
    Result := Result + LowerCase(IntToHex(lvDigest[i], 2));
end;

end.
