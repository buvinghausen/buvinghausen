#!/usr/bin/env bash
# Updates Python via pyenv (standard + free-threaded builds) and removes the
# superseded free-threaded global build once the new one is active. The
# paired standard (non-t) build is left alone — TOOLCHAIN.md keeps it around
# on purpose for `pyenv local` compatibility testing.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export PYENV_ROOT="$HOME/.pyenv"
if [[ ! -d "$PYENV_ROOT/bin" ]]; then
	echo "pyenv not found — run the Python install steps in TOOLCHAIN.md first" >&2
	exit 1
fi
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
export PYTHON_GIL=0

log "pyenv update"
pyenv update

PYTHON_PREV=$(cat "$PYENV_ROOT/version" 2>/dev/null || true)
PYTHON_LATEST=$(pyenv latest 3)

log "Python ${PYTHON_LATEST} (standard + free-threaded)"
pyenv install -s "${PYTHON_LATEST}"
pyenv install -s "${PYTHON_LATEST}t"
pyenv global "${PYTHON_LATEST}t"

if [[ -n "$PYTHON_PREV" && "$PYTHON_PREV" == *t && "$PYTHON_PREV" != "${PYTHON_LATEST}t" ]]; then
	log "Removing superseded free-threaded build: $PYTHON_PREV"
	pyenv uninstall -f "$PYTHON_PREV"
fi

python --version
python -c "import sys; print('GIL enabled:', sys._is_gil_enabled())"
