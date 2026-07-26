# art-gen-kit · ChatGPT 批量生图工具包

通过 **Chrome CDP + Playwright** 附着已登录的 ChatGPT，读取 Markdown 批次 Prompt，自动提交、轮询、下载、裁切、转 WebP，并可选后处理（抠白底 / 去棋盘格 / 审计）。

适用于任意项目：复制整个 `art-gen-kit/` 目录，配置路径即可使用。

---

## 目录结构（复制到新项目后）

```
your-project/
├── assets/art/              ← 输出 .webp（可用 ART_GEN_DIR 改路径）
│   ├── _sheets/             ← 原始组图归档
│   ├── _archive/chats/      ← 对话全量图片备份
│   └── ART_PROMPTS_*.md     ← 批次 Prompt 文件
└── tools/art-gen-kit/       ← 本工具包（或 scripts/art-gen-kit/）
    ├── kit_paths.py         ← 路径配置（读环境变量）
    ├── orchestrate_req.py   ← ★ 主调度器（多窗口、轮询、续跑）
    ├── chatgpt_gen_art.py   ← 单批/legacy 提交
    ├── batch_art_utils.py   ← Prompt 解析 + 组图裁切
    ├── submit_map_windows.py
    ├── resume_dual_decks.py ← 对话恢复 / 限流检测
    ├── dealpha.py           ← 白底 → 真 alpha
    ├── postprocess_art.py   ← dealpha + strip + audit
    ├── crop_contact_sheet.py
    ├── archive_chat_images.py
    ├── run_parallel.py      ← 多 Prompt 文件并行（各 1 tab）
    ├── launch_chrome_debug.sh
    ├── setup.sh
    ├── config.example.env
    └── PROMPTS_TEMPLATE.md
```

**默认路径推断：** 工具包位于 `项目/scripts/art-gen-kit/` 时，`ART_GEN_ROOT` = 上两级目录。

---

## 一次性安装

```bash
cd art-gen-kit
chmod +x setup.sh launch_chrome_debug.sh
./setup.sh
```

依赖见 `requirements-art-gen.txt`：`playwright>=1.40`、`pillow>=10.0`。

也可共用上级目录已有 venv（FateQuest：`fatequest/scripts/.venv/bin/python`）。

---

## 配置（其他项目必做）

```bash
cp config.example.env config.env
# 编辑 ART_GEN_ROOT、ART_GEN_DIR 等
source config.env
```

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `ART_GEN_ROOT` | `kit/../..` | 项目根目录 |
| `ART_GEN_DIR` | `$ROOT/assets/art` | 输出 `.webp` 目录 |
| `ART_GEN_PROMPTS_DIR` | 同 `ART_GEN_DIR` | `*PROMPTS*.md` 所在目录 |
| `ART_GEN_TOOLS_DIR` | （空） | 含 `audit.py` + `strip_checker.py` 的目录；空则跳审计 |
| `CHROME_DEBUG_PROFILE` | `~/.cache/art-gen-chrome-debug` | Chrome 调试配置目录 |

---

## 每次生图流程

### 1. 启动 Chrome（CDP）

```bash
./launch_chrome_debug.sh          # 默认端口 9222
./launch_chrome_debug.sh 9223     # 自定义端口
USE_DEFAULT_PROFILE=1 ./launch_chrome_debug.sh   # 用日常配置（须先 Cmd+Q 退出 Chrome）
```

在弹出窗口登录 https://chatgpt.com/ ，确认能手动生图。

验证：`curl -s http://127.0.0.1:9222/json/version`

### 2. 编写 Prompt 文件

见 `PROMPTS_TEMPLATE.md`。每个 Batch 块包含：

| 字段 | 说明 |
|---|---|
| `Window` | 浏览器标签/对话 lane 名；同 Window 的多 Batch 顺序复用同一对话 |
| `Mode` | `sheet`（组图裁切）或 `separate`（一次 N 张独立图） |
| `Grid` | sheet 模式：`列×行` |
| `Cell` / `Output per file` | 像素尺寸 |
| `Background` | `transparent` 或 `opaque` |
| `Files` | 输出文件名列表（须与代码引用名一致） |
| `Prompt` | 发给 ChatGPT 的英文正文 |

### 3. 主调度器 `orchestrate_req.py`（推荐）

```bash
# 预览待跑窗口
.venv/bin/python orchestrate_req.py --prompts-file MY_PROMPTS.md --dry-run --skip-existing

# 单窗口顺序跑（稳）
.venv/bin/python orchestrate_req.py --prompts-file MY_PROMPTS.md \
  --max-windows 1 --poll-sec 600 --skip-existing

# 双窗口并行（同文件内两个 Window）
.venv/bin/python orchestrate_req.py --prompts-file MY_PROMPTS.md \
  --max-windows 2 --poll-sec 600 --skip-existing

# 只跑指定 Window
.venv/bin/python orchestrate_req.py --prompts-file MY_PROMPTS.md \
  --window-order WindowA WindowB --max-windows 1 --skip-existing
```

#### `orchestrate_req.py` 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `--port` | `9222` | Chrome CDP 端口 |
| `--prompts-file` | `ART_PROMPTS_REQ.md` | Prompt 文件名（在 PROMPTS_DIR 或 ART_DIR 查找） |
| `--max-windows` | `2` | 同时打开的 ChatGPT 标签数 |
| `--poll-sec` | `600` | 轮询/收割间隔（秒）；生图慢可加大 |
| `--skip-existing` | 开 | 磁盘已有文件则跳过 |
| `--no-skip-existing` | | 强制重跑 |
| `--dry-run` | | 只打印队列，不提交 |
| `--window-order` | | 指定 Window 顺序；配合 `--max-windows 1` 可逐个跑 |
| `--quality` | `90` | WebP 质量 |
| `--rate-limit-ms` | `600000` | 检测到限流后等待（毫秒） |
| `--wait-login-ms` | `600000` | 等待手动登录的最长时间 |

**运行逻辑：**
1. 解析 Prompt 文件 → 按 `Window` 分组为 lane
2. 打开 lane → 提交 Batch → 标记 waiting
3. 每 `--poll-sec` 收割新图 → 裁切/缩放 → 写入 `ART_GEN_DIR`
4. lane 完成 → 开下一个；对话 URL 写入 `orchestrate_req_status.json` 可续跑
5. 900s 仍显示 generating 会强制尝试 harvest

### 4. 多 Prompt 文件并行 `run_parallel.py`

两个（或多个）Prompt 文件各占 1 个 tab，适合 P0+P1 双线：

```bash
.venv/bin/python run_parallel.py ART_PROMPTS_P0.md ART_PROMPTS_P1.md
```

内部：每个文件启动独立 `orchestrate_req.py --max-windows 1`，间隔 3s 错开开 tab。

### 5. 后处理（透明底必跑）

ChatGPT 常输出白底或 baked-in 棋盘格：

```bash
.venv/bin/python postprocess_art.py                    # 全部 art/*.webp
.venv/bin/python postprocess_art.py icon-*.webp        # 指定 glob
.venv/bin/python dealpha.py --apply                    # 仅抠白底
```

设置 `ART_GEN_TOOLS_DIR` 后可跑 `strip_checker` + `audit`（FateQuest 在 `tools/art/`）。

### 6. 组图单独裁切

```bash
.venv/bin/python crop_contact_sheet.py --list --prompts-file MY_PROMPTS.md
.venv/bin/python crop_contact_sheet.py --prompts-file MY_PROMPTS.md --batch 1
.venv/bin/python crop_contact_sheet.py --all-sheets --prompts-file MY_PROMPTS.md
```

### 7. 归档对话全部图片

```bash
.venv/bin/python archive_chat_images.py --url 'https://chatgpt.com/c/UUID'
```

保存到 `assets/art/_archive/chats/<uuid>/`。

---

## Legacy 单批脚本 `chatgpt_gen_art.py`

较早期接口，仍可用于 `ART_PROMPTS.md` 分段（P0/P1/P2）或单次试跑：

```bash
.venv/bin/python chatgpt_gen_art.py --dry-run
.venv/bin/python chatgpt_gen_art.py --batch --prompts-file ART_PROMPTS_UI.md --skip-existing
.venv/bin/python chatgpt_gen_art.py --skip-existing --limit 1
```

| 参数 | 说明 |
|---|---|
| `--section P0\|P1\|P2\|ALL` | ART_PROMPTS.md 区间 |
| `--prompt-index 1\|2\|3` | 使用第几套 Prompt |
| `--only file-a file-b` | 只跑指定输出名 |
| `--new-chat` | 每张图新对话 |
| `--timeout-ms` | 等图超时 |
| `--port` | CDP 端口 |

---

## Prompt 文件 → 脚本 → 产物 数据流

```
ART_PROMPTS_*.md
    │ parse_batch_prompts_md()
    ▼
BatchJob[] (window, mode, files[], prompt, grid…)
    │ orchestrate_req / chatgpt_gen_art
    ▼
Playwright → ChatGPT (submit_prompt)
    │ poll / harvest_lane
    ▼
fetch_image_bytes → resize_to_spec → image_to_webp_bytes
    │ sheet: split_contact_sheet → _sheets/ + cells
    ▼
ART_GEN_DIR/*.webp
    │ postprocess_art / dealpha
    ▼
真透明 / 无棋盘格 最终素材
```

---

## 常见问题

| 问题 | 处理 |
|---|---|
| `Too many requests` | 减 `--max-windows` 为 1；加大 `--poll-sec`；等 10–60 分钟后 `--skip-existing` 续跑 |
| 页面断开 TargetClosed | orchestrator 会自动 `ensure_lane_page` 重开；保留 chat URL |
| 提交含中文被拒 | Prompt 改全英文 |
| 透明底发灰/棋盘格 | 跑 `dealpha.py --apply` + `postprocess_art.py` |
| CDP 连不上 | 必须先 `launch_chrome_debug.sh`；普通 Chrome 无法中途开 9222 |
| DOM 变更提交失败 | 改 `chatgpt_gen_art.py` 内选择器 |

---

## 文件清单

| 文件 | 职责 |
|---|---|
| `kit_paths.py` | 环境变量路径 |
| `batch_art_utils.py` | Markdown 解析、组图裁切、WebP、catalog |
| `chatgpt_gen_art.py` | CDP 连接、提交、下载、legacy 批处理 |
| `orchestrate_req.py` | 多 lane 调度、轮询、续跑状态 |
| `submit_map_windows.py` | 构建消息、save_batch、missing_files |
| `resume_dual_decks.py` | ensure_chat、generation_busy、限流 |
| `dealpha.py` | 白底 flood-fill → alpha |
| `postprocess_art.py` | 后处理管线入口 |
| `crop_contact_sheet.py` | 离线裁切已有组图 |
| `archive_chat_images.py` | 对话图片全量归档 |
| `harvest_chat_images.py` | 批量收割指定 URL |
| `run_parallel.py` | 多 Prompt 文件并行 wrapper |
| `launch_chrome_debug.sh` | 启动调试 Chrome |

---

## FateQuest 中的位置

本 kit 源码位于：

`fatequest/scripts/art-gen-kit/`

FateQuest 运行时可将 `ART_GEN_ROOT` 指向 `fatequest/`，Prompt 与输出均在 `fatequest/assets/art/`。

```bash
cd fatequest/scripts/art-gen-kit
export ART_GEN_ROOT="$(cd ../.. && pwd)"
export ART_GEN_TOOLS_DIR="/path/to/fatequest/tools/art"   # 可选
source config.env  # 或手动 export
./launch_chrome_debug.sh
.venv/bin/python run_parallel.py ART_PROMPTS_REQ_P0.md ART_PROMPTS_REQ_P1.md
```

---

## 复制到新项目 Checklist

1. 复制 `art-gen-kit/` 文件夹
2. `./setup.sh`
3. 配置 `config.env`（`ART_GEN_ROOT`、`ART_GEN_DIR`）
4. 复制 `PROMPTS_TEMPLATE.md` → 你的 Prompt 文件
5. `./launch_chrome_debug.sh` + 登录 ChatGPT
6. `orchestrate_req.py --dry-run` → 正式跑 → `postprocess_art.py`
