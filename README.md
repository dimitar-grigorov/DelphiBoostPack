# DelphiBoostPack

**The modern RTL Delphi 2007 never shipped - as drop-in units, not a framework.**

HTTP, JSON, hash dictionaries, SHA-256, background tasks. Pure Pascal, no DLLs, no packages to register. Drop in a unit and go.

![Delphi](https://img.shields.io/badge/Delphi-7%20to%2011.3-E62431)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![Tests](https://img.shields.io/badge/tests-DUnit-blue)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

## Quick start

Copy the unit you want out of [src/Core/](src/Core/) into your project - or clone the repo and add `src\Core\Classes` and `src\Core\Units` to your library path. That is the whole install.

An HTTPS call and a JSON parse, on a 2007 compiler, with nothing installed:

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

Rewriting a 300-unit legacy app just to get a `TDictionary` is not a plan. This is the missing RTL as loose units you can lift one at a time: it targets Delphi 2007 first and stays clean from Delphi 7 to 11.3, so the same code compiles wherever your codebase happens to live.

Everything has DUnit tests, and the crypto and hash units are checked against the published standard vectors (FIPS, RFC) and the Windows CryptoAPI, so the numbers match other implementations.

## What's inside

Full descriptions and examples in the [feature guide](docs/FEATURES.md).

**Network and async**

| Unit | What you get |
|------|--------------|
| [TbpHttpClient](docs/FEATURES.md#tbphttpclient) | `Get` / `Post` / `PostJson` / `Put` / `Delete`, bearer and basic auth, streaming downloads. WinInet, so TLS comes from Windows and no OpenSSL DLLs ride along |
| [TbpHttpDownloadTask](docs/FEATURES.md#tbphttpdownloadtask) | non-blocking downloads with progress, prompt cancel and partial-file cleanup |
| [TbpTask](docs/FEATURES.md#tbptask) | run any method on a worker thread, completion and failure as events on the calling thread |
| [TbpCancellationToken](docs/FEATURES.md#tbpcancellationtoken) | the C# `CancellationToken` idea, for Delphi 7 |

**Data**

| Unit | What you get |
|------|--------------|
| [TbpJsonValue](docs/FEATURES.md#tbpjsonvalue) | strict RFC 8259 reader and writer, `FindPath('data.items[0].name')`, pretty printing |
| [BpDateUtils](docs/FEATURES.md#bpdateutils) | ISO 8601 / RFC 3339 and Unix time both ways, in `Int64` - what D2007 has no `ISO8601ToDate` for |
| [TbpStrDictionary](docs/FEATURES.md#tbpstrdictionary) / [TbpIntDictionary](docs/FEATURES.md#tbpintdictionary) | real hash maps for compilers with no generics, `TDictionary`-style API, typed accessors that refuse to coerce |
| [TbpIntList](docs/FEATURES.md#tbpintlist) | a list of integers that behaves like `TStringList` |

**Strings**

| Unit | What you get |
|------|--------------|
| [TbpStringBuilder](docs/FEATURES.md#tbpstringbuilder) | the XE6 `TStringBuilder` API, minus the slow `Length` setter it appends through |
| [BpStrUtils](docs/FEATURES.md#bpstrutils) | `Split`, `Join`, `StartsWith` / `EndsWith`, and a `FastStringReplace` that stays linear where `StringReplace` goes quadratic |

**Hashing and encoding**

| Unit | What you get |
|------|--------------|
| [BpSHA256](docs/FEATURES.md#bpsha256) / [BpMD5](docs/FEATURES.md#bpmd5) | one-shot or streaming digests for buffers, strings and files; hex or Base64 out |
| [BpHMACSHA256](docs/FEATURES.md#bphmacsha256) | request signing and webhook verification (RFC 2104) |
| [BpPasswordHash](docs/FEATURES.md#bppasswordhash) | PBKDF2-HMAC-SHA256 with CSPRNG salt, 600k iterations and a self-describing record |
| [BpBase64](docs/FEATURES.md#bpbase64) | Base64 and Base64url; the decoder forgives padding and whitespace |
| [BpHashBobJenkins](docs/FEATURES.md#bphashbobjenkins) | lookup3, interoperable with the RTL's `BobJenkinsHash` |

**Windows and odds and ends**

| Unit | What you get |
|------|--------------|
| [TbpCredentials](docs/FEATURES.md#tbpcredentials) | secrets in the Windows Credential Manager, keyring style, instead of plaintext in an INI |
| [TbpObjectComparer](docs/FEATURES.md#tbpobjectcomparer) | diff two objects by RTTI and get the changed properties, collections included |
| [BpVariantUtils](docs/FEATURES.md#bpvariantutils) / [BpSysUtils](docs/FEATURES.md#bpsysutils) / [StopWatch](docs/FEATURES.md#stopwatch) | strict Variant conversions, old-compiler shims, a `QueryPerformanceCounter` stopwatch |

## One file instead of ten

`dist\` holds amalgamated builds, SQLite style: `BpDictionaries.pas`, `BpHashes.pas`, `BpHttpClientStandalone.pas`, `BpJsonStandalone.pas`. Each is self-contained - take the one you need and nothing else. Use at most one bundle per project, and treat them as build artifacts: fix the real unit and regenerate. [Details ->](docs/FEATURES.md#single-file-bundles)

## Building and testing

The `.cmd` scripts at the repo root drive Delphi 2007 through MSBuild:

```
Build_Main_D2007.cmd Release
RunTests_D2007.cmd            unit + integration
RunTests_D2007.cmd /nointeg   offline run
RunTests_D2007.cmd /bench     add the benchmarks
```

`RunTests_D2007.cmd` builds the DUnit runner and runs it. See [tests/README.md](tests/README.md) for the breakdown, and note that the tests are also the most complete set of examples in the repo.

## Contributing

Fork it, fix or add something, open a pull request. Bugs, new units and better docs are all fair game. Match the house style: locals `lv`, globals `gv`, constants `lc` / `gc`, parameters `a` (`aValue`), classes `Tbp`, one class per unit named after it, `//` comments only.

## Getting Delphi

Official ISOs and web installers for the older Delphi and RAD Studio releases are collected here:

- [Delphi Official Downloads](https://github.com/dimitar-grigorov/DelphiBoostPack/blob/main/Delphi%20Official%20Downloads.md)

## License

GPL-3.0 - see [LICENSE](LICENSE).
