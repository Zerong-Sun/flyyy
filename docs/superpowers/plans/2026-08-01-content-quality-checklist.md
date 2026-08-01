# 500 城内容品质抽检规程（v0.3 品质支线）

| 字段 | 内容 |
|------|------|
| 关联 | [2026-08-01-quality-polish.md](2026-08-01-quality-polish.md) · CAS §3 |
| 状态 | 规程已立；人工抽检按批执行 |

## 规程

1. 从 `world.json` `cities` 按 `content_confidence` 分层抽样：每批抽 **≥10%**，且 Demo 20 枢纽全量审读。  
2. 审读字段：七字段字数下限、语气、禁歧视/政治动员、`source_ids` 是否齐全。  
3. C 置信度城：百科页须显示「资料不足」等价提示（`content_confidence == "C"`）。  
4. 记录写入 `docs/superpowers/reviews/YYYY-MM-DD-content-sample.md`（缺陷列表 + 通过数）。  

## 本切片自动化门禁

- `coverage_report.missing_content_count`（当前管线默认 50 城为 0）  
- `has_souvenir_category == false`  
- Demo smoke + `test_v3_aviation`

## 性能 LOD 核对

| 项 | 代码位置 | 目标 |
|----|----------|------|
| 航线同时绘制 | `GlobeController` ≤24 | 保持 |
| 标签 | HUD / pin 策略 | ≤200 |
| 地球贴图 | 优先 4K，回退 2K | `generate_earth_albedo.py --size 4096` |

手测：1080p Profiler 截图放入 reviews（发布前）。
