# Trade Feedback & Regional Anchors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ETL price anchors (hot/normal/cold per product-city pair), embedded intelligence labels in Market UI, four surprise event types, and a five-tier sell feedback animation system.

**Architecture:** ETL computes `sell_buy_ratio` per (product, city) and outputs `product_market_tags` into `world.json`. Runtime systems read tags for free/paid intelligence labels, four event types triggered via hash-scheduled `PopupEvent` dialogs, and a five-tier sell animation driven from `MainHUD._on_sell_result()`. All events are ephemeral (not persisted to save).

**Tech Stack:** Godot 4 GDScript (game), Python 3 + pytest (ETL/test), SQLite (ETL output).

---

## Global Constraints

- All prices in USD; display via existing `format_money()`
- Intelligence labels read from `world.json` → `product_market_tags`
- Event seeds: `hash(str(city_id) + str(date_seed) + str(product_id) + event_type)`, where `date_seed = floor(game_time_seconds / 3600)`
- PopupEvent component reused for all 4 event types + SellResult variant
- FeedbackParticles scene parameterized: palette, count, duration, direction
- Margin tier thresholds: L2 (< $0, rate < −20%), L1 (< $0, rate ≥ −20%), W0 ($0–$3k), W1 ($3k–$10k), W2 (≥ $10k or accidental premium)
- No save-file persistence for events, intelligence purchases, or notes
- No change to ticket/baggage pricing or EconomySystem pricing formula

---

### Task 1: ETL — Compute sell_buy_ratio and output product_market_tags

**Files:**
- Modify: `etl/scripts/run_pipeline.py` (in the price materialization section, ~L619-648)
- Test: `tests/etl/test_trade_contracts.py` (extend or add new test)

**Interfaces:**
- Produces: `product_market_tags` dict in `game/data/world.json` with structure `{"origin|product_id": {"hot": [...], "normal": [...], "cold": [...]}}`
- Consumes: existing `buy_origin`, `sell_remote` computed values during ETL price loop

- [ ] **Step 1: Write failing tests for sell_buy_ratio thresholds**

Add to `tests/etl/test_trade_contracts.py`:

```python
def test_sell_buy_ratio_tags_exist():
    """After pipeline run, world.json must have product_market_tags for every product."""
    import json
    with open("game/data/world.json") as f:
        world = json.load(f)
    tags = world.get("product_market_tags", {})
    products = world.get("products", {})
    origins = world.get("hubs", {})

    for origin_id in origins:
        for product_id in products:
            key = f"{origin_id}|{product_id}"
            assert key in tags, f"Missing tags for {key}"
            entry = tags[key]
            assert "hot" in entry
            assert "normal" in entry
            assert "cold" in entry


def test_sell_buy_ratio_hot_threshold():
    """Hot cities must have sell_buy_ratio >= 1.15."""
    import json
    with open("game/data/world.json") as f:
        world = json.load(f)
    tags = world["product_market_tags"]
    markets = world["markets"]

    for key, entry in tags.items():
        origin_id, product_id = key.split("|")
        for city_id in entry["hot"]:
            sell_base = markets[city_id]["products"][product_id]["sell_base_usd"]
            buy_origin = markets[origin_id]["products"][product_id]["buy_base_usd"]
            if buy_origin > 0:
                ratio = sell_base / buy_origin
                assert ratio >= 1.15, (
                    f"{key} → {city_id} tagged hot but ratio={ratio:.3f} < 1.15"
                )


def test_sell_buy_ratio_cold_threshold():
    """Cold cities must have sell_buy_ratio < 1.0."""
    import json
    with open("game/data/world.json") as f:
        world = json.load(f)
    tags = world["product_market_tags"]
    markets = world["markets"]

    for key, entry in tags.items():
        origin_id, product_id = key.split("|")
        for city_id in entry["cold"]:
            sell_base = markets[city_id]["products"][product_id]["sell_base_usd"]
            buy_origin = markets[origin_id]["products"][product_id]["buy_base_usd"]
            if buy_origin > 0:
                ratio = sell_base / buy_origin
                assert ratio < 1.0, (
                    f"{key} → {city_id} tagged cold but ratio={ratio:.3f} >= 1.0"
                )


def test_sell_buy_ratio_no_city_duplicates():
    """Each city must appear in exactly one of hot/normal/cold per product."""
    import json
    with open("game/data/world.json") as f:
        world = json.load(f)
    tags = world["product_market_tags"]
    all_cities = set(world["hubs"].keys())

    for key, entry in tags.items():
        cities_seen = set()
        for cat in ("hot", "normal", "cold"):
            for city_id in entry[cat]:
                assert city_id not in cities_seen, (
                    f"{key}: {city_id} appears in multiple categories"
                )
                cities_seen.add(city_id)
        # All cities should be covered (cold may have all remaining)
        assert cities_seen == all_cities, (
            f"{key}: missing cities: {all_cities - cities_seen}"
        )
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/zero/project/flyyy && python -m pytest tests/etl/test_trade_contracts.py::test_sell_buy_ratio_tags_exist tests/etl/test_trade_contracts.py::test_sell_buy_ratio_hot_threshold tests/etl/test_trade_contracts.py::test_sell_buy_ratio_cold_threshold tests/etl/test_trade_contracts.py::test_sell_buy_ratio_no_city_duplicates -v
```
Expected: all 4 FAIL (KeyError or assertions on missing data).

- [ ] **Step 3: Implement sell_buy_ratio computation in run_pipeline.py**

In `run_pipeline.py`, in the price materialization loop where per-city-product prices are computed, add after computing `sell_base_usd` for each (origin_city, product_id, dest_city):

```python
# Compute sell_buy_ratio and tag for product_market_tags
buy_origin = markets[origin_city]["products"][product_id]["buy_base_usd"]
sell_remote = markets[dest_city]["products"][product_id]["sell_base_usd"]
sell_buy_ratio = sell_remote / buy_origin if buy_origin > 0 else 1.0

if sell_buy_ratio >= 1.15:
    tag = "hot"
elif sell_buy_ratio >= 1.0:
    tag = "normal"
else:
    tag = "cold"

key = f"{origin_city}|{product_id}"
if key not in product_market_tags:
    product_market_tags[key] = {"hot": [], "normal": [], "cold": []}
product_market_tags[key][tag].append(dest_city)
```

At file top, initialize `product_market_tags = {}` before the city loop. At JSON write section, add `"product_market_tags": product_market_tags` to the output dict alongside existing `markets`, `products`, `hubs`.

- [ ] **Step 4: Run ETL pipeline and verify tests pass**

```bash
cd /Users/zero/project/flyyy && python etl/scripts/run_pipeline.py
cd /Users/zero/project/flyyy && python -m pytest tests/etl/test_trade_contracts.py::test_sell_buy_ratio_tags_exist tests/etl/test_trade_contracts.py::test_sell_buy_ratio_hot_threshold tests/etl/test_trade_contracts.py::test_sell_buy_ratio_cold_threshold tests/etl/test_trade_contracts.py::test_sell_buy_ratio_no_city_duplicates -v
```
Expected: all 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add etl/scripts/run_pipeline.py tests/etl/test_trade_contracts.py game/data/world.json
git commit -m "feat(etl): add sell_buy_ratio tags (hot/normal/cold) to world.json"
```

---

### Task 2: PopupEvent — Reusable Event Dialog Component

**Files:**
- Create: `game/scripts/components/PopupEvent.gd`
- Create: `game/scenes/PopupEvent.tscn`

**Interfaces:**
- Produces: `PopupEvent` scene (extends `AcceptDialog`), callable with `show_event(type: String, data: Dictionary)`
- Signals: `confirmed`, `cancelled`
- Methods: `get_result() -> Dictionary` (returns `{"accepted": true/false, "type": type, "data": data}`)

- [ ] **Step 1: Create PopupEvent.gd**

```gdscript
extends AcceptDialog
class_name PopupEvent

## PopupEvent — reusable dialog for all surprise events and sell results.
## Call show_event(type, data) to configure and display.
## Emits event_confirmed or event_cancelled after user choice.

signal event_confirmed(result: Dictionary)
signal event_cancelled(result: Dictionary)

var _event_type: String = ""
var _event_data: Dictionary = {}

func show_event(event_type: String, data: Dictionary = {}) -> void:
	_event_type = event_type
	_event_data = data
	_configure()
	popup_centered()

func _configure() -> void:
	match _event_type:
		"arrival_discount":
			title = "偶遇商机！"
			_show_two_button(data.get("product_name", ""), data.get("discount_pct", 0))
		"free_cargo":
			title = "舱位福利"
			_show_two_button("额外 +50kg 免费货运", 0)
		"accidental_premium":
			title = "意外溢价！"
			_show_one_button(data.get("bonus_pct", 0), data.get("original", 0.0), data.get("premium", 0.0))
		"sell_result":
			title = ""
			_show_sell_result(data)

func _show_two_button(item_desc: String, discount_pct: int = 0) -> void:
	var body := ""
	if _event_type == "arrival_discount":
		body = "本地经销商清仓，\n" + item_desc + " 限时折扣 " + str(discount_pct) + "%\n\n" + "剩余 2 小时（游戏时间）"
		add_button("趁机买入", true)
		add_cancel_button("不了谢谢")
	elif _event_type == "free_cargo":
		body = "该航班货舱有空位，额外 +50kg cargo 本次免费（原价 $380）"
		add_button("接受", true)
		add_cancel_button("不用")
	dialog_text = body

func _show_one_button(bonus_pct: int, original: float, premium: float) -> void:
	dialog_text = (
		"买家急需这批货！\n"
		+ "本次售价额外加成 +" + str(bonus_pct) + "%\n\n"
		+ "原售出价：$" + str(original) + "\n"
		+ "溢价后：$" + str(premium)
	)
	add_button("成交！", true)

func _show_sell_result(data: Dictionary) -> void:
	# Handled by MainHUD._show_sell_result_card — this variant just displays result card content
	dialog_text = ""  # populated by caller
	# One close button only
	add_button("继续", true)

func _on_confirmed() -> void:
	event_confirmed.emit({"accepted": true, "type": _event_type, "data": _event_data})

func _on_cancelled() -> void:
	event_cancelled.emit({"accepted": false, "type": _event_type, "data": _event_data})

# Seed generation helper — deterministic hash for event triggers
static func event_seed(city_id: String, date_hour: int, product_id: String = "", event_type: String = "") -> int:
	var raw := str(city_id) + str(date_hour) + str(product_id) + event_type
	return hash(raw)
```

- [ ] **Step 2: Create PopupEvent.tscn**

In Godot editor, create a scene with root node `PopupEvent` (extends AcceptDialog):
- Set `dialog_autowrap = true`
- Set `size = Vector2(400, 250)` (approximate, adjust after testing)
- Connect `confirmed` signal to `_on_confirmed`
- Connect `canceled` signal to `_on_cancelled`

- [ ] **Step 3: Commit**

```bash
git add game/scripts/components/PopupEvent.gd game/scenes/PopupEvent.tscn
git commit -m "feat: add PopupEvent reusable dialog component with 4 event types"
```

---

### Task 3: FeedbackParticles — Parameterized Particle Effects Scene

**Files:**
- Create: `game/scripts/components/FeedbackParticles.gd`
- Create: `game/scenes/FeedbackParticles.tscn`

**Interfaces:**
- Produces: `FeedbackParticles` scene, callable with `play(config: Dictionary)` where config keys: `palette` (String: "grey"/"gold"/"gold_rain"), `count` (int), `duration` (float), `direction` (String: "down"/"right_arc")
- Auto-frees after duration

- [ ] **Step 1: Create FeedbackParticles.gd**

```gdscript
extends Node2D
class_name FeedbackParticles

## FeedbackParticles — parameterized transient particle effects for sell feedback.
## Call FeedbackParticles.play(config) to spawn and auto-free after duration.

static func play(parent: Node, config: Dictionary) -> void:
	var particles := FeedbackParticles.new()
	particles._config = config
	parent.add_child(particles)
	particles._start()

var _config: Dictionary = {}
var _elapsed: float = 0.0

func _start() -> void:
	var count: int = _config.get("count", 20)
	var palette: String = _config.get("palette", "gold")
	var duration: float = _config.get("duration", 2.0)
	var direction: String = _config.get("direction", "right_arc")

	for i in range(count):
		var dot := ColorRect.new()
		dot.size = Vector2(8, 8)
		match palette:
			"grey":
				dot.color = Color(0.5, 0.5, 0.5, 0.7)
			"gold", "gold_rain":
				dot.color = Color(1.0, 0.84, 0.0, 0.85)
		add_child(dot)

		var start_pos := Vector2(0, 0)
		match direction:
			"down":
				start_pos = Vector2(randf_range(100, 900), 0)
			"right_arc":
				start_pos = Vector2(800, randf_range(200, 600))

		dot.position = start_pos

		var tween := create_tween()
		tween.tween_property(dot, "position", start_pos + Vector2(randf_range(-100, 100), randf_range(200, 500)), duration)
		tween.parallel().tween_property(dot, "modulate:a", 0.0, duration)

	# Gold flash overlay for W2
	if palette == "gold_rain":
		var flash := ColorRect.new()
		flash.color = Color(1.0, 0.84, 0.0, 0.3)
		flash.size = get_viewport().get_visible_rect().size
		flash.position = Vector2.ZERO
		add_child(flash)
		var flash_tween := create_tween()
		flash_tween.tween_property(flash, "modulate:a", 0.0, 0.5)

	# Auto-free after longest tween completes
	await get_tree().create_timer(duration + 0.05).timeout
	queue_free()
```

- [ ] **Step 2: Create FeedbackParticles.tscn**

In Godot editor, create a scene with root `Node2D`, attach script `FeedbackParticles.gd`. No children needed — particles created programmatically.

- [ ] **Step 3: Commit**

```bash
git add game/scripts/components/FeedbackParticles.gd game/scenes/FeedbackParticles.tscn
git commit -m "feat: add FeedbackParticles parameterized particle effects for sell animations"
```

---

### Task 4: AppState — Sell Transaction Log for Voyage Notes

**Files:**
- Modify: `game/scripts/autoload/AppState.gd`

**Interfaces:**
- Produces: `AppState.sell_transactions` (Array[Dictionary]), `AppState.log_sell_transaction(data: Dictionary)`
- Consumed by: Task 8 (Voyage Notes tab)

- [ ] **Step 1: Add sell_transactions array and log_sell_transaction method**

In `AppState.gd`, add at top (near other state variables):

```gdscript
# Sell transaction log for voyage notes (Task 4)
var sell_transactions: Array[Dictionary] = []
```

Add method:

```gdscript
## Log a completed sell transaction. Persists to save file (already in serialized state).
func log_sell_transaction(sell_city: String, product_id: String, qty: int,
		total_revenue: float, total_unit_cost: float, game_timestamp: float) -> void:
	sell_transactions.append({
		"sell_city": sell_city,
		"product_id": product_id,
		"qty": qty,
		"total_revenue": total_revenue,
		"total_unit_cost": total_unit_cost,
		"margin": total_revenue - total_unit_cost,
		"timestamp": game_timestamp
	})
```

Ensure `sell_transactions` is included in serialization/deserialization if the save system uses explicit field lists. If `AppState` uses `get_property_list()` or manual dict serialization, add `sell_transactions` to the saved dict keys. Print a warning to console if the save system path is not obvious:

```bash
# Check current serialization approach
cd /Users/zero/project/flyyy && rg -n "save|serialize|to_dict|from_dict" game/scripts/autoload/AppState.gd | head -20
```

- [ ] **Step 2: Run existing tests to verify no regression**

```bash
cd /Users/zero/project/flyyy && python -m pytest tests/game/test_content_assets.py -v --tb=short
```

- [ ] **Step 3: Commit**

```bash
git add game/scripts/autoload/AppState.gd
git commit -m "feat: add sell_transactions log to AppState for voyage notes"
```

---

### Task 5: EconomySystem — Extended Sell Response with Margin Data

**Files:**
- Modify: `game/scripts/systems/EconomySystem.gd`

**Interfaces:**
- Modifies: `sell()` method return value — extends existing return dict with `margin`, `margin_rate`, `accidental_premium`, `total_cost`
- Consumed by: Task 13 (sell animation tier determination)

- [ ] **Step 1: Extend EconomySystem.sell() return dict**

In `EconomySystem.gd`, find the `sell()` method. After computing `sell_price`, `revenue`, and crediting cash, extend the return dictionary:

```gdscript
# Existing return structure (reference — find actual return statement):
# return {"revenue": revenue, "qty": qty, ...}

# After computing revenue and deducting inventory:
var total_unit_cost: float = qty * unit_cost
var margin: float = revenue - total_unit_cost

var result := {
	"success": true,
	"revenue": revenue,
	"qty": qty,
	"product_id": product_id,
	"unit_price": sell_price,
	"total_unit_cost": total_unit_cost,
	"margin": margin,
	"margin_rate": margin / total_unit_cost if total_unit_cost > 0 else 0.0,
	"accidental_premium": false,
	"accidental_premium_bonus": 0.0,
}
return result
```

Replace the existing return statement (which currently returns a simpler dict or emits a signal) with this extended struct. If the current sell method uses signals (`EventBus.sell_completed.emit(...)`), pass the same extended data through the signal's arguments.

- [ ] **Step 2: Verify sell still works after change**

Build and run the game, perform a sell action, confirm no errors in console.

- [ ] **Step 3: Commit**

```bash
git add game/scripts/systems/EconomySystem.gd
git commit -m "feat: extend EconomySystem.sell() return with margin/margin_rate for sell animations"
```

---

### Task 6: Market Tab — Free Intelligence Labels

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (Market tab section)

**Interfaces:**
- Reads: `world.json` → `product_market_tags` (loaded via `DataStore` or similar)
- Consumed by: Task 7 (paid upgrade labels)

- [ ] **Step 1: Load product_market_tags at startup**

In `MainHUD._ready()` or wherever `world.json` data is loaded, cache:

```gdscript
var _product_market_tags: Dictionary = {}

func _load_market_tags() -> void:
	var world_data = DataStore.get_world_data()  # adjust to actual data source path
	_product_market_tags = world_data.get("product_market_tags", {})
```

If the data loading path uses a different singleton/method in the existing codebase, read the actual `MainHUD.gd` to find how `world.json` products/markets are accessed and follow the same pattern. The key point is: `_product_market_tags` is available as a dict keyed by `"{origin_id}|{product_id}"`.

- [ ] **Step 2: Add label to each product row in Market tab**

In the method that builds the Market product list (likely `_populate_market_list()` or similar), for each product row after setting the buy/sell preview values, add:

```gdscript
var current_city := AppState.current_city_id
var origin_city := current_city  # buying at current location
var ticket_dest := AppState.active_ticket_destination  # or AppState.last_purchased_ticket.destination

var tag_key := "%s|%s" % [origin_city, product_id]
var tags := _product_market_tags.get(tag_key, {})

var label := Label.new()
if ticket_dest != "":
	if ticket_dest in tags.get("hot", []):
		label.text = "📍%s热卖" % ticket_dest
		label.add_theme_color_override("font_color", Color.GREEN)
	elif ticket_dest in tags.get("normal", []):
		label.text = "📍%s可售" % ticket_dest
		label.add_theme_color_override("font_color", Color.WHITE)
	elif ticket_dest in tags.get("cold", []):
		label.text = "⚠️不建议"
		label.add_theme_color_override("font_color", Color.RED)
	else:
		label.text = ""
else:
	# No ticket — find best hot destination
	var hot_cities := tags.get("hot", [])
	if hot_cities.size() > 0:
		label.text = "⭐最佳目的地：" + hot_cities[0]
		label.add_theme_color_override("font_color", Color.GOLD)
	else:
		label.text = ""

product_row.add_child(label)
```

**Read the actual MainHUD.gd Market tab code first** to find the exact method, variable names, row container type, and how existing UI elements are added. Adapt the variable names above to match actual code patterns.

- [ ] **Step 3: Manual smoke test**

Launch game, navigate to a city, buy a ticket, open Market tab — verify labels appear with correct colors and city names.

- [ ] **Step 4: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add free intelligence labels (hot/normal/cold) to Market tab"
```

---

### Task 7: Market Tab — Paid Precision Upgrade

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (same Market tab section as Task 6)

**Interfaces:**
- Consumes: `product_market_tags` from Task 6, `EconomySystem.sell_price()` formula
- Produces: "预计毛利 $X – $Y" labels that replace free labels after purchase

- [ ] **Step 1: Add upgrade button next to each free label**

In the same Market row build method from Task 6, add a small button next to the free label:

```gdscript
var upgrade_btn := Button.new()
upgrade_btn.text = "🔍"
upgrade_btn.tooltip_text = "精准预测 ($200)"
upgrade_btn.custom_minimum_size = Vector2(28, 28)
upgrade_btn.pressed.connect(_on_upgrade_intel.bind(product_id, product_row))
label.add_sibling(upgrade_btn)
```

- [ ] **Step 2: Implement _on_upgrade_intel handler**

```gdscript
const INTEL_UPGRADE_COST := 200.0

func _on_upgrade_intel(product_id: String, product_row: Node) -> void:
	if AppState.cash < INTEL_UPGRADE_COST:
		_show_error("资金不足")
		return

	var current_city := AppState.current_city_id
	var ticket_dest := AppState.active_ticket_destination
	if ticket_dest == "":
		_show_error("请先购买机票")
		return

	AppState.cash -= INTEL_UPGRADE_COST

	var market_data := _get_market_data(product_id)  # existing accessor
	var buy_price := market_data["buy_base_usd"]
	var sell_price_est := EconomySystem.sell_price_estimate(product_id, ticket_dest)

	var daily_amp := 0.06
	var low := (sell_price_est * buy_price * (1.0 - daily_amp)) - (buy_price * 1.0)
	var high := (sell_price_est * buy_price * (1.0 + daily_amp)) - (buy_price * 1.0)

	var free_label: Label = product_row.find_child("IntelligenceLabel", true, false)
	if free_label:
		free_label.text = "预计毛利 $" + str(int(low)) + "–$" + str(int(high))
		free_label.add_theme_color_override("font_color", Color.CYAN)
```

**Note:** The `sell_price_estimate` function does not currently exist in `EconomySystem`. You need to add it:

In `EconomySystem.gd`:

```gdscript
## Static approximate sell price — for UI preview, not actual transaction.
## Returns the sell_base_usd from world data (no runtime modifiers applied).
static func sell_price_estimate(product_id: String, dest_city: String) -> float:
	var world_data := DataStore.get_world_data()
	var dest_city_data := world_data["markets"].get(dest_city, {})
	var product_data := dest_city_data.get("products", {}).get(product_id, {})
	return product_data.get("sell_base_usd", 0.0)
```

Add this to `EconomySystem.gd` as part of this task.

- [ ] **Step 3: Manual smoke test**

Buy ticket → open Market → click 🔍 on a product → verify $200 deducted, label changes to margin range.

- [ ] **Step 4: Commit**

```bash
git add game/scripts/ui/MainHUD.gd game/scripts/systems/EconomySystem.gd
git commit -m "feat: add paid precision upgrade ($200) for intelligence margin range"
```

---

### Task 8: Voyage Notes Tab

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (new tab next to Inventory)

**Interfaces:**
- Reads: `AppState.sell_transactions` (Task 4)
- Produces: "Notes" tab in the MainHUD tab bar

- [ ] **Step 1: Add Notes tab to MainHUD tab container**

In `MainHUD._ready()`, add a new tab alongside existing Market / Inventory / Flights tabs:

```gdscript
var notes_tab := _create_notes_tab()
tab_container.add_child(notes_tab)
tab_container.set_tab_title(tab_container.get_tab_idx_from_node(notes_tab), "笔记")
```

- [ ] **Step 2: Implement _create_notes_tab()**

```gdscript
func _create_notes_tab() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Group transactions by city
	var by_city: Dictionary = {}
	for tx in AppState.sell_transactions:
		var city := tx["sell_city"]
		if city not in by_city:
			by_city[city] = []
		by_city[city].append(tx)

	for city in by_city:
		var city_section := VBoxContainer.new()
		var header := Label.new()
		header.text = "📒 " + city + " 交易笔记"
		header.add_theme_font_size_override("font_size", 16)
		city_section.add_child(header)

		var total_margin: float = 0.0
		var wins: int = 0
		var losses: int = 0
		for tx in by_city[city]:
			var row := Label.new()
			var margin := tx["margin"]
			total_margin += margin
			var emoji := "✅" if margin >= 0 else "❌"
			if margin >= 0:
				wins += 1
			else:
				losses += 1
			row.text = "  %s：毛利 %s$%s" % [tx["product_id"], emoji, str(int(margin))]
			city_section.add_child(row)

		var sep := HSeparator.new()
		city_section.add_child(sep)

		var summary := Label.new()
		summary.text = "  %d赚 %d亏  净利 $%d" % [wins, losses, int(total_margin)]
		city_section.add_child(summary)

		vbox.add_child(city_section)

	return scroll
```

- [ ] **Step 3: Refresh notes tab on tab selection**

Connect tab_changed signal to refresh notes content when the Notes tab is selected:

```gdscript
tab_container.tab_changed.connect(_on_tab_changed)

func _on_tab_changed(idx: int) -> void:
	if tab_container.get_tab_title(idx) == "笔记":
		# Rebuild notes content
		var notes_scroll := tab_container.get_tab_control(idx) as ScrollContainer
		var vbox := notes_scroll.get_child(0) as VBoxContainer
		for child in vbox.get_children():
			child.queue_free()
		# Re-populate (call helper that rebuilds content)
		_populate_notes(vbox)
```

- [ ] **Step 4: Manual smoke test**

Sell some items → switch to Notes tab → verify entries appear grouped by city with correct margin counts.

- [ ] **Step 5: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add voyage notes tab with city-grouped sell transaction history"
```

---

### Task 9: Surprise Event 1 — Arrival Discount Encounter

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (arrival hook), `game/scripts/components/PopupEvent.gd` (Task 2)

**Interfaces:**
- Consumes: PopupEvent.show_event("arrival_discount", data), hash seed from PopupEvent.event_seed()
- Trigger: arrival at new city

- [ ] **Step 1: Wire arrival encounter in MainHUD**

In the arrival handler (where the city transition concludes and Market/Inventory tabs refresh), after existing logic:

```gdscript
func _on_arrival_complete(city_id: String) -> void:
	# ... existing arrival logic (refresh tabs, flight overlay, etc.) ...

	# Check for arrival encounter
	_check_arrival_encounter(city_id)
```

- [ ] **Step 2: Implement _check_arrival_encounter**

```gdscript
func _check_arrival_encounter(city_id: String) -> void:
	var date_hour := int(AppState.game_time_seconds / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, "", "arrival_discount")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if rng.randf() > 0.20:
		return  # 80% no event

	# Pick a random product available in this city
	var market_products := _get_market_products(city_id)  # existing method or add simple accessor
	if market_products.size() == 0:
		return
	var product_idx := rng.randi() % market_products.size()
	var product_id := market_products[product_idx]
	var discount_pct := rng.randi_range(20, 40)

	var popup := load("res://scenes/PopupEvent.tscn").instantiate()
	popup.event_confirmed.connect(_on_arrival_discount_accepted.bind(product_id, discount_pct))
	popup.event_cancelled.connect(_on_arrival_discount_declined.bind())
	add_child(popup)
	popup.show_event("arrival_discount", {
		"product_name": product_id,
		"discount_pct": discount_pct,
		"product_id": product_id,
	})

	# Store active discount for current stay
	_active_arrival_discount = {
		"product_id": product_id,
		"discount_pct": discount_pct,
		"city_id": city_id,
	}
```

- [ ] **Step 3: Implement discount application on buy**

When the player buys the discounted product (in the existing buy handler in Market tab), check `_active_arrival_discount`:

```gdscript
# Inside buy handler, after computing buy_price:
if (_active_arrival_discount.get("product_id", "") == product_id
		and _active_arrival_discount.get("city_id", "") == AppState.current_city_id):
	var discount := 1.0 - float(_active_arrival_discount["discount_pct"]) / 100.0
	buy_price = buy_price * discount
```

Clear `_active_arrival_discount = {}` on city departure.

- [ ] **Step 4: Manual smoke test**

Fly to a new city ~5 times, verify occasionally (~20%) the discount popup appears; accept and buy the product at reduced price.

- [ ] **Step 5: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add arrival discount encounter (20% chance, 20-40% off one product)"
```

---

### Task 10: Surprise Event 2 — Free Cargo Slot

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (same arrival hook as Task 9)

**Interfaces:**
- Consumes: PopupEvent.show_event("free_cargo", data)
- Produces: sets `_free_cargo_on_flight = true` flag used by ticket/baggage purchase logic

- [ ] **Step 1: Wire free cargo check in arrival handler**

In `_on_arrival_complete()`, add after arrival discount check:

```gdscript
	_check_free_cargo(city_id)
```

- [ ] **Step 2: Implement _check_free_cargo**

```gdscript
func _check_free_cargo(city_id: String) -> void:
	var date_hour := int(AppState.game_time_seconds / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, "", "free_cargo")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if rng.randf() > 0.10:
		return

	var popup := load("res://scenes/PopupEvent.tscn").instantiate()
	popup.event_confirmed.connect(_on_free_cargo_accepted.bind())
	popup.event_cancelled.connect(_on_free_cargo_declined.bind())
	add_child(popup)
	popup.show_event("free_cargo", {})

func _on_free_cargo_accepted() -> void:
	_free_cargo_on_flight = true

func _on_free_cargo_declined() -> void:
	_free_cargo_on_flight = false
```

Also trigger on ticket purchase (after `_on_ticket_purchased` or similar): call `_check_free_cargo(AppState.current_city_id)` again — this time the seed includes a different event_type or moment, so it's a separate roll.

- [ ] **Step 3: Apply free cargo when buying ticket**

In the ticket purchase flow, if player adds cargo:

```gdscript
# In baggage/cargo selection UI:
var cargo_price := 380.0
if _free_cargo_on_flight:
	cargo_price = 0.0
	_free_cargo_on_flight = false  # consumed
```

- [ ] **Step 4: Manual smoke test**

Arrive at cities or buy tickets ~10 times, verify occasional free cargo offer and $0 charge when accepted.

- [ ] **Step 5: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add free cargo slot event (10% on arrival/after ticket purchase)"
```

---

### Task 11: Surprise Event 3 — Accidental Premium on Sell

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (sell flow)

**Interfaces:**
- Consumes: PopupEvent.show_event("accidental_premium", data), EconomySystem sell result
- Modifies: sell_revenue before crediting cash

- [ ] **Step 1: Intercept sell flow before cash credit**

In the sell handler (where user confirms sell and EconomySystem.sell() is called), after computing base sell_price but before crediting cash:

```gdscript
func _on_sell_confirmed(product_id: String, qty: int) -> void:
	var sell_result := EconomySystem.sell(product_id, qty, AppState.current_city_id)
	if not sell_result["success"]:
		return

	# Check for accidental premium
	_check_accidental_premium(sell_result, product_id)
```

- [ ] **Step 2: Implement _check_accidental_premium**

```gdscript
func _check_accidental_premium(sell_result: Dictionary, product_id: String) -> void:
	var city_id := AppState.current_city_id
	var date_hour := int(AppState.game_time_seconds / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, product_id, "accidental_premium")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var base_chance := 0.075  # 7.5%, midpoint of 5-10%
	if rng.randf() > base_chance:
		_show_sell_result_card(sell_result)
		return

	var bonus_pct := rng.randi_range(20, 35)
	var original_revenue := sell_result["revenue"]
	var premium_revenue := original_revenue * (1.0 + float(bonus_pct) / 100.0)

	var popup := load("res://scenes/PopupEvent.tscn").instantiate()
	popup.event_confirmed.connect(_on_premium_accepted.bind(sell_result, bonus_pct, premium_revenue))
	add_child(popup)
	popup.show_event("accidental_premium", {
		"bonus_pct": bonus_pct,
		"original": int(original_revenue),
		"premium": int(premium_revenue),
	})

func _on_premium_accepted(sell_result: Dictionary, bonus_pct: int, premium_revenue: float) -> void:
	# Update sell result with premium
	sell_result["revenue"] = premium_revenue
	sell_result["margin"] = premium_revenue - sell_result["total_unit_cost"]
	sell_result["margin_rate"] = sell_result["margin"] / sell_result["total_unit_cost"] if sell_result["total_unit_cost"] > 0 else 0.0
	sell_result["accidental_premium"] = true
	sell_result["accidental_premium_bonus"] = bonus_pct

	# Credit the extra cash difference
	var extra_cash := premium_revenue - (premium_revenue / (1.0 + float(bonus_pct) / 100.0))
	AppState.cash += extra_cash

	_show_sell_result_card(sell_result)
```

- [ ] **Step 3: Manual smoke test**

Sell items ~20 times, verify occasionally (~5-10% of sells) the premium popup appears with 20-35% bonus.

- [ ] **Step 4: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add accidental premium event on sell (5-10% chance, 20-35% bonus)"
```

---

### Task 12: Surprise Event 4 — City-Exclusive Discovery (after Sell)

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (after-sell hook)

**Interfaces:**
- Consumes: PopupEvent, product_market_tags (cold check)
- Produces: instant sell-all at 2× price for matching product in inventory

- [ ] **Step 1: Implement check after a successful sell in cold city**

After `_show_sell_result_card()` completes and sell is finalized:

```gdscript
func _after_sell_check_discovery(sold_product_id: String) -> void:
	var city_id := AppState.current_city_id
	var origin_city := AppState.current_city_id  # where it was bought — stored in inventory stack

	# Check if this destination is COLD for the product
	var tag_key := "%s|%s" % [origin_city, sold_product_id]
	var tags := _product_market_tags.get(tag_key, {})
	if city_id not in tags.get("cold", []):
		return

	# Check if player still has more of this product in inventory
	if not _player_has_more_of(sold_product_id):
		return

	# Roll for discovery
	var date_hour := int(AppState.game_time_seconds / 3600.0)
	var seed_val := PopupEvent.event_seed(city_id, date_hour, sold_product_id, "city_discovery")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	if rng.randf() > 0.05:
		return

	# Check already triggered this stay
	if _discovery_triggered_in_city.has(city_id + "|" + sold_product_id):
		return
	_discovery_triggered_in_city[city_id + "|" + sold_product_id] = true

	var popup := load("res://scenes/PopupEvent.tscn").instantiate()
	popup.event_confirmed.connect(_on_discovery_sell_all.bind(sold_product_id, city_id))
	add_child(popup)
	popup.dialog_text = (
		'"这里的人从没见过%s！"\n\n库存中所有%s 卖出价额外 ×2.0'
		% [sold_product_id, sold_product_id]
	)
	popup.title = "✨ 意外发现！"
	popup.add_button("全部溢价卖出", true)
	popup.add_cancel_button("暂不处理")
	popup.popup_centered()
```

- [ ] **Step 2: Implement _on_discovery_sell_all**

```gdscript
func _on_discovery_sell_all(product_id: String, city_id: String) -> void:
	var total_revenue: float = 0.0
	var total_cost: float = 0.0
	var total_qty: int = 0

	# Find all stacks of this product across baggage and cargo
	for stack in AppState.inventory:
		if stack["product_id"] == product_id:
			var sell_price := EconomySystem.sell_price_estimate(product_id, city_id) * 2.0
			var revenue := sell_price * stack["qty"]
			total_revenue += revenue
			total_cost += stack["unit_cost"] * stack["qty"]
			total_qty += stack["qty"]
			AppState.cash += revenue

	# Remove all stacks of this product
	AppState.inventory = AppState.inventory.filter(func(s): return s["product_id"] != product_id)

	# Show result card
	_show_sell_result_card({
		"revenue": total_revenue,
		"qty": total_qty,
		"product_id": product_id,
		"unit_price": total_revenue / total_qty if total_qty > 0 else 0,
		"total_unit_cost": total_cost,
		"margin": total_revenue - total_cost,
		"margin_rate": (total_revenue - total_cost) / total_cost if total_cost > 0 else 0,
		"accidental_premium": true,  # triggers W2 tier always
		"accidental_premium_bonus": 100,  # represents 2x
		"discovery_bonus": true,
	})

	EventBus.cash_changed.emit(AppState.cash)
```

- [ ] **Step 3: Manual smoke test**

Buy a product, fly to a cold-tag city, sell one unit, check if the "意外发现" popup appears occasionally (5%). When it does, verify all remaining units sell at 2×.

- [ ] **Step 4: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add city-exclusive discovery event (5% in cold city, 2x sell-all)"
```

---

### Task 13: Five-Tier Sell Feedback Animation System

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd`
- Uses: `FeedbackParticles` (Task 3), `PopupEvent` sell_result variant (Task 2)

**Interfaces:**
- Consumes: sell_result dict from EconomySystem (Task 5), premium from Task 11, discovery from Task 12
- Produces: tier-based visual/audio feedback

- [ ] **Step 1: Determine tier from margin data**

```gdscript
func _determine_sell_tier(margin: float, margin_rate: float, accidental_premium: bool) -> String:
	if accidental_premium or margin >= 10000:
		return "W2"  # Grand Slam
	elif margin >= 3000:
		return "W1"  # Big Win
	elif margin >= 0:
		return "W0"  # Normal Win
	elif margin_rate >= -0.20:
		return "L1"  # Small Loss
	else:
		return "L2"  # Big Loss
```

- [ ] **Step 2: Build and display sell result card**

```gdscript
var _sell_console_lines := [
	"没事，学费而已",
	"下一趟回本",
	"做生意就是这样",
	"这个城市不太行",
	"及时止损也是赢",
]
var _sell_console_big_loss := "赔大了...但旅行本身就值得"
var _celebration_w1 := ["这笔漂亮！", "眼光不错", "路走对了"]
var _celebration_w2 := ["传奇交易！", "你就是这条航线的王", "同行看了都眼红"]

func _show_sell_result_card(sell_result: Dictionary) -> void:
	var tier := _determine_sell_tier(
		sell_result["margin"], sell_result["margin_rate"],
		sell_result.get("accidental_premium", false)
	)

	var popup := load("res://scenes/PopupEvent.tscn").instantiate()

	match tier:
		"L2":
			popup.title = "交易亏损"
			# Spawn paper shred particles
			FeedbackParticles.play(self, {"palette": "grey", "count": 25, "duration": 2.0, "direction": "down"})
			# Play sound
			AudioManager.play_sfx("sfx_loss")

		"L1":
			popup.title = "交易亏损"
			AudioManager.play_sfx("sfx_loss_light")

		"W0":
			popup.title = "交易成功"
			AudioManager.play_sfx("sfx_sell")  # existing

		"W1":
			popup.title = "大赚一笔！"
			FeedbackParticles.play(self, {"palette": "gold", "count": 30, "duration": 2.0, "direction": "right_arc"})
			AudioManager.play_sfx("sfx_big_win")

		"W2":
			popup.title = "大满贯！"
			if sell_result.get("discovery_bonus", false):
				popup.title = "✨发现者加成 — 大满贯！"
			FeedbackParticles.play(self, {"palette": "gold_rain", "count": 60, "duration": 3.0, "direction": "down"})
			AudioManager.play_sfx("sfx_grand_slam")

	# Build card body text
	var body := ""
	body += "售出数量：" + str(sell_result["qty"]) + "\n"
	body += "售出收入：$" + str(int(sell_result["revenue"])) + "\n"

	var margin := sell_result["margin"]
	var sign := "+" if margin >= 0 else ""
	body += "账面毛利：" + sign + "$" + str(int(margin)) + "\n"

	# Net trip profit hint
	var flight_cost := AppState.last_flight_price if AppState.has("last_flight_price") else 0.0
	var baggage_cost := AppState.last_baggage_cost if AppState.has("last_baggage_cost") else 0.0
	if flight_cost > 0 or baggage_cost > 0:
		body += "本趟机票：−$" + str(int(flight_cost))
		if baggage_cost > 0:
			body += "  行李/货运：−$" + str(int(baggage_cost))
		body += "\n"
		var net := margin - flight_cost - baggage_cost
		var net_sign := "+" if net >= 0 else ""
		body += "──────────────────\n"
		body += "行程净利：" + net_sign + "$" + str(int(net)) + "\n"

	# Consolation or celebration copy
	match tier:
		"L2":
			body += "\n" + _sell_console_big_loss
		"L1":
			body += "\n" + _sell_console_lines[randi() % _sell_console_lines.size()]
		"W1":
			body += "\n" + _celebration_w1[randi() % _celebration_w1.size()]
		"W2":
			body += "\n" + _celebration_w2[randi() % _celebration_w2.size()]

	# Wealth milestone toast
	if AppState.cash >= 100000 or AppState.cash >= AppState.starting_cash * 2.0:
		# Show toast (use existing hint system or a short Label)
		_show_toast("财富里程碑！")

	popup.dialog_text = body
	popup.add_button("继续", true)
	popup.popup_centered()

	add_child(popup)

	# Cash roll animation (Task 14 will wire this)
```

- [ ] **Step 3: Log sell transaction for voyage notes**

At the end of `_show_sell_result_card`, after popup closes:

```gdscript
	popup.event_confirmed.connect(func(_r):
		AppState.log_sell_transaction(
			AppState.current_city_id,
			sell_result["product_id"],
			sell_result["qty"],
			sell_result["revenue"],
			sell_result["total_unit_cost"],
			AppState.game_time_seconds
		)
		_cash_roll_animation(int(sell_result["revenue"] - sell_result["total_unit_cost"]))
		EventBus.cash_changed.emit(AppState.cash)
	)
```

- [ ] **Step 4: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add five-tier sell feedback animation system (L2-W2) with particles and copy"
```

---

### Task 14: Cash Number Rolling Animation

**Files:**
- Modify: `game/scripts/ui/MainHUD.gd` (cash display section)

**Interfaces:**
- Reads: `AppState.cash` before and after sell
- Produces: ease-out animated cash number

- [ ] **Step 1: Implement _cash_roll_animation**

```gdscript
func _cash_roll_animation(delta_margin: float) -> void:
	var cash_label: Label = _find_cash_label()  # find the existing cash Label in HUD
	if not cash_label:
		return

	var old_value: float = AppState.cash - delta_margin
	var new_value: float = AppState.cash
	var duration := 1.0
	var is_grand_slam := delta_margin >= 10000

	if is_grand_slam:
		duration = 0.5  # double speed
		# Flash gold once
		cash_label.add_theme_color_override("font_color", Color.GOLD)
		await get_tree().create_timer(0.3).timeout
		cash_label.remove_theme_color_override("font_color")

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.tween_method(_update_cash_display.bind(cash_label), old_value, new_value, duration)

func _update_cash_display(value: float, label: Label) -> void:
	label.text = "$" + str(int(value))

func _find_cash_label() -> Label:
	# Search the HUD scene tree for the cash label
	# Adjust path to match actual MainHUD.tscn structure
	var cash_container := find_child("CashBar", true, false)
	if cash_container:
		return cash_container.find_child("CashValue", true, false)
	return null
```

- [ ] **Step 2: Verify no conflict with existing cash update**

In the existing cash_changed signal handler (if `MainHUD` listens to `EventBus.cash_changed`), add a flag to skip auto-update during roll animation:

```gdscript
var _cash_rolling: bool = false

func _on_cash_changed(new_cash: float) -> void:
	if _cash_rolling:
		return
	var label := _find_cash_label()
	if label:
		label.text = "$" + str(int(new_cash))
```

Set `_cash_rolling = true` at start of roll, `false` at end.

- [ ] **Step 3: Commit**

```bash
git add game/scripts/ui/MainHUD.gd
git commit -m "feat: add cash number ease-out rolling animation after sell"
```

---

### Task 15: I18n — Consolation & Celebration Copy

**Files:**
- Modify: `game/assets/i18n/zh_CN.csv`

**Interfaces:**
- Produces: i18n keys consumed by sell result card (Task 13)

- [ ] **Step 1: Add new keys to zh_CN.csv**

Append to `game/assets/i18n/zh_CN.csv`:

```csv
sell_console_1,"没事，学费而已",en,"It's just tuition"
sell_console_2,"下一趟回本",en,"Next trip will pay it back"
sell_console_3,"做生意就是这样",en,"That's business"
sell_console_4,"这个城市不太行",en,"Wrong city for this"
sell_console_5,"及时止损也是赢",en,"Cutting losses is a win too"
sell_console_big_loss,"赔大了...但旅行本身就值得",en,"Big loss... but the trip was worth it"
celebration_w1_1,"这笔漂亮！",en,"Nice deal!"
celebration_w1_2,"眼光不错",en,"Good eye"
celebration_w1_3,"路走对了",en,"Right call"
celebration_w2_1,"传奇交易！",en,"Legendary deal!"
celebration_w2_2,"你就是这条航线的王",en,"You rule this route!"
celebration_w2_3,"同行看了都眼红",en,"The competition is jealous"
ui.intel.upgrade,"🔍精准预测",en,"Precision Forecast"
ui.intel.cost,"$200",en,"$200"
```

- [ ] **Step 2: Commit**

```bash
git add game/assets/i18n/zh_CN.csv
git commit -m "feat(i18n): add sell consolation, celebration, and intelligence upgrade copy"
```

---

### Task 16: Integration Smoke Test & Final Polish

**Files:**
- Test: `tools/demo_smoke_logic.py` (extend existing smoke test, optional)
- Manual: full gameplay walkthrough

**Interfaces:**
- Tests all subsystems end-to-end

- [ ] **Step 1: Full walkthrough checklist**

Run game, perform this sequence:
1. Start game ($50,000), verify Market tab shows ⭐best destination labels
2. Buy a ticket to Dubai, verify labels change to 📍Dubai热卖/可售/不建议
3. Click 🔍 on a product, verify $200 deducted, label changes to margin range
4. Buy products (at least 2 types, qty 5+ each)
5. Fly to Dubai — verify arrival encounter may pop up (~20%)
6. Accept/free cargo when offered
7. Sell products, verify normal win W0 feedback (green)
8. Repeat flights to different cities — observe hot city usually profitable, cold city usually loss
9. After many sells, check Notes tab shows history grouped by city
10. Trigger accidental premium (may take many attempts) — verify W2 grand slam feedback
11. Trigger cold-city discovery: fly a product to its cold city, sell one, wait for popup

- [ ] **Step 2: Fix any issues found in smoke test**

Log all issues to a file: `docs/superpowers/reviews/2026-07-26-feedback-anchors-fixlist.md`.

Fix issues one by one. Each fix gets its own commit with `fix:` prefix.

- [ ] **Step 3: Run existing test suite to verify no regressions**

```bash
cd /Users/zero/project/flyyy && python -m pytest tests/ -v --tb=short
```

Expect: all tests pass (ETL anchor tests from Task 1 + existing tests).

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final integration polish for trade feedback & anchors"
```
