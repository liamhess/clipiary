from __future__ import annotations

import shutil
from pathlib import Path

from .common import Runner, ToolError, ensure_dir, remove_path


def build_icon(root: Path, runner: Runner, source_png: str | None) -> Path:
    resources_dir = root / "Resources"
    iconset_dir = resources_dir / "AppIcon.iconset"
    tmp_tiff_dir = resources_dir / ".appicon-tiff"
    combined_tiff = resources_dir / "AppIcon.tiff"
    icon_file = resources_dir / "AppIcon.icns"
    master_png = resources_dir / "AppIcon-1024.png"

    ensure_dir(resources_dir, dry_run=runner.dry_run)

    if source_png:
        source_path = Path(source_png).expanduser()
        if not source_path.exists():
            raise ToolError(f"Missing source icon PNG at {source_path}")
        print(f"copy {source_path} -> {master_png}")
        if not runner.dry_run:
            shutil.copy2(source_path, master_png)

    if not master_png.exists() and not runner.dry_run:
        raise ToolError(f"Missing master icon PNG at {master_png}")
    if not master_png.exists() and runner.dry_run and not source_png:
        raise ToolError(f"Missing master icon PNG at {master_png}")

    remove_path(iconset_dir, dry_run=runner.dry_run)
    ensure_dir(iconset_dir, dry_run=runner.dry_run)

    for size in (16, 32, 128, 256, 512):
        standard = iconset_dir / f"icon_{size}x{size}.png"
        retina = iconset_dir / f"icon_{size}x{size}@2x.png"
        runner.run(
            ["sips", "-z", str(size), str(size), str(master_png), "--out", str(standard)]
        )
        retina_size = size * 2
        runner.run(
            ["sips", "-z", str(retina_size), str(retina_size), str(master_png), "--out", str(retina)]
        )

    remove_path(tmp_tiff_dir, dry_run=runner.dry_run)
    ensure_dir(tmp_tiff_dir, dry_run=runner.dry_run)

    pngs = sorted(iconset_dir.glob("*.png"))
    for png in pngs:
        tiff = tmp_tiff_dir / f"{png.stem}.tiff"
        runner.run(["sips", "-s", "format", "tiff", str(png), "--out", str(tiff)])

    tiffs = sorted(tmp_tiff_dir.glob("*.tiff"))
    runner.run(["tiffutil", "-cat", *[str(path) for path in tiffs], "-out", str(combined_tiff)])
    runner.run(["tiff2icns", str(combined_tiff), str(icon_file)])

    remove_path(tmp_tiff_dir, dry_run=runner.dry_run)
    remove_path(combined_tiff, dry_run=runner.dry_run)
    return icon_file
