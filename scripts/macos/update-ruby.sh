#!/usr/bin/env bash
# Updates Ruby via rbenv/ruby-build: pulls the latest ruby-build definitions,
# installs the newest patch of every ABI series the polyglot CI builds
# against, sets the primary as global, and removes every other build. Darwin
# twin of scripts/update-ruby.sh — read that header for why there is more than
# one Ruby (RUBY_COMPAT_SERIES is the local twin of HyperUuid ci.yml's
# ruby_compat_version) and for the prune policy.
#
# Darwin differences: build deps from Homebrew (ruby-build finds Homebrew's
# openssl@3/readline/libyaml/gmp itself), the zsh form of `rbenv init` in
# ~/.zshrc, and rbspy's aarch64-apple-darwin release binary into ~/.local/bin.
# YJIT still needs rustc at configure time — rustup's, sourced explicitly.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

RUBY_COMPAT_SERIES=(3.4)

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
require_cmd rustc "rustc not found — run the rust module first (YJIT needs it at configure time, see TOOLCHAIN-macos.md)"

export RBENV_ROOT="$HOME/.rbenv"
if [[ ! -d "$RBENV_ROOT" ]]; then
	log "rbenv not found — bootstrapping (see TOOLCHAIN-macos.md)"

	log "Build dependencies (shared Homebrew list, see lib-macos.sh)"
	brew_build_deps

	log "rbenv + ruby-build"
	git clone https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
	git clone https://github.com/rbenv/ruby-build.git "$RBENV_ROOT/plugins/ruby-build"

	append_zshrc_once "# rbenv" <<EOF2

# rbenv
export PATH="$RBENV_ROOT/bin:\$PATH"
eval "\$(rbenv init - --no-rehash zsh)"
EOF2
fi
export PATH="$RBENV_ROOT/bin:$PATH"
eval "$(rbenv init - --no-rehash bash)"
require_cmd rbenv "rbenv install failed — check the clone output above"

log "ruby-build definitions update"
git -C "$RBENV_ROOT/plugins/ruby-build" pull --ff-only

CRUBY_LIST=$(rbenv install --list | grep -vE 'jruby|mruby|picoruby|truffleruby' | xargs -n1)
RUBY_PRIMARY=$(tail -1 <<<"$CRUBY_LIST")
RUBY_KEEP=("$RUBY_PRIMARY")
for series in "${RUBY_COMPAT_SERIES[@]}"; do
	v=$(grep -E "^${series//./\\.}\." <<<"$CRUBY_LIST" | tail -1 || true)
	[[ -n "$v" ]] || { echo "Ruby ${series}.x is no longer in \`rbenv install --list\` (EOL?) — remove it from RUBY_COMPAT_SERIES" >&2; exit 1; }
	[[ "$v" == "$RUBY_PRIMARY" ]] || RUBY_KEEP+=("$v")
done

for v in "${RUBY_KEEP[@]}"; do
	log "Ruby $v"
	rbenv install -s "$v"
done
rbenv global "$RUBY_PRIMARY"
rbenv rehash

log "Pruning Ruby builds outside the kept set (${RUBY_KEEP[*]}; global $RUBY_PRIMARY)"
while IFS= read -r v; do
	[[ " ${RUBY_KEEP[*]} " == *" $v "* ]] && continue
	echo "  $v"
	rbenv uninstall -f "$v"
done < <(rbenv versions --bare)

# rbspy: one release binary outside rbenv profiles whichever interpreter it is
# pointed at and survives the rebuilds above. macOS note: attaching to a
# running process needs sudo (SIP) — `rbspy record -- ruby x.rb` does not.
log "rbspy (profiler)"
RBSPY_LATEST=$(github_latest_release rbspy/rbspy)
RBSPY_CURRENT=$(rbspy --version 2>/dev/null | awk '{print $2}' || true)
if [[ "$RBSPY_CURRENT" == "$RBSPY_LATEST" ]]; then
	echo "rbspy already at $RBSPY_CURRENT — skipping"
else
	RBSPY_PKG="rbspy-$(uname -m | sed 's/arm64/aarch64/')-apple-darwin"
	install_from_tarball_local "https://github.com/rbspy/rbspy/releases/download/v${RBSPY_LATEST}/${RBSPY_PKG}.tar.gz" \
		"$RBSPY_PKG" "$LOCAL_BIN/rbspy"
fi

for v in "${RUBY_KEEP[@]}"; do
	RBENV_VERSION="$v" ruby --version
done
gem --version
rbspy --version
