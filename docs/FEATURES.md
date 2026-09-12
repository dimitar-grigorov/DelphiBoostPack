# Feature guide

What each unit gives you and where it bites. The [README](../README.md) is the tour. Add a unit to `uses` and go: no packages, no DLLs, no base class. For one file instead, see [single-file bundles](#single-file-bundles).

**Network and async** · [TbpHttpClient](#tbphttpclient) · [TbpHttpDownloadTask](#tbphttpdownloadtask) · [TbpCancellationToken](#tbpcancellationtoken) · [TbpTask](#tbptask)

**Data** · [TbpJsonValue](#tbpjsonvalue) · [BpDateUtils](#bpdateutils) · [TbpStringList](#tbpstringlist) · [TbpStrDictionary](#tbpstrdictionary) · [TbpIntDictionary](#tbpintdictionary) · [TbpIntList](#tbpintlist) · [TbpInt64List](#tbpint64list)

**Strings** · [TbpStringBuilder](#tbpstringbuilder) · [BpStrUtils](#bpstrutils)

**Hashing** · [BpSHA256](#bpsha256) · [BpMD5](#bpmd5) · [BpHMACSHA256](#bphmacsha256) · [BpPasswordHash](#bppasswordhash) · [BpBase64](#bpbase64) · [BpHashBobJenkins](#bphashbobjenkins)

**Windows and odds** · [TbpCredentials](#tbpcredentials) · [TbpObjectComparer](#tbpobjectcomparer) · [BpKeyFold](#bpkeyfold) · [BpVariantUtils](#bpvariantutils) · [BpSysUtils](#bpsysutils) · [StopWatch](#stopwatch)

---

## Network and async

### [TbpHttpClient](../src/Core/Classes/BpHttpClient.pas)

HTTP and HTTPS over WinInet, so TLS comes from Schannel: no OpenSSL DLLs, no certificate bundle to go stale. Microsoft does not support WinInet inside a Windows service, so reach for WinHTTP there.

```pascal
uses BpHttpClient;

lvBody := TbpHttpClient.FetchUrl('https://api.example.com/v1/status');

lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');
lvClient.AddHeader('X-Api-Version', '2');          // persistent
lvResp := lvClient.Get('https://api.example.com/v1/items', '', lvToken);
if BpHttpResponseIsSuccess(lvResp) then
  lvText := BpHttpResponseBodyAsUtf8(lvResp);
```

`Get`, `Post`, `PostJson`, `Put`, `Delete`, `Patch`, `Head`, `Options`, `Execute` and the `FetchUrl` class function. Every verb takes an optional header block and a [TbpCancellationToken](#tbpcancellationtoken) last.

```pascal
TbpHttpResponse = record
  StatusCode: Integer;
  StatusText: string;       // reason phrase, 'Not Found'
  Headers: string;         // raw, CRLF separated
  Body: AnsiString;        // raw bytes as received
  ContentLength: Int64;    // -1 when the header was absent
  FinalUrl: string;        // where the redirects ended
end;
```

A 404 is a response, not an exception. Only transport failures raise `EbpHttpClient`, which carries `StatusCode` and `WinInetError`.

**Properties.** `UserAgent` (`DelphiBoostPack/1.0`), `ConnectTimeout` / `SendTimeout` / `ReceiveTimeout` (8000 ms), `FollowRedirects` (`True`), `MaxRedirects` (10), `AutoDecompress` (`True`), `Username` / `Password` for WinInet challenge auth. Proxy settings come from Internet Options and WPAD with no code. One client owns one WinInet session, so keep the instance: every later request to the same host skips the TCP and TLS handshake. Setting `UserAgent` drops the session.

**Compression.** The buffered verbs send `Accept-Encoding: gzip, deflate` and let WinInet decode the reply, from Vista on. Downloads do not, because the decoded bytes would no longer match `Content-Length` and that is the check a truncated file is caught by.

**Headers.** `AddHeader` replaces a name already set and removes it on an empty value, and `Authorization` has one writer at a time: `AddHeader`, `BearerToken` and `SetBasicAuth` each replace whatever the others left. A name must be a non-empty RFC 7230 token; `BearerToken` and `UserAgent` reject CR and LF; `SetBasicAuth` rejects a colon in the user-id. Per-request headers merge on top. WinInet's cookie jar is off, so the only `Cookie` sent is one the caller set and a `Set-Cookie` is not remembered: that jar belongs to the logged-on user, is keyed by host alone, and would ride straight through the redirect credential strip.

**Redirects.** Followed by the client, not by WinInet, which replays the header block on every hop with no way to edit it. A hop to another origin, so any change of scheme, host or port, loses the persistent headers plus `Authorization`, `Cookie` and `Proxy-Authorization`, and never gets them back. The one exception `requests` also makes: the same host upgraded from `http` to `https` keeps them. Method per [WHATWG fetch](https://fetch.spec.whatwg.org/#http-redirect-fetch): 303 to GET unless HEAD, 301 and 302 only a POST, 307 and 308 unchanged; a downgraded method drops the body and its `Content-*` headers. `FollowRedirects := False` returns the 3xx instead.

**Downloads.** `Download` streams to any `TStream`, `DownloadToFile` to a file, both in constant memory with `Int64` progress and a token. `DownloadToFile` writes to a temporary file beside the destination and renames it over only on a 2xx, so a 404, a cancel, a truncated body or a typo in the url leaves whatever was already there untouched, and no temp file behind. They block, so use a worker thread or [TbpHttpDownloadTask](#tbphttpdownloadtask).

```pascal
procedure TMainForm.HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
  var aCancel: Boolean);
begin
  ProgressBar1.Position := BpHttpProgressPercent(aReceived, aTotal);  // -1 = unknown
  aCancel := FStopRequested;
end;

lvClient.DownloadToFile(lvUrl, 'C:\temp\big.zip', HandleProgress, FToken);
```

The file is kept only on a 2xx, and a body short of the advertised `Content-Length` is an error. Resume with `Range: bytes=<n>-` and append on a 206.

**Wire trace.** [BpHttpTrace.pas](../src/Core/Classes/BpHttpTrace.pas) is an optional in-process `ssh -v`: `TbpHttpTrace.Attach(aClient, aSink)`, `Detach` when done. It installs a WinInet status callback, so an untraced build pays nothing. The sink runs on the I/O thread. Headers never pass through it.

**Helpers.** `BpHttpResponseIsSuccess`, `BpHttpResponseBodyAsUtf8`, `BpHttpHeaderValue`, `BpHttpContentLength`, `BpHttpResponseHasBody`, `BpHttpRedirectTarget`, `BpHttpRedirectMethod`, `BpHttpStripCredentials`, `BpHttpStripContentHeaders`, `BpHttpReasonPhrase`, `BpHttpProgressPercent` and `BpClassifyHttpError`, which turns a WinInet code or an HTTP status into a sentence for a user. `ParseUrl`, `BuildHeaders`, `SameOrigin` and `KeepsCredentials` are public too.

### [TbpHttpDownloadTask](../src/Core/Classes/BpHttpClient.pas)

The non-blocking download, shaped like a C# `Task`. `Start` returns at once and the events arrive on the thread that created the task, marshalled through a hidden window, with no `ProcessMessages`.

```pascal
FTask := BpDownloadAsync(lvUrl, 'C:\temp\big.zip', HandleProgress, HandleComplete);
// FTask.State: dtsPending / dtsRunning / dtsSucceeded / dtsFailed / dtsCancelled
```

`Cancel` aborts even in a blocked read, and `Free` cancels, joins and releases in any state, so closing a form mid-download is safe. `Received` / `Total` are live counters, `Response` / `HttpStatus` / `ErrorMessage` / `ErrorCode` are authoritative once `IsFinished`, and all of them are lock-guarded for any thread. `OnError` fires before `OnComplete`. `Create(False)` puts the events on the worker thread, for console apps. A task is one-shot.

### [TbpCancellationToken](../src/Core/Classes/BpHttpClient.pas)

The C# `CancellationToken` for Delphi 7: one side calls `Cancel`, the working side polls `IsCancellationRequested`, and a registered cleanup runs inside `Cancel` itself, which is how a blocked read aborts instead of timing out. Thread-safe, one-shot, nothing in it is HTTP.

### [TbpTask](../src/Core/Classes/BpTasks.pas)

Run any method on a worker thread and get the result back on the main thread. Self-contained, one thread per task, no pool.

```pascal
uses BpTasks;

procedure TMainForm.DoCrunch(aSender: TObject; aToken: TbpTaskToken);
begin
  while HasWorkLeft and not aToken.IsCancellationRequested do
    CrunchNextChunk;   // worker thread, no UI calls in here
end;

FTask := BpRunAsync(DoCrunch, HandleDone);   // HandleDone runs on the main thread
```

Cancellation is cooperative, so no thread is killed. An exception in the work body lands in `ErrorClass` and `ErrorMessage` instead of crossing the thread boundary; `OnError` fires first, then `OnComplete` on every terminal state.

The caller owns the task and frees it from any thread. `Free` cancels, joins and cleans up in any state, and from the moment it is entered no further event starts: a queued completion is dropped, a running handler finishes first, and a handler may free its own task. Events go through one hidden dispatcher window, so they run on the main thread whichever thread created the task, and that thread has to pump messages. `Create(False)` runs them on the worker instead. An exception escaping a handler goes to `BpSetTaskExceptionHook`, else to `Classes.ApplicationHandleException`.

`TbpTaskToken` is a bare interlocked flag for polling work; [TbpCancellationToken](#tbpcancellationtoken) adds cleanups that run inside `Cancel`, for when something must be torn down to make the cancel prompt.

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
finally
  lvJson.Free;                                             // a container owns its children
end;
```

Four shapes per type: `GetX` raises, `GetXDef` returns the default, `TryGetX` returns `False`, `Find` / `FindPath` return `nil`. Same for `Str`, `Bool`, `Int` (`Int64`) and `Float`. `Parse` raises `EbpJson` with line and column, `TryParse` returns `False`, and the parser is strict about leading zeros, control characters, trailing commas, `NaN`, single quotes, junk after the value and out-of-range numbers.

```pascal
lvRoot := TbpJsonValue.CreateObject;
lvRoot.SetStr('name', 'first');              // create-or-replace; AddX appends
lvRoot.SetArray('tags').AddStr('new');       // container setters chain
Memo1.Text := lvRoot.ToJsonPretty;
```

`ToJson(True)` escapes everything above #127 as `\uXXXX`. Below Delphi 2009 a string holds UTF-8 bytes in and out.

### [BpDateUtils](../src/Core/Units/BpDateUtils.pas)

The ISO 8601 and RFC 3339 handling the RTL skipped until XE6. Delphi 2007 has no `ISO8601ToDate` at all.

```pascal
uses BpDateUtils;

lvUtc := BpISO8601ToDateTime('2026-07-24T12:34:56.789+03:00');  // UTC TDateTime
lvText := BpDateTimeToISO8601(lvUtc);        // 2026-07-24T09:34:56.789Z
lvLocal := BpDateTimeToISO8601Local(lvUtc);  // 2026-07-24T12:34:56.789+03:00
lvStamp := BpDateTimeToUnix(lvUtc);          // Int64 seconds, also *MS
lvWall := BpUtcToLocal(lvUtc);               // machine zone, or pass a zone
```

Date-only values, `T`-or-space separators, fractional seconds and every zone form, parsed strictly: malformed input is rejected, not guessed at. Epoch conversion is `Int64` both ways, so 1850 round-trips as cleanly as 2040. Local time follows the date, not the day the code runs, so a July stamp formatted in January still carries `+03:00`; every local call overloads on a `TTimeZoneInformation`. Where wall clock and UTC are not one-to-one, RFC 5545 decides: a time that occurs twice means the first, one in the skipped hour moves ahead by the gap.

### [TbpStringList](../src/Core/Classes/BpStringList.pas)

A `TStrings` with the whole `TStringList` API, so it goes wherever one is taken. Three things differ: `IndexOf` and `IndexOfName` are O(1) through an index built on first lookup that survives every mutation, `Sort` is a stable merge sort, and hashing, equality and order all read the same case-folded characters through [BpKeyFold](#bpkeyfold).

```pascal
lvList.Values['host'] := 'localhost';   // IndexOfName behind Values is O(1)
lvList.Sorted := True;                  // Find is a binary search on the same relation
```

That one relation is ordinal, the way Git and .NET `Ordinal` compare, not the Windows collation. So a hash hit and a binary search cannot disagree and a lookup allocates nothing, at the price of `_` sorting after `Z`; use `CustomSort` for a linguistic order. `Insert`, `Put`, `Exchange`, `Move` and `CustomSort` raise on a `Sorted` list. A variable typed `TStringList` has to be retyped. Numbers in [the benchmark](../tests/Benchmarks/BpStringListBenchmark.pas); the short version is that `THashedStringList` throws its hash away on every write and goes quadratic where this does not.

### [TbpStrDictionary](../src/Core/Classes/BpStrDictionary.pas)

A string-keyed hash map with a `TDictionary`-style API, for compilers with no generics.

```pascal
lvDict := TbpStrDictionary.Create(True);        // case-insensitive keys
lvDict.SetInt('port', 8080);
lvDict['debug'] := True;                        // default property, AddOrSet
lvHost := lvDict.GetStrDef('HOST', '127.0.0.1');
```

`Add` raises on a duplicate, `AddOrSet` overwrites, plus `TryGetValue`, `ContainsKey`, `Remove`, `Count`, `Capacity`, `ForEach` and `GetKeys`. Values are `Variant` and nothing is coerced: `'8080'` stored as a string will not answer `GetInt`. Each type has `GetX` raising, `GetXDef` defaulting and `TryGetX`, over `Int`, `Int64`, `Str`, `Bool`, `Float` and `IntArray`; the rules are [BpVariantUtils](#bpvariantutils).

Open addressing, power-of-two capacity, 0.75 load, backward-shift deletion so no tombstones accumulate, and the ordinal relation from [BpKeyFold](#bpkeyfold). `ForEach` may read but not write: a mutation during a callback raises, because a rehash under the scan would skip entries.

### [TbpIntDictionary](../src/Core/Classes/BpIntDictionary.pas)

The same map with `Int64` keys and no case option. `GetKeys` returns a `TbpInt64DynArray`. Keys go through the Thomas Wang 64-to-32 mix, exposed as `BpHashInt64`.

### [TbpIntList](../src/Core/Classes/BpIntList.pas)

A list of integers shaped like `TStringList`, with an `IndexOf` that does not scan: `Add`, `Delete`, `Insert`, `IndexOf`, `Find`, `Sorted`, `Duplicates`, `Capacity`, `CommaText`, `DelimitedText`, load and save.

```pascal
lvIds.CommaText := '5,3,9,1';
lvIds.Sorted := True;                         // 1,3,5,9, and stays ordered
if lvIds.Find(5, lvIndex) then
  lvIds.Delete(lvIndex);
```

`Find` bisects while `Sorted` and uses the hash index otherwise, reporting the insertion point on a miss. Values stay dense in one `array of Integer`, so `Items[]` is a single memory access. The index is built on first lookup, survives an append and is dropped by any move, so an append-only list keeps it. While `Sorted`, `Items[]`, `Insert` and `Exchange` raise. Sorting is an in-place introsort that drops to heapsort on bad pivots.

### [TbpInt64List](../src/Core/Classes/BpInt64List.pas)

The same list over `array of Int64`, for database keys, file sizes or millisecond timestamps. Same API line for line; parsing goes through `TryStrToInt64`, so text out of range raises instead of wrapping.

---

## Strings

### [TbpStringBuilder](../src/Core/Classes/BpStringBuilder.pas)

The XE6 `TStringBuilder` API on compilers that never got it. Appends write through a cached pointer into a geometrically grown buffer instead of resizing the string every call.

```pascal
lvSb := TbpStringBuilder.Create(1024);  // presize when you can
lvSb.Append('SELECT * FROM ').Append(lvTable);
lvSb.Append(lvIds[lvIdx]);              // Integer overload, no IntToStr
lvSql := lvSb.ToString;
```

`Append` is overloaded for `string`, `Char`, `Char` plus a count, `Integer`, `Int64`, `Double` and `Boolean`, each returning `Self`. `Chars[]` is the default property and `Length` is writable.

### [BpStrUtils](../src/Core/Units/BpStrUtils.pas)

`Split`, `Join`, `StartsWith` / `EndsWith` and their case-insensitive `*Text` variants, plus `FastStringReplace`, which is why the unit exists: `SysUtils.StringReplace` recopies the tail on every hit and goes quadratic, while this scans for all matches first and builds the result in one allocation. Same `TReplaceFlags`, so it is a drop-in swap.

---

## Hashing and encoding

Checked against the published standard vectors (FIPS, RFC) and the Windows CryptoAPI. All pure Pascal, no DLLs.

The `AnsiString` entry points hash the raw bytes they are given, so on Delphi 2009+ a `string` argument is narrowed through the active ANSI code page first and the digest differs from the Delphi 2007 one. Pass `AnsiString(UTF8Encode(lvText))` when the bytes matter. This holds for all four units below.

### [BpSHA256](../src/Core/Classes/BpSHA256.pas)

SHA-256 (FIPS 180-4), one-shot or streaming.

```pascal
lvHex := TbpSHA256.HashStrHex('hello');
lvHex := TbpSHA256.HashFileHex('setup.exe');            // streams the file

lvHasher := TbpSHA256.Create;                           // streaming
lvHasher.Update(lvBuf, lvRead);                         // or TBytes, or AnsiString
lvHasher.Final(lvDigest);                               // Final resets for reuse
```

`HashBuffer`, `HashBytes`, `HashStr` and `HashFile` return a `TbpSHA256Digest`, which `DigestToHex` and `DigestToBase64` format.

### [BpMD5](../src/Core/Classes/BpMD5.pas)

MD5 (RFC 1321), the same shape. Broken for anything security-related: keep it to legacy checksums, ETags and old protocols that demand it.

### [BpHMACSHA256](../src/Core/Classes/BpHMACSHA256.pas)

HMAC-SHA256 (RFC 2104), for signing API requests and verifying webhooks.

```pascal
lvSig := TbpHMACSHA256.ComputeHex(lvSecret, lvPayload);
if not BpConstantTimeEquals(lvSig, lvHeaderSig) then     // from BpPasswordHash
  raise Exception.Create('bad signature');
```

`Compute`, `ComputeHex` and `ComputeBase64` for one shot; `Create(aKey)` / `Update` / `Final` when the message is a stream. Keys of any length are handled per the RFC. The peer signs the UTF-8 body, so sign the same bytes, or hand it the `Body: AnsiString` that [TbpHttpClient](#tbphttpclient) already returns.

### [BpPasswordHash](../src/Core/Classes/BpPasswordHash.pas)

PBKDF2-HMAC-SHA256 (RFC 2898). Never store a bare SHA-256 of a password.

```pascal
lvStored := BpHashPassword('correct horse battery staple');
// $pbkdf2-sha256$600000$Bx1n...$9f3c...   put this in your users table
if BpVerifyPassword(lvEntered, lvStored) then
  Login;
```

Salt from the Windows CSPRNG, 600,000 iterations per current OWASP guidance. The record is self-describing, so the work factor travels with the hash and can be raised without breaking old rows. `BpVerifyPassword` compares in constant time and refuses a record whose iteration count or hash length is out of bounds, so a truncated row cannot authenticate; `BpHashPassword` raises `EbpPasswordHash` rather than mint one. Also `BpPBKDF2SHA256` and `BpPBKDF2SHA256Hex` as a raw KDF, `BpGenerateSalt` and `BpConstantTimeEquals`.

### [BpBase64](../src/Core/Units/BpBase64.pas)

Base64 and Base64url (RFC 4648).

```pascal
lvText := Base64Encode(lvBytes);            // or a buffer, or an AnsiString
lvJwtPart := Base64UrlEncode(lvHeaderJson); // -_ alphabet, no padding
lvBytes := Base64Decode(lvText);
lvHeader := Base64EncodeUtf8(lvUser + ':' + lvPassword);
```

Encoding is a single allocation. The decoder eats either alphabet, forgives missing padding and skips whitespace, so MIME-wrapped input just works; anything else raises `EbpBase64`, including data after a pad. The `Utf8` trio takes and returns `WideString` and always puts UTF-8 on the wire, so the same text gives the same Base64 on Delphi 7 and on Delphi 12, surrogate pairs included.

### [BpHashBobJenkins](../src/Core/Classes/BpHashBobJenkins.pas)

Bob Jenkins lookup3, producing the same values as the RTL's `BobJenkinsHash` and the reference C. Fast, well distributed and non-cryptographic: a bucket index, not a fingerprint. `Update` chains by re-seeding with the previous hash, as the RTL does, so a chunked result is not the one-shot hash of the concatenation; use `GetHashValue` over a contiguous buffer when you need that value.

---

## Windows and odds and ends

### [TbpCredentials](../src/Core/Classes/BpCredentials.pas)

A secret store on the Windows Credential Manager, keyed by service and username like Python's keyring.

```pascal
TbpCredentials.SetPassword('MyApp', 'api', 'secret-token');          // once, at setup
lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');  // raises if missing
if TbpCredentials.TryGetPassword('MyApp', 'api', lvToken) then ...   // soft version
```

Entries land under `'<service>/<username>'` in the vault the Control Panel shows, as UTF-16LE so .NET reads them too. Plus `DeletePassword`, `FindUserNames` and `DeleteAll`. The vault is per-user: other accounts cannot read it, but any process running as you can. The `*Protected` variants add a `CryptProtectData` layer keyed by your own entropy, which is friction, not a boundary.

### [TbpObjectComparer](../src/Core/Classes/BpObjectComparer.pas)

Diffs two `TPersistent` objects by RTTI and reports which published properties changed, `TCollection` items included.

```pascal
lvDiffs := TbpObjectComparer.CompareObjects(lvBefore, lvAfter);   // IPropDifference
Memo1.Text := TbpObjectComparer.CompareObjectsAsString(lvBefore, lvAfter);
```

Each difference carries the property path and the old and new values, ready for an audit log. Collection items match by identity rather than position when they implement `IUniqueID`, which is why old and new paths are separate fields: a moved item is reported as changed, not as two unrelated edits.

### [BpKeyFold](../src/Core/Units/BpKeyFold.pas)

One ordinal relation for string keys, so a hash table and a binary search cannot disagree: `BpKeyHash`, `BpKeyEquals` and `BpKeyCompare` all read the same folded characters, with `*Buf` variants for a slice with no `Copy`. The fold is upper casing through a table built once, in place of `AnsiUpperCase`, which allocates on every call.

It equals `AnsiSameText` on every single-byte pair of the active code page, which the suite checks exhaustively. It is not the collation: `AnsiCompareText` orders words linguistically, this orders bytes. `BpKeyFoldUsable` is False only on a DBCS code page before Unicode, where everything falls back to the RTL.

### [BpVariantUtils](../src/Core/Units/BpVariantUtils.pas)

Strict Variant-to-native conversions: each succeeds only when the Variant already holds that type, so nothing is parsed, widened or rounded behind your back.

```pascal
if BpTryVarToInt(lvField, lvCount) then ...      // False for '42', True for 42
```

`BpTryVarToInt`, `*Int64`, `*Str`, `*Bool`, `*Float`, `*Date` and `*IntArray` are the shared rule set behind the dictionaries' typed accessors. A `varDate` is its own kind, so a timestamp never arrives as 46264.52, and `varUInt64` is read from the payload rather than through a `Double`.

### [BpSysUtils](../src/Core/Units/BpSysUtils.pas)

`CharInSet` overloads for `Char`, `WideChar` and `Byte`, so code written against a newer RTL builds on Delphi 7 and 2007 unchanged. The whole unit is inside `{$IF CompilerVersion < 20.0}`, so leaving it in `uses` on a modern compiler costs nothing.

### [StopWatch](../src/Core/Units/StopWatch.pas)

A `QueryPerformanceCounter` stopwatch with the `TStopwatch` shape, for Delphi 7 to 2007 (also version-guarded, so the RTL class wins later).

```pascal
lvSw := TStopWatch.StartNew;   // IStopWatch, nothing to free
DoTheWork;
lvSw.Stop;
Log(Format('%.2f ms', [lvSw.ElapsedMilliseconds]));
```

---

## Single-file bundles

To avoid adding ten units to a project, take one self-contained file from [dist/](../dist/) instead:

| Bundle | Contains |
|--------|----------|
| [BpDictionaries.pas](../dist/BpDictionaries.pas) | both dictionaries, the key fold and the Variant helpers |
| [BpHashes.pas](../dist/BpHashes.pas) | SHA-256, MD5, HMAC-SHA256, PBKDF2, Base64 |
| [BpHttpClientStandalone.pas](../dist/BpHttpClientStandalone.pas) | HTTP client, downloads, async task, cancellation token, Base64 |
| [BpJsonStandalone.pas](../dist/BpJsonStandalone.pas) | JSON reader/writer with the string builder |

Generated from the modular units, SQLite amalgamation style, by [tools/Amalgamate.ps1](../tools/Amalgamate.ps1). Treat them as build artifacts: fix the real unit and regenerate.

One catch: two bundles that embed the same helper declare its identifiers twice, and which one you get depends on `uses` order, so an `EbpBase64` raised inside one is not the `EbpBase64` the other catches. Today that is `BpHashes` and `BpHttpClientStandalone`. Use one or the other, and do not mix a bundle with the modular units it contains.
