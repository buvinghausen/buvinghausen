# Fedora WSL2 strong-name signing quirk

On this machine (Fedora 44 under WSL2), a plain `dotnet build` / `Build.csproj` fails with:

```
Interop.Crypto.RsaSignHash
```

from `Microsoft.CSharp.Core.targets`.

## Root cause

Fedora's system crypto-policy rejects SHA-1 signatures, and full strong-name signing
(`SignAssembly=true` + `DelaySign=false` + `AssemblyOriginatorKeyFile=ProtoBuf.snk`, set in
`src/Directory.Build.props`) requires a SHA-1 RSA signature.

Same root cause, independently confirmed on this box for a sibling project — see `efcore-pg`'s
`fedora-wsl-build-quirks` memory (Npgsql.snk, identical symptom).

## Fix

```sh
dotnet build Build.csproj -p:PublicSign=true
```

(or any target). Public-signing embeds the real public key without doing the SHA-1 RSA signature
step Fedora blocks, so `InternalsVisibleTo` attributes (which hard-code the expected
`PublicKey=...` — see `protobuf-net.Core/Properties/AssemblyInfo.cs` and `AGENTS.md`'s BuildTools
section) still resolve correctly. CI on `windows-latest` doesn't need this.

## Do NOT flip `SignAssembly` to `false`

Tried this first and it breaks the build outright (550 errors) rather than just failing to sign:
several `AssemblyInfo.cs` files hard-code the signed public key in
`[InternalsVisibleTo("protobuf-net, PublicKey=...")]`-style attributes, so an unsigned
(empty-public-key) output assembly loses friend access to `protobuf-net.Core`'s internals —
`CS0281` cascading into `CS0122`/`CS0115` across `protobuf-net`, `protobuf-net.MessagePipes`,
`protobuf-net.Reflection.Test`, etc.

`PublicSign=true` is strictly better: same public key/token, no SHA-1 signature needed.

## One caveat

`-p:PublicSign=true` is a global MSBuild property, so it applies even to
`src/protogen.site.blazor.client`, which deliberately sets `SignAssembly=false` with no key file of
its own (a Blazor WASM sample). MSBuild passes `/publicsign+` to csc regardless of that project's
own `SignAssembly` value, so that one project fails with `CS8102` ("Public signing was specified
and requires a public key, but no public key was specified").

This is a side effect of forcing the property blanket-wide, not a real bug — every other project in
the traversal (including net462 `protobuf-net` itself, `protobuf-net.BuildTools`, `AotSmoke`,
`AotColdStart`, nupkg packing) builds clean under it. Safe to ignore or build around; not worth
"fixing" by touching that project's signing intent.

## Why this is worth remembering

An earlier session's subagent hit the same `RsaSignHash` error cold, correctly suspected a
crypto-policy block, but then spent ~27 minutes and dozens of individually permission-prompted
commands reverse-engineering `/etc/crypto-policies`, FIPS flags, and a hand-written `openssl.cnf`
override from scratch — instead of the two-word fix already known for a sibling project on this
exact machine. That is the incident Brian called "the openssl disaster" / getting "k-holed".

The parent session's own postmortem ("transient dotnet-build-server flakiness") was likely a wrong
guess made without checking cross-project memory — worth treating with suspicion if it resurfaces.

## How to apply

The moment a local build here throws a SHA-1/RSA/crypto interop error during compile, reach for
`-p:PublicSign=true` immediately rather than investigating OS crypto policy.
