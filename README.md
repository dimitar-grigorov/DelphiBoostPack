# DelphiBoostPack

*The modern RTL Delphi 2007 never shipped, as drop-in units instead of a framework.*

Hash dictionaries, a fast StringBuilder, SHA-256 / MD5 / HMAC, Base64, a WinInet HTTP client with async streaming downloads, background tasks with cooperative cancellation, and a JSON parser, all in pure Pascal. No DLLs, no packages to register. Drop in a unit and go.

It targets Delphi 2007 first and stays clean from Delphi 7 all the way to 11.3, because rewriting a 300-unit legacy app just to get a `TDictionary` is not a plan. If you are stuck on an old compiler and keep reaching for things it does not have, help yourself to whatever is useful here.

Everything has DUnit tests, and the crypto and hash units are checked against the published standard vectors (FIPS, RFC) and the Windows CryptoAPI, so the numbers actually match.

> **Featured - a modern HTTP client for Delphi 2007.** `TbpHttpClient` brings the ergonomics of C# `HttpClient` and JS `fetch` to a 2007 compiler: one-liner `GET`s, JSON `POST`s, bearer and basic auth, and async streaming downloads with progress and cooperative cancellation. All over WinInet, so no OpenSSL DLLs ride along with your exe. [Jump to the examples ↓](#using-the-http-client)

## What's inside

### Collections
- **`TbpStrDictionary`** / **`TbpIntDictionary`** - real hash maps with string and Int64 keys, for compilers with no generics, with a familiar `TDictionary`-style API. Open addressing, linear probing, power-of-two capacity, backward-shift deletion. Values are Variants, but the typed accessors (`GetInt`, `TryGetStr`, `GetFloatDef` and the rest) check the type instead of quietly coercing it.
- **`TbpIntList`** - a list of integers that behaves like `TStringList`: sorting, delimited text, the usual indexing.

### Strings
- **`TbpStringBuilder`** - the XE6 `TStringBuilder` API, minus the slow part. The RTL routes every append through the `Length` setter; this one writes through a cached pointer, so it is quite a bit faster.
- **`BpStrUtils`** - `Split`, `Join`, `StartsWith` / `EndsWith`, and a `FastStringReplace` that finds every match first and builds the result in one allocation. `SysUtils.StringReplace` recopies the tail on each hit and goes quadratic; this one does not.

### Hashing and encoding
- **`BpSHA256`** - SHA-256 (FIPS 180-4), pure Pascal. Stream it in chunks or call a one-shot class function for a buffer, string or file, hex or Base64 out. Checked against the FIPS vectors and CryptoAPI.
- **`BpMD5`** - MD5 (RFC 1321), same shape as the SHA unit. It is broken for anything security-related, so keep it to legacy checksums, ETags and content fingerprints.
- **`BpHMACSHA256`** - HMAC-SHA256 (RFC 2104) for API request signing and webhook verification.
- **`BpPasswordHash`** - password hashing done right: PBKDF2-HMAC-SHA256 (RFC 2898 / NIST SP 800-132). `BpHashPassword` salts from the Windows CSPRNG, derives with 600,000 iterations (current OWASP guidance) and returns a self-describing record (`$pbkdf2-sha256$600000$<salt>$<hash>`); `BpVerifyPassword` re-derives and compares in constant time, and malformed records just return `False`. The raw `BpPBKDF2SHA256` is exposed too, checked against the published test vectors and Python's `hashlib`.
- **`BpHashBobJenkins`** - the Bob Jenkins lookup3 hash (a public-domain algorithm), producing values that interoperate with the RTL's `BobJenkinsHash`. It is what powers the string dictionary.
- **`BpBase64`** - Base64 and Base64url (RFC 4648). One allocation to encode; the decoder eats either alphabet, forgives missing padding and skips whitespace, so MIME-wrapped input just works.

### HTTP, JSON and tasks
- **`TbpHttpClient`** - HTTP and HTTPS over WinInet. TLS comes from Schannel, which means no OpenSSL DLLs shipping alongside your exe. `Get` / `Post` / `Put` / `Delete` hand back a response record; bearer tokens, basic auth and persistent headers are one call each, and `PostJson` sets the content type for you. `Download` / `DownloadToFile` stream a body of any size to a `TStream` or a file in constant memory, with `Int64` progress callbacks and cooperative cancellation; `DownloadToFile` deletes the partial file on any failure or cancel, so an error page never masquerades as the payload.
- **`TbpHttpDownloadTask`** - the non-blocking wrapper, shaped like a C# `Task` or a JS promise: `Start` returns immediately, the download runs on its own worker thread (no `ProcessMessages` anywhere), progress and completion arrive as events on the main thread, and `Cancel` aborts promptly even while the worker sits in a blocked read. The destructor cancels, joins and cleans up, whatever state the task died in.
- **`TbpTask` / `BpRunAsync`** - the download task generalized (`BpTasks.pas`, a self-contained unit with no dependencies): run any method on an owned worker thread, get completion (and failure, with the exception's message and class name) as events on the creating thread, cancel cooperatively through a lightweight `TbpTaskToken`, and the destructor cancels, joins and cleans up in any state. One thread per task, no pool - a scoped AsyncCalls replacement for the everyday case.
- **`TbpCancellationToken`** - the C# `CancellationToken` / JS `AbortController` idea for Delphi 7: one side calls `Cancel`, the working side polls or registers a cleanup that runs inside the cancel. Thread-safe, one-shot, transport-agnostic.
- **`TbpJsonValue`** - a JSON reader and writer (RFC 8259). One class is the whole tree, tagged by `Kind`. The parser is strict on purpose: leading zeros, raw control characters, trailing commas and junk after the value all fail, and the error tells you the line and column. Pull values out with the same typed accessors as the dictionaries, reach deep with `FindPath('data.items[0].name')`, and write it back with `ToJson` or `ToJsonPretty`. No RTTI, no data binding, just the tree.
- **`BpDateUtils`** - the ISO 8601 / RFC 3339 date handling the RTL skipped until XE6 (D2007 has no `ISO8601ToDate` at all), the natural companion to the JSON unit since every JSON API dates in ISO 8601. Parses date-only values, `T`-or-space timestamps, fractional seconds and every zone form (`Z`, `+hh:mm`, `+hhmm`, `+hh`) into a UTC `TDateTime`, and strictly: malformed input is rejected, not guessed at. Formats back to a `Z` string or local wall-clock with a numeric offset, and converts Unix epoch seconds and milliseconds both ways in `Int64`, so dates before 1970 and past 2038 round-trip cleanly.

### Odds and ends
- **`TbpCredentials`** - a Python-keyring-style secret store on the Windows Credential Manager. `SetPassword` / `GetPassword` / `DeletePassword` keyed by (service, username); entries land in the same vault the Control Panel shows, stored as UTF-16LE so .NET code reads them too. The `*Protected` variants add a DPAPI layer with app-supplied entropy on top, and `FindUserNames` / `DeleteAll` enumerate a service. No config files with plaintext passwords.
- **`TbpObjectComparer`** - diffs two objects by RTTI and tells you which published properties changed, collections included.
- **`BpVariantUtils`** - strict Variant-to-native conversions. It only succeeds when the Variant already holds that type; nothing is parsed or widened behind your back.
- **`BpSysUtils`** - small shims like `CharInSet` for the pre-2009 compilers.
- **`StopWatch`** - a `QueryPerformanceCounter` stopwatch for Delphi 7-2007, used by the benchmarks.

## Using the HTTP client

One-liner fetch and everyday API calls:

```pascal
lvBody := TbpHttpClient.FetchUrl('https://api.example.com/v1/status');

lvClient := TbpHttpClient.Create;
try
  lvClient.BearerToken := 'secret';           // or SetBasicAuth('user', 'pass')
  lvClient.AddHeader('X-Api-Version', '2');   // sent with every request
  lvResp := lvClient.PostJson('https://api.example.com/v1/items', '{"name":"first"}');
  if BpHttpResponseIsSuccess(lvResp) then
    lvText := BpHttpResponseBodyAsUtf8(lvResp)
  else
    ShowMessage(BpClassifyHttpError(0, lvResp.StatusCode));
finally
  lvClient.Free;
end;
```

Downloading with progress and cancel. The callback gets `Int64` counters (`aTotal` is `-1` when the server sent no `Content-Length`) and can abort inline; a `TbpCancellationToken` aborts from outside, promptly, even while a read blocks:

```pascal
procedure TMainForm.HandleProgress(aSender: TObject; const aReceived, aTotal: Int64;
  var aCancel: Boolean);
begin
  ProgressBar1.Position := BpHttpProgressPercent(aReceived, aTotal);  // -1 = unknown
end;

// blocking, so run it on a worker thread; the file is deleted on error or cancel
lvClient.DownloadToFile('https://host/big.zip', 'C:\temp\big.zip',
  HandleProgress, FToken);
```

Async without freezing the UI: `BpDownloadAsync` returns a started `TbpHttpDownloadTask` (a hot task, C# style). No `ProcessMessages` anywhere; events arrive through the message queue on the thread that created the task:

```pascal
FTask := BpDownloadAsync('https://host/big.zip', 'C:\temp\big.zip',
  HandleProgress, HandleComplete);    // returns immediately
// in HandleComplete check FTask.State: dtsSucceeded / dtsFailed / dtsCancelled
// later, from the Stop button:
FTask.Cancel;                         // partial file cleaned up
```

Need auth or timeouts on an async download? Create `TbpHttpDownloadTask` yourself, configure its `Client` (the full `TbpHttpClient` surface), set `Url` + `DestFileName`/`DestStream`, wire the events, `Start`. Console apps pass `Create(False)` / `BpDownloadAsync(..., False)` and get events on the worker thread. Resume is one header away: send `'Range: bytes=123456-'` and append on a 206.

## Running any work in the background

The same task shape works for arbitrary work, not just downloads. `BpRunAsync` (in `BpTasks.pas`) runs a method on a worker thread and delivers `OnComplete` back on the thread that made the call; the work polls the token to honour a cancel:

```pascal
procedure TMainForm.DoCrunch(aSender: TObject; aToken: TbpTaskToken);
begin
  while HasWorkLeft and not aToken.IsCancellationRequested do
    CrunchNextChunk;   // worker thread; no UI calls here
end;

FTask := BpRunAsync(DoCrunch, HandleDone);  // returns immediately
// in HandleDone check FTask.State: tskSucceeded / tskFailed / tskCancelled;
// on failure ErrorMessage and ErrorClass carry the exception. FTask.Cancel
// any time; FTask.Free cancels, joins and cleans up in any state.
```

## Keeping secrets out of config files

`TbpCredentials` stores secrets in the Windows Credential Manager, keyed by service and username like Python's keyring (the entry lands under `'<service>/<username>'`). Store the API token once, then feed it to the HTTP client at startup:

```pascal
TbpCredentials.SetPassword('MyApp', 'api', 'secret-token');   // once, e.g. from a setup dialog

lvClient.BearerToken := TbpCredentials.GetPassword('MyApp', 'api');  // raises EbpCredentials if missing
// or the soft version:
if TbpCredentials.TryGetPassword('MyApp', 'api', lvToken) then
  lvClient.BearerToken := lvToken;

TbpCredentials.DeletePassword('MyApp', 'api');                // True if it existed
```

The vault is per-user: other accounts cannot read it, but any process running as you can. The `*Protected` variants add a `CryptProtectData` layer keyed by an entropy value your app supplies, so a casual same-user reader gets ciphertext (friction, not a hard boundary):

```pascal
TbpCredentials.SetPasswordProtected('MyApp', 'api', 'secret-token', 'my-app-pepper');
lvToken := TbpCredentials.GetPasswordProtected('MyApp', 'api', 'my-app-pepper');
```

## Grab a single file

Do not want to add ten units to your project? Take one file from `dist\` instead. Each bundle is self-contained:

- **`BpDictionaries.pas`** - both dictionaries, with the hash and Variant helpers baked in
- **`BpHashes.pas`** - SHA-256, MD5, HMAC-SHA256, PBKDF2 password hashing and Base64
- **`BpHttpClientStandalone.pas`** - the HTTP client, streaming downloads, the async download task and cancellation token, with Base64 baked in
- **`BpJsonStandalone.pas`** - the JSON reader/writer with the string builder baked in

These are generated from the modular units, SQLite amalgamation style, by `tools\Amalgamate.ps1`. They are build artifacts, so do not patch them by hand; fix the real unit and regenerate:

```
powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1
```

One catch: use at most one bundle per project. Two bundles that embed the same helper would collide on duplicate identifiers. `tools\VerifyBundles.cmd` compiles each bundle on its own and runs a smoke test against known-answer vectors, so you can trust what ships.

## Building and testing

The `.cmd` scripts at the repo root drive Delphi 2007 through MSBuild:

```
Build_Main_D2007.cmd Release
Build_Tests_D2007.cmd Debug
RunTests_D2007.cmd
```

`RunTests_D2007.cmd` builds the DUnit runner and runs it. The suite splits into unit, integration and benchmark kinds; pass `/nointeg` for an offline run or `/bench` to add the benchmarks. See [tests/README.md](tests/README.md) for the full breakdown.

## Coding style

If you send a patch, match the house style:

- Locals start with `lv`, globals with `gv`, local constants with `lc`, global constants with `gc`.
- Parameters start with a lowercase `a`, e.g. `aValue`, `aKeyLen`.
- Classes get the `Tbp` prefix (Boost Pack), e.g. `TbpStringBuilder`.
- One class per unit where it makes sense, and the unit is named after it (`TbpIntList` lives in `BpIntList.pas`).
- Comments are `//` lines. Braces `{ }` are for compiler directives only.

## Contributing

Fork it, fix or add something, open a pull request. Bugs, new units and better docs are all fair game.

## Getting Delphi

Official ISOs and web installers for the older Delphi and RAD Studio releases are collected here:

- [Delphi Official Downloads](https://github.com/dimitar-grigorov/DelphiBoostPack/blob/main/Delphi%20Official%20Downloads.md)
