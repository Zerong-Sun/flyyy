# 500 城内容品质抽检 — 20260806

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

## 抽样明细（seed=20260806）

- `aguascalientes` · Aguascalientes · conf=C · PASS
- `akureyri` · Akureyri · conf=C · PASS
- `al_jawf` · Al-Jawf · conf=C · PASS
- `amsterdam` (demo hub) · Amsterdam · conf=A · PASS
- `asaba` · Asaba · conf=C · PASS
- `atlanta` (demo hub) · Atlanta · conf=A · PASS
- `bandar_abbas` · Bandar Abbas · conf=C · PASS
- `bangkok` (demo hub) · Bangkok · conf=A · PASS
- `beijing` (demo hub) · Beijing · conf=A · PASS
- `belgrade` · Belgrade · conf=A · PASS
- `bilbao` · Bilbao · conf=C · PASS
- `bodø` · Bodø · conf=C · PASS
- `bosaso` · Bosaso · conf=C · PASS
- `brasília` · Brasília · conf=A · PASS
- `bratislava` · Bratislava · conf=A · PASS
- `broome` · Broome · conf=C · PASS
- `buffalo` · Buffalo · conf=C · PASS
- `burbank` · Burbank · conf=C · PASS
- `bâle___mulhouse` · Bâle / Mulhouse · conf=C · PASS
- `changchun` · Changchun · conf=C · PASS
- `changsha_(changsha)` · Changsha (Changsha) · conf=C · PASS
- `chicago` (demo hub) · Chicago · conf=A · PASS
- `chiclayo` · Chiclayo · conf=C · PASS
- `ciudad_del_este` · Ciudad del Este · conf=C · PASS
- `dalaman` · Dalaman · conf=C · PASS
- `dallas` (demo hub) · Dallas · conf=A · PASS
- `denver` (demo hub) · Denver · conf=A · PASS
- `djanet` · Djanet · conf=C · PASS
- `dubai` (demo hub) · Dubai · conf=A · PASS
- `edinburgh` · Edinburgh · conf=C · PASS
- `faro` · Faro · conf=C · PASS
- `fort_de_france` · Fort-de-France · conf=C · PASS
- `fortaleza` · Fortaleza · conf=C · PASS
- `frankfurt` (demo hub) · Frankfurt · conf=A · PASS
- `gaborone` · Gaborone · conf=A · PASS
- `groningen` · Groningen · conf=C · PASS
- `guangzhou` (demo hub) · Guangzhou · conf=A · PASS
- `göteborg` · Göteborg · conf=C · PASS
- `hagåtña` · Hagåtña · conf=C · PASS
- `hargeisa` · Hargeisa · conf=C · PASS
- `hartford` · Hartford · conf=C · PASS
- `hong_kong` (demo hub) · Hong Kong · conf=A · PASS
- `istanbul` (demo hub) · Istanbul · conf=A · PASS
- `joão_pessoa` · João Pessoa · conf=C · PASS
- `kaliningrad` · Kaliningrad · conf=C · PASS
- `kano` · Kano · conf=C · PASS
- `karachi` · Karachi · conf=A · PASS
- `kingston` · Kingston · conf=A · PASS
- `kochi` · Kochi · conf=C · PASS
- `kuching` · Kuching · conf=C · PASS
- `kumamoto` · Kumamoto · conf=C · PASS
- `köln_(cologne)` · Köln (Cologne) · conf=C · PASS
- `laguindingan` · Laguindingan · conf=C · PASS
- `london` (demo hub) · London · conf=A · PASS
- `los_angeles` (demo hub) · Los Angeles · conf=A · PASS
- `maiquetía` · Maiquetía · conf=A · PASS
- `miami` (demo hub) · Miami · conf=A · PASS
- `nuuk` · Nuuk · conf=A · PASS
- `osaka` · Osaka · conf=C · PASS
- `paris` (demo hub) · Paris · conf=A · PASS
- `seoul` (demo hub) · Seoul · conf=A · PASS
- `shanghai` (demo hub) · Shanghai · conf=A · PASS
- `siddharthanagar_(bhairahawa)` · Siddharthanagar (Bhairahawa) · conf=C · PASS
- `singapore` (demo hub) · Singapore · conf=A · PASS
- `skardu` · Skardu · conf=C · PASS
- `tehran` · Tehran · conf=A · PASS
- `tokyo` (demo hub) · Tokyo · conf=A · PASS
- `zhezkazgan` · Zhezkazgan · conf=C · PASS
- `şanlıurfa` · Şanlıurfa · conf=C · PASS

## 缺陷清单

无（首批全通过）

## 备注

- C 置信度城须在百科页显示「资料不足」提示：当前数据集 400 座 C 城；UI 已支持（MainHUD._show_city）。C 城模板文案豁免字数下限，但须保持字段非空（见 check_fields）。
- `source_ids` 已随 v0.2 落地：所有城均有非空 `source_ids`（ourairports / openflights 引用）。
