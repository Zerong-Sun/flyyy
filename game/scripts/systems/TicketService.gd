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


static func _cabin_price(flight: Dictionary, cabin: String) -> float:
	var price: float = float(flight.get("ticket_base_price_economy", 0))
	if cabin == "business":
		price = float(flight.get("ticket_base_price_business", 0))
	elif cabin == "first":
		price = float(flight.get("ticket_base_price_first", 0))
		if price <= 0.0:
			var econ: Dictionary = DataService.economy.get("ticket", {})
			price = float(flight.get("ticket_base_price_economy", 0)) * float(econ.get("first_multiplier", 25.0))
	return price


static func _extra_cost(extra_tier: String, cargo_blocks: int) -> Dictionary:
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	var extra_kg: float = 0.0
	var extra_cost: float = 0.0
	var enables_cold := false
	if extra_tier != "" and extras.has(extra_tier):
		var tier: Dictionary = extras[extra_tier]
		extra_kg = float(tier.get("extra_kg", 0))
		extra_cost = float(tier.get("price_usd", 0))
		enables_cold = bool(tier.get("enables_cold_chain", false))
	var cargo_kg: float = 50.0 * float(maxi(0, cargo_blocks))
	var cargo_cost: float = float(extras.get("cargo_per_50kg_usd", 168)) * float(maxi(0, cargo_blocks))
	return {
		"extra_kg": extra_kg,
		"extra_cost": extra_cost,
		"cargo_kg": cargo_kg,
		"cargo_cost": cargo_cost,
		"enables_cold_chain": enables_cold,
	}


static func purchase(flight: Dictionary, cabin: String, extra_tier: String, cargo_blocks: int, replace_existing: bool = false) -> String:
	if not AppState.game_started:
		return "请先开始游戏"
	if str(flight.get("origin_airport_id", "")) != AppState.current_airport_id:
		return "只能购买当前机场出发航班"
	var dep: float = GameClock.parse_iso_to_unix(str(flight.get("scheduled_departure_utc", "")))
	if dep <= GameClock.unix_time:
		return "航班已起飞"
	if not AppState.held_tickets.is_empty():
		if not replace_existing:
			return "已有机票。请先退票，或确认以手续费替换。"
		var refund_msg: String = refund_current()
		if refund_msg.begins_with("没有") or refund_msg.begins_with("已到"):
			return refund_msg
	var price: float = _cabin_price(flight, cabin)
	var bag: Dictionary = _extra_cost(extra_tier, cargo_blocks)
	var total: float = price + float(bag.extra_cost) + float(bag.cargo_cost)
	if total > AppState.cash_usd:
		return "资金不足（需 %s）" % _Economy.format_money(total)
	AppState.add_cash(-total)
	AppState.held_tickets = [{
		"flight_instance_id": flight.get("flight_instance_id", ""),
		"marketing_flight_number": flight.get("marketing_flight_number", ""),
		"airline_name": flight.get("airline_name", ""),
		"alliance_id": flight.get("alliance_id", DataService.airline_alliance_id(str(flight.get("operating_airline_id", "")))),
		"origin_airport_id": flight.get("origin_airport_id", ""),
		"destination_airport_id": flight.get("destination_airport_id", ""),
		"origin_iata": flight.get("origin_iata", ""),
		"destination_iata": flight.get("destination_iata", ""),
		"scheduled_departure_utc": flight.get("scheduled_departure_utc", ""),
		"scheduled_arrival_utc": flight.get("scheduled_arrival_utc", ""),
		"distance_km": flight.get("distance_km", 0),
		"duration_minutes": flight.get("duration_minutes", 0),
		"stops": int(flight.get("stops", 0)),
		"stop_airports": flight.get("stop_airports", []),
		"cabin": cabin,
		"ticket_price": price,
		"extra_kg": bag.extra_kg,
		"cargo_kg": bag.cargo_kg,
		"extra_tier": extra_tier,
		"cargo_blocks": cargo_blocks,
		"total_paid": total,
		"is_connection_leg": false,
		"enables_cold_chain": bag.enables_cold_chain,
	}]
	AppState.trip_cabin = cabin
	AppState.trip_baggage_extra_kg = float(bag.extra_kg)
	AppState.cargo_kg_capacity = float(bag.cargo_kg)
	AppState.trip_cold_chain = bool(bag.enables_cold_chain)
	AppState.last_flight_price = price
	AppState.last_baggage_cost = float(bag.extra_cost) + float(bag.cargo_cost)
	EventBus.ticket_purchased.emit()
	if not bool(AppState.tutorial_flags.get("ticket", false)):
		AppState.tutorial_flags["ticket"] = true
		var tip := I18nService.tutorial("first_ticket")
		if tip.is_empty():
			tip = "购票成功。可点击「加速至起飞」，或等待时间流逝后强制登机。"
		EventBus.tutorial_hint.emit(tip)
	return ""


static func purchase_connection(conn: Dictionary, cabin: String, extra_tier: String, cargo_blocks: int, replace_existing: bool = false) -> String:
	## Purchase a two-leg connection itinerary built from transfer_edges.
	if not AppState.game_started:
		return "请先开始游戏"
	if str(conn.get("origin_airport_id", "")) != AppState.current_airport_id:
		return "只能购买当前机场出发航班"
	if not AppState.held_tickets.is_empty():
		if not replace_existing:
			return "已有机票。请先退票，或确认以手续费替换。"
		var refund_msg: String = refund_current()
		if refund_msg.begins_with("没有") or refund_msg.begins_with("已到"):
			return refund_msg
	var hub_id := str(conn.get("hub_airport_id", ""))
	var dest_id := str(conn.get("destination_airport_id", ""))
	if hub_id == "" or dest_id == "":
		return "联程数据不完整"
	var price: float = _cabin_price(conn, cabin)
	var bag: Dictionary = _extra_cost(extra_tier, cargo_blocks)
	var total: float = price + float(bag.extra_cost) + float(bag.cargo_cost)
	if total > AppState.cash_usd:
		return "资金不足（需 %s）" % _Economy.format_money(total)
	# Schedule: depart in 3h; second leg after hub MCT (per-airport / edge).
	var now := GameClock.unix_time
	var dep1 := now + 3.0 * 3600.0
	var seg1_min := int(conn.get("seg1_duration_avg", 120))
	var seg2_min := int(conn.get("seg2_duration_avg", 120))
	var origin_ap: Dictionary = DataService.get_airport(str(conn.get("origin_airport_id", "")))
	var dest_ap: Dictionary = DataService.get_airport(dest_id)
	var international: bool = str(origin_ap.get("country_id", "")) != str(dest_ap.get("country_id", ""))
	var mct: int = int(conn.get("mct_minutes", 0))
	if mct <= 0:
		mct = DataService.mct_minutes_for_airport(hub_id, international)
	var arr1 := dep1 + float(seg1_min) * 60.0
	var dep2 := arr1 + float(mct) * 60.0
	var arr2 := dep2 + float(seg2_min) * 60.0
	var dist_total := float(conn.get("total_distance_km", 0))
	var dist1 := dist_total * 0.55
	var dist2 := dist_total * 0.45
	AppState.add_cash(-total)
	var ticket1 := {
		"flight_instance_id": "cnx1_%s_%s" % [conn.get("origin_iata", ""), conn.get("hub_iata", "")],
		"marketing_flight_number": "CN1 %s-%s" % [conn.get("origin_iata", ""), conn.get("hub_iata", "")],
		"airline_name": "联程拼装（重建网络）",
		"origin_airport_id": conn.get("origin_airport_id", ""),
		"destination_airport_id": hub_id,
		"origin_iata": conn.get("origin_iata", ""),
		"destination_iata": conn.get("hub_iata", ""),
		"scheduled_departure_utc": _unix_to_iso(dep1),
		"scheduled_arrival_utc": _unix_to_iso(arr1),
		"distance_km": dist1,
		"duration_minutes": seg1_min,
		"cabin": cabin,
		"ticket_price": price * 0.55,
		"extra_kg": bag.extra_kg,
		"cargo_kg": bag.cargo_kg,
		"extra_tier": extra_tier,
		"cargo_blocks": cargo_blocks,
		"total_paid": total * 0.55,
		"is_connection_leg": true,
		"connection_leg": 1,
		"connection_final_dest": conn.get("destination_iata", ""),
		"mct_minutes": mct,
		"enables_cold_chain": bag.enables_cold_chain,
	}
	var ticket2 := {
		"flight_instance_id": "cnx2_%s_%s" % [conn.get("hub_iata", ""), conn.get("destination_iata", "")],
		"marketing_flight_number": "CN2 %s-%s" % [conn.get("hub_iata", ""), conn.get("destination_iata", "")],
		"airline_name": "联程拼装（重建网络）",
		"origin_airport_id": hub_id,
		"destination_airport_id": dest_id,
		"origin_iata": conn.get("hub_iata", ""),
		"destination_iata": conn.get("destination_iata", ""),
		"scheduled_departure_utc": _unix_to_iso(dep2),
		"scheduled_arrival_utc": _unix_to_iso(arr2),
		"distance_km": dist2,
		"duration_minutes": seg2_min,
		"cabin": cabin,
		"ticket_price": price * 0.45,
		"extra_kg": 0.0,
		"cargo_kg": bag.cargo_kg,
		"extra_tier": "",
		"cargo_blocks": cargo_blocks,
		"total_paid": total * 0.45,
		"is_connection_leg": true,
		"connection_leg": 2,
		"connection_final_dest": conn.get("destination_iata", ""),
		"enables_cold_chain": bag.enables_cold_chain,
	}
	AppState.held_tickets = [ticket1, ticket2]
	AppState.trip_cabin = cabin
	AppState.trip_baggage_extra_kg = float(bag.extra_kg)
	AppState.cargo_kg_capacity = float(bag.cargo_kg)
	AppState.trip_cold_chain = bool(bag.enables_cold_chain)
	AppState.last_flight_price = price
	AppState.last_baggage_cost = float(bag.extra_cost) + float(bag.cargo_cost)
	AppState.log_stat("connection_flights", 1.0)
	EventBus.ticket_purchased.emit()
	return ""


static func _unix_to_iso(unix_t: float) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(int(unix_t))
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]


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
	AppState.trip_cold_chain = false
	EventBus.ticket_purchased.emit()
	return "已退票，退回 %s（含 30%% 手续费）" % _Economy.format_money(refund)


static func add_baggage_or_cargo(extra_tier: String, add_cargo_blocks: int) -> String:
	## On-the-spot expand while holding a ticket (market overweight path).
	if AppState.held_tickets.is_empty():
		return "请先购票后再加购行李/货运"
	var t: Dictionary = next_ticket()
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	if dep <= GameClock.unix_time:
		return "已到起飞时间，不可加购"
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	var cost: float = 0.0
	var extra_kg: float = float(t.get("extra_kg", 0))
	if extra_tier != "" and extras.has(extra_tier):
		var tier: Dictionary = extras[extra_tier]
		var new_kg: float = float(tier.get("extra_kg", 0))
		if new_kg <= extra_kg:
			return "请选择更大的行李扩展档位"
		cost += float(tier.get("price_usd", 0))
		extra_kg = new_kg
	var blocks: int = int(t.get("cargo_blocks", 0)) + maxi(0, add_cargo_blocks)
	if add_cargo_blocks > 0:
		cost += float(extras.get("cargo_per_50kg_usd", 168)) * float(add_cargo_blocks)
	if cost <= 0.0:
		return "未选择加购项"
	if cost > AppState.cash_usd:
		return "资金不足（需 %s）" % _Economy.format_money(cost)
	AppState.add_cash(-cost)
	t["extra_kg"] = extra_kg
	t["extra_tier"] = extra_tier if extra_tier != "" else t.get("extra_tier", "")
	t["cargo_blocks"] = blocks
	t["cargo_kg"] = 50.0 * float(blocks)
	t["total_paid"] = float(t.get("total_paid", 0)) + cost
	AppState.trip_baggage_extra_kg = extra_kg
	AppState.cargo_kg_capacity = float(t["cargo_kg"])
	AppState.held_tickets[0] = t
	EventBus.ticket_purchased.emit()
	EventBus.inventory_changed.emit()
	return "加购成功，支付 %s" % _Economy.format_money(cost)
