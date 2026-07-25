extends Node
## Handles fast-forward, forced boarding, 5s transition, arrival.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Tickets = preload("res://scripts/systems/TicketService.gd")

signal transition_started(ticket: Dictionary)
signal transition_finished

var _boarding := false


func _ready() -> void:
	set_process(true)
	EventBus.game_started.connect(_on_game_started)


func _on_game_started() -> void:
	AppState.last_market_date = GameClock.game_date_string()
	_boarding = false


func _process(_delta: float) -> void:
	if not AppState.game_started or _boarding:
		return
	var d: String = GameClock.game_date_string()
	if d != AppState.last_market_date:
		_Economy.recover_demand_for_new_day(AppState.last_market_date, d)
		AppState.last_market_date = d
	var t: Dictionary = _Tickets.next_ticket()
	if t.is_empty():
		return
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	if GameClock.unix_time >= dep:
		start_boarding(t)


func fast_forward_to_departure() -> String:
	var t: Dictionary = _Tickets.next_ticket()
	if t.is_empty():
		return "没有已购航班"
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	if dep <= GameClock.unix_time:
		return "已到起飞时间"
	var before_date: String = GameClock.game_date_string()
	_Economy.age_inventory(0.0)
	GameClock.jump_to_unix(dep)
	var after_date: String = GameClock.game_date_string()
	_Economy.recover_demand_for_new_day(before_date, after_date)
	AppState.last_market_date = after_date
	_Economy.age_inventory(0.0)
	EventBus.market_changed.emit()
	return ""


func start_boarding(ticket: Dictionary) -> void:
	if _boarding:
		return
	_boarding = true
	GameClock.set_paused(true)
	transition_started.emit(ticket)
	var dur: float = float(ticket.get("duration_minutes", 0))
	var hours: float = dur / 60.0
	GameClock.add_minutes(dur)
	_Economy.age_inventory(0.0)
	_Economy.apply_flight_fragility(hours)
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(5.0).timeout
	_arrive(ticket)
	_boarding = false
	GameClock.set_paused(false)
	transition_finished.emit()


func _arrive(ticket: Dictionary) -> void:
	var dest: String = str(ticket.get("destination_airport_id", ""))
	var cargo_value: float = _Economy.inventory_cargo_value_usd()
	var cash_before_note: float = AppState.cash_usd
	AppState.current_airport_id = dest
	AppState._mark_visit(dest)
	AppState.held_tickets.clear()
	AppState.trip_baggage_extra_kg = 0.0
	AppState.trip_cabin = "economy"
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		item["in_cargo"] = false
		item["quality"] = _Economy.current_quality(item)
	AppState.cargo_kg_capacity = 0.0
	AppState.travel_log.append({
		"departure_airport": ticket.get("origin_iata", ""),
		"arrival_airport": ticket.get("destination_iata", ""),
		"flight_number": ticket.get("marketing_flight_number", ""),
		"airline": ticket.get("airline_name", ""),
		"departure_time": ticket.get("scheduled_departure_utc", ""),
		"arrival_time": ticket.get("scheduled_arrival_utc", ""),
		"distance": ticket.get("distance_km", 0),
		"ticket_price": ticket.get("ticket_price", 0),
		"cargo_value": cargo_value,
		"profit_after_arrival": cash_before_note - float(ticket.get("total_paid", ticket.get("ticket_price", 0))),
		"cash_on_arrival": cash_before_note,
	})
	AppState.last_market_date = GameClock.game_date_string()
	SaveSystem.save_game()
	EventBus.arrived.emit()
	EventBus.airport_selected.emit(dest)
	EventBus.inventory_changed.emit()
	if not bool(AppState.tutorial_flags.get("arrived", false)):
		AppState.tutorial_flags["arrived"] = true
		EventBus.tutorial_hint.emit("已抵达目的地。打开「市场」出售商品结算利润。")
