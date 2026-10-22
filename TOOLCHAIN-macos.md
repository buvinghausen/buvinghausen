# toolchain-macos.md — macOS Polyglot Dev Environment

**Machine:** Mac mini (Apple M6, arm64, 32 GB)
**OS:** macOS 27.0.1
**Shell:** zsh

The macOS twin of [TOOLCHAIN.md](TOOLCHAIN.md). Same orchestrator (`./update-toolchain.sh` picks `scripts/macos/` on Darwin, `scripts/` elsewhere), same module names, same replay-safe / version-diff / prune policies — this document only spells out where macOS differs and why, and carries the macOS receipts. For what each tool is *for* (which CI gate it mirrors, which Hyper* binding it builds), the Fedora doc's section of the same name is the reference; it isn't repeated here.

> **Three rules that differ from the Fedora pass, box-wide:**
>
> 1. **Homebrew is the package manager** — the `dnf` analogue. Everything Fedora takes from dnf or from a Linux release tarball that Homebrew also carries at the same version (`gh`, `actionlint`, `shellcheck`, `mono`, `hyperfine`, `swiftlint`, `fnm`, `php`) comes from `brew`. Upstream installers (rustup, pyenv, SDKMAN, rbenv, dotnet-install.sh, emsdk, wasmtime) are unchanged — they support Darwin natively.
> 2. **Nothing runs as root.** Where Fedora writes to `/usr/local/{bin,go}` and `/opt`, this pass uses the user-owned twins: `~/.local/bin` (already first on `PATH` — Claude Code's installer put it there), `~/.local/go`, `~/.local/opt/*`. Homebrew itself is user-owned under `/opt/homebrew`, so this is the platform's own convention, not a workaround. The only sudo anywhere is two one-time steps that stay manual: Xcode's `xcode-select -s` / `-license accept` (see [Swift](#swift)) and the Rosetta 2 install (see [Base Dependencies](#base-dependencies)).
> 3. **`~/.zshrc` is the rc file.** zsh is the login shell; every upstream installer in the pass that self-wires a profile (fnm, SDKMAN, wasmtime) already targets `.zshrc` on Darwin, and `scripts/macos/lib-macos.sh`'s `append_zshrc_once` is the `append_bashrc_once` twin for the rest. `~/.zprofile` holds only what was there before this pass (Homebrew's `shellenv`, Docker Desktop's `PATH` line).

> **Prerequisites the pass assumes** (both present on this box before the first run): Homebrew, and the Xcode Command Line Tools (`xcode-select --install`) — the compiler, linker, `make`, `git`, `libclang` (for `bindgen`) and Apple Swift all come from the CLT. `scripts/macos/update-base.sh` hard-fails if `xcode-select -p` has nothing selected.

> **The scripts run under Homebrew bash 5.3**, not `/bin/bash` 3.2: `update-jvm.sh`'s prune uses associative arrays. `base` installs it; `update-toolchain.sh` does `hash -r` before each module so the one launched right after `base` resolves `bash` to the new binary rather than the hashed 3.2. BSD-vs-GNU, checked rather than assumed on this box: `sort -V`, `readlink -f`, `sed 's/x/\nx/'` (newline in a replacement) and `xargs -r` all work; `find` has no `-printf` (the jvm prune lists directories with a glob instead); `grep` is BSD "GNU compatible"; `tar` is bsdtar; `uname -m` prints `arm64`, which `lib.sh`'s `arch_amd64_arm64`/`arch_x64_arm64` already pass through as the right token.

---

## Base Dependencies

The one Homebrew list every from-source build in this pass draws on — `brew_build_deps` in `scripts/macos/lib-macos.sh`, called by `update-base.sh` on every pass and by the python/ruby modules' first-time bootstrap. Smaller than Fedora's: php is a Homebrew prebuilt (no php-build headers), Swift comes with the CLT (no swiftly prerequisites), and the compiler is the CLT's.

```zsh
brew update
brew install bash pkgconf autoconf automake libtool \
  openssl@3 readline sqlite xz zlib zstd libb2 \
  libyaml gmp libffi
```

Who needs what:

- **the scripts:** `bash` (5.x — see the bash note above).
- **pyenv** ([suggested build environment](https://github.com/pyenv/pyenv/wiki#suggested-build-environment), macOS): `openssl@3 readline sqlite xz zlib zstd libb2 pkgconf`. The wiki also lists `tcl-tk@8`; it is **deprecated** in Homebrew and nothing here needs tkinter, so it's left out — `pyenv install` builds without `_tkinter` and says so in its warnings.
- **ruby-build** ([suggested build environment](https://github.com/rbenv/ruby-build/wiki#suggested-build-environment), macOS): `openssl@3 readline libyaml gmp autoconf`. The same wiki warns that a Homebrew `binutils` on `PATH` breaks the Ruby build (its `ar`/`ranlib` shadow the system ones) — deliberately not installed.
- **autotools** (`autoconf automake libtool pkgconf`) for both configure runs; `libffi` for ctypes/Fiddle.

> **Rosetta 2** is a box-level prerequisite `update-base.sh` checks after the CLT: the Hyper repos' osx-x64 leg is cross-built on Apple silicon and its own `cargo test` runs under Rosetta, and an arm64 Mac without it fails every x86_64 binary with `Bad CPU type in executable`. Its installer needs sudo, so the module does what it does for an unselected Xcode — stops and prints the one command:
>
> ```zsh
> sudo softwareupdate --install-rosetta --agree-to-license
> ```
>
> The check is `arch -x86_64 /usr/bin/true`; it failed on this box before Rosetta was installed, which is what found the gap.

> `brew update` is the index refresh (the `dnf makecache` analogue), not a package upgrade. The pass deliberately never runs a blanket `brew upgrade` — the same stance the Fedora module takes by skipping `dnf update -y`. Each module `brew install`s then `brew upgrade`s its own formulae (`brew_ensure`), both no-ops when current, which gives `dnf install -y`'s present-and-latest semantics.

---

## Node.js / TypeScript

fnm from Homebrew — fnm's own curl installer just shells out to `brew install fnm` on macOS and then edits `~/.zshrc` itself; calling brew directly keeps the rc wiring under `append_zshrc_once` like every other module. The hook is zsh's:

```zsh
brew install fnm
cat >> ~/.zshrc << 'EOF2'

# fnm
eval "$(fnm env --use-on-cd --shell zsh)"
EOF2
source ~/.zshrc
fnm install --lts && fnm default lts-latest
npm install -g npm@latest typescript@latest
```

Everything else (Krypton LTS, keep-only-`fnm current` prune, Go-native `tsc` 7) is as on Fedora; `scripts/macos/update-node.sh` is the replay-safe form.

---

## Go

The raw `darwin-arm64` tarball, into `~/.local/go` instead of `/usr/local/go` — Go derives `GOROOT` from where its binary lives, so the path is free, and this one needs no sudo. TinyGo's `darwin-arm64` tarball goes under `~/.local/tinygo` exactly as on Fedora.

```zsh
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
ARCH=$(uname -m | sed 's/x86_64/amd64/')
curl -fsSLO https://go.dev/dl/${GO_VERSION}.darwin-${ARCH}.tar.gz
rm -rf ~/.local/go && tar -C ~/.local -xzf ${GO_VERSION}.darwin-${ARCH}.tar.gz
rm ${GO_VERSION}.darwin-${ARCH}.tar.gz

cat >> ~/.zshrc << 'EOF2'

# Go
export PATH=$PATH:$HOME/.local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF2
```

gopls, dlv, revive, benchstat (`go install`) and TinyGo (release tarball, same `~/.local/tinygo` tree) are unchanged — `scripts/macos/update-go.sh` — with one addition: **`brew install binaryen`**. The darwin TinyGo tarball's `bin/` carries only `tinygo`, no `wasm-opt` (the Linux one bundles it), and `tinygo build -target wasm` hard-fails without one ("could not find wasm-opt" — hit on the first run here). TinyGo's own Homebrew formula declares `binaryen` as its dependency, so that is the source; `~/emsdk/upstream/bin/wasm-opt` would also work via `WASMOPT=`, but that couples the go module to the wasm one, which runs later.

---

## Java / Kotlin / Gradle (SDKMAN) · GraalVM CE · async-profiler

SDKMAN's installer supports Darwin and writes its block into `~/.zshrc` itself (and `~/.bashrc`). `sdk install java` resolves the Temurin LTS for `darwinarm64`; the GraalVM CE lookup in `update-jvm.sh` is keyed on `$SDKMAN_PLATFORM`, so the same resolver that picks `25.4.4.1+1-graalce` on `linuxarm64` picks it here — verified against the `versions/all` endpoint before the first run. Install and update exactly as on Fedora.

Two macOS-specific lines in `scripts/macos/update-jvm.sh`:

- the prune loop lists each candidate's versions with a directory glob (BSD `find` has no `-printf`), excluding the `current` symlink by name;
- async-profiler's macOS release is a **universal zip**, not a tarball: its single top-level directory becomes `~/.local/opt/async-profiler` (asprof loads `../lib/libasyncProfiler.dylib` relative to its own path, so the tree stays together), with `asprof`/`jfrconv` symlinked into `~/.local/bin`.

```zsh
AP_VERSION=$(curl -s https://api.github.com/repos/async-profiler/async-profiler/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
curl -fsSLO https://github.com/async-profiler/async-profiler/releases/download/v${AP_VERSION}/async-profiler-${AP_VERSION}-macos.zip
unzip -q async-profiler-${AP_VERSION}-macos.zip
rm -rf ~/.local/opt/async-profiler && mv async-profiler-${AP_VERSION}-macos ~/.local/opt/async-profiler
ln -sf ~/.local/opt/async-profiler/bin/asprof ~/.local/bin/asprof
ln -sf ~/.local/opt/async-profiler/bin/jfrconv ~/.local/bin/jfrconv
rm async-profiler-${AP_VERSION}-macos.zip
```

---

## Python

pyenv via `pyenv.run` as on Fedora; build deps from [Base Dependencies](#base-dependencies) (python-build finds Homebrew's `openssl@3`/`readline`/`sqlite`/`xz`/`zlib` itself). Same standard + free-threaded pair, same GIL-enabled global default, same prune, same pip tool list — `scripts/macos/update-python.sh`.

```zsh
curl https://pyenv.run | bash
cat >> ~/.zshrc << 'EOF2'

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - zsh)"

# GIL enabled by default (yt-dlp and other GIL-dependent tools need it).
# Flip to free-threaded for testing: export PYTHON_GIL=0
EOF2
```

Plus **Pyodide's Python series** beside the global: `PYTHON_PYODIDE_SERIES=3.14` in `scripts/macos/update-python.sh`. pyodide-build only builds for the Python minor its Pyodide release embeds, and the host interpreter has to be that minor — the Forge's `hyper-build-wheels.yml` pins `PYODIDE_VERSION` `314.0.7` on `python-version: "3.14"`. The module installs the newest 3.14.x, puts `pyodide-build` into that build's own site-packages (not the global's), and removes superseded 3.14 patches; edit the series when the pin's minor moves. The per-release cross-build environment and its Emscripten are not toolchain: `pyodide xbuildenv install <version>` / `install-emscripten` fetch them per run, as the Forge does.

> **The other floors are containers, not host installs.** Python 3.11, Ruby 3.3, PHP 8.2 and Swift 6.2 — each binding's declared floor — run in the Forge's `musl-suite` / `swift-static-suite` scripts inside Docker (`python:<floor>-alpine`, `ruby:<floor>-alpine`, `php:<floor>-cli-alpine`, `swift:<version>`), so on this box they come from [Docker](#docker), and the host keeps one toolchain per language.

> **Local test loop for a binding** (HyperUuid's `python/`): a venv, then `maturin develop --release` and `pytest` from that directory — the tests import from `src/`, so the extension has to be built in place; a `pip install ./python[test]` wheel build leaves `src/hyperuuid` without its `_native` and every collection fails on it. The pyenv global build's `maturin`/`pytest` are on the shims path only while no venv shadows them — install both into the venv.
>
> **py-spy on macOS needs sudo to attach** to a running process (SIP — py-spy's own README: "OSX always requires running as root"). `py-spy record -- python x.py`, where py-spy spawns the target, does not. The same applies to rbspy below. Nothing in the pass runs as root; this is a per-invocation `sudo` when you actually attach.

---

## Rust

rustup-init is the same on every platform and leaves profile wiring to the caller (`--no-modify-path` makes that explicit); `~/.zshrc` gets the `. ~/.cargo/env` line. The one asset change is cargo-nextest's prebuilt binary: `get.nexte.st/latest/mac` resolves to the `universal-apple-darwin` tarball.

```zsh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
cat >> ~/.zshrc << 'EOF2'

# Rust
source "$HOME/.cargo/env"
EOF2
source ~/.cargo/env
rustup component add rust-analyzer clippy rustfmt
rustup target add thumbv7em-none-eabi
cargo install cargo-watch cargo-edit
cargo install --locked samply cargo-semver-checks
curl -LsSf https://get.nexte.st/latest/mac | tar zxf - -C ${CARGO_HOME:-~/.cargo}/bin
```

Two additions over Fedora's module, both for the Hyper repos' CI parity:

- **Apple targets** — `x86_64-apple-darwin` (the osx-x64 cdylib, tested under Rosetta) and `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `aarch64-apple-ios-macabi`, `x86_64-apple-ios-macabi` (the static libraries behind the Swift xcframework, Go's `go/staticlib/ios_*` and C#'s iOS / Mac Catalyst apps), the same list the Forge's `apple_mobile` build uses.
- **Static-library targets** — `x86_64`/`aarch64` `-unknown-linux-gnu`, `-unknown-linux-musl` and `-pc-windows-msvc`, plus the `llvm-tools` component: the rest of the Forge's `build-static-libs.sh` set (a static library is compiled, never linked, so all of them cross-build here with no C toolchain; the archive trim uses `llvm-tools`' `llvm-ar`). The script adds them itself when missing — that is how they were found — and the module keeps them current with stable.
- **MSRV toolchains** — `RUST_MSRV_SERIES=(1.85 1.88)` in `scripts/macos/update-rust.sh`, every `rust-version` the Hyper repos declare (HyperUuid 1.85; HyperCast and HyperTabular 1.88), installed `--profile minimal` so `cargo +1.85 check --lib` reproduces each `ci.yml`'s `check-msrv` job. Same role as the Ruby module's `RUBY_COMPAT_SERIES`: edit it when a `rust-version` moves. `rustup toolchain install 1.85` names the toolchain by its series and lands each point release in place; any pinned toolchain outside the list is uninstalled, stable and nightly are left alone.

`samply` is the profiler on macOS too (it samples through the Mach task APIs there, no `perf` involved) — see [Formatting / Profiling / Performance](#formatting--profiling--performance). `scripts/macos/update-rust.sh` is the replay-safe form.

---

## WebAssembly (WASM)

Unchanged in substance — `scripts/macos/update-wasm.sh`: the three Rust targets, `wasm-pack`, the Emscripten SDK (`git clone` into `~/emsdk`, supports arm64 macOS — but its tooling needs **Python ≥ 3.10** and the CLT ships 3.9.6, so the module installs Homebrew's `python` and names it through `EMSDK_PYTHON`; found by the first run failing with exactly that message), wasmtime (its installer's `detect_profile` writes `~/.zshrc` for a zsh `$SHELL`), .NET's `wasm-tools` workload, and the `wasm-opt` patch loop over every installed `Microsoft.NET.Runtime.Emscripten.*.Sdk.*` pack (the `osx-arm64` pack matches the same glob; the bug it fixes is the same rustc ≥ 1.87 vs. bundled Binaryen mismatch documented in the Fedora doc).

---

## Android (NDK · SDK)

The first box in the pass where Android works on arm64: Google ships a macOS host build (universal binaries), so the Fedora module's "no aarch64 Linux host" skip has no counterpart here. The archive is the darwin **zip** (`android-ndk-<release>-darwin.zip` — same contents as the `.dmg` Homebrew's cask uses, minus the disk-image mount). Inside, the NDK root sits in an app bundle, `AndroidNDK<build>.app/Contents/NDK`; `scripts/macos/update-android.sh` locates it by its `source.properties` (exactly one, or it fails with the real listing) and moves it to `~/.local/opt/android-ndk-<release>`, with the version-free `~/.local/opt/android-ndk` symlink as the stable `ANDROID_NDK_HOME`. Release resolution (stable tags, highest by `sort -V`), symlink swap, superseded-tree removal, the two Rust Android targets and `cargo-ndk` are all as on Fedora.

```zsh
cat >> ~/.zshrc << 'EOF2'

# Android NDK
export ANDROID_NDK_HOME=$HOME/.local/opt/android-ndk
EOF2
```

> The LLVM prebuilt directory is `toolchains/llvm/prebuilt/darwin-x86_64` even on Apple Silicon — the binaries are universal. The module resolves it by glob and prints it in its verify step rather than hardcoding either name. Nothing from the NDK goes on `PATH`, same reasoning as Fedora: its `clang`/`lld` would shadow the CLT's.

**The Android SDK, macOS only.** The Hyper repos' `test-android` job builds the C# binding's APKs with the .NET `android` workload and runs them, plus the cross-built Go and Swift suites, on an emulator. That takes the SDK the Fedora module skips — it skips sdkmanager because it needs the command-line-tools package and a JDK, and on this box both are in hand. Under `~/.local/opt/android-sdk` (`ANDROID_HOME`):

- **bootstrap only:** the newest `commandlinetools-mac_<arch>` zip, named in Google's `repository2-3.xml` under the `cmdline-tools;latest` package, unpacked to `cmdline-tools/latest` — the one layout sdkmanager accepts. After that `sdkmanager --update` keeps it, and everything else, current.
- **`platform-tools`** (adb), **`emulator`**, and **`system-images;android-36;google_apis_ps16k;arm64-v8a`** — `ci.yml`'s emulator (`api-level: 36`, `target: google_apis_ps16k`), arm64 for this host where CI's runner is x86_64 — with one AVD on it, `hyper-api36`.
- **the platform and build-tools the workload builds against**, read from the workload's own defaults (`AndroidSdkPlatformVersion`, `AndroidSdkBuildToolsVersion` in its newest `Microsoft.Android.Sdk.Darwin` pack: `platforms;android-37.0` and `build-tools;37.0.0` for workload 37.2.0-rc.2), so they follow `dotnet workload update`; any platform or build-tools the workload no longer names is uninstalled. That is why `android` needs the `dotnet` module to have run, as well as `jvm` for sdkmanager's JDK.

```zsh
cat >> ~/.zshrc << 'EOF2'

# Android SDK
export ANDROID_HOME=$HOME/.local/opt/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator
EOF2
```

> **JDK:** `ci.yml` pins `setup-java` 21 for the workload's build tasks, but the workload itself declares `MinimumSupportedJavaVersion` 21.0 and `LatestSupportedJavaVersion` 25.0.99, so the Temurin 25 default already qualifies and no second JDK is installed. (SDKMAN's darwinarm64 index also carries Temurin 21 only as the 2023 GA, `21.0.0.0+35-tem`; Adoptium itself is at 21.0.12.1.)
>
> **Licenses:** no `sdkmanager --licenses` step. Command-line-tools 23 says the option `is no longer needed`; with `licenses/` removed, `sdkmanager --install` still installed a platform and wrote `licenses/` itself. It also prints that sdkmanager is deprecated, with `android sdk` (the `android` binary in the same `cmdline-tools/latest/bin`) as its replacement. sdkmanager still works, so the module stays on it until it doesn't.

---

## Swift

Apple's toolchain, not swiftly's. The Command Line Tools ship `swift`, SwiftPM and `swift format`; full Xcode adds the platform SDKs (iOS — the Hyper repos' `ci.yml` iOS smoke test) and Instruments / `xctrace`. Both update through Apple (`softwareupdate`, the App Store), so there is no toolchain install or prune in `scripts/macos/update-swift.sh` — it verifies the Apple side is selected and keeps SwiftLint current from Homebrew, which carries the same `0.65.x` the Hyper CI pins.

**Xcode is a manual, one-time install** — the App Store, the signed `.xip` from https://developer.apple.com/download/all/ (`xip --expand`, then move `Xcode.app` to `/Applications`), or `xcodes install --latest --select` from the `xcodesorg/made` tap; all three need an Apple ID, the last two skip the App Store — followed by three commands, the only sudo anywhere in this toolchain:

```zsh
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

The module hard-fails with exactly those lines when `/Applications/Xcode.app` exists but isn't the selected developer directory; when Xcode is absent it reports that the CLT Swift is in use and continues — a documented state, not a failure.

```zsh
brew install swiftlint
swift --version
swift format --version
swiftlint version
```

> **What the CLT alone cannot do, found by running it:** `swift build` and `swift format` work; **`swift test` does not** — the CLT ships `Testing.framework` (swift-testing) but no `XCTest.framework`, and HyperUuid's suite imports XCTest (`unable to resolve module dependency: 'XCTest'`). That is Xcode's. **SwiftLint crashes** on a CLT-only box (`Fatal error: Loading sourcekitdInProc.framework ... failed`, exit 133): it searches every Xcode toolchain path for sourcekitd and never the CLT's, although the CLT has it under `usr/lib`. `TOOLCHAIN_DIR` is the override it honors — with `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools`, `swiftlint lint --strict Sources` over HyperUuid's six files ran clean. The module exports it for its own run and wires a guarded line into `~/.zshrc` that sets it only while the CLT is the selected developer directory, so it falls away by itself once Xcode is.

> **swiftly, for Swift SDKs only.** Apple's Swift stays the toolchain — it is what GitHub's macOS runners use for the Hyper repos' macOS legs. But it cannot use swift.org's Swift SDKs: the Hyper repos cross-build their Swift suite for Android with swift.org's Android SDK (`.github/scripts/android_build_suite.sh`), and under Xcode 27.1's Swift 6.4 that build stopped on every file with `compiled module was created by a different version of the compiler ''; rebuild 'Foundation'`. So `update-swift.sh` installs swiftly (the notarized `swiftly.pkg`, `installer -target CurrentUserHomeDirectory`, `swiftly init --no-modify-profile --skip-install`) and, through it, the swift.org release of the same minor as Xcode's Swift — `swiftly install 6.4` resolves the newest patch, 6.4.1, which is also what CI's `setup-swift: "6.4"` resolves — into `~/Library/Developer/Toolchains`, removing any other swift.org release. It is **not on `PATH`**: `swift` and `xcrun swift` stay Apple's. A job that needs it puts swiftly's proxies (`~/.swiftly/bin`, which follow the toolchain swiftly has in use) first for that run. The Android suites, from a Hyper repo's checkout with `hyper-api36` booted (`ANDROID_NDK_HOME` comes from `~/.zshrc`):
>
> ```zsh
> PATH="$HOME/.swiftly/bin:$PATH" .github/scripts/android_build_suite.sh swift aarch64 /tmp/swift
> .github/scripts/android_device_test.sh /tmp/swift ./HyperUuidPackageTests.xctest
> .github/scripts/android_build_suite.sh go aarch64 /tmp/go
> .github/scripts/android_device_test.sh /tmp/go ./hyperuuid.test -test.v -test.short
> ```
>
> The Go flags are each repo's `ci.yml` `test-android` ones (`-test.short` is HyperUuid's: it skips the two 1 GiB batch tests an emulator has no memory for).
>
> The static-Linux and wasm SDKs need no host toolchain: the Forge runs them inside `swift:<version>` containers (see [Docker](#docker)).

---

## Ruby

rbenv + ruby-build by `git clone`, both Rubies (`RUBY_COMPAT_SERIES=(3.4)` + the newest stable), same per-series prune — `scripts/macos/update-ruby.sh`. Build deps come from [Base Dependencies](#base-dependencies); ruby-build finds Homebrew's `openssl@3` on its own. YJIT still needs `rustc` at configure time — rustup's, sourced explicitly, so the [Rust](#rust) module runs first.

```zsh
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
cat >> ~/.zshrc << 'EOF2'

# rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - --no-rehash zsh)"
EOF2
```

rbspy: the `aarch64-apple-darwin` release binary into `~/.local/bin` (`uname -m` says `arm64`; the asset name wants `aarch64`, the module maps it). Attaching to a running process needs sudo on macOS (SIP), `rbspy record -- ruby x.rb` does not.

**ruby.wasm (`rbwasm build`) needs pkg-config narrowed to `openssl@3`.** The Forge's `suite-ruby-wasm.sh` does it, and so must a bare `rbwasm build` (the Ruby READMEs say so for consumers). Nothing to install (the `ruby_wasm` gem, its wasi-sdk and its cross-built libyaml/zlib/OpenSSL are per-repo, under `ruby/wasm-smoke/build/`), but Homebrew's pkg-config leaks into it twice. rbwasm first builds a native baseruby, whose `ext/openssl` takes whatever `openssl.pc` pkg-config finds; Homebrew's `openssl` is now `openssl@4`, which Ruby 3.4 and 4.0 don't compile against (`incomplete definition of type 'ASN1_BIT_STRING'`). Then the wasm Ruby's `ext/psych` asks pkg-config for `yaml-0.1` before it honours rbwasm's `--with-libyaml-dir`, gets Homebrew's (a ruby-build dependency) and links its arm64 `libyaml.a` into a wasm module: wasi-sdk 22 (Ruby 3.4) shrugs it off, wasi-sdk 24 (Ruby 4.0) fails with `undefined symbol: yaml_emitter_emit`. Ubuntu runners don't hit the second one because pkg-config omits system `-L` dirs there. Run rbwasm with pkg-config seeing only `openssl@3`:

```zsh
PKG_CONFIG_LIBDIR="$(brew --prefix openssl@3)/lib/pkgconfig" bundle exec rbwasm build …
```

CI's ruby.wasm job, as the Forge runs it, from a Hyper repo's checkout (`<forge>` is a checkout of `SkunkWerkx/.github`; the script sets the pkg-config path itself on macOS):

```zsh
<forge>/.github/actions/ruby-wasm-suite/suite-ruby-wasm.sh hyperuuid 4.0 archive gem node browser
```

`PKG_CONFIG_PATH` is not enough: it is searched in front of the default path, not instead of it, so `yaml-0.1` is still found.

---

## PHP

Homebrew's `php`, not phpenv/php-build. The formula is the newest stable PHP, its configure line already carries `--with-ffi` (the one flag the Fedora module has to add by hand — HyperUuid's PHP binding dlopens the Rust cdylib through PHP's FFI extension), it ships `php-config` and the Zend headers `cargo-php`/`ext-php-rs` link against, and its `pecl` is wired to install outside the Cellar so an extension survives `brew upgrade php`. Homebrew keeps one php, so there is nothing to prune.

```zsh
brew install php composer    # php-build bundles Composer on Fedora; Homebrew's php doesn't — it's its own formula
pecl install xdebug          # same for Xdebug — pecl does it, into Homebrew's pecl dir outside the Cellar
cargo install cargo-php --locked --force
php -m | grep -iE 'ffi|xdebug'
```

`scripts/macos/update-php.sh` keys the pecl step on `php -r 'exit(extension_loaded("xdebug") ? 0 : 1);'` (pecl refuses to reinstall an installed extension, exit 1) and rebuilds `cargo-php` against whatever `brew upgrade php` just produced, as the Fedora module does after a phpenv rebuild. The check is in-process on purpose: the first draft used `php -m | grep -q`, and under `set -o pipefail` that is a race — `grep -q` exits on the first match, php then dies writing the rest of its module list into the closed pipe (exit 255, 5 runs out of 6 here), the pipeline reports failure, and the replay runs `pecl install xdebug` straight into its "already installed" exit 1. Any `cmd | grep -q` test in these scripts has the same exposure; `grep … >/dev/null` reads to EOF and doesn't.

---

## .NET · Older runtimes · .NET 11 preview

`dotnet-install.sh` resolves `osx-arm64` itself and lays out `$DOTNET_ROOT` (`~/.dotnet`) identically, so `scripts/macos/update-dotnet.sh` is the Fedora module with `~/.zshrc` as the rc file: LTS SDK, the 9.0/8.0 `aspnetcore` runtimes for multi-target test execution, the 11.0 preview channel for the Norse DU work, the exact-version prune across `sdk/`, `shared/*/`, `host/fxr/`, `packs/*/`, `templates/`, preview/rc manifest-band prune, `dotnet-trace`/`dotnet-counters`, tool/workload updates.

```zsh
cat >> ~/.zshrc << 'EOF2'

# .NET
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools
EOF2
```

Plus the **mobile workloads** — `dotnet workload install ios maccatalyst android`, for the Hyper repos' C# legs: the iOS-simulator app and the Mac Catalyst process in `ci.yml`'s Apple job, and the CoreCLR and Native AOT APKs in its Android job. They install into the newest SDK's band, the 11.0 preview (the module runs outside any repo's `global.json`), the same band `wasm-tools` is in; `dotnet workload update` moves them from then on. The android workload's build tasks need an Android SDK and a JDK at build time, not at install — see [Android](#android-ndk--sdk).

> **The ios / maccatalyst workloads need one exact Xcode.** Each build checks the selected Xcode's major.minor against the workload's `RecommendedXcodeVersion` (27.0 for 27.0.12212-net11-rc.2) and stops on anything else: `requires Xcode 27.0. The current version of Xcode is 27.1`. (The Mac Catalyst link failure on `_UIApplicationDidReceiveMemoryWarningNotification` is a separate workload problem that 27.0 does not fix; see the build-machine receipts below.) The fix is that Xcode installed *beside* the selected one and handed to the C# Apple builds only, through `DEVELOPER_DIR=/Applications/Xcode-27.0.app/Contents/Developer`. Installing Xcode needs an Apple ID, so `update-dotnet.sh` ends by reading `RecommendedXcodeVersion` from the newest `Microsoft.iOS.Sdk` pack, looking for a matching `/Applications/Xcode*.app`, and failing loudly with the download/`xip`/`-runFirstLaunch` steps when there is none.

The `-f <tfm>` rule for `dotnet test` on multi-targeted repos and the net472-under-Mono path are the same as on Linux — the .NET Framework CLR doesn't run on macOS either.

## Mono (legacy .NET Framework test execution)

```zsh
brew install mono
```

Homebrew's `mono` is 6.14.1 with an arm64 bottle — the same release the Fedora box runs — so the net472 receipt there (`dotnet build -f net472`, then `mono <exe>`) carries over unchanged. Installed by the `tools` module.

---

## Formatting / Profiling / Performance

Same matrix as the Fedora doc, with the macOS replacements in the rows where Linux tooling doesn't exist on Apple Silicon. **Bold** is installed by this pass.

| Toolchain | Formatting | Profiling | Performance |
|---|---|---|---|
| Node / TypeScript | — | `node --cpu-prof` (bundled) | — |
| Go | `gofmt` (bundled) | `go tool pprof` (bundled) | `go test -bench` (bundled) + **benchstat** |
| JVM | Spotless + palantir-java-format (Gradle plugin, per repo) | JFR (bundled) + **async-profiler** (macOS build) | JMH (per repo) |
| .NET | `dotnet format` (SDK) | **dotnet-trace**, **dotnet-counters** | BenchmarkDotNet (per repo) |
| Rust | **rustfmt** | **samply** | criterion (per repo) |
| Swift | `swift format` (CLT) + **SwiftLint** | **samply** / `sample` (bundled) / Instruments (`xctrace`, needs Xcode) | package-benchmark (per repo) |
| Ruby | rubocop (per repo) | **rbspy** (sudo to attach) | benchmark-ips (per repo) |
| PHP | phpcs (per repo) | Xdebug (**pecl**) | phpbench (per repo) — `XDEBUG_MODE=off` |
| Python | **ruff** | **py-spy** (sudo to attach) | **pyperf** |
| any process | — | `sample`, `leaks`, `heap`, `malloc_history`, `vmmap` (bundled in macOS), `xctrace` (Xcode) | **hyperfine** |

> **No `perf`, `valgrind` or `heaptrack` on this box, by fact not by choice:** `perf` is a Linux kernel tool; Homebrew's `valgrind` formula is `depends_on :linux` (no Apple Silicon support upstream); there is no `heaptrack` formula at all. The bundled macOS tools cover the same questions — `sample <pid>` for a call-stack sample, `leaks <pid>` / `leaks --atExit -- ./bin` for memcheck's job, `malloc_history` and `heap` for heaptrack's, `xctrace record --template 'Time Profiler'` for a full Instruments trace once Xcode is installed. `samply record ./bin` is the cross-language sampler that opens the Firefox Profiler UI, same as on Linux.

```zsh
brew install hyperfine
hyperfine --warmup 3 'cmd-a' 'cmd-b'
sample <pid> 5 -file out.txt
leaks --atExit -- ./bin
```

---

## GitHub CLI · actionlint · ShellCheck · pyflakes · PowerShell · LLVM

```zsh
brew install gh actionlint shellcheck
brew install pipx && pipx install pyflakes
brew install llvm lld
```

**LLVM / lld** are for the Hyper repos' release guard (`.github/scripts/release_guard.py` and its tests): it reads exports with `llvm-nm` / `llvm-readobj` and builds cross-format fixtures with `clang` and `lld-link`, where CI has `apt-get install llvm clang lld`. Homebrew's `llvm` is keg-only (`provided_by_macos`), so its `bin/` stays off `PATH` and the CLT's `clang` and libclang keep winning everywhere else — put it first only for that run:

```zsh
PATH="$(brew --prefix llvm)/bin:$PATH" python3 -I -m unittest discover -s .github/scripts/tests
```

`lld` is not keg-only: `ld.lld`, `lld-link`, `ld64.lld` and `wasm-ld` land in Homebrew's `bin`, none of which shadows the CLT's `ld`.

`gh`, `actionlint` and `shellcheck` track the same versions as the GitHub/dnf installs on Fedora. There is no `pyflakes` formula; pipx gives it its own venv on Homebrew's python and a `~/.local/bin/pyflakes` shim — outside the pyenv build `update-python.sh` replaces on every upgrade, which is the same reason Fedora takes it from dnf rather than pip, so actionlint's `python`-step integration stays live across Python upgrades.

PowerShell: the `osx-arm64` release tarball under `~/.local/opt/microsoft/powershell/7`, `pwsh` symlinked into `~/.local/bin` — the same shape as Fedora's `/opt` install without the sudo:

```zsh
PS_VERSION=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')
ARCH=$(uname -m | sed 's/x86_64/x64/')
curl -fsSLO https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/powershell-${PS_VERSION}-osx-${ARCH}.tar.gz
mkdir -p ~/.local/opt/microsoft/powershell/7
tar -xzf powershell-${PS_VERSION}-osx-${ARCH}.tar.gz -C ~/.local/opt/microsoft/powershell/7
chmod +x ~/.local/opt/microsoft/powershell/7/pwsh
ln -sf ~/.local/opt/microsoft/powershell/7/pwsh ~/.local/bin/pwsh
rm powershell-${PS_VERSION}-osx-${ARCH}.tar.gz
```

---

## Claude Code

Already on the box (native installer, `~/.local/bin/claude`, auto-updates on `latest`) — nothing for the pass to do, same as on Fedora.

## Playwright (Claude Code browser automation)

Same `@playwright/mcp` server, wired in exactly as on Fedora — the `playwright` plugin from `claude-plugins-official`, whose `.mcp.json` launches `npx @playwright/mcp@latest` with no arguments:

```zsh
claude plugin install playwright@claude-plugins-official    # replay-safe: exit 0, "already installed"
```

The browser is different. Homebrew's `chromium` cask is **disabled** (`fails_gatekeeper_check` — the snapshot builds are unsigned), and the Fedora doc's reasons for a system browser (one copy, under its own update cadence, no second ~300 MB Playwright-managed download) land on the one the server looks for by default on macOS, `/Applications/Google Chrome.app`:

```zsh
brew install --cask google-chrome      # notarized Developer ID (Google LLC), auto_updates: true
```

Chrome's own updater only runs while Chrome is open, which on a build box it rarely is: it sat at 155 after 156 shipped, and `wasm-pack test --chrome` — which always fetches the newest chromedriver — then failed with `This version of ChromeDriver only supports Chrome version 156`. `brew upgrade` skips `auto_updates` casks unless told `--greedy`, so `scripts/macos/update-tools.sh` runs `brew upgrade --cask --greedy google-chrome` after the install-if-missing. The module also writes `~/.local/bin/google-chrome`, an exec wrapper around the app's binary: the Forge's browser checks call `google-chrome` by that name (the Ubuntu runner images ship one; the cask puts nothing on `PATH`), and a symlink does not do, because Chrome finds its framework from the path it was started by and a headless launch through a symlink prints nothing. Not Brave: Brave works with `--executable-path` (verified — it loaded a page through the server), but it is the personal browser on this box, and automation gets its own. The server launches Chrome with an isolated profile either way.

> **Chrome must be opened once from the GUI before anything can launch it from the command line.** Found the hard way: straight after the cask install, every launch — `Google Chrome --headless=new --dump-dom`, through the Playwright server, with an explicit `--user-data-dir`, a minimal environment, sandboxed or not — died with `FATAL:base/path_service.cc:264 Failed to get the path for 1001` (`DIR_USER_DATA`), exit 133, `SIGTRAP`; through Playwright that surfaces as `Target page, context or browser has been closed` at `initializeServer`. Gatekeeper assessed the bundle as accepted and notarized, and the quarantine attribute was *not* the difference (it is unchanged after the fix). One `open -a "Google Chrome"`, through its first-run screens, created `~/Library/Application Support/Google/Chrome` and its `First Run` sentinel, and from then on headless and Playwright launches work. Brave (also Chromium 155) had been opened long before and never showed it. The module tests for the sentinel and hard-fails with the instruction when it is missing — the fix is a manual GUI step, like Xcode's.

Verify:

```zsh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
claude plugin list                     # playwright@claude-plugins-official — Status: ✔ enabled
claude mcp list                        # plugin:playwright:playwright: npx @playwright/mcp@latest - ✔ Connected (from a shell with fnm's node on PATH)
```

> **Receipt:** driving `npx @playwright/mcp@latest --headless` over stdio with no browser flag (initialize → `browser_navigate` → `browser_close`) returned `Page URL: https://example.com/`, `Page Title: Example Domain`, `isError: false`. `~/Library/Caches/ms-playwright` is 8 KB: no Playwright-managed browser was downloaded. The same run before Chrome was installed failed with `Chromium distribution 'chrome' is not found at /Applications/Google Chrome.app/Contents/MacOS/Google Chrome` — the server does not look for Brave or anything else on its own.

---

## Docker

Docker Desktop for Mac — installed, CLI on `~/.docker/bin` (its installer wired `~/.zprofile`), updates itself. `scripts/macos/update-docker.sh` just runs the Fedora `scripts/update-docker.sh`, which only talks to the docker CLI and is OS-neutral; the clean-slate container policy documented there applies here unchanged.

Docker is also where the binding floors run locally: the Forge's musl and Swift-static suites are `docker run` scripts (see [Python](#python)), and the images they pull are the ones this module refreshes afterwards.

> Docker Desktop has to be **running** for the module: with it closed, `docker images` fails on the socket (`failed to connect to the docker API at unix:///Users/buvy/.docker/run/docker.sock`) and the module stops there with exit 1 — which is what it should do, there is no daemon to talk to. Start Docker Desktop and rerun `./update-toolchain.sh docker`.

---

## Tailscale

Standalone Tailscale.app (`io.tailscale.ipn.macsys`, not the App Store build) — installed, updates itself. The CLI is the app bundle's own binary, `/Applications/Tailscale.app/Contents/MacOS/Tailscale`, and nothing puts it on `PATH`; `~/.local/bin/tailscale` is a two-line wrapper that `exec`s it by that path:

```zsh
cat ~/.local/bin/tailscale
#!/bin/sh
exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
```

> **A symlink does not work here**, unlike `pwsh`/`asprof`. The binary resolves its app bundle from the executable path, and launched through `~/.local/bin/tailscale -> …/MacOS/Tailscale` it aborted with `Tailscale/BundleIdentifiers.swift:49: Fatal error: The current bundleIdentifier is unknown to the registry` (1.104.1). A wrapper that `exec`s the real path keeps the bundle lookup intact; an alias would too, but only in interactive zsh.

Verify:

```zsh
which tailscale        # /Users/buvy/.local/bin/tailscale
tailscale version      # 1.104.1
tailscale status       # the tailnet's peers, from the running app
```

---

## Code Directory

`~/Developer/` — the macOS convention (Finder gives it the hammer icon), already in use: this repo is `~/Developer/buvinghausen/buvinghausen`. Same layout underneath as the Fedora `~/code/`:

```
~/Developer/
  ├── buvinghausen/
  ├── NorseArchitecture/
  └── SkunkWerkx/
```

## posh-git-sh

Same script (it supports zsh), scoped to `~/Developer/**` instead of `~/code/**`, wired through zsh's `precmd` hook rather than bash's `PROMPT_COMMAND` (the README's documented zsh form). `scripts/macos/update-tools.sh` splices this above SDKMAN's end-of-file block, like the Fedora module does for `~/.bashrc`:

```zsh
curl -o ~/.posh-git-sh https://raw.githubusercontent.com/lyze/posh-git-sh/master/git-prompt.sh
```

```zsh
# posh-git-sh — only active inside ~/Developer/**
source ~/.posh-git-sh

precmd() {
    case "$PWD" in
        $HOME/Developer/*)
            __posh_git_ps1 '%n@%m:%~ ' '$ '
            ;;
        *)
            PS1='%n@%m:%~$ '
            ;;
    esac
}
```

---

## Verified Environment

```
bash      5.3.20         Homebrew — runs the scripts (/bin/bash is 3.2)
fnm       1.39.0         Homebrew
Node.js   v24.22.0       (Krypton LTS)
npm       12.2.0
tsc       7.0.2          (Go-native compiler)
go        1.27.2         darwin/arm64, ~/.local/go
gopls     0.24.0
dlv       1.27.2
benchstat v0.0.0-20261009192801-be2c69fb417e
tinygo    0.43.0         ~/.local/tinygo (darwin-arm64 tarball) + binaryen 133 (Homebrew, wasm-opt)
java      25.0.4.1+1     Temurin LTS (SDKMAN, darwinarm64)
graalvm   25.4.4.1+1     GraalVM CE, SDKMAN-managed alongside Temurin — never `current`
async-profiler 4.5      ~/.local/opt/async-profiler (macOS universal zip), asprof + jfrconv in ~/.local/bin
kotlin    2.4.21
gradle    9.8.1
python    3.15.1         GIL enabled (standard build; 3.15.1t alongside for free-threaded testing)
python    3.14.9         Pyodide's series (PYTHON_PYODIDE_SERIES) — pyodide-build 0.39.1, pyodide-cli 0.5.0
ruff      0.17.1
mypy      2.4.0
pyperf    2.10.0
py-spy    0.4.2          sudo to attach on macOS
openpyxl  3.1.5          HyperTabular's fixture writer (corpus/workbook/make_fixtures.py: same parts as the committed files bar docProps/core.xml's timestamps)
rustc     1.99.1         aarch64-apple-darwin; + x86_64-apple-darwin, aarch64-apple-ios{,-sim,-macabi}, x86_64-apple-ios-macabi,
                         {x86_64,aarch64}-unknown-linux-{gnu,musl}, {x86_64,aarch64}-pc-windows-msvc (static libs only), llvm-tools
rustc     1.85.1 / 1.88.0  MSRV toolchains (RUST_MSRV_SERIES), --profile minimal
cargo     1.99.1
nextest   0.9.148        prebuilt universal-apple-darwin binary
samply    0.13.1
cargo-semver-checks 0.51.0
wasm-pack 0.15.0
emcc      6.0.12         ~/emsdk (EMSDK_PYTHON = Homebrew python@3.15)
wasmtime  49.0.3
android-ndk r30          30.0.16248370, clang 21.0.0 — ~/.local/opt/android-ndk symlink, prebuilt darwin-x86_64 (universal)
cargo-ndk 4.1.2
android-sdk              ~/.local/opt/android-sdk — cmdline-tools 23.0 (sdkmanager 1.0.16625370), platform-tools 37.0.1 (adb 1.0.41), emulator 37.2.12.0,
                         platforms;android-37.0 + build-tools;37.0.0 (the workload's defaults), system-images;android-36;google_apis_ps16k;arm64-v8a, AVD hyper-api36
xcode     27.1           Build 27A9275, /Applications/Xcode.app selected, license accepted, first launch done; iOS SDK 27.1
swift     6.4            Apple (swiftlang-6.4.0.34.1) from Xcode — the CLT 27.0 ships the same build; on PATH
swiftly   1.2.0          ~/.swiftly (not on PATH) — swift.org 6.4.1 in ~/Library/Developer/Toolchains, for Swift SDKs (Android)
swiftlint 0.65.1         Homebrew (TOOLCHAIN_DIR only needed while CLT-only, see Swift)
ruby      4.0.7          arm64-darwin27, rbenv/ruby-build, global — primary Magnus ABI + Fiddle suite host
ruby      3.4.11         compat Magnus ABI, RBENV_VERSION-selected
rbspy     0.53.0         ~/.local/bin, aarch64-apple-darwin release binary; sudo to attach
php       8.5.11         Homebrew, --with-ffi, Xdebug 3.5.3 via pecl
composer  2.10.3         Homebrew
cargo-php 0.2.1
dotnet    10.0.402       (+ 9.0.21, 8.0.32 runtimes for multi-target test execution)
dotnet-11 11.0.100-rc.2.26504.105   TEMPORARY preview channel (Norse DU work)
dotnet-trace    10.0.750501
dotnet-counters 10.0.750501
wasm-tools workload      11.0.100-rc.2 band; bundled wasm-opt replaced by emsdk's
ios / maccatalyst        27.0.12212-net11-rc.2, 11.0.100-rc.2 band
android workload         37.2.0-rc.2.84, 11.0.100-rc.2 band
mono      6.14.1         Homebrew (arm64 bottle) — legacy net472/net462 test execution
gh        2.102.0        Homebrew
actionlint 1.7.12       Homebrew
shellcheck 0.11.0       Homebrew
pyflakes  4.0.3          pipx (Homebrew python@3.15)
pwsh      7.6.7          ~/.local/opt/microsoft/powershell/7 (osx-arm64 tarball)
hyperfine 2.0.0          Homebrew
llvm / lld 23.1.4        Homebrew — llvm keg-only (off PATH), lld on PATH; release-guard checks
sample/leaks/heap/malloc_history/vmmap   bundled with macOS 27.0.1
google-chrome 156.0.8078.48  Homebrew cask, `--greedy` upgrade each pass; Playwright's default browser (opened once by hand, see Playwright);
                             `google-chrome` on PATH via an exec wrapper in ~/.local/bin
playwright plugin ea10b213686c  claude-plugins-official, user scope — npx @playwright/mcp@latest, server 0.0.83
docker    29.8.2         CLI from Docker Desktop (~/.docker/bin)
tailscale 1.104.1        standalone Tailscale.app (io.tailscale.ipn.macsys), exec wrapper in ~/.local/bin — a symlink aborts
claude    2.1.302        native, auto-updates enabled
posh-git-sh              ~/Developer/** only, zsh precmd
```

*Verified on: 2026-10-16 · Mac mini (Apple M6) · macOS 27.0.1 · first full pass via `./update-toolchain.sh`, module by module, from a box that had only Homebrew, the Command Line Tools, Docker Desktop and Claude Code on it. The receipts, each run from this box against the real repo rather than `--version` alone:*

- *`rust`: HyperUuid `cargo nextest run` — 83 passed, 1 skipped. `cargo cdylib` produced the 50,960-byte `libhyperuuid.dylib` every binding below loads.*
- *`go`: HyperUuid `go test ./...` ok (1.6 s); `tinygo build -target wasm` over `go/internal/tinygosmoke` — 1.33 MB module, after `binaryen` went into the module (first attempt failed `could not find wasm-opt`, see [Go](#go)).*
- *`jvm`: `asprof -d 3 -e cpu -o collapsed` attached to a running Temurin JVM with no sudo and no JVM flags — 306 samples, `Busy.hot` on the stack, `-f flame.html` written. `native-image -o hello Hello` under `25.4.4.1+1-graalce`: a 4.68 MiB Mach-O arm64 executable in 8.9 s, links `libSystem`/`Foundation`/`libz`/`CoreFoundation`/`libobjc`, prints `os.arch=aarch64`.*
- *`dotnet`: HyperUuid `dotnet test -f net10.0` — 99/99 once `libhyperuuid.dylib` was staged at `csharp/HyperUuid/runtimes/osx-arm64/native/` (87 `DllNotFoundException`s without it: the csproj flattens whatever is under `runtimes/` into the output, same as every CI leg stages its own). SequentialGuid `dotnet test -f net10.0` on `SequentialGuid.Tests`: 6309 total, one failure on the first run that did not reproduce on the immediate rerun (6309/6309) — name not captured, so unexplained rather than explained away. The 11.0 rc.2 SDK ran a `global.json`-pinned hello world and `dotnet workload list` cleanly after the manifest-band prune had removed the `11.0.100-preview.6` folder the rc.2 tarball also carries (its own band is `11.0.100-rc.2`).*
- *Mono: SequentialGuid `dotnet build -f net472` + `mono SequentialGuid.Tests.exe` — 6207 passed, 0 failed, the same number the Fedora box reports.*
- *`wasm`: `cargo wasm-module` → `hyperuuid.wasm` (41,773 bytes, wasm32-wasip1), `wasmtime run --invoke hyperuuid_version` executed it; `cargo wasm-staticlib` → the 3.68 MB `libhyperuuid.a` for `wasm32-unknown-emscripten` linked through emsdk's `emcc`. The `wasm-opt` patch replaced the binary in `Microsoft.NET.Runtime.Emscripten.6.0.2.Sdk.osx-arm64`. Not run: `wasm-pack test --headless --chrome` over `browser-test` (needs Chrome/chromedriver; Brave is wired for Playwright only).*
- *`android`: `cargo ndk -t arm64-v8a cdylib` / `-t x86_64 cdylib` — 20,728- and 24,728-byte `libhyperuuid.so`, `NEEDED` only `libc.so`, 19 exported `T` symbols (checked with the NDK's `llvm-readelf`/`llvm-nm`); `cargo clippy --target aarch64-linux-android -- -D warnings` clean. First time Android has worked on an arm64 box in this pass.*
- *`swift`: `swift build` of HyperUuid's package (XCFramework declared) — 13 s; `swift format lint --strict --recursive Sources` exit 0; `swiftlint lint --strict Sources` 0 violations in 6 files with `TOOLCHAIN_DIR` set (exit 133 crash without it). `swift test` needs Xcode (no XCTest in the CLT) — see [Swift](#swift). **After Xcode 27.1 was installed and selected:** `./update-toolchain.sh swift` took the Xcode path (prints `Xcode 27.1 / Build version 27A9275`, no `TOOLCHAIN_DIR` export, the `~/.zshrc` guard line evaluates to nothing in a login shell); `swift test` — 73 tests, 0 failures in 4.5 s (XCTest; the swift-testing run alongside is empty by design); `swiftlint lint --strict Sources` with `TOOLCHAIN_DIR` unset — 0 violations in 6 files, no crash; `xctrace record --template 'Time Profiler' --time-limit 2s --launch -- /usr/bin/yes` wrote a `.trace` with a captured run (exit 54 is the launched target being SIGKILLed at the limit, the trace is still complete) and `xctrace export --toc` reads it back.*
- *`ruby`: `bundle exec rake native:dev` + `bundle exec rspec` under 4.0.7 and under 3.4.11 — 388 examples, 0 failures each, `HyperUuid::BACKEND` `:native` under both (the Magnus extension stages as `hyperuuid_native.bundle` on Darwin); `HYPERUUID_PURE=1 bundle exec rspec` — 388 examples, 0 failures, 13 pending, `BACKEND` `:fiddle`.*
- *`php`: `composer install` + `vendor/bin/phpunit` — 114 tests, 27,596 assertions, 2 skipped, OK, through Homebrew php's FFI; `vendor/bin/phpcs` clean. Composer was the one thing missing after the first run (php-build bundles it, Homebrew's php doesn't) — added to the module.*
- *`python`: in a venv, `maturin develop --release` + `pytest` — 425 passed in 5.2 s (an `abi3` `_native` built in place under `src/hyperuuid/`; a plain `pip install ./python[test]` is the wrong shape here — the tests import from `src/`, which then has no `_native`). `ruff check` / `ruff format --check` clean.*
- *`tools`: `actionlint` over HyperUuid's four workflows ran with both integrations live — shellcheck and pyflakes findings surfaced through it, and a deliberately broken workflow produced SC2086 plus pyflakes' unused-import and undefined-name — its own exit was 1 because 1.7.12's runner-label list predates `ubuntu-26.04`, a stale-tool finding, not a toolchain one. `hyperfine` measured a 2x workload at 2.0x; `leaks --atExit` found the deliberate `malloc` leak in `main`; `sample` wrote a call graph for a live process; `pwsh` 7.6.7 ran. Playwright MCP: the plugin installed, `claude mcp list` shows it `✔ Connected`, and `example.com` loaded through the server with its default browser, Google Chrome (see [Playwright](#playwright-claude-code-browser-automation) for the one-time GUI launch Chrome needed first).*
- *`docker`: with Docker Desktop closed the module stops on the socket error (the loud failure it should give). With it running, on a box with **zero images**, it aborted at `Pulling latest for each` with exit 1: `docker images … | grep -v '<none>' | sort -u | while …` — grep exits 1 on empty input and `pipefail` turns the empty pull list into a failed pipeline. Fixed in the Fedora `scripts/update-docker.sh` (the one OS-neutral edit made to it: `|| true` on the grep, inside a group so `sort -u` still sees the empty list); rerun exits 0 and prints the empty before/after image tables. It can't be rerun on Fedora from here; the change is a no-op whenever at least one image exists.*
- *Replay (`./update-toolchain.sh base node go jvm dotnet rust wasm android swift ruby php python tools`, docker left out for the daemon reason above): every module took its no-op path — Homebrew `already installed and up-to-date` for all 23 formulae, `Go already at go1.27.2`, `TinyGo already at 0.43.0`, SDKMAN `All candidates are up-to-date`, `async-profiler already at 4.5`, every dotnet-install.sh SDK/runtime `already installed`, rustup `unchanged`, every `cargo install` `Ignored package … already installed` (cargo-php and cargo-ndk are `--force` rebuilds by design), emsdk `All SDK components already installed`, `NDK already at r30`, `rbspy already at 0.53.0`, `xdebug already loaded`, pip `Requirement already satisfied` for all seven tools, `pyflakes is already at latest version 4.0.3`, `pwsh already at 7.6.7`; clean overwrites where the upstream installer always downloads (wasmtime's install.sh, posh-git-sh). The first replay attempt stopped in `php` with exit 1 — the `php -m | grep -q` pipefail race described under [PHP](#php) — and completed after the in-process check replaced it; `php python tools` reran clean on the fix.*


*Added 2026-10-21, curating the gaps a HyperUuid-wide survey found (what CI and the Forge run against what this box had). Each module rerun from `./update-toolchain.sh <module>`:*

- *`base`: before Rosetta was installed it stopped at `==> Rosetta 2` with the one sudo command and exit 1; after `sudo softwareupdate --install-rosetta --agree-to-license` it prints `x86_64 binaries run` and passes. The Forge's osx-x64 test step, `cargo test --release --target x86_64-apple-darwin` in HyperUuid's `rust/`, then ran its x86_64 Mach-O test binaries under Rosetta: 65 passed, 0 failed, 1 ignored.*
- *`docker`, and the floors through it: with Docker Desktop running, the module exits 0. The Forge's own scripts, run from its checkout against HyperUuid: `musl-native/build-musl.sh` built `libhyperuuid.so` in Alpine (the crate's suite passing there), then `musl-suite/suite-musl.sh … linux-musl-arm64` with `SUITE_IMAGE` set to each floor — PHP on `php:8.2-cli-alpine` 96 tests, 43,550 assertions, 1 skipped; Ruby on `ruby:3.3-alpine` 309 examples, 0 failures, 14 pending; Python on `python:3.11-alpine` 319 passed, 3 skipped. Not run: the Swift 6.2 floor (`swift-static-suite`, which needs the static-libs artifacts and the static-Linux/wasm Swift SDKs).*
- *`rust`: the five Apple targets and `1.85-` / `1.88-aarch64-apple-darwin` installed; HyperUuid's `check-msrv` commands (`cargo +1.85 check --lib`, then `--lib --no-default-features --features cdylib`) pass; `cargo build --release --lib --target <t>` produced `libhyperuuid.rlib` for each of the five Apple targets. Negative control for the prune: a hand-installed `1.80` was uninstalled by the next replay (`not a declared rust-version`), 1.85/1.88 and stable kept.*
- *`dotnet`: `Successfully updated workload(s): wasm-tools ios maccatalyst android.` The `wasm` module's `wasm-opt` patch in `Microsoft.NET.Runtime.Emscripten.6.0.2.Sdk.osx-arm64` was still in place afterwards.*
- *`android`: SDK bootstrapped and replayed clean (`hyper-api36 already exists`). Prune control: a hand-installed `platforms;android-36` was removed by the next replay, `android-37.0` and `build-tools;37.0.0` kept. End to end, CI's `test-android` steps for one APK: `cargo ndk -t arm64-v8a cdylib -- -C link-arg=-Wl,-z,max-page-size=16384` (18,792-byte `.so`), staged into `runtimes/android-arm64/native/`, `dotnet pack`, `dotnet publish` of `HyperUuid.AndroidSmokeTest` `-r android-arm64 -p:PublishAot=false` on JDK 25 — the signed APK carries `lib/arm64-v8a/libhyperuuid.so`; `hyper-api36` booted headless (`-no-window -gpu swiftshader_indirect`; `API 36, page size 16384`) and HyperUuid's own `.github/scripts/android_smoke.sh` passed it: `native: available=True version=0.9.0`, `ALL NATIVE AOT CHECKS PASSED`, `exit code 0`. Not run: the Native AOT APK (needs the `android-arm64` static archive), and the Go and Swift suites on the device.*
- *`python`: 3.14.9 built beside the global (the same pass moved the global 3.15.0 → 3.15.1). With the Forge's pin, `pyodide xbuildenv install 314.0.7` under 3.14.9 installed the cross-build environment (`pyodide config get python_version` → 3.14.2). Negative control: the same command under 3.15.1 fails with `Version 314.0.7 is not compatible with the current environment` — the reason the series exists. The control's pyodide-build install into the global and the xbuildenv cache were removed afterwards.*
- *`tools`: HyperUuid's release-guard tests, `python3 -I -m unittest discover -s .github/scripts/tests` — 13 errors with LLVM off `PATH`, 4 with `$(brew --prefix llvm)/bin` first. The 4 are the tests' Linux-host assumptions rather than missing tools: they shell out to bare `ar` (Apple's here) and `cc -shared` (a Mach-O dylib named `.so`, which `llvm-nm --dynamic` rejects with `File format has no dynamic symbol table`). On ubuntu runners they pass.*

*Added 2026-10-21, this box as HyperUuid's primary build machine: every CI and Forge job that can run on macOS, replayed against a `git clone --local` of HyperUuid `master` (the working tree itself untouched), with CI's own flags and pins:*

- *Static libraries: the Forge's `build-static-libs.sh` with `APPLE_MOBILE=1 ANDROID=1` — every Linux glibc/musl, Windows MSVC, Apple, Android and wasm archive, the Swift artifact bundle (0.9.0, 11 variants) and the three-slice xcframework.*
- *Swift static suites (the Forge's `suite-swift-static.sh`): Swift 6.4 — `smoke-glibc smoke-musl test-wasm smoke-wasm browser-wasm`, 61 tests; the Swift 6.2 floor — `test smoke-glibc smoke-musl smoke-wasm`, 61 tests.*
- *Android, the whole `test-android` job: all four APKs (CoreCLR and Native AOT, `android-arm64` and `android-x64`), CI's inspection on each (the `.so` where CoreCLR carries it, the core linked into the AOT binary, `zipalign -P 16`); on `hyper-api36` both arm64 APKs (`ALL NATIVE AOT CHECKS PASSED`), the Go suite (`PASS`) and the Swift suite (61 tests, 0 failures, 2 skipped) on the swift.org 6.4.1 Android SDK. Not run: the two x64 APKs, which an arm64 emulator can't execute. Rerun with nothing outside the repos and this doc, after `android_build_suite.sh` stopped hardcoding the NDK's `prebuilt/linux-x86_64` (it now takes the NDK's one host directory, `darwin-x86_64` here, and the unedited script fails with `linux-x86_64/bin/aarch64-linux-android21-clang ... not found`): both suites staged from the real NDK by the commands under [Swift](#swift) and run on `hyper-api36` by `android_device_test.sh` — Go `PASS` (74 passed, 1 skipped, `-test.short` as CI runs it; without it the first 1 GiB batch test took the emulator offline), Swift 61 tests, 0 failures, 2 skipped.*
- *Apple job: Swift `swift test` on the iOS simulator and as Mac Catalyst, 61 tests each; the iOS device build (`BUILD SUCCEEDED`); Go `go test` in the iOS simulator (`ok`); the Go iOS device link carries `_uuid_new_v7`. **Failing:** the C# Mac Catalyst app. With Xcode 27.0 installed as `/Applications/Xcode-27.0.app` (27A266a) and passed through `DEVELOPER_DIR`, the version check passes and the `dotnet` module's Xcode check goes green, but the link still fails on `_UIApplicationDidReceiveMemoryWarningNotification`: the workload (27.0.12212-net11-rc.2) links only `Foundation GSS Security`, leaving out the UIKit its own `libxamarin-dotnet-coreclr.a` references. Not HyperUuid's doing: `dotnet new maccatalyst` builds, and the same template with its sources replaced by a UIKit-free `Program.cs` fails identically. CI has never run this leg on net11: its last `test-apple-mobile` (run 39468483559, `1345e03`) built net10 on Xcode 26.6, and `278705c` moved it to net11 after. The other two C# legs, run as `ci.yml`'s own step scripts on Xcode 27.0 from a fresh clone with only the Forge-built `staticlibs/` staged: the iOS simulator app passes (`native: available=True version=0.9.0`, `ALL NATIVE AOT CHECKS PASSED`, on CI's newest-runtime iPhone, iOS 27.1); the iOS device link fails on the same `_UIApplicationDidReceiveMemoryWarningNotification`, and so does a `dotnet new ios` app with a UIKit-free `Program.cs` while the stock template links — one workload bug for device and Catalyst. (A first simulator attempt from the long-lived clone failed on a macOS `libhyperuuid.dylib` left in `csharp/HyperUuid/bin` by the native suites — a contaminated checkout, not a finding.)*
- *Lint, all 20 of CI's checks: `cargo fmt`, the five clippy configurations, `cargo +1.85 check`, `cargo semver-checks`, revive at CI's `v1.16.0` (`go run …@v1.16.0`), `check_go_archives.sh`, gofmt, ruff at CI's `0.16.5` (`pipx run ruff==0.16.5`), phpcs, `rake docs:check` + rubocop, swiftlint, `swift format lint --strict`, `dotnet format whitespace`, spotless, `check_exports.py` and the corpus oracle, all pass. Negative control, in a second clone with one violation per checker: all 20 fail. The swiftlint config enables only `missing_docs`, so an undocumented `public func` is what fails it; `as!` passes.*
- *Release-guard tests, `python3 -I -m unittest discover -s .github/scripts/tests` in `python:3.14-slim` with `git llvm clang lld binutils`: 21 tests, OK; the four macOS-host errors in the `tools` receipt above are the control. A first container run without `git` errored 14 of them on `FileNotFoundError: 'git'`; the runners have it.*
- *Native macOS suites: `cargo test --release`; `cargo cdylib` + the smoke (all 13 exports called); C# `dotnet test` (0 failed); Java `gradlew test javadoc` and `testWasm` (GraalWasm); `go test`; Swift `swift test` under both build systems (61); PHP phpunit (96 tests, 43,549 assertions, 2 skipped); Ruby Magnus under 4.0 and 3.4 (309 examples, 0 failures each) and Fiddle (309, 0 failures, 14 pending); Python `maturin develop` + pytest (321 passed, 1 skipped). The osx-x64 leg under Rosetta is the `base` receipt above.*
- *Wasm: the emscripten staticlib; the Blazor app in headless Chrome (`ALL WASM CHECKS PASSED`); `wasm-pack test --headless --chrome` over `browser-test`, 6 passed — after the `--greedy` Chrome upgrade (before it, chromedriver 156 refused Chrome 155); the TinyGo module in the browser (`DONE`) on TinyGo 0.43.0, the newest 0.x, which is what CI installs (it pinned 0.42.0 until this pass).*
- *Pyodide: the Forge's `suite-pyodide.mjs` under Node and `browser-pyodide.mjs` in Chrome, on Pyodide 314.0.7 from Python 3.14.9: 315 passed, 7 skipped, each.*
- *ruby.wasm, 3.4 and 4.0, through the Forge's `suite-ruby-wasm.sh … archive gem node browser` from a fresh HyperUuid clone in a login shell with no `PKG_CONFIG_*` set: both exit 0, `DONE` under Node and in Chrome, with no Homebrew path in either psych `mkmf.log`. Negative control, 4.0 from a cold build dir with the script's Darwin block removed: baseruby's `ext/openssl` fails against `openssl@4` (`ASN1_STRING_FLAG_BITS_LEFT`); the unmodified script then passes from the same cold state. Before the script, with only `PKG_CONFIG_PATH` set to `openssl@3`, 3.4 passed but 4.0 failed linking Homebrew's arm64 `libyaml.a`. The Ruby README's consumer command (`PKG_CONFIG_LIBDIR=… bundle exec rbwasm build` over the published `hyperuuid-wasm` 0.9.0, 4.0) builds a 54,634,500-byte `ruby.wasm`.*
- *Swift on Android needs swift.org's compiler: Xcode's Apple Swift 6.4 rejects the swift.org Android SDK's modules (`compiled module was created by a different version of the compiler`), so the suite runs with swiftly's proxies first on `PATH` (`Apple Swift version 6.4.1 (swift-6.4.1-RELEASE)`; the command is under [Swift](#swift)). The first try at that run also stopped on `matched multiple SDKs` (6.4.0 and 6.4.1 Android SDKs both installed); the `swift` module now removes Swift SDKs that aren't for the kept release, and its rerun removed `swift-6.4.0-RELEASE_android`.*
- *Found in HyperUuid, not fixed here: the release-guard tests assume a Linux host's `ar` and `cc -shared`. (`android_build_suite.sh`'s hardcoded NDK host, found in the same pass, is fixed in all three repos; HyperUuid's header also gave the local Go command without CI's `-test.short`.)*
- *Not runnable here: the Windows legs.*

---

## Full Update Pass

```zsh
./update-toolchain.sh              # every module, in order
./update-toolchain.sh dotnet go    # or just the modules you want
```

Same orchestrator as Fedora — on Darwin it runs `scripts/macos/update-<module>.sh` for each of `base node go jvm dotnet rust wasm android swift ruby php python tools docker`. Every module is a no-op or clean overwrite when current; `go`, `jvm`, `dotnet`, `ruby`, `python` and `docker` remove what they supersede. `base`, `node`, `go`, `jvm`, `dotnet`, `rust`, `ruby`, `python` bootstrap their own prerequisite when missing, so a fresh Mac with Homebrew and the CLT runs the pass end to end; `wasm`, `android`, `ruby` and `php` hard-fail with a pointer if `rust`/`dotnet` haven't run first (they're earlier in the order); `android` also hard-fails without the `jvm` module's JDK or the `dotnet` module's android workload pack (it reads the SDK platform and build-tools from it); `dotnet` hard-fails at its end until the Xcode the ios/maccatalyst workloads were built for is installed beside the selected one, `base` until Rosetta 2 is installed, `swift` for an installed-but-unselected Xcode, and `tools` for a Google Chrome that has never been opened from the GUI — all one-time manual steps, each printed by the module. Nothing in the pass asks for a password.

The command-by-command reference for each stack is its section above where macOS differs, and the same-named section of [TOOLCHAIN.md](TOOLCHAIN.md) where it doesn't; `scripts/macos/update-*.sh` is the reference for the exact, current invocation. If they drift, the scripts win.
