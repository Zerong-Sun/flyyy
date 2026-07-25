extends RefCounted
class_name TicketService

const _Economy = preload("res://scripts/systems/EconomySystem.gd")


static func next_ticket() -> Dictionary:
	var best: Dictionary = {}
	var best_t: float = INF
	for t_v in AppState.held_tickets:
		var t: Dictionary = t_v
		var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
		if dep < best_t:
			best_t = dep
			best = t
	return best


static func purchase(flight: Dictionary, cabin: String, extra_tier: String, cargo_blocks: int) -> String:
	if not AppState.game_started:
		return "请先开始游戏"
	if str(flight.get("origin_airport_id", "")) != AppState.current_airport_id:
		return "只能购买当前机出发航班"
	var dep: float = GameClock.parse_iso_to_unix(str(flight.get("scheduled_departure_utc", "")))
	if dep <= GameClock.unix_time:
		return "航班已起飞"
	var price: float = float(flight.get("ticket_base_price_economy", 0))
	if cabin == "business":
		price = float(flight.get("ticket_base_price_business", 0))
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	var extra_kg: float = 0.0
	var extra_cost: float = 0.0
	if extra_tier != "" and extras.has(extra_tier):
		var tier: Dictionary = extras[extra_tier]
		extra_kg = float(tier.get("extra_kg", 0))
		extra_cost = float(tier.get("price_usd", 0))
	var cargo_cost: float = 0.0
	var cargo_kg: float = 0.0
	if cargo_blocks > 0:
		cargo_kg = 50.0 * float(cargo_blocks)
		cargo_cost = float(extras.get("cargo_per_50kg_usd", 168)) * float(cargo_blocks)
	var total: float = price + extra_cost + cargo_cost
	if total > AppState.cash_usd:
		return "资金不足（需 %s）" % _Economy.format_money(total)
	AppState.add_cash(-total)
	AppState.held_tickets = [{
		"flight_instance_id": flight.get("flight_instance_id", ""),
		"marketing_flight_number": flight.get("marketing_flight_number", ""),
		"airline_name": flight.get("airline_name", ""),
		"origin_airport_id": flight.get("origin_airport_id", ""),
		"destination_airport_id": flight.get("destination_airport_id", ""),
		"origin_iata": flight.get("origin_iata", ""),
		"destination_iata": flight.get("destination_iata", ""),
		"scheduled_departure_utc": flight.get("scheduled_departure_utc", ""),
		"scheduled_arrival_utc": flight.get("scheduled_arrival_utc", ""),
		"distance_km": flight.get("distance_km", 0),
		"duration_minutes": flight.get("duration_minutes", 0),
		"cabin": cabin,
		"ticket_price": price,
		"extra_kg": extra_kg,
		"cargo_kg": cargo_kg,
		"total_paid": total,
	}]
	AppState.trip_cabin = cabin
	AppState.trip_baggage_extra_kg = extra_kg
	AppState.cargo_kg_capacity = cargo_kg
	EventBus.ticket_purchased.emit()
	if not bool(AppState.tutorial_flags.get("ticket", false)):
		AppState.tutorial_flags["ticket"] = true
		EventBus.tutorial_hint.emit("购票成功。可点击「加速至起飞」，或等待时间流逝后强制登机。")
	return ""


static func refund_current() -> String:
	var t: Dictionary = next_ticket()
	if t.is_empty():
		return "没有可退机票"
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	if dep <= GameClock.unix_time:
		return "已到起飞时间，不可退票"
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	var fee_rate: float = float(extras.get("refund_fee_rate", 0.3))
	var refund: float = float(t.get("total_paid", 0)) * (1.0 - fee_rate)
	AppState.add_cash(refund)
	AppState.held_tickets.clear()
	AppState.trip_baggage_extra_kg = 0.0
	AppState.cargo_kg_capacity = 0.0
	AppState.trip_cabin = "economy"
	EventBus.ticket_purchased.emit()
	return "已退票，退回 %s（含 30%% 手续费）" % _Economy.format_money(refund)
