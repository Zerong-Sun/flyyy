extends Control
## Three-tab collection codex: cities / products / routes.
## Links AppState.visited_cities, stats.products_discovered, stats.routes_flown,
## and the achievements wall (collect category). Built in code like CollectorPanel.

const _Colors = preload("res://themes/DemoColors.gd")
const _ThemeFactory = preload("res://themes/ThemeFactory.gd")

var _tab := 0  # 0 city | 1 product | 2 route
var _title_label: Label
var _progress_label: Label
var _content: VBoxContainer
var _tab_buttons: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	_build()
	visible = true


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(640, 520)
	panel.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_theme_constant_override("margin_left", 24)
	v.add_theme_constant_override("margin_right", 24)
	v.add_theme_constant_override("margin_top", 16)
	v.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(v)

	_title_label = Label.new()
	_title_label.text = I18nService.t("ui.codex.title")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", _Colors.ICE)
	v.add_child(_title_label)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for pair in [["ui.codex.city", 0], ["ui.codex.product", 1], ["ui.codex.route", 2]]:
		var tb := Button.new()
		tb.text = I18nService.t(str(pair[0]))
		tb.toggle_mode = true
		var idx: int = pair[1]
		tb.button_pressed = idx == _tab
		tb.pressed.connect(func (): _select_tab(idx))
		tabs.add_child(tb)
		_tab_buttons.append([tb, idx])

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	v.add_child(_progress_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	match _tab:
		0:
			_build_city_tab()
		1:
			_build_product_tab()
		_:
			_build_route_tab()

	var close := Button.new()
	close.text = I18nService.t("ui.challenge.to_menu")
	close.pressed.connect(func (): visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)


func _select_tab(idx: int) -> void:
	_tab = idx
	for pair_v in _tab_buttons:
		var pair: Array = pair_v
		pair[0].button_pressed = int(pair[1]) == idx
	refresh()


func _set_progress(cur: int, total: int) -> void:
	_progress_label.text = I18nService.t("ui.codex.progress", {"cur": cur, "total": total})


func _add_empty() -> void:
	var e := Label.new()
	e.text = I18nService.t("ui.codex.empty")
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	_content.add_child(e)


func _row(text: String, unlocked: bool) -> void:
	var row := Label.new()
	row.text = ("🔓 " if unlocked else "🔒 ") + text
	row.add_theme_font_size_override("font_size", 14)
	row.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY if unlocked else _Colors.TEXT_SECONDARY)
	_content.add_child(row)


func _build_city_tab() -> void:
	var cities: Dictionary = DataService.cities_by_id
	var visited: Dictionary = AppState.visited_cities
	var unlocked := 0
	for city_id in cities.keys():
		if visited.has(str(city_id)):
			unlocked += 1
	_set_progress(unlocked, int(cities.size()))
	if cities.is_empty():
		_add_empty()
		return
	var rows: Array = []
	for city_id in cities.keys():
		var c: Dictionary = cities[city_id]
		var is_visited := visited.has(str(city_id))
		var name := DataService.place_name(c, "name")
		var country := str(c.get("country_zh", ""))
		rows.append({"sort": name, "text": "%s · %s" % [name, country], "unlocked": is_visited})
	rows.sort_custom(func (a, b): return str(a.sort) < str(b.sort))
	for r in rows:
		_row(str(r.text), bool(r.unlocked))


func _build_product_tab() -> void:
	var products: Dictionary = DataService.products_by_id
	var found: Dictionary = AppState.stats.get("products_discovered", {})
	var unlocked := 0
	for pid in products.keys():
		if found.has(str(pid)):
			unlocked += 1
	_set_progress(unlocked, int(products.size()))
	if products.is_empty():
		_add_empty()
		return
	var rows: Array = []
	for pid in products.keys():
		var p: Dictionary = products[pid]
		var is_found := found.has(str(pid))
		var name := str(p.get("name_zh", pid))
		var cat := str(p.get("category", ""))
		var origin := DataService.get_city(str(p.get("origin_city_id", "")))
		var origin_name := DataService.place_name(origin, "name")
		rows.append({"sort": name, "text": "%s（%s · %s）" % [name, cat, origin_name], "unlocked": is_found})
	rows.sort_custom(func (a, b): return str(a.sort) < str(b.sort))
	for r in rows:
		_row(str(r.text), bool(r.unlocked))


func _build_route_tab() -> void:
	var routes: Dictionary = AppState.stats.get("routes_flown", {})
	var counts: Dictionary = {}
	for entry_v in AppState.travel_log:
		var entry: Dictionary = entry_v
		var key := "%s|%s" % [entry.get("departure_airport", ""), entry.get("arrival_airport", "")]
		if key != "|":
			counts[key] = int(counts.get(key, 0)) + 1
	_set_progress(int(routes.size()), int(routes.size()))
	if routes.is_empty():
		_add_empty()
		return
	var rows: Array = []
	for key in routes.keys():
		var parts := str(key).split("|")
		if parts.size() < 2:
			continue
		var n: int = int(counts.get(str(key), 0))
		var label := "%s → %s" % [parts[0], parts[1]]
		if n > 0:
			label += "  " + I18nService.t("ui.codex.route_count", {"n": n})
		rows.append({"sort": label, "text": label})
	rows.sort()
	for r in rows:
		_row(str(r.text), true)
