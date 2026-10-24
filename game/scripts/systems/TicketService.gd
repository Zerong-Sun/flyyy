extends RefCounted
class_name TicketService

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _NewsEvents = preload("res://scripts/systems/NewsEvents.gd")


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
		if enables_cold:
			extra_cost *= ReputationSystem.cold_baggage_discount()
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
	var quoted: Dictionary = _NewsEvents.quote_flight(flight)
	if bool(quoted.get("news_unavailable", false)):
		return "受当前新闻事件影响，该航班已取消，请刷新航班列表"
	flight = quoted
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
	AppState.record_travel_expense(total)
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
		"ledger_paid": total,
		"is_connection_leg": false,
		"enables_cold_chain": bag.enables_cold_chain,
	}]
	AppState.trip_cabin = cabin
	AppState.trip_baggage_extra_kg = float(bag.extra_kg)
	AppState.cargo_kg_capacity = float(bag.cargo_kg)
	AppState.set_cold_chain(bool(bag.enables_cold_chain))
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
	## Purchase a two-leg connection assembled from REAL scheduled flights:
	## an origin→hub leg plus the earliest hub→dest leg departing within
	## [arr1 + MCT, arr1 + max_connection]. Never mints phantom flights
	## (ratchet P0 — SmokeConnectionContract.gd part A).
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
	var mct: int = int(conn.get("mct_minutes", 0))
	if mct <= 0:
		var origin_ap: Dictionary = DataService.get_airport(str(conn.get("origin_airport_id", "")))
		var dest_ap: Dictionary = DataService.get_airport(dest_id)
		var international: bool = str(origin_ap.get("country_id", "")) != str(dest_ap.get("country_id", ""))
		mct = DataService.mct_minutes_for_airport(hub_id, international)
	var econ_mct: Dictionary = DataService.economy.get("mct", {})
	var max_cnx: int = int(econ_mct.get("max_connection_min", 480))
	var now := GameClock.unix_time

	# Assemble from the real schedule: earliest origin→hub flight that has a
	# hub→dest flight departing inside the [arr1 + mct, arr1 + max_cnx] window.
	var f1: Dictionary = {}
	var f2: Dictionary = {}
	for f1_v in DataService.flights_from(str(conn.get("origin_airport_id", ""))):
		var cand1: Dictionary = f1_v
		if str(cand1.get("destination_airport_id", "")) != hub_id:
			continue
		var q1: Dictionary = _NewsEvents.quote_flight(cand1)
		if bool(q1.get("news_unavailable", false)):
			continue
		var dep1: float = GameClock.parse_iso_to_unix(str(q1.get("scheduled_departure_utc", "")))
		if dep1 < now + 60.0:
			continue
		var arr1: float = dep1 + float(q1.get("duration_minutes", 0)) * 60.0
		var best2: Dictionary = {}
		var best2_dep := INF
		for f2_v in DataService.flights_from(hub_id):
			var cand2: Dictionary = f2_v
			if str(cand2.get("destination_airport_id", "")) != dest_id:
				continue
			var q2: Dictionary = _NewsEvents.quote_flight(cand2)
			if bool(q2.get("news_unavailable", false)):
				continue
			var dep2: float = GameClock.parse_iso_to_unix(str(q2.get("scheduled_departure_utc", "")))
			if dep2 < arr1 + float(mct) * 60.0:
				continue
			if dep2 - arr1 > float(max_cnx) * 60.0:
				continue
			if dep2 < best2_dep:
				best2_dep = dep2
				best2 = q2
		if not best2.is_empty():
			f1 = q1
			f2 = best2
			break
	if f1.is_empty() or f2.is_empty():
		return "当前时刻无可用联程航班（需满足 %d–%d 分钟中转窗口）" % [mct, max_cnx]

	var dep1: float = GameClock.parse_iso_to_unix(str(f1.get("scheduled_departure_utc", "")))
	var arr1: float = dep1 + float(f1.get("duration_minutes", 0)) * 60.0
	var dep2: float = GameClock.parse_iso_to_unix(str(f2.get("scheduled_departure_utc", "")))
	var mct_gap := int(round((dep2 - arr1) / 60.0))
	var price1: float = _cabin_price(f1, cabin)
	var price2: float = _cabin_price(f2, cabin)
	var price: float = price1 + price2
	var bag: Dictionary = _extra_cost(extra_tier, cargo_blocks)
	var total: float = price + float(bag.extra_cost) + float(bag.cargo_cost)
	if total > AppState.cash_usd:
		return "资金不足（需 %s）" % _Economy.format_money(total)
	AppState.add_cash(-total)
	AppState.record_travel_expense(total)
	var ticket1 := {
		"flight_instance_id": f1.get("flight_instance_id", ""),
		"marketing_flight_number": f1.get("marketing_flight_number", ""),
		"airline_name": f1.get("airline_name", ""),
		"alliance_id": f1.get("alliance_id", DataService.airline_alliance_id(str(f1.get("operating_airline_id", "")))),
		"origin_airport_id": f1.get("origin_airport_id", ""),
		"destination_airport_id": f1.get("destination_airport_id", ""),
		"origin_iata": f1.get("origin_iata", ""),
		"destination_iata": f1.get("destination_iata", ""),
		"scheduled_departure_utc": f1.get("scheduled_departure_utc", ""),
		"scheduled_arrival_utc": f1.get("scheduled_arrival_utc", ""),
		"distance_km": f1.get("distance_km", 0),
		"duration_minutes": f1.get("duration_minutes", 0),
		"stops": int(f1.get("stops", 0)),
		"cabin": cabin,
		"ticket_price": price1,
		"extra_kg": bag.extra_kg,
		"cargo_kg": bag.cargo_kg,
		"extra_tier": extra_tier,
		"cargo_blocks": cargo_blocks,
		"total_paid": price1 + float(bag.extra_cost) + float(bag.cargo_cost),
		"ledger_paid": price1 + float(bag.extra_cost) + float(bag.cargo_cost),
		"is_connection_leg": true,
		"connection_leg": 1,
		"connection_final_dest": conn.get("destination_iata", ""),
		# Contractual MCT (the minimum) vs the actual scheduled layover gap.
		"mct_minutes": mct,
		"layover_minutes": mct_gap,
		"enables_cold_chain": bag.enables_cold_chain,
	}
	var ticket2 := {
		"flight_instance_id": f2.get("flight_instance_id", ""),
		"marketing_flight_number": f2.get("marketing_flight_number", ""),
		"airline_name": f2.get("airline_name", ""),
		"alliance_id": f2.get("alliance_id", DataService.airline_alliance_id(str(f2.get("operating_airline_id", "")))),
		"origin_airport_id": f2.get("origin_airport_id", ""),
		"destination_airport_id": f2.get("destination_airport_id", ""),
		"origin_iata": f2.get("origin_iata", ""),
		"destination_iata": f2.get("destination_iata", ""),
		"scheduled_departure_utc": f2.get("scheduled_departure_utc", ""),
		"scheduled_arrival_utc": f2.get("scheduled_arrival_utc", ""),
		"distance_km": f2.get("distance_km", 0),
		"duration_minutes": f2.get("duration_minutes", 0),
		"stops": int(f2.get("stops", 0)),
		"cabin": cabin,
		"ticket_price": price2,
		"extra_kg": 0.0,
		"cargo_kg": bag.cargo_kg,
		"extra_tier": "",
		"cargo_blocks": cargo_blocks,
		"total_paid": price2,
		"ledger_paid": price2,
		"is_connection_leg": true,
		"connection_leg": 2,
		"connection_final_dest": conn.get("destination_iata", ""),
		"enables_cold_chain": bag.enables_cold_chain,
	}
	AppState.held_tickets = [ticket1, ticket2]
	AppState.trip_cabin = cabin
	AppState.trip_baggage_extra_kg = float(bag.extra_kg)
	AppState.cargo_kg_capacity = float(bag.cargo_kg)
	AppState.set_cold_chain(bool(bag.enables_cold_chain))
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


static func rebook_connection_leg2(leg2: Dictionary, mct_minutes: int) -> Dictionary:
	## Rebook a connection leg 2 onto the next real hub→dest flight departing
	## inside [now + mct, now + max_connection] (GDLC Playtest #3 ratchet).
	## Free through-ticket rebooking: keeps the original price/allocation,
	## swaps the flight fields. Returns {} if no candidate exists.
	var hub_id := str(leg2.get("origin_airport_id", ""))
	var dest_id := str(leg2.get("destination_airport_id", ""))
	var econ_mct: Dictionary = DataService.economy.get("mct", {})
	var max_cnx: int = int(econ_mct.get("max_connection_min", 480))
	var now := GameClock.unix_time
	var best: Dictionary = {}
	var best_dep := INF
	for f_v in DataService.flights_from(hub_id):
		var f: Dictionary = f_v
		if str(f.get("destination_airport_id", "")) != dest_id:
			continue
		var q: Dictionary = _NewsEvents.quote_flight(f)
		if bool(q.get("news_unavailable", false)):
			continue
		var dep: float = GameClock.parse_iso_to_unix(str(q.get("scheduled_departure_utc", "")))
		if dep < now + float(mct_minutes) * 60.0 - 30.0:
			continue
		if dep - now > float(max_cnx) * 60.0:
			continue
		if dep < best_dep:
			best_dep = dep
			best = q
	if best.is_empty():
		return {}
	return {
		"flight_instance_id": best.get("flight_instance_id", ""),
		"marketing_flight_number": best.get("marketing_flight_number", ""),
		"airline_name": best.get("airline_name", ""),
		"alliance_id": best.get("alliance_id", DataService.airline_alliance_id(str(best.get("operating_airline_id", "")))),
		"origin_airport_id": best.get("origin_airport_id", ""),
		"destination_airport_id": best.get("destination_airport_id", ""),
		"origin_iata": best.get("origin_iata", ""),
		"destination_iata": best.get("destination_iata", ""),
		"scheduled_departure_utc": best.get("scheduled_departure_utc", ""),
		"scheduled_arrival_utc": best.get("scheduled_arrival_utc", ""),
		"distance_km": best.get("distance_km", 0),
		"duration_minutes": best.get("duration_minutes", 0),
		"stops": int(best.get("stops", 0)),
		"cabin": leg2.get("cabin", "economy"),
		"ticket_price": leg2.get("ticket_price", 0),
		"extra_kg": 0.0,
		"cargo_kg": leg2.get("cargo_kg", 0),
		"extra_tier": "",
		"cargo_blocks": leg2.get("cargo_blocks", 0),
		"total_paid": leg2.get("total_paid", 0),
		"ledger_paid": leg2.get("ledger_paid", 0),
		"is_connection_leg": true,
		"connection_leg": 2,
		"connection_final_dest": leg2.get("connection_final_dest", ""),
		"enables_cold_chain": leg2.get("enables_cold_chain", false),
	}


static func refund_current() -> String:
	var t: Dictionary = next_ticket()
	if t.is_empty():
		return "没有可退机票"
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	if dep <= GameClock.unix_time:
		return "已到起飞时间，不可退票"
	var extras: Dictionary = DataService.economy.get("baggage_extras", {})
	var fee_rate: float = float(extras.get("refund_fee_rate", 0.3))
	# Refund every held leg: a connection holds one itinerary across two legs
	# whose total_paid is split 55/45, so clearing both must refund the full sum.
	var refund: float = refund_held(fee_rate)
	AppState.held_tickets.clear()
	AppState.trip_baggage_extra_kg = 0.0
	AppState.cargo_kg_capacity = 0.0
	AppState.trip_cabin = "economy"
	AppState.set_cold_chain(false)
	EventBus.ticket_purchased.emit()
	return "已退票，退回 %s（含 %d%% 手续费）" % [_Economy.format_money(refund), int(fee_rate * 100.0)]


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
		var tier_price := float(tier.get("price_usd", 0))
		if bool(tier.get("enables_cold_chain", false)):
			tier_price *= ReputationSystem.cold_baggage_discount()
		cost += tier_price
		extra_kg = new_kg
	var blocks: int = int(t.get("cargo_blocks", 0)) + maxi(0, add_cargo_blocks)
	if add_cargo_blocks > 0:
		cost += float(extras.get("cargo_per_50kg_usd", 168)) * float(add_cargo_blocks)
	if cost <= 0.0:
		return "未选择加购项"
	if cost > AppState.cash_usd:
		return "资金不足（需 %s）" % _Economy.format_money(cost)
	AppState.add_cash(-cost)
	AppState.record_travel_expense(cost)
	AppState.last_baggage_cost += cost
	if str(AppState.trip_recap.get("status", "")) == "in_transit":
		AppState.trip_recap["baggage_cost"] = float(AppState.trip_recap.get("baggage_cost", 0.0)) + cost
	t["extra_kg"] = extra_kg
	t["extra_tier"] = extra_tier if extra_tier != "" else t.get("extra_tier", "")
	t["cargo_blocks"] = blocks
	t["cargo_kg"] = 50.0 * float(blocks)
	t["total_paid"] = float(t.get("total_paid", 0)) + cost
	t["ledger_paid"] = float(t.get("ledger_paid", 0)) + cost
	AppState.trip_baggage_extra_kg = extra_kg
	AppState.cargo_kg_capacity = float(t["cargo_kg"])
	AppState.held_tickets[0] = t
	EventBus.ticket_purchased.emit()
	EventBus.inventory_changed.emit()
	return "加购成功，支付 %s" % _Economy.format_money(cost)


static func refund_held(fee_rate: float = -1.0) -> float:
	if fee_rate < 0.0:
		fee_rate = float(DataService.economy.get("baggage_extras", {}).get("refund_fee_rate", 0.3))
	var refund := 0.0
	var ledger_refund := 0.0
	for ticket in AppState.held_tickets:
		refund += float(ticket.get("total_paid", 0.0)) * (1.0 - clampf(fee_rate, 0.0, 1.0))
		ledger_refund += float(ticket.get("ledger_paid", 0.0)) * (1.0 - clampf(fee_rate, 0.0, 1.0))
	AppState.add_cash(refund)
	AppState.record_travel_expense(-minf(maxf(0.0, AppState.travel_expenses), ledger_refund))
	return refund


static func apply_cargo_promotion() -> float:
	## One free block per itinerary, including the receipt used for later refunds.
	if AppState.held_tickets.is_empty():
		return 0.0
	var first: Dictionary = AppState.held_tickets[0]
	if bool(first.get("cargo_promotion_applied", false)) or int(first.get("cargo_blocks", 0)) <= 0:
		return 0.0
	var remaining: float = float(DataService.economy.get("baggage_extras", {}).get("cargo_per_50kg_usd", 0))
	var refunded := 0.0
	var ledger_refunded := 0.0
	for ticket in AppState.held_tickets:
		var reduction: float = minf(remaining, float(ticket.get("total_paid", 0)))
		var ledger_reduction: float = minf(reduction, float(ticket.get("ledger_paid", 0)))
		ticket["total_paid"] = float(ticket.get("total_paid", 0)) - reduction
		ticket["ledger_paid"] = float(ticket.get("ledger_paid", 0)) - ledger_reduction
		ticket["cargo_promotion_applied"] = true
		remaining -= reduction
		refunded += reduction
		ledger_refunded += ledger_reduction
	AppState.add_cash(refunded)
	AppState.record_travel_expense(-minf(maxf(0.0, AppState.travel_expenses), ledger_refunded))
	return refunded
