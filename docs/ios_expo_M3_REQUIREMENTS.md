# 《环球航商》iOS Expo — M3 需求规格（规划）

| 字段 | 内容 |
|------|------|
| 文档编号 | REQ-ios-expo-M3 |
| 版本 | v0.1（规划） |
| 前置 | M2 已关闭（见 [2026-08-01-ios-expo-m2-acceptance.md](superpowers/plans/2026-08-01-ios-expo-m2-acceptance.md)） |
| 启动条件 | 桌面 v0.3 MVP（经停/MCT/延误/头等）可玩后 |
| 状态 | 规划中（本里程碑不强制实现代码） |

## 1. 目标一句话

把手机 Demo 从「12 枢纽可对外试玩」升级为 **20–30 枢纽 + BGM + 可选中英 UI**，并评估与根目录 `expo-go/` 双轨合并。

## 2. In Scope

| # | 能力 | 优先级 |
|---|------|--------|
| A1 | BGM：`globe_day` / `market` / `menu` / `night` → AAC 入库 `ios/expo/assets/audio/bgm/` | P0 |
| C1 | 扩城 20–30：`export_expo_data.py` + Metro `assets.js` 校验 | P0 |
| I1 | i18n 开关（UI 英/中；结构预留） | P1 |
| M1 | `expo-go/` 双轨合并评估报告（合并或废弃其一） | P1 |
| P1 | EAS Development/Preview 稳定化 + TestFlight 说明 | P0 |
| T1 | 性能预算：中端机拖转 ≥30 FPS | P1 |
| U1 | 付费情报快照 B（M2 明确推后） | P2 |

## 3. Out of Scope

- 500+ 城 / 联程 / 延误全量移植（跟桌面 v0.3 对齐后再议）
- App Store 正式上架、IAP、账号
- Lock Screen Widget / Push

## 4. 依赖与顺序

```mermaid
flowchart LR
  V03[桌面 v0.3 MVP]
  M3a[BGM + EAS]
  M3b[扩城 20-30]
  M3c[i18n + 双轨评估]
  V03 --> M3a
  M3a --> M3b
  M3b --> M3c
```

## 5. 成功标准

1. 试玩包含循环 BGM，Sound 开关有效。  
2. 枢纽 ≥20，导出管线一键可跑。  
3. 非开发同学可用 Preview/TestFlight 安装说明独立开玩。  
4. 双轨合并有明确书面决议。

## 6. 修订

| 日期 | 说明 |
|------|------|
| 2026-08-01 | 初稿：承接全周期路线图阶段 3 |
