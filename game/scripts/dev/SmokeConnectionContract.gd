extends SceneTree
## Connection contract regression — the automated equivalent of two ratchet P0s:
##   P0-A: a purchased connection's legs must BE real scheduled flights
##         (no minted cnx1_/cnx2_ phantom tickets) and must chain
##         origin→hub→destination.
##   P0-B: a leg-1 cancellation must not strand leg 2 and teleport the player
##         (itinerary dropped, 70% of the FULL itinerary refunded, boarding a
##         ticket whose origin != current airport is refused).
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeConnectionContract.gd

var _errors: PackedStringArray = []
var data: Node = null
var app_state: Node = null
var clock: Node = null

# Loaded lazily inside _run: the system scripts resolve autoload singletons as
# globals, which are only registered after the autoloads are added to the tree.
var _search_script: GDScript
var _ticket_script: GDScript
var _ops_script: GDScript


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
	_ops_script = load("res://scripts/systems/FlightOps.gd") as GDScript
	ok = _check(_search_script != null and _ticket_script != null and _ops_script != null,
			"system scripts failed to load (autoload globals unresolved?)") and ok
	if _search_script == null or _ticket_script == null or _ops_script == null:
		_finish()

	# Freeze the world clock so flight selection stays deterministic.
	clock.call("set_paused", true)

	var ops := _ops_script.new() as Node
	root.add_child(ops)
	ops.set_process(false)

	ok = await _part_a_real_flights() and ok
	ok = await _part_b_cancel_no_teleport(ops) and ok
	ok = await _part_c_boarding_origin_guard(ops) and ok

	_finish(ok)


# ═══ PART A: every purchased connection leg must BE a scheduled flight
#     chaining origin→hub→destination ═══
func _part_a_real_flights() -> bool:
	var ok := true
	app_state.call("reset_new_game", "pvg")
	clock.set("unix_time", 1740787200.0)  # 2025-03-01 00:00 UTC

	var conns: Array = _search_script.search_connections("PVG")
	ok = _check(conns.size() > 0, "no connections from PVG") and ok
	var conn_used: Dictionary = {}
	var held: Array = []
	for c_v in conns:
		var c: Dictionary = c_v
		var pmsg: String = _ticket_script.purchase_connection(c, "economy", "", 0)
		if pmsg == "":
			conn_used = c
			held = app_state.get("held_tickets") as Array
			break
	ok = _check(not conn_used.is_empty(),
			"no connection purchasable from PVG at baseline time (real-flight assembly)") and ok
	if conn_used.is_empty():
		return ok
	ok = _check(held.size() == 2, "expected 2 connection legs, got %d" % held.size()) and ok
	if held.size() != 2:
		return ok
	var leg1: Dictionary = held[0]
	var leg2: Dictionary = held[1]
	var hub_id := str(conn_used.get("hub_airport_id", ""))
	var dest_id := str(conn_used.get("destination_airport_id", ""))
	# Chain contract: origin→hub, hub→dest.
	ok = _check(str(leg1.get("origin_airport_id", "")) == "pvg"
			and str(leg1.get("destination_airport_id", "")) == hub_id,
			"leg 1 does not chain origin→hub") and ok
	ok = _check(str(leg2.get("origin_airport_id", "")) == hub_id
			and str(leg2.get("destination_airport_id", "")) == dest_id,
			"leg 2 does not chain hub→destination") and ok
	for leg_v in held:
		var leg: Dictionary = leg_v
		var origin_id := str(leg.get("origin_airport_id", ""))
		var fid := str(leg.get("flight_instance_id", ""))
		var dep_iso := str(leg.get("scheduled_departure_utc", ""))
		var found := false
		for f_v in data.call("flights_from", origin_id):
			var f: Dictionary = f_v
			if str(f.get("flight_instance_id", "")) == fid \
					and str(f.get("scheduled_departure_utc", "")) == dep_iso:
				found = true
				break
		ok = _check(found,
				"phantom leg: %s (%s %s) is not a scheduled flight" % [fid, origin_id, dep_iso]) and ok
	# Layover gap must sit inside [edge MCT, max_connection].
	var mct := int(conn_used.get("mct_minutes", 0))
	var arr1: float = clock.call("parse_iso_to_unix", str(leg1.get("scheduled_arrival_utc", "")))
	var dep2: float = clock.call("parse_iso_to_unix", str(leg2.get("scheduled_departure_utc", "")))
	var gap_min: float = (dep2 - arr1) / 60.0
	var max_cnx := int(data.get("economy").get("mct", {}).get("max_connection_min", 480))
	ok = _check(gap_min >= float(mct) - 0.5 and gap_min <= float(max_cnx) + 0.5,
			"layover gap %.1f min outside [%d, %d]" % [gap_min, mct, max_cnx]) and ok
	return ok


# ═══ PART B: leg-1 cancel drops the whole itinerary, refunds 70% of it,
#     and never teleports the player ═══
func _part_b_cancel_no_teleport(ops: Node) -> bool:
	var ok := true
	app_state.call("reset_new_game", "pvg")
	var start_cash := float(app_state.get("cash_usd"))
	var baseline := 1740787200.0  # 2025-03-01 00:00 UTC
	clock.set("unix_time", baseline)

	# Pick a REAL scheduled flight from PVG whose reliability roll is a
	# cancellation at its own departure time (deterministic scan, no purchase).
	var t1: Dictionary = {}
	for f_v in data.call("flights_from", "pvg"):
		var f: Dictionary = f_v
		var dep: float = clock.call("parse_iso_to_unix", str(f.get("scheduled_departure_utc", "")))
		if dep < baseline + 60.0:
			continue
		clock.set("unix_time", dep)
		var roll: Dictionary = ops.call("_reliability_roll", {
			"flight_instance_id": f.get("flight_instance_id", ""),
			"scheduled_departure_utc": f.get("scheduled_departure_utc", ""),
		}) as Dictionary
		if bool(roll.get("cancelled", false)):
			t1 = _ticket_from_flight(f, 1, 300.0)
			break
	ok = _check(not t1.is_empty(), "no real PVG flight rolls a cancellation — widen scan") and ok
	if t1.is_empty():
		return ok
	clock.set("unix_time", baseline)

	# Leg 2: a real flight from leg 1's destination whose roll is NOT cancelled
	# (so that on the pre-fix code it would actually board and teleport).
	var hub_id := str(t1.get("destination_airport_id", ""))
	var arr1: float = clock.call("parse_iso_to_unix", str(t1.get("scheduled_arrival_utc", "")))
	var t2: Dictionary = {}
	for f_v in data.call("flights_from", hub_id):
		var f: Dictionary = f_v
		var dep: float = clock.call("parse_iso_to_unix", str(f.get("scheduled_departure_utc", "")))
		if dep < arr1 + 90.0 * 60.0:
			continue
		clock.set("unix_time", dep)
		var roll: Dictionary = ops.call("_reliability_roll", {
			"flight_instance_id": f.get("flight_instance_id", ""),
			"scheduled_departure_utc": f.get("scheduled_departure_utc", ""),
		}) as Dictionary
		if not bool(roll.get("cancelled", false)):
			t2 = _ticket_from_flight(f, 2, 200.0)
			break
	ok = _check(not t2.is_empty(), "no non-cancelling real flight from hub after leg 1") and ok
	if t2.is_empty():
		return ok
	clock.set("unix_time", baseline)

	# Hold the itinerary and fly leg 1 into its cancellation.
	app_state.set("held_tickets", [t1, t2])
	var t1_dep: float = clock.call("parse_iso_to_unix", str(t1.get("scheduled_departure_utc", "")))
	var t2_dep: float = clock.call("parse_iso_to_unix", str(t2.get("scheduled_departure_utc", "")))
	clock.set("unix_time", t1_dep)
	await ops.call("start_boarding", t1)
	clock.call("set_paused", true)

	# 1. The whole itinerary is dropped — leg 2 must not survive a leg-1 cancel.
	ok = _check((app_state.get("held_tickets") as Array).is_empty(),
			"leg 2 survived a leg-1 cancellation (teleport trap)") and ok
	# 2. Refund is 70% of the FULL itinerary (300 + 200).
	ok = _check(absf(float(app_state.get("cash_usd")) - (start_cash + 350.0)) < 1.0,
			"cancel refund %.2f != 70%% of itinerary (expect cash %.2f)" %
			[float(app_state.get("cash_usd")), start_cash + 350.0]) and ok
	# 3. Time passes beyond leg 2's departure — the player never moves.
	clock.set("unix_time", t2_dep + 3600.0)
	ops.call("_process", 0.0)
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(8.0).timeout
	ok = _check(str(app_state.get("current_airport_id")) == "pvg",
			"player teleported after connection cancel") and ok
	ok = _check((app_state.get("travel_log") as Array).is_empty(),
			"travel log recorded a flight after a cancelled connection") and ok
	return ok


# ═══ PART C: boarding a ticket whose origin is not the current airport
#     must be refused (defense in depth against any stale-ticket path) ═══
func _part_c_boarding_origin_guard(ops: Node) -> bool:
	var ok := true
	app_state.call("reset_new_game", "pvg")
	clock.set("unix_time", 1740787200.0)
	# Pick a forged id/dep whose reliability roll is not a cancellation, so the
	# only thing standing between the forged ticket and a teleport is the guard.
	var now_t := 1740787200.0
	var dep_t := now_t + 60.0
	var dep_iso: String = _ticket_script._unix_to_iso(dep_t)
	var forged_id := ""
	for i in range(200):
		var cand := "forged_%d" % i
		clock.set("unix_time", dep_t)
		var roll: Dictionary = ops.call("_reliability_roll", {
			"flight_instance_id": cand,
			"scheduled_departure_utc": dep_iso,
		}) as Dictionary
		if not bool(roll.get("cancelled", false)):
			forged_id = cand
			break
	ok = _check(forged_id != "", "could not find a non-cancelling forged id") and ok
	if forged_id == "":
		return ok
	var forged := {
		"flight_instance_id": forged_id,
		"marketing_flight_number": "FORGED",
		"airline_name": "forged",
		"origin_airport_id": "ord",
		"destination_airport_id": "dfw",
		"origin_iata": "ORD",
		"destination_iata": "DFW",
		"scheduled_departure_utc": dep_iso,
		"scheduled_arrival_utc": _ticket_script._unix_to_iso(dep_t + 3600.0),
		"distance_km": 1200,
		"duration_minutes": 60,
		"cabin": "economy",
		"ticket_price": 100.0,
		"total_paid": 100.0,
		"is_connection_leg": false,
	}
	clock.set("unix_time", now_t)
	await ops.call("start_boarding", forged)
	await _wait_frames(2)
	ok = _check(str(app_state.get("current_airport_id")) == "pvg",
			"forged ticket (origin ORD) boarded from PVG — no origin guard") and ok
	return ok


func _ticket_from_flight(f: Dictionary, leg: int, total_paid: float) -> Dictionary:
	return {
		"flight_instance_id": f.get("flight_instance_id", ""),
		"marketing_flight_number": f.get("marketing_flight_number", ""),
		"airline_name": f.get("airline_name", ""),
		"alliance_id": f.get("alliance_id", ""),
		"origin_airport_id": f.get("origin_airport_id", ""),
		"destination_airport_id": f.get("destination_airport_id", ""),
		"origin_iata": f.get("origin_iata", ""),
		"destination_iata": f.get("destination_iata", ""),
		"scheduled_departure_utc": f.get("scheduled_departure_utc", ""),
		"scheduled_arrival_utc": f.get("scheduled_arrival_utc", ""),
		"distance_km": f.get("distance_km", 0),
		"duration_minutes": f.get("duration_minutes", 0),
		"stops": int(f.get("stops", 0)),
		"cabin": "economy",
		"ticket_price": total_paid,
		"total_paid": total_paid,
		"is_connection_leg": true,
		"connection_leg": leg,
		"connection_final_dest": f.get("destination_iata", ""),
		"mct_minutes": 0,
	}


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish(ok: bool = false) -> void:
	if ok and _errors.is_empty():
		print("SMOKE_CONNECTION_CONTRACT_OK")
		quit(0)
	else:
		print("SMOKE_CONNECTION_CONTRACT_FAIL")
		for e in _errors:
			printerr("  - ", e)
		quit(1)
