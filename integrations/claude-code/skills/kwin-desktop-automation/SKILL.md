---
name: kwin-desktop-automation
description: "Use when automating, debugging, or interacting with a KDE Plasma 6 Wayland desktop session — enumerate/rise/close windows, inspect AT-SPI2 trees, drive mouse/keyboard/touch, run apps in an isolated virtual KWin session, write raise-or-launch wrappers for waybar/launcher scripts, or build resource-monitoring waybar modules (memory, disk, CPU) with health states and actionable tooltips."
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [kde, kwin, plasma, wayland, mcp, gui-automation, desktop, waybar, xdotool, at-spi2, monitoring, mawk, pango]
    related_skills: [native-mcp, mcporter, wails-v3-linux-systray, requesting-code-review, limpieza-espacio-disco-debian]
---

# KDE Plasma 6 / KWin Wayland Desktop Automation

## Overview

KDE Plasma 6 on Wayland removed the X11 window-management APIs that `xdotool`, `wmctrl`, and similar tools relied on. Window control now has to go through **KWin's own DBus scripting interface** (`org.kde.KWin /Scripting`) or **AT-SPI2** (accessibility) for input semantics. This skill documents the patterns that work in 2026, the MCP server that wraps them (`kwin-mcp`), and the diagnostic recipes that work **without launching GUI apps** (so an agent can verify behavior headlessly).

Use this skill when: debugging why a launcher/waybar `on-click` keeps spawning duplicate windows, writing raise-or-launch wrappers, inspecting window state from a script, or driving a Plasma desktop from another agent.

## Headless Debugging Doctrine (READ FIRST)

**The cardinal rule:** when debugging any window-management or raise-or-launch behaviour, **never launch the app you're trying to test**. You will pollute the user's desktop, change the active window, and get results that pass for the wrong reason. The user explicitly called this out: *"esa herramienta que estás lanzando es GUI, no sirve para debuggear"*. The right introspection is always one of:

| What you need to know | Headless method (no GUI launched) |
|---|---|
| What windows exist? | KWin probe.js via `qdbus6 loadScript` + `Script.run` (see below) — or `kwin-mcp` `dbus_call` |
| Is the raise working? | `qdbus6 org.kde.KWin /KWin org.kde.KWin.queryWindowInfo` before & after — compare `caption` / `resourceClass` |
| Is the process alive? | `kill -0 <pid>`; `pgrep -af <name>` |
| What class/window owns a PID? | KWin probe.js with `print("WIN|"+w.pid+"|"+w.caption+"|"+w.resourceClass)` |
| What DBus methods does KWin expose? | `qdbus6 org.kde.KWin /Scripting` (introspect), or `kwin-mcp` `dbus_call` |
| Is the lockfile stale? | `[ -f LOCK ] && kill -0 $(cat LOCK)` — no new launch |
| Behaviour in a clean isolated env? | `kwin-mcp session_start` → run a dummy app → run your raise script → `queryWindowInfo` to verify |

**KWin `print()` capture is unreliable.** On Debian 13 + Plasma 6.3 the stderr of `kwin_wayland` is NOT captured by `journalctl _COMM=kwin_wayland` (the journal is empty even though the script ran). Do not assume a silent journal means a failed script — `loadScript` returning a slot + `Script.run` returning success is the authoritative signal. If you need to confirm a raise worked, diff `queryWindowInfo` before/after, or use the `callDBus` callback pattern from https://rudd-o.com/linux-and-free-software/how-to-raise-a-window-under-wayland-or-x11-when-using-kde-kwin-plasma to get a synchronous return value.

## When to Use

- User reports a waybar, rofi, wofi, kcmshell6, or similar launcher spawning duplicate windows on click → raise-or-launch pattern.
- Need to enumerate, raise, focus, or close windows in a Plasma 6 Wayland session from a shell script.
- Need to drive the desktop (mouse, keyboard, touch, screenshots, AT-SPI2 tree) from an agent.
- Need to verify a window-management change **without launching a GUI app** (e.g. from a headless test).
- Need a single-instance wrapper for `kcmshell6 <module>`, `systemsettings`, or any other app that should not multi-spawn.
- Writing CI/headless GUI tests for a KDE/Qt/GTK app on Wayland.

**Don't use for:** non-KDE compositors (Sway, Hyprland, GNOME, River — different DBus / wlroots protocols); X11 sessions (just use `xdotool` / `wmctrl`); anything not on Linux.

## MCP Server: kwin-mcp (30 tools)

The fastest path on Plasma 6 Wayland is the **`kwin-mcp`** MCP server (https://github.com/isac322/kwin-mcp, MIT, Python 3.12+). It ships 30 tools covering session management, observation, mouse, keyboard, touch, clipboard, and window management. Tools are registered with the prefix `mcp_kwin_mcp_*`.

### Install

```bash
# System deps (Debian/Ubuntu). The pygobject → pycairo build chain needs
# the *-2.0* variant of girepository (not the older 1.0). Forgetting it
# manifests as "Dependency 'girepository-2.0' is required but not found"
# during the meson build of pycairo/pygobject.
sudo apt install kwin-wayland spectacle at-spi2-core \
    python3-gi gir1.2-atspi-2.0 python3-dbus \
    libgirepository-2.0-dev libcairo2-dev pkg-config python3-dev

# Python deps (Hermes' native MCP client needs the mcp package too)
pip install mcp

# The server itself.
# Option A: Install from the Debian-fixed fork (recommended for Debian/Ubuntu):
python3 -m venv ~/.venv-kwin-mcp
source ~/.venv-kwin-mcp/bin/activate
pip install "kwin-mcp @ git+https://github.com/MoriNo23/kwin-mcp.git@main"
# Ensure ~/.venv-kwin-mcp/bin is in $PATH for the Hermes process.

# Option B: Original upstream (has AT-SPI2 bugs on Debian):
# uv tool install kwin-mcp
```

### Register with Hermes

Add to `~/.hermes/config.yaml` (use `hermes config edit`):

```yaml
mcp_servers:
  kwin-mcp:
    command: kwin-mcp
    args: []
    timeout: 60
    connect_timeout: 30
```

Restart Hermes. Tools appear prefixed `mcp_kwin_mcp_*`. Hermes' native MCP client (`native-mcp` skill) handles discovery, reconnection, and tool injection automatically.

### Tool Catalog (30)

| Category | Tools |
|---|---|
| **Session (3)** | `session_start`, `session_connect`, `session_stop` |
| **Observation (3)** | `screenshot`, `accessibility_tree`, `find_ui_elements` |
| **Mouse (6)** | `mouse_click`, `mouse_move`, `mouse_scroll`, `mouse_drag`, `mouse_button_down`, `mouse_button_up` |
| **Keyboard (6)** | `keyboard_type`, `keyboard_type_unicode`, `keyboard_key`, `keyboard_key_down`, `keyboard_key_up` |
| **Touch (4)** | `touch_tap`, `touch_swipe`, `touch_pinch`, `touch_multi_swipe` |
| **Clipboard (2)** | `clipboard_get`, `clipboard_set` |
| **Wait (1)** | `wait_for_element` |
| **Apps (4)** | `launch_app`, `list_windows`, `focus_window`, `dbus_call` |
| **Diagnostics (2)** | `read_app_log`, `wayland_info` |

`session_start` creates an **isolated** KWin session (sandboxed via `dbus-run-session` + `kwin_wayland --virtual`) so automation never touches the host desktop. `session_connect` attaches to a **real** existing KWin instance (host desktop or container) — only use when the user explicitly says "do it on my real session".

## Raise-or-Launch: the Waybar Click Pattern

The default problem: every click on a waybar module runs `kcmshell6 <module>` and opens a new window. The fix is a wrapper that:
1. Checks if a window for the module is already open (by PID or by KWin resource class).
2. If yes, raises it via KWin scripting DBus (and restores from minimized).
3. If no, launches the module and records the PID.

### Pattern A: PID lockfile + KWin DBus raise (no extra deps)

This is the minimal pure-bash version. Works on any Plasma 6 install with `qdbus6` (part of `qt6-tools`).

```bash
#!/bin/bash
# ~/.config/waybar/scripts/kcm-launcher.sh
# Usage: kcm-launcher.sh <kcm-module-name>
# Raise existing KCM window if open, else launch and remember PID.
#
# Cleanup is LAZY: the next invocation detects a stale lockfile via
# `kill -0` and removes it. Do NOT add a background `( while kill -0 ...;
# do sleep 2; done; rm -f ... ) & disown` watcher — that pattern hangs
# the parent shell on some process supervisors (e.g. the Hermes terminal
# sandbox flags `&`/`nohup`/`disown` in foreground commands).
set -euo pipefail

KCM="$1"
LOCK="/tmp/kcm-${KCM}.pid"

# 1) Try to raise an existing instance (lazy cleanup of stale lockfile here)
if [ -f "$LOCK" ]; then
    PID=$(cat "$LOCK" 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        SCRIPT_FILE=$(mktemp --suffix=.js)
        cat > "$SCRIPT_FILE" <<EOF
var target = ${PID};
for (var i = 0; i < workspace.windowList().length; i++) {
    var w = workspace.windowList()[i];
    if (w.pid === target) {
        if (w.minimized) w.minimized = false;
        workspace.activeWindow = w;
        workspace.raiseWindow(w);
        break;
    }
}
EOF
        # loadScript returns the slot number; we must use the slot's
        # Script.run — Scripting.start() does NOT run a named script.
        SLOT=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
                  "$SCRIPT_FILE" "raise_${KCM}" 2>/dev/null \
               | awk 'END{print $NF}')
        if [ -n "$SLOT" ] && [ "$SLOT" -ge 0 ] 2>/dev/null; then
            qdbus6 org.kde.KWin "/Scripting/Script${SLOT}" \
                   org.kde.kwin.Script.run >/dev/null 2>&1 || true
        fi
        qdbus6 org.kde.KWin /Scripting \
               org.kde.kwin.Scripting.unloadScript "raise_${KCM}" >/dev/null 2>&1 || true
        rm -f "$SCRIPT_FILE"
        exit 0
    else
        # Stale lockfile (PID dead). Drop it and fall through to launch.
        rm -f "$LOCK"
    fi
fi

# 2) Launch new instance and record PID
kcmshell6 "$KCM" &
KCM_PID=$!
echo "$KCM_PID" > "$LOCK"
exit 0
```

Waybar config:

```jsonc
"pulseaudio": {
    "format": "{volume}%  ",
    "on-click": "~/.config/waybar/scripts/kcm-launcher.sh kcm_pulseaudio"
},
"network": {
    "on-click": "~/.config/waybar/scripts/kcm-launcher.sh kcm_networkmanagement"
}
```

### Pattern B: Match by WM_CLASS / desktopFile (no PID needed)

Slightly more robust against PID reuse. Match by KWin `resourceClass` instead. Use this when the launcher might be `systemsettings` (which reuses the parent process) or any app where you can't trust the PID.

```bash
SCRIPT=$(cat <<EOF
var matches = ${KCM_CLASS:-"\"org.kde.kcmshell6\""};
for (var i = 0; i < workspace.windowList().length; i++) {
    var w = workspace.windowList()[i];
    if (w.resourceClass === matches || w.desktopFile === "${DESKTOP}") {
        if (w.minimized) w.minimized = false;
        workspace.activeWindow = w;
        workspace.raiseWindow(w);
        break;
    }
}
EOF
)
```

The rest of the load/run/unload dance is the same as Pattern A.

### Pattern C: Use kwin-mcp tools from waybar (overkill but standard)

The waybar `on-click` is a single shell command. You can chain `hermes`-invoked MCP tools, but a far simpler path is the bash wrappers above. Reserve `kwin-mcp` for agent-driven sessions, not for human click latency.

## KWin Scripting DBus — The Underlying API

When you can't or won't install `kdotool` / `ww` / `kwin-mcp`, the raw API works fine. Important facts learned the hard way:

- Service: `org.kde.KWin`, paths under `/Scripting`.
- `loadScript(file, name) → int slot` — returns a slot number (0..3 in KWin 6; older versions had more).
- **To run a named script:** `dbus-send --print-reply --dest=org.kde.KWin /Scripting/Script${SLOT} org.kde.kwin.Script.run` (NOT `/Scripting org.kde.kwin.Scripting.start` — `start()` runs scripts loaded **without** a name, and there's no obvious feedback).
- **To stop:** `/Scripting/Script${SLOT} org.kde.kwin.Script.stop`.
- **To unload:** `/Scripting org.kde.kwin.Scripting.unloadScript string:${name}`.
- KWin 5 used `clientList()`; KWin 6 prefers `windowList()`. Both still work in 6.4+ but `clientList()` is deprecated.
- Script output (`print()`) goes to `kwin_wayland`'s **stderr**, captured by `journalctl _COMM=kwin_wayland` (NOT `kwin_wayland_wrapper`, NOT `--user` on most distros). On systems where this is empty, use `callDBus` to send results back synchronously — see https://rudd-o.com/linux-and-free-software/how-to-raise-a-window-under-wayland-or-x11-when-using-kde-kwin-plasma for the callback pattern.

## Diagnosing Without Launching GUIs

The cardinal rule: **do not launch `kcmshell6`, `konsole`, `kwrite`, etc. from a debug script** — it pollutes the desktop and your test results. Use these headless techniques (see the *Headless Debugging Doctrine* above for the full table).

### List all KWin clients (no apps launched) — probe.js + journal

This is the same trick `kdotool` uses internally. The output of `print()` lands in `journalctl _COMM=kwin_wayland` on most distros — but **on Debian 13 + Plasma 6.3 the journal is silent** (see Headless Debugging Doctrine). If the journal is empty, do not assume the script failed; verify via the `kwin-mcp`-based path below.

```bash
cat > /tmp/probe.js <<'EOF'
for (var i = 0; i < workspace.windowList().length; i++) {
    var w = workspace.windowList()[i];
    print("WIN|" + w.pid + "|" + w.caption + "|" + w.resourceClass + "|" + w.desktopFile);
}
EOF
SLOT=$(dbus-send --session --print-reply=literal --dest=org.kde.KWin \
        /Scripting org.kde.kwin.Scripting.loadScript \
        string:/tmp/probe.js string:probe | awk '{print $NF}')
dbus-send --session --print-reply --dest=org.kde.KWin \
        /Scripting/Script${SLOT} org.kde.kwin.Script.run >/dev/null
dbus-send --session --print-reply --dest=org.kde.KWin \
        /Scripting/Script${SLOT} org.kde.kwin.Script.stop >/dev/null
dbus-send --session --print-reply --dest=org.kde.KWin \
        /Scripting org.kde.kwin.Scripting.unloadScript string:probe >/dev/null
sleep 0.3
journalctl _COMM=kwin_wayland -o cat -S "$(date '+%Y-%m-%d %H:%M:%S')" | grep '^WIN|'
```

Expected output: one `WIN|` line per existing client with PID, caption, resourceClass, and desktopFile fields.

### Same probe via kwin-mcp (when journal is silent or you have kwin-mcp loaded)

```text
# 1. dbus_call → /Scripting org.kde.kwin.Scripting.loadScript
#    args: string:/tmp/probe.js, string:probe → returns int slot
# 2. dbus_call → /Scripting/Script{slot} org.kde.kwin.Script.run
# 3. dbus_call → /KWin org.kde.KWin.queryWindowInfo (active window only)
# 4. dbus_call → /Scripting org.kde.kwin.Scripting.unloadScript string:probe
```

`queryWindowInfo()` only returns the **active** window. To enumerate all windows without print(), use the `callDBus` callback pattern from rudd-o's recipe (linked above) — your KWin script calls back to a service you expose, returning the data synchronously.

### Query a specific window by uuid

```bash
qdbus6 org.kde.KWin /KWin org.kde.KWin.getWindowInfo "<uuid>"
```

Returns a QVariantMap including `caption`, `resourceClass`, `desktopFile`, `minimized`, etc. Requires the uuid (also returned by `queryWindowInfo()` for the active window, or by your own KWin script with `print(w.internalId)`).

### Check whether a process is actually a KCM

```bash
pgrep -af kcmshell6
pgrep -af systemsettings
```

If a `kcmshell6 kcm_xxx` is running but `kwin-mcp`'s `list_windows` (or your probe.js) doesn't show it, the KCM was launched as an X11 window via XWayland and KWin tracks it differently — use `resourceClass` matching, not PID, in the raise script.

### Validate a raise end-to-end in a clean isolated session

The cleanest validation when you can't (or won't) touch the user's real desktop:

1. `kwin-mcp session_start` (no app) — boots a sandboxed `kwin_wayland --virtual`.
2. `kwin-mcp launch_app konsole -e sleep 300` (or any GUI app) inside the sandbox.
3. Run your raise script (e.g. `kcm-launcher.sh`) with `KCM_LAUNCHER_CMD=konsole` and a fake lock pointing at the konsole PID.
4. `kwin-mcp dbus_call` on `/KWin org.kde.KWin.queryWindowInfo` — confirm the active window is now the konsole you launched (not a new second instance).
5. `kwin-mcp session_stop`.

If the sandbox session shows the right active window after step 4, the same script will work on the host desktop — the KWin DBus API is identical.

## Waybar Module Styling Notes (Plasma 6 + Catppuccin)

These are the gotchas hit when redoing compact waybar modules (e.g. hydrapotion) on this exact stack.

### `@keyframes` multi-selector syntax is rejected

The waybar CSS parser (gtk-css-parser based) does NOT support the standard `0%, 100% { ... }` form inside `@keyframes`. It errors with `Expected closing bracket after keyframes block`. Always write each percentage as its own rule:

```css
/* WRONG — waybar refuses to parse this */
@keyframes pulse {
    0%, 100% { text-shadow: 0 0 4px rgba(255,255,255,0.4); }
    50%      { text-shadow: 0 0 10px rgba(255,255,255,0.8); }
}

/* RIGHT */
@keyframes pulse {
    0%   { text-shadow: 0 0 4px  rgba(255,255,255,0.4); }
    50%  { text-shadow: 0 0 10px rgba(255,255,255,0.8); }
    100% { text-shadow: 0 0 4px  rgba(255,255,255,0.4); }
}
```

### Compact feedback pattern: 1 dynamic Nerd Font glyph + state-CSS + rich tooltip

For waybar modules that need visual progress (hydration, battery, CPU, brightness, custom trackers) without the 10-18-col footprint of a `▓▓▓░░░` bar:

1. **Module script (`return-type: json`)** emits `<glyph> NN%` plus a multi-line `tooltip`. The script picks the glyph from a bucket:
   ```bash
   # Example: nf-md-battery-* (U+F0079..F0083) for a hydration tracker
   case $((PCT/10)) in
       0)  GLYPH="󰁹" ;;  # outline
       1)  GLYPH="󰁺" ;;
       ...
       10) GLYPH="󰂃" ;;  # full
   esac
   ```
2. **CSS** has 3 classes that the script picks from (e.g. by `PCT >= 100` / `>= 80`):
   ```css
   #custom-mything        { color: @blue;   transition: color 0.4s ease; }
   #custom-mything.good   { color: @yellow; text-shadow: 0 0 4px rgba(249,226,175,0.45); }
   #custom-mything.done   { color: @green;  animation: mtPulse 1.6s ease-in-out infinite; }
   ```
3. **Tooltip** (Pango markup, `\\n` for line breaks) carries the detail the bar can't show: consumed/goal numbers, mood, a 10-segment mini bar using `▰`/`▱`.

This is the pattern that shrunk the hydrapotion module from `💧 75% ▓▓▓▓▓▓▓▓░░░` (18 cols) to `󰁺 16%` (5-6 cols) with no loss of information.

### Monitoring modules: 3-4 health states with actionable tooltips

For resource monitors (memory, disk, CPU, temperature, custom trackers) the compact pattern isn't enough — you also need at-a-glance **health feedback** (color + glow + animation at thresholds) and **actionable tooltips** that don't just dump data but suggest the next move. The tested pattern:

| State | Threshold (example: disk) | Color | Glow | Animation |
|---|---|---|---|---|
| `ok` | <70% | module's normal color | — | — |
| `warn` | 70-84% | @yellow | 4px | — |
| `high` | 85-94% | @peach | 5px | — |
| `critical` | ≥95% OR hard-floor (e.g. <2GB free) | @red | 6-12px | pulse 0.8s |

For `memory` use 3 states (ok / warn ≥75% / critical ≥90% OR <0.5GB available) because the warn→critical transition is more abrupt for RAM. Add a hard floor — `available_gb < 0.5` should be critical even on a 32GB box.

The tooltip should:
- Show used / free / total with the locale-correct human units (`13,0G` is fine for display)
- Above 85%, include a short bulleted list of `sudo` and `du` commands that actually work on the user's distro (the `devops/limpieza-espacio-disco-debian` skill has the playbook)
- Mention the click action ("Click to open baobab") so the user knows why the module is clickable

**Reusable templates:** see `references/waybar-monitoring-modules.md` for the full working `topmem.sh` and `disk.sh` (with health states, 4-state disk CSS, Pango tooltips, action lists, and the click → baobab hookup). Copy-paste ready; tested end-to-end on this stack.

### Pango tooltip escape recipe (reusable across any waybar script)

The Pango markup in the `tooltip` JSON field needs three escapes in this exact order:

```bash
sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
```

1. `s/\\/\\\\/g` — backslashes must be doubled (`\n` becomes `\\n`)
2. `s/"/\\"/g` — inner double quotes escaped
3. `:a;N;$!ba;s/\n/\\n/g` — sed idiom that joins all lines into one, then turns the embedded newlines into `\\n` so Pango renders them as line breaks in the tooltip, not as literal `\n` text

The third pattern is non-obvious — without it, multi-line tooltips show as a single concatenated line with visible `\n` characters. The `templates/waybar-compact-module.sh` template (linked below) uses this recipe.

### mawk + locale: two quiet bugs in Debian's default awk

The default `awk` on Debian 13 is `mawk 1.3.4`, which has two silent failures that produce confusing symptoms in scripts emitting JSON:

1. `mawk` ignores `LC_ALL=C` for `printf "%.1f"` decimal output — in es_VE you still get `13,4` with a comma. Workaround: pipe the field through `tr ',' '.'` (only that field, not the whole JSON), or use bash's built-in `printf` which honors `LC_ALL=C` correctly.
2. `mawk` regex `/^Mem:/` with a literal `:` in the pattern is silently dropped (matches nothing, no error). Workaround: `grep -E '^MemTotal:' /proc/meminfo | awk '{print $2}'` — the regex lives in grep, awk just does plain field extraction.

Full reproduction and workarounds in `references/mawk-locale-gotchas.md`. Detect which awk you have with `awk -W version 2>&1 | head -1`. If you control the box, `sudo apt install gawk` fixes both.

### Nerd Font glyph availability check

`fc-match -s 'JetBrains Mono:charset=0xf0083'` tells you which installed font supplies a given PUA codepoint. Use this to pick a glyph that's actually rendered (no "tofu" / missing-glyph box). On the common stack, **Iosevka Nerd Font** carries the `nf-md-*` set; the bare `JetBrains Mono` package does NOT.

**Reusable template:** see `templates/waybar-compact-module.sh` (next to this SKILL.md) for a copy-paste-ready script with the full pattern (glyph table, bucket selection, class thresholds, mini bar, Pango tooltip) and inline CSS to paste alongside it.

## Alternatives (when kwin-mcp is overkill)

| Tool | Lang | Install | Notes |
|---|---|---|---|
| **`kdotool`** (jinliu/kdotool) | Rust | `cargo install kdotool` or pre-built bin | `xdotool`-like CLI. `kdotool search --name "..."` + `kdotool windowactivate <wid>`. Works on KDE 5 + 6. |
| **`ww`** (academo/ww-run-raise) | bash | just download | Raise-or-launch by class or caption. Generates the KWin script on the fly like the patterns above. |
| **`jumpkwapp`** (codeberg jasalt) | Python 3 | `sudo apt install python3-gi python3-dbus; cp jumpkwapp /usr/local/bin` | Raise-or-launch with desktop filter, toggle mode, current-desktop filter. |
| **`wmctrl`** | C | `apt install wmctrl` | **X11 only** — does NOT see native Wayland windows. Useful only when the target is XWayland. |
| **`xdotool`** | C | `apt install xdotool` | **X11 only.** Don't waste time writing a Wayland-compatible script around it. |

For a single, well-tested raise-or-launch, `ww` is the smallest dependency. For agent-driven automation, `kwin-mcp` is the right level of abstraction.

## Common Pitfalls

0. **AT-SPI2 en sesiones aisladas con kwin-mcp v0.7.0 (upstream).** El wrapper script tiene hardcoded `/usr/lib/at-spi-bus-launcher` pero Debian lo instala en `/usr/libexec/`. Además no inicia `at-spi2-registryd`. **Fix:** instalar desde el fork `MoriNo23/kwin-mcp` que incluye el parche (resuelve rutas desde D-Bus service files, inicia registryd sin `--use-gnome-session`, y habilita `IsEnabled=true`). Ver `session.py` en `~/.local/share/uv/tools/kwin-mcp/lib/python3.13/site-packages/kwin_mcp/session.py`.

0b. **AT-SPI2 en sesiones live (session_connect).** El host puede tener AT-SPI2 roto desde boot (dbus-daemon vivo pero sin socket). `session_connect` ahora detecta esto, mata procesos stale, y reinicia limpiamente con `ATSPI_DBUS_IMPLEMENTATION=dbus-daemon`. Las apps existentes del desktop NO se re-registran — necesitan restart. Apps nuevas via `launch_app` sí se registran.

1. **Using `xdotool` on a Wayland-only session.** The script silently no-ops (`xdotool` is not installed) or returns nothing because the window is Wayland-native. Check `which xdotool` first; if it's missing, switch to KWin DBus or `kwin-mcp`.

2. **Calling `org.kde.kwin.Scripting.start()` for a named script.** That method runs the *last loaded anonymous* script, not the one with your pluginName. Use `/Scripting/Script${SLOT} org.kde.kwin.Script.run` with the slot number returned by `loadScript`.

3. **Forgetting that KWin rotates script slots.** In KWin 6, only slots 0-3 are kept. A new `loadScript` reuses the oldest slot. Always capture the slot number from the `loadScript` return value — don't assume it's 0, 1, 2, or 3.

4. **Trying to debug with `journalctl --user`.** KWin's `print()` output goes to **system** journal, not user, and is tagged `_COMM=kwin_wayland` (the inner process, not `kwin_wayland_wrapper`). If `journalctl _COMM=kwin_wayland` returns nothing, your script isn't running — the `loadScript` return value is fine but `run()` was never invoked, or the script crashed on parse.

5. **PIDs being reused.** Don't rely on the PID lockfile forever. Add the cleanup watcher in Pattern A, and treat the lockfile as a 5-30s hint, not a long-lived claim. For apps like `systemsettings` (which doesn't fork per window), match by `resourceClass`/`desktopFile` instead.

6. **Launching the KCM app to "test" the raise.** You'll get spurious results: the new window changes focus, the active window changes, and your "raise" test may pass for the wrong reason. Use `probe.js` to list existing windows and verify the raise by inspecting `workspace.activeWindow` before/after.

7. **Failing to call `unloadScript`.** A leaked named script keeps running and holds a slot. After a few clicks your slot table is full and `loadScript` returns -1. Always pair `loadScript`/`run`/`stop` with `unloadScript` in a `trap` or a `set -e` chain.

8. **Putting the `qdbus6` command in `on-click` instead of a wrapper script.** Long compound shell commands in waybar's JSON break on quoting (waybar does not run your command in a shell, it `exec`s it). Always wrap in a `chmod +x`'d script.

9. **Forgetting `kwin-mcp` needs the `mcp` Python package on the host.** The `kwin-mcp` binary itself works, but if Hermes' native MCP client can't import `mcp`, it silently skips MCP discovery. Run `pip show mcp` to confirm.

10. **The `session_start` MCP tool vs. driving the host desktop.** `session_start` creates a sandboxed `kwin_wayland --virtual`. It does NOT see the user's real windows. To automate the host desktop (e.g. the user's actual kcmshell6 window), use `session_connect` explicitly, after confirming with the user.

11. **Testing your bash script from the Hermes terminal sandbox — `&` and `nohup`/`disown` are blocked in foreground `bash -c`.** When you run `bash -c 'sleep 60 & exit 0'` from the terminal tool, the sandbox returns `-15` (SIGTERM) or the command times out. The same is true for `nohup ... &` and `( while ...; do ...; done ) & disown` patterns inside the foreground command. Workarounds: (a) write the logic to a file and `bash script.sh` — the sandbox only inspects the *outer* command; (b) for verifying logic, run with a quick mock that exits immediately (no `sleep`) and check the lockfile state after; (c) for full end-to-end, defer to `kwin-mcp` and validate the KWin DBus pattern in a virtual session.

12. **Background watcher in the launcher script hangs the caller.** The pattern `( while kill -0 "$KCM_PID" 2>/dev/null; do sleep 5; done; rm -f "$LOCK" ) & disown` is fine when invoked by waybar (waybar doesn't have the Hermes sandbox) but is fragile and unnecessary. Use **lazy cleanup** instead: check `kill -0 "$PID"` at the top of the next invocation; if dead, `rm -f "$LOCK"` and fall through to launch. See Pattern A below.

13. **`xdotool` may appear installed after `apt install` of a related package.** In a session where you verified `which xdotool` returned nothing, do NOT re-verify it later in the same session — `apt install wmctrl` or similar can pull it in transitively. If a script "doesn't need xdotool" should not depend on it, write the script without that dep from the start (the KWin DBus path is the right answer regardless).

14. **Empty PID in `kill -0 ""` can hang a subshell.** Always guard: `[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null`. The `2>/dev/null` is not enough if the shell blocks on a `kill` syscall that returns ESRCH weirdly under set -e.

15. **Pango tooltip rendered as single line with visible `\n`.** The `tooltip` JSON field carries Pango markup. The `\\n` (literal backslash-n) becomes a line break in Pango. If you forget the `s/\\n/\\\\n/g` step in your sed pipeline, waybar shows `\n` literally in the tooltip and the multi-line layout collapses. Use the full 3-step recipe in the "Pango tooltip escape" subsection above — it handles backslashes, quotes, and newlines in the right order.

16. **mawk's `printf %.1f` ignores `LC_ALL=C` on Debian 13.** A `LC_ALL=C awk 'BEGIN{printf "%.1f", 1.5}'` returns `1,5` (comma) not `1.5`, breaking strict JSON. Workaround: `awk '...' | tr ',' '.'` on the numeric field only, or use bash `printf`. Don't assume `LC_ALL=C` alone will fix it. See `references/mawk-locale-gotchas.md`.

17. **mawk regex with literal `:` silently fails.** `awk '/^Mem:/ {print $2}' /proc/meminfo` returns nothing on Debian 13's mawk 1.3.4. No error, just empty output. The `:^` combination is the trigger. Workaround: `grep -E '^MemTotal:' | awk '{print $2}'`. See the same reference.

18. **Disk monitor that only watches `/` misses `/home` filling up.** The common gotcha is a script that only handles one mount — the user runs out of space on `/home` (which is often the bigger partition on multi-mount setups) and the bar shows a green disk module. Always monitor at least `/` and `/home` separately, with the same health-state CSS. The "monitoring modules" pattern in this skill shows a `disk.sh` that takes any mount point as `$1`.

## Verification Checklist

- [ ] `which kwin-mcp` and `pip show mcp` both return non-empty.
- [ ] `~/.hermes/config.yaml` has `mcp_servers.kwin-mcp.command: kwin-mcp` (or `hermes config show mcp_servers` lists it).
- [ ] After Hermes restart, `mcp_kwin_mcp_session_start` appears in the tool list.
- [ ] `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"x","version":"0"}}}' | kwin-mcp` returns a valid initialize response.
- [ ] For raise-or-launch scripts, click the waybar module once — the KCM opens. Click again — the **same** window comes to the front, no new window appears. `pgrep -af kcmshell6` shows exactly one instance.
- [ ] After 5+ clicks in a row, `kwin-mcp_session_start` (or your probe.js) shows only one `kcmshell6` window.
- [ ] Stale-lockfile recovery: write a fake `999999` PID into the lockfile; next click cleans it and relaunches. Verify with `pgrep -af kcm-` (mock) or `pgrep -af kcmshell6` (real).
- [ ] Headless raise validation: `BEFORE=$(qdbus6 ... queryWindowInfo | grep caption)`, run the script, `AFTER=$(qdbus6 ... queryWindowInfo | grep caption)`, compare — should match when the active window was already the target.
- [ ] *(Optional, if print() journal works on your system)* `journalctl _COMM=kwin_wayland -o cat -S "5 minutes ago" | grep raise_` shows one `raise_<kcm>` invocation per click, with no errors.

## One-Shot Recipes

### Quick "raise or launch" kcmshell6 module (pure bash, copy-paste)

```bash
mkdir -p ~/.config/waybar/scripts
cat > ~/.config/waybar/scripts/kcm-launcher.sh <<'BASH'
#!/bin/bash
# See skill: kwin-desktop-automation
# Lazy cleanup of stale lockfile (no background watcher) — see pitfalls 11+12.
set -euo pipefail
KCM="$1"
LOCK="/tmp/kcm-${KCM}.pid"

# Stale lockfile recovery (no GUI app launched)
if [ -f "$LOCK" ]; then
    PID=$(cat "$LOCK" 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        # Try to raise the existing KWin window
        SCRIPT_FILE=$(mktemp --suffix=.js)
        cat > "$SCRIPT_FILE" <<EOF
var target = ${PID};
for (var i = 0; i < workspace.windowList().length; i++) {
    var w = workspace.windowList()[i];
    if (w.pid === target) {
        if (w.minimized) w.minimized = false;
        workspace.activeWindow = w; workspace.raiseWindow(w); break;
    }
}
EOF
        SLOT=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
                "$SCRIPT_FILE" "raise_${KCM}" 2>/dev/null | awk 'END{print $NF}')
        if [ -n "$SLOT" ] && [ "$SLOT" -ge 0 ] 2>/dev/null; then
            qdbus6 org.kde.KWin "/Scripting/Script${SLOT}" org.kde.kwin.Script.run >/dev/null 2>&1 || true
        fi
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript \
                "raise_${KCM}" >/dev/null 2>&1 || true
        rm -f "$SCRIPT_FILE"
        exit 0
    fi
    rm -f "$LOCK"   # stale
fi

# No alive instance — launch
kcmshell6 "$KCM" &
echo $! > "$LOCK"
BASH
chmod +x ~/.config/waybar/scripts/kcm-launcher.sh
```

### Verify a raise worked, headlessly (no GUI app launched)

```bash
# Capture active window caption before
BEFORE=$(qdbus6 org.kde.KWin /KWin org.kde.KWin.queryWindowInfo 2>/dev/null \
         | grep '^caption' | head -1)

# Trigger your raise script (still no GUI — it reads the lockfile, no-ops if stale)
~/.config/waybar/scripts/kcm-launcher.sh kcm_pulseaudio

# Capture active window after
AFTER=$(qdbus6 org.kde.KWin /KWin org.kde.KWin.queryWindowInfo 2>/dev/null \
        | grep '^caption' | head -1)

[ "$BEFORE" = "$AFTER" ] && echo "raise succeeded (active window unchanged: $BEFORE)" \
                       || echo "raise detected change: '$BEFORE' → '$AFTER'"
```

### Inspect an existing KCM window's state from CLI

```bash
# Find the kcmshell6 window's UUID via probe.js, then queryWindowInfo
qdbus6 org.kde.KWin /KWin org.kde.KWin.queryWindowInfo | grep -E 'caption|resourceClass|minimized'
```

### End-to-end validation in an isolated virtual session (no host impact)

```text
# 1. Start sandbox
mcp_kwin_mcp_session_start(app_command="konsole -e sleep 300")

# 2. Confirm the konsole is the active window
mcp_kwin_mcp_dbus_call(service="org.kde.KWin", path="/KWin",
                      interface="org.kde.KWin", method="queryWindowInfo")
# → caption should contain "konsole"

# 3. Run your raise script with the konsole's PID as the lockfile
echo <konsole_pid> > /tmp/kcm-test.pid
KCM_LAUNCHER_CMD=/bin/true bash kcm-launcher.sh test

# 4. Re-query — caption should still be the konsole (raise, not re-spawn)
mcp_kwin_mcp_dbus_call(..., method="queryWindowInfo")

# 5. Cleanup
mcp_kwin_mcp_session_stop()
```
