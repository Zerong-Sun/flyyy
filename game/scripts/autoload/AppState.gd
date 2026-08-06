extends Node
## Player runtime state.

const SAVE_VERSION := 1

var save_id: String = ""
var cash_usd: float = 0.0
var current_airport_id: String = ""
var visited_airports: Dictionary = {}  # id -> true
var visited_cities: Dictionary = {}
var visited_countries: Dictionary = {}
var inventory: Array = []  # {product_id, qty, unit_cost, quality, purchased_unix, in_cargo}
var cargo_kg_capacity: float = 0.0
var held_tickets: Array = []  # ticket dicts
var travel_log: Array = []
var demand_pressure: Dictionary = {}  # "city|product" -> float 0..1
var tutorial_flags: Dictionary = {}
var game_started: bool = false
var game_mode: String = "sandbox"  # "sandbox" | "challenge" | "collector"
var challenge: Dictionary = {}  # {start_unix, deadline_unix, ended, result}
var sell_transactions: Array[Dictionary] = []

# Per-ticket trip baggage (cleared on arrival)
var trip_baggage_extra_kg: float = 0.0
var trip_cabin: String = "economy"  # economy|business|first
var trip_cold_chain: bool = false
# Unix time when the cold-chain window opened (set by set_cold_chain(true)).
# -1 means no window is currently open. When the window closes, protected
# elapsed hours are folded into each cold-chain item as cold_protected_hours
# so protection survives arrival / refund instead of being erased.
var cold_chain_start_unix: float = -1.0
var reliability_events_enabled: bool = true
var last_market_date: String = ""
var last_flight_price: float = 0.0
var last_baggage_cost: float = 0.0
var reduced_animations: bool = false
var night_bgm_enabled: bool = true
var place_locale: String = "zh"  # "zh" or "en" — display language for place names only
var unlocked_achievements: Dictionary = {}  # id -> true
var stats: Dictionary = {
	"total_flight_segments": 0,
	"total_distance_km": 0.0,
	"total_flight_hours": 0.0,
	"business_flights": 0,
	"first_flights": 0,
	"cargo_flights": 0,
	"connection_flights": 0,
	"stopover_flights": 0,
	"delayed_flights": 0,
	"cancelled_flights": 0,
	"alliance_flights": 0,
	"fast_forwards": 0,
	"intel_purchases": 0,
	"hot_streak_sells": 0,
	"categories_sold": {},
	"products_discovered": {},
	"routes_flown": {},
	"extreme_airports": {"north": "", "south": "", "east": "", "west": ""},
	"discovery_triggered": 0,
	"big_loss_count": 0,
	"single_profit_max": 0.0,
	"consecutive_on_time": 0,
}


func _default_stats() -> Dictionary:
	return {
		"total_flight_segments": 0,
		"total_distance_km": 0.0,
		"total_flight_hours": 0.0,
		"business_flights": 0,
		"first_flights": 0,
		"cargo_flights": 0,
		"connection_flights": 0,
		"stopover_flights": 0,
		"delayed_flights": 0,
		"cancelled_flights": 0,
		"alliance_flights": 0,
		"fast_forwards": 0,
		"intel_purchases": 0,
		"hot_streak_sells": 0,
		"categories_sold": {},
		"products_discovered": {},
		"routes_flown": {},
		"extreme_airports": {"north": "", "south": "", "east": "", "west": ""},
		"discovery_triggered": 0,
		"big_loss_count": 0,
		"single_profit_max": 0.0,
		"consecutive_on_time": 0,
	}


func reset_new_game(airport_id: String, mode: String = "sandbox") -> void:
	save_id = "S%s_%d" % [Time.get_unix_time_from_system(), randi() % 10000]
	game_mode = mode
	challenge = {}
	cash_usd = float(DataService.economy.get("starting_cash_usd", 50000.0))
	current_airport_id = airport_id
	visited_airports = {}
	visited_cities = {}
	visited_countries = {}
	inventory = []
	cargo_kg_capacity = 0.0
	held_tickets = []
	travel_log = []
	demand_pressure = {}
	tutorial_flags = {}
	sell_transactions = []
	trip_baggage_extra_kg = 0.0
	trip_cabin = "economy"
	trip_cold_chain = false
	cold_chain_start_unix = -1.0
	last_market_date = "2025-03-01"
	last_flight_price = 0.0
	last_baggage_cost = 0.0
	unlocked_achievements = {}
	stats = _default_stats()
	_mark_visit(airport_id)
	game_started = true
	GameClock.unix_time = GameClock.BASELINE_UNIX
	GameClock.start_clock()
	EventBus.game_started.emit()
	EventBus.cash_changed.emit()
	EventBus.inventory_changed.emit()
	if not tutorial_flags.get("welcome", false):
		tutorial_flags["welcome"] = true
		var tip := I18nService.tutorial("new_game")
		if tip.is_empty():
			tip = "欢迎来到《环球航商》。先查看城市特产，再打开航班面板购票。航班为公开数据重建，非真实时刻。"
		EventBus.tutorial_hint.emit(tip)


func _mark_visit(airport_id: String) -> void:
	var a: Dictionary = DataService.get_airport(airport_id)
	if a.is_empty():
		return
	visited_airports[airport_id] = true
	visited_cities[str(a.get("city_id", ""))] = true
	visited_countries[str(a.get("country_id", ""))] = true


func current_airport() -> Dictionary:
	return DataService.get_airport(current_airport_id)


func current_city_id() -> String:
	return str(current_airport().get("city_id", ""))


func personal_baggage_limit_kg() -> float:
	var ticket: Dictionary = DataService.economy.get("ticket", {})
	var base := float(ticket.get("baggage_economy_kg", 20.0))
	if trip_cabin == "business":
		base = float(ticket.get("baggage_business_kg", 60.0))
	elif trip_cabin == "first":
		base = float(ticket.get("baggage_first_kg", 100.0))
	var carry := float(ticket.get("carry_on_kg", 5.0))
	return base + carry + trip_baggage_extra_kg


func inventory_weight_kg(cargo_only: bool = false, personal_only: bool = false) -> float:
	var w := 0.0
	for item_v in inventory:
		var item: Dictionary = item_v
		var p: Dictionary = DataService.get_product(str(item.get("product_id", "")))
		var unit := float(p.get("weight_kg", 0.1))
		var in_cargo: bool = bool(item.get("in_cargo", false))
		if cargo_only and not in_cargo:
			continue
		if personal_only and in_cargo:
			continue
		w += unit * float(item.get("qty", 0))
	return w


func add_cash(delta: float) -> void:
	cash_usd += delta
	EventBus.cash_changed.emit()


func set_cold_chain(active: bool) -> void:
	## Open/close the cold-chain window. Opening records the start time so
	## EconomySystem can age cold-chain goods at the protected rate for the
	## window; closing folds the protected hours into each cold item.
	if active:
		if not trip_cold_chain:
			cold_chain_start_unix = GameClock.unix_time
		trip_cold_chain = true
		return
	if trip_cold_chain:
		_fold_cold_protection()
	trip_cold_chain = false
	cold_chain_start_unix = -1.0


func _fold_cold_protection() -> void:
	## Accrue protected hours for every cold-chain item held during the window.
	if cold_chain_start_unix <= 0.0:
		return
	var now: float = float(GameClock.unix_time)
	var start: float = cold_chain_start_unix
	for item_v in inventory:
		var item: Dictionary = item_v
		var p: Dictionary = DataService.get_product(str(item.get("product_id", "")))
		if not bool(p.get("requires_cold_chain", false)):
			continue
		var base: float = maxf(float(item.get("purchased_unix", 0.0)), start)
		if now > base:
			item["cold_protected_hours"] = float(item.get("cold_protected_hours", 0.0)) + (now - base) / 3600.0


func log_stat(key: String, delta: float = 1.0) -> void:
	if not stats.has(key):
		stats[key] = 0
	var cur = stats[key]
	if typeof(cur) == TYPE_FLOAT or typeof(cur) == TYPE_INT:
		stats[key] = float(cur) + delta
	elif typeof(cur) == TYPE_DICTIONARY and typeof(delta) == TYPE_STRING:
		(stats[key] as Dictionary)[str(delta)] = true


func mark_category_sold(category: String) -> void:
	if category == "":
		return
	var cats: Dictionary = stats.get("categories_sold", {})
	cats[category] = true
	stats["categories_sold"] = cats


func mark_product_discovered(product_id: String) -> void:
	if product_id == "":
		return
	var found: Dictionary = stats.get("products_discovered", {})
	found[product_id] = true
	stats["products_discovered"] = found


func mark_route_flown(origin_iata: String, dest_iata: String) -> void:
	if origin_iata == "" or dest_iata == "":
		return
	var routes: Dictionary = stats.get("routes_flown", {})
	routes["%s|%s" % [origin_iata, dest_iata]] = true
	stats["routes_flown"] = routes


func update_extreme_airport(airport_id: String) -> void:
	var a: Dictionary = DataService.get_airport(airport_id)
	if a.is_empty():
		return
	var lat := float(a.get("latitude", a.get("lat", 0.0)))
	var lon := float(a.get("longitude", a.get("lon", 0.0)))
	var extremes: Dictionary = stats.get("extreme_airports", {"north": "", "south": "", "east": "", "west": ""})
	for pair in [["north", true], ["south", false]]:
		var key: String = pair[0]
		var want_max: bool = pair[1]
		var cur_id := str(extremes.get(key, ""))
		if cur_id == "":
			extremes[key] = airport_id
			continue
		var cur_a: Dictionary = DataService.get_airport(cur_id)
		var cur_lat := float(cur_a.get("latitude", cur_a.get("lat", 0.0)))
		if want_max and lat > cur_lat:
			extremes[key] = airport_id
		elif not want_max and lat < cur_lat:
			extremes[key] = airport_id
	for pair2 in [["east", true], ["west", false]]:
		var key2: String = pair2[0]
		var want_max2: bool = pair2[1]
		var cur_id2 := str(extremes.get(key2, ""))
		if cur_id2 == "":
			extremes[key2] = airport_id
			continue
		var cur_a2: Dictionary = DataService.get_airport(cur_id2)
		var cur_lon := float(cur_a2.get("longitude", cur_a2.get("lon", 0.0)))
		if want_max2 and lon > cur_lon:
			extremes[key2] = airport_id
		elif not want_max2 and lon < cur_lon:
			extremes[key2] = airport_id
	stats["extreme_airports"] = extremes


## Log a completed sell transaction. Persists to save file via to_dict/from_dict.
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
	mark_product_discovered(product_id)
	var p: Dictionary = DataService.get_product(product_id)
	mark_category_sold(str(p.get("category", "")))
	var margin: float = total_revenue - total_unit_cost
	if margin > float(stats.get("single_profit_max", 0.0)):
		stats["single_profit_max"] = margin
	if margin < 0.0 and total_unit_cost > 0.0 and margin / total_unit_cost < -0.20:
		log_stat("big_loss_count", 1.0)


func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"save_id": save_id,
		"cash_usd": cash_usd,
		"current_airport_id": current_airport_id,
		"unix_time": GameClock.unix_time,
		"visited_airports": visited_airports,
		"visited_cities": visited_cities,
		"visited_countries": visited_countries,
		"inventory": inventory,
		"cargo_kg_capacity": cargo_kg_capacity,
		"held_tickets": held_tickets,
		"travel_log": travel_log,
		"demand_pressure": demand_pressure,
		"tutorial_flags": tutorial_flags,
		"trip_baggage_extra_kg": trip_baggage_extra_kg,
		"trip_cabin": trip_cabin,
		"trip_cold_chain": trip_cold_chain,
		"cold_chain_start_unix": cold_chain_start_unix,
		"reliability_events_enabled": reliability_events_enabled,
		"last_market_date": last_market_date,
		"game_started": game_started,
		"game_mode": game_mode,
		"challenge": challenge,
		"sell_transactions": sell_transactions,
		"last_flight_price": last_flight_price,
		"last_baggage_cost": last_baggage_cost,
		"reduced_animations": reduced_animations,
		"night_bgm_enabled": night_bgm_enabled,
		"place_locale": place_locale,
		"unlocked_achievements": unlocked_achievements,
		"stats": stats,
	}


func from_dict(d: Dictionary) -> void:
	save_id = str(d.get("save_id", ""))
	cash_usd = float(d.get("cash_usd", 0))
	current_airport_id = str(d.get("current_airport_id", ""))
	GameClock.unix_time = float(d.get("unix_time", GameClock.BASELINE_UNIX))
	visited_airports = d.get("visited_airports", {})
	visited_cities = d.get("visited_cities", {})
	visited_countries = d.get("visited_countries", {})
	inventory = d.get("inventory", [])
	cargo_kg_capacity = float(d.get("cargo_kg_capacity", 0))
	held_tickets = d.get("held_tickets", [])
	travel_log = d.get("travel_log", [])
	demand_pressure = d.get("demand_pressure", {})
	tutorial_flags = d.get("tutorial_flags", {})
	trip_baggage_extra_kg = float(d.get("trip_baggage_extra_kg", 0))
	trip_cabin = str(d.get("trip_cabin", "economy"))
	trip_cold_chain = bool(d.get("trip_cold_chain", false))
	cold_chain_start_unix = float(d.get("cold_chain_start_unix", -1.0))
	reliability_events_enabled = bool(d.get("reliability_events_enabled", true))
	last_market_date = str(d.get("last_market_date", GameClock.game_date_string()))
	game_started = bool(d.get("game_started", false))
	game_mode = str(d.get("game_mode", "sandbox"))
	challenge = d.get("challenge", {})
	if typeof(challenge) != TYPE_DICTIONARY:
		challenge = {}
	sell_transactions = []
	for tx_v in d.get("sell_transactions", []):
		if typeof(tx_v) == TYPE_DICTIONARY:
			sell_transactions.append(tx_v)
	last_flight_price = float(d.get("last_flight_price", 0.0))
	last_baggage_cost = float(d.get("last_baggage_cost", 0.0))
	reduced_animations = bool(d.get("reduced_animations", false))
	night_bgm_enabled = bool(d.get("night_bgm_enabled", true))
	place_locale = str(d.get("place_locale", "zh"))
	unlocked_achievements = d.get("unlocked_achievements", {})
	stats = _default_stats()
	var loaded_stats: Dictionary = d.get("stats", {})
	for k in loaded_stats.keys():
		stats[k] = loaded_stats[k]
	if current_airport_id != "":
		_mark_visit(current_airport_id)
	if game_started:
		GameClock.start_clock()
	EventBus.cash_changed.emit()
	EventBus.inventory_changed.emit()
