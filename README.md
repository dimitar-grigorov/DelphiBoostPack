# DelphiBoostPack

The parts of a modern RTL that Delphi 2007 never got: hash dictionaries, a fast StringBuilder, SHA-256 / MD5 / HMAC, Base64, a WinInet HTTP client and a JSON parser. Pure Pascal, no DLLs, no packages to register. Drop in a unit and go.

It targets Delphi 2007 first and stays clean from Delphi 7 all the way to 11.3, because rewriting a 300-unit legacy app just to get a `TDictionary` is not a plan. If you are stuck on an old compiler and keep reaching for things it does not have, help yourself to whatever is useful here.

Everything has DUnit tests, and the crypto and hash units are cross-checked against the Windows CryptoAPI and the XE6 RTL so the numbers actually match.

## What's inside

### Collections
- **TbpStrDictionary** / **TbpIntDictionary** - real hash maps with string and Int64 keys, for compilers with no generics. Same engine as XE6's `TDictionary`: open addressing, linear probing, power-of-two capacity, backward-shift deletion. Values are Variants, but the typed accessors (`GetInt`, `TryGetStr`, `GetFloatDef` and the rest) check the type instead of quietly coercing it.
- **TbpIntList** - a list of integers that behaves like `TStringList`: sorting, delimited text, the usual indexing.

### Strings
- **TbpStringBuilder** - the XE6 `TStringBuilder` API, minus the slow part. The RTL routes every append through the `Length` setter; this one writes through a cached pointer, so it is quite a bit faster.
- **BpStrUtils** - `Split`, `Join`, `StartsWith` / `EndsWith`, and a `FastStringReplace` that finds every match first and builds the result in one allocation. `SysUtils.StringReplace` recopies the tail on each hit and goes quadratic; this one does not.

### Hashing and encoding
- **BpSHA256** - SHA-256 (FIPS 180-4), pure Pascal. Stream it in chunks or call a one-shot class function for a buffer, string or file, hex or Base64 out. Checked against the FIPS vectors and CryptoAPI.
- **BpMD5** - MD5 (RFC 1321), same shape as the SHA unit. It is broken for anything security-related, so keep it to legacy checksums, ETags and content fingerprints.
- **BpHMACSHA256** - HMAC-SHA256 (RFC 2104) for API request signing and webhook verification.
- **BpHashBobJenkins** - the Bob Jenkins lookup3 hash, byte-for-byte identical to the XE+ `BobJenkinsHash`. It is what powers the string dictionary.
- **BpBase64** - Base64 and Base64url (RFC 4648). One allocation to encode; the decoder eats either alphabet, forgives missing padding and skips whitespace, so MIME-wrapped input just works.

### HTTP and JSON
- **TbpHttpClient** - HTTP and HTTPS over WinInet. TLS comes from Schannel, which means no OpenSSL DLLs shipping alongside your exe. `Get` / `Post` / `Put` / `Delete` hand back a response record; bearer tokens, basic auth and persistent headers are one call each, and `PostJson` sets the content type for you.
- **TbpJsonValue** - a JSON reader and writer (RFC 8259). One class is the whole tree, tagged by `Kind`. The parser is strict on purpose: leading zeros, raw control characters, trailing commas and junk after the value all fail, and the error tells you the line and column. Pull values out with the same typed accessors as the dictionaries, reach deep with `FindPath('data.items[0].name')`, and write it back with `ToJson` or `ToJsonPretty`. No RTTI, no data binding, just the tree.

### Odds and ends
- **TbpObjectComparer** - diffs two objects by RTTI and tells you which published properties changed, collections included.
- **BpVariantUtils** - strict Variant-to-native conversions. It only succeeds when the Variant already holds that type; nothing is parsed or widened behind your back.
- **BpSysUtils** - small shims like `CharInSet` for the pre-2009 compilers.
- **StopWatch** - a `QueryPerformanceCounter` stopwatch for Delphi 7-2007, used by the benchmarks.

## Grab a single file

Do not want to add ten units to your project? Take one file from `dist\` instead. Each bundle is self-contained:

- **BpDictionaries.pas** - both dictionaries, with the hash and Variant helpers baked in
- **BpHashes.pas** - SHA-256, MD5, HMAC-SHA256 and Base64
- **BpHttpClientStandalone.pas** - the HTTP client with Base64 baked in
- **BpJsonStandalone.pas** - the JSON reader/writer with the string builder baked in

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

The test project is DUnit and also carries benchmarks that pit the performance units against their RTL equivalents, so the speed claims above are not just talk.

## Coding style

If you send a patch, match the house style:

- Locals start with `lv`, globals with `gv`, local constants with `lc`, global constants with `gc`.
- Classes get the `Tbp` prefix (Boost Pack), e.g. `TbpStringBuilder`.
- One class per unit where it makes sense, and the unit is named after it (`TbpIntList` lives in `BpIntList.pas`).
- Comments are `//` lines. Braces `{ }` are for compiler directives only.

## Contributing

Fork it, fix or add something, open a pull request. Bugs, new units and better docs are all fair game.

## Getting Delphi

Official ISOs and web installers for the older Delphi and RAD Studio releases are collected here:

- [Delphi Official Downloads](https://github.com/dimitar-grigorov/DelphiBoostPack/blob/main/Delphi%20Official%20Downloads.md)
