extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
func _run() -> void:
	if not "flyyy-godot-" in OS.get_user_data_dir():
		push_error("SmokeUpgrade requires tools/test_godot.py isolated saves")
		quit(1)
		return
	var state: Node = root.get_node("AppState")
	var clock: Node = root.get_node("GameClock")
	var saves: Node = root.get_node("SaveSystem")
	var data: Node = root.get_node("DataService")
	if "--verify-reopen" in OS.get_cmdline_user_args():
		check(saves.load_game(), "restore in a new engine process")
		check(state.current_airport_id == "ist" and state.inventory.size() == 1, "reopened location and inventory")
		check(state.realized_net() == 410, "reopened accounting")
		print("REOPEN_CHECK: ", failures)
		quit(0 if failures.is_empty() else 1)
		return
	state.reset_new_game("ist")
	clock.set_paused(true)
	state.save_id = "upgrade-regression"
	var economy: GDScript = load("res://scripts/systems/EconomySystem.gd")
	var inventory: GDScript = load("res://scripts/systems/InventorySystem.gd")
	var planner: GDScript = load("res://scripts/systems/TradePlanner.gd")
	check(planner != null, "planner must compile")
	var plans: Array = planner.recommendations(3)
	check(not plans.is_empty(), "starter route plans exist")
	if not plans.is_empty():
		check(plans[0].net > 0, "a profitable starter plan exists")
	for plan in plans:
		check(absf(plan.net - (plan.revenue - plan.purchase - plan.fare)) < 0.01, "route accounting")
	var products: Array = data.market_product_ids("istanbul")
	for pid in products:
		check(economy.sell_price("istanbul", pid, 1.0) <= economy.buy_price("istanbul", pid) * 0.95 + 0.001, "same city spread")
	var pid: String = str(products[0])
	var result: String = inventory.buy(pid, 1, false)
	check(result == "", "buy succeeds: " + result)
	state.record_travel_expense(300)
	state.log_sell_transaction("istanbul", pid, 1, 500, 100, clock.unix_time)
	state.log_sell_transaction("istanbul", pid, 1, 200, 100, clock.unix_time)
	check(state.realized_net() == 200, "partial sales charge travel once")
	state.record_travel_expense(-210)
	check(state.realized_net() == 410, "refund offsets expenses")
	var original: Dictionary = state.to_dict()
	check(not saves.validate(original).is_empty(), "valid state accepted")
	var broken := original.duplicate(true)
	broken.inventory = [null]
	check(saves.validate(broken).is_empty(), "null inventory rejected")
	broken = original.duplicate(true)
	broken.cash_usd = "oops"
	check(saves.validate(broken).is_empty(), "string cash rejected")
	broken = original.duplicate(true)
	broken.inventory = [{"product_id": "missing", "qty": 1, "unit_cost": 1, "purchased_unix": 0}]
	check(saves.validate(broken).is_empty(), "unknown inventory rejected")
	check(saves.save_game(), "first atomic save")
	var cash: float = state.cash_usd
	state.cash_usd += 123
	check(saves.save_game(), "second save creates recovery copy")
	state.reset_new_game("pvg")
	check(saves.load_game(), "reload saved progress")
	check(state.current_airport_id == "ist" and state.cash_usd == cash + 123, "cash and location restored")
	check(state.realized_net() == 410, "ledger restored")
	var file := FileAccess.open("user://save_demo.json", FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	check(saves.load_game(), "corrupt primary falls back")
	check(state.cash_usd == cash, "last-known-good copy used")
	print("SmokeUpgrade checks complete: ", failures)
	quit(0 if failures.is_empty() else 1)
