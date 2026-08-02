# 双轨合并评估决议 — iOS Expo（M3 · M1）

| 字段 | 内容 |
|------|------|
| 日期 | 2026-08-02 |
| 前置 | M2 已关闭（`docs/ios_expo_M2_REQUIREMENTS.md` §13 决议 4：「M2 维持双轨；合并评估 → M3」） |
| 决议 | **统一到 `ios/expo/` 单一移动端工程；不引入、不维护根目录 `expo-go/`** |

## 1. 事实核查

| 轨 | 位置 | 现状 |
|----|------|------|
| Expo Go 手机 Demo | `ios/expo/` | React Native + Expo SDK 54，20 枢纽，可玩，本仓库唯一移动端代码工程 |
| 设计稿原型 | `ios/Airborne Trader iOS.dc.html` | Design Canvas 导出的静态 HTML 视觉稿（非代码，只读参考） |
| 根目录 `expo-go/`（30 城快照） | — | **在 git 历史中从未存在**；仅旧文档出现过该路径，系规划期误写 |

`git log --all -- expo-go/` 无任何提交；`rg expo-go` 命中均为需求/验收文档中的历史引用。

## 2. 结论与决策

1. **单一工程**：移动端以 `ios/expo/` 为准，作为唯一可交付物。后续一切移动端开发（M3 及之后）只在此工程推进。
2. **废弃 `expo-go/` 路径**：旧文档中「与根目录 `expo-go/`（30 城快照）合并」的描述作废，无对应实体。
3. **HTML 设计稿定位**：`ios/Airborne Trader iOS.dc.html` 保持为视觉参考，不作为可运行版本，也不做同步维护（需要真机验证一律走 `ios/expo/`）。
4. **内容同步策略**：桌面 Godot 与移动端共享 `game/data/world.json` 语义；`ios/expo/` 通过 `tools/export_expo_data.py` 生成管线快照（`ios/expo/data/ios-data.json`）+ `src/gameData.js` 可玩内容层。移动端不再并行维护第二份游戏逻辑代码。

## 3. 落地动作（本次已完成）

- 扩城至 20 枢纽：`ios/config/expo_hubs.json`、`src/gameData.js`、`src/assets.js`、`ios/assets/city_*.webp`
- 本决议文档登记（本文件）
- `docs/ios_expo_M2_REQUIREMENTS.md` §13 决议 4 状态 → 已关闭（由本文档替代）

## 4. 遗留

- 如需 App Store 正式发布，再评估 `ios/expo/` 内的原生配置（见 M3 P1 EAS 三档 profile 与 `eas.json`）。
