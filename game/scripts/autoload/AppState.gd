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

# Per-ticket trip baggage (cleared on arrival)
var trip_baggage_extra_kg: float = 0.0
var trip_cabin: String = "economy"  # economy|business


func reset_new_game(airport_id: String) -> void:
	save_id = "S%s_%d" % [Time.get_unix_time_from_system(), randi() % 10000]
	cash_usd = float(DataService.economy.get("starting_cash_usd", 6944.0))
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
	trip_baggage_extra_kg = 0.0
	trip_cabin = "economy"
	_mark_visit(airport_id)
	game_started = true
	GameClock.unix_time = GameClock.BASELINE_UNIX
	GameClock.start_clock()
	EventBus.game_started.emit()
	EventBus.cash_changed.emit()
	EventBus.inventory_changed.emit()
	if not tutorial_flags.get("welcome", false):
		tutorial_flags["welcome"] = true
		EventBus.tutorial_hint.emit("欢迎来到《环球航商》。先查看城市特产，再打开航班面板购票。航班为公开数据重建，非真实时刻。")


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
		"game_started": game_started,
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
	game_started = bool(d.get("game_started", false))
	if game_started:
		GameClock.start_clock()
	EventBus.cash_changed.emit()
	EventBus.inventory_changed.emit()
