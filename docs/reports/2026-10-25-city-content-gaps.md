# 城市文案缺口：基线与修复

## 本次修复

- 游戏当前 500 座城市均有对应的 `etl/content/cities/{city_id}.json` 文案源文件；七个正文栏位均非空，已移除旧占位句。
- 原 257 座 C 级城市已补入基于 Wikidata 地点资料、机场资料与明确标为国家或地区背景的饮食内容；12 座资料较少的城市另写了有出处的地方史。原有 162 座 B 级城市也重新生成了正文，并修正了纽瓦克、杜勒斯、杰贝阿里、亚历山大四处定位模糊的条目。最终为 A 级 81、B 级 419、C 级 0。
- 天津已改用中文名和专属的历史、海河地理、港口经济、津味早点、杨柳青年画内容。
- 按航线连接度选择 100 座重点城市，并强制纳入天津，加入 Wikimedia Commons 实景图。每张图的作者、许可和原始页面见 `game/assets/cities/photo_credits.json`；城市页也显示署名及来源、许可入口。两组同一都会区机场共用城市景观图，因此 100 座城市对应 98 个不同的原图文件。
- 旧 [CSV](2026-10-25-city-content-gaps.csv) 留作修复前的缺口快照，不再代表当前状态。
- 验证：`run_pipeline.py --full` 报告 `missing_content_count: 0`；ETL 定向测试 16 项通过；Godot `SmokeUI.gd` 与 `SmokeContent.gd` 通过。后者实际加载了天津照片。

文案重建：`python3 etl/scripts/fetch_wikidata_facts.py`、`python3 etl/scripts/fill_current_city_gaps.py --refresh-b`、`python3 etl/scripts/run_pipeline.py --full`。照片导入：`python3 etl/scripts/import_city_photos.py`。结构化人口数据可能来自不同统计年份；缺少城市级饮食资料时，正文明确写为国家或地区饮食背景。

## 修复前基线

- 游戏收录 500 城；A 级 81、B 级 162、C 级 257。
- 257 座 C 级城市有通用占位文案，但没有该城专属的 `etl/content/cities/{city_id}.json` 文件；七字段没有字面空值。完整名单见 [CSV](2026-10-25-city-content-gaps.csv)。
- 243 座 A/B 级城市均有对应源文件。`world.json` 的 `has_content_file` 对 B 级城市仍标为 `false`，不能用它判断文案是否缺失。
- 257 座 C 级城市中，修正天津后仍有 256 座的 `name_zh` 以拉丁字母开头；这也是独立的地名翻译缺口。
- 天津（TSN）属于 C 级：目前城市页展示的是通用航线节点描述和“更多细节将在后续内容更新中扩展”。

## 中国大陆待补文案（29 城）

| IATA | 城市（当前显示名） | city_id |
|---|---|---|
| KWL | Guilin (Lingui)（中国） | `guilin_(lingui)` |
| KWE | Guiyang (Nanming)（中国） | `guiyang_(nanming)` |
| XNN | Haidong (Huzhu Tu Autonomous County)（中国） | `haidong_(huzhu_tu_autonomous_c` |
| TXN | Huangshan（中国） | `huangshan` |
| SWA | Jieyang (Rongcheng)（中国） | `jieyang_(rongcheng)` |
| TNA | Jinan (Licheng)（中国） | `jinan_(licheng)` |
| LHW | Lanzhou (Yongdeng)（中国） | `lanzhou_(yongdeng)` |
| LJG | Lijiang（中国） | `lijiang` |
| NKG | Nanjing（中国） | `nanjing` |
| NNG | Nanning (Jiangnan)（中国） | `nanning_(jiangnan)` |
| NGB | Ningbo（中国） | `ningbo` |
| TAO | Qingdao (Jiaozhou)（中国） | `qingdao_(jiaozhou)` |
| SYX | Sanya (Tianya)（中国） | `sanya_(tianya)` |
| SHA | Shanghai (Minhang)（中国） | `shanghai_(minhang)` |
| LXA | Shannan (Gonggar)（中国） | `shannan_(gonggar)` |
| SHE | Shenyang（中国） | `shenyang` |
| SZX | Shenzhen（中国） | `shenzhen` |
| SJW | Shijiazhuang（中国） | `shijiazhuang` |
| TYN | Taiyuan（中国） | `taiyuan` |
| TSN | 天津 | `tianjin` |
| WNZ | Wenzhou (Longwan)（中国） | `wenzhou_(longwan)` |
| WUH | Wuhan (Huangpi)（中国） | `wuhan_(huangpi)` |
| WUX | Wuxi（中国） | `wuxi` |
| XIY | Xi'an（中国） | `xi'an` |
| XMN | Xiamen（中国） | `xiamen` |
| YNT | Yantai（中国） | `yantai` |
| YCU | Yuncheng (Yanhu)（中国） | `yuncheng_(yanhu)` |
| ZUH | Zhuhai (Jinwan)（中国） | `zhuhai_(jinwan)` |
| URC | Ürümqi（中国） | `ürümqi` |

## 文本需求位置

- `docs/v0.2_REQUIREMENTS.md` §2.1.1、§2.3：L2 重点城市定义、七字段字数、来源、置信度与 C 级提示。
- `PRD_01.md` §13.2–13.4：城市字段、简介长度和内容来源。
- 实际源文件：`etl/content/cities/{city_id}.json`；生成后的运行时数据：`game/data/world.json` 的 `cities`。
- 当前 ETL 缺文件时会在 `etl/scripts/run_pipeline.py` 的 `load_city_blurb()` 中生成 C 级占位内容；`build_coverage_report()` 将 C 级城市列入 `missing_content_cities`。
