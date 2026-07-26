"""Shared batch contact-sheet parsing, cropping, catalog, and metadata helpers."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image

from kit_paths import ART_DIR, CATALOG_PATH, ROOT, SHEETS_DIR

_SIZE_RE = re.compile(r"(\d+)\s*[×xX]\s*(\d+)")


@dataclass
class BatchFile:
    filename: str
    description: str
    out_w: int
    out_h: int


@dataclass
class BatchJob:
    name: str
    files: list[BatchFile]
    prompt: str
    cols: int
    rows: int
    cell_w: int
    cell_h: int
    transparent: bool
    source: str = ""
    mode: str = "sheet"  # sheet | separate
    output_dir: Path | None = None
    window: str = ""  # category window id (A/B/C/…) when present


def _parse_size_pair(text: str) -> tuple[int | None, int | None]:
    m = _SIZE_RE.search(text)
    if not m:
        return None, None
    return int(m.group(1)), int(m.group(2))


def parse_batch_prompts_md(text: str, source: str = "") -> list[BatchJob]:
    jobs: list[BatchJob] = []
    sections = re.split(r"\n## Batch ", text)
    for raw in sections[1:]:
        title_end = raw.find("\n")
        title = raw[:title_end].strip() if title_end > 0 else "batch"
        block = raw[title_end:] if title_end > 0 else raw

        grid_m = re.search(r"\*\*Grid\*\*:\s*(\d+)\s*[×xX]\s*(\d+)", block)
        mode_m = re.search(r"\*\*Mode\*\*:\s*(\w+)", block, re.I)
        mode = (mode_m.group(1).lower() if mode_m else "sheet").strip()
        if mode not in ("sheet", "separate"):
            mode = "sheet"

        count_m = re.search(r"\*\*Count\*\*:\s*(\d+)", block)
        if grid_m:
            cols, rows = int(grid_m.group(1)), int(grid_m.group(2))
        elif mode == "separate":
            cols, rows = 1, 1
        else:
            continue

        cell_m = re.search(r"\*\*Cell\*\*:\s*(\d+)\s*[×xX]\s*(\d+)", block)
        cell_w, cell_h = (512, 512)
        if cell_m:
            cell_w, cell_h = int(cell_m.group(1)), int(cell_m.group(2))

        out_m = re.search(r"\*\*Output(?: per file)?\*\*:\s*(\d+)\s*[×xX]\s*(\d+)", block, re.I)
        batch_out_w, batch_out_h = cell_w, cell_h
        if out_m:
            batch_out_w, batch_out_h = int(out_m.group(1)), int(out_m.group(2))
        elif re.search(r"\*\*Output\*\*:\s*as listed", block, re.I):
            batch_out_w, batch_out_h = cell_w, cell_h

        bg_m = re.search(r"\*\*Background\*\*:\s*(.+)", block, re.I)
        bg = (bg_m.group(1) if bg_m else "").lower()
        transparent = "transparent" in bg and not re.match(r"^\s*opaque", bg)

        batch_files: list[BatchFile] = []
        for m in re.finditer(
            r"^\s*\d+\.\s+`([^`]+)`(?:\s*[-—–]\s*(.+))?\s*$", block, re.M
        ):
            fn = m.group(1).strip()
            desc = (m.group(2) or "").strip()
            fw, fh = _parse_size_pair(desc)
            if fw and fh:
                out_w, out_h = fw, fh
            else:
                out_w, out_h = batch_out_w, batch_out_h
            batch_files.append(BatchFile(fn, desc, out_w, out_h))

        if not batch_files:
            names = re.findall(r"`([a-z0-9][a-z0-9-]+\.(?:webp|png))`", block)
            batch_files = [
                BatchFile(fn, "", batch_out_w, batch_out_h) for fn in names
            ]

        prompt_m = re.search(
            r"\*\*Prompt\*\*\s*\n\n(.+?)(?:\n---|\n## Batch |\Z)", block, re.S
        )
        prompt = prompt_m.group(1).strip() if prompt_m else ""
        if not batch_files or not prompt:
            continue
        n_files = len(batch_files)
        if mode == "sheet" and n_files != cols * rows:
            print(f"[warn] {title}: {n_files} files != {cols}x{rows}")
        if mode == "separate":
            cols, rows = n_files, 1

        out_dir_m = re.search(r"\*\*Output dir\*\*:\s*(.+)", block, re.I)
        output_dir = None
        if out_dir_m:
            rel = out_dir_m.group(1).strip().strip("/")
            output_dir = ROOT / "assets" / rel

        win_m = re.search(r"\*\*Window\*\*:\s*([A-Za-z0-9]+)", block, re.I)
        window = win_m.group(1).strip() if win_m else ""

        jobs.append(
            BatchJob(
                name=title,
                files=batch_files if mode == "separate" else batch_files[: cols * rows],
                prompt=prompt,
                cols=cols,
                rows=rows,
                cell_w=cell_w,
                cell_h=cell_h,
                transparent=transparent,
                source=source,
                mode=mode,
                output_dir=output_dir,
                window=window,
            )
        )
    return jobs


def detect_gutter_inset(w: int, h: int, cols: int, rows: int) -> tuple[int, int]:
    """Estimate gutter pixels to trim from each cell edge (dark dividers)."""
    # ~1.2% of cell dimension, clamped 2–12 px
    cw, ch = w // cols, h // rows
    gx = max(2, min(12, int(cw * 0.012)))
    gy = max(2, min(12, int(ch * 0.012)))
    return gx, gy


def split_contact_sheet(
    raw: bytes | Image.Image,
    job: BatchJob,
    gutter_trim: bool = True,
) -> list[Image.Image]:
    im = raw if isinstance(raw, Image.Image) else Image.open(BytesIO(raw))
    im = im.convert("RGBA" if job.transparent else "RGB")
    w, h = im.size
    cw, ch = w // job.cols, h // job.rows
    gx, gy = detect_gutter_inset(w, h, job.cols, job.rows) if gutter_trim else (0, 0)

    cells: list[Image.Image] = []
    for r in range(job.rows):
        for c in range(job.cols):
            idx = r * job.cols + c
            bf = job.files[idx] if idx < len(job.files) else None
            out_w = bf.out_w if bf else job.cell_w
            out_h = bf.out_h if bf else job.cell_h
            x0 = c * cw + gx
            y0 = r * ch + gy
            x1 = (c + 1) * cw - gx
            y1 = (r + 1) * ch - gy
            cell = im.crop((x0, y0, x1, y1))
            if out_w and out_h and (cell.width != out_w or cell.height != out_h):
                cell = cell.resize((out_w, out_h), Image.Resampling.LANCZOS)
            cells.append(cell)
    return cells


def _prepare_im(im: Image.Image, transparent: bool) -> Image.Image:
    if transparent:
        return im.convert("RGBA")
    if im.mode in ("RGBA", "LA"):
        bg = Image.new("RGB", im.size, (13, 20, 17))
        bg.paste(im, mask=im.split()[-1])
        return bg
    return im.convert("RGB")


def image_to_webp_bytes(
    im: Image.Image,
    transparent: bool,
    quality: int = 90,
    description: str = "",
) -> bytes:
    out = BytesIO()
    im = _prepare_im(im, transparent)
    save_kw: dict[str, Any] = {"format": "WEBP", "quality": quality, "method": 6}
    if description:
        exif = im.getexif()
        exif[270] = description[:2000]
        save_kw["exif"] = exif
    im.save(out, **save_kw)
    return out.getvalue()


def save_cell_webp(
    cell: Image.Image,
    path: Path,
    transparent: bool,
    description: str = "",
    quality: int = 90,
) -> None:
    data = image_to_webp_bytes(cell, transparent, quality, description)
    path.write_bytes(data)


def slug_batch(name: str) -> str:
    return re.sub(r"[^\w.-]+", "-", name.lower()).strip("-")[:48]


def sheet_path_for(job: BatchJob, prompts_stem: str) -> Path:
    return SHEETS_DIR / f"{slug_batch(prompts_stem)}--{slug_batch(job.name)}.webp"


def parse_art_prompts_single(text: str) -> dict[str, dict[str, str]]:
    """Parse ART_PROMPTS.md ### blocks → {filename: {where, content, spec, accent}}."""
    out: dict[str, dict[str, str]] = {}
    blocks = re.split(r"\n### `", text)
    for raw in blocks:
        if not raw.startswith(("card-", "sym-", "arch-", "mode-", "bg-", "curse-", "comp-", "realm-", "item-", "map-", "region-", "marker-", "icon")):
            if "`" not in raw[:80]:
                continue
        if not raw.startswith("`"):
            raw = "`" + raw
        m_name = re.match(r"`([^`]+)`", raw)
        if not m_name:
            continue
        name = m_name.group(1).strip()
        if not re.search(r"\.(webp|png)$", name):
            continue

        def meta(key: str) -> str:
            mm = re.search(rf"-\s+\*\*{key}\*\*：(.+)", raw)
            return mm.group(1).strip() if mm else ""

        out[name] = {
            "where": meta("用在"),
            "content": meta("内容"),
            "spec": meta("规格"),
            "accent": meta("辅色"),
        }
    return out


def parse_brief_table(text: str) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    for line in text.splitlines():
        if not line.strip().startswith("|"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 5:
            continue
        ref = parts[1].strip("` ")
        if not ref.endswith(".webp") and not ref.endswith(".png"):
            continue
        if "引用名" in ref or "---" in ref:
            continue
        # merge multi-name cells like sym-qian.webp `sym-kun.webp`
        for token in re.findall(r"[\w-]+\.(?:webp|png)", ref):
            out[token] = {
                "where": parts[2],
                "content": parts[3],
                "spec": parts[4],
            }
    return out


def build_catalog_entry(
    filename: str,
    *,
    batch: str = "",
    description_en: str = "",
    brief: dict[str, str] | None = None,
    single: dict[str, str] | None = None,
    out_w: int | None = None,
    out_h: int | None = None,
    source: str = "",
) -> dict[str, Any]:
    brief = brief or {}
    single = single or {}
    where = brief.get("where") or single.get("where") or ""
    content = brief.get("content") or single.get("content") or description_en
    spec = brief.get("spec") or single.get("spec") or ""
    accent = brief.get("accent") or single.get("accent") or ""
    w, h = out_w, out_h
    if not w or not h:
        sw, sh = _parse_size_pair(spec)
        w, h = sw, sh

    desc_zh = content
    if where and content:
        desc_zh = f"{content}（{where}）"
    elif where:
        desc_zh = where

    return {
        "file": filename,
        "batch": batch,
        "source": source,
        "description_en": description_en or content,
        "description_zh": desc_zh,
        "where": where,
        "content": content,
        "spec": spec,
        "accent": accent,
        "width": w,
        "height": h,
    }


def collect_catalog(art_dir: Path | None = None) -> dict[str, Any]:
    art_dir = art_dir or ART_DIR
    brief = parse_brief_table((art_dir / "ART_BRIEF.md").read_text(encoding="utf-8"))
    single: dict[str, dict[str, str]] = {}
    prompts_path = art_dir / "ART_PROMPTS.md"
    if prompts_path.exists():
        single = parse_art_prompts_single(prompts_path.read_text(encoding="utf-8"))

    entries: dict[str, dict[str, Any]] = {}

    for prompts_name in ("ART_PROMPTS_UI.md", "ART_PROMPTS_CARDS.md"):
        p = art_dir / prompts_name
        if not p.exists():
            continue
        for job in parse_batch_prompts_md(p.read_text(encoding="utf-8"), source=prompts_name):
            for bf in job.files:
                entries[bf.filename] = build_catalog_entry(
                    bf.filename,
                    batch=job.name,
                    description_en=bf.description,
                    brief=brief.get(bf.filename),
                    out_w=bf.out_w,
                    out_h=bf.out_h,
                    source=prompts_name,
                )

    for fn, meta in single.items():
        if fn not in entries:
            entries[fn] = build_catalog_entry(fn, brief=brief.get(fn), single=meta, source="ART_PROMPTS.md")

    for fn, meta in brief.items():
        if fn not in entries:
            entries[fn] = build_catalog_entry(fn, brief=meta, source="ART_BRIEF.md")

    # enrich with on-disk dimensions
    assets: list[dict[str, Any]] = []
    for p in sorted(art_dir.glob("*.webp")):
        if p.name.startswith("_"):
            continue
        entry = entries.get(p.name) or build_catalog_entry(p.name)
        try:
            with Image.open(p) as im:
                entry["width"] = im.size[0]
                entry["height"] = im.size[1]
                exif = im.getexif()
                if exif and 270 in exif:
                    entry["exif_description"] = exif[270]
        except Exception:
            pass
        entry["bytes"] = p.stat().st_size
        assets.append(entry)

    for p in sorted(art_dir.glob("*.png")):
        if p.name.startswith("_"):
            continue
        entry = entries.get(p.name) or build_catalog_entry(p.name)
        try:
            with Image.open(p) as im:
                entry["width"] = im.size[0]
                entry["height"] = im.size[1]
        except Exception:
            pass
        entry["bytes"] = p.stat().st_size
        assets.append(entry)

    return {
        "version": 1,
        "style": "Cloud-ridge Twilight / 云岭暮光",
        "count": len(assets),
        "assets": assets,
    }


def write_catalog(catalog: dict[str, Any], path: Path | None = None) -> Path:
    path = path or CATALOG_PATH
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def embed_catalog_descriptions(catalog: dict[str, Any], art_dir: Path | None = None) -> int:
    art_dir = art_dir or ART_DIR
    n = 0
    for entry in catalog["assets"]:
        fn = entry["file"]
        path = art_dir / fn
        if not path.exists():
            continue
        desc = entry.get("description_en") or entry.get("description_zh") or ""
        if not desc:
            continue
        # EXIF ImageDescription is ASCII-unreliable; use English batch text only
        if not desc.isascii():
            desc = f"FateQuest art asset - see ART_CATALOG.json for {fn}"
        try:
            im = Image.open(path)
            transparent = "透明" in (entry.get("spec") or "") or fn.startswith("ui-orn")
            data = image_to_webp_bytes(im, transparent, description=desc)
            path.write_bytes(data)
            n += 1
        except Exception:
            continue
    return n
