# DelphiBoostPack

**The bits of the modern RTL that Delphi 2007 never got - as drop-in units, not a framework.**

HTTP, JSON, hash dictionaries, SHA-256, background tasks. Pure Pascal source, no third-party DLLs, no packages to register. Copy in a unit and use it.

![Delphi](https://img.shields.io/badge/Delphi-7%20to%2011.3-E62431)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![Tests](https://img.shields.io/badge/tests-DUnit-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

## Install

Nothing to install, two ways in:

- **Modular.** Put `src\Core\Classes`, `src\Core\Units` and `src\Core\Interfaces` on your library path, or copy the units you use. A few want a companion: the dictionaries want `BpVariantUtils` and `BpKeyFold`, `TbpStringList` wants `BpKeyFold`, `BpJson` wants `BpStringBuilder`, `BpHttpClient` and the hashes want `BpBase64`, `BpPathUtils` wants `BpKeyFold`, and everything that touches `TBytes` wants `BpCompat`.
- **One file.** Take a bundle from [dist/](dist/) instead. Each is self-contained, so do not also use the modular units it embeds.

An HTTPS call and a JSON parse, on a 2007 compiler, with nothing else installed:

```pascal
uses BpHttpClient, BpJson;

lvJson := TbpJsonValue.Parse(TbpHttpClient.FetchUrl('https://api.github.com/repos/dimitar-grigorov/DelphiBoostPack'));
try
  ShowMessage(Format('%s, %d stars', [lvJson.GetStr('full_name'),
    lvJson.GetIntDef('stargazers_count', 0)]));
finally
  lvJson.Free;
end;
```

A big download that does not freeze the UI, in one line:

```pascal
FTask := BpDownloadAsync('https://host/big.zip', 'C:\temp\big.zip', HandleProgress, HandleDone);
```

Worker thread, progress and completion events on the main thread, no `ProcessMessages`, `FTask.Cancel` whenever you like. [More examples ->](docs/FEATURES.md)

## Why

Rewriting a 300-unit legacy app just to get a `TDictionary` is not a plan. This is the missing RTL as loose units you can lift one at a time: it targets Delphi 2007 first and is written to compile unchanged from Delphi 7 to 11.3, so it goes wherever your codebase happens to live. The scripts here build and test on Delphi 2007 and compile every unit on Delphi 7, so the low end of that range is checked rather than claimed.

Nearly every unit has a DUnit test unit behind it, and the crypto and hash units are checked against the published standard vectors (FIPS, RFC) and the Windows CryptoAPI, so the numbers match other implementations.

## What's inside

Full descriptions and examples in the [feature guide](docs/FEATURES.md).

**Network and async**

| Unit | What you get |
|------|--------------|
| [TbpHttpClient](docs/FEATURES.md#tbphttpclient) | `Get` / `Post` / `PostJson` / `Put` / `Delete`, all cancellable, bearer and basic auth, streaming downloads, keep-alive. WinInet, so TLS comes from Windows and no OpenSSL DLLs ride along |
| [TbpHttpDownloadTask](docs/FEATURES.md#tbphttpdownloadtask) | non-blocking downloads with progress, prompt cancel and partial-file cleanup |
| [TbpTask](docs/FEATURES.md#tbptask) | run any method on a worker thread, completion and failure as events on the main thread, any thread may create or free it |
| [TbpCancellationToken](docs/FEATURES.md#tbpcancellationtoken) | the C# `CancellationToken` idea, for Delphi 7 |

**Data**

| Unit | What you get |
|------|--------------|
| [TbpJsonValue](docs/FEATURES.md#tbpjsonvalue) | strict RFC 8259 reader and writer, `FindPath('data.items[0].name')`, pretty printing |
| [BpDateUtils](docs/FEATURES.md#bpdateutils) | ISO 8601 / RFC 3339 and Unix time both ways, in `Int64` - what D2007 has no `ISO8601ToDate` for |
| [TbpStrDictionary](docs/FEATURES.md#tbpstrdictionary) / [TbpIntDictionary](docs/FEATURES.md#tbpintdictionary) | real hash maps for compilers with no generics, `TDictionary`-style API, typed accessors that refuse to coerce |
| [TbpStringList](docs/FEATURES.md#tbpstringlist) | the `TStringList` API on a `TStrings` with O(1) `IndexOf` and `IndexOfName`, a stable `Sort` and one ordinal relation behind hash, equality and order |
| [TbpIntList](docs/FEATURES.md#tbpintlist) | a list of integers that behaves like `TStringList`, with O(1) `IndexOf` |
| [TbpInt64List](docs/FEATURES.md#tbpint64list) | the same list for `Int64` - keys, file sizes, millisecond timestamps |

**Strings**

| Unit | What you get |
|------|--------------|
| [TbpStringBuilder](docs/FEATURES.md#tbpstringbuilder) | the XE6 `TStringBuilder` API on compilers that never got it; appends through a cached buffer pointer instead of resizing the string every time |
| [BpStrUtils](docs/FEATURES.md#bpstrutils) | `Split`, `Join`, `StartsWith` / `EndsWith`, and a `FastStringReplace` that stays linear where `StringReplace` goes quadratic |

**Hashing and encoding**

| Unit | What you get |
|------|--------------|
| [BpSHA256](docs/FEATURES.md#bpsha256) / [BpMD5](docs/FEATURES.md#bpmd5) | one-shot or streaming digests for buffers, strings and files; hex or Base64 out |
| [BpHMACSHA256](docs/FEATURES.md#bphmacsha256) | request signing and webhook verification (RFC 2104) |
| [BpPasswordHash](docs/FEATURES.md#bppasswordhash) | PBKDF2-HMAC-SHA256 with CSPRNG salt, 600k iterations and a self-describing record |
| [BpBase64](docs/FEATURES.md#bpbase64) | Base64 and Base64url; the decoder forgives padding and whitespace, and a UTF-8 set for text |
| [BpEncoding](docs/FEATURES.md#bpencoding) | strict UTF-8 decoding that fails instead of handing back U+FFFD, with a documented fallback |
| [BpHashBobJenkins](docs/FEATURES.md#bphashbobjenkins) | lookup3, interoperable with the RTL's `BobJenkinsHash` |

**Windows and odds and ends**

| Unit | What you get |
|------|--------------|
| [TbpCredentials](docs/FEATURES.md#tbpcredentials) | secrets in the Windows Credential Manager, keyring style, instead of plaintext in an INI |
| [TbpObjectComparer](docs/FEATURES.md#tbpobjectcomparer) | diff two objects by RTTI and get the changed properties, collections included |
| [BpKeyFold](docs/FEATURES.md#bpkeyfold) | case folding for hash keys with no allocation per lookup, and correct outside ASCII |
| [BpPathUtils](docs/FEATURES.md#bppathutils) | one path relation instead of one per call site, and the Windows shapes hand-rolled helpers get wrong |
| [BpVariantUtils](docs/FEATURES.md#bpvariantutils) / [BpSysUtils](docs/FEATURES.md#bpsysutils) / [StopWatch](docs/FEATURES.md#stopwatch) | strict Variant conversions, old-compiler shims, a `QueryPerformanceCounter` stopwatch |

## One file instead of ten

[dist/](dist/) holds amalgamated builds, SQLite style: [BpDictionaries.pas](dist/BpDictionaries.pas), [BpHashes.pas](dist/BpHashes.pas), [BpHttpClientStandalone.pas](dist/BpHttpClientStandalone.pas), [BpJsonStandalone.pas](dist/BpJsonStandalone.pas). Each is self-contained - take the one you need and nothing else. They can be combined: no two of them export the same helper. Treat them as build artifacts: fix the real unit and regenerate. [Details ->](docs/FEATURES.md#single-file-bundles)

## Building and testing

The `.cmd` scripts at the repo root are thin wrappers over [tools/Build_Delphi.cmd](tools/Build_Delphi.cmd), which drives MSBuild for a `.dproj`, `dcc32` for a `.dpr`, and either compiler:

```
Build_Main_D2007.cmd Release
Build_Main_D7.cmd             compile every unit with Delphi 7
RunTests_D2007.cmd            unit + integration
RunTests_D2007.cmd /nointeg   offline run
RunTests_D2007.cmd /bench     add the benchmarks
tools\VerifyBundles.cmd /d7   compile the dist bundles standalone on Delphi 7
```

`RunTests_D2007.cmd` builds the DUnit runner and runs it. See [tests/README.md](tests/README.md) for the breakdown, and note that the tests are also the most complete set of examples in the repo. The Delphi 7 claim is a compile gate, not a test run: DUnit is not part of that install, so `Build_Main_D7.cmd` compiles every unit through `src\DelphiBoostPack.dpr`, which uses them all.

Add `/ci` to any of them to skip the pause on failure. The compilers are found from `BDS` and `DELPHI7`, then the registry, then the default install path.

## Contributing

Fork it, fix or add something, open a pull request. Bugs, new units and better docs are all fair game.

House style: locals `lv`, globals `gv`, constants `lc` / `gc`, parameters `a` (`aValue`); classes get the `Tbp` prefix, one class per unit where it makes sense and the unit named after it; comments are `//` lines.

## Getting Delphi

Official ISOs and web installers for the older Delphi and RAD Studio releases are collected here:

- [Delphi Official Downloads](https://github.com/dimitar-grigorov/DelphiBoostPack/blob/main/Delphi%20Official%20Downloads.md)

## License

GPL-3.0 - see [LICENSE](LICENSE).
