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
    util-linux \
    dbus-1 \
    dbus-1-devel \
    glib2-tools \
    at-spi2-core \
    libwayland-client0 \
    wayland-utils \
    Mesa-dri \
    libcap-progs \
    Mesa-libGL1 \
    xwayland

# Container runtimes can reject binaries with file capabilities.
setcap -r "$(command -v kwin_wayland)" 2>/dev/null || true

# Disable xdg-desktop-portal D-Bus auto-activation. KWin auto-activates the
# portal on startup, but the portal backend cannot reach a working compositor
# in headless containers and crashes; the activation cascade then segfaults
# KWin while it waits for the portal reply. Renaming the .service files
# prevents activation entirely; KWin runs fine without the portal in our
# test scope (no screencast / sandboxed file-chooser usage).
for service in \
    org.freedesktop.portal.Desktop \
    org.freedesktop.portal.Documents \
    org.freedesktop.impl.portal.desktop.kde \
    org.freedesktop.impl.portal.desktop.gtk; do
    file="/usr/share/dbus-1/services/${service}.service"
    if [ -e "$file" ]; then
        mv "$file" "${file}.disabled"
    fi
done

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

# Guard: the busybox cascade above can leave /usr/bin/bash and /usr/bin/sh
# in an inconsistent state. The next workflow step will run with `shell: bash`
# (set in defaults.run.shell) and fail with `OCI runtime exec failed` if bash
# is not on PATH. Surfacing the failure here, before pytest, makes the cause
# obvious instead of producing an exec-127 in a later, unrelated step.
if ! command -v bash >/dev/null 2>&1; then
    echo "ERROR: bash binary missing from PATH after openSUSE setup" >&2
    exit 1
fi
