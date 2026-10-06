#!/usr/bin/env bash
# Updates Ruby via rbenv/ruby-build: pulls the latest ruby-build definitions,
# installs the newest patch of every ABI series the polyglot CI builds
# against, sets the primary as global, and removes every other build.
#
# Host Ruby here isn't for general Ruby development — it's the build/test
# target for Rust-backed Ruby bindings, part of the write-in-Rust/wrap-per-
# language polyglot work: the compiled Magnus (rb-sys) extension and the
# Fiddle fallback that HyperUuid ships. See TOOLCHAIN.md's Ruby section.
#
# WHY MORE THAN ONE RUBY: a Magnus extension is bound to one Ruby minor (no
# abi3 equivalent), so SkunkWerkx/.github's hyper-build-native.yml builds and
# tests it once per ABI — `ruby_version` (its default, the current release)
# plus the caller's optional `ruby_compat_version`. HyperUuid's ci.yml sets
# ruby_compat_version "3.4" and its ruby/Rakefile lists ABIS %w[3.4 4.0], so
# reproducing a CI leg locally needs both Rubies installed at once. The
# primary is always the newest stable CRuby ruby-build knows; the compat
# series are listed here, and this list is the local twin of that ci.yml
# input — when 3.4 goes EOL (2028-03-31) and leaves ci.yml, drop it here too
# and the next pass uninstalls it.
#
# Prune policy is per series, like update-jvm.sh: within a kept series only
# the newest patch survives; any series not kept goes entirely.
#
# Bootstraps rbenv + ruby-build itself when missing (fresh machine / fresh
# distro), transcribed from TOOLCHAIN.md's Ruby section so both paths never
# drift apart.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

RUBY_COMPAT_SERIES=(3.4)

# YJIT is compiled at `rbenv install` time and needs rustc on PATH. That is
# rustup's rustc, on purpose — the rust module runs before this one in
# update-toolchain.sh — not the Fedora `rust` rpm ruby-build's wiki suggests,
# so the toolchain that builds Ruby is the one `rustup update` keeps current.
# Sourced explicitly rather than trusting the caller's PATH.
if [[ -f "$HOME/.cargo/env" ]]; then
	source "$HOME/.cargo/env"
fi
require_cmd rustc "rustc not found — run the rust module first (YJIT needs it at configure time, see TOOLCHAIN.md)"

export RBENV_ROOT="$HOME/.rbenv"
if [[ ! -d "$RBENV_ROOT" ]]; then
	log "rbenv not found — bootstrapping (see TOOLCHAIN.md)"

	log "Build dependencies (shared dnf list, see lib.sh)"
	dnf_build_deps

	log "rbenv + ruby-build"
	git clone https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
	git clone https://github.com/rbenv/ruby-build.git "$RBENV_ROOT/plugins/ruby-build"

	append_bashrc_once "# rbenv" <<EOF

# rbenv
export PATH="$RBENV_ROOT/bin:\$PATH"
eval "\$(rbenv init - --no-rehash bash)"
EOF
fi
export PATH="$RBENV_ROOT/bin:$PATH"
eval "$(rbenv init - --no-rehash bash)"
require_cmd rbenv "rbenv install failed — check the clone output above"

log "ruby-build definitions update"
git -C "$RBENV_ROOT/plugins/ruby-build" pull --ff-only

# `rbenv install --list` prints exactly one line per maintained series — its
# newest patch — so the primary is the last CRuby line and each compat series
# is the line with that prefix. A compat series missing from the list has
# left ruby-build's maintained set (EOL): fail loudly so the list above gets
# trimmed on purpose rather than silently building nothing for it.
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

# rbspy: sampling profiler for Ruby. A standalone release binary rather than
# a gem on purpose — a gem (stackprof, vernier) would have to be reinstalled
# into every kept Ruby after each rebuild above, where one binary outside
# rbenv profiles whichever interpreter it is pointed at and survives them all.
log "rbspy (profiler)"
RBSPY_LATEST=$(github_latest_release rbspy/rbspy)
RBSPY_CURRENT=$(rbspy --version 2>/dev/null | awk '{print $2}' || true)
if [[ "$RBSPY_CURRENT" == "$RBSPY_LATEST" ]]; then
	echo "rbspy already at $RBSPY_CURRENT — skipping"
else
	RBSPY_PKG="rbspy-$(uname -m)-unknown-linux-gnu"
	install_from_tarball "https://github.com/rbspy/rbspy/releases/download/v${RBSPY_LATEST}/${RBSPY_PKG}.tar.gz" \
		"$RBSPY_PKG" /usr/local/bin/rbspy
fi

for v in "${RUBY_KEEP[@]}"; do
	RBENV_VERSION="$v" ruby --version
done
gem --version
rbspy --version
