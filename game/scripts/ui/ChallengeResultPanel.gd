extends Control
## 15-day challenge settlement screen. Shows the eight PRD §6.2 metrics,
## a normalized score and A/B/C/D grade, plus restart / back-to-menu actions.
## Built in code to match the project's UI conventions.

signal restart_requested
signal menu_requested

const _Economy = preload("res://scripts/systems/EconomySystem.gd")
const _Colors = preload("res://themes/DemoColors.gd")
const _ThemeFactory = preload("res://themes/ThemeFactory.gd")
const _CB = preload("res://themes/ColorBlindPalette.gd")

var _result: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_result(result: Dictionary) -> void:
	_result = result
	for c in get_children():
		c.queue_free()
	_build()
	visible = true


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(640, 560)
	panel.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_theme_constant_override("margin_left", 28)
	v.add_theme_constant_override("margin_right", 28)
	v.add_theme_constant_override("margin_top", 20)
	v.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(v)

	var title := Label.new()
	title.text = I18nService.t("ui.challenge.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", _Colors.ICE)
	v.add_child(title)

	var score_label := Label.new()
	score_label.text = I18nService.t("ui.challenge.score", {"score": int(_result.get("score", 0))})
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 20)
	score_label.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
	v.add_child(score_label)

	var grade_label := Label.new()
	grade_label.text = I18nService.t("ui.challenge.grade", {"grade": str(_result.get("grade", "-"))})
	grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade_label.add_theme_font_size_override("font_size", 28)
	grade_label.add_theme_color_override("font_color", _grade_color(str(_result.get("grade", "D"))))
	v.add_child(grade_label)

	var metrics: Array = [
		["ui.challenge.metric.net_worth", _Economy.format_money(float(_result.get("net_worth", 0)))],
		["ui.challenge.metric.visited_cities", "%d" % int(_result.get("visited_cities", 0))],
		["ui.challenge.metric.visited_countries", "%d" % int(_result.get("visited_countries", 0))],
		["ui.challenge.metric.products_discovered", "%d" % int(_result.get("products_discovered", 0))],
		["ui.challenge.metric.total_distance_km", "%.0f km" % float(_result.get("total_distance_km", 0))],
		["ui.challenge.metric.on_time_rate", "%d%%" % int(float(_result.get("on_time_rate", 0)) * 100.0)],
		["ui.challenge.metric.single_profit_max", _Economy.format_money(float(_result.get("single_profit_max", 0)))],
		["ui.challenge.metric.profit_per_hour", _Economy.format_money(float(_result.get("profit_per_hour", 0)))],
	]
	for m in metrics:
		var row := HBoxContainer.new()
		v.add_child(row)
		var k := Label.new()
		k.text = I18nService.t(str(m[0]))
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
		row.add_child(k)
		var val := Label.new()
		val.text = str(m[1])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY)
		row.add_child(val)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	var restart := Button.new()
	restart.text = I18nService.t("ui.challenge.restart")
	restart.pressed.connect(func (): restart_requested.emit())
	buttons.add_child(restart)
	var to_menu := Button.new()
	to_menu.text = I18nService.t("ui.challenge.to_menu")
	to_menu.pressed.connect(func (): menu_requested.emit())
	buttons.add_child(to_menu)


func _grade_color(grade: String) -> Color:
	if _CB.active():
		return _CB.grade_color(grade)
	match grade:
		"A":
			return Color(0.9, 0.8, 0.2)
		"B":
			return Color(0.5, 0.85, 0.5)
		"C":
			return Color(0.55, 0.7, 0.95)
		_:
			return _Colors.TEXT_SECONDARY
