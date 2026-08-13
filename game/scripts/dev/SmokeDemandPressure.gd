extends SceneTree
## Demand-pressure ratchet (GDLC Playtest #3): bulk sales must escalate
## pressure INSIDE the sale — unit k is priced at the pressure after k-1
## units, not all N units at the pre-sale price (a 9+ unit dump saturated
## the 0.7 cap while transacting 100% of units at full price).
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeDemandPressure.gd

var _errors: PackedStringArray = []
var data: Node = null
var app_state: Node = null
var clock: Node = null

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
	_check(app_state != null and clock != null, "autoloads missing")
	if data == null or app_state == null or clock == null:
		_finish()

	_economy_script = load("res://scripts/systems/EconomySystem.gd") as GDScript
	_inventory_script = load("res://scripts/systems/InventorySystem.gd") as GDScript
	ok = _check(_economy_script != null and _inventory_script != null,
			"system scripts failed to load") and ok
	if _economy_script == null or _inventory_script == null:
		_finish()

	# Fresh sandbox at PVG with a frozen clock (deterministic quotes).
	app_state.call("reset_new_game", "pvg")
	clock.call("set_paused", true)
	clock.set("unix_time", 1740787200.0)

	# Pick a purchasable light product so 10 units fit the 20kg economy hold.
	var city_id: String = str(app_state.call("current_city_id"))
	var pid := ""
	for p_id in data.call("market_product_ids", city_id):
		var p: Dictionary = data.call("get_product", p_id)
		var price: float = _economy_script.buy_price(city_id, p_id)
		if price > 0.0 and float(p.get("weight_kg", 1.0)) * 10.0 <= 20.0:
			pid = p_id
			break
	ok = _check(pid != "", "no purchasable light product in PVG") and ok
	if pid == "":
		_finish()

	var bmsg: String = _inventory_script.buy(pid, 10, false)
	ok = _check(bmsg == "", "buy 10 failed: %s" % bmsg) and ok
	if bmsg != "":
		_finish()
	# Fresh goods are quality 1.0; pre-sale pressure is 0 on a fresh game.
	var price_p0: float = _economy_script.sell_price(city_id, pid, 1.0)
	var res: Dictionary = _inventory_script.sell(0, 10)
	ok = _check(bool(res.get("success", false)),
			"sell failed: %s" % str(res.get("msg", ""))) and ok
	var revenue: float = float(res.get("revenue", 0.0))
	ok = _check(revenue < price_p0 * 10.0 - 0.01,
			"bulk sale not escalated in-sale: revenue %.2f == naive %.2f" %
			[revenue, price_p0 * 10.0]) and ok
	var key := "%s|%s" % [city_id, pid]
	var pressure: float = float((app_state.get("demand_pressure") as Dictionary).get(key, 0.0))
	ok = _check(absf(pressure - 0.7) < 0.001,
			"pressure after 10-sale %.3f != 0.7 (cap)" % pressure) and ok

	_finish(ok)


func _finish(ok: bool = false) -> void:
	if ok and _errors.is_empty():
		print("SMOKE_DEMAND_PRESSURE_OK")
		quit(0)
	else:
		print("SMOKE_DEMAND_PRESSURE_FAIL")
		for e in _errors:
			printerr("  - ", e)
		quit(1)
