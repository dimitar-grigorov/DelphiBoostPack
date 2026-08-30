unit BpCredentials;

// Keyring-style secret store on the Windows Credential Manager.
//   TbpCredentials.SetPassword('MyApp', 'api', 'secret-token');
//   lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');
//   TbpCredentials.DeletePassword('MyApp', 'api');

interface

uses
  SysUtils;

type
  EbpCredentials = class(Exception);

  TbpWideStringArray = array of WideString;

  // CRED_TYPE_GENERIC under '<service>/<username>', local machine persist,
  // secret as UTF-16LE bytes. Vault is per-user: other users cannot read it,
  // but any process running as the same user can.
  TbpCredentials = class
  public
    class procedure SetPassword(const aService, aUserName, aSecret: WideString);
    // raises EbpCredentials when the entry does not exist
    class function GetPassword(const aService, aUserName: WideString): WideString;
    class function TryGetPassword(const aService, aUserName: WideString;
      out aSecret: WideString): Boolean;
    // True when the entry existed, False when it was not there
    class function DeletePassword(const aService, aUserName: WideString): Boolean;
    // usernames stored under aService, unsorted; empty array when none
    class function FindUserNames(const aService: WideString): TbpWideStringArray;
    // removes every entry under aService, returns how many
    class function DeleteAll(const aService: WideString): Integer;

    // extra CryptProtectData layer keyed by aEntropy.
    // Friction against same-user readers, not a hard boundary.
    class procedure SetPasswordProtected(const aService, aUserName, aSecret,
      aEntropy: WideString);
    // raises EbpCredentials when the entry is missing or will not unprotect
    class function GetPasswordProtected(const aService, aUserName,
      aEntropy: WideString): WideString;
    // False in both those cases, never raises on a wrong entropy
    class function TryGetPasswordProtected(const aService, aUserName,
      aEntropy: WideString; out aSecret: WideString): Boolean;
  end;

implementation

uses
  Windows;

const
  gcCredTypeGeneric = 1;
  gcCredPersistLocalMachine = 2;
  gcErrorNotFound = 1168;
  gcCryptProtectUiForbidden = 1;
  // wincred.h limits for generic credentials
  gcCredMaxBlobSize = 5 * 512;
  gcCredMaxTargetNameLen = 32767;
  gcComment = WideString('Stored by DelphiBoostPack');

type
  // wincred.h CREDENTIALW; 'Type' is a Pascal keyword, hence CredType
  PbpCredentialW = ^TbpCredentialW;
  TbpCredentialW = record
    Flags: DWORD;
    CredType: DWORD;
    TargetName: PWideChar;
    Comment: PWideChar;
    LastWritten: TFileTime;
    CredentialBlobSize: DWORD;
    CredentialBlob: PAnsiChar;
    Persist: DWORD;
    AttributeCount: DWORD;
    Attributes: Pointer;
    TargetAlias: PWideChar;
    UserName: PWideChar;
  end;

  PbpDataBlob = ^TbpDataBlob;
  TbpDataBlob = record
    cbData: DWORD;
    pbData: PAnsiChar;
  end;

  TbpCredentialWArray = array[0..High(Word)] of PbpCredentialW;
  PbpCredentialWArray = ^TbpCredentialWArray;

// not in Delphi 2007's import units
function CredWriteW(aCredential: PbpCredentialW; aFlags: DWORD): BOOL; stdcall;
  external 'advapi32.dll';
function CredReadW(aTargetName: PWideChar; aType, aFlags: DWORD;
  out aCredential: PbpCredentialW): BOOL; stdcall; external 'advapi32.dll';
function CredDeleteW(aTargetName: PWideChar; aType, aFlags: DWORD): BOOL; stdcall;
  external 'advapi32.dll';
procedure CredFree(aBuffer: Pointer); stdcall; external 'advapi32.dll';
function CredEnumerateW(aFilter: PWideChar; aFlags: DWORD; out aCount: DWORD;
  out aCredentials: PbpCredentialWArray): BOOL; stdcall; external 'advapi32.dll';
function CryptProtectData(aDataIn: PbpDataBlob; aDescr: PWideChar;
  aEntropy: PbpDataBlob; aReserved, aPrompt: Pointer; aFlags: DWORD;
  aDataOut: PbpDataBlob): BOOL; stdcall; external 'crypt32.dll';
function CryptUnprotectData(aDataIn: PbpDataBlob; aDescr: PPWideChar;
  aEntropy: PbpDataBlob; aReserved, aPrompt: Pointer; aFlags: DWORD;
  aDataOut: PbpDataBlob): BOOL; stdcall; external 'crypt32.dll';

function BuildTargetName(const aService, aUserName: WideString): WideString;
begin
  Result := aService + '/' + aUserName;
end;

procedure RaiseLastCredError(const aWhat: string);
var
  lvCode: DWORD;
begin
  lvCode := GetLastError;
  raise EbpCredentials.CreateFmt('%s failed: %s (error %d)',
    [aWhat, SysErrorMessage(lvCode), lvCode]);
end;

procedure RaiseNotFound(const aService, aUserName: WideString);
begin
  raise EbpCredentials.CreateFmt('No credential stored for service ''%s'', user ''%s''',
    [string(aService), string(aUserName)]);
end;

procedure WipeString(var aBytes: AnsiString);
begin
  if aBytes <> '' then
    FillChar(PAnsiChar(aBytes)^, Length(aBytes), 0);
  aBytes := '';
end;

procedure WriteBlob(const aService, aUserName: WideString; const aBlob: AnsiString);
var
  lvCred: TbpCredentialW;
  lvTarget: WideString;
begin
  if aService = '' then
    raise EbpCredentials.Create('Service name must not be empty');
  if Length(aBlob) > gcCredMaxBlobSize then
    raise EbpCredentials.CreateFmt('Secret is %d bytes; generic credentials hold at most %d',
      [Length(aBlob), gcCredMaxBlobSize]);
  lvTarget := BuildTargetName(aService, aUserName);
  if Length(lvTarget) > gcCredMaxTargetNameLen then
    raise EbpCredentials.Create('Service/username is too long for a target name');
  FillChar(lvCred, SizeOf(lvCred), 0);
  lvCred.CredType := gcCredTypeGeneric;
  lvCred.TargetName := PWideChar(lvTarget);
  lvCred.Comment := PWideChar(gcComment);
  lvCred.UserName := PWideChar(aUserName);
  lvCred.Persist := gcCredPersistLocalMachine;
  lvCred.CredentialBlobSize := Length(aBlob);
  if lvCred.CredentialBlobSize > 0 then
    lvCred.CredentialBlob := PAnsiChar(aBlob);
  if not CredWriteW(@lvCred, 0) then
    RaiseLastCredError('CredWriteW');
end;

function TryReadBlob(const aService, aUserName: WideString;
  out aBlob: AnsiString): Boolean;
var
  lvCred: PbpCredentialW;
  lvTarget: WideString;
begin
  aBlob := '';
  lvTarget := BuildTargetName(aService, aUserName);
  if not CredReadW(PWideChar(lvTarget), gcCredTypeGeneric, 0, lvCred) then
  begin
    if GetLastError = gcErrorNotFound then
    begin
      Result := False;
      Exit;
    end;
    RaiseLastCredError('CredReadW');
  end;
  try
    SetLength(aBlob, lvCred^.CredentialBlobSize);
    if aBlob <> '' then
      Move(lvCred^.CredentialBlob^, PAnsiChar(aBlob)^, Length(aBlob));
  finally
    // wipe the secret before the buffer goes back to the system heap
    if lvCred^.CredentialBlobSize > 0 then
      FillChar(lvCred^.CredentialBlob^, lvCred^.CredentialBlobSize, 0);
    CredFree(lvCred);
  end;
  Result := True;
end;

function SecretToBytes(const aSecret: WideString): AnsiString;
begin
  SetLength(Result, Length(aSecret) * SizeOf(WideChar));
  if Result <> '' then
    Move(PWideChar(aSecret)^, PAnsiChar(Result)^, Length(Result));
end;

function BytesToSecret(const aBytes: AnsiString): WideString;
begin
  SetLength(Result, Length(aBytes) div SizeOf(WideChar));
  if Result <> '' then
    Move(PAnsiChar(aBytes)^, PWideChar(Result)^, Length(Result) * SizeOf(WideChar));
end;

procedure InitEntropyBlob(const aEntropy: WideString; var aBlob: TbpDataBlob;
  out aUse: PbpDataBlob);
begin
  aBlob.cbData := Length(aEntropy) * SizeOf(WideChar);
  aBlob.pbData := PAnsiChar(PWideChar(aEntropy));
  if aBlob.cbData > 0 then
    aUse := @aBlob
  else
    aUse := nil;
end;

class procedure TbpCredentials.SetPassword(const aService, aUserName,
  aSecret: WideString);
var
  lvBlob: AnsiString;
begin
  lvBlob := SecretToBytes(aSecret);
  try
    WriteBlob(aService, aUserName, lvBlob);
  finally
    WipeString(lvBlob);
  end;
end;

class function TbpCredentials.TryGetPassword(const aService, aUserName: WideString;
  out aSecret: WideString): Boolean;
var
  lvBlob: AnsiString;
begin
  aSecret := '';
  Result := TryReadBlob(aService, aUserName, lvBlob);
  try
    if Result then
      aSecret := BytesToSecret(lvBlob);
  finally
    WipeString(lvBlob);
  end;
end;

class function TbpCredentials.GetPassword(const aService,
  aUserName: WideString): WideString;
begin
  if not TryGetPassword(aService, aUserName, Result) then
    RaiseNotFound(aService, aUserName);
end;

class function TbpCredentials.DeletePassword(const aService,
  aUserName: WideString): Boolean;
var
  lvTarget: WideString;
begin
  lvTarget := BuildTargetName(aService, aUserName);
  Result := CredDeleteW(PWideChar(lvTarget), gcCredTypeGeneric, 0);
  if (not Result) and (GetLastError <> gcErrorNotFound) then
    RaiseLastCredError('CredDeleteW');
end;

class function TbpCredentials.FindUserNames(const aService: WideString): TbpWideStringArray;
var
  lvCreds: PbpCredentialWArray;
  lvCount: DWORD;
  lvFilter: WideString;
  i, lvHits: Integer;
begin
  SetLength(Result, 0);
  lvFilter := aService + '/*';
  if not CredEnumerateW(PWideChar(lvFilter), 0, lvCount, lvCreds) then
  begin
    if GetLastError = gcErrorNotFound then
      Exit;
    RaiseLastCredError('CredEnumerateW');
  end;
  try
    SetLength(Result, lvCount);
    lvHits := 0;
    for i := 0 to Integer(lvCount) - 1 do
      if lvCreds^[i]^.CredType = gcCredTypeGeneric then
      begin
        // target is '<service>/<username>'; the username starts past the '/'
        Result[lvHits] := Copy(WideString(lvCreds^[i]^.TargetName),
          Length(aService) + 2, MaxInt);
        Inc(lvHits);
      end;
    SetLength(Result, lvHits);
  finally
    CredFree(lvCreds);
  end;
end;

class function TbpCredentials.DeleteAll(const aService: WideString): Integer;
var
  lvUsers: TbpWideStringArray;
  i: Integer;
begin
  Result := 0;
  lvUsers := FindUserNames(aService);
  for i := 0 to High(lvUsers) do
    if DeletePassword(aService, lvUsers[i]) then
      Inc(Result);
end;

class procedure TbpCredentials.SetPasswordProtected(const aService, aUserName,
  aSecret, aEntropy: WideString);
var
  lvIn, lvOut, lvEntropy: TbpDataBlob;
  lvEntropyPtr: PbpDataBlob;
  lvPlain, lvCipher: AnsiString;
begin
  lvPlain := SecretToBytes(aSecret);
  try
    lvIn.cbData := Length(lvPlain);
    lvIn.pbData := PAnsiChar(lvPlain);
    InitEntropyBlob(aEntropy, lvEntropy, lvEntropyPtr);
    if not CryptProtectData(@lvIn, nil, lvEntropyPtr, nil, nil,
      gcCryptProtectUiForbidden, @lvOut) then
      RaiseLastCredError('CryptProtectData');
    try
      SetLength(lvCipher, lvOut.cbData);
      if lvCipher <> '' then
        Move(lvOut.pbData^, PAnsiChar(lvCipher)^, lvOut.cbData);
    finally
      LocalFree(HLOCAL(lvOut.pbData));
    end;
    WriteBlob(aService, aUserName, lvCipher);
  finally
    WipeString(lvPlain);
  end;
end;

class function TbpCredentials.TryGetPasswordProtected(const aService, aUserName,
  aEntropy: WideString; out aSecret: WideString): Boolean;
var
  lvIn, lvOut, lvEntropy: TbpDataBlob;
  lvEntropyPtr: PbpDataBlob;
  lvCipher, lvPlain: AnsiString;
begin
  aSecret := '';
  Result := TryReadBlob(aService, aUserName, lvCipher);
  if not Result then
    Exit;
  try
    lvIn.cbData := Length(lvCipher);
    lvIn.pbData := PAnsiChar(lvCipher);
    InitEntropyBlob(aEntropy, lvEntropy, lvEntropyPtr);
    // wrong entropy, tampered blob or a plain entry: a Try* answers False
    if not CryptUnprotectData(@lvIn, nil, lvEntropyPtr, nil, nil,
      gcCryptProtectUiForbidden, @lvOut) then
    begin
      Result := False;
      Exit;
    end;
    try
      SetLength(lvPlain, lvOut.cbData);
      if lvPlain <> '' then
        Move(lvOut.pbData^, PAnsiChar(lvPlain)^, lvOut.cbData);
      aSecret := BytesToSecret(lvPlain);
    finally
      if lvOut.cbData > 0 then
        FillChar(lvOut.pbData^, lvOut.cbData, 0);
      LocalFree(HLOCAL(lvOut.pbData));
      WipeString(lvPlain);
    end;
  finally
    WipeString(lvCipher);
  end;
end;

class function TbpCredentials.GetPasswordProtected(const aService, aUserName,
  aEntropy: WideString): WideString;
var
  lvBlob: AnsiString;
begin
  if TryGetPasswordProtected(aService, aUserName, aEntropy, Result) then
    Exit;
  // will not unprotect is not the same as missing
  if TryReadBlob(aService, aUserName, lvBlob) then
  begin
    WipeString(lvBlob);
    raise EbpCredentials.CreateFmt('Credential for service ''%s'', user ''%s'' will not ' +
      'unprotect: wrong entropy, a tampered blob, or an unprotected entry',
      [string(aService), string(aUserName)]);
  end;
  RaiseNotFound(aService, aUserName);
end;

end.
