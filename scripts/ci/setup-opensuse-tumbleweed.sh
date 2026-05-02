#!/usr/bin/env bash
# Install kwin-mcp integration test dependencies on openSUSE Tumbleweed.
set -euo pipefail

zypper --non-interactive refresh

# KWin + session bootstrap. Tumbleweed ships Plasma 6 → kwin6.
# Fall back to kwin5 if kwin6 is not yet indexed on the rolling release.
if ! zypper --non-interactive install kwin6; then
    zypper --non-interactive install kwin5
fi

zypper --non-interactive install \
    dbus-1 \
    glib2-tools \
    at-spi2-core \
    libwayland-client0 \
    wayland-utils \
    Mesa-dri \
    Mesa-libGL1

# Clipboard / input helpers
zypper --non-interactive install \
    wl-clipboard \
    wtype \
    spectacle

# End-to-end GUI targets (kcalc for arithmetic, kate for keyboard input)
zypper --non-interactive install kcalc kate

# PyGObject / dbus-python build dependencies
zypper --non-interactive install \
    python3 \
    python3-pip \
    python3-gobject \
    python3-dbus-python \
    cairo-devel \
    gobject-introspection-devel \
    pkgconf \
    gcc \
    git

# uv (Python package manager)
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
