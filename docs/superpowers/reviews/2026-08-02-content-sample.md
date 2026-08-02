# 500 城内容品质抽检 — 20260802

**规程：** [2026-08-01-content-quality-checklist](../../superpowers/plans/2026-08-01-content-quality-checklist.md)

## 摘要

| 指标 | 值 |
|------|-----|
| 城市总数 | 500 |
| 抽样数（≥10%） | 69 |
| 抽样率 | 13.8% |
| Demo 20 枢纽 | 20/20 覆盖 |
| PASS | 69 |
| ISSUE | 0 |

## 抽样明细（seed=20260802）

- `abu_dhabi` · Abu Dhabi · conf=A · PASS
- `ad_dammam` · Ad Dammam · conf=C · PASS
- `aguascalientes` · Aguascalientes · conf=C · PASS
- `ahvaz` · Ahvaz · conf=C · PASS
- `akureyri` · Akureyri · conf=C · PASS
- `al_jawf` · Al-Jawf · conf=C · PASS
- `algiers` · Algiers · conf=A · PASS
- `almaty` · Almaty · conf=A · PASS
- `amsterdam` (demo hub) · Amsterdam · conf=A · PASS
- `aomori` · Aomori · conf=C · PASS
- `apia` · Apia · conf=A · PASS
- `atlanta` (demo hub) · Atlanta · conf=A · PASS
- `bangkok` (demo hub) · Bangkok · conf=A · PASS
- `bangui` · Bangui · conf=A · PASS
- `barnaul` · Barnaul · conf=C · PASS
- `barranquilla` · Barranquilla · conf=C · PASS
- `batam` · Batam · conf=C · PASS
- `beijing` (demo hub) · Beijing · conf=A · PASS
- `belo_horizonte` · Belo Horizonte · conf=C · PASS
- `birmingham,_west_midlands` · Birmingham, West Midlands · conf=C · PASS
- `bobo_dioulasso` · Bobo Dioulasso · conf=C · PASS
- `bridgetown` · Bridgetown · conf=A · PASS
- `burgas` · Burgas · conf=C · PASS
- `béjaïa` · Béjaïa · conf=C · PASS
- `calicut` · Calicut · conf=C · PASS
- `cebu_city_lapu_lapu_city` · Cebu City/Lapu-Lapu City · conf=C · PASS
- `chicago` (demo hub) · Chicago · conf=A · PASS
- `chihuahua` · Chihuahua · conf=C · PASS
- `chongqing` · Chongqing · conf=C · PASS
- `cochabamba` · Cochabamba · conf=C · PASS
- `dallas` (demo hub) · Dallas · conf=A · PASS
- `dar_es_salaam` · Dar es Salaam · conf=A · PASS
- `denver` (demo hub) · Denver · conf=A · PASS
- `dubai` (demo hub) · Dubai · conf=A · PASS
- `dushanbe` · Dushanbe · conf=A · PASS
- `düsseldorf` · Düsseldorf · conf=C · PASS
- `edremit` · Edremit · conf=C · PASS
- `el_aaiún` · El Aaiún · conf=C · PASS
- `frankfurt` (demo hub) · Frankfurt · conf=A · PASS
- `funchal` · Funchal · conf=C · PASS
- `goiânia` · Goiânia · conf=C · PASS
- `guadalajara` · Guadalajara · conf=A · PASS
- `guangzhou` (demo hub) · Guangzhou · conf=A · PASS
- `gurandani` · Gurandani · conf=C · PASS
- `guwahati` · Guwahati · conf=C · PASS
- `haiphong_(hai_an)` · Haiphong (Hai An) · conf=C · PASS
- `harbin` · Harbin · conf=C · PASS
- `hong_kong` (demo hub) · Hong Kong · conf=A · PASS
- `hyderabad` · Hyderabad · conf=C · PASS
- `iquitos` · Iquitos · conf=C · PASS
- `istanbul` (demo hub) · Istanbul · conf=A · PASS
- `ivalo` · Ivalo · conf=C · PASS
- `jaipur` · Jaipur · conf=C · PASS
- `kailua_kona` · Kailua-Kona · conf=C · PASS
- `kochi` · Kochi · conf=C · PASS
- `london` (demo hub) · London · conf=A · PASS
- `los_angeles` (demo hub) · Los Angeles · conf=A · PASS
- `lubumbashi` · Lubumbashi · conf=C · PASS
- `miami` (demo hub) · Miami · conf=A · PASS
- `miyazaki` · Miyazaki · conf=C · PASS
- `orio_al_serio_(bg)` · Orio al Serio (BG) · conf=C · PASS
- `paris` (demo hub) · Paris · conf=A · PASS
- `qeshm(dayrestan)` · Qeshm(Dayrestan) · conf=C · PASS
- `seoul` (demo hub) · Seoul · conf=A · PASS
- `shanghai` (demo hub) · Shanghai · conf=A · PASS
- `singapore` (demo hub) · Singapore · conf=A · PASS
- `tokyo` (demo hub) · Tokyo · conf=A · PASS
- `tunoshna` · Tunoshna · conf=C · PASS
- `willemstad` · Willemstad · conf=C · PASS

## 缺陷清单

无（首批全通过）

## 备注

- C 置信度城须在百科页显示「资料不足」提示：当前数据集 400 座 C 城；UI 已支持（MainHUD._show_city）。C 城模板文案豁免字数下限，但须保持字段非空（见 check_fields）。
- `source_ids` 已随 v0.2 落地：所有城均有非空 `source_ids`（ourairports / openflights 引用）。
