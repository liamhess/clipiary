from __future__ import annotations

import argparse
import os
from pathlib import Path

from .build import build_app
from .cask import generate_cask
from .common import Runner, ToolError, print_json, repo_root, resolve_path
from .dev import dev_loop
from .env import load_env
from .icon import build_icon
from .publish import import_signing_certificate, publish_release, start_release, verify_tagged_commit_on_main
from .release import build_release


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="clipiary")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    build_parser.add_argument("--json", action="store_true")
    build_parser.add_argument("--dry-run", action="store_true")

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    run_parser.add_argument("--dry-run", action="store_true")

    dev_parser = subparsers.add_parser("dev")
    dev_parser.add_argument("--watch-interval", type=float, default=float(os.environ.get("WATCH_INTERVAL", "1")))
    dev_parser.add_argument("--dry-run", action="store_true")

    release_parser = subparsers.add_parser("release")
    release_parser.add_argument("--version", required=True)
    release_parser.add_argument("--build-number", default=None)
    release_parser.add_argument("--metadata-out", default=None)
    release_parser.add_argument("--json", action="store_true")
    release_parser.add_argument("--dry-run", action="store_true")

    publish_parser = subparsers.add_parser("publish")
    publish_parser.add_argument("--metadata", required=True)
    publish_parser.add_argument("--dry-run", action="store_true")

    ci_release_parser = subparsers.add_parser("ci-release")
    ci_release_parser.add_argument("--version", required=True)
    ci_release_parser.add_argument("--build-number", default=os.environ.get("GITHUB_RUN_NUMBER", "1"))
    ci_release_parser.add_argument("--metadata-out", default="dist/release.json")
    ci_release_parser.add_argument("--json", action="store_true")
    ci_release_parser.add_argument("--dry-run", action="store_true")

    start_release_parser = subparsers.add_parser("start-release")
    start_release_parser.add_argument("bump", choices=("patch", "minor", "major"))
    start_release_parser.add_argument("--dry-run", action="store_true")

    icon_parser = subparsers.add_parser("icon")
    icon_parser.add_argument("--source", default=None)
    icon_parser.add_argument("--dry-run", action="store_true")

    cask_parser = subparsers.add_parser("cask")
    cask_parser.add_argument("--version", required=True)
    cask_parser.add_argument("--sha256", required=True)
    cask_parser.add_argument("--output", default=None)
    cask_parser.add_argument("--dry-run", action="store_true")

    return parser


def load_metadata_file(path: Path) -> dict[str, str]:
    import json

    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    root = repo_root()
    env = load_env(root)
    runner = Runner(dry_run=getattr(args, "dry_run", False))

    try:
        if args.command == "build":
            result = build_app(root, env, runner, configuration=args.configuration)
            if args.json:
                print_json(result)
            else:
                print(result.app_bundle)
            return 0

        if args.command == "run":
            result = build_app(root, env, runner, configuration=args.configuration)
            runner.run(["open", str(result.app_bundle)])
            return 0

        if args.command == "dev":
            dev_loop(root, env, runner, args.watch_interval)
            return 0

        if args.command == "release":
            build_number = args.build_number or env.get("CLIPIARY_BUILD_NUMBER", "1")
            metadata_out = resolve_path(root, args.metadata_out)
            metadata = build_release(
                root,
                env,
                runner,
                version=args.version,
                build_number=build_number,
                metadata_out=metadata_out,
            )
            if args.json:
                print_json(metadata)
            else:
                print(metadata.archive_path)
            return 0

        if args.command == "publish":
            payload = load_metadata_file(resolve_path(root, args.metadata))
            from .release import ReleaseMetadata

            metadata = ReleaseMetadata(
                version=payload["version"],
                build_number=payload["build_number"],
                app_bundle=Path(payload["app_bundle"]),
                archive_path=Path(payload["archive_path"]),
                sha256=payload["sha256"],
                sha256_path=Path(payload["sha256_path"]),
                cask_path=Path(payload["cask_path"]),
                release_notes_path=Path(payload["release_notes_path"]),
                release_repo=payload["release_repo"],
                cask_token=payload["cask_token"],
            )
            publish_release(root, env, runner, metadata)
            return 0

        if args.command == "ci-release":
            import_signing_certificate(root, env, runner)
            verify_tagged_commit_on_main(root, runner, env.get("GITHUB_SHA"))
            metadata = build_release(
                root,
                env,
                runner,
                version=args.version,
                build_number=args.build_number,
                metadata_out=resolve_path(root, args.metadata_out),
            )
            publish_release(root, env, runner, metadata)
            if args.json:
                print_json(metadata)
            return 0

        if args.command == "start-release":
            result = start_release(root, runner, args.bump)
            action = "Would create and push tag" if runner.dry_run else "Created and pushed tag"
            print(f"{action}: {result['tag']}")
            if result["actions_url"]:
                print(f"GitHub Actions: {result['actions_url']}")
            if result["release_url"]:
                print(f"Release page: {result['release_url']}")
            return 0

        if args.command == "icon":
            print(build_icon(root, runner, args.source))
            return 0

        if args.command == "cask":
            output = resolve_path(root, args.output)
            content = generate_cask(env, args.version, args.sha256, output, dry_run=runner.dry_run)
            if output is None:
                print(content, end="")
            return 0
    except ToolError as exc:
        print(str(exc), file=os.sys.stderr)
        return 1

    parser.error(f"Unhandled command: {args.command}")
    return 2
