extends SceneTree
## Headless v0.3 full-loop regression — the automated equivalent of the editor
## manual test "完整环：延误一次 + 联程 MCT + 头等 + 冷藏".
## Covers: MCT-aware connection scheduling, first-class + refrigerated (cold)
## baggage purchase, cold-chain quality decay, seeded delay simulation, and the
## post-arrival state reset.
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeV3Loop.gd

var _errors: PackedStringArray = []
var data: Node = null
var app_state: Node = null
var clock: Node = null

# Loaded lazily inside _run: the system scripts resolve autoload singletons as
# globals, which are only registered after the autoloads are added to the tree.
var _search_script: GDScript
var _ticket_script: GDScript
var _economy_script: GDScript
var _inventory_script: GDScript


func _initialize() -> void:
	data = root.get_node_or_null("DataService") as Node
	app_state = root.get_node_or_null("AppState") as Node
	clock = root.get_node_or_null("GameClock") as Node
	call_deferred("_run")


func _fail(msg: String) -> void:
	_errors.append(msg)


func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond


func _run() -> void:
	var ok := true
	_check(data != null and bool(data.get("loaded")), "DataService not loaded")
	_check(app_state != null, "AppState missing")
	_check(clock != null, "GameClock missing")
	if data == null or app_state == null or clock == null:
		_finish()

	_search_script = load("res://scripts/systems/FlightSearch.gd") as GDScript
	_ticket_script = load("res://scripts/systems/TicketService.gd") as GDScript
	_economy_script = load("res://scripts/systems/EconomySystem.gd") as GDScript
	_inventory_script = load("res://scripts/systems/InventorySystem.gd") as GDScript
	ok = _check(_search_script != null and _ticket_script != null
			and _economy_script != null and _inventory_script != null,
			"system scripts failed to load (autoload globals unresolved?)") and ok
	if _search_script == null or _ticket_script == null:
		_finish()

	# ── v0.3 data surface ──
	var world: Dictionary = data.get("world") as Dictionary
	ok = _check(str(world.get("meta", {}).get("etl_version", "")) == "0.3.0",
			"etl_version != 0.3.0") and ok
	var alliances: Dictionary = data.get("alliances_by_id") as Dictionary
	ok = _check(alliances.size() >= 3, "alliances_by_id < 3") and ok
	var airlines: Dictionary = data.get("airlines_by_id") as Dictionary
	ok = _check(airlines.size() >= 10, "airlines_by_id < 10") and ok
	var dg: Dictionary = data.get("dangerous_goods") as Dictionary
	ok = _check(not dg.is_empty(), "dangerous_goods empty") and ok
	var econ: Dictionary = data.get("economy") as Dictionary
	ok = _check(econ.has("mct") and econ.has("reliability") and econ.has("cold_chain"),
			"economy.mct/reliability/cold_chain missing") and ok

	# ── start a fresh game at PVG hub ──
	app_state.call("reset_new_game", "pvg")
	ok = _check(str(app_state.get("current_airport_id")) == "pvg", "new game not at pvg") and ok

	# ═══ PART A: 联程 MCT — schedule must use edge/airport MCT, not hardcoded 90 ═══
	var conns: Array = _search_script.search_connections("PVG")
	ok = _check(conns.size() > 0, "no connections from PVG") and ok
	var conn: Dictionary = {}
	for c_v in conns:
		var c: Dictionary = c_v
		if int(c.get("mct_minutes", 0)) > 0 and int(c.get("mct_minutes", 0)) != 90:
			conn = c
			break
	if conn.is_empty():
		for c_v in conns:
			var c: Dictionary = c_v
			if int(c.get("mct_minutes", 0)) > 0:
				conn = c
				break
	ok = _check(not conn.is_empty(), "no connection with mct_minutes > 0") and ok
	if not conn.is_empty():
		var mct := int(conn.get("mct_minutes", 0))
		var seg1 := int(conn.get("seg1_duration_avg", 0))
		var seg2 := int(conn.get("seg2_duration_avg", 0))
		ok = _check(int(conn.get("duration_minutes", 0)) == seg1 + mct + seg2,
				"connection duration does not include MCT") and ok
		var cmsg: String = _ticket_script.purchase_connection(conn, "economy", "", 0)
		ok = _check(cmsg == "", "connection purchase failed: %s" % cmsg) and ok
		var held: Array = app_state.get("held_tickets")
		ok = _check(held.size() == 2, "expected 2 connection legs") and ok
		if held.size() == 2:
			var t1: Dictionary = held[0]
			var t2: Dictionary = held[1]
			ok = _check(int(t1.get("mct_minutes", 0)) == mct,
					"leg1 mct_minutes mismatch: %s != %d" % [t1.get("mct_minutes", 0), mct]) and ok
			var arr1: float = clock.call("parse_iso_to_unix", str(t1.get("scheduled_arrival_utc", "")))
			var dep2: float = clock.call("parse_iso_to_unix", str(t2.get("scheduled_departure_utc", "")))
			var gap_min: float = (dep2 - arr1) / 60.0
			ok = _check(absf(gap_min - float(mct)) < 1.0,
					"MCT layover gap %.1f min != %d min" % [gap_min, mct]) and ok
		var stats: Dictionary = app_state.get("stats")
		ok = _check(float(stats.get("connection_flights", 0)) >= 1.0,
				"connection_flights stat not counted") and ok
		# Refund must cover BOTH legs: a connection splits total_paid 55/45.
		var fee_rate := float(econ.get("baggage_extras", {}).get("refund_fee_rate", 0.3))
		var paid_total := 0.0
		for t_v in held:
			paid_total += float((t_v as Dictionary).get("total_paid", 0))
		var cash_before_refund := float(app_state.get("cash_usd"))
		var rmsg: String = _ticket_script.refund_current()
		ok = _check(not rmsg.begins_with("没有"), "connection refund failed: %s" % rmsg) and ok
		var refunded := float(app_state.get("cash_usd")) - cash_before_refund
		var expected_refund := paid_total * (1.0 - fee_rate)
		ok = _check(absf(refunded - expected_refund) < 0.01,
				"connection refund %.2f != sum of legs %.2f" % [refunded, expected_refund]) and ok

	# ═══ PART B: 头等 + 冷藏 + 延误 — one first-class refrigerated flight that rolls a delay ═══
	var ops := (load("res://scripts/systems/FlightOps.gd") as GDScript).new() as Node
	root.add_child(ops)
	ops.set_process(false)

	var flights: Array = data.call("flights_from", "pvg")
	var delayed_fl: Dictionary = {}
	var saved_unix: float = float(clock.get("unix_time"))
	for f_v in flights:
		var f: Dictionary = f_v
		if not bool(f.get("cabin_first_available", false)):
			continue
		var dep: float = clock.call("parse_iso_to_unix", str(f.get("scheduled_departure_utc", "")))
		if dep <= saved_unix + 60.0:
			continue
		clock.set("unix_time", dep)
		var roll: Dictionary = ops.call("_reliability_roll", {
			"flight_instance_id": f.get("flight_instance_id", ""),
			"scheduled_departure_utc": f.get("scheduled_departure_utc", ""),
		}) as Dictionary
		clock.set("unix_time", saved_unix)
		if not bool(roll.get("cancelled", false)) and int(roll.get("delay_min", 0)) > 0:
			delayed_fl = f
			break
	clock.set("unix_time", saved_unix)
	ok = _check(not delayed_fl.is_empty(),
			"no first-class future flight rolls a delay — widen data range") and ok

	if not delayed_fl.is_empty():
		var ticket_cfg: Dictionary = econ.get("ticket", {})
		var first_kg := float(ticket_cfg.get("baggage_first_kg", 100.0))
		var carry_kg := float(ticket_cfg.get("carry_on_kg", 5.0))
		var pmsg: String = _ticket_script.purchase(delayed_fl, "first", "cold", 0)
		ok = _check(pmsg == "", "first+cold purchase failed: %s" % pmsg) and ok
		ok = _check(str(app_state.get("trip_cabin")) == "first", "trip_cabin != first") and ok
		ok = _check(bool(app_state.get("trip_cold_chain")), "trip_cold_chain not set") and ok
		var held: Array = app_state.get("held_tickets")
		ok = _check(not held.is_empty(), "held_tickets empty after purchase") and ok
		if not held.is_empty():
			var ticket: Dictionary = held[0]
			ok = _check(absf(float(ticket.get("ticket_price", 0.0))
					- float(delayed_fl.get("ticket_base_price_first", 0.0))) < 0.01,
					"first-class price not from ticket_base_price_first") and ok
			var limit: float = app_state.call("personal_baggage_limit_kg")
			ok = _check(absf(limit - (first_kg + carry_kg)) < 0.01,
					"first-class baggage limit %.1f != %.1f" % [limit, first_kg + carry_kg]) and ok
			ok = _check(str(ticket.get("alliance_id", "")) != "",
					"ticket missing alliance_id") and ok

		# ── cold-chain quality decay: protected < unprotected aging ──
		var city_id: String = str(app_state.call("current_city_id"))
		var cold_pid := ""
		var cold_life := 100.0
		for pid in data.call("market_product_ids", city_id):
			var p: Dictionary = data.call("get_product", pid)
			if bool(p.get("requires_cold_chain", false)) \
					and float(p.get("shelf_life_hours", 99999.0)) < 90000.0:
				cold_pid = pid
				cold_life = float(p.get("shelf_life_hours", 100.0))
				break
		if cold_pid != "":
			var bmsg: String = _inventory_script.buy(cold_pid, 2, false)
			ok = _check(bmsg == "", "cold-chain product buy failed: %s" % bmsg) and ok
			var inv: Array = app_state.get("inventory")
			if inv.size() > 0:
				var item: Dictionary = inv[0]
				item["purchased_unix"] = float(clock.get("unix_time")) - 24.0 * 3600.0
				# Protected: cold window covers the full 24h hold.
				app_state.set("trip_cold_chain", true)
				app_state.set("cold_chain_start_unix", float(item["purchased_unix"]))
				item["cold_protected_hours"] = 0.0
				var q_protected: float = _economy_script.current_quality(item)
				# Unprotected: same hold, no window, no folded hours.
				app_state.set("trip_cold_chain", false)
				app_state.set("cold_chain_start_unix", -1.0)
				item.erase("cold_protected_hours")
				var q_unprotected: float = _economy_script.current_quality(item)
				# Restore the protected window for the boarding/arrival phase.
				app_state.set("trip_cold_chain", true)
				app_state.set("cold_chain_start_unix", float(item["purchased_unix"]))
				item["cold_protected_hours"] = 0.0
				ok = _check(q_unprotected < q_protected,
						"cold chain: unprotected %.3f !< protected %.3f"
						% [q_unprotected, q_protected]) and ok
				ok = _check(q_protected > 0.0 and q_protected <= 1.0,
						"protected quality out of range: %.3f" % q_protected) and ok
				ok = _check(absf(q_protected - (1.0 - (24.0 * 0.35 / cold_life))) < 0.001,
						"protected quality %.3f != expected %.3f" % [q_protected, 1.0 - 24.0 * 0.35 / cold_life]) and ok
		else:
			_fail("no finite-shelf cold-chain product in PVG market")
			ok = false

		# ── board the flight: seeded delay fires, arrival resets trip state ──
		var ff := ops.call("fast_forward_to_departure") as String
		ok = _check(ff == "", "fast_forward: %s" % ff) and ok
		await ops.call("start_boarding", app_state.get("held_tickets")[0])
		var stats: Dictionary = app_state.get("stats")
		ok = _check(float(stats.get("delayed_flights", 0)) >= 1.0,
				"delay was not simulated") and ok
		ok = _check(float(stats.get("first_flights", 0)) >= 1.0,
				"first_flights not counted") and ok
		ok = _check(int(stats.get("consecutive_on_time", -1)) == 0,
				"consecutive_on_time must reset to 0 after a delay (was %s)"
				% stats.get("consecutive_on_time", -1)) and ok
		ok = _check((app_state.get("held_tickets") as Array).is_empty(),
				"held_tickets not cleared after arrival") and ok
		ok = _check(not bool(app_state.get("trip_cold_chain")),
				"trip_cold_chain not reset after arrival") and ok
		ok = _check((app_state.get("travel_log") as Array).size() >= 1,
				"travel_log not appended") and ok
		# Cold protection must survive arrival: protected hours are folded into
		# the item so the post-arrival sale still benefits from the cold window.
		var inv_after: Array = app_state.get("inventory")
		if inv_after.size() > 0:
			var cold_item: Dictionary = inv_after[0]
			var protected_hours: float = float(cold_item.get("cold_protected_hours", 0.0))
			ok = _check(protected_hours > 0.0,
					"cold_protected_hours not folded after arrival") and ok
			var q_after: float = _economy_script.current_quality(cold_item)
			ok = _check(q_after > (1.0 - (24.0 + protected_hours) * 2.0 / cold_life) + 0.001,
					"cold-chain sale benefit lost after arrival: %.3f" % q_after) and ok
		else:
			_fail("inventory empty after arrival")
			ok = false

	_finish(ok)


func _finish(ok: bool = false) -> void:
	if ok and _errors.is_empty():
		print("SMOKE_V3_LOOP_OK")
		quit(0)
	else:
		print("SMOKE_V3_LOOP_FAIL")
		for e in _errors:
			printerr("  - ", e)
		quit(1)
