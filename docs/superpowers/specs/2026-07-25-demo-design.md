# 《环球航商》Demo 设计纪要

**日期：** 2026-07-25  
**范围：** PRD §24 Demo（20 座枢纽）完整可玩闭环  

**首版交付口径：** 可玩 Demo = PRD §27（含基础 UI Theme）；地图阶段一门控见历史文档。素材现状见 `docs/CONTENT_ASSET_SPEC.md` §0.5。

## 决策锁定

- 引擎：Godot 4.x（GDScript），Forward+
- 数据：Python ETL → SQLite 校验源 + JSON 运行时（避免 GDExtension 二进制依赖）
- 航班：OpenFlights 邻接 + 拟真时刻表；UI 强制重建声明
- 时间：360×（1s = 6 游戏分钟）
- 模式：仅沙盒；仅直飞
- 货币：内部 USD，UI 显示 USD + CNY 折算；初始 ≈ ¥50,000

## 模块边界

见实现计划与 `game/scripts/` 目录。Godot 只读 `game/data/world.json` 与 `flights.json`。

## 非目标

20 座以外机场、真实时刻表、Logo、联程、动态汇率、多语言、云存档。
