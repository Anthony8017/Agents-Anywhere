"""Run each simulator case serially; compare Release builds without profiling overhead."""
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(os.environ.get("AA_PERF_OUTPUT", "/tmp/aa-static-scroll-results"))
ROOT.mkdir(parents=True, exist_ok=True)
DEVICE = os.environ.get("AA_PERF_DEVICE", "booted")
ENV = {**os.environ, "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer")}
BUNDLE = "com.agentsanywhere.scrollprobe"


def sim(*args, extra=None):
    return subprocess.check_output(["xcrun", "simctl", *args], env={**ENV, **(extra or {})}, text=True).strip()


def main():
    container = Path(sim("get_app_container", DEVICE, BUNDLE, "data"))
    log = container / "Documents/static-scroll.jsonl"
    cases = [("plain", "prose", "on"), ("markdown", "prose", "on"), ("markdown", "prose", "off"),
             ("markdown", "mixed", "on"), ("markdown", "mixed", "off"),
             ("groups", "mixed", "on"), ("groups", "patches", "on"),
             ("timeline", "mixed", "on"), ("timeline", "mixed", "off")]
    if os.environ.get("AA_MATRIX_CASES"):
        cases = json.loads(os.environ["AA_MATRIX_CASES"])
    for case in cases:
        mode, scenario, selection = case[:3]
        equality = case[3] if len(case) > 3 else "original"
        label = case[4] if len(case) > 4 else ""
        extra = case[5] if len(case) > 5 else {}
        previous_size = log.stat().st_size if log.exists() else 0
        name = f"{mode}-{scenario}-{selection}" + (f"-{equality}-{label}" if len(case) > 3 else "")
        launch = sim("launch", "--terminate-running-process", DEVICE, BUNDLE, extra={
            "SIMCTL_CHILD_AA_PERF_COUNTERS": "1", "SIMCTL_CHILD_AA_PERF_MODE": mode,
            "SIMCTL_CHILD_AA_PERF_SCENARIO": scenario, "SIMCTL_CHILD_AA_PERF_SELECTION": selection,
            "SIMCTL_CHILD_AA_PERF_LAYOUT_EQUALITY": equality, **extra})
        print(f"START {name}: {launch}", flush=True)
        deadline = time.monotonic() + 65
        text = ""
        while time.monotonic() < deadline:
            if log.exists():
                with log.open("rb") as file:
                    file.seek(previous_size)
                    text = file.read().decode()
                if '"event":"finished"' in text or '"event":"error"' in text:
                    break
            time.sleep(0.5)
        (ROOT / f"{name}.jsonl").write_text(text)
        rows = [json.loads(line) for line in text.splitlines() if line.startswith("{")]
        print(json.dumps({"case": name, "records": rows}, ensure_ascii=False), flush=True)
        if not any(row.get("event") == "finished" for row in rows):
            raise RuntimeError(f"Incomplete case: {name}")


if __name__ == "__main__":
    main()
