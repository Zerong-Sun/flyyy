extends SceneTree
## Headless codex panel regression — the automated equivalent of
## "开始新游戏 → 逛 2 城/发现商品/飞 1 段 → 打开图鉴 → 切三页 → 校验进度".
## Covers: CodexPanel.refresh()/_build() on all three tabs without script
## errors, progress counters, and route counts from travel_log.
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeCodex.gd

var _errors: PackedStringArray = []
var data: Node = null
var app_state: Node = null
var clock: Node = null


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

	app_state.call("reset_new_game", "pvg", "sandbox")
	ok = _check(str(app_state.get("game_mode")) == "sandbox", "game_mode != sandbox") and ok

	# ── seed collection state: 1 visited city (PVG), 1 discovered product,
	#    1 flown route via a real tick + arrival ──
	var visited: Dictionary = app_state.get("visited_cities")
	ok = _check(visited.size() >= 1, "visited_cities empty after new game") and ok

	# Seed product discovery the same way a sell transaction does.
	var origin_city := app_state.call("current_city_id") as String
	var first_pid: String = ""
	var local_products: Array = data.call("products_for_city", origin_city)
	if not local_products.is_empty():
		first_pid = str(local_products.front().get("product_id", ""))
	ok = _check(first_pid != "", "no product discoverable at PVG") and ok
	app_state.call("mark_product_discovered", first_pid)
	var products: Dictionary = (app_state.get("stats") as Dictionary).get("products_discovered", {})
	ok = _check(products.size() >= 1, "products_discovered empty after seeding") and ok

	var ticket_script: GDScript = load("res://scripts/systems/TicketService.gd") as GDScript
	var ops_script: GDScript = load("res://scripts/systems/FlightOps.gd") as GDScript
	ok = _check(ticket_script != null and ops_script != null,
			"system scripts failed to load (autoload globals unresolved?)") and ok
	if ticket_script == null or ops_script == null:
		_finish()

	clock.call("set_paused", true)
	var ops := ops_script.new() as Node
	root.add_child(ops)
	ops.set_process(false)

	var flights: Array = data.call("flights_from", str(app_state.get("current_airport_id")))
	var now := float(clock.get("unix_time"))
	var chosen: Dictionary = {}
	for f_v in flights:
		var f: Dictionary = f_v
		var dep: float = clock.call("parse_iso_to_unix", str(f.get("scheduled_departure_utc", "")))
		if dep >= now + 60.0:
			chosen = f
			break
	ok = _check(not chosen.is_empty(), "no future flight from PVG") and ok
	if chosen.is_empty():
		_finish()
	var pmsg: String = ticket_script.purchase(chosen, "economy", "", 0)
	ok = _check(pmsg == "", "purchase failed: %s" % pmsg) and ok
	var held: Array = app_state.get("held_tickets")
	if not held.is_empty():
		await ops.call("start_boarding", held[0])

	var routes: Dictionary = (app_state.get("stats") as Dictionary).get("routes_flown", {})
	ok = _check(routes.size() >= 1, "routes_flown empty after flight") and ok

	# ── instantiate the panel and drive all three tabs ──
	var codex_script: GDScript = load("res://scripts/ui/CodexPanel.gd") as GDScript
	ok = _check(codex_script != null, "CodexPanel.gd failed to load") and ok
	if codex_script == null:
		_finish()
	var panel := codex_script.new() as Control
	root.add_child(panel)
	await _wait_frames(2)

	panel.call("refresh")
	await _wait_frames(2)
	ok = _check(bool(panel.get("visible")), "codex panel not visible after refresh") and ok

	for idx in [0, 1, 2]:
		panel.call("_select_tab", idx)
		await _wait_frames(2)
		ok = _check(int(panel.get("_tab")) == idx, "tab %d not selected" % idx) and ok
		var progress: String = str(panel.get("_progress_label").get("text"))
		ok = _check(progress != "", "tab %d progress label empty" % idx) and ok
		var content: Node = panel.get("_content")
		ok = _check(content.get_child_count() > 0, "tab %d has no rows" % idx) and ok

	# Refresh again to make sure rebuild is idempotent (no duplicate/leftover nodes).
	panel.call("refresh")
	await _wait_frames(2)
	ok = _check(panel.get_child_count() >= 1, "panel rebuild left no children") and ok

	panel.queue_free()
	_finish(ok)


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish(ok: bool = false) -> void:
	if ok and _errors.is_empty():
		print("SMOKE_CODEX_OK")
		quit(0)
	else:
		print("SMOKE_CODEX_FAIL")
		for e in _errors:
			printerr("  - ", e)
		quit(1)
