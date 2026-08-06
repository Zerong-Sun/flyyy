extends SceneTree
## Headless 30-day challenge lifecycle regression — the automated equivalent of
## "开 30日挑战 → 跑 3 段航班积累指标 → 快进到截止 → 结算 → 重启复位".
## Covers: mode state, ChallengeSystem start/deadline/settlement, the eight
## PRD §6.2 metrics + score/grade, and restart reset.
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeChallenge.gd

var _errors: PackedStringArray = []
var data: Node = null
var app_state: Node = null
var clock: Node = null
var challenge: Node = null

# Loaded lazily inside _run: the system scripts resolve autoload singletons as
# globals, which are only registered after the autoloads are added to the tree.
var _ticket_script: GDScript


func _initialize() -> void:
	data = root.get_node_or_null("DataService") as Node
	app_state = root.get_node_or_null("AppState") as Node
	clock = root.get_node_or_null("GameClock") as Node
	challenge = root.get_node_or_null("ChallengeSystem") as Node
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
	_check(challenge != null, "ChallengeSystem missing")
	if data == null or app_state == null or clock == null or challenge == null:
		_finish()

	_ticket_script = load("res://scripts/systems/TicketService.gd") as GDScript
	var ops_script: GDScript = load("res://scripts/systems/FlightOps.gd") as GDScript
	ok = _check(_ticket_script != null and ops_script != null,
			"system scripts failed to load (autoload globals unresolved?)") and ok
	if _ticket_script == null or ops_script == null:
		_finish()

	# ── start a fresh 30-day challenge at PVG hub ──
	app_state.call("reset_new_game", "pvg", "challenge")
	ok = _check(str(app_state.get("game_mode")) == "challenge", "game_mode != challenge") and ok
	ok = _check(bool(challenge.call("is_active")), "challenge not active after start") and ok
	ok = _check(float(app_state.get("cash_usd")) > 0.0, "cash not initialized") and ok

	# Freeze the world clock so flight selection stays deterministic.
	clock.call("set_paused", true)

	var ops := ops_script.new() as Node
	root.add_child(ops)
	ops.set_process(false)

	# ═══ PART A: run up to 8 legs until 3 successful arrivals (seeded
	# cancellations refund without moving, so keep trying) ═══
	var attempts := 0
	while attempts < 8:
		attempts += 1
		if float((app_state.get("stats") as Dictionary).get("total_flight_segments", 0)) >= 3.0:
			break
		var origin_id: String = str(app_state.get("current_airport_id"))
		var flights: Array = data.call("flights_from", origin_id)
		var now := float(clock.get("unix_time"))
		var chosen: Dictionary = {}
		for f_v in flights:
			var f: Dictionary = f_v
			var dep: float = clock.call("parse_iso_to_unix", str(f.get("scheduled_departure_utc", "")))
			if dep >= now + 60.0:
				chosen = f
				break
		ok = _check(not chosen.is_empty(), "attempt %d: no future flight from %s" % [attempts, origin_id]) and ok
		if chosen.is_empty():
			break
		var pmsg: String = _ticket_script.purchase(chosen, "economy", "", 0)
		ok = _check(pmsg == "", "attempt %d purchase failed: %s" % [attempts, pmsg]) and ok
		var held: Array = app_state.get("held_tickets")
		ok = _check(held.size() == 1, "attempt %d: expected 1 held ticket" % attempts) and ok
		var ff := ops.call("fast_forward_to_departure") as String
		ok = _check(ff == "", "attempt %d fast_forward: %s" % [attempts, ff]) and ok
		if not held.is_empty():
			await ops.call("start_boarding", held[0])

	ok = _check(float((app_state.get("stats") as Dictionary).get("total_flight_segments", 0)) >= 3.0,
			"total_flight_segments < 3") and ok
	ok = _check(float((app_state.get("stats") as Dictionary).get("total_distance_km", 0)) > 0.0,
			"total_distance_km not accumulated") and ok
	ok = _check(float((app_state.get("stats") as Dictionary).get("total_flight_hours", 0.0)) > 0.0,
			"total_flight_hours not accumulated") and ok
	ok = _check(float((app_state.get("visited_cities") as Dictionary).size()) >= 2,
			"visited_cities < 2") and ok

	# ═══ PART B: jump clock past the deadline → settlement fires ═══
	var challenge_state: Dictionary = app_state.get("challenge") as Dictionary
	var deadline: float = float(challenge_state.get("deadline_unix", 0.0))
	ok = _check(deadline > 0.0, "challenge deadline_unix missing") and ok
	clock.set("unix_time", deadline + 1.0)
	# ChallengeSystem._process is ALWAYS; give it a few frames to end the run.
	await _wait_frames(10)
	var challenge_state_after: Dictionary = app_state.get("challenge") as Dictionary
	ok = _check(bool(challenge_state_after.get("ended", false)),
			"challenge.ended not set after deadline") and ok

	var result: Dictionary = challenge_state_after.get("result", {})
	var metrics: Dictionary = challenge.call("compute_metrics") as Dictionary
	for key in ["net_worth", "visited_cities", "visited_countries", "products_discovered",
			"total_distance_km", "on_time_rate", "single_profit_max", "profit_per_hour"]:
		ok = _check(metrics.has(key), "compute_metrics missing key: %s" % key) and ok
		ok = _check(result.has(key), "settled result missing key: %s" % key) and ok
	ok = _check(metrics.has("score") and metrics.has("grade"), "metrics missing score/grade") and ok
	ok = _check(result.has("score") and result.has("grade"), "settled result missing score/grade") and ok
	ok = _check(JSON.stringify(result) == JSON.stringify(metrics),
			"settled result diverges from compute_metrics()") and ok
	var on_time: float = float(metrics.get("on_time_rate", -1.0))
	ok = _check(on_time >= 0.0 and on_time <= 1.0,
			"on_time_rate out of range: %.2f" % on_time) and ok
	var score: int = int(metrics.get("score", -1))
	ok = _check(score >= 0 and score <= 100, "score out of range: %d" % score) and ok
	ok = _check(str(metrics.get("grade", "")) in ["A", "B", "C", "D"],
			"invalid grade: %s" % str(metrics.get("grade", ""))) and ok

	# ═══ PART C: restart resets the challenge ═══
	app_state.call("reset_new_game", "pvg", "challenge")
	ok = _check(bool(challenge.call("is_active")), "challenge not active after restart") and ok
	var challenge_state_restart: Dictionary = app_state.get("challenge") as Dictionary
	ok = _check(not bool(challenge_state_restart.get("ended", false)),
			"challenge.ended not reset after restart") and ok
	ok = _check(absf(float(app_state.get("cash_usd")) - 50000.0) < 1.0,
			"cash not reset to starting value after restart") and ok

	_finish(ok)


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish(ok: bool = false) -> void:
	if ok and _errors.is_empty():
		print("SMOKE_CHALLENGE_OK")
		quit(0)
	else:
		print("SMOKE_CHALLENGE_FAIL")
		for e in _errors:
			printerr("  - ", e)
		quit(1)
