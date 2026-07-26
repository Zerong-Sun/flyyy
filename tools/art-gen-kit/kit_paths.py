"""Portable path configuration for art-gen-kit.

Override via environment variables (see config.example.env):

  ART_GEN_ROOT          Project root directory
  ART_GEN_DIR           Output folder for .webp assets (default: <root>/assets/art)
  ART_GEN_PROMPTS_DIR   Folder containing *PROMPTS*.md (default: same as ART_GEN_DIR)
  ART_GEN_TOOLS_DIR     Optional folder with audit.py + strip_checker.py for postprocess
"""

from __future__ import annotations

import os
from pathlib import Path

KIT_DIR = Path(__file__).resolve().parent

# Default: project/scripts/art-gen-kit → project root is two levels up
ROOT = Path(os.environ.get("ART_GEN_ROOT", KIT_DIR.parent.parent)).resolve()

ART_DIR = Path(os.environ.get("ART_GEN_DIR", ROOT / "assets" / "art")).resolve()
SHEETS_DIR = ART_DIR / "_sheets"
CATALOG_PATH = ART_DIR / "ART_CATALOG.json"
PROMPTS_DIR = Path(os.environ.get("ART_GEN_PROMPTS_DIR", ART_DIR)).resolve()

_tools = os.environ.get("ART_GEN_TOOLS_DIR", "").strip()
TOOLS_DIR = Path(_tools).resolve() if _tools else None
