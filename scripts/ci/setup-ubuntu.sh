#!/usr/bin/env bash
# Install kwin-mcp integration test dependencies on Ubuntu (24.04+).
#
# This uses the stock Ubuntu archive. For a Kubuntu-like environment with
# bleeding-edge KDE, layer the kubuntu-ppa/backports PPA before running this
# script.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update

# KWin + session bootstrap
apt-get install -y --no-install-recommends \
    kwin-wayland \
    dbus-daemon \
    libglib2.0-bin \
    at-spi2-core \
    libwayland-client0 \
    wayland-utils \
    libgl1-mesa-dri \
    libglvnd0

# Clipboard / input helpers
apt-get install -y --no-install-recommends \
    wl-clipboard \
    wtype \
    kde-spectacle

# End-to-end GUI targets (kcalc for arithmetic, kate for keyboard input)
apt-get install -y --no-install-recommends kcalc kate

# PyGObject / dbus-python build dependencies
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-gi \
    gir1.2-atspi-2.0 \
    python3-dbus \
    libcairo2-dev \
    libgirepository-2.0-dev \
    libdbus-1-dev \
    pkg-config \
    gcc \
    git \
    ca-certificates \
    curl

# uv (Python package manager)
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
