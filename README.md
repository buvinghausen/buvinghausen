Software architect in the .NET space since the framework's inception — two-time startup employee #3, I design spec-first, plan-second, code-last: specs are cheap to rewrite, code isn't, so every incongruence gets sorted before a single line is committed to. Once code ships, the philosophy doesn't change — compile-time enforcement over runtime guessing, no silent fallbacks, fail loudly and immediately, and naming as a deliberate act, never an afterthought. The pit of success: the easy path and the correct path should be the same path.

The repos below are where that ethos ships in the open.

## My Open Source Projects

### [SequentialGuid](https://github.com/buvinghausen/SequentialGuid)
[![NuGet](https://img.shields.io/nuget/v/SequentialGuid.svg)](https://www.nuget.org/packages/SequentialGuid/) [![NuGet Downloads](https://img.shields.io/nuget/dt/SequentialGuid.svg)](https://www.nuget.org/packages/SequentialGuid/)

A zero-dependency .NET library for generating RFC 9562 compliant, time-ordered UUIDs. Produces UUIDv7 (millisecond precision), UUIDv8 (tick precision), deterministic UUIDv5/v8 name-based, and random UUIDv4 identifiers — all with SQL Server sort-order support and built-in timestamp extraction. Ideal for reducing clustered index fragmentation while retaining the global uniqueness and merge-safety of standard UUIDs.

### [TaskTupleAwaiter](https://github.com/buvinghausen/TaskTupleAwaiter)
[![NuGet](https://img.shields.io/nuget/v/TaskTupleAwaiter.svg)](https://www.nuget.org/packages/TaskTupleAwaiter/) [![NuGet Downloads](https://img.shields.io/nuget/dt/TaskTupleAwaiter.svg)](https://www.nuget.org/packages/TaskTupleAwaiter/)

A lightweight .NET library that lets you `await` a tuple of tasks and destructure the results in a single line. Supports up to 16 tasks with mixed return types, `ConfigureAwait`, and .NET 8+ `ConfigureAwaitOptions` — no `Task.WhenAll` boilerplate required.

## [Norse Architecture](https://github.com/NorseArchitecture)

A reference .NET platform built as composable realms — primitives, contracts, infrastructure, hosting, EF Core foundations, identity, and access — orchestrated through .NET Aspire. Each realm is its own repo and ships independently; mix in the realms you need, swap the runtime containers, and compose your own platform on the same substrate.

### [Bifrost](https://github.com/NorseArchitecture/Bifrost)

The rainbow bridge between the realms, watched over by Heimdall. Clone with submodules and the whole platform comes up running:

```shell
git clone --recurse-submodules https://github.com/NorseArchitecture/Bifrost.git
```

| Realm | The lore | Provides |
|---|---|---|
| [Svartalfheim](https://github.com/NorseArchitecture/Svartalfheim) | The dwarven forge where Mjölnir and Gleipnir were made | Domain primitives — value types, identifiers, `Result` parsing, encryption |
| [Asgard](https://github.com/NorseArchitecture/Asgard) | Realm of the Æsir, whose laws bind gods and mortals alike | Abstractions — the contracts every realm must honor |
| [Midgard](https://github.com/NorseArchitecture/Midgard) | Realm of mortals, where the law is lived | Infrastructure — persistence, messaging, caching, external integrations |
| [Urdarbrunnr](https://github.com/NorseArchitecture/Urdarbrunnr) | The Well of Urd at Yggdrasil's roots, where the Norns carve fate into its trunk as runes | EF Core foundations — entity base types, conventions, migrations chassis |
| [Yggdrasil](https://github.com/NorseArchitecture/Yggdrasil) | The World Tree that binds the nine realms | Hosting — web, worker, and migration service chassis |
| [Himinbjorg](https://github.com/NorseArchitecture/Himinbjorg) | Heimdall's hall at the head of Bifrost | Identity — backend-only EF persistence for ASP.NET Identity & OpenIddict |
| [Heimdall](https://github.com/NorseArchitecture/Heimdall) | The ever-watchful guardian of Bifrost, who alone decides who may cross | Access — one auth ruleset enforced across Blazor Server, WASM, and MAUI |
| [Glitnir](https://github.com/NorseArchitecture/Glitnir) | The shining hall of judgment, where every suit is settled | The design court — specs, plans, and proof-of-concept verdicts |
