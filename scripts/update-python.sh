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
# verbatim (dnf build deps, pyenv.run installer, ~/.bashrc block) so both
# paths never drift apart. Fedora/dnf-specific, matching this box; substitute
# package manager for other distros per TOOLCHAIN.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export PYENV_ROOT="$HOME/.pyenv"
if [[ ! -d "$PYENV_ROOT/bin" ]]; then
	log "pyenv not found — bootstrapping (see TOOLCHAIN.md)"

	log "pyenv build dependencies"
	sudo dnf install -y make gcc zlib-devel bzip2 bzip2-devel readline-devel \
		sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel gawk

	log "pyenv installer"
	curl https://pyenv.run | bash

	cat >>"$HOME/.bashrc" <<'EOF'

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

python --version
python -c "import sys; print('GIL enabled:', sys._is_gil_enabled())"
