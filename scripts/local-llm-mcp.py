#!/usr/bin/env python3
"""local-llm — an MCP server that hands grunt work to the Ollama model on this
box so the frontier model in the Claude Code session doesn't spend its tokens
on it.  Two tools:

  local_llm        — one prompt in, text out.
  local_llm_files  — the server reads the files itself, so their contents
                     never enter the frontier model's context; only the
                     local model's answer comes back.

Runs under the pipx `mcp` venv (`mcp run local-llm-mcp.py`): stdlib + the
mcp SDK only.  Talks to Ollama's native /api/chat (not the Anthropic shim),
so num_ctx and `think` are honoured as sent.  Config is environment:

  LOCAL_LLM_MODEL     Ollama tag to use           (default: local-llm)
  LOCAL_LLM_HOST      Ollama base URL             (default: http://127.0.0.1:11434)
  LOCAL_LLM_MAX_BYTES cap on total file bytes per local_llm_files call
                                                  (default: 400000 ≈ 100K tokens)
"""
import json
import os
import pathlib
import urllib.error
import urllib.request

from mcp.server import MCPServer
from mcp.server.mcpserver.exceptions import ToolError  # its text reaches the model; a bare exception's does not

MODEL = os.environ.get("LOCAL_LLM_MODEL", "local-llm")
HOST = os.environ.get("LOCAL_LLM_HOST", "http://127.0.0.1:11434").rstrip("/")
MAX_BYTES = int(os.environ.get("LOCAL_LLM_MAX_BYTES", "400000"))
TIMEOUT_S = 1800  # a 64K-token prompt takes minutes to prefill on an M-series base chip

mcp = MCPServer(
    "local-llm",
    instructions=(
        "Tools that run a local open-weight model on this machine. Use them for work "
        "that is mechanical or high-volume and does not need frontier-level judgment: "
        "summarising files or logs, first-draft tests and boilerplate, extracting facts "
        "from large documents, classifying or reformatting text. Prefer local_llm_files "
        "when the input is on disk — the file contents then never enter your own context. "
        "Keep architecture, debugging of subtle bugs, and final review for yourself."
    ),
)


def _chat(messages, max_tokens, think):
    body = {
        "model": MODEL,
        "messages": messages,
        "stream": False,
        "think": think,
        "options": {"num_predict": max_tokens},
    }
    req = urllib.request.Request(
        f"{HOST}/api/chat",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:  # Ollama answered: unknown model, bad request — its body says which
        detail = e.read().decode("utf-8", errors="replace").strip()
        raise ToolError(f"Ollama rejected the request (HTTP {e.code}): {detail or e.reason}") from e
    except urllib.error.URLError as e:  # nothing answered
        raise ToolError(f"Ollama at {HOST} unreachable ({e.reason}). Is `ollama serve` running?") from e
    msg = d.get("message", {})
    text = (msg.get("content") or "").strip()
    if not text:
        raise ToolError(f"{MODEL} returned no text (done_reason={d.get('done_reason')!r})")
    usage = f"\n\n[local-llm: {MODEL}, prompt {d.get('prompt_eval_count', '?')} tok, output {d.get('eval_count', '?')} tok]"
    return text + usage


@mcp.tool()
def local_llm(prompt: str, system: str = "", max_tokens: int = 2048, think: bool = False) -> str:
    """Send one prompt to the local model and return its reply.

    Args:
        prompt: The task, with any input text inlined.
        system: Optional system prompt (role, format constraints).
        max_tokens: Cap on the reply length.
        think: Let the model reason before answering. Slower; use for anything non-trivial.
    """
    messages = ([{"role": "system", "content": system}] if system else []) + [
        {"role": "user", "content": prompt}
    ]
    return _chat(messages, max_tokens, think)


@mcp.tool()
def local_llm_files(paths: list[str], instruction: str, max_tokens: int = 2048, think: bool = False) -> str:
    """Read files from disk, send them with an instruction to the local model, return its reply.

    The file contents go to the local model only — they never enter the calling
    model's context. Use for summarising, extracting from, or drafting against
    files that would be expensive to read directly.

    Args:
        paths: Absolute paths of regular files to include (total size capped by LOCAL_LLM_MAX_BYTES).
        instruction: What to do with them.
        max_tokens: Cap on the reply length.
        think: Let the model reason before answering.
    """
    parts, total = [], 0
    for p in paths:
        path = pathlib.Path(p)
        if not path.is_absolute():
            raise ToolError(f"{p}: paths must be absolute")
        if not path.is_file():
            raise ToolError(f"{p}: not a regular file")
        data = path.read_bytes()
        total += len(data)
        if total > MAX_BYTES:
            raise ToolError(f"total input exceeds LOCAL_LLM_MAX_BYTES={MAX_BYTES} at {p}; split the call")
        parts.append(f"===== {path} =====\n{data.decode('utf-8', errors='replace')}\n")
    prompt = "".join(parts) + f"\n===== INSTRUCTION =====\n{instruction}"
    return _chat([{"role": "user", "content": prompt}], max_tokens, think)


if __name__ == "__main__":
    mcp.run()
