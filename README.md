# DelphiBoostPack

A small, dependency-free utility library for old Delphi versions. Main development happens on Delphi 2007, the goal is to keep everything working from Delphi 7 up to 11.3. If you maintain a legacy codebase and miss things like dictionaries, a fast StringBuilder or a usable HTTP client, this is for you.

No external DLLs, no design-time packages, no runtime dependencies beyond the RTL and WinInet (for the HTTP client). Everything is covered by DUnit tests.

## What's inside

### Collections
- **TbpStrDictionary** / **TbpIntDictionary** (`BpStrDictionary.pas`, `BpIntDictionary.pas`) - hash dictionaries with string and Int64 keys for Delphi versions without generics. The engine follows the XE6 `TDictionary` design: open addressing, linear probing, power-of-two capacity, backward-shift deletion. Values are Variants with typed accessors (`GetInt`, `TryGetStr`, `GetFloatDef` and friends) that validate instead of silently converting.
- **TbpIntList** (`BpIntList.pas`) - a `TStringList`-style list of integers with sorting, delimited text and the usual index operations.

### Strings
- **TbpStringBuilder** (`BpStringBuilder.pas`) - StringBuilder modeled on the XE6 API but considerably faster, since it appends through a cached raw pointer instead of the `Length` property setter.
- **BpStrUtils.pas** - `Split`, `Join`, `StartsWith`/`EndsWith` and `FastStringReplace`, which collects match positions first and builds the result in a single allocation instead of copying the tail on every match like `SysUtils.StringReplace` does.

### Hashing and encoding
- **BpSHA256.pas** - SHA-256 per FIPS 180-4 in pure Pascal. Streaming interface plus one-shot class functions for buffers, strings and files, with hex or Base64 output. Verified against the FIPS known-answer vectors and cross-checked against Windows CryptoAPI.
- **BpMD5.pas** - MD5 per RFC 1321, same interface as BpSHA256. Broken for signatures, still handy for legacy checksums and ETags.
- **BpHMACSHA256.pas** - HMAC-SHA256 per RFC 2104, for API signatures and webhook verification.
- **BpHashBobJenkins.pas** - Bob Jenkins lookup3 hash, byte-for-byte identical with the XE+ RTL `BobJenkinsHash`, used by the string dictionary.
- **BpBase64.pas** - Base64 and Base64url per RFC 4648. Single-allocation encode, decoder accepts both alphabets, tolerates missing padding and skips whitespace.

### HTTP
- **TbpHttpClient** (`BpHttpClient.pas`) - HTTP/HTTPS client over WinInet, so TLS comes from Windows (Schannel) and no OpenSSL DLLs are needed. `Get`/`Post`/`Put`/`Delete` return a response record, with persistent headers, bearer token and basic auth helpers, and `PostJson` for the typical API call.

### Other
- **TbpObjectComparer** (`BpObjectComparer.pas`) - compares two objects via RTTI and reports which published properties differ, including collections.
- **BpVariantUtils.pas** - strict Variant-to-native conversions. Succeeds only when the Variant already holds the requested kind of data, no parsing or implicit widening.
- **BpSysUtils.pas** - small compatibility shims like `CharInSet` for pre-2009 compilers.
- **StopWatch.pas** - high-precision stopwatch (`QueryPerformanceCounter`) for Delphi 7-2007, used by the benchmark suite.

## Single-file bundles

If you just want to drop one `.pas` file into a project, take a bundle from `dist\`:

- **BpDictionaries.pas** - both dictionaries with the hash and Variant helpers embedded
- **BpHashes.pas** - SHA-256, MD5, HMAC-SHA256 and Base64
- **BpHttpClientStandalone.pas** - the HTTP client with Base64 embedded

The bundles are generated from the modular units, SQLite amalgamation style, by `tools\Amalgamate.ps1`. Do not edit them directly; fix the source unit and regenerate:

```
powershell -ExecutionPolicy Bypass -File tools\Amalgamate.ps1
```

Use at most one bundle per project. Two bundles embedding the same helper unit would declare duplicate identifiers. `tools\VerifyBundles.cmd` compiles each bundle standalone and runs a short smoke test against known-answer vectors.

## Building and testing

The `.cmd` scripts at the repository root build with Delphi 2007 via MSBuild:

```
Build_Main_D2007.cmd Release
Build_Tests_D2007.cmd Debug
RunTests_D2007.cmd
```

Tests are DUnit; the suite also contains benchmarks that compare the performance-oriented classes against their RTL counterparts.

## Coding style

To keep the codebase consistent:

- **Local variables** start with `lv`, e.g. `lvIndex`, `lvName`.
- **Global variables** start with `gv`, e.g. `gvUserCount`.
- **Local constants** start with `lc`, **global constants** with `gc`.
- **Classes** use the `Tbp` prefix (from Boost Pack), e.g. `TbpStringBuilder`.
- **One class per unit** where practical; the unit is named after the class, e.g. `TbpIntList` lives in `BpIntList.pas`.
- **Comments** are one-line `//` comments; `{ }` braces are reserved for compiler directives.

## Contribution

Contributions are welcome. Fork the repository, make your changes and submit a pull request. Bug fixes, new utilities and documentation improvements are all appreciated.

## Official Delphi Downloads

Official ISOs and web installers for a wide range of Delphi and RAD Studio versions are collected here:

- [Delphi Official Downloads](https://github.com/dimitar-grigorov/DelphiBoostPack/blob/main/Delphi%20Official%20Downloads.md)
