#!/usr/bin/env bash
# Install kwin-mcp integration test dependencies on Fedora.
set -euo pipefail

dnf -y update

# KWin + session bootstrap
dnf -y install \
    kwin-wayland \
    dbus-daemon \
    glib2 \
    at-spi2-core \
    wayland-devel \
    wayland-utils \
    mesa-dri-drivers \
    mesa-libGL

# Clipboard / input helpers
dnf -y install \
    wl-clipboard \
    wtype \
    spectacle

# End-to-end GUI targets (kcalc for arithmetic, kate for keyboard input)
dnf -y install kcalc kate

# PyGObject / dbus-python build dependencies
dnf -y install \
    python3 \
    python3-devel \
    python3-pip \
    python3-gobject \
    python3-dbus \
    dbus-devel \
    cairo-devel \
    gobject-introspection-devel \
    pkgconf \
    gcc \
    git

# uv (Python package manager)
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
