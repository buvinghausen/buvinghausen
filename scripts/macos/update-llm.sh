#!/usr/bin/env bash
# Local LLM worker for the hybrid setup in TOOLCHAIN-macos.md's "Local LLM"
# section: Ollama (Homebrew, login service), one pulled model behind a
# fixed-context alias tag, the local-llm MCP server registered in Claude Code
# (user scope) so a frontier session can farm grunt work to the box, and a
# `claude-local` wrapper for an all-local Claude Code session.
#
# Sized for this box — Apple M6, 32 GB unified memory (Metal sees ~25 GiB
# of it): the model + KV cache must stay inside that or Ollama spills layers
# to the CPU and generation collapses. The alias tag pins the context length
# (there is no per-request way to set it through the Anthropic endpoint
# Claude Code talks to, and `brew services` can't carry OLLAMA_CONTEXT_LENGTH).
# Every step is replay-safe: brew/pipx install-or-upgrade, `ollama pull`
# re-checks the digest, `ollama create` overwrites the alias, the MCP
# registration is remove-then-add, the wrapper is a clean overwrite.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh
ensure_local_dirs

BASE_MODEL="qwen3.6:35b-a3b"   # MoE, ~3B active params — the bandwidth-bound choice at 170 GB/s
ALIAS="local-llm"              # what Claude Code / the MCP server name; swap BASE_MODEL without rewiring
NUM_CTX=65536                  # Ollama's floor for coding tools is 64K; see the doc for the memory receipt

require_cmd claude "Claude Code not found — install it first (https://claude.ai/install.sh)"
require_cmd pipx "pipx not found — run the tools module first (it installs pipx for pyflakes)"

log "Ollama (Homebrew)"
brew_ensure ollama

# Homebrew's launchd plist already sets OLLAMA_FLASH_ATTENTION=1 and
# OLLAMA_KV_CACHE_TYPE=q8_0 (the formula's caveat). Start it as a login
# service unless something is already answering on the port — a foreground
# `ollama serve` in another terminal counts, and is left alone.
log "Ollama service"
if curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
	echo "ollama already answering on :11434 — $(curl -fsS http://127.0.0.1:11434/api/version)"
else
	brew services start ollama
	for _ in $(seq 1 30); do
		curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
		sleep 1
	done
	curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1 || { echo "ollama did not come up on :11434 — see /opt/homebrew/var/log/ollama.log" >&2; exit 1; }
fi

# `ollama pull` is the version-diff: a no-op when the local digest matches
# the registry's, a download when the tag has moved. On Apple Silicon the
# registry resolves this tag to its MLX nvfp4 build (`ollama show` prints the
# quantization that actually landed).
log "Base model $BASE_MODEL"
ollama pull "$BASE_MODEL"

# The alias: same blobs (a new manifest only, no second copy on disk), with
# the context length baked in so every client — the Anthropic-compatible
# endpoint included — gets it without per-request options.
log "Alias $ALIAS ($BASE_MODEL @ num_ctx $NUM_CTX)"
MODELFILE=$(mktemp)
cat >"$MODELFILE" <<EOF
FROM $BASE_MODEL
PARAMETER num_ctx $NUM_CTX
EOF
ollama create "$ALIAS" -f "$MODELFILE"
rm -f "$MODELFILE"

# MCP SDK + its `mcp run` launcher: pipx, same shape as pyflakes in the
# tools module — its own venv on Homebrew's python, outside the pyenv build
# the python module replaces on every upgrade.
log "mcp SDK (pipx)"
if pipx list --short 2>/dev/null | grep '^mcp ' >/dev/null; then
	pipx upgrade mcp
else
	pipx install "mcp[cli]"
fi

log "local-llm MCP server → $LOCAL_BIN/local-llm-mcp.py"
install -m 0644 ../local-llm-mcp.py "$LOCAL_BIN/local-llm-mcp.py"

# User scope (~/.claude.json) so every project sees it. `claude mcp add`
# refuses a name that already exists, so this is remove-then-add; the
# server's defaults (model local-llm, host 127.0.0.1:11434) match the above.
log "Register local-llm in Claude Code (user scope)"
claude mcp remove -s user "$ALIAS" >/dev/null 2>&1 || true
claude mcp add -s user -t stdio "$ALIAS" -- "$LOCAL_BIN/mcp" run "$LOCAL_BIN/local-llm-mcp.py"

# All-local Claude Code session. Ollama's Anthropic-compatible endpoint takes
# the place of api.anthropic.com for this process only; the three
# ANTHROPIC_DEFAULT_* pins make the sonnet/haiku/opus aliases (settings.json's
# "model", background tasks, subagents) resolve to the alias tag instead of a
# Claude ID the local server doesn't have. The two CLAUDE_CODE_ vars strip
# the beta headers/fields a non-Anthropic upstream rejects and the
# telemetry/update traffic that has no business in a local session.
# CLAUDE_CODE_MAX_CONTEXT_TOKENS: an ID Claude Code doesn't recognise is
# assumed to have a 200K window; this declares the alias's real one so
# proactive compaction fires before Ollama truncates (docs: model-config,
# "Correct the window for a gateway or custom model ID").
log "claude-local wrapper → $LOCAL_BIN/claude-local"
cat >"$LOCAL_BIN/claude-local" <<EOF
#!/usr/bin/env bash
# Claude Code against the local Ollama model ($ALIAS) — written by scripts/macos/update-llm.sh.
export ANTHROPIC_BASE_URL=http://127.0.0.1:11434
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=
export ANTHROPIC_MODEL=$ALIAS
export ANTHROPIC_DEFAULT_SONNET_MODEL=$ALIAS
export ANTHROPIC_DEFAULT_HAIKU_MODEL=$ALIAS
export ANTHROPIC_DEFAULT_OPUS_MODEL=$ALIAS
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=$NUM_CTX
exec claude "\$@"
EOF
chmod 0755 "$LOCAL_BIN/claude-local"

ollama --version
ollama show "$ALIAS" | grep -E 'quantization|context length|num_ctx|parameters' | head -4
mcp version
claude mcp list 2>/dev/null | grep "^$ALIAS:"
