extends SceneTree
## Headless collector-mode regression — the automated equivalent of
## "新游戏选收藏家 → 发现商品/逛城 → 打开收藏面板 → 校验三行进度（商品/城市/成就）".
## Covers: collector game_mode state, AppState.mark_product_discovered /
## visited tracking, and CollectorPanel.refresh()/_build() without script
## errors, including the completion banner path (unlocked = total).
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeCollector.gd

var _errors: PackedStringArray = []
var data: Node = null
var app_state: Node = null
var ach_system: Node = null
var i18n: Node = null


func _initialize() -> void:
	data = root.get_node_or_null("DataService") as Node
	app_state = root.get_node_or_null("AppState") as Node
	ach_system = root.get_node_or_null("AchievementSystem") as Node
	i18n = root.get_node_or_null("I18nService") as Node
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
	_check(ach_system != null, "AchievementSystem missing")
	_check(i18n != null, "I18nService missing")
	if data == null or app_state == null or ach_system == null or i18n == null:
		_finish()

	# ── start a collector-mode new game at PVG ──
	app_state.call("reset_new_game", "pvg", "collector")
	ok = _check(str(app_state.get("game_mode")) == "collector", "game_mode != collector") and ok

	# Collect totals must be non-empty (products / cities / collect achievements).
	var products_total := int(data.get("products_by_id").size())
	var cities_total := int(data.get("cities_by_id").size())
	ok = _check(products_total > 0, "no products in data") and ok
	ok = _check(cities_total > 0, "no cities in data") and ok
	var ach_total := 0
	for ach_v in ach_system.get("definitions"):
		var ach: Dictionary = ach_v
		if str(ach.get("category", "")) == "collect":
			ach_total += 1
	ok = _check(ach_total > 0, "no collect-category achievements defined") and ok

	# ── seed collection state the same way real play does ──
	var origin_city := app_state.call("current_city_id") as String
	var first_pid: String = ""
	var local_products: Array = data.call("products_for_city", origin_city)
	if not local_products.is_empty():
		first_pid = str(local_products.front().get("product_id", ""))
	ok = _check(first_pid != "", "no product discoverable at PVG") and ok
	app_state.call("mark_product_discovered", first_pid)
	var discovered: Dictionary = (app_state.get("stats") as Dictionary).get("products_discovered", {})
	ok = _check(discovered.size() >= 1, "products_discovered empty after seeding") and ok
	var visited: Dictionary = app_state.get("visited_cities")
	ok = _check(visited.size() >= 1, "visited_cities empty after new game") and ok

	# ── instantiate the panel, refresh, and drive the build twice (idempotent) ──
	var panel_script: GDScript = load("res://scripts/ui/CollectorPanel.gd") as GDScript
	ok = _check(panel_script != null, "CollectorPanel.gd failed to load") and ok
	if panel_script == null:
		_finish()
	var panel := panel_script.new() as Control
	root.add_child(panel)
	await _wait_frames(2)

	panel.call("refresh")
	await _wait_frames(2)
	ok = _check(bool(panel.get("visible")), "collector panel not visible after refresh") and ok
	ok = _check(panel.get_child_count() >= 1, "collector panel has no children after build") and ok
	ok = _check(_count_progress_bars(panel) >= 3, "collector panel missing 3 progress rows") and ok

	panel.call("refresh")
	await _wait_frames(2)
	ok = _check(panel.get_child_count() >= 1, "collector panel rebuild left no children") and ok

	# ── completion banner path: unlock every collect achievement ──
	var unlocked_ach: Dictionary = app_state.get("unlocked_achievements")
	for ach_v in ach_system.get("definitions"):
		var ach: Dictionary = ach_v
		if str(ach.get("category", "")) == "collect":
			unlocked_ach[str(ach.get("id", ""))] = true
	panel.call("refresh")
	await _wait_frames(2)
	ok = _check(_has_complete_banner(panel), "collector completion banner missing when all unlocked") and ok

	panel.queue_free()
	_finish(ok)


func _count_progress_bars(panel: Control) -> int:
	var n := 0
	for c in panel.get_children():
		n += _count_progress_bars_rec(c)
	return n


func _count_progress_bars_rec(node: Node) -> int:
	var n := 0
	if node is ProgressBar:
		n += 1
	for c in node.get_children():
		n += _count_progress_bars_rec(c)
	return n


func _has_complete_banner(panel: Control) -> bool:
	for c in panel.get_children():
		if _find_label_text(c, str(i18n.call("t", "ui.collector.complete"))):
			return true
	return false


func _find_label_text(node: Node, text: String) -> bool:
	if node is Label and str((node as Label).text) == text:
		return true
	for c in node.get_children():
		if _find_label_text(c, text):
			return true
	return false


func _wait_frames(n: int) -> void:
	for i in n:
		await process_frame


func _finish(ok: bool = false) -> void:
	if ok and _errors.is_empty():
		print("SMOKE_COLLECTOR_OK")
		quit(0)
	else:
		print("SMOKE_COLLECTOR_FAIL")
		for e in _errors:
			printerr("  - ", e)
		quit(1)
