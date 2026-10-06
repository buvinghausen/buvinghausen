#!/usr/bin/env bash
# Updates Python via pyenv (standard + free-threaded builds) and removes the
# superseded global build once the new one is active. Preserves whichever
# flavor (standard vs free-threaded `t`) is currently set as global rather
# than forcing one — TOOLCHAIN.md documents standard/GIL-enabled as the
# current default (yt-dlp needs the GIL); free-threaded is opt-in via
# `pyenv local`/`pyenv shell` for testing.
#
# Bootstraps pyenv itself when missing (fresh machine / fresh distro), rather
# than hard-failing like the other update-*.sh scripts do — this is the
# install entry point TOOLCHAIN.md's Python section documents, transcribed
# (pyenv.run installer, ~/.bashrc block; build deps come from lib.sh) so both
# paths never drift apart. Fedora/dnf-specific, matching this box; substitute
# package manager for other distros per TOOLCHAIN.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export PYENV_ROOT="$HOME/.pyenv"
if [[ ! -d "$PYENV_ROOT/bin" ]]; then
	log "pyenv not found — bootstrapping (see TOOLCHAIN.md)"

	log "Build dependencies (shared dnf list, see lib.sh)"
	dnf_build_deps

	log "pyenv installer"
	curl https://pyenv.run | bash

	append_bashrc_once "# pyenv" <<'EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# GIL enabled by default (yt-dlp and other GIL-dependent tools need it).
# Flip to free-threaded for testing: export PYTHON_GIL=0
EOF
fi
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

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

# Build/test/lint tooling for the Python bindings of the Rust-core projects
# (HyperUuid: pyo3 abi3 extension built with maturin, pytest suite, ruff
# lint + `ruff format`), plus the rest of what those bindings' extras and CI
# name: mypy (the `test` extra — tests/test_typing.py skips without it),
# pyperf (the `bench` extra — what bench_*.py are written against), and py-spy
# (sampling profiler; attaches from outside, no code changes to the target).
# Installed into the pyenv global build, so this runs on every pass — the
# uninstall above discards the superseded build's site-packages along with it.
log "maturin / pytest / ruff / mypy / pyperf / py-spy"
pip install --upgrade pip maturin pytest ruff mypy pyperf py-spy

python --version
python -c "import sys; print('GIL enabled:', sys._is_gil_enabled())"
ruff --version
mypy --version
# pyperf's CLI has no version flag — ask the module.
python -c "import pyperf; print('pyperf', pyperf.__version__)"
py-spy --version
