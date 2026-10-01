# toolchain.md — WSL2 Polyglot Dev Environment

**Machine:** Microsoft Surface Snapdragon (aarch64)
**OS:** Windows 11 + WSL2 (Fedora, aarch64)
**Shell:** bash

All languages, compilers, and build tools live in WSL2. Windows is the display layer only. The polyglot toolchain never escapes WSL2.

> **Architecture note:** All install scripts auto-detect architecture at runtime — arm64 (Snapdragon) and amd64 (x86_64) are both supported without modification.

> **Editorial note:** the Snapdragon has been genuinely great silicon for this setup — no complaints on perf or battery running a full polyglot WSL2 toolchain.

> **Distro note:** The `dnf` dependency block is the only Fedora-specific section. For other distros substitute `apt`, `pacman`, etc. for the same package list. Everything else is distro-independent.

---

## Base Dependencies

The one `dnf` list every from-source build in this doc draws on. It used to be five — this block plus a separate prerequisite list at the top of the [Python](#python), [Swift](#swift), [Ruby](#ruby) and [PHP](#php) sections, each overlapping this one and each other (the pyenv list was a strict subset of this block already). They're folded together here, grouped by who needs what, so there is exactly one place to add a header and one function (`dnf_build_deps` in `scripts/lib.sh`) that both `update-base.sh` and each language module's first-time bootstrap call:

```bash
sudo dnf update -y
sudo dnf install -y \
  curl wget git gcc gcc-c++ make patch gawk binutils glibc-devel \
  autoconf automake libtool bison re2c \
  openssl-devel zlib-devel zlib-ng-compat-devel bzip2 bzip2-devel xz xz-devel \
  readline-devel libedit-devel ncurses-devel gdbm-devel sqlite sqlite-devel \
  libffi-devel libuuid-devel tk-devel libyaml-devel perl-FindBin \
  libxml2-devel libxslt-devel libcurl-devel libicu-devel gmp-devel openldap-devel \
  oniguruma-devel libsodium-devel libzip-devel libpng-devel libjpeg-turbo-devel \
  libwebp-devel libtidy-devel clang-devel python3-devel zip unzip
```

Who needs what (every line is the union of these, deduplicated):

- **Everything / cargo builds:** `curl wget git gcc gcc-c++ make patch gawk`.
- **pyenv** ([suggested build environment](https://github.com/pyenv/pyenv/wiki#suggested-build-environment)): `zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel`.
- **ruby-build** ([suggested build environment](https://github.com/rbenv/ruby-build/wiki#suggested-build-environment), Fedora 40+ variant): `autoconf libyaml-devel gdbm-devel ncurses-devel perl-FindBin zlib-ng-compat-devel` on top of the shared compiler/ssl/readline/ffi set. The wiki also lists `rust` (YJIT is compiled at configure time and needs `rustc`); deliberately *not* installed from dnf here — that would be a second Rust on the box next to rustup's, and rustup is the one that stays current. `scripts/update-ruby.sh` sources `~/.cargo/env` before `rbenv install` so ruby-build finds rustup's `rustc` regardless of the caller's `PATH`; the [Rust](#rust) section must be done first (it is, in the Full Update Pass order). The `rust` rpm that the earlier list had pulled in was removed 2026-09-02.
- **php-build** ([php.watch's compile-from-source guide](https://php.watch/articles/compile-php-fedora-rhel-centos), plus `libtidy-devel`/`libxslt-devel` which that guide omits but the default `./configure` needs — confirmed by running it, see the PHP section's Verified note): `binutils glibc-devel libtool bison re2c automake libxml2-devel libcurl-devel gmp-devel libicu-devel openldap-devel oniguruma-devel libsodium-devel libzip-devel libpng-devel libjpeg-turbo-devel libwebp-devel libtidy-devel libxslt-devel`. `clang-devel` isn't a PHP build dependency — it's there for `bindgen` (used by `ext-php-rs-build` and `rb-sys`) to find `libclang`.
- **swiftly** (per swift.org's Fedora tarball instructions): `libedit-devel python3-devel zip unzip` on top of `binutils libcurl-devel libicu-devel libuuid-devel libxml2-devel sqlite-devel` shared with the others.

> **Note:** `scripts/update-base.sh` (the `base` module in the [Full Update Pass](#full-update-pass)) runs the `dnf install` line above on every pass — idempotent, fast no-op once installed. It deliberately skips the `dnf update -y` line: a blanket system-wide package upgrade is a much bigger, less predictable action than installing a fixed dependency list, so that stays a manual step you run yourself when you want it.

---

## Node.js

Install fnm (fast node manager) and Node.js Krypton LTS (24.x):

```bash
curl -fsSL https://fnm.vercel.app/install | bash
source ~/.bashrc
fnm install --lts
fnm use lts-latest
fnm default lts-latest
```

Update npm to latest:

```bash
npm install -g npm@latest
```

**Updating Node.js:**

```bash
fnm install --lts && fnm default lts-latest
```

---

## TypeScript

Install the Go-native compiler (7.x) rather than the JavaScript-based compiler. The Go compiler delivers significantly faster type-checking on large codebases:

```bash
npm install -g typescript@latest
```

> **Note:** TypeScript 7.0 hit GA on 2026-07-08 — `latest` now resolves to the Go-native compiler directly. The old `@rc` pin used during the prerelease period is retired: npm's `rc` dist-tag is frozen on the stale `7.0.1-rc` since nobody publishes to it post-GA, so keeping that pin would silently install *behind* stable rather than ahead of it. If a future major briefly ships a next-gen compiler under `@rc`/`@next` again, re-pin deliberately and drop it the same way once it GAs.

**Updating TypeScript:**

```bash
npm install -g typescript@latest
```

---

## Go

Auto-detects architecture at install time:

```bash
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
wget https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz
sudo tar -C /usr/local -xzf ${GO_VERSION}.linux-${ARCH}.tar.gz
rm ${GO_VERSION}.linux-${ARCH}.tar.gz

cat >> ~/.bashrc << 'EOF'

# Go
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

source ~/.bashrc
go version
```

Install gopls (language server) and Delve (debugger) for JetBrains/GoLand:

```bash
go install golang.org/x/tools/gopls@latest
go install github.com/go-delve/delve/cmd/dlv@latest
go install github.com/mgechev/revive@latest   # linter (HyperUuid's CI lints with it)
```

**Updating Go:** Remove the old installation first, then re-run the install block above:

```bash
sudo rm -rf /usr/local/go
```

**GoLand config:**
- Settings → Go → GOROOT → `\\wsl.localhost\FedoraLinux-44\usr\local\go`
- **Delve (debugger):** GoLand bundles a `linux/amd64` `dlv` that fails on arm64 with `Exec format error`. There is no UI setting to override the path — replace the bundled binary after every GoLand update:

```powershell
# Run from PowerShell (or copy via Explorer)
Copy-Item "\\wsl.localhost\FedoraLinux-44\home\buvy\go\bin\dlv" "C:\Program Files\JetBrains\GoLand\plugins\go-plugin\lib\dlv\linux\dlv" -Force
```

---

## Java / Kotlin (SDKMAN)

Install SDKMAN:

```bash
curl -s "https://get.sdkman.io" | bash

cat >> ~/.bashrc << 'EOF'

# SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
EOF

source ~/.bashrc
```

Install latest LTS Java (Temurin) and Kotlin:

```bash
sdk install java
sdk install kotlin
```

> **Note:** `sdk install java` with no version specified installs the latest LTS Temurin release automatically — no version pinning required.

**Updating Java / Kotlin:**

```bash
sdk update && sdk upgrade
```

### GraalVM CE (native-image)

GraalVM Community Edition is a second `java` *version* under the same SDKMAN candidate — installed alongside the Temurin LTS, never made `current`. It's here for `native-image`: ahead-of-time compiling a JVM app to a standalone ELF executable. The `-graalce` identifier is the Community build; `-graal` is Oracle's own GraalVM build, which this setup does not use.

```bash
sdk install java 25.4.4.1+1-graalce     # answer "n" to "set as default?" — Temurin stays current
```

Select it per shell when you want it, or pin it per project:

```bash
sdk use java 25.4.4.1+1-graalce          # this shell only; `sdk use java 25.0.4-tem` to go back

echo "java=25.4.4.1+1-graalce" > .sdkmanrc && sdk env   # per project; `sdk env` re-reads it
```

`native-image` is in this build's `bin/` directly (there is no `gu` binary in it at all — no separate component install step), and the build below needed nothing beyond the [Base Dependencies](#base-dependencies) list: the resulting executable links against `libc` and `libz` only.

> **Why `sdk upgrade` can't manage this:** `sdk upgrade` compares what's installed against the candidate's single remote default (`25.0.4-tem`), and that's the whole check — a `-graalce` build is never offered, never upgraded, and would sit at the version you first installed forever. `scripts/update-jvm.sh` therefore resolves the newest `-graalce` in the Temurin default's major series itself (from the same `versions/all` API endpoint `sdk list` reads — pinned to the default's major, not "newest overall", so a non-LTS GraalVM never lands ahead of the LTS the rest of the JVM stack runs on), installs it when missing with an explicit `n` piped to the default prompt (an empty answer on a non-tty stdin means *yes*, which would silently flip `current` off Temurin), and lets the existing series-key prune (`25-graalce` competes only with other `-graalce` builds) retire the one it superseded.

> **Verified, 2026-09-04:** `Hello.java` → `javac` → `native-image -o hello Hello` under `25.3.4+1.r25-graalce` on this box: a 5.07 MiB stripped aarch64 PIE ELF, dynamically linked against only `libc`/`libz`, built in 36 s wall (3 min CPU), runs and prints `os.arch` = `aarch64`. Then the script path for real: `sdk uninstall java 25.3.4+1.r25-graalce`, `./update-toolchain.sh jvm` — it resolved the same identifier from the API, reinstalled it, answered the "set as default?" prompt itself, and `current` was still the Temurin symlink (mtime unchanged) afterwards; the rerun on top of that reported "already installed" and changed nothing.

> **Verified on x86_64, 2026-10-01:** the module isn't arch-specific — the API lookup is keyed on `$SDKMAN_PLATFORM` (set by `sdkman-init.sh`), and `versions/all` for both `linuxx64` and `linuxarm64` resolves the same newest Java 25 build, `25.4.4.1+1-graalce` (superseding `25.3.4+1.r25-graalce`, which the API no longer lists). On an x86_64 WSL2 box with only Temurin installed, `./update-toolchain.sh jvm` installed it alongside `25.0.4-tem`, answered the default prompt itself, and left `current` on Temurin; the rerun reported "already installed". `native-image -o hello Hello` under it: a 5.00 MiB stripped x86-64 PIE ELF, dynamically linked against only `libc`/`libm`/`libz`, built in 24 s wall (4 min CPU), runs and prints `os.arch` = `amd64`. `native-image --version` reports `25.0.4.1.1`, GraalVM CE `25.4.4.1.1+1.1` (`jvmci-25.4-b23`).

**IntelliJ config:** Settings → Build Tools → Gradle → Gradle JVM → `~/.sdkman/candidates/java/current`

---

## Gradle

```bash
sdk install gradle
```

> **Note:** For project work, prefer the Gradle wrapper (`./gradlew`) over the global install — it pins the Gradle version per project and is what IntelliJ uses when connecting via Gateway. The global install is for bootstrapping and one-off use outside a project context. Kotlin DSL (`build.gradle.kts`) is preferred over Groovy DSL.

**Updating Gradle:**

```bash
sdk update && sdk upgrade
```

---

## Python

Build dependencies are in [Base Dependencies](#base-dependencies) (the pyenv group). Install pyenv:

```bash
curl https://pyenv.run | bash

cat >> ~/.bashrc << 'EOF'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# GIL enabled by default (yt-dlp and other GIL-dependent tools need it).
# Flip to free-threaded for testing: export PYTHON_GIL=0
EOF

source ~/.bashrc
pyenv update
```

Install latest stable Python (standard + free-threaded builds), global defaults to the standard build:

```bash
PYTHON_LATEST=$(pyenv latest 3)
pyenv install ${PYTHON_LATEST}
pyenv install ${PYTHON_LATEST}t
pyenv global ${PYTHON_LATEST}
```

Verify:

```bash
python --version
python -c "import sys; print('GIL enabled:', sys._is_gil_enabled())"
```

Build, test, and lint tooling for Python bindings over a Rust core (HyperUuid: pyo3 abi3 extension via maturin, pytest suite, ruff lint):

```bash
pip install --upgrade pip maturin pytest ruff
```

> **Note:** these live in the global pyenv build's site-packages, so re-run the `pip install` after every Python upgrade — `update-python.sh` does, since it uninstalls the superseded build and its packages with it.

> **Note:** The `t` suffix is the free-threaded build. Standard (GIL-enabled) is the current global default since some tools (yt-dlp) don't tolerate the GIL disabled. To test something against free-threading: `pyenv shell ${PYTHON_LATEST}t && export PYTHON_GIL=0` for that shell, or `pyenv local ${PYTHON_LATEST}t` to pin a project directory to it. Revert to free-threaded-by-default globally with `pyenv global ${PYTHON_LATEST}t` and restoring `export PYTHON_GIL=0` in `~/.bashrc`.

> **Updating Python:** `pyenv update` first to get new versions, then re-run the install block. `pyenv latest 3` always resolves the current stable release — when 3.15 ships stable it will naturally pick that up.

```bash
pyenv update
PYTHON_LATEST=$(pyenv latest 3)
pyenv install ${PYTHON_LATEST}
pyenv install ${PYTHON_LATEST}t
pyenv global ${PYTHON_LATEST}t
```

---

## Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

cat >> ~/.bashrc << 'EOF'

# Rust
source "$HOME/.cargo/env"
EOF

source ~/.bashrc

# Essential components
rustup component add rust-analyzer clippy rustfmt

# Bare-metal target for no_std checks (cargo check --no-default-features --target thumbv7em-none-eabi)
rustup target add thumbv7em-none-eabi

# Cargo tools
cargo install cargo-watch cargo-edit
curl -LsSf https://get.nexte.st/latest/linux-arm | tar zxf - -C ${CARGO_HOME:-~/.cargo}/bin
```

Verify:

```bash
rustc --version
cargo --version
rust-analyzer --version
cargo nextest --version
```

> **Note:** `cargo-nextest` installs from nextest's own prebuilt `aarch64-unknown-linux-gnu` binary (`get.nexte.st/latest/linux-arm`), not `cargo install` — building it from source takes 15+ minutes on Snapdragon (dozens of transitive crates, `--locked` release profile) versus seconds for the tarball. Substitute `linux-arm-musl` in the URL for a fully static binary with no glibc dependency, or `linux-x64`/`linux-x64-musl` on amd64. `cargo-watch`/`cargo-edit` don't ship prebuilt binaries this way, so those stay on `cargo install`.

**Updating Rust:**

```bash
rustup update
curl -LsSf https://get.nexte.st/latest/linux-arm | tar zxf - -C ${CARGO_HOME:-~/.cargo}/bin
```

**RustRover/IntelliJ config:** Settings → Rust → Toolchain location → `~/.cargo/bin`

---

## WebAssembly (WASM)

A cross-cutting compile target used by multiple language stacks above, not a language of its own — grouped here rather than folded into Rust's section since Rust is just its first consumer (shipping a native core to run inside a browser/edge WASM host — see `~/code/SkunkWerx/HyperUuid`). Depends on `rust` and `dotnet` already being installed (both run earlier in `MODULES`).

Rust wasm targets:

```bash
rustup target add wasm32-wasip1 wasm32-unknown-unknown wasm32-unknown-emscripten
```

> **Note:** three targets, three different stories, picked for a reason. `wasm32-wasip1` (WASI) gets a real OS-like syscall surface — `random_get`/`clock_time_get` work out of the box, no extra glue needed — the natural target for proving core logic (RNG, clock reads) survives a WASM sandbox at all. `wasm32-unknown-unknown` has no such syscalls; anything touching randomness or the clock needs a JS-side shim (`wasm-bindgen`, or a custom `getrandom` backend) — the target for idiomatic browser/npm consumption. `wasm32-unknown-emscripten` is what pairs with .NET's Blazor WebAssembly `NativeFileReference` native-interop story below; unlike the other two, its linker is `emcc`, not `rust-lld` — needs the Emscripten SDK (next).

Emscripten SDK (`emcc`, the linker `wasm32-unknown-emscripten` needs) — installed via `git clone` per [the project's own recommended method](https://github.com/emscripten-core/emsdk); no distro package, no curl-pipe installer:

```bash
git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
(cd ~/emsdk && ./emsdk install latest && ./emsdk activate latest)

cat >> ~/.bashrc << 'EOF'

# Emscripten SDK
source "$HOME/emsdk/emsdk_env.sh" > /dev/null
EOF

source ~/.bashrc
```

Wasmtime — a standalone WASI runtime, for running/testing a `wasm32-wasip1` binary directly (`wasmtime run target/wasm32-wasip1/release/*.wasm`) without a browser or Node in the loop:

```bash
curl https://wasmtime.dev/install.sh -sSf | bash
source ~/.bashrc
```

> **Note:** the installer wires `$WASMTIME_HOME`/`PATH` into `~/.bashrc` itself (guarded by its own `grep -qc 'WASMTIME_HOME'` idempotency check), unlike Go/.NET's raw-tarball installers — no manual `append_bashrc_once` needed here.

.NET `wasm-tools` workload — Blazor WebAssembly plus native interop (`<NativeFileReference>` statically linking a wasm32 native library, e.g. an Emscripten-built `libhyperuuid` side module, into a Blazor WASM app):

```bash
dotnet workload install wasm-tools
```

**A real, verified bug this hits every time, worth documenting rather than rediscovering:**
`NativeFileReference`ing a `wasm32-unknown-emscripten` **static library** (`.a`, built via `cargo rustc --crate-type staticlib` — the default `cdylib` produces an already-linked module `NativeFileReference` can't pull symbols from) built by a modern Rust toolchain fails the native relink with:

```
Unknown option '--enable-bulk-memory-opt'
```

Confirmed identically on both `linux-arm64` and `linux-x64`, and independently in an unrelated
project ([PyO3/maturin#2549](https://github.com/PyO3/maturin/issues/2549)): rustc ≥ 1.87 emits
WASM target-feature metadata that Binaryen's `wasm-opt` only learned to honor from Emscripten
3.1.74 onward. Every .NET SDK band's `wasm-tools` workload observed so far bundles an older
Emscripten (3.1.56 for the 10.0 LTS band) — squarely inside the broken range. Fix: drop the
newer, compatible `wasm-opt` from this section's own `emsdk` install in over the bundled one —
`update-wasm.sh` does this automatically after every `dotnet workload install`. Re-run the
module (or just the loop below) after a bare `dotnet workload update`, which restores the
stock broken binary:

```bash
for sdk_pack in "$DOTNET_ROOT/packs"/Microsoft.NET.Runtime.Emscripten.*.Sdk.*; do
  version_dir=$(find "$sdk_pack" -maxdepth 1 -mindepth 1 -type d | head -1)
  cp ~/emsdk/upstream/bin/wasm-opt "$version_dir/tools/bin/wasm-opt"
done
```

Verify:

```bash
rustup target list --installed | grep wasm
emcc --version
wasmtime --version
dotnet workload list
```

**Updating:**

```bash
rustup target add wasm32-wasip1 wasm32-unknown-unknown wasm32-unknown-emscripten
(cd ~/emsdk && git pull && ./emsdk install latest && ./emsdk activate latest)
curl https://wasmtime.dev/install.sh -sSf | bash
dotnet workload update
```

---

## Swift

Build dependencies are in [Base Dependencies](#base-dependencies) (the swiftly group). Install Swiftly, the official Swift toolchain manager — same role here as fnm/pyenv/rustup/SDKMAN play for their languages above:

```bash
ARCH=$(uname -m)
curl -O https://download.swift.org/swiftly/linux/swiftly-${ARCH}.tar.gz
tar zxf swiftly-${ARCH}.tar.gz
./swiftly init --assume-yes --quiet-shell-followup --no-modify-profile --platform fedora39
rm swiftly swiftly-${ARCH}.tar.gz

cat >> ~/.bashrc << 'EOF'

# Swiftly (Swift toolchain manager)
. "$HOME/.local/share/swiftly/env.sh"
EOF

source ~/.bashrc
```

Verify:

```bash
swiftly --version
swift --version
```

> **Note:** `swiftly init` installs the latest stable toolchain automatically (no separate `swiftly install latest` step needed) and, by default, wires its env-sourcing line into `~/.bash_profile`/`~/.bash_login` — login-shell files WSL2's interactive bash terminals don't source. `--no-modify-profile` skips that, and the env line is appended to `~/.bashrc` by hand instead, matching every other language manager in this doc (Go, Rust, pyenv, SDKMAN).
>
> **`--platform fedora39`, not fedora41 — confirmed, not a typo.** swift.org's own platform-support matrix lists Fedora 41 as the current minimum, but the `swiftly` *binary currently shipped* at `download.swift.org/swiftly/linux` only recognizes `ubuntu24.04`/`22.04`/`20.04`/`18.04`, `fedora39`, `ubi9`, `amazonlinux2`, `debian12` as `--platform` values (confirmed by running it: `fedora41` fails hard with `Fatal error: Unrecognized platform fedora41`, listing that exact set). `fedora39` is the newest Fedora entry the installed swiftly release actually accepts, and it works fine on Fedora 44 — glibc/ABI compatibility across Fedora releases carries it. Re-check this note (and drop it) once a newer swiftly release adds `fedora41`/`fedora44` to its recognized list.
>
> **Verified:** ran this exact sequence on this box (Fedora 44 aarch64) — `swiftly init --platform fedora39` installed swiftly 1.1.3 and Swift 6.3.3 (`aarch64-unknown-linux-gnu`) cleanly. Confirmed working end to end, not just `--version`: `swift package init --type executable` + `swift build` compiled and linked a real executable, which ran and printed `Hello, world!`. Also confirmed the `~/.bashrc` wiring works in a fresh non-login interactive shell (`bash -lc 'swift --version'`), not just the shell that ran the installer.

**Updating Swift:**

```bash
swiftly self-update
swiftly update
```

> **Note:** `swiftly update` with no argument updates the currently in-use toolchain to the latest available and uninstalls the superseded one as part of the same command — no separate prune step, same auto-resolving-over-pinned convention as `rustup update` above.

---

## Ruby

Purpose here isn't a general Ruby dev environment — it's host Rubies (with headers) to build and test the Rust-backed Ruby bindings for the polyglot work: write the core in Rust, compile it as a Ruby native extension via [`rb-sys`](https://github.com/oxidize-rb/rb-sys)/[`magnus`](https://github.com/matsadler/magnus) (the fast path), with [Fiddle](https://github.com/ruby/fiddle) dlopen-ing the plain `cdylib` as the zero-compile fallback the same gem carries. Whether a downstream consumer compiles the extension themselves or pulls a precompiled platform gem is their call — this section only covers the local dev/test loop, which mirrors one leg of `SkunkWerkx/.github`'s `hyper-build-native.yml`.

Build dependencies are in [Base Dependencies](#base-dependencies) (the ruby-build group). Install rbenv (version manager) + ruby-build (the plugin that actually compiles Ruby from source — same two-piece split as pyenv's underlying `python-build`):

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

cat >> ~/.bashrc << 'EOF'

# rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - --no-rehash bash)"
EOF

source ~/.bashrc
```

Install the Rubies — plural, and the reason is the CI this box reproduces. A Magnus extension is bound to a single Ruby minor (there is no `abi3` equivalent to collapse that axis the way PyO3 does for Python), so `hyper-build-native.yml` builds and tests it once per ABI: `ruby_version` (its default `4.0`, the current release, which the Fiddle suite also runs on) plus the caller's optional `ruby_compat_version`. HyperUuid's `ci.yml` sets that to `3.4`, and its `ruby/Rakefile` packs both (`ABIS = %w[3.4 4.0]`) into every platform gem. Running that leg locally therefore needs both Rubies installed side by side — the primary is the newest stable CRuby and is global, the compat one is selected per shell with `RBENV_VERSION`:

```bash
RUBY_PRIMARY=$(rbenv install --list | grep -vE 'jruby|mruby|picoruby|truffleruby' | tail -1 | xargs)
RUBY_COMPAT=$(rbenv install --list | grep -E '^\s*3\.4\.' | xargs)
rbenv install ${RUBY_PRIMARY}
rbenv install ${RUBY_COMPAT}
rbenv global ${RUBY_PRIMARY}
```

Verify:

```bash
ruby --version
RBENV_VERSION=${RUBY_COMPAT} ruby --version
gem --version
```

> **Verified:** built Ruby 4.0.6 from source on this box (Fedora 44 aarch64) via `rbenv install` — confirmed working end to end, not just `--version`: `bundle gem --ext=rust rust_smoke` (Bundler's built-in Rust-extension scaffold, which wires up `rb-sys`/`magnus`/`rake-compiler` automatically) generated a gem, `bundle install && bundle exec rake compile` built the Rust side, and `ruby -Ilib -e 'require "rust_smoke"; puts RustSmoke.hello("...")'` called into the compiled Rust and printed the real result. `--no-rehash` in the `rbenv init` line matches ruby-build's own recommendation (skips a redundant shim rehash on every shell startup).

> **Verified (two ABIs), 2026-09-02:** `scripts/update-ruby.sh` built 3.4.10 from source next to the existing 4.0.6 (global stayed 4.0.6, prune found nothing outside the kept set). Then the real thing, in HyperUuid: `cargo build --release --features ruby` once per ABI, each under its own `CARGO_TARGET_DIR`, staged as `ruby/lib/hyperuuid/{3.4,4.0}/hyperuuid_native.so`; `bundle exec rspec` under 3.4.10 and under 4.0.6 — 55 examples, 0 failures each, with `HyperUuid::BACKEND` confirmed `:native` under both (so the suite really went through the compiled extension, not the fallback); and `HYPERUUID_PURE=1 bundle exec rspec` on 4.0.6 — 55 examples, 0 failures, 6 pending, `BACKEND` `:fiddle`. Under 3.4.10, `bundle install` auto-installed the lockfile's `BUNDLED WITH 4.0.16` next to the interpreter's default bundler 2.6.9 on its own — the same thing `setup-ruby` does on the runner — so the script doesn't need a bundler step. Re-proved the same day after the `rust` rpm was removed: `rbenv uninstall 3.4.10`, then `./update-toolchain.sh ruby` from a deliberately bare `PATH` (no `~/.cargo/bin`, no rbenv) rebuilt it through the script's own `~/.cargo/env` sourcing — `RubyVM::YJIT.enabled?` true under `--yjit`, and HyperUuid's suite 55/55 on the rebuilt interpreter with `BACKEND` `:native` again.

> **Building the Magnus extension against both ABIs locally** — the same shape as the workflow's `build-magnus.sh`, one ABI at a time, each in its own `CARGO_TARGET_DIR`:
>
> ```bash
> cd ~/code/SkunkWerkx/HyperUuid/rust
> for abi in 3.4 4.0; do
>   RBENV_VERSION=$(rbenv versions --bare | grep "^${abi}\.") \
>     CARGO_TARGET_DIR="target/ruby-${abi}" cargo build --release --features ruby
>   mkdir -p "../ruby/lib/hyperuuid/${abi}"
>   cp "target/ruby-${abi}/release/libhyperuuid.so" "../ruby/lib/hyperuuid/${abi}/hyperuuid_native.so"
> done
> ```
>
> Then `bundle exec rspec` in `ruby/` under each `RBENV_VERSION` — `lib/hyperuuid.rb` requires `hyperuuid/<minor>/hyperuuid_native` for whichever Ruby is running, so the same suite exercises each ABI's extension. The Fiddle fallback is `HYPERUUID_PURE=1 bundle exec rspec` (the workflow's `pure_env`), against `lib/hyperuuid/native/<rid>/libhyperuuid.so`.
>
> **Ruby 4.0 unbundled `fiddle`.** Through 3.x it was a default gem — effectively stdlib, always on the load path. 4.0 made it a bundled gem: still installed next to the interpreter by ruby-build, but no longer implicitly loadable under `bundle exec`, so a gem using it needs an explicit `spec.add_dependency "fiddle"`. HyperUuid hit exactly that `LoadError` on 4.0.6 before adding the line (see its gemspec).

**Updating Ruby** — the primary tracks the newest stable CRuby automatically; the compat series is a fixed list, and it is the local twin of HyperUuid `ci.yml`'s `ruby_compat_version` input: when 3.4 goes EOL (2028-03-31) and leaves `ci.yml`, drop it here too and the next pass uninstalls it. Within each kept series only the newest patch survives; anything outside the kept set goes:

```bash
cd ~/.rbenv/plugins/ruby-build && git pull
RUBY_PRIMARY=$(rbenv install --list | grep -vE 'jruby|mruby|picoruby|truffleruby' | tail -1 | xargs)
RUBY_COMPAT=$(rbenv install --list | grep -E '^\s*3\.4\.' | xargs)
rbenv install -s ${RUBY_PRIMARY}
rbenv install -s ${RUBY_COMPAT}
rbenv global ${RUBY_PRIMARY}
rbenv versions --bare | grep -vxF -e "${RUBY_PRIMARY}" -e "${RUBY_COMPAT}" | xargs -rn1 rbenv uninstall -f
```

> `scripts/update-ruby.sh` is the replay-safe version of this (`RUBY_COMPAT_SERIES=(3.4)` at the top is the list to edit), and it hard-fails with a pointer at that list if a compat series has dropped out of `rbenv install --list` — that is what EOL looks like from ruby-build's side, and the right response is a deliberate edit, not a silent skip.

---

## PHP

Same purpose as the Ruby section above, mirrored for PHP: a host PHP (with headers) to build and test Rust↔PHP native code. Two paths ended up mattering here, both covered by this section: [`ext-php-rs`](https://github.com/davidcole1340/ext-php-rs) + its `cargo-php` CLI (a compiled native extension, PHP's Zend API linked directly), and PHP's built-in `FFI` extension (dlopen a plain `cdylib` at runtime — no compile step, no Zend API). HyperUuid's actual PHP binding ended up on the FFI path, matching the dlopen-based approach the Go/Swift/Ruby bindings all use against the same shared `libhyperuuid` — see the `--with-ffi` note below. WASM builds of PHP exist (e.g. `vmware-labs/webassembly-language-runtimes`) but are stale (frozen at PHP 8.2.6, no push since mid-2024, CGI-SAPI-only) — skipped in favor of this native path; WASM-target bridging, if any, happens on the GHA runner, not locally.

Build dependencies are in [Base Dependencies](#base-dependencies) (the php-build group — including the `libtidy-devel`/`libxslt-devel` pair the upstream guide omits, and `clang-devel` for `bindgen`).

Install phpenv (version manager) + php-build (the plugin that compiles PHP from source — same rbenv-derived architecture as Ruby's rbenv/ruby-build pair above):

```bash
git clone https://github.com/phpenv/phpenv.git ~/.phpenv
git clone https://github.com/php-build/php-build ~/.phpenv/plugins/php-build

cat >> ~/.bashrc << 'EOF'

# phpenv
export PATH="$HOME/.phpenv/bin:$PATH"
eval "$(phpenv init -)"
EOF

source ~/.bashrc
```

Install latest stable PHP, built `--with-ffi` (libffi-devel is already in the dependency list above; the default `./configure` php-build runs does *not* pass `--with-ffi` on its own — confirmed by inspecting `php -i`'s `Configure Command` output after a plain install and finding no FFI extension at all, not just a disabled one):

```bash
PHP_LATEST=$(phpenv install --list | grep -vE 'snapshot|alpha|beta|RC' | tail -1 | xargs)
PHP_BUILD_CONFIGURE_OPTS="--with-ffi" phpenv install ${PHP_LATEST}
phpenv global ${PHP_LATEST}
phpenv rehash
```

Install `cargo-php`, the build/install CLI for `ext-php-rs` extensions:

```bash
cargo install cargo-php --locked
```

Verify:

```bash
php --version
php-config --includes
php -m | grep -i ffi
cargo-php --version
```

> **`cargo-php` install must happen with `php` already active on `PATH`** — its build script shells out to `php-config` to link against the Zend API. Installing it before `phpenv global` is set (or in a shell that hasn't sourced `~/.bashrc`) fails with `Could not find PHP executable` — confirmed by hitting exactly that error on this box, then fixing it by re-running `cargo install cargo-php` after `phpenv global` was in effect.
>
> **Verified:** built PHP 8.5.9 from source on this box (Fedora 44 aarch64) via `phpenv install` — confirmed working end to end, not just `--version`: a minimal `ext-php-rs` crate (`#[php_function] fn hello(subject: String) -> String`, `#[php_module]`) built with `cargo php install --release --yes`, which compiled it, dropped `libphp_smoke.so` into PHP's `extension_dir`, and wired an `extension=` line into `php.ini` automatically. `php -r 'echo hello("world"), PHP_EOL;'` then called into the compiled Rust and printed the real result — no `-d extension=` flag needed, it autoloads.
>
> **Verified (FFI path):** rebuilt the same PHP 8.5.9 with `--with-ffi` added (`phpenv install -f`, forcing a rebuild of an already-installed version) — `php -m` now lists `FFI`. Confirmed end to end against HyperUuid's real `libhyperuuid.so`: `FFI::cdef($cHeaderDecls, $path)` dlopen'd it, called `uuid_new_v4`/`uuid_new_v5`/`uuid_new_v7` through `FFI::new('uint8_t[16]')` buffers, `FFI::memcpy` for input bytes and `FFI::string` to read output bytes back, and got byte-identical results to the RFC 9562 test vectors — no `ffi.enable` ini change needed: PHP's CLI SAPI runs FFI unrestricted regardless of the `ffi.enable` setting (confirmed by testing against the untouched `php.ini-production` default, which ships `;ffi.enable=preload` commented out); that directive only restricts non-CLI SAPIs like FPM.

**Updating PHP:**

```bash
cd ~/.phpenv/plugins/php-build && git pull
PHP_PREV=$(phpenv version-name)
PHP_LATEST=$(phpenv install --list | grep -vE 'snapshot|alpha|beta|RC' | tail -1 | xargs)
PHP_BUILD_CONFIGURE_OPTS="--with-ffi" phpenv install -s ${PHP_LATEST}
phpenv global ${PHP_LATEST}
phpenv rehash
[ "$PHP_PREV" != "$PHP_LATEST" ] && phpenv uninstall -f "$PHP_PREV"
cargo install cargo-php --locked --force
```

---

## .NET

Install via the official dotnet-install script (non-admin, auto-detects arm64):

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS

cat >> ~/.bashrc << 'EOF'

# .NET
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools
EOF

source ~/.bashrc
dotnet --version
dotnet --list-sdks
```

> **Note:** `--channel LTS` always resolves the latest LTS SDK patch release transparently — no version pinning required. arm64 is auto-detected. The package manager version is intentionally avoided to ensure `dotnet update` picks up patch releases (10.0.100 → 10.0.301+) without distro feed lag.

**Updating .NET:**

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS
```

---

## Older .NET Runtimes (multi-target test execution)

The `--channel LTS` SDK install above only brings the latest LTS shared runtime (currently 10.0.x) into `$DOTNET_ROOT/shared`. Multi-targeted projects (e.g. `net10.0;net9.0;net8.0`) still *compile* fine for the older TFMs, but `dotnet test -f net9.0` / `net8.0` fails at launch with `NETSDK1067`/`applaunch failed` because the matching `Microsoft.NETCore.App` shared framework isn't installed — only the SDK's own runtime is. SDKs and runtimes coexist side by side, so install the older runtimes directly:

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 9.0 --runtime aspnetcore
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 8.0 --runtime aspnetcore
dotnet --list-runtimes
```

> **Note:** `--runtime aspnetcore` installs the `Microsoft.AspNetCore.App` shared framework *and* pulls in `Microsoft.NETCore.App` alongside it (no SDK) — covers `dotnet test`/`dotnet run` for an already-built net9.0/net8.0 app whether or not it touches ASP.NET Core, and avoids getting blocked when contributing to open-source projects that do target the older ASP.NET Core TFMs. Repeat per channel as repos add/retire TFMs; .NET 8 and 9 both end support 2026-11-10, at which point this section can drop to whatever channels are still in support.
>
> Verified against `SequentialGuid.Tests` (`tests/unit/SequentialGuid.Tests`) — before installing, `dotnet test -f net9.0`/`net8.0` reported "Zero tests ran" with the framework-not-found error; after installing 9.0.17 and 8.0.28, both ran clean (net9.0: 6295 passed; net8.0: 6293 passed).

**Updating older runtimes:** re-run the install line for each channel you have installed — same auto-resolving-over-pinned convention as the LTS SDK.

> **Bare `dotnet test` (no `-f`) always fails on a repo that multi-targets net472, even for projects that don't touch net472 themselves.** `dotnet test`'s MTP orchestrator enumerates every TFM in every project up front and aborts the whole run with `Unhandled exception: ... Ensure you have a runnable project type. A runnable project should target a runnable TFM ... The current OutputType is 'Exe'.` the instant it hits a net472 leg — net472 isn't launchable through the `dotnet` muxer on Linux, full stop. This isn't fixed by the `--runtime aspnetcore` installs above; it's a different failure mode (orchestrator launch, not missing shared framework). **Always pass `-f <tfm>`** to scope the run to one modern TFM at a time, e.g. `dotnet test -f net10.0` — that runs every project in the repo for that one TFM cleanly. `-f net472` does **not** work either (same error, confirmed) — net472 has to go through Mono directly, see below.

---

## Mono (legacy .NET Framework test execution)

.NET Framework's CLR doesn't run natively on Linux, but multi-targeted libraries here still ship `net472`/`net462` test legs. Mono can host and execute the built test exe directly — including xUnit v3's Microsoft.Testing.Platform (MTP) test exe, which was the open question worth verifying before documenting this:

```bash
sudo dnf install -y mono-complete
mono --version
```

`dotnet test` (with or without `-f net472`) cannot launch a net472 test leg on Linux — confirmed, same `Unhandled exception: ... runnable TFM` error as the bare-`dotnet-test` case above. The only path that works is to **build** with the SDK, then **run the exe directly under Mono**, bypassing `dotnet test`'s orchestrator entirely:

```bash
dotnet build tests/unit/SequentialGuid.Tests/SequentialGuid.Tests.csproj -f net472
mono tests/unit/SequentialGuid.Tests/bin/Debug/net472/SequentialGuid.Tests.exe
```

> **Verified, not assumed:** ran the actual `SequentialGuid.Tests` net472 build (`tests/unit/SequentialGuid.Tests`) under Mono 6.14.1. The MTP runner self-identified as `64-bit Mono 6.14.1` and reported **6207 passed, 0 failed** — the same exe, same MTP host, that runs on real .NET Framework on Windows. No build-only fallback needed; this is a real execution receipt, not a guess.
>
> **One-command repo wrapper:** since neither bare `dotnet test` nor `dotnet test -f net472` can run the full matrix, multi-targeted repos get a repo-local `test.sh` at the root that loops `dotnet test -f <tfm>` over the modern TFMs, then `dotnet build -f net472` + `mono <exe>` over the net472 test projects, with `set -euo pipefail` so any failure stops the script and propagates a non-zero exit code. See `SequentialGuid/test.sh` for the reference implementation — it's repo-specific (hardcodes that repo's TFM list and net472 project paths), so copy and adjust per repo rather than trying to generalize it.
>
> **Known risk (unconfirmed, not yet hit):** Mono's BCL isn't byte-identical to real .NET Framework (globalization/ICU, some reflection edge cases). Low risk for bit/byte-manipulation-style libraries like SequentialGuid, but if a net472 test ever passes under Mono and fails on real .NET Framework (or vice versa), suspect this first before suspecting the code.

**Updating Mono:**

```bash
sudo dnf install -y mono-complete
# `install`, not `update` — dnf's install upgrades an already-installed package to
# the latest available version, but `update` errors out if the package isn't
# installed yet ("available, but not installed"). `install` works either way.
```

---

## .NET 11 Preview SDK — TEMPORARY (Norse discriminated unions)

> **Temporary section — remove once no longer needed.** Tracking the .NET 11 preview channel (currently preview 6, shipped 2026-07-14) to get native discriminated union support for the Norse Architecture. **Exit condition:** drop this section once .NET 11 hits GA and the team has decided whether to adopt it as a standing channel, or once the DU work no longer needs the preview bits — whichever comes first. The main [.NET](#net) section above stays pinned to `--channel LTS` regardless; this installs side by side, it does not replace that baseline.
>
> **`--quality preview` covers RC too.** `dotnet-install.sh` only has three quality values — `daily`, `preview`, `GA` — there's no separate `rc` value. Every monthly 11.0 build (previews and, later, release candidates) ships under `preview` until GA, so the install command below doesn't need to change when 11.0 reaches RC.

Install the latest preview build of the 11.0 channel into the same `$DOTNET_ROOT` — SDKs coexist side by side automatically:

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 11.0 --quality preview
dotnet --list-sdks
```

> **Note:** Installing a preview SDK does not change which SDK `dotnet` resolves to by default — the CLI picks the latest installed unless pinned. Add a `global.json` in the Norse Architecture repo (not globally) to pin those projects to the 11.0 preview SDK, so every other repo on this machine keeps resolving to the LTS SDK untouched:
>
> ```json
> {
>   "sdk": {
>     "version": "11.0.100-",
>     "rollForward": "latestFeature"
>   },
>   "test": {
>     "runner": "Microsoft.Testing.Platform"
>   }
> }
> ```
>
> Replace the version with whatever `dotnet --list-sdks` reports after install. `rollForward: latestFeature` follows this toolchain's auto-resolving-over-pinned convention — each new preview build (preview 5 → preview 6 → ...) lands in the same feature band, so the pin keeps working without editing `global.json` per preview drop. The `test` block makes `dotnet test` default to Microsoft.Testing.Platform instead of the legacy VSTest runner, matching xUnit v3's native MTP support.

**Updating the preview SDK:**

```bash
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 11.0 --quality preview
```

> **Old preview SDKs pile up.** Each monthly build installs as a new side-by-side SDK under `$DOTNET_ROOT` rather than replacing the last one — `scripts/update-dotnet.sh` (see [Full Update Pass](#full-update-pass)) handles this by diffing `dotnet --list-sdks` before/after the install and pruning the superseded preview's SDK/runtime/pack/host artifacts once the new one is confirmed present.

---

## GitHub CLI

Auto-detects architecture at install time:

```bash
GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
wget https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz
tar -xzf gh_${GH_VERSION}_linux_${ARCH}.tar.gz
sudo install gh_${GH_VERSION}_linux_${ARCH}/bin/gh /usr/local/bin/gh
rm -rf gh_${GH_VERSION}_linux_${ARCH} gh_${GH_VERSION}_linux_${ARCH}.tar.gz

gh --version
```

Authenticate:

```bash
gh auth login
# Select: GitHub.com → HTTPS → Login with a web browser
```

**Updating gh:** Re-run the install block above — `sudo install` overwrites the existing binary in place.

---

## actionlint

Static checker for GitHub Actions workflow files — catches YAML/`workflow` schema errors, bad `runs-on` labels, invalid `${{ }}` expressions and their type errors, unknown contexts, and shell mistakes in `run:` blocks, all before you push and burn a CI run finding out. Same release-tarball pattern as `gh`, auto-detecting architecture:

```bash
AL_VERSION=$(curl -s https://api.github.com/repos/rhysd/actionlint/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
wget https://github.com/rhysd/actionlint/releases/download/v${AL_VERSION}/actionlint_${AL_VERSION}_linux_${ARCH}.tar.gz
tar -xzf actionlint_${AL_VERSION}_linux_${ARCH}.tar.gz actionlint
sudo install actionlint /usr/local/bin/actionlint
rm actionlint actionlint_${AL_VERSION}_linux_${ARCH}.tar.gz

actionlint --version
```

Run it from a repo root — with no arguments it finds and checks every workflow under `.github/workflows/`:

```bash
cd ~/code/some-repo
actionlint
```

> **Gotcha:** the no-argument form walks up looking for a Git repository and hard-errors (`no project was found in any parent directories ...`, exit 3) outside one, even when `.github/workflows/` is sitting right there. Pass explicit file paths (`actionlint path/to/workflow.yml`) to lint a directory that isn't a repo. Exit codes: `0` clean, `1` problems found, `3` invalid usage.

**Updating actionlint:** Re-run the install block above — `sudo install` overwrites the existing binary in place.

### ShellCheck + pyflakes integrations

`actionlint` shells out to `shellcheck` for `run:` script bodies and `pyflakes` for `python`-shell steps when either is on `PATH`, and *silently* skips those checks when it isn't — no warning, just fewer findings. Both are installed here, so both integrations are live:

```bash
sudo dnf install -y ShellCheck python3-pyflakes

shellcheck --version
pyflakes --version
```

> **Why dnf and not pip/pyenv for `pyflakes`:** a `pip install pyflakes` lands inside the pyenv-managed build, and `scripts/update-python.sh` uninstalls the superseded build on every Python upgrade — actionlint's python-step linting would quietly go dark after each pass. The dnf package is tied to the system `python3` instead and survives pyenv churn.

> **Version note:** Fedora ships `python3-pyflakes` 3.1.0, behind upstream. Fine for what actionlint uses it for (undefined names, unused imports in inline `python` steps); if a newer pyflakes ever matters, that's the point to reconsider the pyenv/pip tradeoff above.

---

## PowerShell

Microsoft's RHEL/CentOS repos only ship x86_64 RPMs — no aarch64 packages. Install from the GitHub releases tarball instead, which ships arm64 and amd64 binaries:

```bash
PS_VERSION=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')
wget https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/powershell-${PS_VERSION}-linux-${ARCH}.tar.gz
sudo mkdir -p /opt/microsoft/powershell/7
sudo tar -xzf powershell-${PS_VERSION}-linux-${ARCH}.tar.gz -C /opt/microsoft/powershell/7
sudo chmod +x /opt/microsoft/powershell/7/pwsh
sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
rm powershell-${PS_VERSION}-linux-${ARCH}.tar.gz
pwsh --version
```

**Updating PowerShell:** Re-run the install block — `tar -xzf` overwrites in place, the symlink is stable, no `mkdir` needed again.

---

## Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash

claude --version
claude doctor
```

Authenticate:

```bash
claude
# On first launch follow the browser prompt to sign in with your Anthropic account
```

> **Note:** The native installer auto-updates in the background on the `latest` channel — no update command required. Requires a Claude Pro subscription or higher.

---

## Playwright (Claude Code browser automation)

Browser automation is Microsoft's official `@playwright/mcp` server, wired in as a Claude Code plugin (marketplace: `claude-plugins-official`). No standalone install step for the server itself — the plugin's `.mcp.json` launches it on demand via `npx`, always resolving `@latest`:

```json
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest"]
  }
}
```

The browser is the distro's `chromium` package, not Playwright's own bundled Chromium download:

```bash
sudo dnf install -y chromium
```

The MCP server auto-detects the system `chromium-browser` executable (`/usr/sbin/chromium-browser`) directly — no `npx playwright install chromium` step, no second Chromium download managed separately from the OS. `~/.cache/ms-playwright` stays effectively empty (a few KB of registry metadata, no browser binaries) as a result — that's expected, not a broken install.

Verify:

```bash
npx @playwright/mcp@latest --version
chromium-browser --version
```

> **Note:** Routing through the dnf-managed `chromium` package keeps the browser under the distro's own patch/security-update cadence and avoids a redundant ~300MB Playwright-managed browser download sitting alongside the system one. This is intentional, not a fallback — the MCP server resolves straight to `chromium-browser`.

**Updating:**

```bash
sudo dnf install -y chromium
# `install`, not `update` — same reasoning as the Mono section above.
# @playwright/mcp always resolves @latest via npx — no separate update command
```

---

## Docker

Docker Desktop runs on the Windows host, not inside WSL2 — there is no install step here. The CLI and socket are injected into the distro via WSL integration, which is opt-in per-distro and off by default for non-default distros like Fedora.

Enable on the Windows side:

1. Docker Desktop → **Settings → Resources → WSL Integration**
2. Toggle the entry for **Fedora** under "Enable integration with additional distros"
3. **Apply & Restart**
4. From PowerShell: `wsl --shutdown`, then reopen the Fedora terminal

Verify:

```bash
docker version
docker context ls
```

> **Note:** The Windows host manages Docker Desktop purely to provide the GUI for one-off container/image/volume cleanup — no `dnf install`, no update command inside WSL, updates happen entirely through Docker Desktop on Windows. Project workloads themselves run from WSL via **Aspire** — that's the next wave of toolchain verification.

> **Verified:** Docker Desktop's WSL2 backend shares a network namespace with automatic localhost forwarding — a port published with `docker run -p` is reachable on `localhost` from *both* WSL2 and Windows simultaneously, no extra config. Confirmed by pulling and running `downloads.unstructured.io/unstructured-io/unstructured-api:latest` (`-p 8000:8000`) and curling `http://localhost:8000/healthcheck` from inside WSL — `200 OK`, `{"healthcheck":"HEALTHCHECK STATUS: EVERYTHING OK!"}`. The same URL works unchanged from Postman/browser on Windows.
>
> Day-to-day container lifecycle (start/stop/remove) is intended to go through the Docker Desktop GUI on Windows, not the WSL CLI — the CLI here is for occasional one-off verification, not routine use. One gotcha if you do run from the CLI: a bare `docker run` (no `-d`) ties the container to the foreground process and it dies (`Exited 137`) when that shell session ends; use `docker run -d` or just manage it from the GUI.
>
> `unstructured-api` itself is a parked capability, not active work yet — it extracts text chunks from unstructured documents (PDFs, Office docs, etc.) as a precursor step to running embeddings for RAG. This was just a "does the plumbing work" check.

**Updating images:**

```bash
./scripts/update-docker.sh
```

Lists every locally-pulled image (`docker images`), then re-pulls each `repository:tag` pair. Images pinned to an immutable version tag are effectively a no-op (already at that digest); floating tags (`:latest`, etc.) actually refresh. Local-only builds with no upstream repository fail their pull individually and are skipped without aborting the rest of the sweep.

> **Note — clean-slate policy, deliberate:** a container built from a tag that's since moved shows up in `docker ps -a` with a raw image ID instead of a name. The script force-removes any container in that state (`docker rm -f`, never `-v` — named *and* anonymous volumes are always left behind) and then prunes the now-unreferenced image. It does **not** try to reconstruct the container's `docker run` config (bind mounts, networks, replication topology) — that's easy to get subtly wrong, and anything worth keeping either lives in a named volume (survives regardless) or is owned by an orchestrator that already knows how to recreate its own containers correctly. Confirmed live on this machine: Aspire's Norse Architecture postgres primary/replica pair (`pg-primary-*`/`pg-replica-*`) bind-mounts ephemeral, session-specific init scripts from `/run/desktop/mnt/host/wsl/docker-desktop-bind-mounts/...` that only Aspire itself can regenerate correctly — the pair comes back on the next AppHost run, rebuilt against the fresh image, data intact via the `norse-pg-primary`/`norse-pg-replica` volumes. This is tuned for solo personal-machine use — if anyone else ever runs this against a shared box, they inherit the clean-slate trade-off, not just the script.

---

## Code Directory

All repositories live inside WSL2 at `~/code/` — never on `/mnt/c/`. Crossing the WSL2/Windows filesystem boundary via `/mnt/c/` degrades I/O performance noticeably for git operations, file watching, and builds.

Suggested layout:

```
~/code/
  ├── buvinghausen/    # personal repos
  └── norse/           # Norse Architecture
        └── Bifrost/
            ├── Svartalfheim/
            ├── Asgard/
            └── ...
```

Clone with submodules using the `--` separator to pass git flags through gh:

```bash
gh repo clone buvinghausen/Bifrost -- --recurse-submodules
```

---

## GitHub Desktop (Windows) via `\\wsl.localhost\`

For wide-support-surface OSS libraries (legacy .NET Framework targets — currently just `SequentialGuid` and `TaskTupleAwaiter`), GitHub Desktop on Windows opens the repo directly through the `\\wsl.localhost\<distro>\...` share rather than a separate Windows-side clone. This is purely a review/revert UI (eyeball diffs, uncheck hunks, discard lines) — not the commit path of record — so the network-share performance hit doesn't matter.

**Gotcha:** Windows git (bundled in GitHub Desktop) stats files through the 9P protocol, which can report a different executable bit than Linux-native git sees on the same inode. This shows up as a file marked "modified" in GitHub Desktop with zero line diff — a mode-only change (`100755` ↔ `100644`), most often hitting shell scripts like `test.sh`.

Fix per-repo:

```bash
git config core.fileMode false
```

This lives in `.git/config`, which is the same file regardless of which OS's git reads it, so it only needs setting once per repo.

> **Trade-off:** with filemode tracking off, git won't auto-detect a deliberate `chmod +x` on a new file. To stage a real permission change, either flip it back temporarily (`git config core.fileMode true`) or run `git update-index --chmod=+x path/to/file` directly — that works regardless of the `core.fileMode` setting.

---

## posh-git-sh

Git-aware prompt active only inside `~/code/**`. Outside that boundary the prompt reverts to the standard bash default.

```bash
curl -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh
```

Add to `~/.bashrc` (before SDKMAN block):

```bash
# posh-git-sh — only active inside ~/code/**
source ~/.posh-git-sh

_update_prompt() {
    case "$PWD" in
        $HOME/code/*)
            PROMPT_COMMAND='__posh_git_ps1 "\u@\h:\w " "\\\$ ";'
            ;;
        *)
            PROMPT_COMMAND=''
            PS1='\u@\h:\w\$ '
            ;;
    esac
}

cd() {
    builtin cd "$@" || return
    _update_prompt
}

_update_prompt
```

> **Note:** The prompt only activates when inside `~/code/**` AND inside a git repo — navigating to `~/code` itself without a repo won't trigger it. That's correct behavior.

**Updating posh-git-sh:**

```bash
curl -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh
```

---

## JetBrains WSL2 Tips

**Use local IDEs with a WSL Run Target** — not JetBrains Gateway. With a full suite (GoLand, RustRover, Rider, PyCharm, IntelliJ, WebStorm) Gateway doubles the servicing burden: every IDE patch requires a matching Gateway patch. Run Targets give the same WSL2 build/run/test integration from the local IDE without that overhead.

**WSL Run Target setup (per IDE, one-time):**

1. Settings → Build, Execution, Deployment → Run Targets → `+` → WSL
2. Select `FedoraLinux-44` from the distro list
3. JetBrains introspects the distro and maps toolchain paths automatically
4. In each run/debug configuration set **Run target** to the WSL entry

**GoLand specifics:**

- Settings → Go → GOROOT → `\\wsl.localhost\FedoraLinux-44\usr\local\go`
- With the WSL Run Target active, GoLand translates the UNC path correctly when invoking the toolchain — the broken-path bug (`stat /main.go: directory not found`) is a symptom of missing Run Target configuration, not a GOROOT misconfiguration

**General:**

- All `export` and init lines above are in `~/.bashrc` — JetBrains WSL introspection sources it automatically
- After initial setup run `wsl --shutdown` from PowerShell then reopen before connecting to ensure a clean environment load
- **If a run configuration produces broken paths** (e.g. `/main.go` instead of the full Linux path), delete it and recreate it from scratch — the path mapping bakes in at creation time and corruption isn't fixable by editing

---

## Verified Environment

```
Node.js   v24.18.0       (Krypton LTS)
npm       12.0.1
tsc       7.0.2          (Go-native compiler, GA since 2026-07-08 — no longer @rc)
go        1.26.5         linux/arm64
gopls     0.23.0
dlv       1.27.0
java      25.0.4         Temurin LTS
graalvm   25.4.4.1+1     GraalVM CE (java 25.0.4.1.1, native-image 25.0.4.1.1), SDKMAN-managed alongside Temurin — never `current`
kotlin    2.4.20
gradle    9.8.0
python    3.14.5         GIL enabled (standard build; 3.14.5t available via pyenv local/shell for free-threaded testing)
rustc     1.97.1         aarch64-unknown-linux-gnu
cargo     1.97.1
nextest   0.9.140         prebuilt aarch64-unknown-linux-gnu binary, not cargo-installed
swiftly   1.1.3           toolchain manager
swift     6.3.3           aarch64-unknown-linux-gnu (via swiftly --platform fedora39, see Swift section)
ruby      4.0.6           aarch64-linux, via rbenv/ruby-build, global — primary Magnus ABI + Fiddle suite host
ruby      3.4.10          compat Magnus ABI (HyperUuid ci.yml ruby_compat_version), RBENV_VERSION-selected
php       8.5.9           via phpenv/php-build, built --with-ffi — host for ext-php-rs and FFI extension dev
cargo-php 0.1.21          ext-php-rs's build/install CLI
dotnet    10.0.302       (+ 9.0.18, 8.0.29 runtimes for multi-target test execution)
dotnet-11 11.0.100-preview.6.26359.118   TEMPORARY preview channel (Norse DU work) — see its own section
mono      6.14.1         legacy net472/net462 test execution
playwright-mcp 0.0.78    @playwright/mcp, via npx, no persistent install
chromium  150.0.7871.114 dnf-managed, not Playwright-downloaded
gh        2.99.0
actionlint 1.7.12       GitHub Actions workflow linter
shellcheck 0.11.0       dnf-managed; actionlint's `run:`-body integration
pyflakes  3.1.0          dnf-managed (python3-pyflakes); actionlint's `python`-step integration
pwsh      7.6.5
claude    2.1.183        native, linux-arm64, auto-updates enabled
posh-git-sh 1.5.1       ~/code/** only
```

*Verified on: 2026-07-17 · Surface Snapdragon · WSL2 Fedora aarch64 · full pass via `./update-toolchain.sh`*
*`playwright-mcp` / `chromium` added and verified separately: 2026-07-12*
*`docker` module (image refresh + dangling-image/stale-container cleanup) added to the update pass 2026-07-17 — not listed above since it tracks container images, not a pinned CLI version.*
*`python` default flipped from free-threaded (`t`, `PYTHON_GIL=0`) back to standard/GIL-enabled: 2026-07-19 — yt-dlp needs the GIL. Free-threaded build stays installed for opt-in testing.*
*`swift` (via swiftly) added and verified 2026-08-26 — `swift build`/SPM confirmed with a real compiled-and-run executable, not just `--version`; see the `--platform fedora39` note in the Swift section for why that flag isn't `fedora41`.*
*`ruby` (via rbenv/ruby-build) and `php` (via phpenv/php-build) added and verified 2026-08-26 for the write-in-Rust/wrap-per-language polyglot work — both confirmed by compiling a real `rb-sys`/`magnus` Ruby extension and a real `ext-php-rs` PHP extension and calling into the compiled Rust from each, not just `--version`. WASM builds of Ruby/PHP were evaluated and skipped: this repo's toolchain covers native compile+interop only, any WASM-target bridging happens on the GHA runner. See the Ruby and PHP sections for the `libtidy-devel`/`libxslt-devel` and `cargo-php`-needs-`php`-on-`PATH` gotchas hit along the way.*
*Correction, 2026-08-27: the "WASM bridging happens on the GHA runner" line above was about HyperUuid's per-platform native `.so`/`.dll`/`.dylib` builds, which genuinely do run on GHA matrix runners (`build-packages.yml`) — not a decision against WASM tooling on this machine in general. See the new [WebAssembly (WASM)](#webassembly-wasm) section for the real first instance of that: Rust/.NET, added the same day.*
*`actionlint` added and verified 2026-09-01 — confirmed both ways: a clean exit-0 pass over HyperUuid's four real workflows, and a deliberately broken workflow (bogus `runs-on` label, undefined `github.*` property) that it flagged on both counts with exit 1. `shellcheck` and `pyflakes` went in the same day and are verified live, not merely present: a workflow with an unquoted `$FOO` in a `run:` body and an unused import plus an undefined name in a `shell: python` step produced SC2086 from shellcheck and both pyflakes diagnostics, routed through actionlint's own output.*

*`ruby` grew a second ABI 2026-09-02 — 3.4.10 alongside 4.0.6, because `SkunkWerkx/.github`'s `hyper-build-native.yml` builds the Magnus extension once per Ruby minor and HyperUuid's `ci.yml` asks for `ruby_compat_version: "3.4"` on top of the forge's `4.0` default. `scripts/update-ruby.sh` now keeps the newest patch per kept series (`RUBY_COMPAT_SERIES`, the local twin of that ci.yml input) instead of one Ruby, and the same day's consolidation folded the four per-language dnf prerequisite lists into the one [Base Dependencies](#base-dependencies) list (`dnf_build_deps` in `scripts/lib.sh`, a confirmed no-op on this box — every package was already installed) and the three copies of the GitHub-release-tarball install pattern in `update-tools.sh` into two `lib.sh` helpers (`github_latest_release`, `install_from_tarball` — exercised for real by the `gh` 2.96.0 → 2.99.0 upgrade in the verifying run). See the Ruby section's two-ABI Verified note for the HyperUuid build-and-rspec evidence.*
*`graalvm` (GraalVM CE via SDKMAN) added to the doc and the `jvm` module 2026-09-04 — it had been installed by hand on 2026-08-27 and was sitting outside the update pass entirely: `sdk upgrade` only ever tracks the Temurin default, so it would never have moved. Verified by a real `native-image` build of a running aarch64 executable and an uninstall-then-`./update-toolchain.sh jvm` round trip that left `current` on Temurin; see the [GraalVM CE](#graalvm-ce-native-image) subsection.*
*`graalvm` bumped to `25.4.4.1+1-graalce` and verified on x86_64 2026-10-01 — the `jvm` module had never run on that box since GraalCE joined it, so only Temurin was present; one `./update-toolchain.sh jvm` run installed it with no script change (the lookup is keyed on `$SDKMAN_PLATFORM`), and a `native-image` build produced a running x86-64 executable. See the x86_64 Verified note in the [GraalVM CE](#graalvm-ce-native-image) subsection. The same run's version output refreshed the `java` (25.0.3 → 25.0.4), `kotlin` (2.4.10 → 2.4.20), and `gradle` (9.6.1 → 9.8.0) rows above.*
*`php` rebuilt `--with-ffi` and re-verified 2026-08-27 — HyperUuid's actual Ruby/PHP bindings ended up on the same dlopen-a-shared-`cdylib` architecture as the Go/Swift bindings (Fiddle for Ruby, `FFI` for PHP) rather than the compiled-native-extension path (`rb-sys`/`ext-php-rs`) the 2026-08-26 entry above verified — that path stays documented since it's still a legitimate way to build Rust↔Ruby/PHP native extensions, just not the one this project used. Ruby's `Fiddle` needed no toolchain change (stdlib); PHP's `FFI` extension wasn't in the default `php-build` configure line at all, hence the rebuild.*

---

## Full Update Pass

Run this periodically to bring the entire toolchain current:

```bash
./update-toolchain.sh              # every module, in order
./update-toolchain.sh dotnet go    # or just the modules you want
```

`update-toolchain.sh` is the executable, replay-safe version of this pass — each `scripts/update-*.sh` module is a no-op or clean overwrite when already current, and the `Go`, `jvm`, `.NET`, and `docker` modules additionally remove whatever they're superseding (old `/usr/local/go`; superseded SDKMAN patch releases within each major series; every stale SDK/runtime/pack/manifest-band across all four .NET channels, not just the 11.0 preview one; dangling images and containers pinned to a superseded image) rather than leaving it to accumulate. Modules: `base` (the [Base Dependencies](#base-dependencies) dnf list — the single one every language module's from-source build shares), `node` (npm + TypeScript), `go`, `jvm` (Java/Kotlin/Gradle, plus [GraalVM CE](#graalvm-ce-native-image) resolved against the Temurin default's major since `sdk upgrade` can't see it; patch-release prune), `dotnet` (LTS + 9.0/8.0 runtimes + 11.0 preview, full stale-version prune, `dotnet new`/`tool`/`workload` updates — prerelease-versioned tools like `dotnet-ef` track the preview channel until GA outranks it), `rust`, `wasm` ([WebAssembly (WASM)](#webassembly-wasm): Rust's `wasm32-wasip1`/`wasm32-unknown-unknown`/`wasm32-unknown-emscripten` targets, Emscripten SDK, wasmtime, .NET's `wasm-tools` workload), `swift` (swiftly self-update + in-use toolchain update, which prunes the superseded toolchain itself), `ruby` (rbenv/ruby-build, newest patch of the primary series + each `RUBY_COMPAT_SERIES` entry, prunes everything else), `php` (phpenv/php-build, prunes the superseded PHP build, re-installs `cargo-php` against the new build), `python`, `tools` (gh, [actionlint](#actionlint) + ShellCheck/pyflakes, pwsh, Mono, Chromium, posh-git-sh), `docker` (image refresh, dangling-image prune, clean-slate container removal). Claude Code isn't a module — it auto-updates itself on the `latest` channel.

`base`, `node`, `go`, `jvm`, `dotnet`, `rust`, `swift`, `ruby`, `php`, and `python` all bootstrap their own prerequisite when it's missing (fnm, Go itself, SDKMAN, dotnet, rustup, swiftly, rbenv, phpenv, pyenv respectively) rather than hard-failing — a fresh machine with nothing but `git`/`curl` on it runs `./update-toolchain.sh` end to end. `tools` never had a hard-fail prerequisite to begin with (every install there is unconditional or version-diffed). `docker` and `wasm` are the two exceptions: Docker Desktop's WSL integration is a manual Windows-side toggle (see [Docker](#docker)) that can't be scripted from inside WSL, and `wasm` depends on `rust` and `dotnet` already being installed (both run earlier in `MODULES`) — both hard-fail with a pointer back to the relevant section rather than bootstrapping a prerequisite themselves.

The command-by-command breakdown for each stack lives in that stack's own section above (e.g. [Go](#go), [.NET](#net)) — treat those as the reference for *what* each step does; `scripts/update-*.sh` is the reference for *exact, current* invocation. If they drift, the scripts win — update the docs above to match rather than editing this block, since this block just points at them.
