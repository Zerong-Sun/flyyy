extends SceneTree
## Headless reputation / unlock regression.
## Verifies level thresholds, has_unlock progression, and the Lv5 baggage
## +10kg wiring (AppState.personal_baggage_limit_kg). The MainHUD purchase
## discounts are guarded by tests/etl/test_reputation.py source checks.
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeReputation.gd

var _errors: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_errors.append(msg)


func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond


func _run() -> void:
	var app := root.get_node_or_null("AppState") as Node
	var rep := root.get_node_or_null("ReputationSystem") as Node
	var ok := _check(app != null, "AppState missing")
	ok = _check(rep != null, "ReputationSystem missing") and ok
	if app == null or rep == null:
		_finish()

	app.call("reset_new_game", "pvg", "sandbox")
	ok = _check(int(app.get("reputation_points")) == 5,
			"new game should start at +5 (start-city visit), got %d" % app.get("reputation_points")) and ok
	ok = _check(int(app.get("level")) == 1, "start level != 1") and ok
	var base_limit := float(app.call("personal_baggage_limit_kg"))
	ok = _check((rep.call("active_unlocks") as Array).is_empty(), "Lv1 should have no active unlocks") and ok

	# Lv1: cold baggage tier charges full price in the actual purchase path.
	var ticket_script: GDScript = load("res://scripts/systems/TicketService.gd") as GDScript
	ok = _check(ticket_script != null, "TicketService failed to load") and ok
	if ticket_script == null:
		_finish()
	var cold_cost1: Dictionary = ticket_script.call("_extra_cost", "cold", 0)
	ok = _check(absf(float(cold_cost1.extra_cost) - 120.0) < 0.001,
			"Lv1 cold tier should cost 120, got %s" % str(cold_cost1.extra_cost)) and ok

	rep.call("add_points", 75)  # 5 + 75 = 80 -> Lv3
	ok = _check(int(app.get("level")) == 3, "expected Lv3 at 80xp, got %d" % app.get("level")) and ok
	var unlocks3: Array = rep.call("active_unlocks")
	ok = _check(unlocks3.size() == 2, "Lv3 should have 2 active unlocks, got %d" % unlocks3.size()) and ok
	ok = _check(bool(rep.call("has_unlock", "unlock_lv2_cargo")), "Lv3 missing lv2 unlock") and ok
	ok = _check(bool(rep.call("has_unlock", "unlock_lv3_cold_discount")), "Lv3 missing lv3 unlock") and ok
	ok = _check(not bool(rep.call("has_unlock", "unlock_lv5_baggage_plus10")), "Lv3 should not have lv5 unlock") and ok
	# Lv3: cold tier must be charged 20% off in the real charge path, not
	# only in the UI label.
	var cold_cost3: Dictionary = ticket_script.call("_extra_cost", "cold", 0)
	ok = _check(absf(float(cold_cost3.extra_cost) - 96.0) < 0.001,
			"Lv3 cold tier should cost 96 (120*0.8), got %s" % str(cold_cost3.extra_cost)) and ok
	var warm_cost3: Dictionary = ticket_script.call("_extra_cost", "standard", 0)
	ok = _check(absf(float(warm_cost3.extra_cost) - 320.0) < 0.001,
			"non-cold tier must stay full price at Lv3, got %s" % str(warm_cost3.extra_cost)) and ok

	rep.call("add_points", 200)  # 5 + 275 = 280 -> Lv5
	ok = _check(int(app.get("level")) == 5, "expected Lv5 at 280xp, got %d" % app.get("level")) and ok
	var limit5 := float(app.call("personal_baggage_limit_kg"))
	ok = _check(absf(limit5 - base_limit - 10.0) < 0.001,
			"Lv5 baggage +10kg not applied (%f -> %f)" % [base_limit, limit5]) and ok

	rep.call("add_points", 500)  # beyond max threshold -> Lv6
	ok = _check(int(app.get("level")) == 6, "expected Lv6 at >=460xp, got %d" % app.get("level")) and ok
	ok = _check(int(rep.call("xp_to_next_level")) == 0, "max level xp_to_next_level != 0") and ok

	_finish(ok)


func _finish(ok: bool = false) -> void:
	if ok and _errors.is_empty():
		print("SMOKE_REPUTATION_OK")
		quit(0)
	else:
		print("SMOKE_REPUTATION_FAIL")
		for e in _errors:
			printerr("  - ", e)
		quit(1)
