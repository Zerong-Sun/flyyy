# 《环球航商》Airborne Trader

Godot 4.x 离线单机：20 座全球枢纽机场、球形地球与拟真航空网络。

> 航班网络基于公开航空数据重建，不代表真实购票信息。

**首版里程碑验收 = 地图与数据原型（PRD §26 第一阶段）**  
工程内已包含航班/贸易等后续系统，但**本里程碑不以完整 Demo（§27）为退出条件**。  
阶段一门控：[docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md](docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md)。  
完整 Demo 验收另见：[docs/superpowers/plans/2026-07-26-demo-acceptance.md](docs/superpowers/plans/2026-07-26-demo-acceptance.md)。

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

美术 / 音乐 / 文本规格见 [`docs/CONTENT_ASSET_SPEC.md`](docs/CONTENT_ASSET_SPEC.md)。  
仓库素材现状盘点（已齐 / 占位 / 缺失）见该文档 **§0.5**。阶段一可用程序占位地球贴图，不依赖美术包 D1。

## 阶段一玩法（本里程碑）

1. 搜索、列表或随机选择起始机场  
2. 在地球上旋转 / 缩放 / 点击（双击聚焦）  
3. 查看选中机场出港大圆航线（可「显示/隐藏航线」）  
4. 打开「数据来源」页查看署名与重建声明  

后续系统（市场、购票、加速、过场、存档）已在工程中，详见下方「完整 Demo 摘要」。

## 完整 Demo 摘要（超出本里程碑）

1. 在「市场」采购当地特产  
2. 在「航班」检索未来航班，购买经济舱/公务舱，可选行李扩展与货运  
3. 「加速至起飞」或等待时间流逝；起飞后强制登机并播放 5 秒过场  
4. 抵达后出售商品；自动存档  

时间流速：现实 1 秒 = 游戏 6 分钟（1 游戏日 ≈ 4 现实分钟）。

## 数据与许可证

详见游戏内「数据来源」页。主要来源：

| 来源 | 用途 | 许可 |
|------|------|------|
| OurAirports | 机场坐标 | Unlicense / 公有领域 |
| OpenFlights | 航线邻接种子 | ODbL |
| 游戏原创 | 城市简介与商品 | 原创内容 |

## 初始资金

按 PRD：¥50,000 等值（冻结汇率 USD/CNY=7.2 → 约 **$6,944**）。计划表中的 “USD$50,000” 为笔误，以 PRD 为准。

## 验收

```bash
# 阶段一（地图与数据）
python3 -m pytest tests/game/test_map_prototype.py -q

# 更广 ETL / Demo 规则（可选）
source etl/.venv/bin/activate
pytest tests/etl -q
python tools/demo_smoke_logic.py
```

阶段一手测清单见上文门控文档。完整 Demo 对照 PRD §27 二十二条。

## 架构

- `etl/` — Python 管线 → SQLite（校验）+ JSON（运行时）  
- `game/` — Godot 客户端（只读 `game/data/*.json`）  
- `PRD_01.md` — 产品需求  
- `docs/CONTENT_ASSET_SPEC.md` — 美术 / 音乐 / 文本规格与 §0.5 现状盘点  

引擎锁定：项目以 Godot 4.x Forward+ 为目标；开发机已安装版本见本机 Godot.app。
