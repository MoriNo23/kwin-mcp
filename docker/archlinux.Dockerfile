# docker/archlinux.Dockerfile - Arch-family test image (multi-arch).
# FROM line uses manjarolinux/base because the official archlinux:base is
# amd64-only on Docker Hub; Manjaro ships archlinux-keyring + manjaro-keyring,
# is pacman-based, and is multi-arch (linux/amd64 + linux/arm64). One Dockerfile
# therefore covers both architectures from the user-facing 'archlinux' slot.
FROM manjarolinux/base:20260322

RUN pacman-key --init \
 && pacman-key --populate archlinux manjaro \
 && pacman -Syu --noconfirm --needed \
 && pacman -S --noconfirm --needed \
      kwin spectacle at-spi2-core python-gobject dbus-python-common \
      mesa wl-clipboard wtype wayland-utils \
      python uv \
 && pacman -Scc --noconfirm \
 && rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*.db

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN groupadd -g 1000 kwinmcp && useradd -m -u 1000 -g 1000 -s /bin/bash kwinmcp

RUN mkdir -p /run/user/1000 \
 && chown 1000:1000 /run/user/1000 \
 && chmod 0700 /run/user/1000

ENV XDG_RUNTIME_DIR=/run/user/1000

RUN install -d -o 1000 -g 1000 /opt/kwinmcp-venv \
 && su kwinmcp -c "uv venv /opt/kwinmcp-venv"

ENV PATH=/opt/kwinmcp-venv/bin:$PATH \
    PYTHONUNBUFFERED=1

RUN install -d -o 1000 -g 1000 /opt/docker /wheels /evidence

COPY --chown=1000:1000 entrypoint.sh /opt/docker/entrypoint.sh
RUN chmod +x /opt/docker/entrypoint.sh

WORKDIR /home/kwinmcp
USER kwinmcp

ENTRYPOINT ["/opt/docker/entrypoint.sh"]
