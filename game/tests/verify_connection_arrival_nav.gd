extends Node
## Headless reproduction for: 联程机票到达第二个目的地后，底部标签栏不再显示。
##
## Scenario:
##   1. 购买两段联程机票；
##   2. 第一段起飞 → 到达中转枢纽；
##   3. 中转停留期间打开「航班」工作台（_dock_panel_work 会隐藏底部导航栏）；
##   4. 第二段起飞 → 到达第二目的地。
##
## 断言：第二段到达后底部导航栏必须恢复可见、面板必须关闭。
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/verify_connection_arrival_nav.tscn

var _failures: PackedStringArray = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
		print("FAIL: ", msg)


func _ready() -> void:
	await _frames(5)

	if DataService.airports.is_empty():
		_check(false, "no airports loaded")
		_finish()
		return

	var flight_search: GDScript = load("res://scripts/systems/FlightSearch.gd") as GDScript
	var ticket_svc: GDScript = load("res://scripts/systems/TicketService.gd") as GDScript

	# Pick an airport that actually has connection (transfer) itineraries.
	var target: Dictionary = {}
	var scanned := 0
	for a in DataService.airports:
		scanned += 1
		if not (flight_search.search_connections(str(a.iata)) as Array).is_empty():
			target = a
			break
		if scanned >= 40:
			break
	_check(not target.is_empty(), "no airport with transfer connections found")
	if target.is_empty():
		_finish()
		return

	AppState.reset_new_game(target.airport_id, "sandbox")
	await _frames(3)

	var hud: Control = get_node("../Main/UI")
	var ops: Node = get_node("../Main/FlightOps")
	_check(hud != null and ops != null, "main scene nodes missing (UI/FlightOps)")
	if hud == null or ops == null:
		_finish()
		return
	ops.set_process(false)  # board manually; keep the clock autonomous

	var conns: Array = flight_search.search_connections(str(target.iata))
	var conn: Dictionary = {}
	for c_v in conns:
		var c: Dictionary = c_v
		if int(c.get("mct_minutes", 0)) > 0:
			conn = c
			break
	_check(not conn.is_empty(), "no connection with mct_minutes > 0")
	if conn.is_empty():
		_finish()
		return

	var err: String = ticket_svc.purchase_connection(conn, "economy", "", 0)
	_check(err == "", "purchase_connection failed: %s" % err)
	_check(AppState.held_tickets.size() == 2, "expected 2 held connection legs, got %d" % AppState.held_tickets.size())
	if err != "" or AppState.held_tickets.size() != 2:
		_finish()
		return

	# ── Leg 1: board → arrive at hub ──
	print("INFO: boarding leg 1 (%s→%s)..." % [
		str(AppState.held_tickets[0].get("origin_iata", "")),
		str(AppState.held_tickets[0].get("destination_iata", "")),
	])
	await ops.call("start_boarding", AppState.held_tickets[0])
	await _frames(3)
	_check(bool(hud.get("_bottom_nav").visible), "bottom nav hidden right after leg-1 (hub) arrival")
	_check(AppState.held_tickets.size() == 1, "expected 1 remaining leg after hub, got %d" % AppState.held_tickets.size())
	if AppState.held_tickets.size() != 1:
		_finish()
		return

	# ── During the hub layover, open the flights workbench (docks panel, hides nav) ──
	hud.call("_show_flights")
	await _frames(5)
	_check(not bool(hud.get("_bottom_nav").visible), "nav should be hidden while the workbench is docked")
	_check(bool(hud.get("_panel_host").visible), "flights panel should be open/docked before leg-2 boarding")

	# ── Leg 2: board → arrive at the second destination ──
	print("INFO: boarding leg 2 (%s→%s)..." % [
		str(AppState.held_tickets[0].get("origin_iata", "")),
		str(AppState.held_tickets[0].get("destination_iata", "")),
	])
	await ops.call("start_boarding", AppState.held_tickets[0])
	await _frames(3)

	_check(AppState.held_tickets.is_empty(), "held_tickets should be empty after final arrival")
	_check(bool(hud.get("_bottom_nav").visible), "BUG: bottom nav still hidden after leg-2 arrival (联程第二目的地)")
	_check(not bool(hud.get("_panel_host").visible), "panel must be closed after arrival")

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_CONNECTION_NAV_OK")
		get_tree().quit(0)
	else:
		print("VERIFY_CONNECTION_NAV_FAIL (%d)" % _failures.size())
		for f in _failures:
			printerr("  - ", f)
		get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
