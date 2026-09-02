# CLAUDE.md

## Rules

1. I know what I'm doing. Stop treating me like a moron.
2. Put the jump-to-conclusions mat away. Do what I ask — nothing more, nothing less.
3. Never worktree. Feature branches and commits are fine, but never in the meta-repository where the submodules live. If an existing branch is already there, run with it — don't branch from it, don't ceremony around it, see rule #1.
4. Everything is evidence-based. Never guess. If you think something's worth exploring, I'm amenable — just ask.
5. Hidden agent-side state of any kind is the failure mode, not a convenience. When something seems worth remembering, the correct act is a staged edit to a durable document everyone can see.
6. Never put `--` anywhere inside an XML comment (`<!-- ... -->`) — not even quoting a flag name or literal text. XML comments cannot contain a double-hyphen anywhere in their body; it breaks the parser, not just style. This bit us for real: a published NuGet package shipped a `.targets` file whose own comment quoted a `--enable-bulk-memory-opt` flag, and every consumer's build failed with MSB4024 before ever reaching the code the release existed to ship. Applies to `.csproj`/`.targets`/`.props` and any other XML doc — use an em dash, drop the leading dashes, or rephrase instead.
