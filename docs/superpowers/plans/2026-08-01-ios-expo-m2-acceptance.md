# iOS Expo M2 验收对照表（2026-08-01）

**里程碑：** REQ-ios-expo-M2（[`docs/ios_expo_M2_REQUIREMENTS.md`](../../ios_expo_M2_REQUIREMENTS.md)）  
**工程：** [`ios/expo/`](../../../ios/expo/) · Expo SDK 54 · 12 枢纽  
**自动化：** `cd ios/expo && node --test src/__tests__/gameLogic.test.mjs` · `pytest tests/test_expo_export.py`  
**手测日：** 2026-08-01（逻辑路径经单测；真机剧本见下方）

## §12 验收清单

| # | 标准 | 自动化 / 代码证据 | 手工 | 状态 |
|---|------|-------------------|------|------|
| 1 | 新用户：Intro → 买 → 订票 → 等待/Speed up → 落地 → 部分出售 → 再起飞 | `gameLogic` 定价/等待/行李；`useGame` 流程 | Expo Go 完整环 | 通过（代码+单测）；待真机勾选 |
| 2 | 杀进程恢复持票倒计时，到点仍自动起飞 | `saveGame` migrate/round-trip；`waitUntilDep` | 杀进程重开 | 通过（字段）；待真机勾选 |
| 3 | 落地超重有提示且货物未丢 | `overweightNote` in `useGame` / `BagsMore` | 超重落地 | 通过（代码） |
| 4 | 地球可拖、可点城、持票可见弧 | `Globe.js` 惯性；`GlobeScreen` 城卡/弧 | 真机拖转 | 通过（代码）；待真机 FPS |
| 5 | Restart 需确认；清档回伊斯坦布尔与起始现金 | Settings 确认流；`STARTING_CITY` | Settings | 通过（代码） |
| 6 | 单测全部通过；`export_expo_data` 可重复执行 | 14/14 node tests；`tools/export_expo_data.py` | — | **通过**（2026-08-01） |
| 7 | 内测包或 Expo Go 扫码说明可交给非开发同学 | [`ios/expo/README.md`](../../../ios/expo/README.md) EAS 节 | 扫码 | 通过（文档）；EAS 构建待账号执行 |
| 8 | 媒体 §9.6：必有类齐全；无音频不崩；A2 五条 SFX 可播 | `audio.js` 5 ID；`assets/audio/sfx/*.m4a` | Sound 开/关 | **通过** |

## §1.3 成功标准对照

| # | 标准 | 状态 |
|---|------|------|
| 1 | 地球拖转 + 枢纽点选；持票大圆弧 | 交付（G1/G2） |
| 2 | 行李按条目出售/丢弃；落地超重提示 | 交付（T1/T2） |
| 3 | 深度情报（关注目的地 + sparkline） | 交付（T3 A+C） |
| 4 | 存档版本迁移 + 清除确认 | 交付（S1） |
| 5 | ETL → Expo 导出路径可重复 | 交付（C1 · `export_expo_data.py`） |
| 6 | EAS 文档 + ≥8 逻辑断言 | 交付（14 条单测；EAS 说明已写） |

## §13 开放问题 — 产品决策（关闭）

| # | 问题 | 决策 | 备注 |
|---|------|------|------|
| 1 | 情报方案 A / B / A+C | **A + 轻量 C** | B 付费快照 → M3 P2 |
| 2 | 扩城是否冲 16–20 | **管线就绪即可** | 维持 12；扩城属 M3 |
| 3 | UI 语言 | **保持英文** | i18n 结构预留；中英切换 → M3 |
| 4 | 与 `expo-go/` 双轨 | **M2 维持双轨** | M3 评估合并 |
| 5 | 超重起飞是否阻断 | **不阻断** | 仅提示，与 REQ §4.2 一致 |
| 6 | A2 音频是否必须 | **必须带真·SFX** | 5 条 AAC 已入库（`d555cd5`） |

## 命令

```bash
cd ios/expo && npm install && node --test src/__tests__/gameLogic.test.mjs
python3 tools/export_expo_data.py
cd ios/expo && npx expo start          # Expo Go 扫码
# 内测包（需 Expo / Apple 账号）：
cd ios/expo && npx eas login && npx eas build --profile preview --platform ios
```

## 手工完整剧本

新档（Istanbul）→ Market 买本地货 → Flights 订经济舱 → Globe Speed up → 过场 → 落地部分出售 → Bags 丢弃确认 → 盯住目的地看 Market 排序 → Settings Restart 确认 → 清档回起点。

## EAS / 内测交接

见 [`ios/expo/README.md`](../../../ios/expo/README.md)「EAS / internal builds」与 [`eas.json`](../../../ios/expo/eas.json)：

| Profile | 用途 |
|---------|------|
| `development` | Dev Client + iOS Simulator |
| `preview` | 内部分发设备包（非 Simulator） |
| `production` | 正式上架（本里程碑不强制） |

**给非开发同学：** 优先 Expo Go 扫码（同 Wi‑Fi）；无法同网时用 `--tunnel`；需要脱离 Expo Go 时用 `preview` 包。无需登录游戏账号。

## 残余（不阻塞 M2 关闭）

- [ ] 真机 Profiler：中端机拖转 ≥30 FPS（手测截图）
- [ ] EAS preview 实际构建产物上传（需账号）
- [ ] C2 扩城 16–20（明确 Out of Scope → M3）
