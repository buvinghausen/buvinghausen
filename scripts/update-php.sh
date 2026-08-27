#!/usr/bin/env bash
# Updates PHP via phpenv/php-build: pulls the latest php-build definitions,
# installs the newest stable PHP, removes the superseded global build once
# the new one is active, and rebuilds cargo-php against it (it links against
# the active php-config, so a PHP rebuild invalidates the old binary).
#
# Host PHP here isn't for general PHP development — it's the build/test
# target for Rust-backed native extensions (ext-php-rs), part of the
# write-in-Rust/wrap-per-language polyglot work. See TOOLCHAIN.md's PHP
# section for the verified ext-php-rs smoke test and why WASM PHP was
# skipped in favor of this native path.
#
# Bootstraps phpenv + php-build itself when missing (fresh machine / fresh
# distro), transcribed verbatim from TOOLCHAIN.md's PHP section so both
# paths never drift apart. Fedora/dnf-specific, matching this box; substitute
# package manager for other distros per TOOLCHAIN.md.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

export PHPENV_ROOT="$HOME/.phpenv"
if [[ ! -d "$PHPENV_ROOT" ]]; then
	log "phpenv not found — bootstrapping (see TOOLCHAIN.md)"

	log "PHP build dependencies"
	sudo dnf install -y git make gcc gcc-c++ binutils glibc-devel autoconf libtool bison re2c automake \
		libxml2-devel bzip2-devel libcurl-devel libffi-devel gmp-devel libicu-devel openldap-devel \
		oniguruma-devel openssl-devel readline-devel libsodium-devel libzip-devel libpng-devel \
		libjpeg-turbo-devel libwebp-devel sqlite-devel libtidy-devel libxslt-devel clang-devel

	log "phpenv + php-build"
	git clone https://github.com/phpenv/phpenv.git "$PHPENV_ROOT"
	git clone https://github.com/php-build/php-build "$PHPENV_ROOT/plugins/php-build"

	append_bashrc_once "# phpenv" <<EOF

# phpenv
export PATH="$PHPENV_ROOT/bin:\$PATH"
eval "\$(phpenv init -)"
EOF
fi
export PATH="$PHPENV_ROOT/bin:$PATH"
eval "$(phpenv init -)"
require_cmd phpenv "phpenv install failed — check the clone output above"

log "php-build definitions update"
git -C "$PHPENV_ROOT/plugins/php-build" pull --ff-only

PHP_PREV=$(phpenv version-name 2>/dev/null || true)
PHP_LATEST=$(phpenv install --list | grep -vE 'snapshot|alpha|beta|RC' | tail -1 | xargs)

log "PHP ${PHP_LATEST}"
phpenv install -s "${PHP_LATEST}"
phpenv global "${PHP_LATEST}"
phpenv rehash

if [[ -n "$PHP_PREV" && "$PHP_PREV" != "$PHP_LATEST" && "$PHP_PREV" != "system" ]]; then
	log "Removing superseded build: $PHP_PREV"
	phpenv uninstall -f "$PHP_PREV"
fi

log "cargo-php (rebuild against the active PHP)"
cargo install cargo-php --locked --force

php --version
cargo-php --version
