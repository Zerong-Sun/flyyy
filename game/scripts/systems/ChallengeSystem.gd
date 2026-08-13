extends Node
## 15-day challenge lifecycle: start, deadline detection, and settlement.
## PRD_01.md §6.2 — world runs 2025-03-01 → 2025-03-15 (inclusive) with eight
## settlement metrics plus a normalized score and A/B/C/D grade.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")

const DAY_SECONDS := 86400.0

# Challenge config lives in world.json economy.challenge (single source of
# truth read by Godot, the pytest mirror, and the expo snapshot — GDLC
# Playtest #2 ratchet). Literal fallbacks mirror etl/config/economy.yaml in
# case the data block is absent.
const _DEFAULT_CHALLENGE := {
	"days": 15,
	"cap_net_worth": 200000.0,
	"cap_cities": 60.0,
	"cap_countries": 30.0,
	"cap_products": 350.0,
	"cap_distance_km": 40075.0,
	"cap_single_profit": 10000.0,
	"cap_profit_per_hour": 200.0,
	"grade_a": 80,
	"grade_b": 60,
	"grade_c": 40,
}


func _challenge_cfg() -> Dictionary:
	return DataService.economy.get("challenge", _DEFAULT_CHALLENGE)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.game_started.connect(_on_game_started)


func _process(_delta: float) -> void:
	if not is_active():
		return
	if GameClock.unix_time >= float(AppState.challenge.get("deadline_unix", 0.0)):
		end_challenge()


func _on_game_started() -> void:
	if AppState.game_mode == "challenge" and AppState.challenge.is_empty():
		start_new()
	elif AppState.game_mode == "collector":
		AppState.challenge = {}


func is_active() -> bool:
	return AppState.game_mode == "challenge" \
			and not AppState.challenge.is_empty() \
			and not bool(AppState.challenge.get("ended", false))


func start_new() -> void:
	var now: float = float(GameClock.unix_time)
	var days: float = float(_challenge_cfg().get("days", 15))
	AppState.challenge = {
		"start_unix": now,
		"deadline_unix": now + days * DAY_SECONDS,
		"ended": false,
		"result": {},
	}


func remaining_days() -> float:
	if not is_active():
		return 0.0
	return maxf(0.0, (float(AppState.challenge.get("deadline_unix", 0.0)) - GameClock.unix_time) / DAY_SECONDS)


func compute_metrics() -> Dictionary:
	var net_worth := _net_worth()
	var total_segments := float(AppState.stats.get("total_flight_segments", 0))
	var delayed := float(AppState.stats.get("delayed_flights", 0))
	var on_time_rate := 0.0
	if total_segments > 0.0:
		on_time_rate = clampf((total_segments - delayed) / total_segments, 0.0, 1.0)
	var flight_hours := float(AppState.stats.get("total_flight_hours", 0.0))
	var start_cash := float(DataService.economy.get("starting_cash_usd", 50000.0))
	var profit_per_hour := 0.0
	if flight_hours > 0.0:
		profit_per_hour = maxf(0.0, (net_worth - start_cash) / flight_hours)

	var cfg: Dictionary = _challenge_cfg()
	var parts: Array[float] = [
		_normalize(net_worth, float(cfg.get("cap_net_worth", 200000.0))),
		_normalize(float(AppState.visited_cities.size()), float(cfg.get("cap_cities", 60.0))),
		_normalize(float(AppState.visited_countries.size()), float(cfg.get("cap_countries", 30.0))),
		_normalize(float(AppState.stats.get("products_discovered", {}).size()), float(cfg.get("cap_products", 350.0))),
		_normalize(float(AppState.stats.get("total_distance_km", 0.0)), float(cfg.get("cap_distance_km", 40075.0))),
		on_time_rate,
		_normalize(float(AppState.stats.get("single_profit_max", 0.0)), float(cfg.get("cap_single_profit", 10000.0))),
		_normalize(profit_per_hour, float(cfg.get("cap_profit_per_hour", 200.0))),
	]
	var score_sum := 0.0
	for p in parts:
		score_sum += p
	var score_pct := int(round(score_sum / parts.size() * 100.0))

	return {
		"net_worth": net_worth,
		"visited_cities": AppState.visited_cities.size(),
		"visited_countries": AppState.visited_countries.size(),
		"products_discovered": AppState.stats.get("products_discovered", {}).size(),
		"total_distance_km": AppState.stats.get("total_distance_km", 0.0),
		"on_time_rate": on_time_rate,
		"single_profit_max": AppState.stats.get("single_profit_max", 0.0),
		"profit_per_hour": profit_per_hour,
		"score": score_pct,
		"grade": _grade(score_pct),
	}


func end_challenge() -> void:
	if not AppState.game_mode == "challenge":
		return
	if bool(AppState.challenge.get("ended", false)):
		return
	AppState.challenge["ended"] = true
	AppState.challenge["result"] = compute_metrics()
	GameClock.set_paused(true)
	EventBus.challenge_ended.emit(AppState.challenge["result"])


func _net_worth() -> float:
	var total := AppState.cash_usd
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		var q: float = _Economy.current_quality(item)
		total += _Economy.sell_price(AppState.current_city_id(), str(item.get("product_id", "")), q) * float(item.get("qty", 0))
	return total


func _normalize(value: float, cap: float) -> float:
	if cap <= 0.0:
		return 0.0
	return clampf(value / cap, 0.0, 1.0)


func _grade(score_pct: int) -> String:
	var cfg: Dictionary = _challenge_cfg()
	if score_pct >= int(cfg.get("grade_a", 80)):
		return "A"
	if score_pct >= int(cfg.get("grade_b", 60)):
		return "B"
	if score_pct >= int(cfg.get("grade_c", 40)):
		return "C"
	return "D"
