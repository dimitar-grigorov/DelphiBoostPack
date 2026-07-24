unit BpCredentialsTests;

{$TYPEINFO ON}

// Integration tests: they write to the real Windows Credential Manager under
// a unique per-test service name and delete everything they created in TearDown.

interface

uses
  TestFramework, SysUtils, Windows, BpCredentials;

type
  TbpCredentialPair = record
    Service: WideString;
    User: WideString;
  end;

  TBpCredentialsTests = class(TTestCase)
  private
    FService: WideString;
    FCreated: array of TbpCredentialPair;
    procedure Track(const aUser: WideString);
    procedure SetTracked(const aUser, aSecret: WideString);
    procedure CheckWideEquals(const aExpected, aActual: WideString; const aCase: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRoundTrip;
    procedure TestOverwriteReplaces;
    procedure TestDeleteTrueThenFalse;
    procedure TestMissingEntry;
    procedure TestUnicodeSecretAndUserName;
    procedure TestEmptySecret;
    procedure TestFindUserNames;
    procedure TestDeleteAll;
    procedure TestRejectsBadInput;
    procedure TestProtectedRoundTrip;
    procedure TestProtectedWrongEntropy;
    procedure TestProtectedMissingEntry;
    procedure TestProtectedBlobIsNotPlaintext;
  end;

implementation

procedure TBpCredentialsTests.SetUp;
begin
  inherited;
  FService := WideString(Format('DelphiBoostPack.Test.%d.%d',
    [GetCurrentProcessId, GetTickCount]));
  SetLength(FCreated, 0);
end;

procedure TBpCredentialsTests.TearDown;
var
  i: Integer;
begin
  for i := 0 to High(FCreated) do
    TbpCredentials.DeletePassword(FCreated[i].Service, FCreated[i].User);
  SetLength(FCreated, 0);
  inherited;
end;

// remember the pair so TearDown cleans up even when a check fails
procedure TBpCredentialsTests.Track(const aUser: WideString);
var
  lvIdx: Integer;
begin
  lvIdx := Length(FCreated);
  SetLength(FCreated, lvIdx + 1);
  FCreated[lvIdx].Service := FService;
  FCreated[lvIdx].User := aUser;
end;

procedure TBpCredentialsTests.SetTracked(const aUser, aSecret: WideString);
begin
  Track(aUser);
  TbpCredentials.SetPassword(FService, aUser, aSecret);
end;

procedure TBpCredentialsTests.CheckWideEquals(const aExpected, aActual: WideString;
  const aCase: string);
begin
  Check(aExpected = aActual, Format('%s: secrets differ (%d vs %d chars)',
    [aCase, Length(aExpected), Length(aActual)]));
end;

procedure TBpCredentialsTests.TestRoundTrip;
var
  lvSecret: WideString;
begin
  SetTracked('alice', 'hunter2');
  CheckWideEquals('hunter2', TbpCredentials.GetPassword(FService, 'alice'), 'get');
  CheckTrue(TbpCredentials.TryGetPassword(FService, 'alice', lvSecret), 'try get');
  CheckWideEquals('hunter2', lvSecret, 'try get value');
end;

procedure TBpCredentialsTests.TestOverwriteReplaces;
begin
  SetTracked('alice', 'first');
  SetTracked('alice', 'second');
  CheckWideEquals('second', TbpCredentials.GetPassword(FService, 'alice'), 'overwrite');
end;

procedure TBpCredentialsTests.TestDeleteTrueThenFalse;
begin
  SetTracked('gone', 'x');
  CheckTrue(TbpCredentials.DeletePassword(FService, 'gone'), 'first delete removes');
  CheckFalse(TbpCredentials.DeletePassword(FService, 'gone'), 'second delete finds nothing');
end;

procedure TBpCredentialsTests.TestMissingEntry;
var
  lvSecret: WideString;
begin
  CheckFalse(TbpCredentials.TryGetPassword(FService, 'nobody', lvSecret), 'try get misses');
  CheckWideEquals('', lvSecret, 'missing leaves secret empty');
  try
    TbpCredentials.GetPassword(FService, 'nobody');
    Fail('missing entry must raise');
  except
    on E: EbpCredentials do
      Check(True);
  end;
end;

procedure TBpCredentialsTests.TestUnicodeSecretAndUserName;
var
  lvUser, lvSecret: WideString;
begin
  // Cyrillic from code points so the source file stays plain ASCII
  lvUser := WideChar($041F) + WideChar($0435) + WideChar($0442) +
    WideChar($044A) + WideChar($0440);
  lvSecret := WideChar($0442) + WideChar($0430) + WideChar($0439) +
    WideChar($043D) + WideChar($0430) + WideChar($0021);
  SetTracked(lvUser, lvSecret);
  CheckWideEquals(lvSecret, TbpCredentials.GetPassword(FService, lvUser),
    'cyrillic round-trip');
end;

procedure TBpCredentialsTests.TestEmptySecret;
var
  lvSecret: WideString;
begin
  SetTracked('empty', '');
  CheckTrue(TbpCredentials.TryGetPassword(FService, 'empty', lvSecret), 'entry exists');
  CheckWideEquals('', lvSecret, 'empty secret round-trips');
end;

procedure TBpCredentialsTests.TestFindUserNames;
var
  lvUsers: TbpWideStringArray;
  i: Integer;
  lvFound: Boolean;
begin
  CheckEquals(0, Length(TbpCredentials.FindUserNames(FService)), 'empty service');
  SetTracked('alice', 'a');
  SetTracked('bob', 'b');
  SetTracked('carol', 'c');
  lvUsers := TbpCredentials.FindUserNames(FService);
  CheckEquals(3, Length(lvUsers), 'three entries');
  lvFound := False;
  for i := 0 to High(lvUsers) do
    if lvUsers[i] = WideString('bob') then
      lvFound := True;
  CheckTrue(lvFound, 'bob is listed');
end;

procedure TBpCredentialsTests.TestDeleteAll;
begin
  SetTracked('alice', 'a');
  SetTracked('bob', 'b');
  CheckEquals(2, TbpCredentials.DeleteAll(FService), 'deletes both');
  CheckEquals(0, TbpCredentials.DeleteAll(FService), 'nothing left');
  CheckEquals(0, Length(TbpCredentials.FindUserNames(FService)), 'store is empty');
end;

procedure TBpCredentialsTests.TestRejectsBadInput;
var
  lvBig: WideString;
begin
  try
    TbpCredentials.SetPassword('', 'user', 'x');
    Fail('empty service must raise');
  except
    on E: EbpCredentials do
      Check(True);
  end;
  // 2560 byte blob limit for generic credentials; 1281 chars is one over
  SetLength(lvBig, 1281);
  FillChar(PWideChar(lvBig)^, Length(lvBig) * SizeOf(WideChar), Ord('x'));
  try
    TbpCredentials.SetPassword(FService, 'user', lvBig);
    Fail('oversized secret must raise');
  except
    on E: EbpCredentials do
      Check(True);
  end;
end;

procedure TBpCredentialsTests.TestProtectedRoundTrip;
var
  lvSecret: WideString;
begin
  Track('vip');
  TbpCredentials.SetPasswordProtected(FService, 'vip', 'top-secret', 'pepper');
  CheckWideEquals('top-secret',
    TbpCredentials.GetPasswordProtected(FService, 'vip', 'pepper'), 'get');
  CheckTrue(TbpCredentials.TryGetPasswordProtected(FService, 'vip', 'pepper', lvSecret),
    'try get');
  CheckWideEquals('top-secret', lvSecret, 'try get value');
  // empty entropy is plain user-scope DPAPI
  Track('vip2');
  TbpCredentials.SetPasswordProtected(FService, 'vip2', 's', '');
  CheckWideEquals('s', TbpCredentials.GetPasswordProtected(FService, 'vip2', ''),
    'no entropy');
end;

procedure TBpCredentialsTests.TestProtectedWrongEntropy;
begin
  Track('vip');
  TbpCredentials.SetPasswordProtected(FService, 'vip', 'top-secret', 'pepper');
  try
    TbpCredentials.GetPasswordProtected(FService, 'vip', 'salt');
    Fail('wrong entropy must raise');
  except
    on E: EbpCredentials do
      Check(True);
  end;
end;

procedure TBpCredentialsTests.TestProtectedMissingEntry;
var
  lvSecret: WideString;
begin
  CheckFalse(TbpCredentials.TryGetPasswordProtected(FService, 'nobody', 'pepper', lvSecret),
    'try get misses');
  try
    TbpCredentials.GetPasswordProtected(FService, 'nobody', 'pepper');
    Fail('missing entry must raise');
  except
    on E: EbpCredentials do
      Check(True);
  end;
end;

procedure TBpCredentialsTests.TestProtectedBlobIsNotPlaintext;
begin
  Track('vip');
  TbpCredentials.SetPasswordProtected(FService, 'vip', 'top-secret', 'pepper');
  // the stored blob is DPAPI ciphertext, not the secret itself
  CheckFalse(TbpCredentials.GetPassword(FService, 'vip') = WideString('top-secret'),
    'plain read must not see the plaintext');
end;

initialization
{$IFNDEF NO_INTEGRATION}
  RegisterTest(TBpCredentialsTests.Suite);
{$ENDIF}

end.
