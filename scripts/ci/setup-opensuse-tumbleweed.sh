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

# Round 19g diagnostic showed /usr/bin/gcc + /usr/bin/cc already symlink to
# gcc-15 from the RPM, but pycairo still failed at "cc not found" in Round
# 19f. Hypothesis: a uv build-isolation env masks /usr/bin from PATH, OR a
# post-install hook fires after setup completes. Print PATH and gcc binary
# state, then unconditionally re-create the symlinks (idempotent).
{
    echo "::group::gcc/PATH diagnostic"
    echo "PATH=${PATH}"
    ls -la /usr/bin/gcc /usr/bin/cc /usr/bin/gcc-15 2>&1 || true
    type gcc 2>&1 || true
    type cc 2>&1 || true
    echo "::endgroup::"
} >&2
[ -x /usr/bin/gcc-15 ] && ln -sf /usr/bin/gcc-15 /usr/bin/gcc || true
[ -x /usr/bin/gcc-15 ] && ln -sf /usr/bin/gcc-15 /usr/bin/cc || true

# Round 19h evidence: setup-step PATH includes /usr/bin and `type cc` resolves
# to /usr/bin/cc, but uv's PEP 517 build for pycairo still fails meson's
# `cc --version` probe with [Errno 2]. uv's build-isolation venv apparently
# loses /usr/bin from the subprocess PATH on this image. Propagate absolute
# CC/CXX via $GITHUB_ENV so the next workflow step (uv sync) bypasses meson's
# PATH lookup entirely and reaches the compiler by absolute path.
#
# Round 19i adds PKG_CONFIG. With the CC/CXX propagation in place pycairo's
# meson run advanced to "Did not find pkg-config by name 'pkg-config'" -- the
# same lost-/usr/bin path stripped pkgconf too. meson honors $PKG_CONFIG as
# an absolute-path override; pointing it at the real pkgconf binary bypasses
# the PATH lookup the same way CC/CXX does for the compiler.
#
# Round 19j evidence: /usr/bin/pkg-config on Tumbleweed is a SHELL SCRIPT
# wrapper (symlinks to x86_64-suse-linux-gnu-pkg-config, which calls pkgconf
# with a triplet PKG_CONFIG_LIBDIR for cross-compile setups). The wrapper
# bare-execs `pkgconf`, so under uv's stripped build PATH it dies with
# "WARNING: Found pkg-config '/usr/bin/pkg-config' but it failed when ran".
# Prefer the bare /usr/bin/pkgconf binary (also pkg-config 1.x compatible),
# which has zero PATH dependencies. Fall back to the wrapper only if the
# pkgconf binary is missing for some reason.
PKG_CONFIG_BIN=""
for cand in /usr/bin/pkgconf /usr/bin/pkg-config; do
    if [ -x "$cand" ]; then
        PKG_CONFIG_BIN="$cand"
        break
    fi
done
{
    echo "::group::pkg-config diagnostic"
    type pkg-config 2>&1 || true
    type pkgconf 2>&1 || true
    ls -la /usr/bin/pkg-config /usr/bin/pkgconf 2>&1 || true
    echo "PKG_CONFIG_BIN=${PKG_CONFIG_BIN}"
    echo "::endgroup::"
} >&2

if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "CC=/usr/bin/gcc-15"
        echo "CXX=/usr/bin/gcc-15"
        echo "AR=/usr/bin/ar"
        echo "RANLIB=/usr/bin/ranlib"
        echo "STRIP=/usr/bin/strip"
        if [ -n "$PKG_CONFIG_BIN" ]; then
            echo "PKG_CONFIG=$PKG_CONFIG_BIN"
        fi
        # Round 19k: dbus-python's ninja link rule executes the bare-name
        # `rm -f libdbus-gmain.a && /usr/bin/ar csrDT ...` shell command and
        # dies with `/bin/sh: line 1: rm: command not found`. The setup-step
        # PATH does include /usr/bin (verified by the gcc/PATH diagnostic),
        # but uv's PEP 517 build subprocess on Tumbleweed somehow ends up
        # without it. Re-export the full PATH explicitly so the next workflow
        # step (uv sync) and any subprocess uv spawns inherit it. We cannot
        # use $GITHUB_PATH (which only prepends) because /usr/bin is already
        # there at workflow level -- the loss happens deeper, and only an
        # explicit PATH= in $GITHUB_ENV is propagated through uv's env.
        echo "PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:${PATH}"
    } >> "$GITHUB_ENV"
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
