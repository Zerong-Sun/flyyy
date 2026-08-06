extends Control
## Reputation / level panel: current Lv, XP progress, and the unlock tree
## (active unlocks highlighted, upcoming ones greyed).

const _Colors = preload("res://themes/DemoColors.gd")
const _ThemeFactory = preload("res://themes/ThemeFactory.gd")

const _ALL_UNLOCK_KEYS := [
	"unlock_lv2_cargo", "unlock_lv3_cold_discount", "unlock_lv4_intel_discount",
	"unlock_lv5_baggage_plus10", "unlock_lv6_globe_title",
]


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
	panel.custom_minimum_size = Vector2(520, 360)
	panel.add_theme_stylebox_override("panel", _ThemeFactory.card_style(false))
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_theme_constant_override("margin_left", 28)
	v.add_theme_constant_override("margin_right", 28)
	v.add_theme_constant_override("margin_top", 18)
	v.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(v)

	var title := Label.new()
	title.text = I18nService.t("ui.reputation.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", _Colors.ICE)
	v.add_child(title)

	var lv_label := Label.new()
	lv_label.text = I18nService.t("ui.reputation.level", {"level": AppState.level})
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_label.add_theme_font_size_override("font_size", 20)
	lv_label.add_theme_color_override("font_color", _Colors.ACCENT_AMBER)
	v.add_child(lv_label)

	var xp := AppState.reputation_points
	var next := ReputationSystem.xp_to_next_level()
	var xp_label := Label.new()
	xp_label.text = I18nService.t("ui.reputation.xp", {"xp": xp, "next": next})
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	v.add_child(xp_label)

	var max_threshold: int = ReputationSystem.LEVEL_THRESHOLDS[ReputationSystem.LEVEL_THRESHOLDS.size() - 1]
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 1
	bar.value = clampf(float(xp) / float(max_threshold), 0.0, 1.0)
	bar.custom_minimum_size = Vector2(460, 14)
	bar.show_percentage = false
	v.add_child(bar)

	var unlock_title := Label.new()
	unlock_title.text = I18nService.t("ui.reputation.unlocks")
	unlock_title.add_theme_font_size_override("font_size", 15)
	unlock_title.add_theme_color_override("font_color", _Colors.ICE)
	v.add_child(unlock_title)

	var active := ReputationSystem.active_unlocks()
	for key in _ALL_UNLOCK_KEYS:
		var row := Label.new()
		var label_key := ReputationSystem.unlock_name(key)
		row.text = ("✅ " if key in active else "🔒 ") + I18nService.t(label_key)
		row.add_theme_color_override("font_color", _Colors.TEXT_PRIMARY if key in active else _Colors.TEXT_SECONDARY)
		v.add_child(row)

	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func (): visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)
