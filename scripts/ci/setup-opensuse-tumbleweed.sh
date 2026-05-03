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
    xwayland \
    gdb

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
# The force-resolution above also removes busybox / busybox-coreutils, which
# on Tumbleweed minimal images owned the /usr/bin/bash symlink that the GNU
# bash package didn't claim. Force-reinstall bash to put a real binary back
# at /usr/bin/bash before the next workflow step's OCI exec resolves it.
zypper --non-interactive install --force --no-recommends bash
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

# Tumbleweed installs versioned compiler binaries (e.g. /usr/bin/gcc-15)
# but the unversioned /usr/bin/gcc symlink lives in a separate `alts`
# post-install hook that is skipped by --no-recommends + --non-interactive.
# pycairo's meson build probes `cc`/`gcc` first, so missing symlinks fail
# the wheel build with `Unknown compiler(s)`. Idempotent backstop: locate
# the newest versioned gcc binary and force-link it to the unversioned
# names. ln -sf is no-op-safe if the link already points to the same target.
echo "::group::gcc symlink diagnostic (Round 19g)" >&2
ls -la /usr/bin/gcc* /usr/bin/cc* 2>&1 | head -30 >&2 || true
echo "command -v gcc -> $(command -v gcc 2>&1 || echo NOT_FOUND)" >&2
echo "::endgroup::" >&2

GCC_BIN=$(ls /usr/bin/gcc-[0-9]* /usr/bin/gcc[0-9]* 2>/dev/null \
    | grep -vE '\-doc$|\-locale$|\.gz$|\.so' \
    | sort -V | tail -1)
if [ -n "$GCC_BIN" ] && [ -x "$GCC_BIN" ]; then
    ln -sf "$GCC_BIN" /usr/bin/gcc
    ln -sf "$GCC_BIN" /usr/bin/cc
    echo "Symlinked $GCC_BIN to /usr/bin/gcc and /usr/bin/cc" >&2
else
    echo "WARNING: no versioned gcc binary found to symlink" >&2
fi

# uv (Python package manager)
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# The workflow's defaults.run.shell uses /usr/bin/bash as an absolute path
# (Round 19a evidence: PATH inside the setup step had bash, but the next
# step's docker exec did its own PATH lookup against a different env and
# failed with `exec: "bash": not found`). Catch the case where the busybox
# cascade above somehow leaves /usr/bin/bash unwritten.
if [ ! -x /usr/bin/bash ]; then
    echo "ERROR: /usr/bin/bash missing after openSUSE setup" >&2
    exit 1
fi
