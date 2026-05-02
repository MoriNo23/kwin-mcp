#!/usr/bin/env bash
# Install kwin-mcp integration test dependencies on openSUSE Tumbleweed.
set -euo pipefail

zypper --non-interactive refresh

# KWin + session bootstrap. Tumbleweed ships Plasma 6 → kwin6.
# Fall back to kwin5 if kwin6 is not yet indexed on the rolling release.
if ! zypper --non-interactive install --no-recommends kwin6; then
    zypper --non-interactive install --no-recommends kwin5
fi
zypper --non-interactive install --no-recommends xdg-desktop-portal-kde

zypper --non-interactive install --no-recommends \
    bash \
    dbus-1 \
    dbus-1-devel \
    glib2-tools \
    at-spi2-core \
    libwayland-client0 \
    wayland-utils \
    Mesa-dri \
    libcap-progs \
    Mesa-libGL1

# Container runtimes can reject binaries with file capabilities.
setcap -r "$(command -v kwin_wayland)" 2>/dev/null || true

# Clipboard / input helpers
zypper --non-interactive install --no-recommends \
    wl-clipboard \
    wtype \
    spectacle

# End-to-end GUI targets (kcalc for arithmetic, kate for keyboard input)
zypper --non-interactive install --no-recommends kcalc kate

# PyGObject / dbus-python build dependencies.
# --force-resolution lets full GNU diffutils/gettext replace the busybox-*
# providers without a separate `zypper remove` step. Removing busybox-diffutils
# explicitly cascades on Tumbleweed and can wipe /usr/bin/sh, after which the
# next workflow step exits with `OCI runtime exec failed: exec: "sh": not found`.
zypper --non-interactive install --no-recommends --force-resolution \
    diffutils gettext-tools coreutils
ln -sf /usr/bin/bash /bin/sh 2>/dev/null || true

zypper --non-interactive install --no-recommends \
    python313 \
    python313-devel \
    python313-pip \
    python313-gobject \
    python313-dbus-python \
    cairo-devel \
    gobject-introspection-devel \
    pkgconf \
    gcc \
    git

# uv (Python package manager)
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
