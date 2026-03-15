from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path

from .build import build_app
from .cask import generate_cask
from .common import Runner, ToolError, dist_dir, remove_path, resolve_path, write_json, write_text
from .env import get_env


DRY_RUN_SHA256 = "0" * 64


@dataclass
class ReleaseMetadata:
    version: str
    build_number: str
    app_bundle: Path
    archive_path: Path
    sha256: str
    sha256_path: Path
    cask_path: Path
    release_notes_path: Path
    release_repo: str
    cask_token: str


def archive_name(env: dict[str, str], version: str) -> str:
    app_name = get_env(env, "CLIPIARY_APP_NAME", "Clipiary")
    return env.get("CLIPIARY_ARCHIVE_NAME", f"{app_name}-{version}.zip")


def zip_app(source_bundle: Path, output_path: Path, runner: Runner) -> None:
    runner.run(
        [
            "ditto",
            "-c",
            "-k",
            "--keepParent",
            "--sequesterRsrc",
            str(source_bundle),
            str(output_path),
        ]
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_release(
    root: Path,
    env: dict[str, str],
    runner: Runner,
    *,
    version: str,
    build_number: str,
    metadata_out: Path | None = None,
) -> ReleaseMetadata:
    app_name = get_env(env, "CLIPIARY_APP_NAME", "Clipiary")
    release_repo = get_env(env, "CLIPIARY_RELEASE_REPO", "liamhess/clipiary")
    cask_token = get_env(env, "CLIPIARY_CASK_TOKEN", "clipiary")
    signing_identity = env.get("CLIPIARY_CODESIGN_IDENTITY", "")
    notary_apple_id = env.get("CLIPIARY_NOTARY_APPLE_ID", "")
    notary_team_id = env.get("CLIPIARY_NOTARY_TEAM_ID", "")
    notary_password = env.get("CLIPIARY_NOTARY_PASSWORD", "")
    output_dir = dist_dir(root)
    archive_path = output_dir / archive_name(env, version)
    notary_archive_path = output_dir / f"{app_name}-{version}-notarization.zip"
    release_notes_path = output_dir / f"{app_name}-{version}.release-notes.txt"
    sha256_path = output_dir / f"{app_name}-{version}.sha256"
    cask_path = resolve_path(root, env.get("CLIPIARY_CASK_OUTPUT_PATH")) or (output_dir / f"{cask_token}.rb")

    for path in (archive_path, notary_archive_path, release_notes_path, sha256_path, cask_path):
        remove_path(path, dry_run=runner.dry_run)

    build_env = env.copy()
    build_env["CLIPIARY_VERSION"] = version
    build_env["CLIPIARY_BUILD_NUMBER"] = build_number
    if signing_identity and not build_env.get("CLIPIARY_CODESIGN_FLAGS"):
        build_env["CLIPIARY_CODESIGN_FLAGS"] = "--timestamp --options runtime"

    build_result = build_app(
        root,
        build_env,
        runner,
        configuration="release",
        version_override=version,
        build_number_override=build_number,
    )

    if (
        signing_identity
        and notary_apple_id
        and notary_team_id
        and notary_password
    ):
        zip_app(build_result.app_bundle, notary_archive_path, runner)
        runner.run(
            [
                "xcrun",
                "notarytool",
                "submit",
                str(notary_archive_path),
                "--apple-id",
                notary_apple_id,
                "--team-id",
                notary_team_id,
                "--password",
                notary_password,
                "--wait",
            ]
        )
        runner.run(["xcrun", "stapler", "staple", str(build_result.app_bundle)])
        remove_path(notary_archive_path, dry_run=runner.dry_run)

    zip_app(build_result.app_bundle, archive_path, runner)
    sha256 = DRY_RUN_SHA256 if runner.dry_run else sha256_file(archive_path)
    write_text(sha256_path, sha256 + "\n", dry_run=runner.dry_run)
    generate_cask(env, version, sha256, cask_path, dry_run=runner.dry_run)

    release_notes = (
        f"Version: {version}\n"
        f"Build: {build_number}\n"
        f"Archive: {archive_path}\n"
        f"SHA256: {sha256}\n"
        f"Cask: {cask_path}\n"
    )
    write_text(release_notes_path, release_notes, dry_run=runner.dry_run)

    metadata = ReleaseMetadata(
        version=version,
        build_number=build_number,
        app_bundle=build_result.app_bundle,
        archive_path=archive_path,
        sha256=sha256,
        sha256_path=sha256_path,
        cask_path=cask_path,
        release_notes_path=release_notes_path,
        release_repo=release_repo,
        cask_token=cask_token,
    )
    if metadata_out is not None:
        write_json(metadata_out, metadata, dry_run=runner.dry_run)
    return metadata


def require_version(value: str | None) -> str:
    if not value:
        raise ToolError("A version is required")
    return value
