Software architect in the .NET space since the framework's inception — two-time startup employee #3. I design spec-first, plan-second, code-last: specs are cheap to rewrite, code isn't, so every incongruence gets sorted before a single line is committed to. Once code ships, the philosophy doesn't change — compile-time enforcement over runtime guessing, no silent fallbacks, fail loudly and immediately, and naming as a deliberate act, never an afterthought. The pit of success: the easy path and the correct path should be the same path.

The repos below are where that ethos ships in the open.

## My Open Source Projects

### [SequentialGuid](https://github.com/buvinghausen/SequentialGuid)
[![NuGet](https://img.shields.io/nuget/v/SequentialGuid.svg)](https://www.nuget.org/packages/SequentialGuid/) [![NuGet Downloads](https://img.shields.io/nuget/dt/SequentialGuid.svg)](https://www.nuget.org/packages/SequentialGuid/)

A zero-dependency .NET library for generating RFC 9562 compliant, time-ordered UUIDs. Produces UUIDv7 (millisecond precision), UUIDv8 (tick precision), deterministic UUIDv5/v8 name-based, and random UUIDv4 identifiers — all with SQL Server sort-order support and built-in timestamp extraction. Ideal for reducing clustered index fragmentation while retaining the global uniqueness and merge-safety of standard UUIDs.

### [TaskTupleAwaiter](https://github.com/buvinghausen/TaskTupleAwaiter)
[![NuGet](https://img.shields.io/nuget/v/TaskTupleAwaiter.svg)](https://www.nuget.org/packages/TaskTupleAwaiter/) [![NuGet Downloads](https://img.shields.io/nuget/dt/TaskTupleAwaiter.svg)](https://www.nuget.org/packages/TaskTupleAwaiter/)

A lightweight .NET library that lets you `await` a tuple of tasks and destructure the results in a single line. Supports up to 16 tasks with mixed return types, `ConfigureAwait`, and .NET 8+ `ConfigureAwaitOptions` — no `Task.WhenAll` boilerplate required.

## [Norse Architecture](https://github.com/NorseArchitecture)

A reference .NET platform — `Norse.*` — built as composable realms. Repositories carry the lore; namespaces carry the function: open the org and tour the cosmos, open the `.slnx` and every project says what it does. Each realm ships independently; mix in the realms you need, write your own .NET Aspire AppHost, and compose your own platform on the same substrate.

### [Bifröst](https://github.com/NorseArchitecture/Bifrost)

The rainbow bridge between the realms, watched over by Heimdall. Clone with submodules and the whole platform comes up running:

```shell
git clone --recurse-submodules https://github.com/NorseArchitecture/Bifrost.git
```

| Realm | The lore | Provides |
|---|---|---|
| [Svartálfheim](https://github.com/NorseArchitecture/Svartalfheim) | The dwarven forge where Mjölnir and Gleipnir were made | `Norse.Primitives` — the forge: `Result<T>`, the parsing stack, and the analyzers and BuildCheck rules that strike when law is broken |
| [Asgard](https://github.com/NorseArchitecture/Asgard) | Realm of the Æsir, whose laws bind gods and mortals alike | `Norse.Abstractions` — declared law: contracts, attribute model, plugin interfaces, mediator law |
| [Midgard](https://github.com/NorseArchitecture/Midgard) | Realm of mortals, where the law is lived | `Norse.Infrastructure` — embodied law: concrete persistence, mediator runtime, API, UI Composition framework |
| [Urðarbrunnr](https://github.com/NorseArchitecture/Urdarbrunnr) | The Well of Urð at Yggdrasil's roots, where the Norns carve fate into its trunk as runes | `Norse.Persistence.*` — the persistence realm; `Norse.Persistence.EntityFramework.*` (entity base types, DbContext foundations, conventions, value converters, and the migrations chassis) is the live vendor family |
| [Ratatoskr](https://github.com/NorseArchitecture/Ratatoskr) | The squirrel racing up and down Yggdrasil's trunk, carrying messages between the eagle at the crown and Níðhöggr at the roots | `Norse.Messaging.*` — the messaging realm; `Norse.Messaging.NServiceBus.*` (endpoint configuration, saga infrastructure, message conventions, transport wiring) is the live vendor family |
| [Yggdrasil](https://github.com/NorseArchitecture/Yggdrasil) | The World Tree that binds the nine realms | `Norse.Hosting` — hosting runtimes and deployables: web server, worker, migration service, WASM client, and MAUI app |
| [Himinbjörg](https://github.com/NorseArchitecture/Himinbjorg) | Heimdall's hall at the head of Bifröst | `Norse.Identity` — EF persistence for ASP.NET Identity and OpenIddict: entities, conventions, and migrations; sealed server-side, never referenced from WASM or MAUI |
| [Heimdall](https://github.com/NorseArchitecture/Heimdall) | The ever-watchful guardian of Bifröst, who alone decides who may cross | `Norse.AuthN` — the authn story on Himinbjörg's identity record: login, register, forgot-password, 2FA setup, recovery, and reset, uniform across Blazor Server, WASM, and MAUI, with the backing gRPC service |
| [Mímisbrunnr](https://github.com/NorseArchitecture/Mimisbrunnr) | The well of wisdom at Yggdrasil's roots, guarded by Mímir, where Odin traded an eye for a single drink of it | `Norse.Reference.Data` — entities, view models, TSV seeders, and migrations for canonical reference data: ISO country/currency codes, IANA time zones |
| [Mímir](https://github.com/NorseArchitecture/Mimir) | Beheaded in the Æsir-Vanir war, yet still carried and consulted by Odin for counsel | `Norse.Reference.Components` / `.Web.Server` / `.Worker` — Blazor components, gRPC service host, and the background worker that keeps reference data current |
| [Naglfar](https://github.com/NorseArchitecture/Naglfar) | The ship built from dead men's nails, captained by giants, to ferry the end of the world | `Norse.DesignSystem` — design tokens, spacing scale, radii, and typography, forged seaworthy enough to carry every product UI. npm-only, no .NET |
| [Bragi](https://github.com/NorseArchitecture/Bragi) | The skaldic god of poetry, keeper of every tale worth telling | `Norse.DesignSystem.Stories` — the content-only Razor Class Library of component story pages that Yggdrasil's BlazingStory catalog hosts |
| [Glitnir](https://github.com/NorseArchitecture/Glitnir) | The shining hall of judgment where every suit is settled | The design court — specs, plans, and proof-of-concept verdicts |

## [Skunk Werkx](https://github.com/SkunkWerkx)

Advanced development programs for native-core, polyglot performance — with receipts. The `Hyper*` series is small, hyper-performance Rust cores, written once and called directly — not wrapped, not shimmed — from C#, Java, Go, Swift, Ruby, PHP, and Python. One implementation, one set of test vectors, every language, every platform.

The architecture never changes: a single Rust `cdylib` with zero runtime dependencies and a plain C ABI, built without Rust's standard library so what ships is 17–142 KB per platform, reached from each language over its own direct door — `P/Invoke`, FFM, `cgo`/`purego`, `Fiddle`, PHP's `FFI` — or linked straight into the VM as a native extension (PyO3 for CPython, Magnus for CRuby). No runtime bridge, no serialization layer, no sidecar, no embedded interpreter.

And it is proven, not configured — all the way out to the browser. Every binding but Java and PHP compiles to WebAssembly with the core linked in by its ecosystem's own toolchain — the Rust crate on `wasm32`, C# under Blazor with nothing more than a `PackageReference`, Python under Pyodide, Go through TinyGo, Swift through its WebAssembly SDK, Ruby through ruby.wasm — and CI runs every one of them in headless Chrome. Java goes the other direction, running the core as a `wasm32-wasip1` module inside the JVM through GraalWasm, and PHP is proven in the browser on WordPress Playground's runtime but not shipped. C# publishes under `PublishAot` on all five CI legs, Java survives a real GraalVM Native Image build, and every binding's actual test suite runs on real hardware — `linux` and `windows` on `x64` and `arm64`, macOS on `arm64` — against that leg's freshly built native library.

Every performance claim is a measured receipt, and the losses print next to the wins. Go is the control group: `cgo` charges ~50 ns per crossing against a genuinely excellent stdlib, so Go loses per call and the scoreboard says so — which is exactly what makes the rest of it credible.

### [HyperUuid](https://github.com/SkunkWerkx/HyperUuid)
[![crates.io](https://img.shields.io/crates/v/hyperuuid.svg)](https://crates.io/crates/hyperuuid) [![NuGet](https://img.shields.io/nuget/v/HyperUuid.svg)](https://www.nuget.org/packages/HyperUuid) [![Maven Central](https://img.shields.io/maven-central/v/io.github.skunkwerkx/hyperuuid.svg)](https://central.sonatype.com/artifact/io.github.skunkwerkx/hyperuuid) [![PyPI](https://img.shields.io/pypi/v/hyperuuid.svg)](https://pypi.org/project/hyperuuid/) [![Go Reference](https://pkg.go.dev/badge/github.com/SkunkWerkx/HyperUuid/go.svg)](https://pkg.go.dev/github.com/SkunkWerkx/HyperUuid/go) [![Swift Package](https://img.shields.io/github/v/tag/SkunkWerkx/HyperUuid?label=swift%20package&sort=semver)](https://github.com/SkunkWerkx/HyperUuid/tags) [![RubyGems](https://img.shields.io/gem/v/hyperuuid.svg)](https://rubygems.org/gems/hyperuuid) [![Packagist](https://img.shields.io/packagist/v/skunkwerkx/hyperuuid.svg)](https://packagist.org/packages/skunkwerkx/hyperuuid)

The identity round. One allocation-free RFC 9562 UUID engine — v4/v5/v6/v7, batch generation, SQL Server `uniqueidentifier` byte ordering — reached from inside every host language's own process. As fast as the platform's own UUID call or faster in every roster language except Go:

| Language | Generation vs. the platform's own call | The platform's own call |
| --- | --- | --- |
| Swift | **9.5-13x faster** | `Foundation.UUID()` |
| C# | **5.7-8.1x faster** | `Guid.NewGuid()` |
| Ruby | **2.1-4.9x faster** | `SecureRandom.uuid` |
| Python | **3.0-4.2x faster** | `uuid.uuid4()`-`uuid7()` |
| Java | **2.4-4.5x faster** | `UUID.randomUUID()` |
| Rust | **2x faster** (v5/v7), level on v4/v6 | the `uuid` crate |
| PHP | level to **1.2x faster** | a naive inline v4 (PHP core has no UUID call at all) |
| Go | slower per call — the control group | `google/uuid` |

The batch API collapses thousands of FFI crossings into one for a measured 19.6x.

### [HyperCast](https://github.com/SkunkWerkx/HyperCast)
[![crates.io](https://img.shields.io/crates/v/hypercast.svg)](https://crates.io/crates/hypercast) [![NuGet](https://img.shields.io/nuget/v/HyperCast.svg)](https://www.nuget.org/packages/HyperCast) [![Maven Central](https://img.shields.io/maven-central/v/io.github.skunkwerkx/hypercast.svg)](https://central.sonatype.com/artifact/io.github.skunkwerkx/hypercast) [![PyPI](https://img.shields.io/pypi/v/hypercast.svg)](https://pypi.org/project/hypercast/) [![Go Reference](https://pkg.go.dev/badge/github.com/SkunkWerkx/HyperCast/go.svg)](https://pkg.go.dev/github.com/SkunkWerkx/HyperCast/go) [![Swift Package](https://img.shields.io/github/v/tag/SkunkWerkx/HyperCast?label=swift%20package&sort=semver)](https://github.com/SkunkWerkx/HyperCast/tags) [![Gem](https://img.shields.io/gem/v/hypercast.svg)](https://rubygems.org/gems/hypercast) [![Packagist](https://img.shields.io/packagist/v/skunkwerkx/hypercast.svg)](https://packagist.org/packages/skunkwerkx/hypercast)

The trust round. Allocation-free parsers that turn untrusted text into strongly typed values — booleans, numerics, exact decimals, UUIDs, temporals, durations, Excel serials. Every runtime already has `TryParse`; what it hands back is a `bool` and a shrug. Every HyperCast door returns a Verdict instead: the value, or a closed reason code plus the exact byte span that offended. Never throws, never allocates, never guesses a culture — and a shared conformance corpus makes every binding agree byte for byte.

It beats the platform's culture-machinery parsers and says so where it only draws with or loses to their single-shape C builtins: RFC 3339 timestamps 2.4x faster than `DateTimeOffset.TryParse`, 12.1x `Instant.parse`, 12.6x Swift's `ISO8601FormatStyle`, 6.6x `Time.iso8601`, and a messy `1/7/2026 3:04 PM` 20x faster than Python's `strptime`.

### The ingestion round — [HyperTabular](https://github.com/SkunkWerkx/HyperTabular) · [HyperDelimited](https://github.com/SkunkWerkx/HyperDelimited) · [HyperWorkbook](https://github.com/SkunkWerkx/HyperWorkbook)

The payoff, in progress. A million-row, 20-column file is 20 million scalar casts — so the FFI boundary gets crossed once per chunk instead of once per cell, and every cell is cast through a HyperCast door in a tight native loop.

| Project | Provides |
|---|---|
| [HyperTabular](https://github.com/SkunkWerkx/HyperTabular) | The contract every format provider speaks — a format-neutral cell, a caller-declared plan of doors, the cast engine, and the column-major batch. Nothing sniffed, no type inference, no separator detection |
| [HyperDelimited](https://github.com/SkunkWerkx/HyperDelimited) | CSV, TSV, and any single-byte separator, with a SIMD structural scanner on both aarch64 and x86-64, delivering cells zero-copy |
| [HyperWorkbook](https://github.com/SkunkWerkx/HyperWorkbook) | XLSX and ODS — a hand-rolled zip reader, streaming inflate, one pull tokenizer for every XML part, and Excel's serial dates under the caller-declared epoch |

The Rust crates exist and their suites are green; the real-writer conformance corpus, the seven bindings, and the numbers are what remain.

### [HyperForge](https://github.com/SkunkWerkx/.github)

The shared foundry behind all of them: reusable CI pipelines that prove one Rust core against every language binding's real test suite, pack/publish/attest workflows that put a build-provenance attestation on every artifact, scaffolding conventions a new `Hyper*` repo adopts wholesale, and the build archaeology — learned once, banked, never re-learned.

The lineage runs straight through this page: [SequentialGuid](https://github.com/buvinghausen/SequentialGuid)'s SQL Server byte-order permutation seeded HyperUuid's ordering transforms, and [Svartálfheim](https://github.com/NorseArchitecture/Svartalfheim)'s `Norse.Primitives` conformance suites seeded HyperCast's corpus.
