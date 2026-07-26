# 《环球航商》Airborne Trader — 可玩 Demo

Godot 4.x 离线单机：20 座全球枢纽机场、拟真航班、贸易闭环与基础 UI Theme。

> 航班网络基于公开航空数据重建，不代表真实购票信息。

**首版里程碑验收 = 可玩 Demo（PRD §27）**  
对照表：[docs/superpowers/plans/2026-07-26-demo-acceptance.md](docs/superpowers/plans/2026-07-26-demo-acceptance.md)。  
阶段一地图门控仍保留：[docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md](docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md)。

## 要求

- Godot 4.3+（本地开发使用 4.7.x）
- Python 3.11+（ETL）

## 快速开始

### 1. 生成数据

```bash
cd etl
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python scripts/01_fetch_sources.py
python scripts/run_pipeline.py
```

管线将校验用 SQLite 与运行时 **JSON** 写出到 `game/data/`（客户端主读 `world.json` / `flights.json`）。

### 2. 打开游戏

用 Godot 打开 [`game/project.godot`](game/project.godot)，运行主场景。

或命令行：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

## 内容与资产规格

美术 / 音乐 / 文本规格见 [`docs/CONTENT_ASSET_SPEC.md`](docs/CONTENT_ASSET_SPEC.md)（**§0.5** 仓库现状）。  
基础 UI Theme：`game/themes/`（CAS 色板 + StyleBox）+ `game/assets/fonts/`（Noto Sans SC / JetBrains Mono）。地球正式贴图与过场插画仍为占位。

## 玩法（§27）

1. 搜索、列表或随机选择起始机场  
2. 在「市场」采购当地特产（注意行李重量）  
3. 在「航班」检索未来航班，购买经济舱/公务舱，可选行李扩展与货运  
4. 「加速至起飞」（二次确认）或等待时间流逝；起飞后强制登机并播放 5 秒过场  
5. 抵达后出售商品；自动/手动存档；「数据来源」查看署名  

时间流速：现实 1 秒 = 游戏 6 分钟（1 游戏日 ≈ 4 现实分钟）。

## 数据与许可证

详见游戏内「数据来源」页。主要来源：

| 来源 | 用途 | 许可 |
|------|------|------|
| OurAirports | 机场坐标 | Unlicense / 公有领域 |
| OpenFlights | 航线邻接种子 | ODbL |
| 游戏原创 | 城市简介与商品 | 原创内容 |
| Noto Sans SC / JetBrains Mono | UI 字体 | OFL 1.1 |

## 初始资金

按 PRD：¥50,000 等值（冻结汇率 USD/CNY=7.2 → 约 **$6,944**）。

## 验收

```bash
source etl/.venv/bin/activate
pytest tests/etl tests/game -q
python tools/demo_smoke_logic.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeContent.gd
```

手工剧本与 §27 二十二条见 [demo-acceptance.md](docs/superpowers/plans/2026-07-26-demo-acceptance.md)。

## 架构

- `etl/` — Python 管线 → SQLite（校验）+ JSON（运行时）  
- `game/` — Godot 客户端（只读 `game/data/*.json`）  
- `game/themes/` — Demo Theme / CAS 色板  
- `PRD_01.md` — 产品需求  
- `docs/CONTENT_ASSET_SPEC.md` — 美术 / 音乐 / 文本规格  

引擎锁定：项目以 Godot 4.x Forward+ 为目标。
