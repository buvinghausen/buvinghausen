# Base image is plain Debian (base:debian), matching Bifrost -- everything else
# needed comes from features in devcontainer.json, except mono-complete: that's
# baked in here as a RUN layer instead of postCreateCommand so Docker caches the
# install (it's a large package) instead of re-downloading it on every "Rebuild
# Container".
#
# mono-complete hosts net472/net462 test exes directly -- dotnet test cannot
# launch those TFMs on Linux at all (confirmed in TOOLCHAIN.md's Mono section).
# The pattern is: dotnet build -f net472/net462, then run the built exe under
# mono directly, bypassing dotnet test's orchestrator entirely.
FROM mcr.microsoft.com/devcontainers/base:debian

RUN apt-get -o Acquire::Retries=3 update -qq \
    && apt-get -o Acquire::Retries=3 install -y -qq --no-install-recommends mono-complete \
    && rm -rf /var/lib/apt/lists/*
