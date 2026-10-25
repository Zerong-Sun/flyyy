extends VBoxContainer
## Compact inline controls. The expanded list scrolls without displacing the market.
signal expansion_changed
signal delivery_requested(order: Dictionary)
var _hidden_controls: Dictionary = {}
var _expanded := false
var _summary: Button
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _elapsed := 0.0
var _countdowns: Dictionary = {}

func _ready() -> void:
	_summary = Button.new()
	_summary.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_summary)
	_summary.pressed.connect(func(): _expanded = not _expanded; rebuild())
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.y = 176
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	MerchantSystem.changed.connect(_schedule_rebuild)
	MerchantSystem.refresh_offers()
	rebuild()

func _schedule_rebuild() -> void:
	call_deferred("rebuild")

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 0.5:
		_elapsed = 0
		_update_summary()
		for label in _countdowns:
			if is_instance_valid(label):
				label.text = _order_label(_countdowns[label])
				label.tooltip_text = label.text

func _update_summary() -> void:
	var d := MerchantSystem.data()
	var order: Dictionary = d.order
	var caption := MerchantSystem.text("商机", "Opportunities")
	if not order.is_empty():
		caption = "%s · %d/%d · %.1fh · +$%.0f" % [DataService.place_name(DataService.get_city(str(order.city)), "name"), order.done, order.qty, maxf(0, (float(order.deadline) - GameClock.unix_time) / 3600), float(order.bonus) - float(order.advance)]
	else:
		caption += " · " + str(d.notice) if str(d.notice) != "" else MerchantSystem.text(" · 24–72h 限时委托", " · 24–72h timed orders")
	if not d.candidates.is_empty():
		caption += MerchantSystem.text(" · 新专长可选", " · New specialty")
	_summary.text = ("▾ " if _expanded else "▸ ") + caption + (MerchantSystem.text(" · 返回交易", " · Back to trading") if _expanded else "")
	_summary.tooltip_text = caption

func _line(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	_rows.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = label_text
	row.add_child(label)
	return row

func _button(row: HBoxContainer, label: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = label
	row.add_child(b)
	b.pressed.connect(callback)

func rebuild() -> void:
	if not is_instance_valid(_rows):
		return
	_countdowns.clear()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_scroll.visible = _expanded
	# Use the same workbench space instead of pushing trading controls off screen.
	for sibling in get_parent().get_children():
		if sibling is Control and sibling.get_index() > get_index():
			if _expanded:
				if not _hidden_controls.has(sibling):
					_hidden_controls[sibling] = sibling.visible
				sibling.visible = false
			elif _hidden_controls.has(sibling):
				sibling.visible = bool(_hidden_controls[sibling])
	if not _expanded:
		_hidden_controls.clear()
	expansion_changed.emit()
	_update_summary()
	if not _expanded:
		return
	var d := MerchantSystem.data()
	var order: Dictionary = d.order
	if not order.is_empty():
		var row := _order_line(order)
		_button(row, MerchantSystem.text("去交货", "Deliver"), func(): delivery_requested.emit(order))
		_button(row, MerchantSystem.text("结束", "End"), func(): MerchantSystem.abandon())
	else:
		var available := 0
		for offer_v in d.offers:
			var offer: Dictionary = offer_v
			if GameClock.unix_time >= float(offer.deadline):
				continue
			available += 1
			var row := _order_line(offer)
			_button(row, MerchantSystem.text("接单", "Accept"), func(): MerchantSystem.accept(str(offer.id)))
		if available == 0:
			_line(MerchantSystem.text("暂无可接委托，下次抵达或次日刷新", "No offers; check after arrival or next day"))
	_line(MerchantSystem.text("当前：", "Active: ") + MerchantSystem.ability_label(d.active))
	for a_v in d.candidates:
		var a: Dictionary = a_v
		var row := _line(MerchantSystem.ability_label(a))
		_button(row, MerchantSystem.text("替换" if not d.active.is_empty() else "启用", "Replace" if not d.active.is_empty() else "Equip"), func(): MerchantSystem.equip(str(a.id)))
		_button(row, "×", func(): MerchantSystem.dismiss_candidate(str(a.id)))
	var near_key := ""
	var near_progress := 0.0
	var near_target := 0.0
	for key_v in d.sales:
		var key := str(key_v)
		var threshold := float(MerchantSystem.rules().product_milestone if key.begins_with("product:") else MerchantSystem.rules().category_milestone)
		var target: float = (floor(float(d.sales[key]) / threshold) + 1) * threshold
		if float(d.sales[key]) / target > near_progress:
			near_key = key
			near_progress = float(d.sales[key]) / target
			near_target = target
	if near_key != "":
		var name := near_key.trim_prefix("category:")
		if near_key.begins_with("product:"):
			name = DataService.place_name(DataService.get_product(near_key.trim_prefix("product:")), "name")
		_line("%s · $%.0f / $%.0f" % [name, d.sales[near_key], near_target])
	_line(MerchantSystem.text("飞行专长", "Flight specialty") + " · %d / %d" % [d.flights, (int(d.flights) / int(MerchantSystem.rules().flight_milestone) + 1) * int(MerchantSystem.rules().flight_milestone)])

func _order_label(o: Dictionary) -> String:
	var city := DataService.place_name(DataService.get_city(str(o.city)), "name")
	var product := DataService.place_name(DataService.get_product(str(o.product)), "name")
	var remaining := maxf(0, (float(o.deadline) - GameClock.unix_time) / 3600)
	return "%s · %s ×%d · %.1fh · +$%.0f%s" % [city, product, int(o.qty) - int(o.done), remaining, float(o.bonus) - float(o.advance), (" · %d/3" % int(o.stage)) if int(o.stage) > 1 else ""]


func _order_line(order: Dictionary) -> HBoxContainer:
	var row := _line(_order_label(order))
	_countdowns[row.get_child(0)] = order
	return row
