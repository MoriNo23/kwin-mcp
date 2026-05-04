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

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC_DIR = PROJECT_ROOT / "src"
if SRC_DIR.exists():
    sys.path.insert(0, str(SRC_DIR))

from kwin_mcp.core import AutomationEngine  # noqa: E402

EVIDENCE = pathlib.Path(os.environ.get("EVIDENCE_DIR", ".sisyphus/evidence"))


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


def run_smoke(engine: AutomationEngine, summary: dict[str, Any]) -> None:
    """Run the container smoke scenario."""
    result = engine.session_start(screen_width=1920, screen_height=1080)
    add_scenario(summary, "session_start", str(result)[:200])

    result = engine.launch_app("qml6 /opt/docker/smoke_app.qml")
    add_scenario(summary, "launch_app", str(result)[:200])

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

    initial = copy_to_evidence(parse_screenshot_path(engine.screenshot()), "initial.png")
    initial_size = initial.stat().st_size
    assert initial_size > 1024, f"initial screenshot suspiciously small: {initial_size} bytes"
    initial_sha = sha256(initial)
    add_scenario(summary, "screenshot_initial", f"size={initial_size}", sha256=initial_sha)

    engine.mouse_click(x=bx, y=by)
    add_scenario(summary, "mouse_click_ping", f"mouse at ({bx},{by})")

    time.sleep(0.3)

    post_click = copy_to_evidence(parse_screenshot_path(engine.screenshot()), "post-click.png")
    post_click_sha = sha256(post_click)
    assert post_click_sha != initial_sha, "post-click screenshot identical to initial"
    add_scenario(
        summary,
        "screenshot_post_click",
        f"size={post_click.stat().st_size}",
        sha256=post_click_sha,
    )

    find_entry = engine.find_ui_elements(query="Smoke entry")
    ex, ey = find_center(find_entry, "Smoke entry")
    add_scenario(summary, "find_smoke_entry", f"center=({ex},{ey})")

    engine.mouse_click(x=ex, y=ey)
    add_scenario(summary, "focus_entry_field", f"mouse at ({ex},{ey})")

    time.sleep(0.2)

    engine.keyboard_type("hello")
    add_scenario(summary, "keyboard_type", "typed text")

    time.sleep(0.3)

    post_typing = copy_to_evidence(parse_screenshot_path(engine.screenshot()), "post-typing.png")
    post_typing_sha = sha256(post_typing)
    assert post_typing_sha != post_click_sha, "post-typing screenshot identical to post-click"
    add_scenario(
        summary,
        "screenshot_post_typing",
        f"size={post_typing.stat().st_size}",
        sha256=post_typing_sha,
    )

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
