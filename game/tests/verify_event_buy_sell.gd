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
		_check(hud.get("_active_event_popup") == sell_popup,
			"sell result bypassed the serialized event queue")
		_check(GameClock.paused, "sell result card must pause game time")
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
		# Real click on the close button must fire event_confirmed and close the
		# card (regression: hiding the default OK left custom buttons dead).
		var signal_state := {"confirmed": false}
		sell_popup.event_confirmed.connect(func(_r): signal_state.confirmed = true)
		for b_v in sell_popup.find_children("*", "Button", true, false):
			var b: Button = b_v
			if b.visible:
				b.emit_signal("pressed")
				break
		await _frames(3)
		_check(bool(signal_state.confirmed), "clicking sell-card close button did not fire event_confirmed")
		_check(not is_instance_valid(sell_popup) or not sell_popup.visible,
			"sell result card did not close after accept")
	# A discovery card may legitimately follow the sale, but it must appear only
	# after the result card and the whole chain must restore the clock afterward.
	var post_sell_popup: PopupEvent = hud.get("_active_event_popup") as PopupEvent
	if post_sell_popup != null:
		_check(post_sell_popup.title.find("意外发现") >= 0,
			"unexpected popup followed the sell result: %s" % post_sell_popup.title)
		_press_button(post_sell_popup, "暂不处理")
		await _frames(4)
	_check(hud.get("_active_event_popup") == null, "sell-result event chain did not drain")
	_check(not GameClock.paused, "sell-result event chain did not restore the clock")

	# ── Scenario 3: real button click must accept an event popup ──
	var accept_state := {"accepted": false, "cancelled": false}
	var accept_popup: PopupEvent = load("res://scenes/PopupEvent.tscn").instantiate() as PopupEvent
	accept_popup.event_confirmed.connect(func(_r): accept_state.accepted = true)
	accept_popup.event_cancelled.connect(func(_r): accept_state.cancelled = true)
	hud.add_child(accept_popup)
	accept_popup.show_event("arrival_discount", {"product_name": "测试商品", "discount_pct": 25})
	await _frames(2)
	_check(accept_popup.visible, "scenario 3 popup did not open")
	var accept_btn: Button = null
	for b_v in accept_popup.find_children("*", "Button", true, false):
		var b: Button = b_v
		if b.visible and b.text == "趁机买入":
			accept_btn = b
			break
	_check(accept_btn != null, "scenario 3 accept button not found")
	if accept_btn != null:
		accept_btn.emit_signal("pressed")
		await _frames(2)
		_check(bool(accept_state.accepted), "clicking 趁机买入 did not fire event_confirmed (BUG: 事件无法接受)")
		_check(not bool(accept_state.cancelled), "clicking accept must not cancel")
		_check(not accept_popup.visible, "accepting must close the popup")
	accept_popup.queue_free()

	# Cancel path must still work independently on a fresh popup.
	var cancel_popup: PopupEvent = load("res://scenes/PopupEvent.tscn").instantiate() as PopupEvent
	var cancel_state := {"accepted": false, "cancelled": false}
	cancel_popup.event_confirmed.connect(func(_r): cancel_state.accepted = true)
	cancel_popup.event_cancelled.connect(func(_r): cancel_state.cancelled = true)
	hud.add_child(cancel_popup)
	cancel_popup.show_event("arrival_discount", {"product_name": "测试商品", "discount_pct": 25})
	await _frames(2)
	var cancel_btn: Button = null
	for b_v in cancel_popup.find_children("*", "Button", true, false):
		var b: Button = b_v
		if b.visible and b.text == "不了谢谢":
			cancel_btn = b
			break
	_check(cancel_btn != null, "scenario 3 cancel button not found")
	if cancel_btn != null:
		cancel_btn.emit_signal("pressed")
		await _frames(2)
		_check(bool(cancel_state.cancelled), "clicking 不了谢谢 did not fire event_cancelled")
		_check(not bool(cancel_state.accepted), "cancel fired accept (BUG: cancel must stay separate)")
		_check(not cancel_popup.visible, "cancelling must close the popup")
	cancel_popup.queue_free()

	# ── Scenario 3b: accidental-premium callback accepts the emitted result ──
	hud.call("_on_arrival_discount_accepted", {}, product_id, discount_pct)
	await _frames(4)
	var premium_index := -1
	for i in AppState.inventory.size():
		if str((AppState.inventory[i] as Dictionary).get("product_id", "")) == product_id:
			premium_index = i
			break
	_check(premium_index >= 0, "could not prepare inventory for premium event")
	if premium_index >= 0:
		var premium_item: Dictionary = AppState.inventory[premium_index]
		var premium_qty := 1
		var premium_unit := _Economy.sell_price(city, product_id, _Economy.current_quality(premium_item))
		var original_revenue := premium_unit * premium_qty
		var premium_revenue := original_revenue * 1.25
		var cash_before_premium := AppState.cash_usd
		var qty_before_premium := _inventory_qty(product_id)
		hud.call("_enqueue_event_popup", "accidental_premium", {
			"bonus_pct": 25,
			"original": int(original_revenue),
			"premium": int(premium_revenue),
		}, Callable(hud, "_on_premium_accepted").bind(
			premium_index, premium_qty, 25, original_revenue, premium_revenue),
		Callable(hud, "_on_premium_declined").bind(premium_index, premium_qty))
		await _frames(3)
		var premium_popup: PopupEvent = hud.get("_active_event_popup") as PopupEvent
		_check(premium_popup != null and premium_popup.visible, "premium event did not open")
		if premium_popup != null:
			_press_button(premium_popup, "成交！")
		await _frames(5)
		_check(_inventory_qty(product_id) == qty_before_premium - 1, "premium accept did not sell inventory")
		_check(absf((AppState.cash_usd - cash_before_premium) - premium_revenue) < 0.02,
			"premium accept cash delta does not include bonus")
		var premium_followup: PopupEvent = hud.get("_active_event_popup") as PopupEvent
		_check(premium_followup != premium_popup,
			"premium event remained active after accept")
		_check(premium_followup != null,
			"premium transaction did not serialize its sell-result follow-up")
		# Close the sell result card produced by the premium transaction.
		for child in hud.get_children():
			if child is PopupEvent and child.visible:
				_press_button(child, I18nService.t("sell_result_continue"))
				break
		await _frames(4)

	# ── Scenario 4: queued event cards must never overlap ──
	var queue_state := {"first": false, "second_cancelled": false}
	var news_data := {
		"title": "📰 测试新闻",
		"body": "第一张卡片",
		"impact": "采购价 +10%",
		"accept_text": "查看市场影响",
		"close_text": "关闭新闻",
	}
	hud.set("_transition_running", true)
	hud.call("_enqueue_event_popup", "news", news_data,
		func(_r): queue_state.first = true, func(_r): pass)
	hud.call("_enqueue_event_popup", "news", news_data.merged({"body": "第二张卡片"}, true),
		func(_r): pass, func(_r): queue_state.second_cancelled = true)
	await _frames(3)
	_check(hud.get("_active_event_popup") == null, "event popup opened over flight transition")
	_check((hud.get("_event_queue") as Array).size() == 2, "transition should preserve queued events")
	hud.set("_transition_running", false)
	hud.call("_show_next_event_popup")
	await _frames(4)
	var first_queued: PopupEvent = hud.get("_active_event_popup") as PopupEvent
	_check(first_queued != null and first_queued.visible, "first queued event did not open")
	_check(GameClock.paused, "visible event popup must pause game time")
	_check((hud.get("_event_queue") as Array).size() == 1, "second event was not held in queue")
	_check(_visible_popup_count(hud) == 1, "queued events overlapped instead of showing one at a time")
	if first_queued != null:
		_press_button(first_queued, "查看市场影响")
	await _frames(5)
	_check(bool(queue_state.first), "first queued event callback did not run")
	var second_queued: PopupEvent = hud.get("_active_event_popup") as PopupEvent
	_check(second_queued != null and second_queued != first_queued and second_queued.visible,
		"second queued event did not open after the first resolved")
	_check(_visible_popup_count(hud) == 1, "resolving first event left multiple visible popups")
	if second_queued != null:
		_press_button(second_queued, "关闭新闻")
	await _frames(5)
	_check(bool(queue_state.second_cancelled), "second queued event cancel callback did not run")
	_check(hud.get("_active_event_popup") == null, "event queue retained a resolved popup")
	_check((hud.get("_event_queue") as Array).is_empty(), "event queue did not drain")
	_check(not GameClock.paused, "event queue did not restore the running game clock")

	# ── Scenario 5: viewing an airport card is not visiting it; close is explicit ──
	var unvisited_id := ""
	for airport_v in DataService.airports:
		var airport: Dictionary = airport_v
		var aid := str(airport.get("airport_id", ""))
		if aid != AppState.current_airport_id and not AppState.visited_airports.has(aid):
			unvisited_id = aid
			break
	_check(not unvisited_id.is_empty(), "no unvisited airport available for card semantics test")
	var visited_before := AppState.visited_airports.size()
	if not unvisited_id.is_empty():
		hud.call("_on_airport_selected", unvisited_id)
		await _frames(2)
		var card_panel: PanelContainer = hud.get("_airport_card_panel") as PanelContainer
		var card: RichTextLabel = hud.get("_airport_card") as RichTextLabel
		_check(card_panel.visible, "airport card did not open on selection")
		var viewport_rect := get_viewport().get_visible_rect()
		_check(viewport_rect.encloses(card_panel.get_global_rect()), "airport card extends outside viewport")
		_check(card.text.find("查看卡片不等于抵达") < 0, "airport card still shows the removed view-vs-arrival copy")
		_check(not AppState.visited_airports.has(unvisited_id), "viewing airport card incorrectly marked it visited")
		var route_action: Button = hud.get("_airport_card_action") as Button
		_check(not route_action.disabled and route_action.text == "查找前往此地的航班",
			"unvisited airport card route action is unclear or disabled")
		var close_card: Button = null
		for button_v in card_panel.find_children("*", "Button", true, false):
			var button: Button = button_v
			if button.text == "收起卡片":
				close_card = button
				break
		_check(close_card != null, "airport card close action missing")
		if close_card != null:
			(close_card as Button).emit_signal("pressed")
		await _frames(2)
		_check(not card_panel.visible, "airport card did not close")
		_check(AppState.visited_airports.size() == visited_before, "closing card changed visit records")
		# Reopen and use the explicit route action; the card should yield to the
		# flight workbench and prefill the selected airport's IATA code.
		hud.call("_on_airport_selected", unvisited_id)
		await _frames(2)
		route_action.emit_signal("pressed")
		await _frames(5)
		var target_airport := DataService.get_airport(unvisited_id)
		var dest_query: LineEdit = hud.get("_dest_code_query") as LineEdit
		_check(bool((hud.get("_panel_host") as Control).visible), "route action did not open flight panel")
		_check(not card_panel.visible, "airport card overlaps flight workbench")
		_check(dest_query != null and dest_query.text == str(target_airport.get("iata", "")),
			"route action did not prefill destination IATA")
		_check(not AppState.visited_airports.has(unvisited_id), "route search incorrectly marked destination visited")
		hud.call("_close_panel")

	# ── Scenario 6: navigation panels keep their close action reachable ──
	await _verify_navigation_layout(hud)

	# ── Scenario 7: focused airport is centred on the camera-facing hemisphere ──
	if not unvisited_id.is_empty():
		var globe: Node3D = get_node("../Main/Globe") as Node3D
		var reduced_before := AppState.reduced_animations
		AppState.reduced_animations = true
		globe.call("focus_airport", unvisited_id)
		await _frames(2)
		var focused_airport := DataService.get_airport(unvisited_id)
		var airport_dir: Vector3 = globe.call(
			"latlon_to_vec",
			float(focused_airport.get("latitude", 0.0)),
			float(focused_airport.get("longitude", 0.0)),
			1.0
		).normalized()
		var camera: Camera3D = globe.get("camera") as Camera3D
		var camera_dir := (camera.global_position - globe.global_position).normalized()
		_check(camera_dir.dot(airport_dir) > 0.999,
			"focused airport is not centred on the camera-facing hemisphere")
		AppState.reduced_animations = reduced_before

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


func _visible_popup_count(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is PopupEvent and child.visible:
			count += 1
	return count


func _press_button(popup: PopupEvent, text: String) -> void:
	for button_v in popup.find_children("*", "Button", true, false):
		var button: Button = button_v
		if button.visible and button.text == text:
			button.emit_signal("pressed")
			return
	_check(false, "button not found: %s" % text)


func _verify_navigation_layout(hud: Control) -> void:
	for method in [
		"_show_city", "_show_market", "_show_flights", "_show_inventory",
		"_show_notes", "_show_achievements", "_show_log", "_show_attr",
		"_toggle_pause",
	]:
		hud.call(method)
		await _frames(4)
		var panel: PanelContainer = hud.get("_panel_host") as PanelContainer
		var bottom_nav: HBoxContainer = hud.get("_bottom_nav") as HBoxContainer
		_check(panel.visible, "%s did not open a panel" % method)
		_check(bottom_nav.visible,
			"%s hides the bottom navigation row" % method)
		_check(get_viewport().get_visible_rect().encloses(bottom_nav.get_global_rect()),
			"bottom navigation row extends outside viewport in %s" % method)
		var close: Button = null
		for button_v in panel.find_children("*", "Button", true, false):
			var button: Button = button_v
			if button.text == "返回地图（Esc）":
				close = button
				break
		_check(close != null and close.visible, "%s has no reachable close action" % method)
		if close != null:
			_check(panel.get_global_rect().encloses(close.get_global_rect()),
				"%s close action overflows the panel" % method)
		_check(get_viewport().get_visible_rect().encloses(panel.get_global_rect()),
			"%s panel extends outside viewport" % method)
		if method == "_toggle_pause":
			_check(not panel.find_children("*", "ScrollContainer", true, false).is_empty(),
				"settings panel is not scrollable")
		hud.call("_close_panel")
		await _frames(2)

	# Switch directly from a wide workbench to Notes. The previous child must be
	# detached before the compact panel is laid out, otherwise its minimum width
	# can push the right edge outside the viewport for one frame.
	hud.call("_show_city")
	await _frames(2)
	hud.call("_show_notes")
	await _frames(2)
	var notes_panel: PanelContainer = hud.get("_panel_host") as PanelContainer
	_check(get_viewport().get_visible_rect().encloses(notes_panel.get_global_rect()),
		"notes panel extends outside viewport after switching from a workbench")
	_check(bool(hud.get("_bottom_nav").visible), "notes panel hides the bottom navigation row")

	# Codex and hosted tabs are mutually exclusive in both directions.
	hud.call("_show_codex")
	await _frames(2)
	var codex: Control = hud.get("_codex_panel") as Control
	_check(codex != null and codex.visible, "codex did not open")
	_check(not notes_panel.visible, "codex overlaps the notes panel")
	_check(codex.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"codex blocks clicks to the persistent bottom navigation")
	hud.call("_show_notes")
	await _frames(2)
	_check(not codex.visible, "notes panel overlaps the codex")
	_check(notes_panel.visible, "notes panel did not reopen after codex")
	hud.call("_close_panel")
	await _frames(2)
