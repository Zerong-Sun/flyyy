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
| 机场 pin | 500（低模 ArrayMesh，圆柱+球头） | `GlobeController._make_pin_mesh` / `_spawn_airports` |
| 标签同时显示 | ≤200（可配置；仅选中/当前/已访问近处） | `GlobeController._update_markers` |
| 航线同时绘制 | ≤24 条 / 源 | `GlobeController.draw_routes_from` |
| 网格 | 15° 经纬线 ImmediateMesh，远淡近显 | `GlobeController._build_grid_overlay` |
| Expo 渲染树 | ~20–30 View + 2 Image；每帧 projectPin×20 + sampleArc(≤28 点) | `ios/expo/src/components/Globe.js` |

## 3. Headless 基线（SmokePerf）

脚本：`game/scripts/dev/SmokePerf.gd`。headless 使用 dummy 渲染驱动，以 `Time.get_ticks_usec()` 测量相邻帧间隔，预热 60 帧后采样 180 帧，报告均值、p50、p95、p99。包含脚本与调度开销，不代表 GPU 帧时间；`TIME_FPS` 更新频率不足，不能充当逐帧样本。

```bash
python3 tools/test_godot.py SmokePerf.gd SmokeSearchPerf.gd
```

### 2026-08-06 首次基线

| 指标 | 值 |
|------|-----|
| 场景 + 500-pin 构建耗时 | 283 ms |
| CPU 帧预算基线（预热后均值） | 131.0 FPS（min 48.0，90 采样） |
| 每帧预算 | 7.63 ms |
| 判定 | SMOKE_PERF_OK（阈值：build ≤2000 ms，均值 ≥20 FPS） |

### 历史数据判读

- 上表保留历史记录；旧实现多次读取同一个低频刷新 FPS 值，无法据此可靠解释最低 FPS 或断言余量充足。新采样口径与旧表不直接比较。
- 当前门禁为构建 ≤2000 ms、平均间隔 ≤50 ms、p95 ≤50 ms，定位明显 CPU 回归；正式发布的 60 FPS 目标仍需下面的真机 GPU 验收。

### 本轮航班搜索对照

同一台机器、Godot 4.7.1 headless 调试进程、PVG 出港、游戏日期 2025-03-16、固定存档种子。加载航班数据后每组重复三次，报告中位数，不包含首次磁盘读取。数据集含 500 机场、1,106,026 条航班。

| 查询 | 修改前 | 首次修改后测量 | 最终验收复跑 | 结果数量 |
|---|---:|---:|---:|---:|
| 全部未来航班，按起飞排序 | 2806.014 ms | 276.471 ms | 340.508 ms | 2496 |
| LHR，按价格排序 | 1900.453 ms | 29.661 ms | 42.679 ms | 31 |
| 经济舱 ≤$500，按价格排序 | 2063.765 ms | 222.512 ms | 294.999 ms | 1666 |

三组完整结果的 SHA-256 摘要前后一致。优化为预先筛除已起飞及不匹配的航班，并缓存当前日期、当前存档的城市新闻事件。价格筛选仍在新闻报价之后；缓存返回深拷贝，换日/换存档清空。`SmokeSearchPerf.gd` 另外以旧的逐条先报价路径核对结果，避免只测速度不测正确性。

新地球采样的一次本机结果：构建 203 ms，均值 6.898 ms，p50 6.885 ms，p95 8.262 ms，p99 8.601 ms。以上属于开发机诊断数据，非手机或正式发布包的性能结论。

最终验收复跑的地球结果为构建 171 ms、均值 6.900 ms、p95 8.124 ms。不同运行之间存在调度波动；搜索复跑的完整结果摘要仍一致，不能把单次最快值视为性能保证。

## 4. 发布前手测（v1.0 前执行）

1. 以 1080p 全屏启动桌面版（正式贴图开启）。
2. 打开 Profiler（Debug → Performance），漫游 60 秒（包含远洋/近景、航线展开、标签密集区）。
3. 记录平均/最低 FPS，截图存 `docs/superpowers/reviews/`，如 `YYYY-MM-DD-perf-1080p.md`。
4. 达标判据：平均 ≥55 FPS 且最低 ≥45 FPS（接近 PRD §27 #20 的 ≈60）。

## 5. 修订

| 日期 | 说明 |
|------|------|
| 2026-08-10 | 60 FPS + VSync；新增运行配置回归门禁 |
| 2026-08-06 | 初稿：目标值 + LOD 预算 + SmokePerf headless 基线（283ms / 131 FPS） |
