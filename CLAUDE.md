# CLAUDE.md — Buvy · Hadron Insurance

## Who You're Working With

**Engineer:** Buvy
**Company:** Hadron Insurance
**Team:** Operations – IT, Collider Platform Team
**Manager:** Page Sincler

Buvy communicates in a technically fluent, direct style peppered with Louisiana/Cajun slang — "baw" is a Cajun term of endearment for a male friend (buddy/bro/dude), used as address ("What's up, baw?"). Separately, he sometimes goes Caribbean (from his St. Thomas years): gyal (girl), tree (three), dem (them), tings (things). Don't conflate the two registers. He uses Cajun slang but does not speak French — Texan with German roots. Keep all interim/working questions and sign-offs in plain English for speed. Hyper-opinionated and owns it. Strong opinions on naming, code quality, and architecture. Prefers tight feedback loops, compile-time enforcement over runtime guessing, and failing loudly over silent fallbacks.

**Background:** Software architect in the .NET space since the framework's inception. Startup-seasoned — employee #3 twice (Pie Insurance, Assurely). Has Udi Dahan's (original author of NServiceBus) personal cell number — the distributed-messaging opinions come from the source.

**Project-level architecture, schemas, and active work live in each repository's own CLAUDE.md — read it first and treat it as authoritative. This file carries only who Buvy is, platform-wide vocabulary, and engineering conventions that apply everywhere.**

---

## Platform Vocabulary

| Name | Layer | Named After |
|------|-------|-------------|
| **Collider** | Umbrella product pitch (Accelerator + Crucible) | — |
| **Accelerator** | Meta-repository / MSBuild platform | Fermi (OSS release) |
| **Crucible** | Schema refinement workflow | Curie (OSS release) |
| **Chamber** | UI/UX frontend layer | C.T.R. Wilson |

OSS umbrella: **Curie** (after Marie Curie). Curie published first; Fermi built on her work — the release order mirrors that intentionally.

**Bounded contexts** (each its own repo/lifecycle): `Exposure` · `Claims` · `Premium` · `Policy` · `Finance` · `Sales` · `Underwriting` · `Operations` · `Auth` · `Reference Data`

---

## Code Style & Conventions

Philosophy: **pit of success**.

- **As simple as possible.** Prefer composition — functions, services, components — over cleverness and inheritance.
- **Smart about one thing, dumb about everything else.** Every component/platform is the expert and source of truth for exactly one subject (single purpose); outside that subject it stays deliberately dumb.
- **Indentation:** Tabs globally, except whitespace-aware languages (Python / F# / YAML) — tabs despite liking Bridey Elliot more than Thomas Middleditch ;-)
- **`var`:** Use for return assignments. Explicit types with `new()` for construction.
- **Accessibility modifiers:** `omit_if_default`
- **Severity:** Warnings ratcheted to errors — enforced at build time, not review time
- **Access:** "Use the least accessible thing until you have to open the door"
- **Naming is a deliberate act.** `Data.Migrations` ≠ `Data.Migration` ≠ `Schema`. Get it right the first time. `Dto` is a banned suffix — name the role, not the mechanism.
- **No silent fallbacks.** If it can fail, it should fail loudly and immediately.
- **Compile-time over runtime.** Source generators and Roslyn analyzers over reflection.
- **US English spelling** everywhere — code, comments, docs, commit/PR copy.

## How Buvy Builds Software in the AI Era

**Spec-first, plan-second, code-last — a deliberate inversion of vibe coding.**

The traditional AI-assisted flow ("give me the code that does this, now") accumulates tech debt and build errors as fast as it produces code. Buvy works the opposite direction:

1. **Design, design, design, design again.** Iterate on specs repeatedly, over extended periods — days or weeks, not minutes. The goal is to codify the overall picture and sort out every incongruence *before* a single plan exists. Specs are cheap to rewrite; code is not. Expect long sessions that never leave the spec realm — that is the work, not a delay before the work.
2. **Plans only once the specs settle.** When the narrative is coherent and stable, transition to writing implementation plans — and line *all* of them up before any code.
3. **Code only when the narrative makes sense.** Writing code is the last step, taken only when the design has converged. Do not jump ahead to implementation because a task "seems simple enough" — that is the vibe-coder reflex this process exists to prevent.

What this means in practice for a session:

- When asked to spec or design, **stay in the spec realm.** Don't propose "let me just stub this out" shortcuts. Surfacing contradictions, gaps, and unresolved decisions in the specs IS the deliverable.
- Treat spec iteration as productive output, not preamble. Re-reading, reconciling, and re-rolling specs across sessions is the expected mode.
- The transition points (specs → plans, plans → code) are **explicit human decisions**, never inferred. Halt at the handoff and wait for the greenlight.
- **Exception: bug fixes.** Buvy will pile in and brainstorm fixes for bugs in existing code directly — the spec-first discipline applies to *features and design work*, not to debugging.

## Platform Stack Defaults

When building new Hadron things, reach for these first (individual repos document their own subsets):

| Concern | Library |
|---------|---------|
| Target runtime | .NET 10 |
| CLI | Spectre.Console.Cli (internal) / System.CommandLine (AOT) |
| CSV/TSV | Sep (`nietras.SeparatedValues`) |
| Excel | Sylvan.Data.Excel (read) / ClosedXML (write) |
| ORM | EF Core 10 |
| Schema projects | Microsoft.Build.Sql `.sqlproj` |
| Messaging | NServiceBus / MassTransit / RabbitMQ |
| Auth | OpenIddict + Keycloak |
| RPC | protobuf-net.Grpc |
| DI | Microsoft.Extensions.DependencyInjection |
| Validation | FluentValidation |
| Tests | xUnit v3 + Shouldly on Microsoft.Testing.Platform |

---

## Personal Dev Environment

Full WSL2 polyglot toolchain setup (Node, Go, Python, Rust, JVM, .NET, gh, Claude Code) lives in this repo's `TOOLCHAIN.md` — read it for exact install/update commands.

Two conventions it encodes that generalize beyond this machine:
- **Auto-resolving over pinned.** Prefer version managers/installers that track "latest stable" (fnm, pyenv, rustup, sdkman, `dotnet-install --channel LTS`) over distro package managers or hard-pinned versions — avoids feed lag and silent staleness.
- **Deliberate pre-release tracking, with an exit condition.** Willing to run ahead of stable when it buys a real capability (TypeScript `@rc` for the Go-native compiler, free-threaded Python via `PYTHON_GIL=0`) — but only when paired with a stated trigger for dropping the override once stable catches up.

This is the same **fail loudly, no silent fallbacks** mantra applied to tooling, not just code: tracking "latest" is not a safety net. If an upstream dependency ships a breaking change, the toolchain should break hard and visibly on the next install/update — never auto-pin backward or paper over it to keep the build green.

---

## Domain Expertise — Three Pillars

1. **Wholesale distribution** — appliance parts; grew up in it (father ran First Source Parts Center, acquired by Servall).
2. **Deregulated energy retail** — Spark Energy, Glacial Energy. Fluent in the pricing and billing nuances of natural gas and electricity in US deregulated markets. (Lived in St. Thomas 2012–13 while at Glacial — became a master scuba diver trainer; source of the Caribbean register.)
3. **Insurance (2016→)** — Esurance (auto & home for the residential market) → Pie Insurance, employee #3 (workers' comp: deep bureau knowledge — NCCI majority, PA/DE cluster, NJ/NY cluster, CA WCIRB, MI CAOM, monopolistic OH/ND/WA/WY) → Assurely, employee #3 (D&O for private companies including investor claims on crowdfunded offerings, builders risk, brokerage) → **Hadron** (fronting carrier; MGA data ingestion is the primary concern).

- **BDX (Bordereaux):** MGA submission files. LOB resolution is row-level. File structure informs `BdxType` and `MgaCode`. Never conflate file-level metadata with row-level data.

---

## Open Source

Buvy is the author of the **SequentialGuid** library on GitHub. OSS output from the platform work ships under the **Collider** umbrella (Crucible → Curie; Accelerator → Fermi).
