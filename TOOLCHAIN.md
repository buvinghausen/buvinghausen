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
go install golang.org/x/perf/cmd/benchstat@latest   # significance-tested comparison of two `go test -bench` runs
```

> **Note:** formatting and profiling need nothing installed — `gofmt` (the Hyper repos' CI gate is `gofmt -l .`) and `go tool pprof` both ship inside the Go distribution. `benchstat` is the one piece of the benchmark loop that doesn't: `go test -bench=. -count=8 > old.txt`, make the change, `> new.txt`, then `benchstat old.txt new.txt` prints the per-benchmark delta for time, bytes and allocations with a p-value, instead of two columns to eyeball. It has no version flag — `go version -m ~/go/bin/benchstat` reads the module version out of the binary.

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

### async-profiler

Sampling CPU/allocation/lock profiler for the JVM, alongside the JFR every JDK here already bundles. Not an SDKMAN candidate, so it installs from its GitHub release tarball in the same shape as [PowerShell](#powershell) — a multi-file tarball unpacked under `/opt` (`asprof` loads `../lib/libasyncProfiler.so` relative to its own resolved path, so the tree has to stay together), entry points symlinked onto `PATH`:

```bash
AP_VERSION=$(curl -s https://api.github.com/repos/async-profiler/async-profiler/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')
wget https://github.com/async-profiler/async-profiler/releases/download/v${AP_VERSION}/async-profiler-${AP_VERSION}-linux-${ARCH}.tar.gz
sudo mkdir -p /opt/async-profiler
sudo tar -xzf async-profiler-${AP_VERSION}-linux-${ARCH}.tar.gz -C /opt/async-profiler --strip-components=1
sudo ln -sf /opt/async-profiler/bin/asprof /usr/local/bin/asprof
sudo ln -sf /opt/async-profiler/bin/jfrconv /usr/local/bin/jfrconv
rm async-profiler-${AP_VERSION}-linux-${ARCH}.tar.gz

asprof --version
```

```bash
asprof -d 30 -f flame.html <pid>                          # CPU flame graph of a running JVM
asprof -d 30 -e cpu -o collapsed -f cpu.collapsed <pid>   # collapsed stacks, for diffing/other viewers
jcmd <pid> JFR.start duration=30s filename=rec.jfr        # the bundled alternative — no install at all
jfr summary rec.jfr
```

> **Verified on x86_64, 2026-10-06:** `./update-toolchain.sh jvm` installed 4.5 through the script; attached to a running `java Busy` (Temurin 25.0.4) with no sudo and no JVM flags, `asprof -d 3 -e cpu -o collapsed` attributed all 300 samples to `Busy.main;Busy.hot` and `-f flame.html` wrote the flame graph, both through the `/usr/local/bin` symlink. On the same pid, `jcmd JFR.start` + `jfr summary` recorded 45 `jdk.ExecutionSample` events — JFR needs nothing beyond the JDK. The release also publishes `linux-arm64`; that path has not been run on the Snapdragon yet.

**Updating async-profiler:** re-run the install block — `tar -xzf` overwrites in place, the symlinks are stable.

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

Build, test, lint, benchmark, and profiling tooling for Python bindings over a Rust core (HyperUuid: pyo3 abi3 extension via maturin, pytest suite, ruff lint and `ruff format` — the formatter is the same binary), plus the rest of what those bindings' extras and CI name: mypy (the `test` extra — `tests/test_typing.py` skips without it), pyperf (the `bench` extra — what `bench_*.py` is written against), and py-spy (sampling profiler; attaches from outside, no changes to the target):

```bash
pip install --upgrade pip maturin pytest ruff mypy pyperf py-spy
```

```bash
py-spy record -o prof.svg -- python script.py   # flame graph of a whole run
py-spy dump --pid <pid>                         # what a live process is doing right now
python -m pyperf timeit -s 'setup' 'stmt'       # calibrated, multi-process timing
```

> **Verified on x86_64, 2026-10-06:** on the pyenv 3.14.8 build, `py-spy record` (0.4.2) sampled a child `python` for 3 s — 299 samples, 0 errors, 98% in the hot function by line — and `py-spy dump --pid` attached to an already-running interpreter and printed its stack, both without sudo (`kernel.yama.ptrace_scope` is 0 under WSL2 here). `pyperf timeit` ran its worker processes and reported a mean ± std dev; `mypy` (2.4.0, compiled) flagged a deliberate `arg-type` error. pyperf's CLI has no version flag — `python -c "import pyperf; print(pyperf.__version__)"`.

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
cargo install --locked samply cargo-semver-checks   # profiler; local twin of the Hyper repos' check-semver CI job
curl -LsSf https://get.nexte.st/latest/linux-arm | tar zxf - -C ${CARGO_HOME:-~/.cargo}/bin
```

Verify:

```bash
rustc --version
cargo --version
rust-analyzer --version
cargo nextest --version
samply --version
cargo semver-checks --version
```

> **Note:** `rustfmt` (a component above) is the formatter — the CI gate is `cargo fmt --check` — and the benchmark harness is criterion, a dev-dependency of each crate (`cargo bench`), so neither needs anything more here. `samply` is the profiler: `samply record ./target/release/<bin>` samples through perf events and opens the result in the Firefox Profiler UI (`--save-only -o prof.json` to just write the profile). Every language binding loads the same Rust core, so it is also the profiler for the native side of any of them. `cargo-semver-checks` is what the `check-semver` CI job runs through its action; locally, `cargo semver-checks --manifest-path rust/Cargo.toml --default-features`. Both install `--locked` because that is the install line each project's README gives. `cargo install` is a no-op when the installed version is current and a from-source rebuild when it isn't: the 0.50.0 → 0.51.0 `cargo-semver-checks` rebuild took 3 m 36 s on the x86_64 box (i9-11900H). Neither build has been timed on the Snapdragon.
>
> **Verified on x86_64, 2026-10-06:** both had been `cargo install`ed by hand on that box and sat outside the update pass; `./update-toolchain.sh rust` now owns them (samply 0.13.1 already current, cargo-semver-checks upgraded in that run). `samply record --save-only` wrote a profile for a C binary and for a `swiftc -O -g` Swift binary; `cargo semver-checks` 0.51.0 against HyperUuid's `rust/Cargo.toml` with default features ran 202 checks, 202 pass, against the 0.6.1 baseline from crates.io.

> **Note:** `cargo-nextest` installs from nextest's own prebuilt `aarch64-unknown-linux-gnu` binary (`get.nexte.st/latest/linux-arm`), not `cargo install` — building it from source takes 15+ minutes on Snapdragon (dozens of transitive crates, `--locked` release profile) versus seconds for the tarball. Substitute `linux-arm-musl` in the URL for a fully static binary with no glibc dependency, or `linux-x64`/`linux-x64-musl` on amd64. `cargo-watch`/`cargo-edit` don't ship prebuilt binaries this way, so those stay on `cargo install`.

**Updating Rust:**

```bash
rustup update
cargo install --locked samply cargo-semver-checks
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

`wasm-pack` — drives the wasm-bindgen test crates for `wasm32-unknown-unknown` (`wasm-pack test --headless --chrome` over `rust/browser-test`, what `SkunkWerkx/.github`'s `hyper-build-wasm.yml` runs), fetching the matching wasm-bindgen test runner and chromedriver itself:

```bash
cargo install wasm-pack
```

> **Note:** like `samply` and `cargo-semver-checks` in the [Rust](#rust) section, this had been installed by hand on the x86_64 box (0.15.0) and was outside the update pass until 2026-10-06; `update-wasm.sh` now runs the same `cargo install`, a no-op when current.

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
wasm-pack --version
emcc --version
wasmtime --version
dotnet workload list
```

**Updating:**

```bash
rustup target add wasm32-wasip1 wasm32-unknown-unknown wasm32-unknown-emscripten
cargo install wasm-pack
(cd ~/emsdk && git pull && ./emsdk install latest && ./emsdk activate latest)
curl https://wasmtime.dev/install.sh -sSf | bash
dotnet workload update
```

---

## Android (NDK)

The second cross-cutting compile target after [WASM](#webassembly-wasm): a Hyper* core built as an Android shared library. What CI does for Android is a lint — HyperUuid's `lint-rust` job runs `cargo clippy --target aarch64-linux-android -- -D warnings` because `entropy.rs` compiles a ChaCha20-for-batches path there that nothing else exercises — and clippy never links, so a rustup target alone covers it. Actually *building* the cdylib for Android needs a linker and sysroot for the target, and that is the NDK. Depends on `rust` already being installed (runs after it in `MODULES`).

**x86_64 only.** Google ships NDK host builds for Linux x86_64, macOS and Windows and nothing else — [the downloads page](https://developer.android.com/ndk/downloads) lists exactly one Linux package, `android-ndk-<release>-linux.zip`, and there is no linux-aarch64 one. On the Snapdragon box `update-android.sh` prints `SKIPPED: the Android NDK has no aarch64 Linux host build` and exits 0 so the full pass carries on; the Android targets and `cargo-ndk` below are not installed there either, since without the NDK they have nothing to link against. Anything Android is vetted on the XPS.

The NDK itself — the release zip straight from `dl.google.com`, not `sdkmanager`: `sdkmanager` needs the whole command-line-tools package and a JDK to download one zip, and nothing here needs the rest of the Android SDK (no platforms, build-tools or emulator — the NDK is the linker and sysroot, which is all a cdylib build needs). Unpacked under `/opt` like pwsh and async-profiler, with a version-free `/opt/android-ndk` symlink as the stable path:

```bash
NDK=r30   # update-android.sh resolves this from android/ndk's GitHub releases — see note
wget -q https://dl.google.com/android/repository/android-ndk-${NDK}-linux.zip
sudo unzip -q android-ndk-${NDK}-linux.zip -d /opt    # lands at /opt/android-ndk-r30
sudo ln -sfn /opt/android-ndk-${NDK} /opt/android-ndk

cat >> ~/.bashrc << 'EOF'

# Android NDK
export ANDROID_NDK_HOME=/opt/android-ndk
EOF

source ~/.bashrc
```

> **Note:** the version comes from the [android/ndk](https://github.com/android/ndk/releases) GitHub releases, which carry every NDK release with betas/rcs flagged prerelease — but not through `lib.sh`'s `github_latest_release`. GitHub's "latest" is the most recently *created* stable release, and NDK point releases of an older line land after newer majors (r27d was published 2025-07-15, a week after r28c), so "latest" can walk backwards onto an LTS point release. `update-android.sh` reads the release list instead: stable tags only, highest by `sort -V` (r28c < r29 < r30). The zip is ~700 MB and unpacks to 2.3 GB. `source.properties` inside carries the `ndkVersion` form (`Pkg.Revision = 30.0.16248370`); the script keys its already-current check on the symlink's target name, which is the release form.
>
> Nothing from the NDK goes on `PATH` on purpose: its `toolchains/llvm/prebuilt/linux-x86_64/bin` carries its own `clang`, `lld` and `llvm-*` that would shadow the Fedora ones. `cargo-ndk` finds it through `ANDROID_NDK_HOME`; inspect outputs by path (`$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf`).

Rust Android targets — `aarch64-linux-android` is every real device and the one CI lints; `x86_64-linux-android` is the emulator's ABI:

```bash
rustup target add aarch64-linux-android x86_64-linux-android
```

> **Note:** both had been `rustup target add`ed by hand on the x86_64 box (alongside a dozen other cross targets that remain outside the pass) and sat outside it until 2026-10-08, the same drift as GraalVM and `samply` before them.

`cargo-ndk` — points cargo's linker and cc-rs's `CC`/`AR` at the NDK's per-target, per-API-level clang wrappers (`aarch64-linux-android21-clang` and friends) for the ABI asked for, so no per-target `linker =` lines in any `.cargo/config.toml`:

```bash
cargo install cargo-ndk
```

Usage — `-t` takes an Android ABI name or a Rust triple, everything after it is the cargo invocation, so the Hyper repos' `cargo cdylib` alias passes straight through:

```bash
cd ~/code/SkunkWerkx/HyperUuid/rust
cargo ndk -t arm64-v8a cdylib          # → target/aarch64-linux-android/release/libhyperuuid.so
cargo ndk -t x86_64 cdylib             # → target/x86_64-linux-android/release/libhyperuuid.so
cargo ndk -t arm64-v8a -o jniLibs cdylib   # -o additionally copies into jniLibs/<abi>/ for an APK
```

`--platform` (API level) defaults to 21, which is also NDK r30's own minimum (`meta/platforms.json`: min 21, max 37) and Rust's floor for the Android targets — nothing to set unless a build needs a newer `libc.so` symbol.

Verify:

```bash
grep Pkg.Revision $ANDROID_NDK_HOME/source.properties
$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --version
rustup target list --installed | grep android
cargo ndk --version
```

> **Verified on x86_64, 2026-10-08:** `./update-toolchain.sh android` installed r30 (clang 21.0.0, `Pkg.Revision = 30.0.16248370`) in 49 s wall; a second run was a clean no-op (`NDK already at r30 — skipping`, cargo-ndk `already installed`). Against HyperUuid's real `rust/` crate at `d32eb49`: `cargo ndk -t arm64-v8a cdylib` and `cargo ndk -t x86_64 cdylib` both linked, producing 20,224-byte (AArch64) and 24,296-byte (X86-64) `libhyperuuid.so` files whose only `NEEDED` is `libc.so` (Bionic — no `libgcc`, no `libc++`), each exporting the same 18 `uuid_*`/`hyperuuid_*` symbols, `hyperuuid_version`/`uuid_new_v4`/`uuid_new_v7`/`uuid_new_v7_batch` among them — the symbol set the iOS smoke test in `ci.yml` greps for. The CI lint line (`cargo clippy --target aarch64-linux-android -- -D warnings`) passes clean. Not run on a device or emulator: the toolchain covers compile+link, and there is no Android SDK or emulator on this machine.

**Updating:**

```bash
./update-toolchain.sh android     # resolves the newest stable NDK, swaps the /opt symlink, removes the superseded unpack
cargo install cargo-ndk
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

SwiftLint — the Hyper repos' `lint-docs-swift` CI gate (`swiftlint lint --strict Sources`, with a `.swiftlint.yml` that enables only `missing_docs`). The formatter is not a separate install: `swift format` ships in the toolchain, and the CI format gate is `swift format lint --strict --recursive`.

```bash
SL_VERSION=$(curl -s https://api.github.com/repos/realm/SwiftLint/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
wget https://github.com/realm/SwiftLint/releases/download/${SL_VERSION}/swiftlint_linux_${ARCH}.zip
unzip swiftlint_linux_${ARCH}.zip swiftlint-static
sudo install swiftlint-static /usr/local/bin/swiftlint
rm swiftlint-static swiftlint_linux_${ARCH}.zip

swiftlint version
swift format --version
```

> **Note:** the release zip carries two binaries. This installs `swiftlint-static` (as `swiftlint`), the one CI runs: it needs neither a Swift toolchain nor the `libxml2.so.2` soname the dynamically linked `swiftlint` is built against — the reason the forge's CI switched to it when Ubuntu 26.04 moved to `libxml2.so.16`. SwiftLint tags its releases bare (`0.65.1`, no `v`), unlike every other release-archive install in this doc. CI pins 0.65.1; this tracks latest, same as `revive` and `ruff`.
>
> **Verified on x86_64, 2026-10-06:** `./update-toolchain.sh swift` installed 0.65.1. From `HyperUuid/swift`, CI's own `swiftlint lint --strict Sources` passed (5 files, 0 violations); against a scratch file with three undocumented `public` declarations under the same `.swiftlint.yml` it reported all three and exited 2. `swift format lint --strict --recursive` (6.3.3, bundled) flagged the same scratch file's indentation and exited 1. The release also publishes `swiftlint_linux_arm64.zip`; not yet run on the Snapdragon.

**Updating Swift:**

```bash
swiftly self-update
swiftly update
```

Re-run the SwiftLint block for a new release — `sudo install` overwrites the binary in place.

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

rbspy — sampling profiler for Ruby. A standalone release binary rather than a gem, on purpose: a gem profiler (stackprof, Vernier) lives inside one Ruby's gem directory and would have to be reinstalled into every kept ABI after each rebuild, where one binary outside rbenv profiles whichever interpreter it is pointed at. Formatting and benchmarking are per-repo Gemfile dependencies (`bundle exec rubocop`, layout cops only; `benchmark-ips`), not installs here.

```bash
RBSPY_VERSION=$(curl -s https://api.github.com/repos/rbspy/rbspy/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
RBSPY_PKG=rbspy-$(uname -m)-unknown-linux-gnu
wget https://github.com/rbspy/rbspy/releases/download/v${RBSPY_VERSION}/${RBSPY_PKG}.tar.gz
tar -xzf ${RBSPY_PKG}.tar.gz
sudo install ${RBSPY_PKG} /usr/local/bin/rbspy
rm ${RBSPY_PKG} ${RBSPY_PKG}.tar.gz

rbspy --version
```

```bash
rbspy record -- ruby script.rb                                        # flame graph of a whole run
RBENV_VERSION=${RUBY_COMPAT} rbspy record -- ruby script.rb           # same, under the compat ABI
rbspy record --format summary --file out.txt --duration 30 --pid <pid>
```

> **Verified on x86_64, 2026-10-06:** `./update-toolchain.sh ruby` installed 0.53.0. `rbspy record --format summary --duration 3 -- ruby busy.rb` ran under both kept Rubies (3.4.11 and 4.0.7, selected with `RBENV_VERSION`, launched through the rbenv shim) without sudo, and each summary attributed ~98% of samples to the block inside the hot method by file and line. rbspy also drops the raw samples in `~/.cache/rbspy/` on every `record`. The release publishes `aarch64-unknown-linux-gnu` too; not yet run on the Snapdragon.

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

> **What php-build brings along, with nothing to install here:** every PHP it builds also gets **Xdebug** (the definition file pins it — `install_xdebug "3.5.3"` for 8.5.10 — and it lands enabled, `xdebug.mode=develop`, via `etc/conf.d/xdebug.ini`), **Composer**, and **PIE**, all in that version's `bin/`. Xdebug is the profiler: `XDEBUG_MODE=profile php -d xdebug.output_dir=. script.php` writes a `cachegrind.out.<pid>.gz` (confirmed on 8.5.10, 2026-10-06). It is also why every benchmark here runs `XDEBUG_MODE=off` — a loaded Xdebug inflates timings ~14x, uniformly, and looks plausible. Composer is what supplies the rest per repo: `vendor/bin/phpcs` is the format/lint gate and `vendor/bin/phpbench` the benchmark harness, both `require-dev`.

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

Diagnostics tools — `dotnet-trace` (EventPipe CPU/event traces) and `dotnet-counters` (live runtime counters). Formatting and benchmarking need no install: `dotnet format` is part of the SDK (the CI gate is `dotnet format whitespace <sln> --verify-no-changes`), and BenchmarkDotNet is a package reference in each repo's `*.Benchmarks` project.

```bash
dotnet tool install --global dotnet-trace
dotnet tool install --global dotnet-counters
```

```bash
dotnet-trace collect -o app.nettrace -- dotnet app.dll        # or: --process-id <pid>
dotnet-trace convert app.nettrace --format Speedscope         # → app.speedscope.json, opens in speedscope.app
dotnet-counters monitor --process-id <pid>                    # live GC / allocation rate / CPU / thread pool
dotnet-counters collect --format csv -o counters.csv -- dotnet app.dll
```

> **Verified on x86_64, 2026-10-06:** `./update-toolchain.sh dotnet` installed both at 10.0.745401 (first install is the module's own step — its update loop only touches tools already present). Against a `net11.0` console app: `dotnet-trace collect --duration 00:00:00:04` wrote a 407 KB `.nettrace`, `convert --format Speedscope` produced a profile carrying the app's hot method by name, and `dotnet-counters collect --format csv` recorded `dotnet.gc.heap.total_allocated` and `dotnet.process.cpu.time` once a second. The tools themselves ran with the 8.0/9.0/10.0/11.0 runtimes all present.

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

## Formatting / Profiling / Performance

What each toolchain uses for the three, and where it comes from. **Bold** is installed by this doc's modules; everything else is either bundled with the toolchain itself or a per-repo dependency the build tool resolves, so there is nothing to install for it. The formatting and performance columns are not picks — they are what the Hyper repos' CI gates and benchmark suites already run.

| Toolchain | Formatting | Profiling | Performance |
|---|---|---|---|
| Node / TypeScript | — (no repo carries a JS/TS formatter config) | `node --cpu-prof` (bundled) | — |
| [Go](#go) | `gofmt` (bundled) | `go tool pprof` (bundled) | `go test -bench` (bundled) + **benchstat** |
| [JVM](#java--kotlin-sdkman) | Spotless + palantir-java-format (Gradle plugin, per repo) | JFR (bundled) + **[async-profiler](#async-profiler)** | JMH (Gradle plugin, per repo) |
| [.NET](#net) | `dotnet format` (SDK) | **dotnet-trace**, **dotnet-counters** | BenchmarkDotNet (package, per repo) |
| [Rust](#rust) | **rustfmt** (rustup component) | **samply** | criterion (dev-dependency, per repo) |
| [WASM](#webassembly-wasm) | — | — | — |
| [Swift](#swift) | `swift format` (bundled) + **SwiftLint** (doc-comment lint gate) | **samply** / **perf** — a Swift executable is a native ELF | package-benchmark (SwiftPM, per repo) |
| [Ruby](#ruby) | rubocop (Gemfile, per repo) | **rbspy** | benchmark-ips (Gemfile, per repo) |
| [PHP](#php) | phpcs (Composer, per repo) | Xdebug (comes with php-build) | phpbench (Composer, per repo) — `XDEBUG_MODE=off` |
| [Python](#python) | **ruff** (`ruff format`) | **py-spy** | **pyperf** |
| any process | — | **perf**, **valgrind**, **heaptrack** | **hyperfine** |

The last row is the language-agnostic set — it works on a process or a binary, not a language, so it lives in the `tools` module rather than under any one stack:

```bash
sudo dnf install -y perf hyperfine valgrind
sudo dnf install -y --setopt=install_weak_deps=False heaptrack

perf --version
hyperfine --version
valgrind --version
heaptrack --version
```

> **Why heaptrack gets its own line and a flag:** Fedora ships it as a single package with the KDE GUI (`heaptrack_gui`) inside, so Qt6 and KDE Frameworks 6 come with it no matter what — 76 packages, 262 MiB. With dnf's default weak dependencies on top it is 130 packages, 336 MiB, the difference being udisks2, kio-extras, a set of filesystem tools and the Qt translations, none of which anything here uses. `install_weak_deps=False` is scoped to that one install; every other dnf line in this doc keeps the default.

```bash
perf stat -- ./bin                         # counters: cycles, instructions, branch/cache misses
perf record -g -- ./bin && perf report     # sampled call graph
hyperfine --warmup 3 'cmd-a' 'cmd-b'       # command-level A/B timing, mean ± σ and the ratio
valgrind --tool=callgrind ./bin            # exact instruction counts per function (callgrind_annotate)
valgrind --leak-check=full ./bin           # memcheck
heaptrack --record-only -o heap ./bin      # who allocated what → heap.gz; then heaptrack_print heap.gz
heaptrack -o heap ./bin                    # same, but opens heaptrack_gui on the result when it finishes
```

> **Verified on x86_64, 2026-10-06** (`./update-toolchain.sh tools`: perf 7.2.8, hyperfine 1.20.0, valgrind 3.27.1), against one small C workload: `perf stat` returned real **hardware** counters (`cycles`, `instructions`, `branch-misses`, `cache-misses`) under the WSL2 6.18 kernel — not just software clocks — and `perf record -g` / `perf report` put 98% in the hot function with its call chain (`kernel.perf_event_paranoid` is 1 here, no sudo needed). `hyperfine` measured a 2x workload as 1.98 ± 0.15x slower. `valgrind` memcheck found the deliberate 64-byte leak at its `malloc` line and honored `--error-exitcode`; callgrind attributed 99.04% of instructions to the hot function. The bundled cells were checked the same day rather than assumed: `node --cpu-prof` wrote a `.cpuprofile` naming the hot function, `go tool pprof -top` read a `go test -cpuprofile` capture, `perf` resolved a `swiftc -O -g` binary's hot symbol at 99%.
>
> `heaptrack` 1.5.0 went in through the same module (76 packages, 262 MiB, matching the dry run). `heaptrack --record-only` wrote `heap.gz` and `heaptrack_print` named the workload's one `malloc` by source line. Without `--record-only` the wrapper script opens `heaptrack_gui` on the result as soon as the run ends, and **blocks until that window is closed** — fine at a terminal (the GUI did come up through WSLg), a hang in anything unattended; found by having a scripted run stall on exactly that.
>
> **Not yet run on the Snapdragon.** Hardware counters in particular are a property of what the hypervisor exposes to the WSL2 kernel on that CPU, so the `perf stat` result above is an x86_64 finding, not a claim about arm64. The forge README's note that the arm64 WSL2 clock defeats the vDSO (~1µs per wall-clock read) applies to any timing done there.

> **Benchmarking rules that travel with these tools** (from `SkunkWerkx/.github`'s README, where they were learned): `XDEBUG_MODE=off` for PHP; never run benchmarks concurrently with builds or with each other; name the machine in every table.

---

## GitHub CLI

Auto-detects architecture at install time:

```bash
GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
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
AL_VERSION=$(curl -s https://api.github.com/repos/rhysd/actionlint/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
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
PS_VERSION=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
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

## Dell XPS-15-9510 (CUDA + llama.cpp)

Machine-specific: everything in this section applies only to the Dell XPS-15-9510 and is **not** part of `./update-toolchain.sh` — no module installs or updates any of it.

**Hardware, as WSL2 sees it:** Intel Core i9-11900H (8 cores / 16 threads; AVX2, AVX-512 F/BW/VL, AVX-512 VNNI), NVIDIA GeForce RTX 3050 Ti Laptop GPU (compute capability 8.6, 4 GiB VRAM, ~3.3 GiB free at idle), and the 40 GB / 12 processors / 8 GB swap that `.wslconfig` hands the distro.

### CUDA toolkit

The GPU driver lives on Windows; WSL2 exposes it through `/usr/lib/wsl/lib` (`libcuda.so`, `nvidia-smi`). Inside the distro you install the **toolkit only, never a driver package** — NVIDIA's CUDA-on-WSL guide says the same: no Linux display driver in WSL2, and install the `cuda-toolkit` package rather than the `cuda`/`cuda-drivers` meta-packages, which pull a driver. Confirmed after the install below: `rpm -qa` shows no `nvidia-driver`/`libnvidia`/`xorg-x11-drv-nvidia` packages.

Match the toolkit's minor version to the `CUDA UMD Version` that `nvidia-smi` reports (13.3 at the time of writing). The repo also carries a newer toolkit (13.4.x), which would only run via minor-version compatibility against an older driver — not worth it.

```bash
nvidia-smi | head -4                     # read "CUDA UMD Version"
sudo dnf config-manager addrepo --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora44/x86_64/cuda-fedora44.repo
sudo dnf install -y cuda-toolkit-13-3 cmake gcc15 gcc15-c++
```

The toolkit installs to `/usr/local/cuda-13.3` (with `/usr/local/cuda` and `/usr/local/cuda-13` symlinks) and is **not** put on `PATH` — the build below references `nvcc` by absolute path.

> **Gotcha — host compiler:** `nvcc` 13.3 rejects GCC newer than 15 (`crt/host_config.h`: `#if __GNUC__ > 15`), and Fedora 44's default `gcc` is 16. Fedora ships `gcc15`/`gcc15-c++` as compat packages (`/usr/bin/gcc-15`, `/usr/bin/g++-15`); point nvcc at them with `-ccbin g++-15` or, under CMake, `-DCMAKE_CUDA_HOST_COMPILER=g++-15`. No `-allow-unsupported-compiler`.

### llama.cpp

Built from source into `~/code/ggml-org/llama.cpp` — CUDA for sm_86, plus `-march=native` on the CPU backend so the AVX-512 paths are compiled in:

```bash
git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/code/ggml-org/llama.cpp
L=~/code/ggml-org/llama.cpp
cmake -S $L -B $L/build -G Ninja \
  -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda-13.3/bin/nvcc \
  -DCMAKE_CUDA_HOST_COMPILER=g++-15 \
  -DGGML_NATIVE=ON -DCMAKE_BUILD_TYPE=Release
cmake --build $L/build -j 12 --target llama-server llama-cli llama-bench

$L/build/bin/llama-cli --list-devices    # expect CUDA0: NVIDIA GeForce RTX 3050 Ti Laptop GPU
```

### Model: Qwen3-30B-A3B-Instruct-2507 (Q4_K_M)

4 GiB of VRAM holds only a ~4B dense model at Q4 with little room left for KV cache. The better fit for this box is a mixture-of-experts model whose ~3B active parameters per token make CPU-side expert evaluation fast enough: attention and KV cache on the GPU, expert tensors in system RAM. Qwen3-30B-A3B at Q4_K_M is 18.56 GB, which fits in the 40 GB WSL allocation with plenty to spare.

```bash
mkdir -p ~/models
curl -L --fail -o ~/models/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf \
  https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf
sha256sum ~/models/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf
# 6c997b8af17debdfb01d890214400ccbab00db6acc0ba8da5de1cc906c4774d0 (the file's LFS oid on Hugging Face)
```

Serve it (OpenAI-compatible API at `http://localhost:8080/v1`, web UI at `http://localhost:8080`):

```bash
~/code/ggml-org/llama.cpp/build/bin/llama-server \
  -m ~/models/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf \
  -ngl 99 -ot exps=CPU -t 6 -fa on -c 16384 --port 8080
```

- `-ngl 99 -ot exps=CPU` — every layer on the GPU *except* the MoE expert tensors, which the override pins to CPU.
- `-t 6` — measured faster than `-t 12` (below); the 12 WSL processors are hyperthreads over 8 physical cores.
- **Don't** spend the spare VRAM on experts (`--n-cpu-moe` < 48): it measured no faster, and at `--n-cpu-moe 40` prompt processing collapsed to ~61 t/s — consistent with the Windows driver spilling VRAM into shared system memory, though that cause wasn't confirmed.

> **Verified, 2026-10-08:** llama.cpp `71ad059`, CUDA 13.3.73 with GCC 15.3.1 as host compiler. A standalone `nvcc -ccbin g++-15 -arch=sm_86` test kernel wrote `42` into device memory and copied it back with `no error`. `llama-bench` (pp512 / tg128, `-fa 1`, `-ngl 99 -ot exps=CPU`): `-t 6` 285.99 ± 10.53 / 13.10 ± 1.50 t/s; `-t 12` 241.52 ± 14.77 / 12.45 ± 0.61 t/s. Throughput degraded across back-to-back runs — a later 5-rep rerun of the same `-t 6` config measured 196.28 ± 28.20 / 8.01 ± 3.14 t/s — so treat any single number as noisy; sustained-load throttling is the suspected cause but CPU thermals aren't visible from inside WSL, so it's unverified. End to end through `llama-server`: a real `/v1/chat/completions` request returned a correct answer, generating at 18.50 t/s (40 tokens), with 2,683 MiB VRAM in use.

**Updating:** `git -C ~/code/ggml-org/llama.cpp pull` and re-run the `cmake` configure + build lines. If a Windows driver update raises `nvidia-smi`'s `CUDA UMD Version`, install the matching `cuda-toolkit-13-N`, `dnf remove` the old one, swap the `cuda-13.3` path in the configure line, and re-check `crt/host_config.h` for the newest GCC that toolkit accepts.

---

## Verified Environment

```
Node.js   v24.18.0       (Krypton LTS)
npm       12.0.1
tsc       7.0.2          (Go-native compiler, GA since 2026-07-08 — no longer @rc)
go        1.26.5         linux/arm64
gopls     0.23.0
dlv       1.27.0
benchstat v0.0.0-20260929162123-406019bb8b68   golang.org/x/perf, `go test -bench` comparison (x86_64, 2026-10-06)
java      25.0.4         Temurin LTS
graalvm   25.4.4.1+1     GraalVM CE (java 25.0.4.1.1, native-image 25.0.4.1.1), SDKMAN-managed alongside Temurin — never `current`
async-profiler 4.5      /opt/async-profiler, asprof + jfrconv symlinked into /usr/local/bin (x86_64, 2026-10-06)
kotlin    2.4.20
gradle    9.8.0
python    3.14.5         GIL enabled (standard build; 3.14.5t available via pyenv local/shell for free-threaded testing)
mypy      2.4.0          pip, pyenv global build — the bindings' `test` extra (x86_64, 2026-10-06)
pyperf    2.10.0         pip, pyenv global build — the bindings' `bench` extra (x86_64, 2026-10-06)
py-spy    0.4.2          pip, pyenv global build — sampling profiler (x86_64, 2026-10-06)
rustc     1.97.1         aarch64-unknown-linux-gnu
cargo     1.97.1
nextest   0.9.140         prebuilt aarch64-unknown-linux-gnu binary, not cargo-installed
samply    0.13.1          cargo install --locked — profiler for the native core (x86_64, 2026-10-06)
cargo-semver-checks 0.51.0  cargo install --locked — local twin of the check-semver CI job (x86_64, 2026-10-06)
wasm-pack 0.15.0          cargo install — wasm-bindgen test runner, `wasm` module (x86_64, 2026-10-06)
android-ndk r30           30.0.16248370, clang 21.0.0 — /opt/android-ndk symlink, ANDROID_NDK_HOME; x86_64 host only, `android` module (x86_64, 2026-10-08)
cargo-ndk 4.1.2           cargo install — NDK linker/sysroot wiring for aarch64-/x86_64-linux-android (x86_64, 2026-10-08)
swiftly   1.1.3           toolchain manager
swift     6.3.3           aarch64-unknown-linux-gnu (via swiftly --platform fedora39, see Swift section)
swiftlint 0.65.1          swiftlint-static from the release zip, installed as /usr/local/bin/swiftlint (x86_64, 2026-10-06)
ruby      4.0.6           aarch64-linux, via rbenv/ruby-build, global — primary Magnus ABI + Fiddle suite host
ruby      3.4.10          compat Magnus ABI (HyperUuid ci.yml ruby_compat_version), RBENV_VERSION-selected
rbspy     0.53.0          release binary in /usr/local/bin — profiles both Ruby ABIs (x86_64, 2026-10-06)
php       8.5.9           via phpenv/php-build, built --with-ffi — host for ext-php-rs and FFI extension dev
cargo-php 0.1.21          ext-php-rs's build/install CLI
dotnet    10.0.302       (+ 9.0.18, 8.0.29 runtimes for multi-target test execution)
dotnet-11 11.0.100-preview.6.26359.118   TEMPORARY preview channel (Norse DU work) — see its own section
dotnet-trace    10.0.745401   global tool — EventPipe traces (x86_64, 2026-10-06)
dotnet-counters 10.0.745401   global tool — live runtime counters (x86_64, 2026-10-06)
mono      6.14.1         legacy net472/net462 test execution
playwright-mcp 0.0.78    @playwright/mcp, via npx, no persistent install
chromium  150.0.7871.114 dnf-managed, not Playwright-downloaded
gh        2.99.0
actionlint 1.7.12       GitHub Actions workflow linter
shellcheck 0.11.0       dnf-managed; actionlint's `run:`-body integration
pyflakes  3.1.0          dnf-managed (python3-pyflakes); actionlint's `python`-step integration
pwsh      7.6.5
perf      7.2.8          dnf-managed — hardware counters confirmed under WSL2 on x86_64 (2026-10-06)
hyperfine 1.20.0         dnf-managed — command-level A/B timing (x86_64, 2026-10-06)
valgrind  3.27.1         dnf-managed — callgrind / memcheck (x86_64, 2026-10-06)
heaptrack 1.5.0          dnf-managed, installed without weak deps — heap allocation profiler (x86_64, 2026-10-06)
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
*Formatting / profiling / performance tooling added 2026-10-06, on the x86_64 box — see the [matrix](#formatting--profiling--performance). New installs: `benchstat` (`go`), `async-profiler` (`jvm`), `dotnet-trace`/`dotnet-counters` (`dotnet`), `rbspy` (`ruby`), `SwiftLint` (`swift`), `mypy`/`pyperf`/`py-spy` (`python`), `perf`/`hyperfine`/`valgrind`/`heaptrack` (`tools`). Folded into the pass from hand-run installs that had been sitting outside it, the same drift the 2026-09-04 GraalVM entry describes: `samply` and `cargo-semver-checks` (`rust`), `wasm-pack` (`wasm`). Every one was installed by its own module's `./update-toolchain.sh <module>` run and then exercised against a real workload, not just `--version`; the Verified notes in each section carry the receipts. Rows above marked `(x86_64, 2026-10-06)` have **not** been run on the Snapdragon: each release-archive install publishes an arm64 asset and py-spy an aarch64 wheel (checked), but nothing arm64 was executed. `scripts/lib.sh`'s `github_latest_release` changed in the same pass — it now anchors on the `tag_name` key, because SwiftLint tags releases without a `v` and because the API was caught returning the whole release object on one line (for `rhysd/actionlint`), a shape the old line-oriented pattern survived only by accident.*
*`android` module added 2026-10-08 on the x86_64 box — see [Android (NDK)](#android-ndk). The NDK (r30) from Google's release zip under `/opt`, Rust's two Android targets (already on the box by hand, folded into the pass), and `cargo-ndk`. Verified by linking HyperUuid's real cdylib for both `aarch64-linux-android` and `x86_64-linux-android` through the NDK and inspecting the ELF outputs with the NDK's `llvm-readelf`, plus the CI lint line; the section's Verified note has the receipts. Not runnable on the Snapdragon: Google publishes no linux-aarch64 NDK host build, so there the module is a loud exit-0 skip rather than a failed pass.*
*`php` rebuilt `--with-ffi` and re-verified 2026-08-27 — HyperUuid's actual Ruby/PHP bindings ended up on the same dlopen-a-shared-`cdylib` architecture as the Go/Swift bindings (Fiddle for Ruby, `FFI` for PHP) rather than the compiled-native-extension path (`rb-sys`/`ext-php-rs`) the 2026-08-26 entry above verified — that path stays documented since it's still a legitimate way to build Rust↔Ruby/PHP native extensions, just not the one this project used. Ruby's `Fiddle` needed no toolchain change (stdlib); PHP's `FFI` extension wasn't in the default `php-build` configure line at all, hence the rebuild.*

---

## Full Update Pass

Run this periodically to bring the entire toolchain current:

```bash
./update-toolchain.sh              # every module, in order
./update-toolchain.sh dotnet go    # or just the modules you want
```

`update-toolchain.sh` is the executable, replay-safe version of this pass — each `scripts/update-*.sh` module is a no-op or clean overwrite when already current, and the `Go`, `jvm`, `.NET`, and `docker` modules additionally remove whatever they're superseding (old `/usr/local/go`; superseded SDKMAN patch releases within each major series; every stale SDK/runtime/pack/manifest-band across all four .NET channels, not just the 11.0 preview one; dangling images and containers pinned to a superseded image) rather than leaving it to accumulate. Modules: `base` (the [Base Dependencies](#base-dependencies) dnf list — the single one every language module's from-source build shares), `node` (npm + TypeScript), `go` (plus gopls, dlv, revive, benchstat), `jvm` (Java/Kotlin/Gradle, plus [GraalVM CE](#graalvm-ce-native-image) resolved against the Temurin default's major since `sdk upgrade` can't see it; patch-release prune; [async-profiler](#async-profiler) from its release tarball), `dotnet` (LTS + 9.0/8.0 runtimes + 11.0 preview, full stale-version prune, first install of `dotnet-trace`/`dotnet-counters`, `dotnet new`/`tool`/`workload` updates — prerelease-versioned tools like `dotnet-ef` track the preview channel until GA outranks it), `rust` (rustup, components, cargo tools including `samply` and `cargo-semver-checks`, nextest), `wasm` ([WebAssembly (WASM)](#webassembly-wasm): Rust's `wasm32-wasip1`/`wasm32-unknown-unknown`/`wasm32-unknown-emscripten` targets, `wasm-pack`, Emscripten SDK, wasmtime, .NET's `wasm-tools` workload), `android` ([Android (NDK)](#android-ndk): the NDK release zip under `/opt` with the superseded unpack removed, Rust's `aarch64-linux-android`/`x86_64-linux-android` targets, `cargo-ndk` — x86_64 host only, a loud exit-0 skip on the Snapdragon), `swift` (swiftly self-update + in-use toolchain update, which prunes the superseded toolchain itself; SwiftLint from its release zip), `ruby` (rbenv/ruby-build, newest patch of the primary series + each `RUBY_COMPAT_SERIES` entry, prunes everything else; `rbspy` from its release tarball), `php` (phpenv/php-build, prunes the superseded PHP build, re-installs `cargo-php` against the new build), `python` (plus maturin, pytest, ruff, mypy, pyperf, py-spy into the global build), `tools` (gh, [actionlint](#actionlint) + ShellCheck/pyflakes, pwsh, Mono, Chromium, perf/hyperfine/valgrind/heaptrack, posh-git-sh), `docker` (image refresh, dangling-image prune, clean-slate container removal). Claude Code isn't a module — it auto-updates itself on the `latest` channel.

`base`, `node`, `go`, `jvm`, `dotnet`, `rust`, `swift`, `ruby`, `php`, and `python` all bootstrap their own prerequisite when it's missing (fnm, Go itself, SDKMAN, dotnet, rustup, swiftly, rbenv, phpenv, pyenv respectively) rather than hard-failing — a fresh machine with nothing but `git`/`curl` on it runs `./update-toolchain.sh` end to end. `tools` never had a hard-fail prerequisite to begin with (every install there is unconditional or version-diffed). `docker`, `wasm` and `android` are the three exceptions: Docker Desktop's WSL integration is a manual Windows-side toggle (see [Docker](#docker)) that can't be scripted from inside WSL, `wasm` depends on `rust` and `dotnet` already being installed (both run earlier in `MODULES`), and `android` on `rust` — all hard-fail with a pointer back to the relevant section rather than bootstrapping a prerequisite themselves. `android` has one more exit that isn't a failure: on a non-x86_64 host it prints that no NDK host build exists for the architecture and exits 0, so a Snapdragon full pass keeps going (see [Android (NDK)](#android-ndk)).

The command-by-command breakdown for each stack lives in that stack's own section above (e.g. [Go](#go), [.NET](#net)) — treat those as the reference for *what* each step does; `scripts/update-*.sh` is the reference for *exact, current* invocation. If they drift, the scripts win — update the docs above to match rather than editing this block, since this block just points at them.
