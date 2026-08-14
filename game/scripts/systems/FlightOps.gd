extends Node
## Handles fast-forward, forced boarding, 5s transition, arrival.
## v0.3: delay/cancel simulation (seeded), first-class / alliance / stopover stats.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Tickets = preload("res://scripts/systems/TicketService.gd")

signal transition_started(ticket: Dictionary)
signal transition_finished
signal layover_prompt(hub_iata: String, mct_minutes: int)

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
		EventBus.market_changed.emit()
		EventBus.news_changed.emit()
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
	if before_date != after_date:
		EventBus.news_changed.emit()
	AppState.log_stat("fast_forwards", 1.0)
	return ""


func _reliability_roll(ticket: Dictionary) -> Dictionary:
	## Seeded delay/cancel. Returns {cancelled, delay_min, on_time}.
	var rel: Dictionary = DataService.economy.get("reliability", {})
	if not bool(rel.get("enabled", true)) or not AppState.reliability_events_enabled:
		return {"cancelled": false, "delay_min": 0, "on_time": true}
	var seed_s := "%s|%s|%s" % [
		ticket.get("flight_instance_id", ""),
		ticket.get("scheduled_departure_utc", ""),
		GameClock.game_date_string(),
	]
	# sha256-derived seed — GDScript's builtin hash() is process-randomized on
	# strings, which made delay/cancel rolls (and the smokes that scan them)
	# flaky across runs (GDLC Playtest #4).
	var h := seed_s.sha256_text().substr(0, 8).hex_to_int()
	var rng := RandomNumberGenerator.new()
	rng.seed = h if h != 0 else 1
	var cancel_p: float = float(rel.get("cancel_prob", 0.015))
	if rng.randf() < cancel_p:
		return {"cancelled": true, "delay_min": 0, "on_time": false}
	var delay_p: float = float(rel.get("delay_prob", 0.08))
	if rng.randf() < delay_p:
		var mean: float = float(rel.get("delay_min_mean", 25))
		var sigma: float = float(rel.get("delay_min_sigma", 18))
		var cap: float = float(rel.get("delay_min_cap", 180))
		var mins: int = int(clamp(rng.randfn(mean, sigma), 5.0, cap))
		return {"cancelled": false, "delay_min": mins, "on_time": false}
	return {"cancelled": false, "delay_min": 0, "on_time": true}


func start_boarding(ticket: Dictionary) -> void:
	if _boarding:
		return
	# Origin guard (ratchet P0): never board a ticket that does not depart from
	# the player's current airport — a stale leg would teleport the player.
	# Stale itineraries are dropped with the same 70% refund as a cancellation.
	if str(ticket.get("origin_airport_id", "")) != AppState.current_airport_id:
		var paid_total := 0.0
		for t_v in AppState.held_tickets:
			paid_total += float((t_v as Dictionary).get("total_paid", 0.0))
		AppState.add_cash(paid_total * 0.7)
		AppState.held_tickets = []
		AppState.trip_baggage_extra_kg = 0.0
		AppState.trip_cabin = "economy"
		AppState.set_cold_chain(false)
		AppState.cargo_kg_capacity = 0.0
		var _fee_pct := int(float(DataService.economy.get("baggage_extras", {}).get("refund_fee_rate", 0.3)) * 100.0)
		EventBus.tutorial_hint.emit("行程已失效 — 已退回 %d%% 票款（%d%% 为退票手续费），请重新购票。" % [100 - _fee_pct, _fee_pct])
		EventBus.ticket_purchased.emit()
		transition_finished.emit()
		return
	_boarding = true
	GameClock.set_paused(true)

	var roll: Dictionary = _reliability_roll(ticket)
	if bool(roll.get("cancelled", false)):
		AppState.log_stat("cancelled_flights", 1.0)
		AppState.stats["consecutive_on_time"] = 0
		# Soft cancel: refund 70% of the FULL itinerary and drop every held leg.
		# Keeping a connection leg 2 whose origin is a hub the player never
		# reached would let _process auto-board it later and teleport the player
		# (ratchet P0 — SmokeConnectionContract.gd part B).
		var paid_total := 0.0
		for t_v in AppState.held_tickets:
			paid_total += float((t_v as Dictionary).get("total_paid", 0.0))
		AppState.add_cash(paid_total * 0.7)
		AppState.held_tickets = []
		AppState.trip_baggage_extra_kg = 0.0
		AppState.trip_cabin = "economy"
		AppState.set_cold_chain(false)
		AppState.cargo_kg_capacity = 0.0
		var _fee_pct := int(float(DataService.economy.get("baggage_extras", {}).get("refund_fee_rate", 0.3)) * 100.0)
		EventBus.tutorial_hint.emit("航班取消（模拟）— 已退回 %d%% 票款（%d%% 为退票手续费）。重建时刻表，不代表真实取消。" % [100 - _fee_pct, _fee_pct])
		EventBus.ticket_purchased.emit()
		_boarding = false
		GameClock.set_paused(false)
		transition_finished.emit()
		return

	var before_operation_date := GameClock.game_date_string()
	var delay_min: int = int(roll.get("delay_min", 0))
	if delay_min > 0:
		AppState.log_stat("delayed_flights", 1.0)
		AppState.stats["consecutive_on_time"] = 0
		GameClock.add_minutes(float(delay_min))
		EventBus.tutorial_hint.emit("航班延误 %d 分钟（模拟）。" % delay_min)

	AudioService.play_sfx("sfx_boarding_alert")
	transition_started.emit(ticket)
	var dur: float = float(ticket.get("duration_minutes", 0))
	var hours: float = dur / 60.0
	GameClock.add_minutes(dur)
	var after_flight_date := GameClock.game_date_string()
	if before_operation_date != after_flight_date:
		_Economy.recover_demand_for_new_day(before_operation_date, after_flight_date)
		AppState.last_market_date = after_flight_date
		EventBus.market_changed.emit()
		EventBus.news_changed.emit()
	_Economy.age_inventory(0.0)
	_Economy.apply_flight_fragility(hours)
	var tree := Engine.get_main_loop() as SceneTree
	# Connection layover: brief pause between legs when remaining ticket waits at hub.
	var is_cnx1 := bool(ticket.get("is_connection_leg", false)) and int(ticket.get("connection_leg", 0)) == 1
	var wait_s := 5.0
	if is_cnx1:
		wait_s = 4.0
	await tree.create_timer(wait_s).timeout
	_arrive(ticket, bool(roll.get("on_time", true)))
	if is_cnx1:
		# MCT re-check on ACTUAL arrival (GDLC Playtest #3 ratchet): a leg-1
		# delay may have pushed the hub gap below the contractual MCT — rebook
		# leg 2 inside the window or refund-and-park. Never honor an impossible
		# connection.
		var mct_contract := int(ticket.get("mct_minutes", DataService.mct_minutes_for_airport(str(ticket.get("destination_airport_id", "")))))
		var hub_id := str(ticket.get("destination_airport_id", ""))
		var t2: Dictionary = _Tickets.next_ticket()
		var gap_min := 0.0
		if not t2.is_empty() and str(t2.get("origin_airport_id", "")) == hub_id:
			var dep2: float = GameClock.parse_iso_to_unix(str(t2.get("scheduled_departure_utc", "")))
			gap_min = (dep2 - GameClock.unix_time) / 60.0
			if gap_min < float(mct_contract) - 0.5:
				var replacement := _Tickets.rebook_connection_leg2(t2, mct_contract)
				if replacement.is_empty():
					# Refund-and-park: 70% of the remaining itinerary.
					var paid_total := 0.0
					for t_v in AppState.held_tickets:
						paid_total += float((t_v as Dictionary).get("total_paid", 0.0))
					AppState.add_cash(paid_total * 0.7)
					AppState.held_tickets = []
					AppState.trip_baggage_extra_kg = 0.0
					AppState.trip_cabin = "economy"
					AppState.set_cold_chain(false)
					AppState.cargo_kg_capacity = 0.0
					var _fee_pct := int(float(DataService.economy.get("baggage_extras", {}).get("refund_fee_rate", 0.3)) * 100.0)
					EventBus.tutorial_hint.emit("前段延误致转机衔接失败 — 已退回 %d%% 票款（%d%% 为退票手续费），请重新购票。" % [100 - _fee_pct, _fee_pct])
					EventBus.ticket_purchased.emit()
				else:
					AppState.held_tickets = [replacement]
					var dep2_new: float = GameClock.parse_iso_to_unix(str(replacement.get("scheduled_departure_utc", "")))
					gap_min = (dep2_new - GameClock.unix_time) / 60.0
					EventBus.tutorial_hint.emit("前段延误致转机紧张 — 已免费改签至 %s。" %
							[str(replacement.get("marketing_flight_number", ""))])
					EventBus.ticket_purchased.emit()
		# Honest layover copy: the actual remaining gap vs the contractual MCT.
		layover_prompt.emit(str(ticket.get("destination_iata", "")), int(round(gap_min)))
		EventBus.tutorial_hint.emit("转机中：%s · 中转 %d 分钟（本场 MCT %d）" %
				[ticket.get("destination_iata", ""), int(round(gap_min)), mct_contract])
		await tree.create_timer(1.0).timeout
	_boarding = false
	GameClock.set_paused(false)
	transition_finished.emit()


func _arrive(ticket: Dictionary, on_time: bool = true) -> void:
	var dest: String = str(ticket.get("destination_airport_id", ""))
	var cargo_value: float = _Economy.inventory_cargo_value_usd()
	var cash_before_note: float = AppState.cash_usd
	AppState.current_airport_id = dest
	AppState._mark_visit(dest)
	# Keep remaining connection legs that depart from the arrival airport.
	var remaining: Array = []
	var consumed_id := str(ticket.get("flight_instance_id", ""))
	for t_v in AppState.held_tickets:
		var t: Dictionary = t_v
		if str(t.get("flight_instance_id", "")) == consumed_id:
			continue
		if str(t.get("origin_airport_id", "")) == dest:
			remaining.append(t)
	AppState.held_tickets = remaining
	if remaining.is_empty():
		AppState.trip_baggage_extra_kg = 0.0
		AppState.trip_cabin = "economy"
		# Close the cold-chain window before recomputing quality so the stored
		# quality keeps the protected portion of the journey instead of aging
		# the whole trip at the unprotected rate.
		AppState.set_cold_chain(false)
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
		"alliance_id": ticket.get("alliance_id", ""),
		"departure_time": ticket.get("scheduled_departure_utc", ""),
		"arrival_time": ticket.get("scheduled_arrival_utc", ""),
		"distance": ticket.get("distance_km", 0),
		"ticket_price": ticket.get("ticket_price", 0),
		"cargo_value": cargo_value,
		"profit_after_arrival": cash_before_note - float(ticket.get("total_paid", ticket.get("ticket_price", 0))),
		"cash_on_arrival": cash_before_note,
		"stops": int(ticket.get("stops", 0)),
	})
	# Achievement / stats tracking
	AppState.log_stat("total_flight_segments", 1.0)
	AppState.log_stat("total_distance_km", float(ticket.get("distance_km", 0)))
	AppState.log_stat("total_flight_hours", float(ticket.get("duration_minutes", 0)) / 60.0)
	AppState.mark_route_flown(str(ticket.get("origin_iata", "")), str(ticket.get("destination_iata", "")))
	ReputationSystem.add_points(2)
	var is_cnx_leg2 := bool(ticket.get("is_connection_leg", false)) and int(ticket.get("connection_leg", 0)) != 1
	var cabin := str(ticket.get("cabin", ""))
	if cabin == "business" and not is_cnx_leg2:
		AppState.log_stat("business_flights", 1.0)
	if cabin == "first" and not is_cnx_leg2:
		AppState.log_stat("first_flights", 1.0)
	if float(ticket.get("cargo_kg", 0)) > 0.0 and not is_cnx_leg2:
		AppState.log_stat("cargo_flights", 1.0)
	if int(ticket.get("stops", 0)) > 0 and not is_cnx_leg2:
		AppState.log_stat("stopover_flights", 1.0)
	var aid := str(ticket.get("alliance_id", ""))
	if aid != "" and aid != "none" and not is_cnx_leg2:
		AppState.log_stat("alliance_flights", 1.0)
	if on_time:
		AppState.log_stat("consecutive_on_time", 1.0)
	AppState.update_extreme_airport(dest)
	AppState.last_market_date = GameClock.game_date_string()
	SaveSystem.save_game()
	EventBus.arrived.emit()
	EventBus.airport_selected.emit(dest)
	EventBus.inventory_changed.emit()
	if not bool(AppState.tutorial_flags.get("arrived", false)):
		AppState.tutorial_flags["arrived"] = true
		var tip := I18nService.tutorial("first_arrive")
		if tip.is_empty():
			tip = "已抵达目的地。打开「市场」出售商品结算利润。"
		EventBus.tutorial_hint.emit(tip)
