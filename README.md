# 《万里行商》Wanli Trader

**全球旅行模拟 · 轻度商业经营 · 地理探索**

基于真实世界机场、航空网络、城市文化与商品价格差异构建的离线单机游戏。玩家在全球枢纽间穿梭，读城市、买特产、选航班、异地套利——把航空网络与地理知识组合成可持续探索的「世界旅行沙盘」。

> 航班网络基于公开航空数据重建，不代表真实购票信息。

Windows 与 macOS 桌面版下载：[GitHub Releases](https://github.com/Zerong-Sun/flyyy/releases/latest)。 当前桌面版 v0.5.0 提供「午夜港口 · Dark」和「电光集市 · Light」，可在游戏设置中切换。Windows 解压后运行 `WanliTrader.exe`，并保留同目录的 `.pck` 文件；macOS 解压后运行 `WanliTrader.app`。macOS 版本为通用架构，支持 Apple Silicon 与 Intel。当前桌面包没有开发者证书公证，首次打开如被系统拦截，请在“系统设置 → 隐私与安全性”中选择“仍要打开”。发布包附有 SHA-256 校验文件。

---

## 游戏立意

### 我们在做什么

《万里行商》的核心价值**不是**复杂的企业经营或真实订票，而是：

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

### 游戏模式

- **沙盒模式** — 无固定结束时间，持续环球旅行（Demo 默认）  
- **15 日挑战** — 按净资产、访问城市数、飞行距离等结算
- **收集模式** — 专注城市、商品和图鉴收集

### 初始条件

- Godot：起始资金 **$50,000**，标准托运行李 20 kg、随身 5 kg。
- 手机端：起始资金 **$6,944**，标准行李 23 kg、货运容量 50 kg；使用独立的轻量平衡配置。

---

## 当前版本

| 客户端 | 范围 | 说明 |
|--------|------|------|
| **Godot 4.7**（桌面主客户端） | 500 个机场、2500 件商品 | 3D 地球、航班、贸易、存档与双外观；[v0.5.0 Windows / macOS 下载](https://github.com/Zerong-Sun/flyyy/releases/tag/v0.5.0) |
| **React Native / Expo SDK 54**（[`ios/expo/`](ios/expo/)） | 20 座枢纽、精选商品 | 可玩的手机端：地球、市场、航班、行李、交易记录、成就、音效、存档与双外观；目前通过 Expo Go 本地预览 |

Expo Go 是开发预览容器，不是《万里行商》的手机版安装包。`ios/expo/app.json` 的 `1.1.0` 是源代码版本；尚未发布新的 iOS / Android 安装包。当前公开的 v0.5.0 Release 仅包含 Windows 和 macOS。

**首版里程碑验收 = 可玩 Demo（PRD §27）**  
对照表：[docs/superpowers/plans/2026-07-26-demo-acceptance.md](docs/superpowers/plans/2026-07-26-demo-acceptance.md)  
阶段一地图门控：[docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md](docs/superpowers/plans/2026-07-26-map-prototype-acceptance.md)

v0.2 扩展（500+ 城市、联程、价格锚点、成就等）见 [docs/v0.2_REQUIREMENTS.md](docs/v0.2_REQUIREMENTS.md)。  
iOS Expo M2 验收：[docs/superpowers/plans/2026-08-01-ios-expo-m2-acceptance.md](docs/superpowers/plans/2026-08-01-ios-expo-m2-acceptance.md)。  
下一步全周期（v0.3 / M3 / v1.0）：[docs/v0.3_REQUIREMENTS.md](docs/v0.3_REQUIREMENTS.md)、[docs/ios_expo_M3_REQUIREMENTS.md](docs/ios_expo_M3_REQUIREMENTS.md)、[docs/v1.0_GATE.md](docs/v1.0_GATE.md)。

---

## 快速开始

### 要求

- Godot 4.7.x（项目配置使用 Godot 4.7 / Forward Plus）
- Python 3.11+（ETL）  

### 1. 生成数据

```bash
cd etl
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python scripts/01_fetch_sources.py --strict
python scripts/run_pipeline.py
```

管线将校验用 SQLite 与运行时 **JSON** 写出到 `game/data/`（客户端主读 `world.json` / `flights.json`）。

### 2. 打开游戏（Godot）

用 Godot 打开 [`game/project.godot`](game/project.godot)，运行主场景。

或命令行：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path game
```

### 3. 运行手机端开发预览

```bash
cd ios/expo
npm install
npx expo start
```

安装与项目 **SDK 54** 兼容的 Expo Go，手机与电脑连接同一 Wi‑Fi，再扫描终端二维码。Expo Go 的 SDK 版本须与项目一致；如出现版本不兼容提示，参见 [Expo 官方说明](https://docs.expo.dev/troubleshooting/expo-go-version-mismatch/)。详见 [`ios/expo/README.md`](ios/expo/README.md)。

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
| BTS On-Time (DOT) | 美国国内真实航班号与计划时刻（2025-03） | 美国联邦政府公开数据 |
| AeroSCOPE 2019 (Zenodo) | 全球航线年度频次（相对归一化） | 研究用途（商用前需联系作者） |
| Wikidata | 城市人口、地理与行政区等结构化事实 | CC0 1.0 |
| 游戏原创 | 城市简介与商品 | 原创内容 |
| Noto Sans SC / JetBrains Mono | UI 字体 | OFL 1.1 |

---

## 验收

建议使用统一入口（需要已生成完整数据、Python 3.11+、Node.js 和 Godot 4.7.1）：

```bash
python3 tools/check_quality.py
python3 tools/check_quality.py --stage godot  # 修复桌面问题后，只重跑相关阶段
# 自动寻找 Godot；也可通过 GODOT_BIN 或 --godot 指定。
# 输出：dist/quality/summary.json、Python / 手机逻辑 / Godot 各场景日志。
python3 tools/test_godot.py SmokeGamedevQuality.gd SmokeSearchPerf.gd
python3 tools/test_godot.py --scenes   # 所有 Smoke + verify 场景，使用隔离存档
```

Godot 测试应通过 `tools/test_godot.py` 运行，避免直接启动回归脚本写入玩家存档；首次运行自动导入资源，`--import` 可强制重新导入。完整优化清单、来源与验收记录见 [游戏开发审阅](docs/GAMEDEV_REVIEW.md)。GitHub Actions 的 [Game quality](.github/workflows/quality.yml) 执行数据生成、逻辑测试、场景回归和双端资源打包。

`summary.json` 只记录本次调用：全阶段通过为 `passed`，`--stage` 局部通过为 `partial`，失败为 `failed`；中断会保留 `running`，环境检查未完成为 `preflight`。不能把旧日志或局部通过视为全量验收。六方面复核与修复证据见 [验证修复清单](docs/VERIFICATION_FIXLIST.md)。

```bash
source etl/.venv/bin/activate
pytest tests/etl tests/game -q
python tools/demo_smoke_logic.py
python tools/test_godot.py SmokeChallenge.gd SmokeConnectionContract.gd SmokeCollector.gd
python tools/test_godot.py SmokeCodex.gd SmokeReputation.gd SmokeV3Loop.gd
python tools/test_godot.py SmokeContent.gd SmokeAudio.gd SmokePerf.gd
# 城市正文 en 由 ETL 生成（Demo 20 手写 + 其余模板），已挂入 run_pipeline：
python -m etl.content.city_content_en      # 单独重打 game/data/world.json 的 *_en 字段
```

手工剧本与 §27 二十二条见 [demo-acceptance.md](docs/superpowers/plans/2026-07-26-demo-acceptance.md)。

---

## 架构

- `etl/` — Python 管线 → SQLite（校验）+ JSON（运行时）  
- `game/` — Godot 客户端（只读 `game/data/*.json`）  
- `ios/expo/` — React Native / Expo 手机客户端（当前提供开发预览）
- `game/themes/` — Demo Theme / CAS 色板  
- `PRD_01.md` — 完整产品需求  
- `docs/CONTENT_ASSET_SPEC.md` — 美术 / 音乐 / 文本规格  

桌面项目配置为 Godot 4.7 / Forward Plus；手机端使用 React Native / Expo SDK 54。桌面与手机端的实现、存档兼容及验证命令见 [升级说明](docs/DESKTOP_MOBILE_UPGRADE.md)。
