extends Node
## Headless regression for the arrival-discount (热卖/偶遇商机) popup and the sell
## result card.
##
## Scenario 1 — 热卖折扣弹出后「趁机买入」：
##   1. 直接触发 _on_arrival_discount_accepted（相当于确认热卖弹窗）；
##   2. 断言：商品立即被按折扣价买入（资金减少 25% 折扣、库存出现该商品）；
##   3. 断言：市场采购列表把该商品置顶显示。
##
## Scenario 2 — 售出结果卡片：
##   1. 调用 _show_sell_result_card 展示一笔盈利售出；
##   2. 断言：PopupEvent 已加入场景树且 visible（修复 add_child/popup_centered 顺序）。
##
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/verify_event_buy_sell.tscn

const _Economy = preload("res://scripts/systems/EconomySystem.gd")

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

	AppState.reset_new_game(DataService.airports[0].airport_id)
	await _frames(3)

	var hud: Control = get_node("../Main/UI")
	_check(hud != null, "main scene UI missing")
	if hud == null:
		_finish()
		return
	var ops: Node = get_node("../Main/FlightOps")
	if ops != null:
		ops.set_process(false)  # keep the world static while we inspect the workbench

	var city := AppState.current_city_id()
	_check(city != "", "no current city after new game")
	if city == "":
		_finish()
		return

	# ── Scenario 1: arrival discount direct buy + pin ──
	var product_id := ""
	for pid_v in DataService.market_product_ids(city):
		var pid := str(pid_v)
		var p := DataService.get_product(pid)
		var w: float = float(p.get("weight_kg", 0.1))
		if w <= 15.0 and w <= AppState.personal_baggage_limit_kg():
			product_id = pid
			break
	_check(product_id != "", "no light market product found for discount buy")
	if product_id == "":
		_finish()
		return

	var discount_pct := 25
	var full_price: float = _Economy.buy_price(city, product_id)
	var expected_cost: float = full_price * (1.0 - float(discount_pct) / 100.0)
	var cash_before: float = AppState.cash_usd
	var inv_before: int = AppState.inventory.size()

	hud.call("_on_arrival_discount_accepted", {}, product_id, discount_pct)
	await _frames(5)

	var bought := false
	for stack_v in AppState.inventory:
		var stack: Dictionary = stack_v
		if str(stack.get("product_id", "")) == product_id and int(stack.get("qty", 0)) > 0:
			bought = true
			_check(absf(float(stack.get("unit_cost", 0.0)) - expected_cost) < 0.01,
				"discount not applied: unit_cost=%.2f expected=%.2f" % [float(stack.get("unit_cost", 0.0)), expected_cost])
	_check(bought, "arrival discount accept did not buy the product (BUG: 热卖弹出后无法购买)")
	_check(AppState.inventory.size() > inv_before, "inventory did not grow after discount buy")
	var paid: float = cash_before - AppState.cash_usd
	_check(absf(paid - expected_cost) < 0.01, "cash delta %.2f != discounted price %.2f" % [paid, expected_cost])

	var buy_tree: Tree = hud.get("_market_buy_tree") as Tree
	_check(buy_tree != null, "market buy tree not built after discount buy")
	if buy_tree != null:
		var root := buy_tree.get_root()
		var first := root.get_first_child() if root != null else null
		_check(first != null and str(first.get_metadata(0)) == product_id,
			"discounted product not pinned to top of buy list (BUG: 商品没有出现在市场里)")
	_check(str(hud.get("_pinned_market_product_id")) == product_id, "pinned product id not recorded")

	# ── Scenario 2: sell the purchased item through the real sell path ──
	var cash_mid: float = AppState.cash_usd
	var qty_before_sell: int = _inventory_qty(product_id)
	_check(qty_before_sell > 0, "no stock to sell in scenario 2")
	if qty_before_sell > 0:
		hud.call("_do_sell", 0, 1)
		await _frames(3)
		_check(_inventory_qty(product_id) == qty_before_sell - 1, "sell did not reduce inventory")
		_check(AppState.cash_usd > cash_mid, "sell did not add cash")
	var popup_seen := false
	var sell_popup = null
	for child in hud.get_children():
		if child is PopupEvent and child.visible:
			popup_seen = true
			sell_popup = child
			break
	_check(popup_seen, "sell result card did not show (BUG: add_child/popup_centered order)")
	if sell_popup != null:
		var ok_btn: Button = sell_popup.get_ok_button()
		_check(ok_btn != null and not ok_btn.visible,
			"default OK button must be hidden on sell result card (BUG: duplicate OK/继续)")
		var visible_buttons := 0
		for b_v in sell_popup.find_children("*", "Button", true, false):
			var b: Button = b_v
			if b.visible:
				visible_buttons += 1
		_check(visible_buttons == 1,
			"sell result card must show exactly one visible button, got %d" % visible_buttons)

	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_EVENT_BUY_SELL_OK")
		get_tree().quit(0)
	else:
		print("VERIFY_EVENT_BUY_SELL_FAIL (%d)" % _failures.size())
		for f in _failures:
			printerr("  - ", f)
		get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _inventory_qty(product_id: String) -> int:
	var total := 0
	for stack_v in AppState.inventory:
		var stack: Dictionary = stack_v
		if str(stack.get("product_id", "")) == product_id:
			total += int(stack.get("qty", 0))
	return total
