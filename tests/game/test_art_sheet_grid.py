from __future__ import annotations

import sys
from pathlib import Path

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "art-gen-kit"))

from batch_art_utils import parse_batch_prompts_md, split_contact_sheet  # noqa: E402
from crop_contact_sheet import crop_job  # noqa: E402

I3_SHEET = ROOT / "game" / "assets" / "art" / "_sheets" / "art_prompts_req--i3-icons-status-info-sheet-2-3-cell-256-256-outp.webp"
requires_i3_sheet = pytest.mark.skipif(
    not I3_SHEET.is_file(),
    reason=f"Contact sheet fixture missing: {I3_SHEET.name}",
)


def _rgb(pixel):
    return pixel[:3] if isinstance(pixel, tuple) and len(pixel) >= 3 else pixel


def _i3_job():
    prompts = ROOT / "game" / "assets" / "art" / "ART_PROMPTS_REQ.md"
    jobs = parse_batch_prompts_md(prompts.read_text(encoding="utf-8"), source=prompts.name)
    return next(job for job in jobs if job.name.startswith("I3"))


def test_split_contact_sheet_auto_swaps_declared_grid():
    colors = [
        (255, 0, 0),
        (0, 255, 0),
        (0, 0, 255),
        (255, 255, 0),
        (255, 0, 255),
        (0, 255, 255),
    ]
    im = Image.new("RGB", (300, 200))
    idx = 0
    for row in range(2):
        for col in range(3):
            cell = Image.new("RGB", (100, 100), colors[idx])
            im.paste(cell, (col * 100, row * 100))
            idx += 1

    job = _i3_job()
    job.cols = 2
    job.rows = 3
    job.cell_w = 100
    job.cell_h = 100
    for batch_file in job.files:
        batch_file.out_w = 100
        batch_file.out_h = 100

    cells = split_contact_sheet(im, job, gutter_trim=False)

    assert len(cells) == 6
    assert _rgb(cells[0].getpixel((50, 50))) == colors[0]
    assert _rgb(cells[1].getpixel((50, 50))) == colors[1]
    assert _rgb(cells[2].getpixel((50, 50))) == colors[2]
    assert _rgb(cells[3].getpixel((50, 50))) == colors[3]
    assert _rgb(cells[4].getpixel((50, 50))) == colors[4]
    assert _rgb(cells[5].getpixel((50, 50))) == colors[5]


@requires_i3_sheet
def test_i3_sheet_auto_swaps_grid_orientation():
    job = _i3_job()
    sheet = I3_SHEET

    cells = split_contact_sheet(Image.open(sheet), job)

    assert len(cells) == 6
    assert all(cell.size == (256, 256) for cell in cells[:3])


@requires_i3_sheet
def test_crop_job_uses_job_output_dir(tmp_path):
    job = _i3_job()
    job.files = job.files[:1]
    job.output_dir = tmp_path / "icons"
    sheet = I3_SHEET

    saved = crop_job(job, sheet, tmp_path / "art", quality=90, force=True)

    assert saved == 1
    assert (job.output_dir / job.files[0].filename).is_file()


def test_req_prompt_output_dir_targets_game_assets():
    job = _i3_job()

    assert job.output_dir == ROOT / "game" / "assets" / "icons"
