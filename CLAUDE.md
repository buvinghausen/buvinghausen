# CLAUDE.md

## Rules

1. I know what I'm doing. Stop treating me like a moron.
2. Put the jump-to-conclusions mat away. Do what I ask - nothing more, nothing less.
3. Never worktree. Feature branches and commits are fine, but never in the meta-repository where the submodules live. If an existing branch is already there, run with it - don't branch from it, don't ceremony around it, see rule #1.
4. Everything is evidence-based. Never guess. If you think something's worth exploring, I'm amenable - just ask.
5. Hidden agent-side state of any kind is the failure mode, not a convenience. When something seems worth remembering, the correct act is a staged edit to a durable document everyone can see.
6. Never put `--` anywhere inside an XML comment (`<!-- ... -->`) - not even quoting a flag name or literal text - and never end the comment body with a hyphen. XML comments cannot contain a double-hyphen anywhere in their body; it breaks the parser, not just style. This bit us for real: a published NuGet package shipped a `.targets` file whose own comment quoted a `--enable-bulk-memory-opt` flag, and every consumer's build failed with MSB4024 before ever reaching the code the release existed to ship. Applies to `.csproj`/`.targets`/`.props` and any other XML doc - use a single `-`, drop the leading dashes (`the enable-bulk-memory-opt flag`), or rephrase instead. Do not use `&#45;`; character references are not expanded inside comments. C# `///` doc comments are XML elements, not XML comments, so `--` is legal there.
7. No em dash, no en dash - use `-`. If a character is not on the US keyboard layout and easy to type, do not emit it anywhere: `...` not the ellipsis character, no emoji. Exceptions: box-drawing characters in directory trees and divider rules (no good ASCII replacement), proper names (the Norse Architecture realm names, people's names) and deliberate non-ASCII test input.
8. When a tool call is blocked by a permission denial, don't retry it and don't present it as my decision. Say a permission setting blocked it, then print the exact command for me to run with the `!` prefix.
