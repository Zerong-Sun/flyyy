# Trade Quantity, Flight Focus & Contract Catalog — Design

**Date:** 2026-07-26  
**Status:** Approved

## Goals

1. Buy/sell with an editable quantity (e.g. 10 or 100 at once).
2. Flight list: departures within 2 hours are gray; default focus starts at the first flight ≥2 hours out; earlier rows remain visible and purchasable.
3. Replace souvenir-scale goods with bulk trade contracts; raise starting cash to `$50,000`.

## Decisions

| Topic | Choice |
|-------|--------|
| Qty UI | SpinBox (1–9999) + shortcuts 1/10/100; wires existing `InventorySystem.buy/sell(qty)` |
| &lt;2h flights | Gray styling only; still buyable; no `TicketService` cutoff |
| Default focus | On opening flights panel, page/select first flight with lead ≥7200s |
| Catalog | Per city ≥5 trade contracts; no `纪念品` / magnets |
| Contract scale | `weight_kg` ~10–50; base price hundreds–thousands USD |
| Starting cash | `50000.0` USD |

## Architecture

- **Qty:** UI-only in `MainHUD`; systems already accept `qty`.
- **Flights:** Helpers in `FlightSearch` (`FOCUS_LEAD_SEC`, `is_short_lead`, `first_focus_index`); `MainHUD` applies gray + auto-focus once per panel open.
- **Catalog/cash:** `economy.yaml` + `etl/content/products/*.yaml` + `PRODUCT_TEMPLATES` → rebuild `world.json`.

## Categories

CAS demo categories include: existing trade-fit enums plus `机械` / `能源` / `电子` / `矿产`. Demo content must not use `纪念品`.

## Out of scope

- Merging inventory stacks on repeat buys
- Hard booking cutoff
- Full PRD rewrite
