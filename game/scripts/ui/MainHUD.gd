extends Control
## Main HUD + panels. Builds UI in code for a self-contained Demo.

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Inventory = preload("res://scripts/systems/InventorySystem.gd")
const _Tickets = preload("res://scripts/systems/TicketService.gd")
const _FlightSearch = preload("res://scripts/systems/FlightSearch.gd")

@onready var globe: Node3D = $"../Globe"
@onready var flight_ops: Node = $"../FlightOps"

var _clock_label: Label
var _cash_label: Label
var _bag_label: Label
var _airport_label: Label
var _disclaimer: Label
var _search: LineEdit
var _airport_list: ItemList
var _airport_card: RichTextLabel
var _hint: Label
var _countdown: Label
var _btn_ff: Button
var _panel_host: Control
var _flight_list: ItemList
var _flight_query: LineEdit
var _flight_detail: RichTextLabel
var _market_list: ItemList
var _inv_list: ItemList
var _city_text: RichTextLabel
var _log_text: RichTextLabel
var _attr_text: RichTextLabel
var _overlay: ColorRect
var _overlay_label: Label
var _new_game_panel: PanelContainer
var _selected_flight: Dictionary = {}
var _cabin: String = "economy"
var _extra_tier: String = ""
var _cargo_blocks: int = 0
var _flights_cache: Array = []
var _market_cache: Array = []
var _last_hint_time := 0.0
var _ff_dialog: ConfirmationDialog
var _replace_ticket_dialog: ConfirmationDialog
var _pending_cabin: String = ""
var _filter_unvisited: bool = false
var _sort_by: String = "departure"
var _flight_page: int = 0
const FLIGHTS_PER_PAGE := 80


func _ready() -> void:
	_build_ui()
	EventBus.airport_selected.connect(_on_airport_selected)
	EventBus.cash_changed.connect(_refresh_top)
	EventBus.inventory_changed.connect(_refresh_bags)
	EventBus.ticket_purchased.connect(_refresh_countdown)
	EventBus.arrived.connect(_on_arrived)
	EventBus.tutorial_hint.connect(_show_hint)
	EventBus.game_started.connect(_on_game_started)
	flight_ops.transition_started.connect(_on_transition_started)
	flight_ops.transition_finished.connect(_on_transition_finished)
	_show_new_game()
	_refresh_airport_list("")
	_disclaimer.text = DataService.disclaimer


func _process(_d: float) -> void:
	_refresh_clock()
	_refresh_countdown()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := _bar(Color(0.05, 0.08, 0.12, 0.85))
	top.position = Vector2(0, 0)
	top.size = Vector2(1280, 52)
	add_child(top)
	_clock_label = _label(top, Vector2(12, 8), "时间")
	_cash_label = _label(top, Vector2(520, 8), "资金")
	_bag_label = _label(top, Vector2(820, 8), "行李")
	_airport_label = _label(top, Vector2(1000, 8), "机场")

	_countdown = _label(self, Vector2(400, 60), "")
	_countdown.add_theme_font_size_override("font_size", 16)
	_btn_ff = Button.new()
	_btn_ff.text = "加速至起飞"
	_btn_ff.position = Vector2(720, 56)
	_btn_ff.visible = false
	_btn_ff.pressed.connect(_on_fast_forward)
	add_child(_btn_ff)

	_disclaimer = _label(self, Vector2(12, 690), DataService.disclaimer)
	_disclaimer.add_theme_font_size_override("font_size", 12)
	_disclaimer.modulate = Color(1, 1, 1, 0.7)

	_hint = _label(self, Vector2(200, 100), "")
	_hint.size = Vector2(880, 40)
	_hint.modulate = Color(1, 0.9, 0.5)

	# Left search
	var left := PanelContainer.new()
	left.position = Vector2(8, 120)
	left.size = Vector2(250, 420)
	add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索机场 / IATA / 城市"
	_search.text_changed.connect(_refresh_airport_list)
	lv.add_child(_search)
	_airport_list = ItemList.new()
	_airport_list.custom_minimum_size = Vector2(230, 300)
	_airport_list.item_selected.connect(_on_list_airport)
	lv.add_child(_airport_list)
	var btn_rand := Button.new()
	btn_rand.text = "随机起点"
	btn_rand.pressed.connect(_on_random)
	lv.add_child(btn_rand)

	# Right airport card
	var right := PanelContainer.new()
	right.position = Vector2(1000, 120)
	right.size = Vector2(270, 360)
	add_child(right)
	_airport_card = RichTextLabel.new()
	_airport_card.bbcode_enabled = true
	_airport_card.fit_content = false
	_airport_card.custom_minimum_size = Vector2(250, 340)
	_airport_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_airport_card)

	# Bottom nav
	var bottom := HBoxContainer.new()
	bottom.position = Vector2(200, 640)
	bottom.size = Vector2(880, 40)
	add_child(bottom)
	for pair in [
		["城市", "_show_city"], ["市场", "_show_market"], ["航班", "_show_flights"],
		["库存", "_show_inventory"], ["旅行记录", "_show_log"], ["数据来源", "_show_attr"],
		["存档", "_save"], ["读档", "_load"], ["设置暂停", "_toggle_pause"]
	]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(Callable(self, pair[1]))
		bottom.add_child(b)

	_panel_host = PanelContainer.new()
	_panel_host.position = Vector2(260, 150)
	_panel_host.size = Vector2(720, 460)
	_panel_host.visible = false
	add_child(_panel_host)

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.75)
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay_label.add_theme_font_size_override("font_size", 28)
	_overlay.add_child(_overlay_label)

	_ff_dialog = ConfirmationDialog.new()
	_ff_dialog.title = "加速至起飞"
	_ff_dialog.ok_button_text = "确认加速"
	_ff_dialog.cancel_button_text = "取消"
	_ff_dialog.confirmed.connect(_do_fast_forward)
	add_child(_ff_dialog)

	_replace_ticket_dialog = ConfirmationDialog.new()
	_replace_ticket_dialog.title = "替换机票"
	_replace_ticket_dialog.ok_button_text = "退旧票并购买"
	_replace_ticket_dialog.cancel_button_text = "取消"
	_replace_ticket_dialog.confirmed.connect(_do_replace_purchase)
	add_child(_replace_ticket_dialog)

	_new_game_panel = PanelContainer.new()
	_new_game_panel.position = Vector2(360, 200)
	_new_game_panel.size = Vector2(560, 280)
	add_child(_new_game_panel)
	var ngv := VBoxContainer.new()
	_new_game_panel.add_child(ngv)
	var title := Label.new()
	title.text = "《环球航商》Demo — 选择起始机场"
	title.add_theme_font_size_override("font_size", 22)
	ngv.add_child(title)
	var info := Label.new()
	info.text = "在左侧搜索或点选地球机场，然后开始。也可随机。\n航班网络基于公开航空数据重建，不代表真实购票信息。"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ngv.add_child(info)
	var row := HBoxContainer.new()
	ngv.add_child(row)
	var b1 := Button.new()
	b1.text = "以当前选中机场开始"
	b1.pressed.connect(_start_selected)
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "随机机场开始"
	b2.pressed.connect(func (): _on_random(); _start_selected())
	row.add_child(b2)
	if SaveSystem.has_save():
		var b3 := Button.new()
		b3.text = "继续存档"
		b3.pressed.connect(_load)
		row.add_child(b3)


func _bar(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(parent: Node, pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	parent.add_child(l)
	return l


func _show_new_game() -> void:
	_new_game_panel.visible = true
	GameClock.set_paused(true)


func _start_selected() -> void:
	var id := _selected_or_first()
	if id == "":
		return
	AppState.reset_new_game(id)
	_new_game_panel.visible = false
	globe.focus_airport(id)
	_refresh_top()
	_refresh_bags()


func _selected_or_first() -> String:
	if _airport_card.get_meta("aid", "") != "":
		return str(_airport_card.get_meta("aid"))
	if DataService.airports.size() > 0:
		return DataService.airports[0].airport_id
	return ""


func _on_game_started() -> void:
	_new_game_panel.visible = false
	_refresh_top()
	_refresh_bags()
	globe.focus_airport(AppState.current_airport_id)


func _on_random() -> void:
	var id := DataService.random_hub_id()
	EventBus.airport_selected.emit(id)
	globe.focus_airport(id)


func _refresh_airport_list(q: String) -> void:
	_airport_list.clear()
	for a in DataService.search_airports(q):
		_airport_list.add_item("%s  %s（%s）" % [a.iata, a.name_zh, a.city_zh])
		_airport_list.set_item_metadata(_airport_list.item_count - 1, a.airport_id)


func _on_list_airport(idx: int) -> void:
	var id: String = _airport_list.get_item_metadata(idx)
	EventBus.airport_selected.emit(id)
	globe.focus_airport(id)


func _on_airport_selected(airport_id: String) -> void:
	var a: Dictionary = DataService.get_airport(airport_id)
	if a.is_empty():
		return
	_airport_card.set_meta("aid", airport_id)
	var local := GameClock.format_local(str(a.timezone))
	var dests := DataService.destinations_from(str(a.iata)).size()
	_airport_card.text = "[b]%s[/b]\n%s / %s\n城市：%s（%s）\n国家：%s\n当地时间：%s\n海拔：%.0f ft\n直飞目的地：%d\n类型：%s\n可信：%s" % [
		a.name_zh, a.iata, a.icao, a.city_zh, a.city_en, a.country_zh, local,
		float(a.elevation_ft), dests, a.type, a.data_confidence
	]
	if AppState.game_started and airport_id == AppState.current_airport_id:
		globe.draw_routes_from(airport_id)


func _refresh_clock() -> void:
	var a := AppState.current_airport()
	var local := ""
	if not a.is_empty():
		local = GameClock.format_local(str(a.timezone))
	_clock_label.text = "UTC %s | 当地 %s | %s" % [GameClock.now_iso(), local, "暂停" if GameClock.paused else "流逝中"]


func _refresh_top() -> void:
	_cash_label.text = "资金 " + _Economy.format_money(AppState.cash_usd)
	var a := AppState.current_airport()
	_airport_label.text = "当前位置 %s" % (a.get("iata", "-"))


func _refresh_bags() -> void:
	var used := AppState.inventory_weight_kg(false, true)
	var lim := AppState.personal_baggage_limit_kg()
	var cargo_u := AppState.inventory_weight_kg(true, false)
	_bag_label.text = "行李 %.1f/%.1fkg  货运 %.1f/%.0fkg" % [used, lim, cargo_u, AppState.cargo_kg_capacity]


func _refresh_countdown() -> void:
	var t: Dictionary = _Tickets.next_ticket()
	if t.is_empty():
		_countdown.text = ""
		_btn_ff.visible = false
		return
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	var remain: float = max(0.0, dep - GameClock.unix_time)
	var hrs: int = int(remain / 3600.0)
	var mins: int = int(fmod(remain, 3600.0) / 60.0)
	if remain <= 0.0:
		_countdown.text = "下一班 %s %s→%s  登机中…" % [
			t.get("marketing_flight_number", ""), t.get("origin_iata", ""), t.get("destination_iata", "")
		]
		_countdown.modulate = Color(1, 0.3, 0.3)
		_btn_ff.visible = false
	else:
		_countdown.text = "下一班 %s %s→%s  倒计时 %dh%02dm  [%s]" % [
			t.get("marketing_flight_number", ""), t.get("origin_iata", ""), t.get("destination_iata", ""),
			hrs, mins, t.get("cabin", "")
		]
		_countdown.modulate = Color(1, 1, 1)
		_btn_ff.visible = AppState.game_started


func _on_fast_forward() -> void:
	var t: Dictionary = _Tickets.next_ticket()
	if t.is_empty():
		_show_hint("没有已购航班")
		return
	var dep: float = GameClock.parse_iso_to_unix(str(t.get("scheduled_departure_utc", "")))
	var hours: float = max(0.0, (dep - GameClock.unix_time) / 3600.0)
	_ff_dialog.dialog_text = "将跳跃约 %.1f 游戏小时至起飞时刻。\n易腐商品品质会按等待时间衰减，市场价格按新日期刷新。\n确认加速？" % hours
	_ff_dialog.popup_centered()


func _do_fast_forward() -> void:
	var err: String = flight_ops.fast_forward_to_departure()
	if err != "":
		_show_hint(err)
	else:
		_show_hint("已加速至起飞时刻。")


func _on_transition_started(ticket: Dictionary) -> void:
	_panel_host.visible = false
	_overlay.visible = true
	_overlay_label.text = "强制登机（不可取消）\n%s  %s → %s\n距离 %.0f km · %s舱\n飞行中…" % [
		ticket.get("marketing_flight_number", ""), ticket.get("origin_iata", ""), ticket.get("destination_iata", ""),
		float(ticket.get("distance_km", 0)), ticket.get("cabin", "")
	]
	globe.draw_trip_route(str(ticket.get("origin_airport_id", "")), str(ticket.get("destination_airport_id", "")))


func _on_transition_finished() -> void:
	_overlay.visible = false


func _on_arrived() -> void:
	_refresh_top()
	_refresh_bags()
	globe.focus_airport(AppState.current_airport_id)


func _show_hint(text: String) -> void:
	_hint.text = text
	_last_hint_time = Time.get_ticks_msec() / 1000.0


func _clear_panel() -> void:
	for c in _panel_host.get_children():
		c.queue_free()
	_panel_host.visible = true


func _require_started() -> bool:
	if not AppState.game_started:
		_show_hint("请先选择机场开始游戏")
		return false
	return true


func _show_city() -> void:
	if not _require_started():
		return
	_clear_panel()
	var c: Dictionary = DataService.get_city(AppState.current_city_id())
	_city_text = RichTextLabel.new()
	_city_text.bbcode_enabled = true
	_city_text.custom_minimum_size = Vector2(700, 440)
	_city_text.fit_content = false
	_city_text.scroll_active = true
	_panel_host.add_child(_city_text)
	if c.is_empty():
		_city_text.text = "无城市数据"
		return
	_city_text.text = "[b]%s[/b]\n\n%s\n\n[b]历史[/b]\n%s\n\n[b]地理[/b]\n%s\n\n[b]经济[/b]\n%s\n\n[b]饮食[/b]\n%s\n\n[b]旅行提示[/b]\n%s" % [
		c.name_zh, c.overview, c.history_summary, c.geography_summary, c.economy_summary, c.food_summary, c.travel_note
	]


func _show_market() -> void:
	if not _require_started():
		return
	_clear_panel()
	var v := VBoxContainer.new()
	_panel_host.add_child(v)
	var title := Label.new()
	title.text = "市场 — %s（超重可就地加购行李/货运）" % AppState.current_city_id()
	v.add_child(title)
	_market_list = ItemList.new()
	_market_list.custom_minimum_size = Vector2(700, 300)
	v.add_child(_market_list)
	_market_cache.clear()
	var city := AppState.current_city_id()
	var locals := DataService.products_for_city(city)
	for p in locals:
		_add_market_row(city, p, true)
	var count := 0
	for p in DataService.world.get("products", []):
		if p.origin_city_id == city:
			continue
		_add_market_row(city, p, false)
		count += 1
		if count >= 25:
			break
	_market_list.item_activated.connect(_buy_market_item)
	var row := HBoxContainer.new()
	v.add_child(row)
	var b1 := Button.new()
	b1.text = "买入 1（行李）"
	b1.pressed.connect(func (): _buy_selected(false))
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "买入 1（货运）"
	b2.pressed.connect(func (): _buy_selected(true))
	row.add_child(b2)
	for pair in [["+10kg", "light"], ["+20kg", "standard"], ["+50kg", "heavy"]]:
		var bx := Button.new()
		bx.text = pair[0]
		var tier: String = pair[1]
		bx.pressed.connect(func (): _show_hint(_Inventory.expand_baggage(tier)); _refresh_bags())
		row.add_child(bx)
	var bc := Button.new()
	bc.text = "+50kg货运"
	bc.pressed.connect(func (): _show_hint(_Inventory.expand_cargo(1)); _refresh_bags())
	row.add_child(bc)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func (): _panel_host.visible = false)
	row.add_child(close)


func _add_market_row(city: String, p: Dictionary, is_local: bool) -> void:
	var buy: float = _Economy.buy_price(city, str(p.get("product_id", "")))
	var sell: float = _Economy.sell_price(city, str(p.get("product_id", "")), 1.0)
	var tag := "本地" if is_local else "外来"
	_market_list.add_item("[%s] %s  买%s  卖%s  %.2fkg" % [
		tag, p.get("name_zh", ""), _Economy.format_money(buy), _Economy.format_money(sell), float(p.get("weight_kg", 0))
	])
	_market_cache.append(p.get("product_id", ""))


func _buy_selected(as_cargo: bool) -> void:
	var idx := _market_list.get_selected_items()
	if idx.is_empty():
		return
	var pid: String = _market_cache[idx[0]]
	var err: String = _Inventory.buy(pid, 1, as_cargo)
	_show_hint(err if err != "" else "购买成功")
	_refresh_bags()


func _buy_market_item(idx: int) -> void:
	_market_list.select(idx)
	_buy_selected(false)


func _show_flights() -> void:
	if not _require_started():
		return
	_clear_panel()
	var v := VBoxContainer.new()
	_panel_host.add_child(v)
	var tip := Label.new()
	tip.text = "全局航班检索（当前机场出港）· " + DataService.disclaimer
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	_flight_query = LineEdit.new()
	_flight_query.placeholder_text = "目的地 / IATA / 航空公司"
	_flight_query.text_changed.connect(func (_t): _flight_page = 0; _reload_flights())
	v.add_child(_flight_query)
	var filters := HBoxContainer.new()
	v.add_child(filters)
	var bun := Button.new()
	bun.text = "仅未访问"
	bun.toggle_mode = true
	bun.toggled.connect(func (on): _filter_unvisited = on; _flight_page = 0; _reload_flights())
	filters.add_child(bun)
	for pair in [["起飞", "departure"], ["票价", "price"], ["时长", "duration"], ["距离", "distance"]]:
		var bs := Button.new()
		bs.text = "排序:" + pair[0]
		var key: String = pair[1]
		bs.pressed.connect(func (): _sort_by = key; _flight_page = 0; _reload_flights())
		filters.add_child(bs)
	_flight_list = ItemList.new()
	_flight_list.custom_minimum_size = Vector2(700, 200)
	_flight_list.item_selected.connect(_on_flight_selected)
	v.add_child(_flight_list)
	var pager := HBoxContainer.new()
	v.add_child(pager)
	var prev := Button.new()
	prev.text = "上一页"
	prev.pressed.connect(func (): _flight_page = maxi(0, _flight_page - 1); _reload_flights())
	pager.add_child(prev)
	var nxt := Button.new()
	nxt.text = "下一页"
	nxt.pressed.connect(func (): _flight_page += 1; _reload_flights())
	pager.add_child(nxt)
	_flight_detail = RichTextLabel.new()
	_flight_detail.bbcode_enabled = true
	_flight_detail.custom_minimum_size = Vector2(700, 100)
	v.add_child(_flight_detail)
	var row := HBoxContainer.new()
	v.add_child(row)
	var be := Button.new()
	be.text = "经济舱购票"
	be.pressed.connect(func (): _purchase("economy"))
	row.add_child(be)
	var bb := Button.new()
	bb.text = "公务舱购票×10"
	bb.pressed.connect(func (): _purchase("business"))
	row.add_child(bb)
	for pair in [["+10kg", "light"], ["+20kg", "standard"], ["+50kg", "heavy"]]:
		var bx := Button.new()
		bx.text = pair[0]
		var tier: String = pair[1]
		bx.pressed.connect(func (): _extra_tier = tier; _show_hint("已选择行李扩展 " + pair[0]))
		row.add_child(bx)
	var bc := Button.new()
	bc.text = "货运+50"
	bc.pressed.connect(func (): _cargo_blocks += 1; _show_hint("货运档位 ×%d（每档50kg）" % _cargo_blocks))
	row.add_child(bc)
	var bcr := Button.new()
	bcr.text = "清零货运"
	bcr.pressed.connect(func (): _cargo_blocks = 0; _show_hint("已清零货运加购"))
	row.add_child(bcr)
	var br := Button.new()
	br.text = "退票(30%)"
	br.pressed.connect(func (): _show_hint(_Tickets.refund_current()); _refresh_bags())
	row.add_child(br)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func (): _panel_host.visible = false)
	row.add_child(close)
	_extra_tier = ""
	_cargo_blocks = 0
	_flight_page = 0
	_reload_flights()


func _reload_flights(_q: String = "") -> void:
	if _flight_list == null:
		return
	_flight_list.clear()
	var q: String = _flight_query.text if _flight_query else ""
	var all: Array = _FlightSearch.search(AppState.current_airport_id, q, 0, _filter_unvisited, _sort_by)
	var start: int = _flight_page * FLIGHTS_PER_PAGE
	if start >= all.size() and _flight_page > 0:
		_flight_page = maxi(0, (all.size() - 1) / FLIGHTS_PER_PAGE)
		start = _flight_page * FLIGHTS_PER_PAGE
	_flights_cache = all.slice(start, mini(all.size(), start + FLIGHTS_PER_PAGE))
	for fl in _flights_cache:
		_flight_list.add_item("%s  %s→%s  %s  经济$%.0f  公务$%.0f  %dmin" % [
			fl.marketing_flight_number, fl.origin_iata, fl.destination_iata,
			str(fl.scheduled_departure_utc).substr(0, 16),
			float(fl.ticket_base_price_economy), float(fl.ticket_base_price_business),
			int(fl.duration_minutes)
		])
	_show_hint("航班 %d–%d / 共 %d（页 %d）" % [
		start + (1 if all.size() > 0 else 0), start + _flights_cache.size(), all.size(), _flight_page + 1
	])


func _on_flight_selected(idx: int) -> void:
	if idx < 0 or idx >= _flights_cache.size():
		return
	_selected_flight = _flights_cache[idx]
	var fl: Dictionary = _selected_flight
	_flight_detail.text = "航班 %s（%s）\n%s → %s\n起飞 %s\n到达 %s\n距离 %.0f km · %d 分钟\n经济舱 $%.2f / 公务舱 $%.2f（10×）\n行李额：经济 %.0fkg / 公务 %.0fkg\n加购：行李档=%s  货运×%d" % [
		fl.get("marketing_flight_number", ""), fl.get("airline_name", ""), fl.get("origin_iata", ""), fl.get("destination_iata", ""),
		fl.get("scheduled_departure_utc", ""), fl.get("scheduled_arrival_utc", ""), float(fl.get("distance_km", 0)), int(fl.get("duration_minutes", 0)),
		float(fl.get("ticket_base_price_economy", 0)), float(fl.get("ticket_base_price_business", 0)),
		float(fl.get("baggage_allowance_economy", 20)), float(fl.get("baggage_allowance_business", 60)),
		_extra_tier if _extra_tier != "" else "无", _cargo_blocks
	]


func _purchase(cabin: String) -> void:
	if _selected_flight.is_empty():
		_show_hint("请先选择航班")
		return
	var err: String = _Tickets.purchase(_selected_flight, cabin, _extra_tier, _cargo_blocks, false)
	if err.find("已有机票") >= 0:
		_pending_cabin = cabin
		_replace_ticket_dialog.dialog_text = err + "\n将按 30% 手续费退旧票后购买新票，确认？"
		_replace_ticket_dialog.popup_centered()
		return
	_show_hint(err if err != "" else "购票成功")
	_refresh_bags()
	_refresh_countdown()
	if err == "" and _selected_flight.has("destination_airport_id"):
		globe.draw_trip_route(AppState.current_airport_id, str(_selected_flight.destination_airport_id))


func _do_replace_purchase() -> void:
	var err: String = _Tickets.purchase(_selected_flight, _pending_cabin, _extra_tier, _cargo_blocks, true)
	_show_hint(err if err != "" else "已替换购票")
	_refresh_bags()
	_refresh_countdown()
	if err == "" and _selected_flight.has("destination_airport_id"):
		globe.draw_trip_route(AppState.current_airport_id, str(_selected_flight.destination_airport_id))


func _show_inventory() -> void:
	if not _require_started():
		return
	_clear_panel()
	var v := VBoxContainer.new()
	_panel_host.add_child(v)
	_inv_list = ItemList.new()
	_inv_list.custom_minimum_size = Vector2(700, 360)
	v.add_child(_inv_list)
	for i in AppState.inventory.size():
		var item: Dictionary = AppState.inventory[i]
		var p: Dictionary = DataService.get_product(str(item.get("product_id", "")))
		var q: float = _Economy.current_quality(item)
		_inv_list.add_item("%s ×%d  品质%.0f%%  成本%s  %s" % [
			p.get("name_zh", item.get("product_id", "")), int(item.get("qty", 0)), q * 100.0,
			_Economy.format_money(float(item.get("unit_cost", 0))),
			"货运" if item.get("in_cargo", false) else "行李"
		])
	var row := HBoxContainer.new()
	v.add_child(row)
	var sell := Button.new()
	sell.text = "出售 1"
	sell.pressed.connect(_sell_one)
	row.add_child(sell)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func (): _panel_host.visible = false)
	row.add_child(close)


func _sell_one() -> void:
	var idxs := _inv_list.get_selected_items()
	if idxs.is_empty():
		return
	var msg: String = _Inventory.sell(idxs[0], 1)
	_show_hint(msg)
	_show_inventory()
	_refresh_bags()


func _show_log() -> void:
	_clear_panel()
	_log_text = RichTextLabel.new()
	_log_text.custom_minimum_size = Vector2(700, 440)
	_log_text.bbcode_enabled = true
	_panel_host.add_child(_log_text)
	var s := "[b]旅行记录[/b]\n已访问机场 %d · 城市 %d · 国家 %d\n\n" % [
		AppState.visited_airports.size(), AppState.visited_cities.size(), AppState.visited_countries.size()
	]
	for e in AppState.travel_log:
		s += "%s %s→%s  %s  $%.0f\n" % [
			e.get("flight_number", ""), e.get("departure_airport", ""), e.get("arrival_airport", ""),
			e.get("airline", ""), float(e.get("ticket_price", 0))
		]
	_log_text.text = s


func _show_attr() -> void:
	_clear_panel()
	_attr_text = RichTextLabel.new()
	_attr_text.bbcode_enabled = true
	_attr_text.custom_minimum_size = Vector2(700, 440)
	_panel_host.add_child(_attr_text)
	var s := "[b]数据来源与许可证[/b]\n\n%s\n\n" % DataService.disclaimer
	for a in DataService.world.get("attributions", []):
		s += "• %s — %s\n  %s\n" % [a.get("name", ""), a.get("license", ""), a.get("note", "")]
	var meta: Dictionary = DataService.world.get("meta", {})
	s += "\n基准日：%s\nETL：%s\n生成：%s\n" % [
		meta.get("baseline_date", ""), meta.get("etl_version", ""), meta.get("generated_at", "")
	]
	_attr_text.text = s


func _save() -> void:
	GameClock.set_paused(true)
	if SaveSystem.save_game():
		_show_hint("已保存")
	else:
		_show_hint("保存失败")
	GameClock.set_paused(false)


func _load() -> void:
	GameClock.set_paused(true)
	if SaveSystem.load_game():
		_show_hint("已读档")
		_new_game_panel.visible = false
		globe.focus_airport(AppState.current_airport_id)
		_refresh_top()
		_refresh_bags()
	else:
		_show_hint("无存档")
	GameClock.set_paused(not AppState.game_started)


func _toggle_pause() -> void:
	GameClock.set_paused(not GameClock.paused)
	_show_hint("时间暂停" if GameClock.paused else "时间继续")
