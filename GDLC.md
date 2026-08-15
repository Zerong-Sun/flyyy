# GDLC Case Study — Wanli Trader (flyyy)

<!-- GDLC Wizard Version: 0.3.0 -->
<!-- GDLC Sibling SHA: 0.3.0 -->
<!-- GDLC Setup Date: 2026-08-13 -->
<!-- GDLC Last Update: 2026-08-13 -->
<!-- Completed Steps: step-0.1, step-0.2, step-0.5, step-1, step-2, step-3, step-4, step-5, step-5.5, step-6, step-7 -->

## Project Surfaces

This project runs GDLC cycles for: gameplay-matrix, pipeline-contract-audit, art-craft-review

Persona matrix pruned to cover these surfaces only. Add rows back as new surfaces come online.

## Tooling

- Test harness: pytest (tests/etl, tests/game) + node --test (ios/expo)
- e2e harness: none (no playwright) — Godot headless Smoke*.gd regressions cover end-to-end loops
- Visual-regression harness: deferred until art-craft-review cycle (not detected — art reviews rely on persona judgment)

## Earned Rules (Project-Specific)

_Rules earned through this project's playtests. When a rule recurs in a second case study, it graduates to the upstream playbook in `claude-gdlc-wizard`._

1. **Score caps must be calibrated to the play window, not the world population.** (Playtest #1) Challenge normalization caps set to world totals (500 cities / 100 countries / 800 products) made A mathematically unreachable in a 15-day window; recalibrated to window-measured excellent-play maxima (60/30/350) with a pytest winability property pinned to persona-sim benchmarks. Candidate for upstream graduation if a second case study hits it.
2. **Economies need a margin-per-kg bound, not a price-ratio bound.** (Playtest #2) A 2.5× sell/buy ratio is harmless on 20 kg of rice and game-breaking on 0.12 kg of diamonds ($53.5k/kg, $1.07M per hold); the degeneracy is margin × (1/weight), so the clamp must couple price to weight. Fixed with `margin_per_kg_cap_usd` — kills the tail, preserves median texture.
3. **Scoring config belongs in data, not literals.** (Playtest #2) Challenge caps/thresholds lived as literals in three places (Godot, pytest mirror, docs) with presence-only guards — value drift passes silently. Moved into `world.json economy.challenge` as the single source of truth read by all consumers.
4. **Selection realism over edge invention.** (Playtest #5) When a synthesis rule must guarantee connectivity, filter the roster at selection time (admit only airports with a real edge to the accepted set, greedy with re-scan so small airports join once their partners do) instead of minting synthetic edges. Result: 500 airports, 0 invented edges, single giant component, all real partners preserved.

## Playtest Ledger

_Chronological log of playtest cycles. Each entry: date, cycle type, personas, findings, ratchet delta._

### Playtest #1 — 2026-08-13 (gameplay-matrix: trade loop + 15-day challenge fairness)

- Cycle: gameplay-matrix, one roster of 5 personas, distinct instruments (headless smokes; pytest suite; independent Python market sim; aviation data audit; challenge winability sim + Expo cross-check)
- Personas: Tourist (初次玩家), Casual Traveler (休闲玩家), Trade Senior (资深商旅), Hub Purist (枢纽专家), Speedrunner (速通玩家)
- Findings: 3 P0s promoted & fixed (connection-cancel teleport; phantom minted connection flights; A-grade unreachable under world-total caps). 7 P1s + 12 P2/P3s recorded below, queued for follow-up cycles. All findings NEW (0% re-surface, first cycle).
- Ratchet delta: +1 headless smoke (`SmokeConnectionContract.gd`: real-legs contract, cancel-no-teleport, boarding origin guard); +1 pytest winability property (`test_excellent_15_day_run_scores_a`, RED 70 < 80 → GREEN 89); SmokeV3Loop updated to the real-flight connection contract; PRD §6.2 caps/thresholds documented; 30→15 day references aligned (PRD/README/CLAUDE.md).
- Earned rules: 1 candidate (window-calibrated caps).
- Queued for pipeline-contract-audit cycle: ETL `hash()` flight numbers (determinism violation), stopover airline–route fabrication, dead MCT config (75 override vs 120 intl / alliance discount), luxury-goods margin blowout (P0 claim, single-observer → downgraded P1, root cause in ETL pricing), Expo challenge-mode parity.

### Playtest #2 — 2026-08-14 (pipeline-contract-audit: determinism, data honesty, economy bounds, cross-implementation)

- Cycle: pipeline-contract-audit, one roster of 4 contract personas, distinct instruments (double-run byte diff; stopover/MCT sampling vs raw routes.dat; margin/kg distribution model; pytest↔Godot↔Expo drift matrix)
- Personas: Determinism Auditor (确定性审计员), Data-Contract Auditor (数据契约审计员), Economy Auditor (经济审计员), Cross-Implementation Auditor (跨实现审计员)
- Findings: 2 P0s (pipeline not byte-reproducible — 55 artifacts drifted; economy tail $53.5k/kg) + 2 P1s (stopover fabrication 144/144; Expo economy drift 3.5×) + 4 P2s (MCT dead config, caps literals, demand-pressure bypass, dead export bridge) — all fixed except runtime-only items queued below. 4/4 ship votes N pre-fix.
- Ratchet delta: +`tests/etl/test_pipeline_contracts.py` (8 RED tests: double-run byte-identity, margin/kg bound, stopover leg membership + antipodal cap, per-leg MCT, challenge-config-in-data, expo export block, demo mapping declaration). Pipeline: stable_rand flight numbers, sorted stopover hubs + joint-airline membership + 20,037 km cap, `airport_mct_minutes` international-first, hub tuple spellings + guangzhou, margin clamp, inherited-product seed, hot-win seed, routes sqlite sort, stopover numbers decoupled from fid. `economy.yaml`: `margin_per_kg_cap_usd` + `challenge:` block → world.json economy. ChallengeSystem.gd + pytest mirror read caps from data; expo snapshot carries the block; gameData.js declares DEMO_SCALE. Data regenerated `--full`.
- Earned rules: 2 new candidates (margin-per-kg bound; scoring config in data).
- Re-surface: determinism `hash()` + stopover + MCT + luxury goods re-verified from Playtest #1 (2 cycles, converging; fixed here). 0 net-new gameplay regressions.
- Queued: demand-pressure applied after sale (runtime, P2), `same_alliance_discount_min` dead config (apply at runtime or remove, P2), Expo full wiring of ios-data.json + challenge mode (P1 partial), same-day flight-number collisions incl. synthetic-vs-BTS (P3), `generated_at` documented exemption (sidecar optional).

### Playtest #3 — 2026-08-14 (gameplay-matrix: challenge fairness follow-ups + feedback contracts)

- Cycle: gameplay-matrix, same 5-persona roster, each re-auditing their queued findings post-P2 with a fresh instrument (smokes; call-order audit; post-clamp distribution model; live-engine MCT demo + Monte Carlo; scoring sim + calibration check)
- Personas: Tourist, Casual Traveler, Trade Senior, Hub Purist, Speedrunner
- Findings: 1 P0 (clamp hole — same-city arbitrage 15,642 $/kg zero-flight, the clamp's purchase reference was wrong), 4 P1s (demand pressure post-sale; delayed leg-1 honored impossible connections at 0.71% of purchases; discovery credited at sell; risk/fee undisclosed + intel gate hiding 2.15× margins), plus 2 NEW P2s (buy-tab estimate showed raw base with zero modifiers; now_iso space-separator broke the departed-flight filter) and a batch of P2/P3 UI-honesty items. All fixed or explicitly queued below.
- Ratchet delta: margin test re-referenced to cheapest purchasable price (RED 15,642 → GREEN 500); `SmokeDemandPressure.gd` (in-sale escalation, RED naive → GREEN); SmokeConnectionContract Part D (delayed leg-1 rebook-or-refund, RED gap 96<120 → GREEN); `verify_timezone.tscn` (5 assertions incl. T-separated now_iso); airport-coverage test (traffic-rank tiebreak — SFO/SEA/IAH/LAS restored); expo on-disk artifact test. Runtime: `rebook_connection_leg2` (free through-ticket rebooking or 70% refund-and-park), `GameClock.now_iso` T-separated, discovery credit moved to buy, sell escalation loop, `_hint_panel` z-index above overlay, countdown visibility re-assert, pre-purchase reliability disclosure (config-driven), fee % strings config-driven everywhere, layover copy uses actual gap + contract MCT, product-name leaks fixed, news popups deferred past first flight, metric list + grade ladder in mode desc, settlement value/cap (n%) display, `same_alliance_discount_min` removed (alliance data wrong for real pairings — reinstate only with interline rebooking).
- Earned rules: 0 new (existing 3 candidates held).
- Re-surface: disclosure, intel gate, demand pressure, MCT-on-delay, dead alliance config, metrics visibility — all re-verified and fixed; 0% NEW-invalidated.
- Queued: throughput vs `cap_profit_per_hour` (clamp-honest play still 14× the 200 $/h cap — re-derive cap from hourly target; balance-direction note), rep grant drift under purchase-credit (+3/discovery — watch), tutorial re-read button, toast queue, baggage-tier toggle states, auto-board panel-yank warning, day-rollover selection persistence, buy-tab estimate realism (assumption labeling shipped), settlement net-worth end-city footnote, `hash(seed_s)` engine-version ratchet (verify scene pins the Time API side).

### Playtest #5 — 2026-08-15 (pipeline-contract-audit: route realism)

- Cycle: pipeline-contract-audit, 3 contract personas, distinct instruments (independent provenance re-derivation vs routes.dat + OurAirports iso_country; 5× cross-PYTHONHASHSEED double-run byte diff incl. sqlite table-level comparison; network-structure analysis — giant component, transfer reachability BFS from ATL + BCN, domestic-only inventory, transfer-hub qualification)
- Personas: Data-Contract Auditor (数据契约审计员), Determinism Auditor (确定性审计员), Hub Purist (枢纽专家)
- Directive: routes must follow reality — remove small-airport connectivity compensation (nearest-neighbour degree padding + forced international routes). User confirmed: keep the 20 demo hubs' ≥8 fill; filter at selection time (≥1 real route per airport).
- Findings: no P0. 2 P2s + 1 P3 fixed this cycle (flight layer operated 13,278 real BTS flights on 424 pairs absent from routes/transfers/coverage — merged real BTS pairs into the route layer; latent hub-padding path could mint hub→non-hub synthetic edges if the ≥8 floor ever fired — fill candidates restricted to hub↔hub; validate() no-intl check was print-only — promoted to an assert). 6 P3s queued (see below). All findings NEW (5th cycle, new surface; 0% re-surface).
- Ratchet delta: `tests/etl/test_route_realism.py` (6 RED-first contract tests: non-hub routes must be real, no forced international edges, non-hub degree == real partner count, small airports stay small, no isolates, every flight pair in the route layer — the last RED at 13,278 flights/424 pairs). `test_v3_aviation.py` intl-route contract rewritten to the realism contract (≥1 route, domestic-only permitted). Pipeline: `ensure_intl_routes` deleted; `ensure_route_degree` hub-only (min 8, hub↔hub candidates); `filter_connected_cities` (ranked greedy + re-scan, selection realism); BTS pairs merged into `routes`; `validate()` forced-intl assert. Result: 500 airports, 0 invented edges (100% of 19,036 directed routes trace to routes.dat or BTS 2025-03), 28 domestic-only airports (e.g. ABQ/ALB/ANC), min non-hub degree 3 (SZB), single giant component (500/500 reachable ≤2 hops via transfers). Roster tail changed by the filter: PIE dropped (orphan plate removed), san_pedro_sula added (procedural plate generated). PRD §3.2 route-realism rule ratified. Data regenerated `--full`; Expo snapshot byte-identical (routes not in the export).
- Earned rules: 1 new candidate (selection realism over edge invention). Cross-model review (Codex) skipped — CLI + API key unavailable in this session.
- Re-surface: 0. Determinism double-run verified byte-identical across seeds (only `meta.generated_at` exempted, per existing contract).
- Queued: P3 — no degree-1/2 island spurs (selection favors big airports; admit true spurs explicitly if wanted); P3 — hub ≥8 guarantee is roster-coupled (HND=29 min) — re-check on roster resize; P3 — challenge 60-city cap never binds (500 cities ≤2 hops of ATL) — balance-direction note, joins the throughput-vs-cap queue; P3 — BHM/RIC/JHG render domestic-only because their real intl partners (FPO/LPQ) are off-roster; P3 — 212 reverse-direction pairs fabricated from one-directional real edges (PRD "合理重建", kept by design); P3 — printed world-hash digests `generated_at` bytes — do not wire into CI as a reproducibility gate.

### Playtest #4 — 2026-08-14 (art-craft-review: first craft cycle)

- Cycle: art-craft-review, 4 craft personas, distinct instruments (style-contract + provenance audit; PIL/numpy full-population plate metrics; computed WCAG contrast + layout reading; render/audio mood audit)
- Personas: Art Director (美术总监), Game Artist (游戏美术), Game Designer (游戏策划), Retro Gamer (复古玩家)
- Findings: no P0. 3 P1s (board countdown 2.49:1 over globe; toast swallowed the fast-forward button 8–12 s; globe had NO WorldEnvironment — centerpiece rendered on the default gray) + P2s (WARN_RED 3.73–4.03:1 on panels, 257 orphan plates, stale contact sheet, tobacco icon dead art, 97-file legacy art/ tree with 2 drifted copies, missing earth-albedo attribution, hub plates half spec resolution, no ARTSTYLE.md) + P3 batch. Cross-persona convergence: orphan plates (Artist+Director), WARN_RED (Designer+Director). Disagreement resolved by data: Retro's "plates half as bright" vs Artist's full-population luminance discipline (0.362 ± 0.023, zero out-of-range) — fleet kept as-is.
- Ratchet delta: `tests/game/test_visual_contract.py` — 11 computed-style/asset-property assertions (the deferred visual-regression harness; RED 6/6 first run at the personas' measured ratios → GREEN). `docs/ARTSTYLE.md` ratified (tokens, typography, plate spec, icons, globe env, audio, provenance, guard). Fixes: WARN_RED → #E57E7E (passes panels AND scrims — darker reds fail panels), PROFIT_GREEN token replaces inline color, BG_DEEP@0.85 scrim strips behind countdown/challenge label, hint mouse_filter IGNORE, disclaimer fade 0.9, WorldEnvironment (BG_DEEP sky + ambient) in globe.tscn, 257 orphan plates + tobacco icon + 97 art/ duplicates removed (_archive/_sheets kept as source-provenance, export-excluded), contact sheet regenerated, transition frames unified to 1280×720, earth albedo attributed, loss-rung copy differentiated (小幅亏损 vs 交易亏损). PLUS: `FlightOps._reliability_roll` seed switched from GDScript `hash()` (process-randomized on strings — the root cause of the intermittent SmokeV3Loop/SmokeChallenge flakiness seen since Playtest #1) to a sha256-derived `hex_to_int()` seed — the roll-dependent smokes are now stable across processes.
- Earned rules: 0 new (3 candidates held).
- Re-surface: 0 net-new gameplay regressions; all craft findings NEW.
- Queued: hub plate 640×360 re-crop or re-classify (documented exception), export_presets.cfg with _archive/_sheets/art exclusions, emoji → themed icons, poster visibility on market/flights screens, sell-celebration card chrome, BGM motif variety, city_id slug sanitization (fragile filenames), toast queue + tutorial re-read + baggage toggles + auto-board warning + day-rollover persistence + net-worth footnote (UI polish from P3, proposals recorded), C-city content second template family, splash.webp dead asset decision, glow on globe env.

## Ratchet (Regression Tests)

_Each P0 finding earns a test RED before the fix. P1/P2 entries at author discretion, severity + reason recorded._

| Date | Finding | Persona(s) | Test file + name |
|------|---------|-----------|------------------|
| 2026-08-13 | P0 — leg-1 cancel kept leg 2 → auto-board teleported player (no-teleport violation) | Casual Traveler + Hub Purist | SmokeConnectionContract.gd part B + C, FlightOps.gd cancel path + boarding origin guard |
| 2026-08-13 | P0 — connection system minted phantom flights (`cnx1_/cnx2_`, dep = now+3h) instead of real schedule | Hub Purist (+ RED test as second observer) | SmokeConnectionContract.gd part A, TicketService.purchase_connection real-flight assembly |
| 2026-08-13 | P0 — collection caps set to 500-city world totals made A unreachable in 15 days (measured ceiling 66–70 < 80) | Trade Senior + Speedrunner | tests/etl/test_challenge_rules.py::test_excellent_15_day_run_scores_a, ChallengeSystem.gd caps 60/30/350 |
| 2026-08-13 | P1 — luxury goods ~2.4–2.7× margins (~$81k/trip) trivialize the economy; single-observer → queued to pipeline-audit (ETL pricing root cause) | Trade Senior | persona-note only, recurrence-likely — see Playtest #1 queue |
| 2026-08-13 | P1 — delayed leg-1 boards a flight whose departure passed; MCT never re-checked on delay | Hub Purist | persona-note only, recurrence-likely — follow-up in connection hardening |
| 2026-08-13 | P1 — delay/cancel risk (8%/1.5%, 30% fee) never disclosed pre-purchase | Casual Traveler | persona-note only, recurrence-likely — ticket-panel copy |
| 2026-08-13 | P1 — chicken-and-egg outlook: no sell outlook until ticket AND goods held | Tourist | persona-note only, recurrence-likely — market UI |
| 2026-08-13 | P1 — default start airport (ATL) never stated on the new-game panel | Tourist | persona-note only, recurrence-likely — new-game UI |
| 2026-08-13 | P1 — products metric anti-correlated with net worth (discovery credits only on sell) | Speedrunner | persona-note only, recurrence-likely — challenge metrics |
| 2026-08-13 | P2/P3 ×12 — fee legibility, delay toast consequences, hidden metric list, toast channel overwrite, tutorial re-read, countdown suppression, news-on-first-boot, baggage-tier state, UTC build-dependence, reliability zero-coverage (now partially covered by SmokeConnectionContract), MCT config dead paths, rosy reliability model, BTS duplicate numbers, generated product copy | all personas | persona-note only — see Playtest #1 queue |
| 2026-08-14 | P0 — pipeline not byte-reproducible: salted `hash()` flight numbers + set-iteration hub/routes order (55 artifacts drifted across PYTHONHASHSEED) | Determinism Auditor (double-run diff) + Hub Purist (#1) | tests/etl/test_pipeline_contracts.py::test_pipeline_double_run_byte_identical, run_pipeline.py |
| 2026-08-14 | P0 — light high-rarity proxies paid up to $53.5k/kg ($1.07M per 20kg hold on real legs); margin × 1/weight degeneracy | Economy Auditor (distribution model) + Trade Senior (#1) | tests/etl/test_pipeline_contracts.py::test_margin_per_kg_bound + test_margin_cap_in_config, economy.yaml margin_per_kg_cap_usd 500 |
| 2026-08-14 | P1 — stopover mint fabricated airline–leg pairs (144/144 unoperated first legs) and could exceed the antipodal bound | Data-Contract Auditor (routes.dat sampling) + Hub Purist (#1) | tests/etl/test_pipeline_contracts.py::test_stopover_legs_real_and_bounded, run_pipeline.py joint-airline membership + 20,037 km cap |
| 2026-08-14 | P1 — Expo demo economy drifted 3.5× on fares (unguarded duplicate; ios-data.json had zero consumers) | Cross-Implementation Auditor (+ RED drift test as second observer) | tests/etl/test_pipeline_contracts.py::test_expo_declared_mapping, gameData.js DEMO_SCALE |
| 2026-08-14 | P2 — flat 75-min hub overrides killed international_min 120 on 87% of transfer edges | Data-Contract Auditor + Hub Purist (#1) | tests/etl/test_pipeline_contracts.py::test_mct_transfer_edges, run_pipeline.py per-leg international + airport_mct_minutes |
| 2026-08-14 | P2 — challenge caps/thresholds were literals in 3 places with presence-only guards | Cross-Implementation Auditor | tests/etl/test_pipeline_contracts.py::test_challenge_config_in_data + test_expo_export_carries_challenge_block, economy.yaml challenge block |
| 2026-08-14 | P2/P3 — demand-pressure applied after sale (bypassable in one dump); `same_alliance_discount_min` dead config; same-day flight-number collisions; latent `hash(city_id)` product seed; unseeded hot-win validation | Economy / Data-Contract / Determinism auditors | persona-note only — runtime items queued, see Playtest #2 queue |
| 2026-08-14 | P0 — margin clamp referenced origin-country buy; buying at a low-cpl city then reselling locally paid 15,642 $/kg with zero flight hours (557 slots) | Trade Senior (post-clamp distribution model) + RED test | tests/etl/test_pipeline_contracts.py::test_margin_per_kg_bound (cheapest-purchasable-price reference), run_pipeline.py universal clamp |
| 2026-08-14 | P1 — demand pressure applied AFTER the sale: one bulk dump transacted 100% of units at the pre-sale price (bulk ≈ 1.5× drip) | Casual Traveler (call order) + Trade Senior (quantified) | SmokeDemandPressure.gd, InventorySystem.sell in-sale escalation |
| 2026-08-14 | P1 — delayed leg-1 honored impossible connections (MCT never re-checked; 0.71% of purchases, planes boarded after departure) | Hub Purist (live engine + Monte Carlo) + Casual Traveler | SmokeConnectionContract.gd Part D, FlightOps rebook-or-refund, TicketService.rebook_connection_leg2 |
| 2026-08-14 | P1 — products_discovered credited at SELL: collector play wrecked profit; metric anti-correlated with net worth | Speedrunner (call site + calibration sim) | InventorySystem.buy discovery credit (sell keeps profit axes) |
| 2026-08-14 | P1 — delay/cancel risk + 30% fee undisclosed pre-purchase; intel gate hid 2.15× margins from tutorial-ordered shoppers | Casual Traveler + Tourist | MainHUD reliability disclosure (config-driven), _market_buy_outlook data-only estimate |
| 2026-08-14 | P2 — now_iso returned SPACE-separated ISO (Godot 4.3+ API change), breaking the departed-flight filter; buy-tab estimate showed raw base with zero modifiers | Hub Purist + Casual Traveler | verify_timezone.tscn, GameClock.now_iso T-separated; estimate labeled + discovery credit |
| 2026-08-14 | P2 — alphabetical airport tiebreak excluded SFO/SEA/IAH/LAS/MSP/SYD/NRT while keeping BUR/FAT/GEG | Hub Purist | tests/etl/test_pipeline_contracts.py::test_top_traffic_airports_present, run_pipeline.py traffic-rank tiebreak |
| 2026-08-14 | P2/P3 — metrics invisible until settlement; layover copy lied twice; fee % hardcoded; product IDs leaked; toast under overlay; countdown hidden in flights panel; news on first boot; stale expo artifact | Tourist / Casual / Purist / Speedrunner | mode desc + settlement value/cap (n%), layover actual-gap copy, config-driven fee strings, name_zh, z_index, countdown re-assert, first-flight news guard, on-disk expo test |
| 2026-08-14 | P1 — boarding countdown WARN_RED over globe = 2.49:1 (most critical state read failed at a glance) | Game Designer | tests/game/test_visual_contract.py (scrim contract), BG_DEEP@0.85 scrim strips |
| 2026-08-14 | P1 — hint toast swallowed the fast-forward button's clicks for 8–12 s after every purchase | Game Designer | test_hint_panel_does_not_block_fast_forward, mouse_filter IGNORE |
| 2026-08-14 | P1 — no WorldEnvironment anywhere: the globe rendered on Godot's default gray with zero ambient | Retro Gamer | test_globe_has_themed_environment, WorldEnvironment in globe.tscn |
| 2026-08-14 | P1/P2 — WARN_RED failed AA on every panel surface (3.73–4.03:1) | Art Director + Game Designer | test_warn_red_on_panel_contrast, token → #E57E7E |
| 2026-08-14 | P2 — 257 orphan city plates (11.5 MB) from the roster trim; stale contact sheet; tobacco icon dead art; 97-file legacy art/ tree with 2 drifted copies; missing earth-albedo attribution | Game Artist + Art Director | test_no_orphan_city_plates, test_no_prd_banned_icon_stems, test_no_legacy_art_duplicate_tree, test_earth_albedo_attributed |
| 2026-08-14 | P2/P3 — no art-style contract; inline colors escaping tokens; transition frames non-uniform; hub plates half spec resolution (documented exception) | Art Director | docs/ARTSTYLE.md ratified; PROFIT_GREEN token; frames unified 1280×720 |
| 2026-08-14 | P3 — five-tier loss rungs titled identically (L2=L1 交易亏损); emoji glyphs clash with poster identity; poster art smallest element on screen | Retro Gamer | csv copy differentiated (小幅亏损); emoji/poster-visibility queued |
| 2026-08-15 | P1 — GDScript `hash()` on strings is process-randomized: delay/cancel rolls differed per run, making the roll-scanning smokes (V3Loop/Challenge) intermittently red since Playtest #1 preflight | cross-cycle evidence (P1 preflight + P4 suite) | FlightOps._reliability_roll sha256 seed; 3× repeat runs green |
| 2026-08-15 | Contract change (user directive): remove small-airport connectivity compensation — nearest-neighbour degree padding + forced international routes minted non-real edges (88 directed / 0.5% in full mode; PPT 4→6, ZUH→MFM) | user directive; Data-Contract Auditor + Hub Purist concurred post-fix | tests/etl/test_route_realism.py C1/C3/C5/small-airport/isolate (RED 4/5 on old data), run_pipeline.py ensure_intl_routes removed + filter_connected_cities |
| 2026-08-15 | P2 — flight layer operated 13,278 real BTS flights on 424 pairs absent from routes/transfers/coverage (game sold them; route systems never saw them) | Data-Contract Auditor | tests/etl/test_route_realism.py::test_every_flight_pair_is_in_routes (RED 13,278/424), run_pipeline.py BTS-pair route merge |
| 2026-08-15 | P2 — latent: hub degree-floor padding could mint hub→non-hub synthetic edges (breaking the no-synthetic/domestic-only contracts) if the ≥8 floor ever fired | Data-Contract Auditor | tests/etl/test_route_realism.py C1/C3/C5, run_pipeline.py hub↔hub-only fill candidates |
| 2026-08-15 | P3 — validate() no-intl check was print-only: a synthetic international edge would pass the pipeline undetected | Data-Contract Auditor | run_pipeline.py forced_intl assert |
| 2026-08-15 | P3 — roster tail favors big airports: no degree-1/2 island spurs (real networks have them) | Hub Purist | persona-note only, recurrence-likely — see Playtest #5 queue |
| 2026-08-15 | P3 — hub ≥8 guarantee is roster-coupled (HND=29 min); re-check if the roster is ever resized | Hub Purist | persona-note only — see Playtest #5 queue |
| 2026-08-15 | P3 — challenge 60-city cap never binds (500 cities ≤2 hops of ATL); challenge bound by schedule, not network | Hub Purist | persona-note only, balance-direction |
| 2026-08-15 | P3 — BHM/RIC/JHG render domestic-only in-game; their real intl partners (FPO/LPQ) are off-roster | Data-Contract Auditor | persona-note only — roster-coverage note |
| 2026-08-15 | P3 — 212 reverse-direction pairs fabricated from one-directional real edges (PRD "合理重建", kept by design) | Data-Contract Auditor | persona-note only — by design |
| 2026-08-15 | P3 — printed world-hash digests generated_at bytes; do not wire into CI as a reproducibility gate | Determinism Auditor | persona-note only |

## What's Working

_Methodological patterns that proved themselves across 2+ playtests (playbook rule #28)._

- **Contract personas auditing a landed pipeline change with independent instruments** (2026-08-15, confirmed across Playtests #2 and #5): each persona re-derives its evidence from raw artifacts with its own scripts and its own regenerations, and the audit has found real holes both times (P2: 8/8 RED contract violations; P5: 424 route-less BTS pairs + a latent padding path). Persona-run audits catch what the author's own GREEN tests structurally miss.

## Related playbooks

- [AI instructions](CLAUDE.md) — project-specific Claude Code guidance, commands, conventions

## References

- Upstream playbook: `https://raw.githubusercontent.com/BaseInfinity/claude-gdlc-wizard/main/GDLC.md`
- Skill: `.claude/skills/gdlc/SKILL.md`
- Wizard: `/gdlc-update` to pull playbook changes
