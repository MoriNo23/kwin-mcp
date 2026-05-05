#!/usr/bin/env bash
# scripts/test-distro.sh — Host wrapper for kwin-mcp Docker smoke harness.
#
# Usage: scripts/test-distro.sh <distro>
#   <distro>  One of: archlinux (more distros coming; add Dockerfile + SUPPORTED entry)
#
# Flow: uv build --wheel → docker build → docker run → exit with container exit code
# Each distro uses a single Dockerfile (<distro>.Dockerfile) that resolves to the
# correct architecture automatically (manjarolinux/base is multi-arch for archlinux).
set -euo pipefail
IFS=$'\n\t'

SUPPORTED=(archlinux)

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [ $# -ne 1 ]; then
  echo "usage: $(basename "$0") <distro>" >&2
  echo "supported: ${SUPPORTED[*]}" >&2
  exit 2
fi

distro="$1"
supported=false
for d in "${SUPPORTED[@]}"; do
  [ "$d" = "$distro" ] && supported=true && break
done

if [ "$supported" = false ]; then
  echo "error: distro '$distro' not supported (no docker/${distro}.Dockerfile defined)" >&2
  echo "supported distros: ${SUPPORTED[*]}" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Resolve repo root
# ---------------------------------------------------------------------------
REPO=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$(realpath "$0")")")

# ---------------------------------------------------------------------------
# Single Dockerfile per distro slot (no host-arch branching)
# manjarolinux/base is multi-arch (linux/amd64 + linux/arm64); Docker pulls
# the correct architecture layer automatically; no host-machine probe needed.
# ---------------------------------------------------------------------------
dockerfile="${distro}.Dockerfile"
if [ ! -f "$REPO/docker/$dockerfile" ]; then
  echo "error: docker/$dockerfile not found" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Build wheel (always rebuild — guarantees fresh code)
# ---------------------------------------------------------------------------
echo "==> Building kwin-mcp wheel..."
uv build --wheel --out-dir "$REPO/dist"
wheel=$(ls -t "$REPO/dist"/kwin_mcp-*.whl 2>/dev/null | head -1 || true)
if [ -z "$wheel" ]; then
  echo "error: no kwin-mcp wheel in dist/" >&2
  exit 3
fi
echo "==> Wheel: $wheel"

# ---------------------------------------------------------------------------
# Build image
# ---------------------------------------------------------------------------
echo "==> Building Docker image kwin-mcp-test:${distro}..."
DOCKER_HOST=tcp://localhost:2375 docker build \
  --build-arg UID=1000 \
  --build-arg GID=1000 \
  -f "$REPO/docker/$dockerfile" \
  -t "kwin-mcp-test:${distro}" \
  "$REPO/docker"
echo "==> Image built: kwin-mcp-test:${distro}"

# ---------------------------------------------------------------------------
# Prepare evidence directory (chmod 0777 so container uid 1000 can write)
# ---------------------------------------------------------------------------
mkdir -p "$REPO/.sisyphus/evidence/${distro}"
chmod 0777 "$REPO/.sisyphus/evidence/${distro}"

# ---------------------------------------------------------------------------
# Run container (forbidden-flag policy: see docker/runtime-contract.md)
# ---------------------------------------------------------------------------
echo "==> Running smoke test in container..."
DOCKER_HOST=tcp://localhost:2375 docker run --rm \
  -v "$REPO/dist:/wheels:ro" \
  -v "$REPO/docker/smoke_test.py:/opt/docker/smoke_test.py:ro" \
  -v "$REPO/docker/smoke_app.qml:/opt/docker/smoke_app.qml:ro" \
  -v "$REPO/.sisyphus/evidence/${distro}:/evidence" \
  "kwin-mcp-test:${distro}"
