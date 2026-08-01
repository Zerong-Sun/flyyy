# 品质打磨支线（贯穿 v0.3）— 清单与工具

关联路线图阶段 2；与 [CONTENT_ASSET_SPEC.md](../CONTENT_ASSET_SPEC.md) §0.5 / D1 对齐。

## 1. D1 收口

| 项 | 动作 | 状态 |
|----|------|------|
| `EARTH_ALBEDO` 4096×2048 | 升级 [`tools/generate_earth_albedo.py`](../../tools/generate_earth_albedo.py) 支持 `--size 4096`；输出 `game/assets/earth/earth_albedo_day_4k.png` | 工具升级见下方 |
| 图标 SVG 源 | 保留光栅；SVG 源目录 `game/assets/icons/_svg/` 可选补齐 | 规划 |
| 过场三帧风格统一 | 审阅 `game/assets/anim/flight_transition/` | 规划 |

## 2. 内容品质

| 项 | 动作 |
|----|------|
| 500 城抽检 | 每批 ≥10% 全字段审读；记录于 `docs/superpowers/reviews/` |
| C 置信度提示 | 百科页已有 `content_confidence`；UI 显示「资料不足」 |
| 20 城金样 | Demo 枢纽回归 smoke |

## 3. 性能 LOD

| 项 | 现状 / 目标 |
|----|-------------|
| 标签上限 | ≤200（可配置） |
| 航线同时显示 | ≤24（`GlobeController`） |
| 500 城漫游 | 实测 1080p≈60 FPS（发布前 Profiler） |

## 4. 游戏感

- 音频响度对照 CAS §2（BGM −16 LUFS 目标）
- Reduce-motion 降级粒子/闪光
- SFX 全表可播（Godot `AUDIO_MANIFEST.csv`）

## 5. 地球贴图生成（本切片落地）

```bash
# 默认 2048；v0.3 品质支线可生成 4K
python3 tools/generate_earth_albedo.py --size 4096 \
  --out game/assets/earth/earth_albedo_day_4k.png
```

`GlobeController` 优先加载 4K，缺失时回退 2K / placeholder（见工具与控制器补丁）。

## 6. 修订

| 日期 | 说明 |
|------|------|
| 2026-08-01 | 初稿 + 4K 生成开关 |
