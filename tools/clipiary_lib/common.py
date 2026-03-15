from __future__ import annotations

import json
import os
import shlex
import subprocess
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any


class ToolError(RuntimeError):
    """Raised for user-facing command failures."""


class Runner:
    def __init__(self, dry_run: bool = False) -> None:
        self.dry_run = dry_run

    def echo(self, cmd: list[str], cwd: Path | None = None) -> None:
        rendered = " ".join(shlex.quote(part) for part in cmd)
        if cwd is not None:
            print(f"[cwd={cwd}] {rendered}")
        else:
            print(rendered)

    def run(
        self,
        cmd: list[str],
        *,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
        read_only: bool = False,
        capture_output: bool = False,
        text: bool = True,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        self.echo(cmd, cwd)
        if self.dry_run and not read_only:
            return subprocess.CompletedProcess(
                cmd,
                0,
                stdout="" if capture_output else None,
                stderr="" if capture_output else None,
            )

        try:
            return subprocess.run(
                cmd,
                check=check,
                cwd=cwd,
                env=env,
                capture_output=capture_output,
                text=text,
            )
        except subprocess.CalledProcessError as exc:
            if exc.stdout:
                print(exc.stdout, end="")
            if exc.stderr:
                print(exc.stderr, end="", file=os.sys.stderr)
            raise ToolError(f"Command failed with exit code {exc.returncode}: {cmd[0]}") from exc

    def read(
        self,
        cmd: list[str],
        *,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
    ) -> str:
        result = self.run(cmd, cwd=cwd, env=env, read_only=True, capture_output=True)
        return result.stdout.strip()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def dist_dir(root: Path) -> Path:
    return root / "dist"


def resolve_path(root: Path, raw_path: str | None) -> Path | None:
    if raw_path is None:
        return None
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return root / path


def ensure_dir(path: Path, *, dry_run: bool) -> None:
    if dry_run:
        print(f"mkdir -p {path}")
        return
    path.mkdir(parents=True, exist_ok=True)


def remove_path(path: Path, *, dry_run: bool) -> None:
    if not path.exists():
        return
    print(f"rm -rf {path}")
    if dry_run:
        return
    if path.is_dir():
        for child in sorted(path.iterdir(), reverse=True):
            remove_path(child, dry_run=False)
        path.rmdir()
    else:
        path.unlink()


def write_text(path: Path, content: str, *, dry_run: bool) -> None:
    print(f"write {path}")
    if dry_run:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_json(path: Path, payload: Any, *, dry_run: bool) -> None:
    write_text(path, json.dumps(normalize_payload(payload), indent=2) + "\n", dry_run=dry_run)


def normalize_payload(payload: Any) -> Any:
    if is_dataclass(payload):
        return normalize_payload(asdict(payload))
    if isinstance(payload, Path):
        return str(payload)
    if isinstance(payload, dict):
        return {key: normalize_payload(value) for key, value in payload.items()}
    if isinstance(payload, list):
        return [normalize_payload(value) for value in payload]
    return payload


def print_json(payload: Any) -> None:
    print(json.dumps(normalize_payload(payload), indent=2))


def base_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    if extra:
        env.update(extra)
    return env
