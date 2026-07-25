# 《环球航商》Airborne Trader — Demo

Godot 4.x 离线单机 Demo：20 座全球枢纽机场、拟真航班、贸易闭环。

> 航班网络基于公开航空数据重建，不代表真实购票信息。

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

### 2. 打开游戏

用 Godot 打开 [`game/project.godot`](game/project.godot)，运行主场景。

或命令行：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

## 玩法摘要

1. 选择或随机起始机场  
2. 在「市场」采购当地特产  
3. 在「航班」检索未来航班，购买经济舱/公务舱，可选行李扩展与货运  
4. 「加速至起飞」或等待时间流逝；起飞后强制登机并播放 5 秒过场  
5. 抵达后出售商品；自动存档  

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

- `etl/` — Python 管线 → SQLite + JSON  
- `game/` — Godot 客户端（只读 `game/data/`）  
- `PRD_01.md` — 产品需求  

引擎锁定：项目以 Godot 4.x Forward+ 为目标；开发机已安装版本见本机 Godot.app。
