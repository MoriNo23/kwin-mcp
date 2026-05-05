#!/usr/bin/env python3
"""In-process smoke test for kwin-mcp inside the container.

Imports AutomationEngine directly. Exercises session start, qml6 app launch,
accessibility discovery, screenshots, mouse input, keyboard input, and evidence
capture.

Exit codes: 0=pass, 1=assertion failed, 10=uncaught exception.
"""

import contextlib
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import sys
import time
from typing import Any

from PIL import Image

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC_DIR = PROJECT_ROOT / "src"
if SRC_DIR.exists():
    sys.path.insert(0, str(SRC_DIR))

from kwin_mcp.core import AutomationEngine  # noqa: E402

EVIDENCE = pathlib.Path(os.environ.get("EVIDENCE_DIR", ".sisyphus/evidence"))
PAUSE_AT = os.environ.get("SMOKE_PAUSE_AT", "")
PAUSE_STEPS = (
    "launch_app",
    "screenshot_initial",
    "mouse_click_ping",
    "keyboard_type",
    "screenshot_post_typing",
)
if PAUSE_AT and PAUSE_AT not in PAUSE_STEPS:
    valid_steps = ", ".join(PAUSE_STEPS)
    print(f"Invalid SMOKE_PAUSE_AT={PAUSE_AT!r}; valid values: {valid_steps}", file=sys.stderr)
    sys.exit(2)


def sha256(p: pathlib.Path) -> str:
    """Return the SHA-256 digest of a file."""
    return hashlib.sha256(p.read_bytes()).hexdigest()


FIND_RE = re.compile(
    r'^- \[(?P<role>[^\]]+)\] "(?P<name>[^"]+)" @ '
    r"\((?P<x>\d+), (?P<y>\d+), (?P<w>\d+)x(?P<h>\d+)\)",
    re.MULTILINE,
)


def find_center(find_output: str, name: str) -> tuple[int, int]:
    """Parse find_ui_elements() text output and return center coordinates."""
    for match in FIND_RE.finditer(find_output):
        if match.group("name") == name:
            x, y, w, h = (int(match.group(key)) for key in ("x", "y", "w", "h"))
            return x + w // 2, y + h // 2
    raise AssertionError(
        f"element not found by name={name!r}\n"
        f"--- find_ui_elements output ---\n{find_output}"
    )


def _find_topleft(find_output: str, name: str) -> tuple[int, int]:
    for match in FIND_RE.finditer(find_output):
        if match.group("name") == name:
            return int(match.group("x")), int(match.group("y"))
    raise AssertionError(f"element not found: {name!r}")


def _screen_offset(png: pathlib.Path, tf_x: int, tf_y: int) -> tuple[int, int]:
    img = Image.open(png).convert("RGBA")
    iw, ih = img.size
    data: bytes = img.tobytes()
    x0, x1 = iw // 5, 4 * iw // 5
    for sy in range(ih // 4, 3 * ih // 4):
        run = 0
        run_start = 0
        for sx in range(x0, x1):
            i = (sy * iw + sx) * 4
            if data[i] == 255 and data[i + 1] == 255 and data[i + 2] == 255 and data[i + 3] == 255:
                if run == 0:
                    run_start = sx
                run += 1
                if run >= 20:
                    return run_start - tf_x, sy - tf_y
            else:
                run = 0
    return 0, 0


SCREENSHOT_RE = re.compile(r"Screenshot saved: (?P<path>\S+\.png)")


def parse_screenshot_path(out: str) -> pathlib.Path:
    """Extract the PNG path from AutomationEngine.screenshot() output."""
    match = SCREENSHOT_RE.search(out)
    assert match, f"could not parse screenshot path from: {out!r}"
    return pathlib.Path(match.group("path"))


def copy_to_evidence(src: pathlib.Path, dst_name: str) -> pathlib.Path:
    """Copy a screenshot into the evidence directory."""
    dst = EVIDENCE / "screenshots" / dst_name
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return dst


def write_a11y(name: str, content: str) -> None:
    """Write accessibility evidence text."""
    dst = EVIDENCE / "a11y" / name
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(content)


def add_scenario(summary: dict[str, Any], name: str, result: str, **extra: Any) -> None:
    """Append a scenario result to summary."""
    summary["scenarios"].append({"name": name, "result": result, **extra})


def _pause_after(step_name: str) -> None:
    """Pause after a smoke step until the continue marker appears."""
    if step_name != PAUSE_AT:
        return
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    pause_marker = EVIDENCE / f".paused-at-{step_name}"
    continue_marker = EVIDENCE / ".continue"
    pause_marker.write_text(step_name)
    print(
        f"[smoke] paused at {step_name} - touch {continue_marker} to resume",
        flush=True,
    )
    while not continue_marker.exists():
        time.sleep(0.5)
    pause_marker.unlink(missing_ok=True)
    continue_marker.unlink(missing_ok=True)
    print(f"[smoke] resumed from {step_name}", flush=True)


def run_smoke(engine: AutomationEngine, summary: dict[str, Any]) -> None:
    """Run the container smoke scenario."""
    result = engine.session_start(screen_width=1920, screen_height=1080)
    add_scenario(summary, "session_start", str(result)[:200])

    result = engine.launch_app("qml6 /opt/docker/smoke_app.qml")
    add_scenario(summary, "launch_app", str(result)[:200])
    _pause_after("launch_app")

    engine.wait_for_element(query="Ping button", timeout_ms=20000)
    add_scenario(summary, "wait_ping_button", "ok")
    engine.wait_for_element(query="Smoke entry", timeout_ms=5000)
    add_scenario(summary, "wait_smoke_entry", "ok")
    engine.wait_for_element(query="Status text", timeout_ms=5000)
    add_scenario(summary, "wait_status_text", "ok")

    tree_before = engine.accessibility_tree(max_depth=10)
    write_a11y("before.txt", tree_before)

    find_before = engine.find_ui_elements(query="Ping button")
    bx, by = find_center(find_before, "Ping button")
    add_scenario(summary, "find_ping_button", f"center=({bx},{by})")

    find_entry = engine.find_ui_elements(query="Smoke entry")
    tf_x, tf_y = _find_topleft(find_entry, "Smoke entry")
    ex, ey = find_center(find_entry, "Smoke entry")

    initial = copy_to_evidence(parse_screenshot_path(engine.screenshot()), "initial.png")
    initial_size = initial.stat().st_size
    assert initial_size > 1024, f"initial screenshot suspiciously small: {initial_size} bytes"
    initial_sha = sha256(initial)
    add_scenario(summary, "screenshot_initial", f"size={initial_size}", sha256=initial_sha)
    _pause_after("screenshot_initial")

    off_x, off_y = _screen_offset(initial, tf_x, tf_y)
    add_scenario(summary, "screen_offset", f"offset=({off_x},{off_y})")

    engine.mouse_move(x=960, y=540)
    time.sleep(0.3)
    engine.mouse_move(x=off_x + bx, y=off_y + by)
    time.sleep(0.3)
    engine.mouse_click(x=off_x + bx, y=off_y + by)
    add_scenario(summary, "mouse_click_ping", f"mouse at ({off_x + bx},{off_y + by})")
    _pause_after("mouse_click_ping")

    time.sleep(1.5)

    post_click = copy_to_evidence(parse_screenshot_path(engine.screenshot()), "post-click.png")
    post_click_sha = sha256(post_click)
    assert post_click_sha != initial_sha, "post-click screenshot identical to initial"
    add_scenario(
        summary,
        "screenshot_post_click",
        f"size={post_click.stat().st_size}",
        sha256=post_click_sha,
    )

    add_scenario(summary, "find_smoke_entry", f"center=({ex},{ey})")

    engine.mouse_click(x=off_x + ex, y=off_y + ey)
    add_scenario(summary, "focus_entry_field", f"mouse at ({off_x + ex},{off_y + ey})")

    time.sleep(0.5)

    engine.keyboard_type("hello")
    add_scenario(summary, "keyboard_type", "typed text")
    _pause_after("keyboard_type")

    time.sleep(1.5)

    post_typing = copy_to_evidence(parse_screenshot_path(engine.screenshot()), "post-typing.png")
    post_typing_sha = sha256(post_typing)
    assert post_typing_sha != post_click_sha, "post-typing screenshot identical to post-click"
    add_scenario(
        summary,
        "screenshot_post_typing",
        f"size={post_typing.stat().st_size}",
        sha256=post_typing_sha,
    )
    _pause_after("screenshot_post_typing")

    tree_after = engine.accessibility_tree(max_depth=10)
    write_a11y("after.txt", tree_after)

    assert tree_after != tree_before, "accessibility tree text did not change"
    assert len({initial_sha, post_click_sha, post_typing_sha}) == 3, (
        f"screenshots not all distinct: initial={initial_sha[:8]}, "
        f"post_click={post_click_sha[:8]}, post_typing={post_typing_sha[:8]}"
    )

    summary["screenshot_sha"] = {
        "initial": initial_sha,
        "post_click": post_click_sha,
        "post_typing": post_typing_sha,
    }


def merge_install_metadata(summary: dict[str, Any]) -> None:
    """Merge installation metadata emitted by the container entrypoint."""
    install_path = EVIDENCE / "install.json"
    if install_path.exists():
        try:
            summary["install"] = json.loads(install_path.read_text())
        except Exception as exc:
            summary["install"] = {"error": f"could not parse install.json: {exc!r}"}
    else:
        summary["install"] = {"error": "install.json missing; entrypoint did not write it"}


def main() -> None:
    """Entrypoint for direct execution in the smoke container."""
    summary: dict[str, Any] = {
        "verdict": "error",
        "started_at": datetime.datetime.now(datetime.UTC).isoformat().replace("+00:00", "Z"),
        "scenarios": [],
    }
    engine = AutomationEngine()
    try:
        run_smoke(engine, summary)
        summary["verdict"] = "pass"
    except AssertionError as exc:
        summary["verdict"] = "fail"
        summary["error"] = str(exc)
        summary["error_type"] = "assertion"
        sys.exit(1)
    except Exception as exc:
        summary["verdict"] = "error"
        summary["error"] = repr(exc)
        summary["error_type"] = type(exc).__name__
        sys.exit(10)
    finally:
        with contextlib.suppress(Exception):
            engine.session_stop()
        merge_install_metadata(summary)
        summary["tasks_passed"] = sum(
            1 for item in summary.get("scenarios", []) if "error" not in item
        )
        EVIDENCE.mkdir(parents=True, exist_ok=True)
        (EVIDENCE / "summary.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
