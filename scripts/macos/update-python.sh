#!/usr/bin/env bash
# Updates Python via pyenv (standard + free-threaded builds) and removes the
# superseded global build once the new one is active. Darwin twin of
# scripts/update-python.sh — read that header for the flavor-preservation
# policy (standard/GIL-enabled is the global default; free-threaded `t` is
# opt-in via `pyenv local`/`pyenv shell`).
#
# Darwin differences: build deps from Homebrew (python-build finds Homebrew's
# openssl@3/readline/sqlite/xz/zlib itself); ~/.zshrc; no tcl-tk (Homebrew's
# tcl-tk@8 is deprecated and nothing here needs tkinter — pyenv builds without
# it and says so in its warnings). py-spy's arm64 wheel installs fine, but
# attaching to a running process needs sudo on macOS (SIP); `py-spy record --
# python x.py` does not.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

export PYENV_ROOT="$HOME/.pyenv"
if [[ ! -d "$PYENV_ROOT/bin" ]]; then
	log "pyenv not found — bootstrapping (see TOOLCHAIN-macos.md)"

	log "Build dependencies (shared Homebrew list, see lib-macos.sh)"
	brew_build_deps

	log "pyenv installer"
	curl https://pyenv.run | bash

	append_zshrc_once "# pyenv" <<'EOF2'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

# GIL enabled by default (yt-dlp and other GIL-dependent tools need it).
# Flip to free-threaded for testing: export PYTHON_GIL=0
EOF2
fi
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"

log "pyenv update"
pyenv update

PYTHON_PREV=$(cat "$PYENV_ROOT/version" 2>/dev/null || true)
PYTHON_LATEST=$(pyenv latest -k 3)

log "Python ${PYTHON_LATEST} (standard + free-threaded)"
pyenv install -s "${PYTHON_LATEST}"
pyenv install -s "${PYTHON_LATEST}t"

if [[ "$PYTHON_PREV" == *t ]]; then
	PYTHON_NEW_GLOBAL="${PYTHON_LATEST}t"
	export PYTHON_GIL=0
else
	PYTHON_NEW_GLOBAL="${PYTHON_LATEST}"
fi
pyenv global "${PYTHON_NEW_GLOBAL}"

if [[ -n "$PYTHON_PREV" && "$PYTHON_PREV" != "$PYTHON_NEW_GLOBAL" ]]; then
	log "Removing superseded build: $PYTHON_PREV"
	pyenv uninstall -f "$PYTHON_PREV"
fi

# Pyodide's interpreter series, beside the global: pyodide-build only builds
# for the Python minor its Pyodide release embeds, and the host interpreter
# has to be that minor (the Forge's hyper-build-wheels.yml pins
# PYODIDE_VERSION 314.0.7 on python-version "3.14"). Edit it when that pin's
# minor moves. pyodide-build goes into this build's own site-packages, not the
# global's; the per-release xbuildenv and its Emscripten are fetched per run
# by `pyodide xbuildenv install`, as the Forge does. Superseded patches within
# the series are removed once the newest is in.
PYTHON_PYODIDE_SERIES=3.14
PYTHON_PYODIDE=$(pyenv latest -k "$PYTHON_PYODIDE_SERIES")
log "Python ${PYTHON_PYODIDE} (Pyodide's series) + pyodide-build"
pyenv install -s "$PYTHON_PYODIDE"
PYENV_VERSION="$PYTHON_PYODIDE" python -m pip install --upgrade pip pyodide-build
while IFS= read -r v; do
	[[ "$v" == "$PYTHON_PYODIDE" ]] && continue
	echo "  removing superseded $v (kept $PYTHON_PYODIDE)"
	pyenv uninstall -f "$v"
done < <(pyenv versions --bare | grep -E "^${PYTHON_PYODIDE_SERIES//./\\.}\.[0-9]+\$" || true)

# openpyxl: HyperTabular's corpus/workbook/make_fixtures.py writes the committed
# .xlsx fixtures with it (regeneration only; the test suites read the files).
log "maturin / pytest / ruff / mypy / pyperf / py-spy / openpyxl"
pip install --upgrade pip maturin pytest ruff mypy pyperf py-spy openpyxl

python --version
python -c "import sys; print('GIL enabled:', sys._is_gil_enabled())"
ruff --version
mypy --version
python -c "import pyperf; print('pyperf', pyperf.__version__)"
py-spy --version
python -c "import openpyxl; print('openpyxl', openpyxl.__version__)"
PYENV_VERSION="$PYTHON_PYODIDE" python --version
PYENV_VERSION="$PYTHON_PYODIDE" pyodide --version
