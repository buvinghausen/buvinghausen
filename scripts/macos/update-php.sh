#!/usr/bin/env bash
# PHP from Homebrew, not phpenv/php-build: the formula is the newest stable
# PHP, its configure line already carries --with-ffi (the one flag the Fedora
# module has to add by hand — HyperUuid's PHP binding dlopens the Rust cdylib
# through PHP's FFI extension), it ships php-config and the Zend headers
# cargo-php/ext-php-rs link against, and its pecl is wired to install outside
# the Cellar so Xdebug survives a `brew upgrade php`. Homebrew keeps one php,
# so there is no superseded build to prune.
#
# Host PHP here isn't for general PHP development — same purpose as on Fedora:
# the build/test target for Rust-backed native code (ext-php-rs via cargo-php,
# and PHP FFI). See TOOLCHAIN-macos.md's PHP section.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib-macos.sh

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
require_cmd cargo "cargo not found — run the rust module first (cargo-php is a cargo install, see TOOLCHAIN-macos.md)"

# Composer is what supplies the per-repo gates (`vendor/bin/phpcs`,
# `vendor/bin/phpunit`, `vendor/bin/phpbench`). php-build bundles it into
# every PHP it builds on Fedora; Homebrew's php does not, so it's its own
# formula here.
log "PHP + Composer (Homebrew)"
brew_ensure php composer

# Xdebug is the profiler (XDEBUG_MODE=profile → cachegrind.out.*); php-build
# bundles it on Fedora, Homebrew's php does not — pecl does. `pecl install`
# refuses to reinstall an installed extension (exit 1), so it is keyed on
# whether PHP already loads it. Asked in-process rather than via
# `php -m | grep -q`: under pipefail, grep -q exits on the first match and
# php then dies on the closed pipe (exit 255) — observed 5 runs out of 6 on
# the replay, which sent the pass into `pecl install` and the exit 1 above.
log "Xdebug (pecl)"
if php -r 'exit(extension_loaded("xdebug") ? 0 : 1);'; then
	echo "xdebug already loaded"
else
	pecl install xdebug
fi

# cargo-php links against the active php-config, so it is rebuilt against
# whatever `brew upgrade php` just produced — same as the Fedora module.
log "cargo-php (rebuild against the active PHP)"
cargo install cargo-php --locked --force

php --version
php -m | grep -i ffi
php -m | grep -i xdebug
php-config --version
composer --version
cargo-php --version
