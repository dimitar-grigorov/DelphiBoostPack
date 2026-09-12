# Tests

DUnit suite for DelphiBoostPack. One project, [DelphiBoostPackTests.dpr](DelphiBoostPackTests.dpr), builds every test into a single runner. Built from the IDE you get the GUI runner; the `.cmd` scripts define `CONSOLE_TESTRUNNER` so the exe runs on the console and returns exit code 1 on any red test, which is what CI gates on. A leaked block fails the run too: the RTL reports leaks with a modal dialog nobody is there to click, so the console runner turns that off and [Core/BpLeakGate.pas](Core/BpLeakGate.pas) prints the leak and sets the exit code instead.

## Running

From the repo root:

```
RunTests_D2007.cmd            unit + integration (default)
RunTests_D2007.cmd /nointeg   unit only, offline and socket-free
RunTests_D2007.cmd /bench     unit + integration + benchmarks
RunTests_D2007.cmd /ci        skip the pause on failure (CI, agents)
```

`RunTests_D2007.cmd` builds first, then runs. To build without running, use `Build_Tests_D2007.cmd` with the same flags. Flags combine, e.g. `/nointeg /bench`.

## The three kinds

The suite is split so you can run only what fits the moment: fast checks on every save, the network path when it matters, benchmarks on demand. The split is wired with conditional defines, set by the build scripts.

| Kind | Default | Define | Turn it |
|------|---------|--------|---------|
| unit | on | always compiled | (cannot be turned off) |
| integration | on | `NO_INTEGRATION` excludes it | off with `/nointeg` |
| benchmarks | off | `BENCHMARK` includes it | on with `/bench` |

### Unit

Pure, offline, deterministic, fast. Every `Bp*Tests.pas` in [Core/](Core) except the network parts of the HTTP tests:

- collections: `BpIntListTests`, `BpInt64ListTests`, `BpIntDictionaryTests`, `BpStrDictionaryTests`, `BpStringListTests`
- strings: `BpStringBuilderTests`, `BpStringListTests`, `BpStrUtilsTests`
- hashing and encoding: `BpSHA256Tests`, `BpMD5Tests`, `BpHMACSHA256Tests`, `BpPasswordHashTests`, `BpHashBobJenkinsTests`, `BpBase64Tests` (crypto and hash checked against the Windows CryptoAPI, the XE6 RTL and the published FIPS/RFC vectors)
- HTTP offline: `BpHttpClientTests` (URL parsing, header building, auth, error classification) and the offline half of `BpHttpDownloadTests` (progress math, `Content-Length` parsing, argument validation, the task state machine)
- other: `BpJsonTests`, `BpDateUtilsTests`, `BpKeyFoldTests`, `BpObjectComparerSimpleTests`, `BpSysUtilsTests`, `BpCancellationTokenTests`, `BpHttpTraceTests`, `BpTasksTests` (background task state machine, cancellation, error capture, the message-pumped marshalled mode and the lifetime rules: free from inside a handler, from a foreign thread, before the completion is dispatched)

### Integration

On by default, registered only when `NO_INTEGRATION` is not defined:

- **credential store** (`TBpCredentialsTests` in [Core/BpCredentialsTests.pas](Core/BpCredentialsTests.pas)) - writes to the real Windows Credential Manager under a unique `DelphiBoostPack.Test.<pid>.<tick>` service name and deletes everything it created in `TearDown`.
- **mock server** ([Core/BpMockHttpServer.pas](Core/BpMockHttpServer.pas)) - a scriptable HTTP server on `127.0.0.1`, modelled on okhttp's MockWebServer: enqueue canned replies, run the client, then assert on the requests it recorded. A `TbpMockResponse` can answer chunked, announce more than it sends, stall, or refuse to answer at all, which is how [Core/BpHttpWireTests.pas](Core/BpHttpWireTests.pas) reaches the redirect, credential, framing and cancellation paths. Deterministic and offline, but it binds a port and starts threads, which is why it counts as integration rather than unit.
- **live endpoints** (`TBpHttpDownloadOnlineTests`) - runs against stable public URLs. Each test probes for connectivity first and reports `SKIPPED` instead of failing when there is no network, so the suite stays green offline.

Pass `/nointeg` for an offline, socket-free run (handy in locked-down CI or when a firewall would block the loopback bind).

### Benchmarks

Off by default. [Benchmarks/](Benchmarks) times the performance units against their RTL equivalents so the speed claims in the main README are measured, not asserted: `BpStringBuilderBenchmark`, `BpStrUtilsBenchmark`, `BpStrDictionaryBenchmark`, `BpIntDictionaryBenchmark`, `BpBase64Benchmark`, `BpHashBenchmark`, `BpStringOperationsBenchmark`, `BpTypesOperationsBenchmark`, `BpStringListBenchmark`, `BpIntListBenchmark`, `BpJsonBenchmark`. They share `BpBaseBenchmarkTestCase` for timing and status output, and back off gracefully on a low-memory box instead of failing the run. Only performance-sensitive units get a benchmark.

## Adding a test

- Unit tests: add a `Bp<Unit>Tests.pas` under [Core/](Core), register the suite in its `initialization`, and add it to the `uses` clause of [DelphiBoostPackTests.dpr](DelphiBoostPackTests.dpr).
- Integration tests: guard the `RegisterTest` call with `{$IFNDEF NO_INTEGRATION}` so an offline run can still opt out.
- Benchmarks: put the unit in [Benchmarks/](Benchmarks) and list it inside the `{$IFDEF BENCHMARK}` block near the top of the project `uses` clause.
