from __future__ import annotations

import base64
import os
import re
import tempfile
from pathlib import Path

from .common import Runner, ToolError, write_text
from .env import get_env
from .release import ReleaseMetadata


SEMVER_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def import_signing_certificate(root: Path, env: dict[str, str], runner: Runner) -> None:
    certificate_p12 = env.get("CLIPIARY_CODESIGN_P12_BASE64") or env.get("CLIPIARY_DEVELOPER_ID_P12_BASE64")
    certificate_password = env.get("CLIPIARY_CODESIGN_P12_PASSWORD") or env.get("CLIPIARY_DEVELOPER_ID_P12_PASSWORD")
    keychain_password = env.get("CLIPIARY_KEYCHAIN_PASSWORD")
    if not (certificate_p12 and certificate_password and keychain_password):
        return

    tmp_dir = root / ".tmp"
    cert_path = tmp_dir / "clipiary-signing-certificate.p12"
    keychain_path = tmp_dir / "clipiary-signing.keychain-db"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    print(f"write {cert_path}")
    if not runner.dry_run:
        cert_path.write_bytes(base64.b64decode(certificate_p12))

    runner.run(["security", "create-keychain", "-p", keychain_password, str(keychain_path)])
    runner.run(["security", "set-keychain-settings", "-lut", "21600", str(keychain_path)])
    runner.run(["security", "unlock-keychain", "-p", keychain_password, str(keychain_path)])
    runner.run(
        [
            "security",
            "import",
            str(cert_path),
            "-P",
            certificate_password,
            "-A",
            "-t",
            "cert",
            "-f",
            "pkcs12",
            "-k",
            str(keychain_path),
        ]
    )
    runner.run(["security", "list-keychains", "-d", "user", "-s", str(keychain_path), "login.keychain-db"])
    runner.run(["security", "default-keychain", "-s", str(keychain_path)])
    runner.run(
        [
            "security",
            "set-key-partition-list",
            "-S",
            "apple-tool:,apple:",
            "-s",
            "-k",
            keychain_password,
            str(keychain_path),
        ]
    )
    runner.run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain_path)])


def verify_tagged_commit_on_main(root: Path, runner: Runner, git_sha: str | None) -> None:
    if not git_sha:
        return
    runner.run(["git", "fetch", "origin", "main", "--depth=1"], cwd=root, read_only=True)
    runner.run(
        ["git", "merge-base", "--is-ancestor", git_sha, "origin/main"],
        cwd=root,
        read_only=True,
    )


def publish_release(root: Path, env: dict[str, str], runner: Runner, metadata: ReleaseMetadata) -> None:
    tag = f"v{metadata.version}"
    gh_env = os.environ.copy()
    gh_env.update(env)
    release_repo = metadata.release_repo
    title = f"Clipiary {metadata.version}"
    if runner.dry_run:
        runner.run(
            [
                "gh",
                "release",
                "create",
                tag,
                str(metadata.archive_path),
                "--title",
                title,
                "--notes-file",
                str(metadata.release_notes_path),
                "--repo",
                release_repo,
            ],
            env=gh_env,
        )
    else:
        release_view = runner.run(
            ["gh", "release", "view", tag, "--repo", release_repo],
            env=gh_env,
            read_only=True,
            check=False,
        )
        if release_view.returncode == 0:
            runner.run(
                [
                    "gh",
                    "release",
                    "upload",
                    tag,
                    str(metadata.archive_path),
                    "--clobber",
                    "--repo",
                    release_repo,
                ],
                env=gh_env,
            )
            runner.run(
                [
                    "gh",
                    "release",
                    "edit",
                    tag,
                    "--title",
                    title,
                    "--notes-file",
                    str(metadata.release_notes_path),
                    "--repo",
                    release_repo,
                ],
                env=gh_env,
            )
        else:
            runner.run(
                [
                    "gh",
                    "release",
                    "create",
                    tag,
                    str(metadata.archive_path),
                    "--title",
                    title,
                    "--notes-file",
                    str(metadata.release_notes_path),
                    "--repo",
                    release_repo,
                ],
                env=gh_env,
            )

    deploy_key = env.get("HOMEBREW_TAP_DEPLOY_KEY", "")
    if not deploy_key:
        return

    tap_repo = get_env(env, "HOMEBREW_TAP_REPOSITORY", "liamhess/homebrew-tap")
    cask_token = metadata.cask_token
    if runner.dry_run:
        runner.run(
            [
                "git",
                "clone",
                f"git@github.com:{tap_repo}.git",
                "<tmp>/homebrew-tap",
            ],
        )
        runner.run(["git", "commit", "-m", f"clipiary {metadata.version}"], cwd=Path("<tmp>/homebrew-tap"))
        runner.run(["git", "push", "origin", "HEAD"], cwd=Path("<tmp>/homebrew-tap"))
        return

    with tempfile.TemporaryDirectory() as tmp_dir_name:
        tmp_dir = Path(tmp_dir_name)
        ssh_key_path = tmp_dir / "homebrew-tap-deploy-key"
        known_hosts_path = tmp_dir / "github-known-hosts"
        tap_dir = tmp_dir / "homebrew-tap"

        write_text(ssh_key_path, deploy_key + "\n", dry_run=runner.dry_run)
        if not runner.dry_run:
            ssh_key_path.chmod(0o600)

        output = runner.read(["ssh-keyscan", "-H", "github.com"])
        known_hosts_path.write_text(output + "\n", encoding="utf-8")

        git_env = os.environ.copy()
        git_env.update(env)
        git_env["GIT_SSH_COMMAND"] = (
            f"ssh -i {ssh_key_path} -o IdentitiesOnly=yes -o UserKnownHostsFile={known_hosts_path}"
        )
        runner.run(["git", "clone", f"git@github.com:{tap_repo}.git", str(tap_dir)], env=git_env)
        runner.run(["git", "config", "user.name", "github-actions[bot]"], cwd=tap_dir, env=git_env)
        runner.run(
            ["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"],
            cwd=tap_dir,
            env=git_env,
        )

        casks_dir = tap_dir / "Casks"
        target_cask = casks_dir / f"{cask_token}.rb"
        print(f"copy {metadata.cask_path} -> {target_cask}")
        if not runner.dry_run:
            casks_dir.mkdir(parents=True, exist_ok=True)
            target_cask.write_text(metadata.cask_path.read_text(encoding="utf-8"), encoding="utf-8")

        runner.run(["git", "add", f"Casks/{cask_token}.rb"], cwd=tap_dir, env=git_env)
        diff = runner.run(
            ["git", "diff", "--cached", "--quiet", "--", f"Casks/{cask_token}.rb"],
            cwd=tap_dir,
            env=git_env,
            read_only=True,
            capture_output=True,
            check=False,
        )
        if diff.returncode == 0:
            print("Tap already up to date.")
            return
        runner.run(["git", "commit", "-m", f"clipiary {metadata.version}"], cwd=tap_dir, env=git_env)
        runner.run(["git", "push", "origin", "HEAD"], cwd=tap_dir, env=git_env)


def latest_release_tag(root: Path, runner: Runner) -> str:
    tags = runner.read(["git", "tag", "--list", "v*", "--sort=version:refname"], cwd=root)
    if not tags:
        raise ToolError("No release tags found; create an initial v0.1.0 tag manually")
    return tags.splitlines()[-1]


def bump_version(tag: str, bump: str) -> str:
    match = SEMVER_RE.match(tag)
    if not match:
        raise ToolError(f"Latest tag is not semver-compatible: {tag}")
    major, minor, patch = (int(value) for value in match.groups())
    if bump == "major":
        major += 1
        minor = 0
        patch = 0
    elif bump == "minor":
        minor += 1
        patch = 0
    else:
        patch += 1
    return f"v{major}.{minor}.{patch}"


def remote_slug(root: Path, runner: Runner) -> str | None:
    origin = runner.read(["git", "config", "--get", "remote.origin.url"], cwd=root)
    ssh_match = re.match(r"git@github\.com:([^/]+/[^/]+?)(?:\.git)?$", origin)
    if ssh_match:
        return ssh_match.group(1)
    https_match = re.match(r"https://github\.com/([^/]+/[^/]+?)(?:\.git)?$", origin)
    if https_match:
        return https_match.group(1)
    return None


def start_release(root: Path, runner: Runner, bump: str) -> dict[str, str]:
    current_tag = latest_release_tag(root, runner)
    next_tag = bump_version(current_tag, bump)

    existing_local = runner.run(
        ["git", "rev-parse", "-q", "--verify", f"refs/tags/{next_tag}"],
        cwd=root,
        read_only=True,
        capture_output=True,
        check=False,
    )
    if existing_local.returncode == 0:
        raise ToolError(f"Tag already exists locally: {next_tag}")

    runner.run(["git", "tag", "-a", next_tag, "-m", f"Clipiary {next_tag[1:]}"], cwd=root)
    runner.run(["git", "push", "origin", next_tag], cwd=root)

    slug = remote_slug(root, runner)
    actions_url = ""
    release_url = ""
    if slug:
        actions_url = f"https://github.com/{slug}/actions/workflows/release.yml"
        release_url = f"https://github.com/{slug}/releases/tag/{next_tag}"

    return {
        "previous_tag": current_tag,
        "tag": next_tag,
        "actions_url": actions_url,
        "release_url": release_url,
    }
