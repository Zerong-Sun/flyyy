# 《环球航商》Airborne Trader

**全球旅行模拟 · 轻度商业经营 · 地理探索**

基于真实世界机场、航空网络、城市文化与商品价格差异构建的离线单机游戏。玩家在全球枢纽间穿梭，读城市、买特产、选航班、异地套利——把航空网络与地理知识组合成可持续探索的「世界旅行沙盘」。

> 航班网络基于公开航空数据重建，不代表真实购票信息。

---

## 游戏立意

### 我们在做什么

《环球航商》的核心价值**不是**复杂的企业经营或真实订票，而是：

- **用真实航线约束旅行** — 每一次移动都依赖实际存在或合理重建的航线，不能点击城市直接传送；
- **用地理与特产驱动探索** — 每座城市有简介、当地商品与可解释的价格差异，鼓励「下一座城卖什么更划算」；
- **用时间制造决策压力** — 世界时钟持续流逝，航班有起飞时刻，购票后可加速至登机，错过即强制出发；
- **用收集感延长单局** — 访问过的机场与城市、交易记录、成就与图鉴，让一次旅程变成数十小时的环球拼图。

产品愿景：**可旋转的真实世界航线图鉴** — 清晰、可信、略带旅途温度。

### 适合谁玩

- 喜欢世界地理、航空与旅行的玩家  
- 喜欢轻度贸易、路线规划与价格套利的玩家  
- 喜欢阅读城市文化、地方特产与地图收集的玩家  

单局体验：最短约 15 分钟完成一次买卖闭环；常规 30–90 分钟；长期目标为访问更多国家、枢纽与商品图鉴。

### 设计边界

游戏明确**不包含**：实时航班追踪、真实购票、航空公司经营、飞机驾驶、多人联机、完整海关/签证模拟，以及酒类、烟草、药品、武器等受管制商品交易。航班、票价与商品价格为历史快照或游戏模拟，不可用于现实旅行决策。

---

## 玩法

### 核心循环

```
读城市 → 买商品 → 选航班 → 加速/等待 → 登机过场 → 异地销售 → 规划下一段
```

1. **抵达机场** — 查看所在城市简介、当地时间与当地市场  
2. **采购** — 按当地价格买入特色商品；商品占用随身或托运行李重量  
3. **查航班** — 在全局航班面板检索未来出港航班（不限提前购票时间）  
4. **购票** — 选择经济舱或公务舱，可加购行李扩展或货运额度  
5. **等待或加速** — 时间持续流逝；购票后可「加速至起飞」（二次确认）  
6. **强制登机** — 到达起飞时刻自动登机，播放约 5 秒过场动画，瞬间抵达目的地  
7. **出售** — 在目的城市按当地供需与稀缺度卖出，结算利润  
8. **继续旅行** — 用利润扩大行程、解锁更多城市，重复循环  

成功的标准是：玩家会**因为下一座城市的商品、价格与航班机会，而主动规划下一段旅程**。

### 关键机制

| 机制 | 说明 |
|------|------|
| **世界时间** | 统一 UTC；界面显示各机场当地时间。现实 1 秒 = 游戏 6 分钟（1 游戏日 ≈ 4 现实分钟） |
| **舱位** | 经济舱为基础票价；公务舱约为经济舱 10 倍，行李额度为经济舱 3 倍 |
| **行李** | 默认经济舱托运 20 kg、随身 5 kg；可付费扩展 +10 / +20 / +50 kg，或使用独立货运额度 |
| **定价** | 原产地采购通常更便宜；目的地越稀缺售价越高；易腐品有保质期与品质衰减 |
| **存档** | 自动/手动保存资金、位置、库存、时间与旅行记录 |

### 游戏模式（规划）

- **沙盒模式** — 无固定结束时间，持续环球旅行（Demo 默认）  
- **30 日挑战** — 2025 年 3 月 1 日至 31 日，按净资产、访问城市数、飞行距离等结算  

### 初始条件

- 起始资金：¥50,000 等值（冻结汇率 USD/CNY=7.2 → 约 **$6,944**）  
- 标准托运行李：20 kg；随身：5 kg  

---

## 当前版本

| 客户端 | 范围 | 说明 |
|--------|------|------|
| **Godot 4.x**（主客户端） | 20 座全球客运枢纽 | 3D 地球、拟真航班、贸易闭环、存档与数据来源页 |
| **Expo Go**（[`ios/expo/`](ios/expo/)） | 12 枢纽手机 Demo | React Native，Design Canvas 原型移植，Expo SDK 54 |

**首版里程碑验收 = 可玩 Demo（PRD §27）**  
对照表：[docs/superpowers/plans/2026-07-26-demo-acceptance.md](docs/superpowers/plans/2026-07-26-demo-acceptance.md)  
阶段一地图门控：[docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md](docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md)

v0.2 扩展（500+ 城市、联程、价格锚点、成就等）见 [docs/v0.2_REQUIREMENTS.md](docs/v0.2_REQUIREMENTS.md)。

---

## 快速开始

### 要求

- Godot 4.3+（本地开发使用 4.7.x）  
- Python 3.11+（ETL）  

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

### 2. 打开游戏（Godot）

用 Godot 打开 [`game/project.godot`](game/project.godot)，运行主场景。

或命令行：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

### 3. Expo Go 手机 Demo

```bash
cd ios/expo
npm install
npx expo start
```

安装 Expo Go，手机与电脑同一 Wi‑Fi，扫描终端二维码。详见 [`ios/expo/README.md`](ios/expo/README.md)。

```bash
python3 tools/export_expo_data.py          # ETL → ios/expo/data/ios-data.json
cd ios/expo && npm test                    # 逻辑单测
# npx eas build --profile preview --platform ios   # 内测包（见 eas.json）
```

---

## 内容与资产规格

美术 / 音乐 / 文本规格见 [`docs/CONTENT_ASSET_SPEC.md`](docs/CONTENT_ASSET_SPEC.md)（**§0.5** 仓库现状）。  
基础 UI Theme：`game/themes/`（CAS 色板 + StyleBox）+ `game/assets/fonts/`（Noto Sans SC / JetBrains Mono）。地球正式贴图与过场插画仍为占位。

---

## 数据与许可证

详见游戏内「数据来源」页。主要来源：

| 来源 | 用途 | 许可 |
|------|------|------|
| OurAirports | 机场坐标 | Unlicense / 公有领域 |
| OpenFlights | 航线邻接种子 | ODbL |
| 游戏原创 | 城市简介与商品 | 原创内容 |
| Noto Sans SC / JetBrains Mono | UI 字体 | OFL 1.1 |

---

## 验收

```bash
source etl/.venv/bin/activate
pytest tests/etl tests/game -q
python tools/demo_smoke_logic.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeContent.gd
```

手工剧本与 §27 二十二条见 [demo-acceptance.md](docs/superpowers/plans/2026-07-26-demo-acceptance.md)。

---

## 架构

- `etl/` — Python 管线 → SQLite（校验）+ JSON（运行时）  
- `game/` — Godot 客户端（只读 `game/data/*.json`）  
- `ios/expo/` — Expo Go 手机 Demo  
- `game/themes/` — Demo Theme / CAS 色板  
- `PRD_01.md` — 完整产品需求  
- `docs/CONTENT_ASSET_SPEC.md` — 美术 / 音乐 / 文本规格  

引擎锁定：项目以 Godot 4.x Forward+ 为目标。
