#!/usr/bin/env bash
# Updates Ruby via rbenv/ruby-build: pulls the latest ruby-build definitions,
# installs the newest stable CRuby, and removes the superseded global build
# once the new one is active — same prune-after-switch shape as update-python.sh.
#
# Host Ruby here isn't for general Ruby development — it's the build/test
# target for Rust-backed native extensions (rb-sys/magnus), part of the
# write-in-Rust/wrap-per-language polyglot work. See TOOLCHAIN.md's Ruby
# section for the verified rb-sys/magnus smoke test.
#
# Bootstraps rbenv + ruby-build itself when missing (fresh machine / fresh
# distro), transcribed verbatim from TOOLCHAIN.md's Ruby section so both
# paths never drift apart. Fedora/dnf-specific, matching this box; substitute
# package manager for other distros per TOOLCHAIN.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export RBENV_ROOT="$HOME/.rbenv"
if [[ ! -d "$RBENV_ROOT" ]]; then
	log "rbenv not found — bootstrapping (see TOOLCHAIN.md)"

	log "Ruby build dependencies"
	sudo dnf install -y autoconf gcc rust patch make bzip2 openssl-devel libyaml-devel libffi-devel \
		readline-devel gdbm-devel ncurses-devel perl-FindBin zlib-ng-compat-devel

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

RUBY_PREV=$(rbenv version-name 2>/dev/null || true)
RUBY_LATEST=$(rbenv install --list | grep -vE 'jruby|mruby|picoruby|truffleruby' | tail -1 | xargs)

log "Ruby ${RUBY_LATEST}"
rbenv install -s "${RUBY_LATEST}"
rbenv global "${RUBY_LATEST}"
rbenv rehash

if [[ -n "$RUBY_PREV" && "$RUBY_PREV" != "$RUBY_LATEST" && "$RUBY_PREV" != "system" ]]; then
	log "Removing superseded build: $RUBY_PREV"
	rbenv uninstall -f "$RUBY_PREV"
fi

ruby --version
gem --version
