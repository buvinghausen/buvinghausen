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

### [Bifrost](https://github.com/NorseArchitecture/Bifrost)

The rainbow bridge between the realms, watched over by Heimdall. Clone with submodules and the whole platform comes up running:

```shell
git clone --recurse-submodules https://github.com/NorseArchitecture/Bifrost.git
```

| Realm | The lore | Provides |
|---|---|---|
| [Svartalfheim](https://github.com/NorseArchitecture/Svartalfheim) | The dwarven forge where Mjölnir and Gleipnir were made | `Norse.Primitives` — the forge: `Result<T>`, the parsing stack, and the analyzers and BuildCheck rules that strike when law is broken |
| [Asgard](https://github.com/NorseArchitecture/Asgard) | Realm of the Æsir, whose laws bind gods and mortals alike | `Norse.Abstractions` — declared law: contracts, attribute model, plugin interfaces, mediator law |
| [Midgard](https://github.com/NorseArchitecture/Midgard) | Realm of mortals, where the law is lived | `Norse.Infrastructure` — embodied law: concrete persistence, mediator runtime, API, UI Composition framework |
| [Urdarbrunnr](https://github.com/NorseArchitecture/Urdarbrunnr) | The Well of Urd at Yggdrasil's roots, where the Norns carve fate into its trunk as runes | `Norse.EntityFramework` — entity base types, DbContext foundations, conventions, value converters, and the migrations chassis |
| [Ratatoskr](https://github.com/NorseArchitecture/Ratatoskr) | The squirrel racing up and down Yggdrasil's trunk, carrying messages between the eagle at the crown and Níðhöggr at the roots | `Norse.NServiceBus` — NServiceBus endpoint configuration, saga infrastructure, message conventions, and transport wiring |
| [Yggdrasil](https://github.com/NorseArchitecture/Yggdrasil) | The World Tree that binds the nine realms | `Norse.Hosting` — hosting runtimes and deployables: web server, worker, migration service, WASM client, and MAUI app |
| [Himinbjorg](https://github.com/NorseArchitecture/Himinbjorg) | Heimdall's hall at the head of Bifrost | `Norse.Identity` — EF persistence for ASP.NET Identity and OpenIddict: entities, conventions, and migrations; sealed server-side, never referenced from WASM or MAUI |
| [Heimdall](https://github.com/NorseArchitecture/Heimdall) | The ever-watchful guardian of Bifrost, who alone decides who may cross | `Norse.AuthN` — the authn story on Himinbjörg's identity record: login, register, forgot-password, 2FA setup, recovery, and reset, uniform across Blazor Server, WASM, and MAUI, with the backing gRPC service |
| [Mimisbrunnr](https://github.com/NorseArchitecture/Mimisbrunnr) | The well of wisdom at Yggdrasil's roots, guarded by Mímir, where Odin traded an eye for a single drink of it | `Norse.ReferenceData.Data` — entities, view models, TSV seeders, and migrations for canonical reference data: ISO country/currency codes, IANA time zones |
| [Mimir](https://github.com/NorseArchitecture/Mimir) | Beheaded in the Æsir-Vanir war, yet still carried and consulted by Odin for counsel | `Norse.ReferenceData.Components` / `.Web.Server` / `.Worker` — Blazor components, gRPC service host, and the background worker that keeps reference data current |
| [Naglfar](https://github.com/NorseArchitecture/Naglfar) | The ship built from dead men's nails, captained by giants, to ferry the end of the world | `Norse.DesignSystem` — design tokens, spacing scale, radii, and typography, forged seaworthy enough to carry every product UI. npm-only, no .NET |
| [Bragi](https://github.com/NorseArchitecture/Bragi) | The skaldic god of poetry, keeper of every tale worth telling | `Norse.DesignSystem.Stories` — the content-only Razor Class Library of component story pages that Yggdrasil's BlazingStory catalog hosts |
| [Glitnir](https://github.com/NorseArchitecture/Glitnir) | The shining hall of judgment where every suit is settled | The design court — specs, plans, and proof-of-concept verdicts |
