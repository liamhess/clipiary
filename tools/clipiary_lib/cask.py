from __future__ import annotations

from pathlib import Path

from .common import write_text
from .env import get_env


def render_cask(env: dict[str, str], version: str, sha256: str) -> str:
    app_name = get_env(env, "CLIPIARY_APP_NAME", "Clipiary")
    cask_token = get_env(env, "CLIPIARY_CASK_TOKEN", "clipiary")
    homepage = get_env(env, "CLIPIARY_HOMEPAGE", "https://github.com/liamhess/clipiary")
    release_repo = get_env(env, "CLIPIARY_RELEASE_REPO", "liamhess/clipiary")
    macos_depends_on = get_env(env, "CLIPIARY_MACOS_DEPENDS_ON", "sonoma")
    description = get_env(
        env,
        "CLIPIARY_DESCRIPTION",
        "macOS clipboard manager with an opt-in global copy-on-select mode",
    )
    archive_name = env.get("CLIPIARY_ARCHIVE_NAME", f"{app_name}-{version}.zip")
    url = f"https://github.com/{release_repo}/releases/download/v{version}/{archive_name}"

    return f"""cask "{cask_token}" do
  version "{version}"
  sha256 "{sha256}"

  url "{url}"
  name "{app_name}"
  desc "{description}"
  homepage "{homepage}"

  depends_on macos: ">= :{macos_depends_on}"

  app "{app_name}.app"
end
"""


def generate_cask(
    env: dict[str, str],
    version: str,
    sha256: str,
    output_path: Path | None,
    *,
    dry_run: bool,
) -> str:
    content = render_cask(env, version, sha256)
    if output_path is not None:
        write_text(output_path, content, dry_run=dry_run)
    return content
