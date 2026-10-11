#!/usr/bin/env python3
"""Native macOS click/focus tests using production views and isolated, offline fixtures."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

APP = "SkillboxUsageUIHarness"
CHECKS = []


def apple(script):
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def ui(script):
    return apple(f'tell application "System Events" to tell process "{APP}"\n{script}\nend tell')


def wait_for(check, message, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                return result
        except RuntimeError:
            pass
        time.sleep(0.1)
    raise AssertionError(message)


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    CHECKS.append(message)
    print("PASS:", message, flush=True)


def element(identifier, window='window 1'):
    # Resolve stable production accessibility IDs rather than coordinates or button order.
    if identifier in ["usage-editor-cancel", "usage-editor-save"]:
        candidates = f"buttons of group 1 of {window}"
    elif identifier.startswith("usage-editor-"):
        candidates = f"text fields of scroll area 1 of group 1 of {window}"
    else:
        candidates = f"buttons of scroll area 1 of group 1 of {window}"
    return f'''set targetElement to missing value
set allElements to {candidates}
repeat with candidate in allElements
    try
        if value of attribute "AXIdentifier" of candidate is "{identifier}" then
            set targetElement to candidate
            exit repeat
        end if
    end try
end repeat
if targetElement is missing value then error "Missing accessibility element: {identifier}"
'''


def click(identifier, window='window 1'):
    # Actual mouse events expose focus/dismissal bugs that AXPress alone can miss.
    coordinates = ui(element(identifier, window) + '''set p to position of targetElement
set s to size of targetElement
return {(item 1 of p) + (item 1 of s) / 2, (item 2 of p) + (item 2 of s) / 2}''')
    native_click(coordinates)


def native_click(coordinates):
    x, y = coordinates.split(", ")
    subprocess.run([str(Path(sys.argv[1]).resolve().parent / "native-ui-click"), x, y], check=True)


def open_usage():
    # AXPress can open a status item even when a menu bar organizer has hidden its icon.
    ui('click menu bar item 1 of menu bar 2')
    wait_for(lambda: int(ui('count windows')) > 0, "Usage popover did not open")


def percent():
    return ui('get value of first static text of scroll area 1 of group 1 of window 1 whose value ends with "% used"')


def screenshot(path, window='window 1'):
    state = json.loads((path.parent / "window-state.json").read_text())
    candidates = [w for w in state["windows"] if w["visible"] == "true" and 0 < int(w["number"]) < 2**32]
    if window != "window 1":
        candidates = [w for w in candidates if w["title"] == "Usage snapshot"]
    if not candidates:
        raise RuntimeError("No visible harness window to capture")
    subprocess.run(["screencapture", "-x", "-l" + candidates[0]["number"], str(path)], check=True)


def main():
    app = Path(sys.argv[1]).resolve()
    output = app.parent
    failure = None
    subprocess.run(["pkill", "-x", APP], check=False)
    app_log = (output / "app.log").open("w")
    state_path = output / "window-state.json"
    state_path.unlink(missing_ok=True)
    environment = dict(os.environ, SKILLBOX_UI_HARNESS_STATE=str(state_path))
    process = subprocess.Popen([str(app / "Contents/MacOS" / APP), "-ApplePersistenceIgnoreState", "YES"], stdout=app_log, stderr=app_log, env=environment)
    try:
        wait_for(lambda: apple(f'tell application "System Events" to exists process "{APP}"') == "true", "Harness did not launch")
        open_usage()
        wait_for(lambda: "codex@example.com" in ui('get entire contents of window 1'), "Fixture usage did not load")
        content = ui('get entire contents of window 1')
        if "SuperGrok" not in content:
            print("Unexpected initial window:", content, flush=True)
        check("Weekly SuperGrok limit" not in content and "SuperGrok" in content, "Plan and weekly quota labels are separate")
        check("Dashboard" not in content, "Usage contains no dashboard links")
        # Scheduling is covered with a controlled clock in ProviderUsageRefreshTests.
        # The click harness focuses on editor lifetime and actual input delivery.
        ui(element("usage-codex-edit") + "click targetElement")
        window = 'window "Usage snapshot"'
        wait_for(lambda: ui(f'exists {window}') == "true", "Usage editor did not open")
        wait_for(lambda: ui('get name of (value of attribute "AXFocusedWindow")') == "Usage snapshot", "Editor did not become the focused window", timeout=3)
        check(True, "Editor activates Skillbox")
        for identifier in ["usage-editor-email", "usage-editor-plan", "usage-editor-price", "usage-editor-renewal"]:
            click(identifier, window)
            check(ui(element(identifier, window) + 'get value of attribute "AXFocused" of targetElement') == "true", f"{identifier} receives mouse focus")
            ui('keystroke "a" using command down')
            ui('keystroke "focus-test"')
            check(ui(f'exists {window}') == "true", f"Mouse click and typing keep {identifier} open")
            check(ui(element(identifier, window) + 'get value of targetElement') == "focus-test", f"{identifier} accepts keyboard input")
        ui(f'click checkbox 1 of scroll area 1 of group 1 of {window}')
        check(ui(f'exists {window}') == "true", "Reset checkbox keeps editor open")
        # Open a real native picker menu, the other common popover-focus failure.
        ui(f'click pop up button 1 of scroll area 1 of group 1 of {window}')
        ui('key code 53')
        check(ui(f'exists {window}') == "true", "Native picker menu keeps editor open")
        screenshot(output / "usage-editor.png", window)
        click("usage-editor-cancel", window)
        wait_for(lambda: ui(f'exists {window}') == "false", "Cancel did not close the editor")
        check(True, "Cancel closes only the editor")
        open_usage()
        click("usage-codex-edit")
        wait_for(lambda: ui(f'exists {window}') == "true", "Could not reopen editor")
        check(ui(element("usage-editor-email", window) + 'get value of targetElement') == "codex@example.com", "Cancel preserves the original snapshot")
        click("usage-editor-save", window)
        wait_for(lambda: ui(f'exists {window}') == "false", "Save did not close the editor")
        open_usage()
        check("Manual" in ui('get entire contents of window 1'), "Save persists a manual snapshot")
        before = percent()
        time.sleep(2.5)
        check(percent() == before, "Periodic refresh preserves manual snapshots")
        click("usage-codex-refresh")
        wait_for(lambda: percent() != before, "Explicit Refresh did not replace the manual snapshot")
        check(True, "Explicit Refresh resumes live usage")
    except Exception as error:
        failure = str(error)
        print("FAIL:", failure, flush=True)
        if state_path.exists():
            print("Native window state:", state_path.read_text(), flush=True)
        try:
            screenshot(output / "failure.png")
        except Exception:
            pass
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        app_log.close()
        (output / "results.json").write_text(json.dumps({"passed": CHECKS, "failure": failure}, indent=2))
    if failure:
        raise SystemExit(1)
    print(f"Native Usage UI harness passed {len(CHECKS)} checks. Artifacts: {output}")


if __name__ == "__main__":
    main()
