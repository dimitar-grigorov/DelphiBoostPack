# Feature guide

Every unit in DelphiBoostPack: what it does, how to call it, where the sharp edges are. The [README](../README.md) is the tour; this is the manual. Add a unit to `uses` and go - no packages, no DLLs, no base class. Prefer a single file? See [single-file bundles](#single-file-bundles).

## Contents

**Network and async**
[TbpHttpClient](#tbphttpclient) · [TbpHttpDownloadTask](#tbphttpdownloadtask) · [TbpCancellationToken](#tbpcancellationtoken) · [TbpTask](#tbptask)

**Data**
[TbpJsonValue](#tbpjsonvalue) · [BpDateUtils](#bpdateutils) · [TbpStringList](#tbpstringlist) · [TbpStrDictionary](#tbpstrdictionary) · [TbpIntDictionary](#tbpintdictionary) · [TbpIntList](#tbpintlist) · [TbpInt64List](#tbpint64list)

**Strings**
[TbpStringBuilder](#tbpstringbuilder) · [BpStrUtils](#bpstrutils)

**Hashing and encoding**
[BpSHA256](#bpsha256) · [BpMD5](#bpmd5) · [BpHMACSHA256](#bphmacsha256) · [BpPasswordHash](#bppasswordhash) · [BpBase64](#bpbase64) · [BpHashBobJenkins](#bphashbobjenkins)

**Windows and odds and ends**
[TbpCredentials](#tbpcredentials) · [TbpObjectComparer](#tbpobjectcomparer) · [BpKeyFold](#bpkeyfold) · [BpVariantUtils](#bpvariantutils) · [BpSysUtils](#bpsysutils) · [StopWatch](#stopwatch)

**Packaging**
[Single-file bundles](#single-file-bundles)

---

## Network and async

### [TbpHttpClient](../src/Core/Classes/BpHttpClient.pas)

HTTP and HTTPS over WinInet, so TLS comes from Schannel: no OpenSSL DLLs, no certificate bundle to go stale.

```pascal
uses BpHttpClient;

lvBody := TbpHttpClient.FetchUrl('https://api.example.com/v1/status');

lvResp := lvClient.Get('https://api.example.com/v1/items');
if BpHttpResponseIsSuccess(lvResp) then
  lvText := BpHttpResponseBodyAsUtf8(lvResp);
```

| Call | Notes |
|------|-------|
| `Get(aUrl, aHeaders, aToken)` | everything after the URL is optional |
| `Post(aUrl, aBody, aHeaders, aToken)` | raw body, you set the content type |
| `PostJson(aUrl, aJson, aToken)` | sets `Content-Type: application/json` |
| `Put` / `Delete` | same shape |
| `Execute(aUrl, aMethod, aHeaders, aBody, aToken)` | the one they all call |
| `FetchUrl(aUrl, aHeaders)` | class function, body only |

```pascal
TbpHttpResponse = record
  StatusCode: Integer;
  StatusText: string;
  Headers: string;         // raw, CRLF separated
  Body: AnsiString;        // raw bytes as received
  ContentLength: Int64;    // -1 when the header was absent
end;
```

A 404 is a response, not an exception. Only transport failures raise `EbpHttpClient`, which carries `StatusCode` and `WinInetError`.

#### Auth and headers

```pascal
lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');
lvClient.SetBasicAuth('user', 'pass');    // WideString, UTF-8 per RFC 7617
lvClient.AddHeader('X-Api-Version', '2'); // persistent, sent every request
```

`AddHeader` replaces a name already set, and rejects CR, LF or a colon in the name, so a value from a config file cannot append headers of its own; `BearerToken` is checked the same way. Per-request headers merge on top, a name in both sent once with the per-request value.

| Property | Default |
|----------|---------|
| `UserAgent` | `DelphiBoostPack/1.0` |
| `ConnectTimeout` / `SendTimeout` / `ReceiveTimeout` | 8000 ms each |
| `FollowRedirects` | `True` |
| `Username` / `Password` | empty (WinInet challenge-response auth) |

Proxy settings come from WinInet, so Internet Options and WPAD are honoured with no code.

#### Connection reuse

One client owns one WinInet session, so every request after the first to the same host skips the TCP and TLS handshake: hold the instance for the life of the form or service. Setting `UserAgent` drops the session.

#### Errors

```pascal
try
  lvResp := lvClient.Get(lvUrl);
  if not BpHttpResponseIsSuccess(lvResp) then
    ShowMessage(BpClassifyHttpError(0, lvResp.StatusCode));
except
  on E: EbpHttpClient do
    ShowMessage(BpClassifyHttpError(E.WinInetError, E.StatusCode));
end;
```

`BpClassifyHttpError` turns a WinInet code or an HTTP status into a sentence for a user; pass 0 for the dimension that does not apply.

#### Cancelling

Every verb takes a [TbpCancellationToken](#tbpcancellationtoken) last. `Cancel` closes the WinInet handle from the other thread, so a request blocked in connect, send or receive aborts at once with `EbpHttpClientCancelled` instead of waiting out the timeout - which is what makes a worker joinable at shutdown.

#### Wire trace

An in-process `ssh -v` in an optional companion unit, [BpHttpTrace.pas](../src/Core/Classes/BpHttpTrace.pas), that nothing else references.

```pascal
uses BpHttpTrace;

procedure MyTrace(aHandle: Pointer; const aLine: string);   // bare procedure
begin
  Log(Format('[http %p] %s', [aHandle, aLine]));            // "connected to ..."
end;

TbpHttpTrace.Attach(FClient, MyTrace);   // any thread; Detach when done
```

It installs a WinInet status callback, so an untraced build pays nothing, and the sink runs on the I/O thread: keep it quick and thread-safe. Headers never pass through it, so no `Authorization` value reaches a log.

#### Streaming downloads

`Download` streams to any `TStream`, `DownloadToFile` to a file, both in constant memory with `Int64` progress and a token. They block - use a worker thread, or [TbpHttpDownloadTask](#tbphttpdownloadtask).

```pascal
procedure TMainForm.HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
  var aCancel: Boolean);
begin
  ProgressBar1.Position := BpHttpProgressPercent(aReceived, aTotal);  // -1 = unknown
  aCancel := FStopRequested;
end;

lvClient.DownloadToFile(lvUrl, 'C:\temp\big.zip', HandleProgress, FToken);
```

The file is kept only on a 2xx, so an error page cannot masquerade as the payload, and a body short of the advertised `Content-Length` counts as an error. Resume is one header away: send `Range: bytes=<n>-` and append on a 206.

#### Helpers

| Function | Returns |
|----------|---------|
| `BpHttpResponseIsSuccess(aResponse)` | 2xx |
| `BpHttpResponseBodyAsUtf8(aResponse)` | body decoded as UTF-8 (`WideString`) |
| `BpHttpHeaderValue(aHeaders, aName)` | one header from a raw block, `''` when absent |
| `BpHttpContentLength(aHeaders)` | `Int64`, `-1` when absent or invalid |
| `BpHttpProgressPercent(aReceived, aTotal)` | 0..100, `-1` when the total is unknown |
| `BpClassifyHttpError(aWinInetError, aHttpStatus)` | a user-facing sentence |

`ParseUrl` and `BuildHeaders` are public too, and unit-tested.

### [TbpHttpDownloadTask](../src/Core/Classes/BpHttpClient.pas)

The non-blocking download, shaped like a C# `Task`. `Start` returns immediately and the events arrive on the thread that created the task, marshalled through a hidden window - no `ProcessMessages` anywhere.

```pascal
FTask := BpDownloadAsync(lvUrl, 'C:\temp\big.zip', HandleProgress, HandleComplete);

procedure TMainForm.HandleComplete(aSender: TObject);
begin
  case FTask.State of
    dtsSucceeded: ShowMessage('Done');
    dtsCancelled: ShowMessage('Cancelled');
    dtsFailed:    ShowMessage(FTask.ErrorMessage);
  end;
end;
```

`Cancel` aborts even in a blocked read; `Free` cancels, joins and releases in any state, so closing a form mid-download is safe. For auth or a stream destination build it yourself: `Create`, then `Client` (the full client surface), `Url`, `DestFileName` or `DestStream`, the events, `Start`.

| Member | Notes |
|--------|-------|
| `State` | `dtsPending` / `dtsRunning` / `dtsSucceeded` / `dtsFailed` / `dtsCancelled` |
| `Received` / `Total` | live counters, `Total` is `-1` while unknown |
| `Response` / `HttpStatus` / `ErrorMessage` / `ErrorCode` | authoritative once `IsFinished` |
| `WaitFor(aTimeoutMs)` | blocks; for console apps and tests |
| `OnError` | fires before `OnComplete` on `dtsFailed` |

Result properties are lock-guarded, so any thread may read them. `Create(False)` puts the events on the worker thread, for console apps with no message loop. A task is one-shot.

### [TbpCancellationToken](../src/Core/Classes/BpHttpClient.pas)

The C# `CancellationToken` idea for Delphi 7: one side calls `Cancel`, the working side polls `IsCancellationRequested` - and a registered cleanup runs inside `Cancel` itself, which is how a blocked read aborts instead of timing out. Thread-safe, one-shot, and nothing in it is HTTP.

### [TbpTask](../src/Core/Classes/BpTasks.pas)

Run any method on a worker thread and get the result back on the thread that started it. Self-contained (`Classes, SysUtils, Windows, Messages`), one thread per task, no pool.

```pascal
uses BpTasks;

procedure TMainForm.DoCrunch(aSender: TObject; aToken: TbpTaskToken);
begin
  while HasWorkLeft and not aToken.IsCancellationRequested do
    CrunchNextChunk;   // worker thread, no UI calls in here
end;

FTask := BpRunAsync(DoCrunch, HandleDone);   // HandleDone runs on this thread
```

Cancellation is cooperative, so no thread is killed: `Free` cancels, joins and cleans up in any state. An exception in the work body is recorded in `ErrorClass` and `ErrorMessage` rather than crossing the thread boundary; `OnError` fires first, then `OnComplete` on every terminal state.

| Member | Notes |
|--------|-------|
| `Work` | `procedure(aSender: TObject; aToken: TbpTaskToken) of object` |
| `Token` | owned; the same instance the work receives |
| `State` | `tskPending` / `tskRunning` / `tskSucceeded` / `tskFailed` / `tskCancelled` |
| `IsFinished` / `WaitFor(aTimeoutMs)` | terminal state reached; blocking wait |
| `Create(False)` | no marshalling - events fire on the worker thread |

**Two tokens, on purpose.** `TbpTaskToken` is a bare interlocked flag with no dependencies; [TbpCancellationToken](#tbpcancellationtoken) adds cleanups that run inside `Cancel`. Use the light one for polling work, the HTTP one when something must be torn down for the cancel to be prompt.

---

## Data

### [TbpJsonValue](../src/Core/Classes/BpJson.pas)

A JSON reader and writer (RFC 8259) in one class. No RTTI, no data binding: the tree is the API, tagged by `Kind`.

```pascal
uses BpJson;

lvJson := TbpJsonValue.Parse(lvResponseBody);
try
  lvName := lvJson.GetStr('name');                         // raises on wrong kind
  lvAge := lvJson.GetIntDef('age', 0);                     // default on missing
  lvFirst := lvJson.PathStrDef('data.items[0].name', '');  // dotted path, no nil checks

  lvItems := lvJson.FindPath('data.items');                // nil when missing
  for lvIdx := 0 to lvItems.Count - 1 do
    Log(lvItems.Items[lvIdx].GetStrDef('name', '(unnamed)'));
finally
  lvJson.Free;
end;
```

`Parse` raises `EbpJson` with line and column, `TryParse` returns `False`. The parser is strict: leading zeros, raw control characters, trailing commas, `NaN`, single quotes, junk after the value and numbers out of `Double` range all fail.

| Access | Missing | Wrong kind |
|--------|---------|------------|
| `GetStr(aName)` / `AsStr` | raises `EbpJson` | raises `EbpJson` |
| `GetStrDef(aName, aDefault)` | `aDefault` | `aDefault` |
| `TryGetStr(aName, aValue)` | `False` | `False` |
| `PathStrDef(aPath, aDefault)` | `aDefault` | `aDefault` |
| `Find(aName)` / `FindPath(aPath)` | `nil` | `nil` |

Same four shapes for `Bool`, `Int` (`Int64`) and `Float`; `AsFloat` accepts an int, nothing else converts.

```pascal
lvRoot := TbpJsonValue.CreateObject;
lvRoot.SetStr('name', 'first');              // create-or-replace; AddX appends
lvRoot.SetArray('tags').AddStr('new');       // container setters chain
Memo1.Text := lvRoot.ToJsonPretty;           // 2-space indent by default
lvRoot.Free;                                 // a container owns its children
```

`ToJson(True)` escapes everything above #127 as `\uXXXX` for a transport that is not UTF-8 clean. Below Delphi 2009 a string holds UTF-8 bytes in and out, so a `\uXXXX` escape and the raw character give the same result.

### [BpDateUtils](../src/Core/Units/BpDateUtils.pas)

The ISO 8601 / RFC 3339 handling the RTL skipped until XE6 - Delphi 2007 has no `ISO8601ToDate` at all.

```pascal
uses BpDateUtils;

lvUtc := BpISO8601ToDateTime('2026-07-24T12:34:56.789+03:00');  // UTC TDateTime
if not BpTryISO8601ToDateTime(lvJson.GetStr('created_at'), lvCreated) then ...

lvText := BpDateTimeToISO8601(lvUtc);        // 2026-07-24T09:34:56.789Z
lvLocal := BpDateTimeToISO8601Local(lvUtc);  // 2026-07-24T12:34:56.789+03:00
lvStamp := BpDateTimeToUnix(lvUtc);          // Int64 seconds, also *MS
```

Date-only values, `T`-or-space separators, fractional seconds and every zone form (`Z`, `+hh:mm`, `+hhmm`, `+hh`), parsed strictly: malformed input is rejected, not guessed at. Epoch conversion is `Int64` both ways, so pre-1970 and post-2038 round-trip cleanly.

### [TbpStringList](../src/Core/Classes/BpStringList.pas)

A `TStringList` whose `IndexOf` and `IndexOfName` answer in constant time. It descends from `TStringList`, so use it exactly like the original.

`TStringList.IndexOf` is a linear scan, and `IniFiles.THashedStringList` throws its hash away on every change, so a list both written and read goes quadratic. This one maintains the index incrementally through the hooks `TStringList` already has; only `Exchange`, `Sort` and `CustomSort` mark it stale.

Delphi 2007, 50,000 entries:

| operation | RTL | TbpStringList |
|-----------|-----|---------------|
| `Add` | `TStringList` 3.12 ms | 6.21 ms |
| `IndexOf` | `THashedStringList` 1180 ms | 17.4 ms |
| `Add` and `IndexOf` interleaved | `THashedStringList` 139,945 ms | 21.4 ms |
| `IndexOfName` | `TStringList` 1014 ms | 14.1 ms |

Adding costs about twice a plain `TStringList` and the first search pays it back. The name index is built only if you call `IndexOfName` or read `Values`. Case-insensitive keys fold through [BpKeyFold](#bpkeyfold), so a lookup allocates nothing and Cyrillic keys fold correctly.

### [TbpStrDictionary](../src/Core/Classes/BpStrDictionary.pas)

A string-keyed hash map with a `TDictionary`-style API, for compilers with no generics.

```pascal
uses BpStrDictionary;

lvDict := TbpStrDictionary.Create(True);        // case-insensitive keys
lvDict.SetInt('port', 8080);
lvDict['debug'] := True;                        // default property, AddOrSet
lvHost := lvDict.GetStrDef('HOST', '127.0.0.1');
if lvDict.TryGetInt('port', lvPort) then ...
```

| Call | Notes |
|------|-------|
| `Create(aCaseInsensitive, aInitialCapacity)` | both optional; presize when you know the count |
| `Add` | raises `EbpStrDictionary` on a duplicate key |
| `AddOrSet` | overwrite, same as writing `Items[]` |
| `TryGetValue` / `ContainsKey` / `Remove` | `Remove` returns `False` when the key was absent |
| `Count` / `Capacity` / `CaseInsensitive` | read-only |
| `Items[aKey]` | default property; reading a missing key raises |
| `ForEach(aCallback)` / `GetKeys(aStrings)` | iterate, or snapshot to sort |

Values are `Variant` and nothing is coerced: `'8080'` stored as a string will not answer `GetInt`. Each type gets three accessors - `GetInt` raises, `GetIntDef` returns the default, `TryGetInt` returns `False`, for both a missing key and the wrong type. The set is `Int`, `Int64`, `Str`, `Bool`, `Float`, plus `IntArray` here, each with a matching `SetX`; the rules live in [BpVariantUtils](#bpvariantutils).

Open addressing with linear probing, power-of-two capacity, 0.75 load factor and backward-shift deletion, so no tombstones slow down later lookups. Hashing is [BpHashBobJenkins](#bphashbobjenkins); folding cut a case-insensitive lookup from 9.96 ms to 2.55 ms over 20,000 keys on Delphi 2007.

### [TbpIntDictionary](../src/Core/Classes/BpIntDictionary.pas)

The same map with `Int64` keys. No case option, and `GetKeys` returns a `TbpInt64DynArray` instead of filling a `TStrings`. Keys go through the Thomas Wang 64-to-32 bit mix, exposed as `BpHashInt64`.

### [TbpIntList](../src/Core/Classes/BpIntList.pas)

A list of integers that behaves like the `TStringList` you know: `Add`, `Delete`, `Insert`, `IndexOf`, `Sorted`, `CommaText`, `DelimitedText`, load and save.

```pascal
uses BpIntList;

lvIds.CommaText := '5,3,9,1';
lvIds.Sorted := True;                         // 1,3,5,9, and stays ordered
if lvIds.BinarySearch(5, lvIndex) then
  lvIds.Delete(lvIndex);
```

`BinarySearch` needs the `Sorted` flag, so use `Sorted := True` rather than a bare `Sort` when you intend to search; `IndexOf` is the linear fallback either way. Sorting is an in-place introsort over a plain `array of Integer`, recursing into the smaller partition only and dropping to heapsort when the pivot keeps splitting badly: 400,000 organ-pipe values sort in 31 ms where a middle-pivot quicksort recurses 200,000 deep and dies. Implements `IBpIntList`; `TIntegerList` / `TIntList` are aliases for older code.

### [TbpInt64List](../src/Core/Classes/BpInt64List.pas)

The same list over `array of Int64`, for database keys, file sizes or millisecond timestamps. Parsing goes through `TryStrToInt64`, so text outside the range raises `EConvertError` instead of quietly wrapping.

---

## Strings

### [TbpStringBuilder](../src/Core/Classes/BpStringBuilder.pas)

The XE6 `TStringBuilder` API on the compilers that never got it. Appends write through a cached pointer into a geometrically grown buffer instead of resizing the string every call.

```pascal
uses BpStringBuilder;

lvSb := TbpStringBuilder.Create(1024);  // presize when you can
lvSb.Append('SELECT * FROM ').Append(lvTable);
lvSb.Append(lvIds[lvIdx]);              // Integer overload, no IntToStr
lvSb.AppendFormat(') LIMIT %d', [lvLimit]);
lvSql := lvSb.ToString;
```

`Append` is overloaded for `string`, `Char`, `Char` + repeat count, `Integer`, `Int64`, `Double` and `Boolean`, each returning `Self`; `AppendLine`, `AppendFormat`, `Insert`, `Clear` and `ToString` behave as in the RTL. `Chars[]` is the default property, and `Length` is writable - shrinking truncates, extending pads with `#0`. [The benchmark](../tests/Benchmarks/BpStringBuilderBenchmark.pas) measures it against `s := s + x`.

### [BpStrUtils](../src/Core/Units/BpStrUtils.pas)

The string helpers the old RTL never had.

```pascal
uses BpStrUtils;

lvParts := Split('a::b::c', '::');                     // TbpStringArray
lvLine := Join(lvParts, ' | ');
if StartsWith(lvUrl, 'https://') and EndsWithText(lvName, '.PAS') then ...

lvClean := FastStringReplace(lvHugeText, #13#10, ' ', [rfReplaceAll]);
```

`StartsWith` / `EndsWith` are case-sensitive, the `*Text` variants are not. `FastStringReplace` is the reason this unit exists: `SysUtils.StringReplace` recopies the tail on every hit and goes quadratic, this one scans for every match first and builds the result in one allocation. Same `TReplaceFlags`, so it is a drop-in swap.

---

## Hashing and encoding

Checked against the published standard vectors (FIPS, RFC), the Windows CryptoAPI and the XE6 RTL. All pure Pascal, no DLLs.

### [BpSHA256](../src/Core/Classes/BpSHA256.pas)

SHA-256 (FIPS 180-4), one-shot or streaming.

```pascal
uses BpSHA256;

lvHex := TbpSHA256.HashStrHex('hello');
lvHex := TbpSHA256.HashFileHex('setup.exe');            // streams the file
lvB64 := TbpSHA256.DigestToBase64(TbpSHA256.HashStr(lvText));

lvHasher := TbpSHA256.Create;                           // streaming
lvHasher.Update(lvBuf, lvRead);                         // or TBytes, or AnsiString
lvHasher.Final(lvDigest);                               // Final resets for reuse
```

`HashBuffer` / `HashBytes` / `HashStr` / `HashFile` return a `TbpSHA256Digest`; `DigestToHex` and `DigestToBase64` format it.

### [BpMD5](../src/Core/Classes/BpMD5.pas)

MD5 (RFC 1321), the same shape as [BpSHA256](#bpsha256). Broken for anything security-related: keep it to legacy checksums, ETags and old protocols that demand it.

### [BpHMACSHA256](../src/Core/Classes/BpHMACSHA256.pas)

HMAC-SHA256 (RFC 2104), for signing API requests and verifying webhooks.

```pascal
uses BpHMACSHA256;

lvSig := TbpHMACSHA256.ComputeHex(lvSecret, lvPayload);
if not BpConstantTimeEquals(lvSig, lvHeaderSig) then     // from BpPasswordHash
  raise Exception.Create('bad signature');
```

`Compute`, `ComputeHex` and `ComputeBase64` for one shot; `Create(aKey)` / `Update` / `Final` when the message is a stream. Keys of any length are handled per the RFC.

### [BpPasswordHash](../src/Core/Classes/BpPasswordHash.pas)

PBKDF2-HMAC-SHA256 (RFC 2898 / NIST SP 800-132). Never store a bare SHA-256 of a password.

```pascal
uses BpPasswordHash;

lvStored := BpHashPassword('correct horse battery staple');
// $pbkdf2-sha256$600000$Bx1n...$9f3c...   put this in your users table
if BpVerifyPassword(lvEntered, lvStored) then
  Login;
```

The salt comes from the Windows CSPRNG and the default is 600,000 iterations (current OWASP guidance). The record is self-describing, so the iteration count travels with the hash and you can raise it later without breaking old rows. `BpVerifyPassword` compares in constant time.

| Function | Use |
|----------|-----|
| `BpHashPassword(aPassword)` / `(aPassword, aIterations)` | store this |
| `BpVerifyPassword(aPassword, aStored)` | check a login |
| `BpPBKDF2SHA256(aPassword, aSalt, aIterations, aKeyLen)` | raw KDF, e.g. an encryption key |
| `BpPBKDF2SHA256Hex(...)` | the same, hex out |
| `BpGenerateSalt(aLen)` | CryptGenRandom bytes; raises rather than falling back |
| `BpConstantTimeEquals(A, B)` | no early exit, so timing leaks nothing |

### [BpBase64](../src/Core/Units/BpBase64.pas)

Base64 and Base64url (RFC 4648).

```pascal
uses BpBase64;

lvText := Base64Encode(lvBytes);            // or a buffer, or an AnsiString
lvJwtPart := Base64UrlEncode(lvHeaderJson); // -_ alphabet, no padding
lvBytes := Base64Decode(lvText);
lvRaw := Base64DecodeStr(lvText);           // AnsiString flavour

lvHeader := Base64EncodeUtf8(lvUser + ':' + lvPassword);
lvBack := Base64DecodeUtf8(lvHeader);       // WideString
```

Encoding is a single allocation. The decoder eats either alphabet, forgives missing padding and skips whitespace, so MIME-wrapped input just works; anything else raises `EbpBase64`.

The `Utf8` trio takes and returns `WideString` and always puts UTF-8 on the wire, so the same text gives the same Base64 on Delphi 7 and on Delphi 12, surrogate pairs included (the pre-2009 `UTF8Encode` gets those wrong). The `AnsiString` overloads encode the bytes handed to them and transcode nothing, so on Delphi 2009+ passing a `string` narrows it through the machine code page first. Base64 that is not valid UTF-8 makes `Base64DecodeUtf8` raise rather than hand back U+FFFD.

The `=` policy is pinned by tests: a pad is tolerated wherever it cannot be mistaken for data (`Zg=`, `Zg===`, `Zm9v=`, pad-only), and data after a pad raises, so `Zg==Zg` is rejected rather than half-read. Whitespace means exactly tab, LF, CR and space.

### [BpHashBobJenkins](../src/Core/Classes/BpHashBobJenkins.pas)

Bob Jenkins lookup3 (public domain), producing the same values as the RTL's `BobJenkinsHash` and the reference C, anchored on the published self-test vector `hashlittle('Four score and seven years ago', 30, 0) = $17770551`.

```pascal
lvBucket := TbpHashBobJenkins.GetHashValue(lvKey) and (lcBucketCount - 1);
```

Fast, well distributed and non-cryptographic - a bucket index, not a fingerprint. It powers [TbpStrDictionary](#tbpstrdictionary); `Reset` / `Update` / `HashAsInteger` for data arriving in pieces.

---

## Windows and odds and ends

### [TbpCredentials](../src/Core/Classes/BpCredentials.pas)

A secret store on the Windows Credential Manager, keyed by service and username like Python's keyring. No more config files with plaintext passwords.

```pascal
uses BpCredentials;

TbpCredentials.SetPassword('MyApp', 'api', 'secret-token');          // once, at setup
lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');  // raises if missing
if TbpCredentials.TryGetPassword('MyApp', 'api', lvToken) then ...   // soft version
```

Entries land under `'<service>/<username>'` in the vault the Control Panel shows, stored as UTF-16LE so .NET code reads them too. `DeletePassword`, `FindUserNames` and `DeleteAll` cover uninstall and account switching.

The vault is per-user: other accounts cannot read it, but any process running as you can. The `*Protected` variants add a `CryptProtectData` layer keyed by an entropy value your app supplies, so a casual same-user reader gets ciphertext - friction, not a hard boundary.

### [TbpObjectComparer](../src/Core/Classes/BpObjectComparer.pas)

Diffs two `TPersistent` objects by RTTI and tells you which published properties changed, walking nested objects and `TCollection` items.

```pascal
uses BpObjectComparer;

lvDiffs := TbpObjectComparer.CompareObjects(lvBefore, lvAfter);   // IPropDifference
Memo1.Text := TbpObjectComparer.CompareObjectsAsString(lvBefore, lvAfter);
```

Each difference carries the property path and the old and new values, ready for an audit log. Collection items can be matched by identity rather than position when they implement `IUniqueID` (`UniqueIdIntf.pas`), which is why old and new paths are separate fields: a moved item is reported as changed, not as two unrelated edits.

### [BpKeyFold](../src/Core/Units/BpKeyFold.pas)

Case folding for hash table keys. `AnsiUpperCase` allocates on every lookup, which is most of what a case-insensitive dictionary spends its time on; this folds through a table built once from the active code page instead.

```pascal
uses BpKeyFold;

if BpFoldedSame(lvKey, lvOther) then ...        // same relation as AnsiSameText
lvBucket := BpFoldedHash(lvKey) and lcMask;     // a hash that agrees with it
```

| Function | Returns |
|----------|---------|
| `BpFoldedHash(aKey)` | FNV-1a over the folded key, never negative |
| `BpFoldedSame(aA, aB)` | case-insensitive equality |
| `BpFoldChar(aCh)` | one character, upper cased |
| `BpFoldInto(aKey, aBuf, aBufChars)` | folded length, or `-1` when it will not fit |
| `BpKeyFoldUsable` | whether the table applies at all |

Folding one byte at a time equals `AnsiCompareText` only on a single byte code page, so on DBCS or a Unicode compiler every function falls back to the RTL: a hash and an equality test that disagreed would file a key in one bucket and look for it in another. Note also that `SysUtils.SameText` is ASCII only before 2009 and misses Cyrillic case pairs entirely.

### [BpVariantUtils](../src/Core/Units/BpVariantUtils.pas)

Strict Variant-to-native conversions: each succeeds only when the Variant already holds that type, so nothing is parsed, widened or rounded behind your back.

```pascal
if BpTryVarToInt(lvField, lvCount) then ...      // False for '42', True for 42
```

`BpTryVarToInt`, `BpTryVarToInt64`, `BpTryVarToStr`, `BpTryVarToBool`, `BpTryVarToFloat`, `BpTryVarToDate`, `BpTryVarToIntArray` - the shared rule set behind the dictionaries' typed accessors, so `GetIntDef` and `BpTryVarToInt` agree by construction. Three details:

- A `varDate` is a kind of its own, not a float, so `BpTryVarToFloat` rejects it and `BpTryVarToDate` reads it: a timestamp never arrives silently as 46264.52.
- Below Delphi 2009 a `varOleStr` converts only when the code page carries every character; when it does not, the call fails instead of handing you a `'?'`.
- `varUInt64` is read from the payload, not through a `Double`, so nothing is rounded. Past `High(Int64)` `BpTryVarToInt64` returns False; `BpTryVarToFloat` still takes it, unsigned.

### [BpSysUtils](../src/Core/Units/BpSysUtils.pas)

`CharInSet` overloads for `Char`, `WideChar` and `Byte`, so code written against a newer RTL builds on Delphi 7 and 2007 unchanged. The whole unit is inside `{$IF CompilerVersion < 20.0}`, so leaving it in `uses` on a modern compiler costs nothing.

### [StopWatch](../src/Core/Units/StopWatch.pas)

A `QueryPerformanceCounter` stopwatch with the `TStopwatch` shape, for Delphi 7 to 2007 (also `{$IF CompilerVersion < 20.0}`, so the RTL class wins later).

```pascal
uses StopWatch;

lvSw := TStopWatch.StartNew;
DoTheWork;
lvSw.Stop;
Log(Format('%.2f ms', [lvSw.ElapsedMilliseconds]));
```

`Reset`, `Start`, `ResetAndStart`, `Stop`, `ElapsedMilliseconds`, `ElapsedTicks`, `IsRunning`, plus `Instance` for a shared one. Returns `IStopWatch`, so there is nothing to free.

---

## Single-file bundles

Do not want to add ten units to your project? Take one file from [dist/](../dist/) instead - each is self-contained:

| Bundle | Contains |
|--------|----------|
| [BpDictionaries.pas](../dist/BpDictionaries.pas) | both dictionaries, hash and Variant helpers baked in |
| [BpHashes.pas](../dist/BpHashes.pas) | SHA-256, MD5, HMAC-SHA256, PBKDF2, Base64 |
| [BpHttpClientStandalone.pas](../dist/BpHttpClientStandalone.pas) | HTTP client, downloads, async task, cancellation token, Base64 |
| [BpJsonStandalone.pas](../dist/BpJsonStandalone.pas) | JSON reader/writer with the string builder baked in |

They are generated from the modular units, SQLite amalgamation style, by [tools/Amalgamate.ps1](../tools/Amalgamate.ps1) from a manifest per bundle in [tools/bundles/](../tools/bundles/). Treat them as build artifacts: fix the real unit and regenerate with `pwsh -NoProfile -File tools\Amalgamate.ps1`. A unit that turns range or overflow checking off is bracketed in the bundle, so your own `{$R+}` survives.

One catch: two bundles that embed the same helper declare its identifiers twice, and which one you get depends on `uses` order - `EbpBase64` raised inside one is not the `EbpBase64` the other catches. Today that is exactly `BpHashes` and `BpHttpClientStandalone`; use one or the other, and do not mix a bundle with the modular units it contains.

[tools/VerifyBundles.cmd](../tools/VerifyBundles.cmd) compiles each bundle on its own and runs a smoke test against known-answer vectors.
