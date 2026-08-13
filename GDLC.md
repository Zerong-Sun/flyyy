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

## Playtest Ledger

_Chronological log of playtest cycles. Each entry: date, cycle type, personas, findings, ratchet delta._

### Playtest #1 — 2026-08-13 (gameplay-matrix: trade loop + 15-day challenge fairness)

- Cycle: gameplay-matrix, one roster of 5 personas, distinct instruments (headless smokes; pytest suite; independent Python market sim; aviation data audit; challenge winability sim + Expo cross-check)
- Personas: Tourist (初次玩家), Casual Traveler (休闲玩家), Trade Senior (资深商旅), Hub Purist (枢纽专家), Speedrunner (速通玩家)
- Findings: 3 P0s promoted & fixed (connection-cancel teleport; phantom minted connection flights; A-grade unreachable under world-total caps). 7 P1s + 12 P2/P3s recorded below, queued for follow-up cycles. All findings NEW (0% re-surface, first cycle).
- Ratchet delta: +1 headless smoke (`SmokeConnectionContract.gd`: real-legs contract, cancel-no-teleport, boarding origin guard); +1 pytest winability property (`test_excellent_15_day_run_scores_a`, RED 70 < 80 → GREEN 89); SmokeV3Loop updated to the real-flight connection contract; PRD §6.2 caps/thresholds documented; 30→15 day references aligned (PRD/README/CLAUDE.md).
- Earned rules: 1 candidate (window-calibrated caps).
- Queued for pipeline-contract-audit cycle: ETL `hash()` flight numbers (determinism violation), stopover airline–route fabrication, dead MCT config (75 override vs 120 intl / alliance discount), luxury-goods margin blowout (P0 claim, single-observer → downgraded P1, root cause in ETL pricing), Expo challenge-mode parity.

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

## What's Working

_Methodological patterns that proved themselves across 2+ playtests (playbook rule #28)._

(none yet)

## Related playbooks

- [AI instructions](CLAUDE.md) — project-specific Claude Code guidance, commands, conventions

## References

- Upstream playbook: `https://raw.githubusercontent.com/BaseInfinity/claude-gdlc-wizard/main/GDLC.md`
- Skill: `.claude/skills/gdlc/SKILL.md`
- Wizard: `/gdlc-update` to pull playbook changes
