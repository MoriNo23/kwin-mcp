# docker/archlinux.Dockerfile - Arch-family test image (multi-arch).
# FROM line uses manjarolinux/base because the official archlinux:base is
# amd64-only on Docker Hub; Manjaro ships archlinux-keyring + manjaro-keyring,
# is pacman-based, and is multi-arch (linux/amd64 + linux/arm64). One Dockerfile
# therefore covers both architectures from the user-facing 'archlinux' slot.
FROM manjarolinux/base:20260322

RUN pacman-key --init \
 && pacman-key --populate archlinux manjaro \
 && pacman -Syu --noconfirm --needed \
# Package substitutions from T6 spec:
#   - dbus-python-common (Arch package name) -> python-dbus (Manjaro equivalent)
#     [reason: dbus-python-common is not available in Manjaro 20260322 x86_64 repos]
#   - dbus, qt6-declarative kept explicit for safety even though transitive deps
#   - See docker/runtime-contract.md "Package substitutions" section
 && pacman -S --noconfirm --needed \
       kwin spectacle at-spi2-core python-gobject python-dbus dbus mesa wl-clipboard wtype wayland-utils python uv qt6-declarative gcc pkgconf \
 && pacman -Scc --noconfirm \
 && rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*.db

# kwin_wayland ships with `cap_sys_nice=ep` file capability for realtime
# scheduling. Container runtimes apply NoNewPrivileges by default for non-root
# users, which causes the kernel to refuse exec ("Operation not permitted").
# Virtual mode (--virtual, software rendering) does not need elevated caps,
# so strip them at build time. /usr/bin/kwin_wayland and /usr/sbin/kwin_wayland
# are hardlinks to the same inode; one setcap -r covers both.
RUN setcap -r /usr/bin/kwin_wayland \
 && (getcap /usr/bin/kwin_wayland | tee /tmp/getcap.out; ! grep -q '=' /tmp/getcap.out)

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN existing_group=$(getent group 1000 | cut -d: -f1 || true) \
 && if [ -n "$existing_group" ] && [ "$existing_group" != kwinmcp ]; then groupmod -n kwinmcp "$existing_group"; fi \
 && if ! getent group 1000 >/dev/null; then groupadd -g 1000 kwinmcp; fi \
 && existing_user=$(getent passwd 1000 | cut -d: -f1 || true) \
 && if [ -n "$existing_user" ] && [ "$existing_user" != kwinmcp ]; then usermod -l kwinmcp -d /home/kwinmcp -m -s /bin/bash "$existing_user"; fi \
 && if ! getent passwd 1000 >/dev/null; then useradd -m -u 1000 -g 1000 -s /bin/bash kwinmcp; fi

RUN mkdir -p /run/user/1000 \
 && chown 1000:1000 /run/user/1000 \
 && chmod 0700 /run/user/1000

ENV XDG_RUNTIME_DIR=/run/user/1000

RUN install -d -o 1000 -g 1000 /opt/kwinmcp-venv \
 && su kwinmcp -c "uv venv --system-site-packages /opt/kwinmcp-venv"

ENV PATH=/opt/kwinmcp-venv/bin:$PATH \
    PYTHONUNBUFFERED=1

RUN install -d -o 1000 -g 1000 /opt/docker /wheels /evidence

COPY --chown=1000:1000 entrypoint.sh /opt/docker/entrypoint.sh
RUN chmod +x /opt/docker/entrypoint.sh

WORKDIR /home/kwinmcp
USER kwinmcp

ENTRYPOINT ["/opt/docker/entrypoint.sh"]
