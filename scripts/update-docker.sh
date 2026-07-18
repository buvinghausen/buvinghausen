#!/usr/bin/env bash
# Refreshes every locally-pulled Docker image, then blows away any container
# still pinned to a now-superseded image and prunes the freed-up dangling
# image behind it. Deliberate clean-slate policy, not an oversight: this does
# NOT try to reconstruct the removed container's `docker run` config (bind
# mounts, networks, replication topology, etc. — easy to get subtly wrong).
# Anything worth having survive this either lives in a named volume (`docker
# rm` here never takes -v, so named AND anonymous volumes are always left
# alone) or is owned by an orchestrator that already knows how to recreate
# its own containers (.NET Aspire's persistent containers, a docker-compose
# project) — e.g. the Norse Architecture postgres primary/replica pair comes
# back on the next Aspire AppHost run, rebuilt against the fresh image, data
# intact via the norse-pg-primary/norse-pg-replica volumes. If you're running
# this against someone else's box, make sure they're fine with that trade —
# this is tuned for solo personal-machine use, not a shared/team default.
#
# Docker Desktop's own engine update happens on the Windows side (see
# TOOLCHAIN.md's Docker section) — there's no WSL-side update command for
# Docker itself. Every step here is replay-safe: an image already at the
# latest digest is a fast no-op pull, and removing a container that's
# already gone or pruning an image that's already gone are both no-ops too.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

require_cmd docker "docker not found — enable Docker Desktop's WSL integration for this distro first (see TOOLCHAIN.md)"

log "Images on record"
docker images

log "Pulling latest for each"
docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | sort -u | while IFS= read -r image; do
	echo
	echo "-- $image"
	docker pull "$image" || echo "   skipped — likely a local-only build with no upstream to pull"
done

log "Removing containers pinned to a superseded image"
# docker ps falls back to printing the raw image ID (instead of repo:tag)
# once the tag a container was created from has moved to a new digest —
# that's the signal used here, no separate tracking needed.
while IFS=$'\t' read -r name image; do
	[[ "$image" =~ ^[0-9a-f]{12,}$ ]] || continue
	echo "  $name (was $image) — recreate via whatever created it (Aspire AppHost, compose, etc.)"
	docker rm -f "$name" >/dev/null
done < <(docker ps -a --format '{{.Names}}\t{{.Image}}')

log "Pruning dangling <none> images"
docker image prune -f

log "Images after refresh"
docker images
