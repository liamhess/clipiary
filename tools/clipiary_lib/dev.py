from __future__ import annotations

import hashlib
import os
import signal
import subprocess
import time
from pathlib import Path

from .build import build_app
from .common import Runner


def file_snapshot(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for base_path in paths:
        if base_path.is_file():
            candidates = [base_path]
        elif base_path.exists():
            candidates = [path for path in sorted(base_path.rglob("*")) if path.is_file()]
        else:
            continue
        for path in candidates:
            stat = path.stat()
            digest.update(str(path).encode("utf-8"))
            digest.update(str(stat.st_mtime_ns).encode("utf-8"))
            digest.update(str(stat.st_size).encode("utf-8"))
    return digest.hexdigest()


def dev_loop(root: Path, env: dict[str, str], runner: Runner, watch_interval: float) -> None:
    app_process: subprocess.Popen[str] | None = None
    watch_paths = [root / "Package.swift", root / "Sources", root / "tools"]
    app_name = env.get("CLIPIARY_APP_NAME", "Clipiary")
    log_path = Path("/tmp/clipiary-dev.log")

    def build_and_restart() -> subprocess.Popen[str] | None:
        nonlocal app_process
        result = build_app(root, env, runner, configuration="debug")
        executable = result.executable_path
        if runner.dry_run:
            return app_process
        if app_process is not None and app_process.poll() is None:
            app_process.terminate()
            try:
                app_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                app_process.kill()
                app_process.wait(timeout=2)
        else:
            subprocess.run(["pkill", "-x", app_name], check=False, capture_output=True, text=True)
        with log_path.open("a", encoding="utf-8") as handle:
            app_process = subprocess.Popen(
                [str(executable)],
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
            )
        return app_process

    def cleanup(*_: object) -> None:
        nonlocal app_process
        if app_process is not None and app_process.poll() is None:
            app_process.terminate()
            try:
                app_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                app_process.kill()
                app_process.wait(timeout=2)
        raise SystemExit(0)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    build_and_restart()
    last_snapshot = file_snapshot(watch_paths)
    print(f"Watching for changes every {watch_interval}s")
    while True:
        time.sleep(watch_interval)
        next_snapshot = file_snapshot(watch_paths)
        if next_snapshot != last_snapshot:
            last_snapshot = next_snapshot
            build_and_restart()
