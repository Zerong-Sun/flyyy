extends Node
## 15-day challenge lifecycle: start, deadline detection, and settlement.
## PRD_01.md §6.2 — world runs 2025-03-01 → 2025-03-15 (inclusive) with eight
## settlement metrics plus a normalized score and A/B/C/D grade.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")

const CHALLENGE_DAYS := 15
const DAY_SECONDS := 86400.0

# Metric normalization caps (value ÷ cap, clamped to 0..1).
const CAP_NET_WORTH := 200000.0
const CAP_CITIES := 500.0
const CAP_COUNTRIES := 100.0
const CAP_PRODUCTS := 800.0
const CAP_DISTANCE_KM := 40075.0
const CAP_SINGLE_PROFIT := 10000.0
const CAP_PROFIT_PER_HOUR := 200.0


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
	AppState.challenge = {
		"start_unix": now,
		"deadline_unix": now + CHALLENGE_DAYS * DAY_SECONDS,
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

	var parts: Array[float] = [
		_normalize(net_worth, CAP_NET_WORTH),
		_normalize(float(AppState.visited_cities.size()), CAP_CITIES),
		_normalize(float(AppState.visited_countries.size()), CAP_COUNTRIES),
		_normalize(float(AppState.stats.get("products_discovered", {}).size()), CAP_PRODUCTS),
		_normalize(float(AppState.stats.get("total_distance_km", 0.0)), CAP_DISTANCE_KM),
		on_time_rate,
		_normalize(float(AppState.stats.get("single_profit_max", 0.0)), CAP_SINGLE_PROFIT),
		_normalize(profit_per_hour, CAP_PROFIT_PER_HOUR),
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
	if score_pct >= 80:
		return "A"
	if score_pct >= 60:
		return "B"
	if score_pct >= 40:
		return "C"
	return "D"
