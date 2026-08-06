# 性能基线与测量规程

| 字段 | 内容 |
|------|------|
| 关联 | `PRD_01.md` §27 #20 · `v1.0_GATE.md` §3 性能 · `2026-08-01-quality-polish.md` §3 |
| 目标 | 1080p 地球漫游 ≈60 FPS（正式贴图开启）；Expo 中端机拖转 ≥30 FPS |

## 1. 目标值

| 端 | 场景 | 目标 |
|----|------|------|
| Godot | 1080p 地球漫游（500 城 pin + 航线） | ≈60 FPS |
| Expo | 中端机地球拖转 | ≥30 FPS |

来源：`PRD_01.md` §27 第 20 条、`docs/v1.0_GATE.md` §3（性能门禁）、`docs/superpowers/reviews/2026-08-02-expo-m3-perf-u1.md`（Expo 渲染预算核对）。

## 2. LOD 与渲染预算

| 项 | 预算 | 代码位置 |
|----|------|----------|
| 地球贴图 | 优先 4K，缺失回退 2K / placeholder | `GlobeController._build_earth` |
| 机场 pin | 500（低模 ArrayMesh，圆柱+球头） | `GlobeController._make_pin_mesh` / `_build_airports` |
| 标签同时显示 | ≤200（可配置；仅选中/当前/已访问近处） | `GlobeController._update_markers` |
| 航线同时绘制 | ≤24 条 / 源 | `GlobeController.draw_routes_from` |
| 网格 | 15° 经纬线 ImmediateMesh，远淡近显 | `GlobeController._build_grid_overlay` |
| Expo 渲染树 | ~20–30 View + 2 Image；每帧 projectPin×20 + sampleArc(≤28 点) | `ios/expo/src/components/Globe.js` |

## 3. Headless 基线（SmokePerf）

脚本：`game/scripts/dev/SmokePerf.gd`。headless 使用 dummy 渲染驱动，`TIME_FPS` 度量的是 **CPU 侧帧预算**（场景构建 + 标记/LOD 更新），**不是 GPU 填充率**。

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  -s res://scripts/dev/SmokePerf.gd
```

### 2026-08-06 首次基线

| 指标 | 值 |
|------|-----|
| 场景 + 500-pin 构建耗时 | 283 ms |
| CPU 帧预算基线（预热后均值） | 131.0 FPS（min 48.0，90 采样） |
| 每帧预算 | 7.63 ms |
| 判定 | SMOKE_PERF_OK（阈值：build ≤2000 ms，均值 ≥20 FPS） |

### 判读

- 帧预算 7.63 ms < 16.7 ms（60 FPS 预算），CPU 侧余量充足；真机 GPU 瓶颈（4K 贴图采样、pin 面数）需手动 Profiler 复核。
- min 48.0 FPS 为预热期抖动，不作为达标判据；取尾段均值。

## 4. 发布前手测（v1.0 前执行）

1. 以 1080p 全屏启动桌面版（正式贴图开启）。
2. 打开 Profiler（Debug → Performance），漫游 60 秒（包含远洋/近景、航线展开、标签密集区）。
3. 记录平均/最低 FPS，截图存 `docs/superpowers/reviews/`，如 `YYYY-MM-DD-perf-1080p.md`。
4. 达标判据：平均 ≥55 FPS 且最低 ≥45 FPS（接近 PRD §27 #20 的 ≈60）。

## 5. 修订

| 日期 | 说明 |
|------|------|
| 2026-08-06 | 初稿：目标值 + LOD 预算 + SmokePerf headless 基线（283ms / 131 FPS） |
