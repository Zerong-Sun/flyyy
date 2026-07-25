extends Node
## Handles fast-forward, forced boarding, 5s transition, arrival.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Tickets = preload("res://scripts/systems/TicketService.gd")

signal transition_started(ticket: Dictionary)
signal transition_finished

var _boarding := false
var _last_date: String = ""


func _ready() -> void:
	_last_date = GameClock.game_date_string()
	set_process(true)


func _process(_delta: float) -> void:
	if not AppState.game_started or _boarding:
		return
	var d: String = GameClock.game_date_string()
	if d != _last_date:
		_Economy.recover_demand_for_new_day(_last_date, d)
		_last_date = d
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
	var hours: float = (dep - GameClock.unix_time) / 3600.0
	_Economy.age_inventory(hours)
	GameClock.jump_to_unix(dep)
	EventBus.market_changed.emit()
	return ""


func start_boarding(ticket: Dictionary) -> void:
	if _boarding:
		return
	_boarding = true
	GameClock.set_paused(true)
	transition_started.emit(ticket)
	var dur: float = float(ticket.get("duration_minutes", 0))
	_Economy.age_inventory(dur / 60.0)
	GameClock.add_minutes(dur)
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(5.0).timeout
	_arrive(ticket)
	_boarding = false
	GameClock.set_paused(false)
	transition_finished.emit()


func _arrive(ticket: Dictionary) -> void:
	var dest: String = str(ticket.get("destination_airport_id", ""))
	AppState.current_airport_id = dest
	AppState._mark_visit(dest)
	AppState.held_tickets.clear()
	AppState.trip_baggage_extra_kg = 0.0
	AppState.trip_cabin = "economy"
	for item_v in AppState.inventory:
		var item: Dictionary = item_v
		item["in_cargo"] = false
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
		"cargo_value": 0.0,
		"profit_after_arrival": 0.0,
	})
	SaveSystem.save_game()
	EventBus.arrived.emit()
	EventBus.airport_selected.emit(dest)
	EventBus.inventory_changed.emit()
	if not bool(AppState.tutorial_flags.get("arrived", false)):
		AppState.tutorial_flags["arrived"] = true
		EventBus.tutorial_hint.emit("已抵达目的地。打开「市场」出售商品结算利润。")
