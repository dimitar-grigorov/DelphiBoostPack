# Feature guide

Every unit in DelphiBoostPack: what it is for, how to call it, and where the sharp edges are. The [README](../README.md) is the tour; this is the manual.

Add a unit to `uses` and go - no packages, no third-party DLLs, no base class to inherit from. Most units stand alone; the few that want a companion say so. Prefer a single file? See [single-file bundles](#single-file-bundles).

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

`BpHttpClient.pas` - HTTP and HTTPS over WinInet. TLS comes from Schannel, the same stack Windows Update uses, so no OpenSSL DLLs ship next to your exe and no certificate bundle goes stale. The shape is borrowed from C# `HttpClient` and JS `fetch`: one call per verb, a response record back.

The shortest thing that works:

```pascal
uses BpHttpClient;

lvBody := TbpHttpClient.FetchUrl('https://api.example.com/v1/status');
```

An instance when you need settings:

```pascal
lvClient := TbpHttpClient.Create;
try
  lvResp := lvClient.Get('https://api.example.com/v1/items');
  if BpHttpResponseIsSuccess(lvResp) then
    lvText := BpHttpResponseBodyAsUtf8(lvResp);
finally
  lvClient.Free;
end;
```

| Call | Notes |
|------|-------|
| `Get(aUrl, aHeaders, aToken)` | |
| `Post(aUrl, aBody, aHeaders, aToken)` | raw body, you set the content type |
| `PostJson(aUrl, aJson, aToken)` | sets `Content-Type: application/json` |
| `Put(aUrl, aBody, aHeaders, aToken)` | |
| `Delete(aUrl, aHeaders, aToken)` | |
| `Execute(aUrl, aMethod, aHeaders, aBody, aToken)` | the one they all call |
| `FetchUrl(aUrl, aHeaders)` | class function, body only |

Everything after the URL is optional, so `Get(lvUrl)` is a complete call.

Every verb returns a `TbpHttpResponse`:

```pascal
TbpHttpResponse = record
  StatusCode: Integer;
  StatusText: string;
  Headers: string;         // raw, CRLF separated
  Body: AnsiString;        // raw bytes as received
  ContentLength: Int64;    // -1 when the header was absent
end;
```

A 404 is a response, not an exception. Only transport failures raise `EbpHttpClient` (which carries `StatusCode` and `WinInetError`), so `if not BpHttpResponseIsSuccess(...)` is the normal branch for HTTP-level errors.

#### Auth and headers

```pascal
lvClient.BearerToken := 'eyJhbGciOi...';       // Authorization: Bearer <token>
lvClient.SetBasicAuth('user', 'pass');         // preemptive Basic, clears BearerToken
lvClient.AddHeader('X-Api-Version', '2');      // persistent, sent with every request
lvClient.ClearHeaders;
```

`AddHeader` replaces a name that is already set, and rejects a CR or LF in the name or value (and a colon in the name) with `EbpHttpClient` - otherwise a value taken from a config file or a database column could append headers of its own and override the `Authorization` the client set. `BearerToken` is checked the same way. Per-request headers go in the `aHeaders` argument as raw CRLF-separated lines and are merged on top of the persistent ones, a name in both sent once with the per-request value. Keep the token out of your config file by pulling it from [TbpCredentials](#tbpcredentials):

```pascal
lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');
```

| Property | Default |
|----------|---------|
| `UserAgent` | `DelphiBoostPack/1.0` |
| `ConnectTimeout` / `SendTimeout` / `ReceiveTimeout` | 8000 ms each |
| `FollowRedirects` | `True` |
| `Username` / `Password` | empty (WinInet challenge-response auth) |

Proxy settings come from WinInet, so Internet Options and WPAD are honoured with no code.

#### Connection reuse

One client owns one WinInet session, opened on the first request and closed with the instance. WinInet keeps its connections alive on that session, so every request after the first to the same host skips the TCP and TLS handshake - the same reason C# `HttpClient` is meant to be kept rather than newed per call. Hold the instance for the life of the form or the service; `FetchUrl` and a `Create` / `Free` around every call pay the handshake each time.

Setting `UserAgent` drops the session, since `InternetOpen` bakes the agent string into it. The timeouts are re-applied to a live session as you assign them, and take effect from the next request.

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

`BpClassifyHttpError` turns a WinInet code or an HTTP status into a sentence you can show a user - no internet connection, the server took too long, not found. Pass 0 for the dimension that does not apply.

#### Cancelling a request

Every verb takes a [TbpCancellationToken](#tbpcancellationtoken) as its last argument. `Cancel` closes the WinInet handle from the other thread, so a request blocked in connect, send or receive aborts at once instead of waiting out the timeout, and the call raises `EbpHttpClientCancelled`:

```pascal
lvResp := FClient.PostJson(lcApiUrl, lvQuery, FToken);   // worker thread
...
FToken.Cancel;                                           // UI thread, on close
```

That is what makes a worker joinable at shutdown: without a token the join waits for `ReceiveTimeout`.

#### Wire trace

An in-process `ssh -v` for when a request misbehaves in the field, in an optional companion unit: [BpHttpTrace.pas](../src/Core/Classes/BpHttpTrace.pas). Nothing references it, it is not in the standalone bundle, and `BpHttpClient` knows nothing about it - copy the file next to the client only when you need it.

```pascal
uses BpHttpTrace;

procedure MyTrace(aHandle: Pointer; const aLine: string);
begin
  Log(Format('[http %p] %s', [aHandle, aLine]));
end;

TbpHttpTrace.Attach(FClient, MyTrace);   // any thread, any time
TbpHttpTrace.Detach(FClient);
```

```
[http 00CC0A18] resolving api.example.com
[http 00CC0A18] connected to 93.184.216.34:443
[http 00CC0A18] sending request
[http 00CC0A18] request sent (412 bytes)
[http 00CC0A18] response received (1460 bytes)
```

`Attach` installs a WinInet status callback on the client's session, which is all the client contributes: `SessionHandle` and a non-zero request context. Detached, there is no callback, so an untraced build pays nothing.

The sink is a bare procedure - no method pointers, no logging unit anywhere near the client - and it runs on the thread doing the I/O, so keep it quick and thread-safe. The method, the URL and the HTTP status are yours already, at the call site; this covers only what happens in between.

Headers never pass through it, so no `Authorization` value can reach a log, and `SanitizeUrl` strips `user:pass@` from a redirect target. A token in a query string is still a query string - that one is yours to keep out.

#### Streaming downloads

`Download` streams to any `TStream`, `DownloadToFile` to a file. Both run in constant memory whatever the size, report progress in `Int64`, and take a cancellation token. They block, so call them from a worker thread - or use [TbpHttpDownloadTask](#tbphttpdownloadtask).

```pascal
procedure TMainForm.HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
  var aCancel: Boolean);
begin
  ProgressBar1.Position := BpHttpProgressPercent(aReceived, aTotal);  // -1 = unknown
  aCancel := FStopRequested;
end;

lvClient.DownloadToFile('https://host/big.zip', 'C:\temp\big.zip', HandleProgress, FToken);
```

`aTotal` is `-1` when the server sent no `Content-Length`. `DownloadToFile` keeps the file only on a 2xx: on an error, a cancel or a non-2xx status it deletes the partial file, so an error page can never masquerade as the payload. A body that stops short of the advertised `Content-Length` counts as an error too - a connection that dies mid-transfer looks like a clean end of stream to WinInet, so without that check a truncated file would be reported as a successful download. Cancelling raises `EbpHttpClientCancelled`.

Resume is one header away - send a range and append when the server answers 206:

```pascal
lvHeaders := Format('Range: bytes=%d-', [lvBytesAlreadyOnDisk]);
lvResp := lvClient.Download(lvUrl, lvAppendStream, HandleProgress, FToken, lvHeaders);
```

#### Helpers

| Function | Returns |
|----------|---------|
| `BpHttpResponseIsSuccess(aResponse)` | 2xx |
| `BpHttpResponseBodyAsUtf8(aResponse)` | body decoded as UTF-8 (`WideString`) |
| `BpHttpHeaderValue(aHeaders, aName)` | one header from a raw block, `''` when absent |
| `BpHttpContentLength(aHeaders)` | `Int64`, `-1` when absent or invalid |
| `BpHttpProgressPercent(aReceived, aTotal)` | 0..100, `-1` when the total is unknown |
| `BpClassifyHttpError(aWinInetError, aHttpStatus)` | a user-facing sentence |

`ParseUrl` and `BuildHeaders` are public too - useful on their own, and the reason URL parsing is unit-tested.

### [TbpHttpDownloadTask](../src/Core/Classes/BpHttpClient.pas)

`BpHttpClient.pas` - the non-blocking download, shaped like a C# `Task` or a JS promise. `Start` returns immediately, the download runs on its own worker thread, and progress and completion arrive as events on the thread that created the task. No `ProcessMessages` anywhere: events are marshalled through a hidden window's message queue.

`BpDownloadAsync` creates, wires and starts one in a single call (a hot task, C# style):

```pascal
FTask := BpDownloadAsync('https://host/big.zip', 'C:\temp\big.zip',
  HandleProgress, HandleComplete);
```

```pascal
procedure TMainForm.HandleComplete(aSender: TObject);
begin
  case FTask.State of
    dtsSucceeded: ShowMessage('Done');
    dtsCancelled: ShowMessage('Cancelled');
    dtsFailed:    ShowMessage(FTask.ErrorMessage);
  end;
end;
```

`FTask.Cancel` from a Stop button aborts promptly, even while the worker sits in a blocked read, and the partial file is cleaned up. `FTask.Free` cancels, joins the worker and releases everything in any state - so a form closing mid-download is safe.

For auth, timeouts or a stream destination, build the task yourself:

```pascal
FTask := TbpHttpDownloadTask.Create;
FTask.Client.BearerToken := lvToken;           // the full TbpHttpClient surface
FTask.Client.ReceiveTimeout := 30000;
FTask.Url := lvUrl;
FTask.DestFileName := lvFileName;              // or DestStream, caller-owned
FTask.OnProgress := HandleProgress;
FTask.OnComplete := HandleComplete;
FTask.Start;
```

| Member | Notes |
|--------|-------|
| `State` | `dtsPending` / `dtsRunning` / `dtsSucceeded` / `dtsFailed` / `dtsCancelled` |
| `Received` / `Total` | live counters, `Total` is `-1` while unknown |
| `Response` / `HttpStatus` / `ErrorMessage` / `ErrorCode` | results, authoritative once `IsFinished` |
| `WaitFor(aTimeoutMs)` | blocks; for console apps and tests |
| `OnError` | fires before `OnComplete` on `dtsFailed` |

All result properties are lock-guarded, so reading them from any thread is safe. Console apps with no message loop pass `Create(False)` (or `BpDownloadAsync(..., False)`) and get their events on the worker thread. `BpDownloadToStreamAsync` is the stream flavour. A task is one-shot: create a new one per download.

### [TbpCancellationToken](../src/Core/Classes/BpHttpClient.pas)

`BpHttpClient.pas` - the C# `CancellationToken` / JS `AbortController` idea for Delphi 7. One side calls `Cancel`, the working side polls - and a registered cleanup runs inside the `Cancel` itself, which is how a request or download aborts a read that is already blocked instead of waiting for it to time out.

```pascal
FToken := TbpCancellationToken.Create;
...
if FToken.IsCancellationRequested then
  Exit;
...
FToken.Cancel;   // safe from any thread, one-shot
```

Thread-safe, one-shot and transport-agnostic - there is nothing HTTP in it, so it fits any cooperative cancel. `TbpHttpDownloadTask` owns one and exposes it as `Token`.

### [TbpTask](../src/Core/Classes/BpTasks.pas)

`BpTasks.pas` - run any method on a worker thread and get the result back on the thread that started it. C# `Task` ergonomics on a compiler that predates them by a decade. Self-contained: `Classes, SysUtils, Windows, Messages` and nothing else from the pack. One thread per task, no pool - a scoped stand-in for AsyncCalls when you just want this one thing off the UI thread.

`BpRunAsync` creates, wires and starts a task in one call:

```pascal
uses BpTasks;

procedure TMainForm.DoCrunch(aSender: TObject; aToken: TbpTaskToken);
begin
  while HasWorkLeft and not aToken.IsCancellationRequested do
    CrunchNextChunk;   // worker thread, no UI calls in here
end;

procedure TMainForm.HandleDone(aSender: TObject);
begin
  case FTask.State of
    tskSucceeded: StatusBar1.SimpleText := 'Done';
    tskCancelled: StatusBar1.SimpleText := 'Cancelled';
    tskFailed:    StatusBar1.SimpleText := FTask.ErrorMessage;
  end;
end;

FTask := BpRunAsync(DoCrunch, HandleDone);   // returns immediately
```

`HandleDone` runs on the thread that called `BpRunAsync`, so touching the UI from it is fine.

#### Cancelling and cleanup

The work polls, so cancellation is cooperative and no thread gets killed. `Free` cancels, joins the worker and cleans up in any state:

```pascal
FTask.Cancel;        // safe from any thread, also before Start
FreeAndNil(FTask);   // blocks only as long as the work takes to notice
```

Check the token often enough that a cancel feels immediate. If the work blocks in a call you cannot interrupt, the join waits for it.

#### Failures

An exception in the work body does not cross the thread boundary. It is caught, recorded and reported:

```pascal
procedure TMainForm.HandleError(aSender: TObject; const aErrorMessage: string);
begin
  Log(Format('%s: %s', [FTask.ErrorClass, aErrorMessage]));
end;
```

`ErrorClass` is the exception's class name (`''` when there was none), `ErrorMessage` its message. `OnError` fires first, then `OnComplete` - and `OnComplete` fires on every terminal state, which is why `case FTask.State` above is the idiomatic shape.

#### Full control

```pascal
FTask := TbpTask.Create;      // create on the thread that should get the events
FTask.Work := DoCrunch;
FTask.OnComplete := HandleDone;
FTask.OnError := HandleError;
FTask.Start;                  // raises EbpTask if Work is unassigned
```

| Member | Notes |
|--------|-------|
| `Work` | `procedure(aSender: TObject; aToken: TbpTaskToken) of object` |
| `Token` | owned; the same instance the work receives |
| `State` | `tskPending` / `tskRunning` / `tskSucceeded` / `tskFailed` / `tskCancelled` |
| `IsFinished` / `WaitFor(aTimeoutMs)` | terminal state reached; blocking wait |
| `Create(False)` | no marshalling - events fire on the worker thread |

**Two tokens, on purpose.** `TbpTaskToken` here is a bare interlocked flag with no dependencies. [TbpCancellationToken](#tbpcancellationtoken) adds cleanups that run inside `Cancel`, which is what makes a blocked socket read abort. Use the light one for polling work, the HTTP one when something must be torn down for the cancel to be prompt.

---

## Data

### [TbpJsonValue](../src/Core/Classes/BpJson.pas)

`BpJson.pas` - a JSON reader and writer (RFC 8259) in one class. No RTTI, no data binding, no attributes: the tree is the API, tagged by `Kind`.

#### Reading

```pascal
uses BpJson;

lvJson := TbpJsonValue.Parse(lvResponseBody);
try
  lvName := lvJson.GetStr('name');                         // raises on wrong kind
  lvAge := lvJson.GetIntDef('age', 0);                     // default on missing
  if lvJson.TryGetBool('active', lvActive) then ...

  lvFirst := lvJson.PathStrDef('data.items[0].name', '');  // dotted path, no nil checks
finally
  lvJson.Free;
end;
```

`Parse` raises `EbpJson` with the line and column; `TryParse` returns `False` instead. That holds for numbers out of `Double` range too: a 400-digit exponent is rejected as a parse error rather than escaping as a floating point trap. The parser is strict on purpose - leading zeros, raw control characters, trailing commas, `NaN`, single quotes and junk after the value all fail, so malformed input is a clear error rather than a surprise three screens later.

Arrays and objects share `Count` and `Items[]`; objects add `Names[]`:

```pascal
lvItems := lvJson.FindPath('data.items');     // nil when missing or wrong kind
if lvItems <> nil then
  for lvIdx := 0 to lvItems.Count - 1 do
    Log(lvItems.Items[lvIdx].GetStrDef('name', '(unnamed)'));
```

| Access | Missing | Wrong kind |
|--------|---------|------------|
| `GetStr(aName)` / `AsStr` | raises `EbpJson` | raises `EbpJson` |
| `GetStrDef(aName, aDefault)` | `aDefault` | `aDefault` |
| `TryGetStr(aName, aValue)` | `False` | `False` |
| `PathStrDef(aPath, aDefault)` | `aDefault` | `aDefault` |
| `Find(aName)` / `FindPath(aPath)` | `nil` | `nil` |

A lookup on a non-object answers as if the member were missing.

Same four shapes for `Bool`, `Int` (`Int64`) and `Float`. `AsFloat` accepts an int; nothing else converts.

#### Writing

```pascal
lvRoot := TbpJsonValue.CreateObject;
try
  lvRoot.SetStr('name', 'first');
  lvRoot.SetInt('qty', 3);
  lvTags := lvRoot.SetArray('tags');
  lvTags.AddStr('new');
  lvTags.AddStr('sale');
  lvRoot.SetObject('meta').SetStr('source', 'import');

  lvResp := lvClient.PostJson(lvUrl, lvRoot.ToJson);
  Memo1.Text := lvRoot.ToJsonPretty;             // 2-space indent by default
finally
  lvRoot.Free;
end;
```

`SetX` is create-or-replace, `AddX` appends to an array, and `SetArray` / `SetObject` / `AddArray` / `AddObject` return the new container so you can keep going. Pass `aEscapeNonAscii := True` to `ToJson` when the transport is not UTF-8 clean and you want everything above #127 as `\uXXXX`.

Encoding below Delphi 2009: a string is UTF-8 bytes, in and out. A `\uXXXX` escape decodes to the same bytes as the raw character, and the writer reads them back the same way, so a round trip loses nothing that the machine code page happens not to carry.

Ownership is simple: a container owns its children, so freeing the root frees the tree. `Clone` gives you a deep copy you own; the standalone `CreateX` constructors give you a value you own until you add it somewhere.

### [BpDateUtils](../src/Core/Units/BpDateUtils.pas)

The ISO 8601 / RFC 3339 handling the RTL skipped until XE6. Delphi 2007 has no `ISO8601ToDate` at all, and every JSON API dates in ISO 8601, so this is the natural companion to [TbpJsonValue](#tbpjsonvalue).

```pascal
uses BpDateUtils;

lvUtc := BpISO8601ToDateTime('2026-07-24T12:34:56.789+03:00');  // UTC TDateTime
if not BpTryISO8601ToDateTime(lvJson.GetStr('created_at'), lvCreated) then
  raise Exception.Create('bad timestamp');

lvText := BpDateTimeToISO8601(lvUtc);                           // 2026-07-24T09:34:56.789Z
lvLocal := BpDateTimeToISO8601Local(lvUtc);                     // 2026-07-24T12:34:56.789+03:00

lvStamp := BpDateTimeToUnix(lvUtc);                             // Int64 seconds
lvMillis := BpDateTimeToUnixMS(lvUtc);                          // Int64 milliseconds
lvBack := BpUnixMSToDateTime(lvMillis);
```

It parses date-only values, `T`-or-space separators, fractional seconds and every zone form (`Z`, `+hh:mm`, `+hhmm`, `+hh`), and it parses them strictly - malformed input is rejected, not guessed at. A value with no zone comes back as written, since there is nothing to convert. Epoch conversion is `Int64` in both directions, so dates before 1970 and past 2038 round-trip cleanly.

### [TbpStringList](../src/Core/Classes/BpStringList.pas)

`BpStringList.pas` - a `TStringList` whose `IndexOf` and `IndexOfName` answer in constant time. It is a `TStringList` descendant, so it goes wherever a `TStrings` goes and everything you already use keeps working: `Text`, `CommaText`, `DelimitedText`, `Values`, `Names`, `Objects`, `Sorted`, `Duplicates`, `CustomSort`, `LoadFromFile`, `Assign`.

```pascal
uses BpStringList;

lvList := TbpStringList.Create;        // then use it exactly like a TStringList
try
  lvList.Add('gamma');
  lvList.Values['host'] := 'localhost';
  if lvList.IndexOf('gamma') >= 0 then ...
  lvPort := lvList.Values['port'];
finally
  lvList.Free;
end;
```

The RTL gives you two bad choices for a list you search: `TStringList.IndexOf` is a linear scan, and `THashedStringList` in `IniFiles` throws its whole hash away on every change and rebuilds it on the next lookup, so a list that is both written and read goes quadratic. This one maintains the index incrementally through the hooks `TStringList` already has - `InsertItem`, `Put`, `Delete`, `Clear` - so a write costs one bucket update, not a rebuild. Only the operations that reorder the whole list (`Exchange`, `Sort`, `CustomSort`) mark it stale, and then just one lookup rebuilds it.

Measured on Delphi 2007, 50,000 entries:

| operation | RTL | TbpStringList |
|-----------|-----|---------------|
| `Add` | `TStringList` 3.12 ms | 6.21 ms |
| `IndexOf` | `THashedStringList` 1180 ms | 17.4 ms |
| `Add` and `IndexOf` interleaved | `THashedStringList` 139,945 ms | 21.4 ms |
| `IndexOfName` | `TStringList` 1014 ms | 14.1 ms |

Adding costs about twice a plain `TStringList`, one hash and one bucket write per row; that is the whole price, and the first search pays it back. There are two indexes, one over the line and one over the name part, and the name one is only built if you ever call `IndexOfName` or read `Values`.

It wants one companion, [BpKeyFold](#bpkeyfold). Case-insensitive keys (the default, as in `TStringList`) fold through it, so a lookup allocates nothing and non-ASCII keys fold correctly - `SysUtils.SameText` is ASCII-only on the pre-Unicode compilers, which silently breaks Cyrillic keys. `CaseSensitive` and `NameValueSeparator` can still be changed at any time; the index notices and rebuilds.

`IndexOf` answers with the lowest matching row, the same as `TStringList`. The tests drive the same operations into a `TStringList` and into this one and compare every answer, so the work-alike claim is checked rather than asserted.

### [TbpStrDictionary](../src/Core/Classes/BpStrDictionary.pas)

`BpStrDictionary.pas` - a string-keyed hash map with a `TDictionary`-style API, for compilers with no generics. `TDictionary` arrived in Delphi 2009; before that the choice was `TStringList.Values` (linear scans, everything a string) or nothing.

```pascal
uses BpStrDictionary;

lvDict := TbpStrDictionary.Create(True);        // case-insensitive keys
try
  lvDict.SetStr('host', 'localhost');
  lvDict.SetInt('port', 8080);
  lvDict['debug'] := True;                      // default property, AddOrSet

  lvHost := lvDict.GetStrDef('HOST', '127.0.0.1');
  if lvDict.TryGetInt('port', lvPort) then
    Connect(lvHost, lvPort);
finally
  lvDict.Free;
end;
```

| Call | Notes |
|------|-------|
| `Create(aCaseInsensitive, aInitialCapacity)` | both optional; presize when you know the count |
| `Add` | raises `EbpStrDictionary` on a duplicate key |
| `AddOrSet` | overwrite, same as writing `Items[]` |
| `TryGetValue` / `ContainsKey` / `Remove` | `Remove` returns `False` when the key was absent |
| `Clear` / `SetCapacity` | |
| `Count` / `Capacity` / `CaseInsensitive` | read-only |
| `Items[aKey]` | default property; reading a missing key raises |

Iterate with `ForEach`, or `GetKeys` into a `TStrings` when you want to sort or snapshot:

```pascal
procedure TMainForm.DumpPair(const aKey: string; const aValue: Variant;
  var aStop: Boolean);
begin
  Memo1.Lines.Add(aKey + '=' + VarToStr(aValue));
  aStop := Memo1.Lines.Count > 100;
end;

lvDict.ForEach(DumpPair);
```

#### Typed accessors

Values are `Variant`, but nothing is coerced behind your back. Each type gets three accessors, and asking for the wrong type is an error rather than a silent conversion - `'8080'` stored as a string will not answer `GetInt`:

| Form | Missing key | Wrong type |
|------|-------------|------------|
| `GetInt(aKey)` | raises | raises |
| `GetIntDef(aKey, aDefault)` | `aDefault` | `aDefault` |
| `TryGetInt(aKey, aValue)` | `False` | `False` |

The set is `Int`, `Int64`, `Str`, `Bool`, `Float`, plus `IntArray` on the string dictionary for stashing a list of ids in one slot. Every type has a matching `SetX`. The rules live in [BpVariantUtils](#bpvariantutils).

Under the hood: open addressing with linear probing, power-of-two capacity, a 0.75 load factor and backward-shift deletion, so there are no tombstones to slow down later lookups. Hashing is [BpHashBobJenkins](#bphashbobjenkins). Case-insensitive mode folds the key through an upper-case table built once from the active code page, so a lookup allocates nothing; on a multi-byte code page, where folding one byte at a time would be wrong, it falls back to `AnsiUpperCase` and `AnsiSameText`. Folding cut a case-insensitive lookup from 9.96 ms to 2.55 ms over 20,000 keys on Delphi 2007, and an insert from 5.20 ms to 3.11 ms.

### [TbpIntDictionary](../src/Core/Classes/BpIntDictionary.pas)

`BpIntDictionary.pas` - the same map with `Int64` keys. No case option, and `GetKeys` returns a `TbpInt64DynArray` instead of filling a `TStrings`:

```pascal
uses BpIntDictionary;

lvById := TbpIntDictionary.Create;
try
  lvById.SetStr(1001, 'Ada');
  lvById.SetStr(1002, 'Grace');

  lvKeys := lvById.GetKeys;
  for lvIdx := 0 to High(lvKeys) do
    Log(Format('%d -> %s', [lvKeys[lvIdx], lvById.GetStr(lvKeys[lvIdx])]));
finally
  lvById.Free;
end;
```

Keys go through the Thomas Wang 64-to-32 bit mix, exposed as `BpHashInt64` if you want it elsewhere.

### [TbpIntList](../src/Core/Classes/BpIntList.pas)

`BpIntList.pas` - a list of integers that behaves like the `TStringList` you already know: `Add`, `Delete`, `Insert`, `IndexOf`, `Sorted`, `CommaText`, `DelimitedText`, load and save.

```pascal
uses BpIntList;

lvIds := TbpIntList.Create;
try
  lvIds.CommaText := '5,3,9,1';
  lvIds.Sorted := True;                         // 1,3,5,9, and stays ordered
  if lvIds.BinarySearch(5, lvIndex) then
    lvIds.Delete(lvIndex);

  lvIds.Delimiter := ';';
  Log(lvIds.DelimitedText);                     // 1;3;9
  lvIds.SaveToFile('ids.txt');
finally
  lvIds.Free;
end;
```

`Sorted := True` sorts and keeps insertions ordered, which is what makes `BinarySearch` worth reaching for on big lists - and `BinarySearch` needs that flag, so use `Sorted := True` rather than a bare `Sort` when you intend to search; `IndexOf` is the linear fallback and works either way. Sorting is an in-place introsort over a plain `array of Integer` - no `TList` of casted pointers, no boxing. It recurses into the smaller partition only, so the stack stays logarithmic, and drops to heapsort when the pivot keeps splitting badly, so the pathological shapes stay O(n log n): 400,000 organ-pipe values sort in 31 ms where a plain middle-pivot quicksort recurses 200,000 deep and dies. The class implements `IBpIntList` if you prefer interface lifetimes, and `TIntegerList` / `TIntList` are aliases for older code.

### [TbpInt64List](../src/Core/Classes/BpInt64List.pas)

`BpInt64List.pas` - the same list, storing `Int64`. Reach for it when the values are database keys, file sizes, Unix timestamps in milliseconds or anything else that outgrows 32 bits.

```pascal
uses BpInt64List;

lvIds := TbpInt64List.Create;
try
  lvIds.CommaText := '9223372036854775807,-2147483649,42';
  lvIds.Sort;                                   // -2147483649,42,9223372036854775807
  Log(lvIds.DelimitedText);
finally
  lvIds.Free;
end;
```

Same API as `TbpIntList` - `Add`, `Delete`, `Insert`, `IndexOf`, `BinarySearch`, `Sorted`, `CommaText`, `DelimitedText`, load and save - over an `array of Int64`, with `CompareInt64` in place of `CompareInt`. Parsing goes through `TryStrToInt64`, so text outside the `Int64` range raises `EConvertError` instead of quietly wrapping. It implements `IBpInt64List` for interface lifetimes.

---

## Strings

### [TbpStringBuilder](../src/Core/Classes/BpStringBuilder.pas)

`BpStringBuilder.pas` - the XE6 `TStringBuilder` API on the compilers that never got it. Appends write through a cached pointer into the buffer and grow it geometrically, instead of resizing the string on every call. [BpStringBuilderBenchmark.pas](../tests/Benchmarks/BpStringBuilderBenchmark.pas) measures it against naive `s := s + x` concatenation, honest caveats included.

```pascal
uses BpStringBuilder;

lvSb := TbpStringBuilder.Create(1024);  // presize when you can
try
  lvSb.Append('SELECT * FROM ').Append(lvTable);
  lvSb.AppendLine(' WHERE id IN (');
  for lvIdx := 0 to lvIds.Count - 1 do
  begin
    if lvIdx > 0 then lvSb.Append(', ');
    lvSb.Append(lvIds[lvIdx]);          // Integer overload, no IntToStr
  end;
  lvSb.AppendFormat(') LIMIT %d', [lvLimit]);
  lvSql := lvSb.ToString;
finally
  lvSb.Free;
end;
```

`Append` is overloaded for `string`, `Char`, `Char` + repeat count, `Integer`, `Int64`, `Double` and `Boolean`, and every overload returns `Self` so calls chain. `AppendLine`, `AppendFormat`, `Insert`, `Clear` and `ToString` behave as in the RTL. `Chars[]` is the default property for random access, and `Length` is writable - shrinking truncates, extending pads with `#0`. Out-of-range indexes and invalid capacities raise `EbpStringBuilder`.

### [BpStrUtils](../src/Core/Units/BpStrUtils.pas)

The string helpers the old RTL never had.

```pascal
uses BpStrUtils;

lvParts := Split('a,b,c', ',');                        // TbpStringArray
lvParts := Split('a::b::c', '::');                     // multi-char delimiter
lvLine := Join(lvParts, ' | ');

if StartsWith(lvUrl, 'https://') and EndsWithText(lvName, '.PAS') then ...
```

`StartsWith` / `EndsWith` are case-sensitive, the `*Text` variants are not.

`FastStringReplace` is the reason this unit exists. `SysUtils.StringReplace` recopies the tail of the string on every hit, so replacing many matches in a large string goes quadratic. This one scans for every match first, then builds the result in a single allocation:

```pascal
lvClean := FastStringReplace(lvHugeText, #13#10, ' ', [rfReplaceAll]);
```

It takes the same `TReplaceFlags` as the RTL version, so it is a drop-in swap where the profiler points.

---

## Hashing and encoding

The crypto and hash units are checked against the published standard vectors (FIPS, RFC), the Windows CryptoAPI and the XE6 RTL, so the numbers actually match other implementations. All pure Pascal, no DLLs.

### [BpSHA256](../src/Core/Classes/BpSHA256.pas)

SHA-256 (FIPS 180-4). One-shot class functions for the everyday case, streaming for the rest.

```pascal
uses BpSHA256;

lvHex := TbpSHA256.HashStrHex('hello');                 // one-shot, hex out
lvHex := TbpSHA256.HashFileHex('setup.exe');            // streams the file
lvB64 := TbpSHA256.DigestToBase64(TbpSHA256.HashStr(lvText));
```

```pascal
lvHasher := TbpSHA256.Create;                           // streaming
try
  while lvStream.Read(lvBuf, SizeOf(lvBuf)) > 0 do
    lvHasher.Update(lvBuf, lvRead);
  lvHasher.Final(lvDigest);
finally
  lvHasher.Free;
end;
```

`Update` is overloaded for a raw buffer, `TBytes` and `AnsiString`. `Final` resets the instance, so you can reuse it. `HashBuffer` / `HashBytes` / `HashStr` / `HashFile` return a `TbpSHA256Digest`; `DigestToHex` and `DigestToBase64` format it.

### [BpMD5](../src/Core/Classes/BpMD5.pas)

MD5 (RFC 1321), the same shape as [BpSHA256](#bpsha256): `HashStrHex`, `HashFileHex`, streaming `Update` / `Final`, `DigestToHex`, `DigestToBase64`.

MD5 is broken for anything security-related. Keep it to legacy checksums, ETags, content fingerprints and old protocols that demand it - for anything new, use SHA-256.

### [BpHMACSHA256](../src/Core/Classes/BpHMACSHA256.pas)

HMAC-SHA256 (RFC 2104), for signing API requests and verifying webhooks.

```pascal
uses BpHMACSHA256;

lvSig := TbpHMACSHA256.ComputeHex(lvSecret, lvPayload);
if not BpConstantTimeEquals(lvSig, lvHeaderSig) then     // from BpPasswordHash
  raise Exception.Create('bad signature');
```

Streaming works as in the hash units - `Create(aKey)`, `Update`, `Final` - which is what you want when the message is a stream rather than a string. `Compute`, `ComputeHex` and `ComputeBase64` cover the one-shot cases, and keys of any length are handled per the RFC.

### [BpPasswordHash](../src/Core/Classes/BpPasswordHash.pas)

Password hashing done properly: PBKDF2-HMAC-SHA256 (RFC 2898 / NIST SP 800-132). Never store a bare SHA-256 of a password; that is a dictionary attack waiting to happen.

```pascal
uses BpPasswordHash;

lvStored := BpHashPassword('correct horse battery staple');
// $pbkdf2-sha256$600000$Bx1n...$9f3c...   put this in your users table

if BpVerifyPassword(lvEntered, lvStored) then
  Login;
```

`BpHashPassword` salts from the Windows CSPRNG, derives with 600,000 iterations (current OWASP guidance) and returns a self-describing record, so the iteration count travels with the hash and you can raise it later without breaking old rows. `BpVerifyPassword` re-derives and compares in constant time; malformed records return `False` rather than raising.

| Function | Use |
|----------|-----|
| `BpHashPassword(aPassword)` / `(aPassword, aIterations)` | store this |
| `BpVerifyPassword(aPassword, aStored)` | check a login |
| `BpPBKDF2SHA256(aPassword, aSalt, aIterations, aKeyLen)` | raw KDF, e.g. deriving an encryption key |
| `BpPBKDF2SHA256Hex(...)` | the same, hex out |
| `BpGenerateSalt(aLen)` | CryptGenRandom bytes; raises rather than falling back |
| `BpConstantTimeEquals(A, B)` | no early exit, so timing leaks nothing |

The raw KDF is checked against the published test vectors and Python's `hashlib`.

### [BpBase64](../src/Core/Units/BpBase64.pas)

Base64 and Base64url (RFC 4648).

```pascal
uses BpBase64;

lvText := Base64Encode(lvBytes);                        // or a buffer, or an AnsiString
lvJwtPart := Base64UrlEncode(lvHeaderJson);             // -_ alphabet, no padding
lvBytes := Base64Decode(lvText);
lvRaw := Base64DecodeStr(lvText);                       // AnsiString flavour
```

Encoding is a single allocation. The decoder eats either alphabet, forgives missing padding and skips whitespace, so MIME-wrapped input just works; genuinely invalid input raises `EbpBase64`.

### [BpHashBobJenkins](../src/Core/Classes/BpHashBobJenkins.pas)

The Bob Jenkins lookup3 hash (public domain), producing the same values as the RTL's `BobJenkinsHash` and as the reference C implementation, which makes it a drop-in for code that expects them. The tests anchor on the published self-test vector, `hashlittle('Four score and seven years ago', 30, 0) = $17770551`, so the interoperability is checked rather than asserted.

```pascal
uses BpHashBobJenkins;

lvBucket := TbpHashBobJenkins.GetHashValue(lvKey) and (lcBucketCount - 1);
```

Fast, well distributed and non-cryptographic - this is a bucket index, not a fingerprint. It is what powers [TbpStrDictionary](#tbpstrdictionary). Streaming (`Reset` / `Update` / `HashAsInteger`) is there for hashing data that arrives in pieces.

---

## Windows and odds and ends

### [TbpCredentials](../src/Core/Classes/BpCredentials.pas)

`BpCredentials.pas` - a secret store on the Windows Credential Manager, keyed by service and username like Python's keyring. No more config files with plaintext passwords.

```pascal
uses BpCredentials;

TbpCredentials.SetPassword('MyApp', 'api', 'secret-token');          // once, at setup

lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');  // raises if missing
if TbpCredentials.TryGetPassword('MyApp', 'api', lvToken) then       // soft version
  lvClient.BearerToken := lvToken;

TbpCredentials.DeletePassword('MyApp', 'api');                       // True if it existed
```

Entries land under `'<service>/<username>'` in the same vault the Control Panel shows, stored as UTF-16LE so .NET code reads them too. `FindUserNames` lists the accounts stored under a service and `DeleteAll` clears them, which covers uninstall and account switching.

The vault is per-user: other accounts cannot read it, but any process running as you can. The `*Protected` variants add a `CryptProtectData` layer keyed by an entropy value your app supplies, so a casual same-user reader gets ciphertext - friction, not a hard boundary:

```pascal
TbpCredentials.SetPasswordProtected('MyApp', 'api', 'secret-token', 'my-app-pepper');
lvToken := TbpCredentials.GetPasswordProtected('MyApp', 'api', 'my-app-pepper');
```

Wrong entropy raises `EbpCredentials`; `TryGetPasswordProtected` returns `False` instead.

### [TbpObjectComparer](../src/Core/Classes/BpObjectComparer.pas)

`BpObjectComparer.pas` - diffs two `TPersistent` objects by RTTI and tells you which published properties changed, walking nested objects and `TCollection` items.

```pascal
uses BpObjectComparer;

lvDiffs := TbpObjectComparer.CompareObjects(lvBefore, lvAfter);
for lvIdx := 0 to High(lvDiffs) do
  Log(Format('%s: %s -> %s', [lvDiffs[lvIdx].NewPropPath,
    VarToStr(lvDiffs[lvIdx].OldValue), VarToStr(lvDiffs[lvIdx].NewValue)]));

Memo1.Text := TbpObjectComparer.CompareObjectsAsString(lvBefore, lvAfter);
```

Each difference is an `IPropDifference` with the property path and the old and new values, so it drops straight into an audit log or a "you changed these settings" dialog. Collection items can be matched by identity rather than position when they implement `IUniqueID` (`UniqueIdIntf.pas`), which is why old and new paths are separate fields - a moved item is reported as changed, not as two unrelated edits.

### [BpKeyFold](../src/Core/Units/BpKeyFold.pas)

Case folding for hash table keys. `AnsiUpperCase` allocates a string on every lookup, which is most of what a case-insensitive dictionary spends its time on; this folds through a table built once from the active code page instead, so a lookup allocates nothing.

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
| `BpFoldInto(aKey, aBuf, aBufChars)` | folded length, or `-1` when it will not fit - for callers running their own hash over the result |
| `BpKeyFoldUsable` | whether the table applies at all |

The subtlety it exists to contain: folding one byte at a time is only equivalent to `AnsiCompareText` on a single byte code page, so on a DBCS code page or a Unicode compiler every function falls back to the RTL call. That matters because a hash and an equality test that disagree would file a key in one bucket and look for it in another - the key would be present and unfindable. Note also that `SysUtils.SameText` is ASCII only on the pre-2009 compilers and does not match a Cyrillic case pair at all; `BpFoldedSame` does.

Used by [TbpStrDictionary](#tbpstrdictionary) and [TbpStringList](#tbpstringlist), and worth having on its own if you keep a hash table of your own.

### [BpVariantUtils](../src/Core/Units/BpVariantUtils.pas)

Strict Variant-to-native conversions. Each function succeeds only when the Variant already holds that type; nothing is parsed, widened or rounded behind your back.

```pascal
uses BpVariantUtils;

if BpTryVarToInt(lvField, lvCount) then ...      // False for '42', True for 42
if BpTryVarToIntArray(lvField, lvIds) then ...
```

`BpTryVarToInt`, `BpTryVarToInt64`, `BpTryVarToStr`, `BpTryVarToBool`, `BpTryVarToFloat`, `BpTryVarToIntArray`. This is the shared rule set behind the dictionaries' typed accessors, so `GetIntDef` and `BpTryVarToInt` agree by construction.

### [BpSysUtils](../src/Core/Units/BpSysUtils.pas)

Small shims for the pre-2009 compilers, compiled only where they are missing. `CharInSet` overloads for `Char`, `WideChar` and `Byte`, so code written against a newer RTL builds on Delphi 7 and 2007 unchanged. The whole unit is inside `{$IF CompilerVersion < 20.0}`, so leaving it in `uses` on a modern compiler costs nothing.

### [StopWatch](../src/Core/Units/StopWatch.pas)

A `QueryPerformanceCounter` stopwatch with the `TStopwatch` shape, for Delphi 7 to 2007 (also `{$IF CompilerVersion < 20.0}`, so the RTL class wins on newer compilers).

```pascal
uses StopWatch;

lvSw := TStopWatch.StartNew;
DoTheWork;
lvSw.Stop;
Log(Format('%.2f ms', [lvSw.ElapsedMilliseconds]));
```

`Reset`, `Start`, `ResetAndStart`, `Stop`, `ElapsedMilliseconds`, `ElapsedTicks`, `IsRunning`, plus `Instance` for a shared one. It returns `IStopWatch`, so there is nothing to free. Used by the benchmark suite.

---

## Single-file bundles

Do not want to add ten units to your project? Take one file from [dist/](../dist/) instead. Each bundle is self-contained - drop it in, `uses` it, done:

| Bundle | Contains |
|--------|----------|
| [BpDictionaries.pas](../dist/BpDictionaries.pas) | both dictionaries, with the hash and Variant helpers baked in |
| [BpHashes.pas](../dist/BpHashes.pas) | SHA-256, MD5, HMAC-SHA256, PBKDF2 password hashing, Base64 |
| [BpHttpClientStandalone.pas](../dist/BpHttpClientStandalone.pas) | HTTP client, streaming downloads, async download task, cancellation token, Base64 |
| [BpJsonStandalone.pas](../dist/BpJsonStandalone.pas) | JSON reader/writer with the string builder baked in |

They are generated from the modular units, SQLite amalgamation style, by [tools/Amalgamate.ps1](../tools/Amalgamate.ps1), from a manifest per bundle in [tools/bundles/](../tools/bundles/). That makes them build artifacts: do not patch them by hand - fix the real unit and regenerate.

```
pwsh -NoProfile -File tools\Amalgamate.ps1
```

One catch: two bundles that embed the same helper declare its identifiers twice, and which one you get then depends on `uses` order - `EbpBase64` raised inside one is not the `EbpBase64` the other one catches. Today that affects exactly one pair, `BpHashes` and `BpHttpClientStandalone`, since both embed `BpBase64`; use one or the other. The same clash appears if you mix a bundle with the modular units it already contains.

[tools/VerifyBundles.cmd](../tools/VerifyBundles.cmd) compiles each bundle on its own and runs a smoke test against known-answer vectors, so what ships is known to build and to be correct.
