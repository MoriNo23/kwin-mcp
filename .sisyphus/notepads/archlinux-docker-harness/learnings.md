# Learnings — archlinux-docker-harness

## [2026-05-05] Plan initialized

### Base image decision (pre-decided)
- `manjarolinux/base:YYYYMMDD` — multi-arch (linux/amd64 + linux/arm64), pacman-based
- `archlinux:base` was REJECTED: amd64-only on Docker Hub
- Must populate BOTH keyrings: `pacman-key --populate archlinux manjaro`
- Date-tag format: `YYYYMMDD` (e.g. `20260322`) — NO `:latest`, NO `@sha256:`

### API shape (CRITICAL)
- `accessibility_tree()` returns FORMATTED TEXT STRINGS — NOT dicts/JSON
- `find_ui_elements()` returns FORMATTED TEXT STRINGS — NOT dicts/JSON
- Real ElementInfo fields: `role, name, description, states, x, y, width, height, actions, children_count, depth`
- Line format for FIND_RE parsing: `- [{role}] "{name}" @ ({x}, {y}, {width}x{height}) [actions: ...]`
- No `children`, `accessible_name`, `value` keys in public API

### Test app (pre-decided)
- `docker/smoke_app.qml` launched via `qml6` (provided by qt6-declarative, transitive dep of kwin)
- 3 exact accessible names: "Smoke entry", "Ping button", "Status text"
- ZERO extra Arch packages needed

### Container setup
- User: `kwinmcp` uid 1000, gid 1000
- Venv: `/opt/kwinmcp-venv` (uv-created, owned by kwinmcp)
- XDG_RUNTIME_DIR: `/run/user/1000`, mode 0700
- LANG=C.UTF-8, LC_ALL=C.UTF-8
- Wheel mounted at `/wheels:ro`, evidence at `/evidence`

### Forbidden flags (ABSOLUTE)
5 exact strings that must NEVER appear in runtime-affecting files:
`--privileged`, `--cap-add=SYS_ADMIN`, `--device=/dev/uinput`, `--device=/dev/input`, `--device=/dev/dri`
## [2026-05-04T15:11:47Z] T2: smoke_app.qml written with exact accessible names
## [2026-05-04T15:12:22Z] T4: .gitignore updated with .sisyphus/evidence/
## [2026-05-05T00:00:00Z] T5: docker/ scaffolded with README.md
## [2026-05-04T15:12:28Z] T3: runtime-contract.md written (12 sections, placeholder for date-tag)

## [2026-05-04T15:14:10Z] T1: date-tag locked
- Locked base image: `manjarolinux/base:20260322` (pushed 2026-03-22, ~6 weeks old → stable).
- Multi-arch verified: `linux/amd64` digest `sha256:a411dec…5c84`, `linux/arm64` digest `sha256:367eb43…79b5`. OCI image-index covers both.
- Pull verification ran via `DOCKER_HOST=tcp://localhost:2375` against this host's docker daemon — both `docker pull` and `docker pull --platform linux/arm64` succeeded.
- QA gotcha: the literal substring `@sha256:` is forbidden anywhere in `task-1-base-image-decision.md` (not just the FROM line). When discussing digest-pinning rejection, use prose ("sha256 digest pinning") instead of the AT-prefixed token.
- Audit file `task-1-rejected-flags-audit.txt` left intentionally empty — Manjaro base needs none of `--privileged`, `--cap-add=SYS_ADMIN`, `--device=/dev/{uinput,input,dri}` for plain pacman/install workloads.
- Downstream: T6 Dockerfile FROM line, T3 runtime-contract `{{MANJARO_DATE_TAG}}` placeholder both resolve to `20260322`.
## [2026-05-04T15:19:57Z] T6: archlinux.Dockerfile written (FROM manjarolinux/base:20260322)
## [2026-05-04T15:22:58Z] T9: test-distro.sh written (SUPPORTED=(archlinux), no uname -m, DOCKER_HOST=tcp://localhost:2375)
- QA gotcha: forbidden-flag QA scans the WHOLE file (not just docker run lines). Comments referencing flag literals (e.g. "NO --privileged") trigger FAIL. Reword to point at runtime-contract.md instead.
- QA gotcha: "no uname -m" check also greps the whole file. Documenting the rationale must avoid the literal token "uname -m"; use "host-machine probe" instead.
- Negative path verified: bash scripts/test-distro.sh ubuntu → exit 2 + "not supported" stderr message.
## [2026-05-04T15:23:00Z] T7: docker/entrypoint.sh written
- Strict mode (set -euo pipefail + IFS hardened), EXIT trap writes summary.json skeleton on any non-zero exit when smoke_test.py has not produced one.
- Evidence dir is timestamped: /evidence/$(date -u +%Y%m%dT%H%M%SZ); screenshots/ and a11y/ subdirs created up front.
- stdout/stderr tee-d to $EVIDENCE_DIR/{stdout,stderr}.log via process substitution so the redirection survives across the final exec.
- Wheel discovery: `ls -t /wheels/kwin_mcp-*.whl | head -1`; missing wheel -> exit 3 with `no_wheel_found`; uv pip install failure -> exit 3 with `wheel_install_failed`.
- install.json producer is a Python heredoc reading WHEEL_BASENAME / WHEEL_SHA256 / KWIN_MCP_VERSION / IMAGE_TAG (env-vars exported by the bash prologue) and pacman -Q for package_versions; FileNotFoundError swallowed so a non-Arch base falls back to empty package_versions.
- IMAGE_TAG sourced from $KWIN_MCP_IMAGE_TAG (set by scripts/test-distro.sh at run time), defaulting to "unknown".
- Final hand-off uses `exec /opt/kwinmcp-venv/bin/python /opt/docker/smoke_test.py` so the smoke test owns the container exit code.
- QA: bash -n clean (shellcheck unavailable on this host), 19 structural PASS lines + 9 error-path PASS lines + offline producer test confirming the exactly-5-keys invariant.

## [2026-05-05T00:00:00Z] T8: smoke_test.py static smoke driver
- `docker/smoke_test.py` imports `AutomationEngine` directly and adds the repository `src/` path before import so `/tmp/t8-find-center.py` can import `find_center` without an installed package.
- `FIND_RE` matches the actual `find_ui_elements()` text line: `- [role] "name" @ (x, y, widthxheight)` with optional actions ignored after the geometry.
- Evidence files for T8 are `.sisyphus/evidence/task-8-static-checks.txt`, `.sisyphus/evidence/task-8-no-forbidden-patterns.txt`, and `.sisyphus/evidence/task-8-find-center-fixture.txt`.

## [2026-05-04 18:17:30 UTC] T11 — docs/docker-testing.md

- Wrote 9-section doc per spec
- Generic forbidden-flag wording (no literal strings)
- Honesty: "Known limitations" includes current hang note pending T10 resolution

## [2026-05-04T18:24:44Z] Piece 1 — Dockerfile + contract cleanup
- Pacman investigation: x86_64 Manjaro 20260322 has no dbus-python-common; python-dbus exists and provides Python D-Bus bindings. qt6-declarative provides QML/JavaScript classes and depends on qt6-base. python-gobject hard deps are gobject-introspection-runtime and python; python-cairo is only optional via Cairo bindings, not a kept hard dependency. Note: default local docker platform resolved to arm64 where python-dbus was absent but dbus-python existed; x86_64 evidence was added because the harness Dockerfile runs on the host default platform.
- Removed: base-devel, pkgconf, python-cairo
- Substituted: dbus-python-common → python-dbus
- Kept-explicit (transitive but safety): dbus, qt6-declarative
- Contract section "Package substitutions" added

## [2026-05-04T18:25:08Z] Piece 2 — session.py SDK fix
- Change A: socket path double-prefix fix at session.py:~173 (already present on entry)
- Change B: same fix inside dbus-run-session inline wrapper at session.py:~380 (already present on entry)
- Change C: kded6 + kglobalacceld auto-start in wrapper at session.py:~357
- Diff size: 9 + / 0 -
- ruff PASS, py_compile PASS
