# hero-plates 抽样审读记录

日期：2026-08-02
任务：区域底板 + 色调变体，补齐 480 城头图（v0.2 全量完成的一部分）
生成器：`tools/art-gen-kit/gen_city_plates.py`
对应计划：`docs/superpowers/plans/2026-08-02-v0.2-hero-plates.md`

## 1. 产出统计

| 指标 | 数值 |
|------|------|
| world.json 城市总数 | 500 |
| 生成头图 | 480 |
| 已有真实头图（Demo 20，未触碰） | 20 |
| 输出尺寸 | 1280×720 WebP（REQ §3.1） |
| 单张体积 | ≈41–46 KB |
| 总体积 | ≈21.8 MB |
| 缺失头图城市 | **0** |
| 幂等性 | 两次 `--force` 重生成字节一致；`--dry-run` 稳定 0 缺失 |

## 2. 区域底板覆盖

pipeline 原 `COUNTRY_REGION` 覆盖 9 区域 69 国；生成器扩展映射覆盖 **145 国全部国家码**，
`global` 兜底仅 0 城（博茨瓦纳 BW 初始遗漏 3 城，已补入 africa）。

| 区域 | 生成数 | 区域 | 生成数 |
|------|-------:|------|-------:|
| europe | 110 | north_america | 47 |
| africa | 73 | middle_east | 41 |
| east_asia | 48 | south_america | 43 |
| southeast_asia | 32 | south_asia | 32 |
| central_asia | 18 | caribbean | 16 |
| oceania | 9 | pacific_islands | 6 |
| central_america | 2 | | |

## 3. 抽样审读（16 城天空主色）

| 城市 | 国家 | 区域 | 天空主色 |
|------|------|------|----------|
| west_island | CC | pacific_islands | #3f6274 |
| brazzaville | CG | africa | #5b4848 |
| matoury | GF | south_america | #3d5656 |
| accra | GH | africa | #5b4244 |
| imphal | IN | south_asia | #584458 |
| siliguri | IN | south_asia | #614a60 |
| kumamoto | JP | east_asia | #3d505d |
| blantyre | MW | africa | #564440 |
| kota_kinabalu | MY | southeast_asia | #38605e |
| ilorin_ogbomosho | NG | africa | #5e4946 |
| evenes | NO | europe | #444f65 |
| asunción | PY | south_america | #42595b |
| doha | QA | middle_east | #554a5a |
| bosaso | SO | africa | #584344 |
| boise | US | north_america | #46586e |
| spokane | US | north_america | #3d4b64 |

**结论：**
- 跨区域差异明显：非洲暖红褐 / 东亚冷钢蓝 / 北美蓝灰 / 南美青绿 / 中东紫褐 / 太平洋青蓝。
- 区域内可辨：africa 抽样 5 城天空 RGB 离散（如 accra #5b4244 vs blantyre #564440 vs
  ilorin #5e4946），加上每城天际线布局/剪影层数/圆盘位置均随 seed 不同，肉眼可辨。

## 4. 视觉要点

- 构图：天空垂直渐变 + 低悬日/月圆盘 + 远景低平带 + 中景区域风剪影（欧式尖顶/中东圆顶/
  东亚楼阁/北美塔楼…）+ 近景地面渐变带 + 轻微颗粒 + 底部 20% 安全区压暗。
- 配色取自既有 Demo 头图主色采样（暖杏/青碧/冷钢），与 A2 真实插画风格衔接。
- 无文字、无水印、无商标；纯几何剪影，无版权风险。

## 5. 问题与修正

| 问题 | 修正 |
|------|------|
| `--force` 曾覆盖 Demo 20 真实头图 | 新增 `PROTECTED_CITY_IDS`，`--force` 也不覆盖；从 git 恢复 20 张原图 |
| africa 区域内天空色过于接近 | 天空 top/bottom 独立色相抖动 ±0.05 + 亮度 ±0.1，区域内可辨 |
| 联系表依赖 `plan` 非空（默认模式为空） | 改为从全部非保护城市独立抽样渲染 |

## 6. 验收结论

- [x] `game/assets/cities/city_*_hero_720.webp` = 500（480 新增 + 20 既有）
- [x] 480 张新增：1280×720、WebP、RGB、无水印
- [x] 幂等：重跑零变更（字节一致）
- [x] `attribution_zh.txt` 已含程序生成过渡资产条款
- [x] `pytest` 全绿（80 passed, 3 skipped）
- [x] 抽样同区域可辨、跨区域差异明显、无脏像素

## 7. 遗留

- 区域底板为「临时通用」过渡资产，后续版本逐步替换为城特定插画（REQ §3.1 / P1）。
- 联系表：`game/assets/cities/_sheets/hero_plates_contact.png`（不入 git，可 `--contact-sheet N` 重新生成）。
