# Trade Feedback & Regional Price Anchors — Design

**Date:** 2026-07-26
**Status:** Draft
**Brainstorm:** `2026-07-26-TBD` (inline in chat)

## Summary

Add four subsystems on top of the existing buy → fly → sell loop: regional price anchors that guarantee directional profit/loss ~90% of the time, implicit intelligence embedded in existing UI, surprise events triggered at arrival/sell moments, and a five-tier sell feedback animation system with consolation and celebration copy. Style: restrained daily with escalation at high-margin / high-loss moments (middle-ground approach). Anchor tier: gross margin only (sell price − buy cost).

---

## 1. Regional Price Anchors (risk_profile)

### 1.1 Problem

Current ETL applies soft bias (origin cheap, remote scarce) but daily ±6% fluctuation + demand decay mean players cannot trust that flying to the right city will pay off.

### 1.2 Design

Extend ETL to compute `sell_buy_ratio` per (product, city) pair during price materialization in `run_pipeline.py`. Derive tags from the ratio:

| sell_buy_ratio | Tag   | Meaning |
|---------------|--------|---------|
| ≥ 1.15        | hot   | After worst-case −6% daily noise + 15% demand decay, margin stays near or above breakeven. ~90% probability of positive gross margin. |
| 1.00 – 1.14   | normal | Directionally correct but noise can flip the result. |
| < 1.00        | cold  | Sell price nearly always below buy cost after noise. |

### 1.3 Formulas (reusing existing ETL math)

```
buy_origin  = base_price × CountryPriceLevel_origin × origin_supply_bonus(0.82) × retail_markup(1.12)
sell_remote = max(base_price × CPL_dest × scarcity_remote × 0.91, buy_remote × 0.95)
sell_buy_ratio = sell_remote / buy_origin
```

- Hot guarantee: `1.15 × (1 − 0.06) × (1 − 0.15) ≈ 0.92`. Worst-case stacked but unrealistically unlikely in practice — actual daily noise and demand rarely hit both extremes simultaneously.
- Cold guarantee: `sell_buy_ratio < 1.0` means even +6% noise cannot rescue the margin.

### 1.4 Output

Extend `world.json`:

```json
{
  "product_market_tags": {
    "beijing|steel_pipes": {
      "hot": ["dubai", "frankfurt"],
      "normal": ["singapore", "london"],
      "cold": ["bangkok", "los_angeles"]
    }
  }
}
```

### 1.5 Consumption

- **Intelligence labels** (Section 2) read tags to display direction hints.
- **Surprise events** (Section 3.4) use cold-tag cities as triggers for city-exclusive discovery.
- **Sell animation tiers** (Section 4) assume hot → usually win, cold → usually loss; tiers validate direction with actual runtime margin.

---

## 2. Implicit Intelligence (Embedded in Existing UI)

### 2.1 Free Intelligence — Market Tab Labels

In the Market tab product list, each row shows a direction label based on the player's current ticket destination:

| Player state | Tag | Label | Color |
|---|---|---|---|
| Ticket to a hot city | `hot` | 📍[city]热卖 | Green |
| Ticket to a normal city | `normal` | 📍[city]可售 | White |
| Ticket to a cold city | `cold` | ⚠️不建议 | Red |
| No ticket (lookup best) | best hot city | ⭐最佳目的地：[city] | Gold |

Labels read from `product_market_tags[product_id]`.

### 2.2 Paid Intelligence — Precision Upgrade

Each product row includes a small button: `🔍精准预测` ($200).

- Deducts $200. Free label is replaced with a margin range for **one** target city (the ticket destination):

```
电子芯片  x10  买入价 $4,200  📍曼谷热卖  预计毛利 $1,050 – $1,480
```

Range calculation (client-side):
- `mid = sell_price_estimate(base, current_demand) − buy_cost`
- `low = mid × (1 − daily_variation_amp)` — worst-case fluctuation
- `high = mid × (1 + daily_variation_amp)` — best-case fluctuation
- Uses `EconomySystem.sell_price()` formula, not a separate calculation.

Upgrade validity: until the ticket is used or cancelled.

### 2.3 Voyage Notes (New Tab, beside Inventory)

After arriving at a city, the city is added to a `Notes` tab alongside Inventory:

```
┌──────────────────────────────────┐
│ 📒 迪拜交易笔记                    │
│ 电子芯片：毛利 +$15,600 ✅         │
│ 稀土矿石：毛利 -$2,100 ❌          │
│ ─────────────────────             │
│ 城市总结：3赚 1亏  净利 +$28,400  │
└──────────────────────────────────┘
```

- Each entry shows product, buy price, sell price, sell city, timestamp.
- Summary row updates with every sell.
- Read-only history; no gameplay impact.

### 2.4 Data Dependencies

| Feature | Data source |
|---|---|
| Free labels | `world.json` → `product_market_tags` |
| Paid prediction | `EconomySystem.sell_price()` with range bounds |
| Voyage notes | `AppState` sell transaction log (new field) |

---

## 3. Surprise Events (Event-Driven, Implicit)

All events use **hash-based seeds** (`hash(city + date + product + event_type)`) for reproducibility — no save-file persistence needed. All share a single `PopupEvent` component parameterized by type.

### 3.1 Arrival Encounter — Discounted Goods

**Trigger:** arriving at a new city. **Probability:** 20%.

```
┌──────────────────────────────────┐
│          🎲 偶遇商机！             │
│                                   │
│   本地经销商清仓，                  │
│   [product_name] 限时折扣 [X]%    │
│                                   │
│   ⏰ 剩余 2 小时（游戏时间）          │
│   折扣库存：无限                   │
│                                   │
│     [趁机买入]     [不了谢谢]       │
└──────────────────────────────────┘
```

- Discount: −20% to −40% (random uniform).
- Valid for current stay only. "趁机买入" navigates to Market tab with discounted buy price applied.
- Max 1 encounter per arrival.

### 3.2 Free Cargo Slot

**Trigger:** arrival at a city, or after buying a ticket. **Probability:** 10%.

```
┌──────────────────────────────────┐
│          📦 舱位福利               │
│                                   │
│   该航班货舱有空位，额外 +50kg       │
│   cargo 本次免费（原价 $380）      │
│                                   │
│      [接受]          [不用]        │
└──────────────────────────────────┘
```

- Accept: sets this flight's cargo cost to $0 (overrides `baggage_extras.cargo_per_50kg_usd`).

### 3.3 Accidental Premium (on Sell)

**Trigger:** after pressing "Sell" but before crediting cash. **Probability:** 5–10%.

```
┌──────────────────────────────────┐
│          💰 意外溢价！             │
│                                   │
│   买家急需这批货！                  │
│   本次售价额外加成 +[Y]%           │
│                                   │
│   原售出价：$X,XXX                │
│   溢价后：$XX,XXX                 │
│                                   │
│      [成交！]                      │
└──────────────────────────────────┘
```

- Bonus: +20% to +35% (random uniform).
- If premium triggers AND the product has a hot tag for this city: sell animation upgrades to **Grand Slam** (see Section 4.2).
- Player must click "成交" to complete; cannot cancel.

### 3.4 City-Exclusive Discovery (after Sell)

**Trigger:** after a successful sell in a cold-tag city (sell_buy_ratio < 1.0), and player still holds more of that product. **Probability:** 5%.

```
┌──────────────────────────────────┐
│          ✨ 意外发现！             │
│                                   │
│   "这里的人从没见过[product]！"     │
│   库存中所有[product]              │
│   卖出价额外 ×2.0                 │
│                                   │
│   [全部溢价卖出]   [暂不处理]       │
└──────────────────────────────────┘
```

- "全部溢价卖出": all stacks of this product in inventory are instantly sold at `sell_price × 2.0`, bypassing normal sell flow.
- "暂不处理": opportunity is queued. Can be re-activated from Notes before leaving the city.
- Max 1 discovery per city stay.

### 3.5 Implementation Notes

- Seed formula: `hash(city_id + date_seed + product_id + event_type)` ensures no duplicate triggers on revisit.
- `PopupEvent` component accepts: `type`, `title`, `body_text`, `action_text`, `cancel_text`, `data_dictionary` (discount %, bonus %, product_id, etc.).
- All event data is ephemeral — cleared on city departure.

---

## 4. Sell Feedback Animation System

### 4.1 Timing Flow

```
[Click "Sell"]
     │
     ▼
[Confirm dialog]  qty / estimated revenue / margin preview
     │
     ▼ [Confirm]
[Loading — 0.5s]  spinning globe icon + "市场处理中..."
     │             ↓ EconomySystem.sell() + accidental premium check
     ▼
[Result card]      margin-level determination → 1.0s – 3.0s
     │             ↓ particles / banner / copy
     ▼
[Close]            back to Inventory tab, cash number ease-out roll (1s)
```

### 4.2 Five-Tier Determination

Joint criteria: **gross margin** (sell_revenue − total_unit_cost) and **margin rate** (margin / total_unit_cost).

| Tier | Condition | Visual | Audio | Duration |
|---|---|---|---|---|
| **Big Loss (L2)** | margin < $0 AND rate < −20% | Red card + confetti-fall particles (grey) + character portrait (worried) + consolation copy | `sfx_loss` | 2.5s |
| **Small Loss (L1)** | margin < $0 AND rate ≥ −20% | Light-red card + red-tinted numbers + hint "下次换个市场试试" | `sfx_loss_light` | 1.5s |
| **Normal Win (W0)** | $0 ≤ margin < $3,000 | Default card + green number bounce. No extra effects. | `sfx_sell` (existing) | 1.0s |
| **Big Win (W1)** | $3,000 ≤ margin < $10,000 | Gold-green gradient card + coin particles flying from right + margin number enlarged & rolling | `sfx_big_win` | 2.0s |
| **Grand Slam (W2)** | margin ≥ $10,000 OR accidental premium triggered | Full-screen gold flash overlay + coin rain + banner "大满贯！" + character portrait (celebrating) | `sfx_grand_slam` | 3.0s |

**Bonus rule:** If W2 is triggered via city-exclusive discovery (Section 3.4), append "✨发现者加成" banner below "大满贯".

**Wealth milestone toast:** If cash after sell exceeds $100,000 or has doubled since game start, show a brief toast: "财富里程碑！" (pops above cash bar, 2s).

### 4.3 Consolation Copy Pool

Random draw from `sell_console_*` (i18n keys, added to `zh_CN.csv`):

```
sell_console_1  "没事，学费而已"
sell_console_2  "下一趟回本"
sell_console_3  "做生意就是这样"
sell_console_4  "这个城市不太行"
sell_console_5  "及时止损也是赢"
```

Big Loss (L2) additionally appends:

```
sell_console_big_loss  "赔大了...但旅行本身就值得"
```

### 4.4 Celebration Copy Pool

Random draw for W1 and W2:

```
celebration_w1_1  "这笔漂亮！"
celebration_w1_2  "眼光不错"
celebration_w1_3  "路走对了"
celebration_w2_1  "传奇交易！"
celebration_w2_2  "你就是这条航线的王"
celebration_w2_3  "同行看了都眼红"
```

### 4.5 Net Trip Profit Hint

At the bottom of the result card, display a small secondary line (does not affect tier):

```
账面毛利：+$8,500
本趟机票：−$1,240  行李/货运：−$320
──────────────────
行程净利：+$6,940
```

Data sources: `AppState.last_flight_price`, `AppState.last_baggage_cost`.

### 4.6 Cash Number Roll

After the result card dismisses, the bottom-bar cash display performs an ease-out roll from old value to new value over ~1s. Grand Slam doubles the scroll speed and flashes gold once at completion.

### 4.7 Implementation Notes

- All animations driven from `MainHUD._on_sell_result(callback)`.
- Tier determination data returned from `EconomySystem` alongside sell response: `{margin, margin_rate, revenue, cost, accidental_premium}`.
- Particle effects use a shared `FeedbackParticles` scene, parameterized: color palette, count, duration, direction.
- `PopupEvent` component extended with `SellResult` variant (reuses the card structure from Section 3 events).

---

## 5. Art Asset Requirements

All assets listed below are needed for the features described in Sections 3 and 4.

### 5.1 Icons & UI Elements

| Asset | Description | Section |
|---|---|---|
| `icon_intel_upgrade` | Small magnifying-glass icon with sparkle, ~24×24, for precision prediction button | 2.2 |
| `icon_notes_tab` | Notebook / journal icon for voyage notes tab, ~24×24 | 2.3 |
| `icon_hot_tag` | Fire/flame small badge, green-tinted | 2.1 |
| `icon_cold_tag` | Snowflake or warning triangle small badge, red-tinted | 2.1 |
| `icon_loading_globe` | Stylized spinning globe or abacus, 48×48, loopable 0.5s cycle | 4.1 |

### 5.2 Character Portraits (Emoji-Style Faces)

| Asset | Expression | Size | Section |
|---|---|---|---|
| `portrait_worried` | Worried / face-palm expression | 64×64 | 4.2 (L2) |
| `portrait_celebrating` | Cheering / arms-up expression | 64×64 | 4.2 (W2) |

### 5.3 Particle & Overlay Effects

| Asset | Description | Section |
|---|---|---|
| `particle_paper_shred` | Small grey paper fragments, falling from top-right, 20-30 particles | 4.2 (L2) |
| `particle_coin` | Gold circular coin, ~16×16, arc trajectory from right edge | 4.2 (W1) |
| `particle_coin_rain` | Heavier coin rain variant (50-80 particles), full-width fall | 4.2 (W2) |
| `overlay_gold_flash` | Full-screen golden flash overlay, instant on → fade out 0.5s | 4.2 (W2) |

### 5.4 Banners & Overlays

| Asset | Description | Section |
|---|---|---|
| `banner_grand_slam` | Horizontal banner centered: "🎉 大满贯！", gold gradient bg, 2-3s display | 4.2 |
| `banner_discovery` | Horizontal banner centered: "✨发现者加成", purple/blue gradient bg, 2-3s display | 4.2 |
| `banner_wealth_milestone` | Small toast banner: "财富里程碑！", gold border, pops above cash bar | 4.2 |
| `event_popup_bg` | Semi-transparent dark backdrop (80% alpha) + rounded card frame for all events | 3.x |

### 5.5 Audio

| Asset | Description | Section |
|---|---|---|
| `sfx_loss` | Deep, short descending tone (~0.3s) | 4.2 |
| `sfx_loss_light` | Subtle lower-pitch tick (~0.15s) | 4.2 |
| `sfx_big_win` | Rising chime with coin jingle (~0.5s) | 4.2 |
| `sfx_grand_slam` | Fanfare with cheering crowd sample (~1.0s) | 4.2 |
| `sfx_coin_roll` | Cash-register or coin-counting loop for cash number roll | 4.6 |

### 5.6 Typography / UI Style Notes

- Green/gold number font for W1/W2 margins: should be **non-monospaced**, ~1.3× normal size, with a subtle glow.
- Consolation / celebration copy: centered below the margin number, dark text on light card, standard body font.

---

## 6. Scope & Out of Scope

### In Scope

- ETL: `sell_buy_ratio` calculation and `product_market_tags` output in `world.json`
- Runtime: free/paid intelligence labels in Market tab (`MainHUD`)
- Runtime: Voyage Notes tab (read-only history)
- Runtime: 4 surprise event types via `PopupEvent` component
- Runtime: 5-tier sell animation system in `MainHUD._on_sell_result()`
- Runtime: cash number rolling animation
- I18n: consolation + celebration copy pools in `zh_CN.csv`
- Art: all assets listed in Section 5

### Out of Scope

- Persisting intelligence purchases or event state to save files
- New game systems / state machines beyond popup events
- Modifying `EconomySystem` pricing formula (read-only use)
- Inventory stack merge
- Hard booking cutoff for flights
- Any change to ticket or baggage pricing
