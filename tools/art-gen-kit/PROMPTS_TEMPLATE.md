# Batch Prompts Template · art-gen-kit

Copy this file to your `ART_GEN_DIR` (or `ART_GEN_PROMPTS_DIR`) and edit batches.
Filename is passed to `--prompts-file` (basename only).

**Rules:**
- English-only prompts (CJK in user message may block submission)
- Each batch = one ChatGPT request
- `Window` groups batches into the same browser tab / chat lane
- `Mode: sheet` = one contact-sheet image, auto-cropped to cells
- `Mode: separate` = N individual images in one response (keep N ≤ 4–6)

---

## Batch 1 · ExampleWindow · two icons

- **Window**: ExampleWindow
- **Mode**: separate · **Count**: 2 · **Output per file**: 512×512 · **Background**: transparent
- **Output dir**: art
- **Files**:
  1. `icon-alpha.webp` — centered sun emblem, gold on transparent
  2. `icon-beta.webp` — centered moon emblem, silver on transparent

**Prompt**

Generate exactly 2 SEPARATE icons on transparent backgrounds (~512×512 each), NOT a contact sheet. Do not write an explanation.
Flat manuscript style, forest ink #0D1411, parchment #F0E4D0, antique gold #BDA476. Readable at 64px. NO text, NO letters.
Order:
1. icon-alpha.webp — sun emblem
2. icon-beta.webp — moon emblem
Negative: photorealistic, 3D, neon, watermark, text.

---

## Batch 2 · ExampleWindow · contact sheet 2×2

- **Window**: ExampleWindow
- **Mode**: sheet · **Grid**: 2×2 · **Cell**: 256×256 · **Output per file**: 256×256 · **Background**: transparent
- **Output dir**: art
- **Files**:
  1. `ui-btn-a.webp` — empty button frame
  2. `ui-btn-b.webp` — button frame highlighted
  3. `ui-btn-c.webp` — button frame pressed
  4. `ui-btn-d.webp` — button frame disabled

**Prompt**

Generate exactly ONE 2×2 contact sheet of 4 UI button frames on transparent background. Thin dark gutters. Flat parchment UI, no text.
Order row by row: empty · highlighted · pressed · disabled
Negative: photorealistic, 3D, neon, text, letters.

---

### Window → batches
- **ExampleWindow**: Batches 1–2

```bash
cd art-gen-kit
source config.env   # optional
.venv/bin/python orchestrate_req.py --prompts-file PROMPTS_TEMPLATE.md --dry-run
.venv/bin/python orchestrate_req.py --prompts-file PROMPTS_TEMPLATE.md --max-windows 1 --skip-existing
```
