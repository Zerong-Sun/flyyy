extends Node
## Achievement definitions, evaluation, and unlock tracking.

const DEFS_PATH := "res://data/achievements.json"

const DEMO_HUB_IATAS := [
	"PEK", "PVG", "CAN", "HKG", "NRT", "ICN", "SIN", "BKK",
	"DXB", "IST", "LHR", "CDG", "FRA", "AMS", "JFK", "LAX",
	"ORD", "ATL", "DFW", "MIA",
]

var definitions: Array = []
var loaded: bool = false


func _ready() -> void:
	load_definitions()
	EventBus.arrived.connect(_on_game_event)
	EventBus.sell_completed.connect(_on_sell_completed)
	EventBus.cash_changed.connect(_on_game_event)
	EventBus.ticket_purchased.connect(_on_game_event)


func load_definitions() -> void:
	definitions.clear()
	if not FileAccess.file_exists(DEFS_PATH):
		push_warning("AchievementSystem: missing %s" % DEFS_PATH)
		return
	var f := FileAccess.open(DEFS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	definitions = data.get("achievements", [])
	loaded = true


func is_unlocked(ach_id: String) -> bool:
	return bool(AppState.unlocked_achievements.get(ach_id, false))


func progress_of(ach: Dictionary) -> float:
	var key := str(ach.get("stat_key", ""))
	var target := float(ach.get("target", 1))
	var current := _current_value(key)
	if target <= 0.0:
		return 1.0 if current > 0.0 else 0.0
	return clampf(current / target, 0.0, 1.0)


func current_display(ach: Dictionary) -> String:
	var key := str(ach.get("stat_key", ""))
	var target := float(ach.get("target", 1))
	var current := _current_value(key)
	if key in ["extreme_ns", "extreme_ew", "demo_hubs_visited"]:
		return "%d/%d" % [int(current), int(target)]
	if target >= 100.0:
		return "%d/%d" % [int(current), int(target)]
	return "%.0f/%.0f" % [current, target]


func check_all() -> Array:
	var newly: Array = []
	for ach_v in definitions:
		var ach: Dictionary = ach_v
		var aid := str(ach.get("id", ""))
		if aid == "" or is_unlocked(aid):
			continue
		if _evaluate(ach):
			AppState.unlocked_achievements[aid] = true
			newly.append(ach)
	return newly


func _evaluate(ach: Dictionary) -> bool:
	var key := str(ach.get("stat_key", ""))
	var target := float(ach.get("target", 1))
	return _current_value(key) >= target


func _current_value(stat_key: String) -> float:
	match stat_key:
		"visited_cities":
			return float(AppState.visited_cities.size())
		"visited_countries":
			return float(AppState.visited_countries.size())
		"cash_usd":
			return float(AppState.cash_usd)
		"categories_sold":
			return float(AppState.stats.get("categories_sold", {}).size())
		"products_discovered":
			return float(AppState.stats.get("products_discovered", {}).size())
		"notes_cities":
			var cities: Dictionary = {}
			for tx in AppState.sell_transactions:
				cities[str(tx.get("sell_city", ""))] = true
			return float(cities.size())
		"demo_hubs_visited":
			var n := 0
			for iata in DEMO_HUB_IATAS:
				var a: Dictionary = DataService.get_airport_by_iata(iata)
				if a.is_empty():
					continue
				if AppState.visited_airports.has(str(a.get("airport_id", ""))):
					n += 1
			return float(n)
		"extreme_ns":
			var ex: Dictionary = AppState.stats.get("extreme_airports", {})
			return 1.0 if str(ex.get("north", "")) != "" and str(ex.get("south", "")) != "" else 0.0
		"extreme_ew":
			var ex2: Dictionary = AppState.stats.get("extreme_airports", {})
			return 1.0 if str(ex2.get("east", "")) != "" and str(ex2.get("west", "")) != "" else 0.0
		_:
			return float(AppState.stats.get(stat_key, 0.0))


func _on_game_event(_a = null) -> void:
	_emit_new_unlocks()


func _on_sell_completed(_result: Dictionary = {}) -> void:
	_emit_new_unlocks()


func _emit_new_unlocks() -> void:
	var newly := check_all()
	for ach_v in newly:
		var ach: Dictionary = ach_v
		var msg := "✨ 成就解锁：" + str(ach.get("name", ach.get("id", "")))
		EventBus.tutorial_hint.emit(msg)
		AudioService.play_sfx("sfx_arrive")
