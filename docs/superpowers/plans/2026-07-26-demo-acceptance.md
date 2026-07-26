# Demo §27 验收对照表（2026-07-26；Theme 收口更新）

**里程碑：** 可玩 Demo（PRD §27）+ 基础 UI Theme  
**自动化：** `pytest tests/etl tests/game -q` · `python tools/demo_smoke_logic.py` · Godot `SmokeContent.gd`  
**手测日：** 2026-07-26（逻辑路径经 smoke + headless 加载；完整编辑器剧本与 Profiler 见下方）

| # | 标准 | 自动化 | 手工 | 状态 |
|---|------|--------|------|------|
| 1 | 地球搜索/定位 20 机场 | `test_map_prototype` / hubs | 编辑器点选/搜索 | 通过（数据+代码） |
| 2 | 随机起点 | — | 新游戏「随机机场」 | 待编辑器勾选 |
| 3 | 2025-03-01 开局 | world meta / smoke | HUD 日期 | 通过 |
| 4 | 界面时间流逝 | — | 开局后看 UTC 变化 | 待编辑器勾选 |
| 5 | UTC + 当地时间 | TZ DST 表 | 对比 PVG/ATL | 通过（数据） |
| 6 | 航班检索+多条件筛选 | — | 票价/时长/公务/未访问 | 待编辑器勾选 |
| 7 | 未起飞均可购；&lt;2h 灰色且默认聚焦 ≥2h | smoke + 数据 | 购票面板 | 通过（规则） |
| 8 | 公务舱 ×10 | `test_business_is_10x` + smoke | 购票 | 通过 |
| 9 | 公务舱 60kg | economy.yaml | HUD 行李额度 | 通过 |
| 10 | 行李+10/20/50 与货运 | `test_baggage_tiers_*` + smoke | 航班/市场加购 | 通过 |
| 11 | 加速至起飞 | — | 二次确认后跳跃 | 代码具备；待编辑器勾选 |
| 12 | 强制登机 | — | 等到起飞/加速后 | 代码具备；待编辑器勾选 |
| 13 | 5s 升空-巡航-降落 | — | 过场三段文案+SFX+几何动效 | 通过（代码）；正式插画仍为 D1 |
| 14 | 采购特色商品 | smoke | 市场 | 通过 |
| 15 | 行李重量 | — | HUD 重量条 | 代码具备；待编辑器勾选 |
| 16 | 抵达出售 | smoke | 库存出售 | 通过 |
| 17 | 价差可解释 | smoke buy/sell | 产地 vs 远端 | 通过 |
| 18 | 每城≥5 商品+简介 | content tests | 城市页 | 通过 |
| 19 | 存档时间/位置/资金/库存/旅行 | smoke 字段 | 存档/读档 | 通过（字段）；待编辑器勾选 |
| 20 | 1080p≈60FPS | 航线绘制上限 24 | 编辑器 Profiler | 见下方 FPS 注记 |
| 21 | 数据来源页 | attribution + fonts | 「数据来源」 | 通过 |
| 22 | 重建声明 | disclaimer | 底栏 disclaimer | 通过 |

## Theme / 美术占位符完成说明

- [`game/themes/DemoColors.gd`](../../game/themes/DemoColors.gd) — CAS §1.1.1 色板  
- [`game/themes/ThemeFactory.gd`](../../game/themes/ThemeFactory.gd) — Panel/Button/LineEdit/ItemList StyleBoxFlat  
- [`game/themes/IconFactory.gd`](../../game/themes/IconFactory.gd) — CAS §1.2.E 图标代码占位符（ImageTexture）  
- 字体：`game/assets/fonts/NotoSansSC-Regular.otf`、`JetBrainsMono-Regular.ttf`（OFL）  
- [`MainHUD.gd`](../../game/scripts/ui/MainHUD.gd) 运行时 `theme = ThemeFactory.build()`；琥珀 CTA / 警告倒计时 / disclaimer 次要色；过场 `_play_transition_fx`  
- [`GlobeController.gd`](../../game/scripts/render/GlobeController.gd) — 大洲近似贴图、Pin、经纬网格、行程飞机三角标记  

素材真源与 D1 待交付清单见 [`CONTENT_ASSET_SPEC.md`](../../CONTENT_ASSET_SPEC.md) §0.5。
## FPS 注记（§27.20）

- 实现侧：`GlobeController.draw_routes_from` 同时绘制航线 **≤24**；机场点 20。  
- 建议手测：1280×720 或拉伸至 1080p，编辑器 Debugger → Profiler，地球漫游 10s，目标约 60FPS。  
- 本收口在自动化环境记录：Godot 4.7.1 headless 主场景加载成功（`DataService` 20 airports）；未在 CI 机上跑 GPU Profiler——发布前请在目标桌面机补一笔 Profiler 截图/备注。

## 命令

```bash
source etl/.venv/bin/activate
pytest tests/etl tests/game -q
python tools/demo_smoke_logic.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeContent.gd
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

## 手工完整剧本

新档 → 随机机场 → 市场买本地特产 → 航班筛选 → 经济/公务购票（可选行李）→ 加速确认 → 过场三段 → 目的地出售 → 存档读档 → 打开数据来源。

## 验证清单关闭

原六维修复项（退票替换、FF 确认、品质老化、行李三档、航班分页、未开局守卫、多日需求恢复、旅行记录货值、市场加购、倒计时 clamp、双击聚焦、规则单测）已在代码与 `tests/etl/test_game_rules.py` / smoke 中落地。后续回归以本表为准。
