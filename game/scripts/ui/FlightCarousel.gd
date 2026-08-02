extends Control
## Horizontal coverflow-style flight card carousel.
## Wheel / drag to scroll; focused card scales up and sits above neighbors.

signal focus_changed(index: int)
signal card_activated(index: int)

const _Colors = preload("res://themes/DemoColors.gd")

const CARD_W := 200.0
const CARD_H := 100.0
const CARD_GAP := 16.0
const SCALE_FOCUS := 1.0
const SCALE_SIDE := 0.82
const DRAG_THRESHOLD := 6.0

var _items: Array = []  # Array of Dictionaries: {title, subtitle, meta, muted, data}
var _cards: Array = []  # Array of PanelContainer
var _focus: int = 0
var _scroll: float = 0.0  # continuous scroll position in card units
var _dragging := false
var _drag_start_x := 0.0
var _drag_start_scroll := 0.0
var _drag_moved := false
var _tween: Tween = null
var _style_normal: StyleBoxFlat = null
var _style_muted: StyleBoxFlat = null
var _style_focus: StyleBoxFlat = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(400, CARD_H + 12.0)
	resized.connect(_layout_cards)
	mouse_exited.connect(_on_mouse_exited)
	_ensure_styles()


func _ensure_styles() -> void:
	if _style_normal != null:
		return
	_style_normal = _card_style(false)
	_style_muted = _card_style(true)
	_style_focus = _focus_style()


func set_items(items: Array) -> void:
	_items = items
	_rebuild()
	if _items.is_empty():
		_focus = 0
		_scroll = 0.0
		return
	_focus = clampi(_focus, 0, _items.size() - 1)
	_scroll = float(_focus)
	_layout_cards()
	focus_changed.emit(_focus)


func clear() -> void:
	set_items([])


func get_focus_index() -> int:
	return _focus


func select_index(index: int, animate: bool = true) -> void:
	if _items.is_empty():
		return
	var i := clampi(index, 0, _items.size() - 1)
	_focus = i
	if animate:
		_animate_to(float(i))
	else:
		_scroll = float(i)
		_layout_cards()
	focus_changed.emit(_focus)


func _rebuild() -> void:
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()
	for i in _items.size():
		var item: Dictionary = _items[i]
		var card := _make_card(item, i)
		add_child(card)
		_cards.append(card)
	_layout_cards()


func _make_card(item: Dictionary, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_W, CARD_H)
	panel.size = Vector2(CARD_W, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
	panel.add_theme_stylebox_override(
		"panel", _style_muted if bool(item.get("muted", false)) else _style_normal
	)
	panel.gui_input.connect(_on_card_gui_input.bind(index))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	var title := Label.new()
	title.text = str(item.get("title", ""))
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", _Colors.ICE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(title)

	var sub := Label.new()
	sub.text = str(item.get("subtitle", ""))
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override(
		"font_color",
		_Colors.TEXT_SECONDARY if bool(item.get("muted", false)) else _Colors.ACCENT_TEAL
	)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)

	var meta := Label.new()
	meta.text = str(item.get("meta", ""))
	meta.add_theme_font_size_override("font_size", 12)
	meta.add_theme_color_override(
		"font_color",
		Color(0.55, 0.55, 0.55) if bool(item.get("muted", false)) else _Colors.TEXT_PRIMARY
	)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(meta)

	return panel


func _card_style(muted: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(_Colors.BG_PANEL.r, _Colors.BG_PANEL.g, _Colors.BG_PANEL.b, 0.94)
	s.border_color = _Colors.BORDER if not muted else Color(_Colors.BORDER.r, _Colors.BORDER.g, _Colors.BORDER.b, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s


func _focus_style() -> StyleBoxFlat:
	var s := _card_style(false)
	s.border_color = _Colors.ACCENT_AMBER
	s.set_border_width_all(2)
	s.shadow_color = Color(_Colors.ACCENT_AMBER.r, _Colors.ACCENT_AMBER.g, _Colors.ACCENT_AMBER.b, 0.35)
	s.shadow_size = 6
	return s


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_kill_tween()
				_dragging = true
				_drag_moved = false
				_drag_start_x = get_global_mouse_position().x
				_drag_start_scroll = _scroll
				accept_event()
			else:
				if _dragging:
					_dragging = false
					if not _drag_moved:
						select_index(index, true)
					else:
						_snap_to_nearest()
					accept_event()
		elif mb.pressed and (
			mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			var delta := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			select_index(_focus + delta, true)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var dx := get_global_mouse_position().x - _drag_start_x
		if absf(dx) > DRAG_THRESHOLD:
			_drag_moved = true
		var step := CARD_W + CARD_GAP
		_scroll = _drag_start_scroll - dx / step
		if not _items.is_empty():
			_scroll = clampf(_scroll, 0.0, float(_items.size() - 1))
		_layout_cards()
		accept_event()


func _on_mouse_exited() -> void:
	if _dragging:
		_dragging = false
		_snap_to_nearest()


func _gui_input(event: InputEvent) -> void:
	# Background of carousel also accepts wheel / drag
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (
			mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			var delta := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			select_index(_focus + delta, true)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_kill_tween()
				_dragging = true
				_drag_moved = false
				_drag_start_x = get_global_mouse_position().x
				_drag_start_scroll = _scroll
				accept_event()
			elif _dragging:
				_dragging = false
				_snap_to_nearest()
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var dx := get_global_mouse_position().x - _drag_start_x
		if absf(dx) > DRAG_THRESHOLD:
			_drag_moved = true
		var step := CARD_W + CARD_GAP
		_scroll = _drag_start_scroll - dx / step
		if not _items.is_empty():
			_scroll = clampf(_scroll, 0.0, float(_items.size() - 1))
		_layout_cards()
		accept_event()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null


func _snap_to_nearest() -> void:
	if _items.is_empty():
		return
	var nearest := clampi(int(round(_scroll)), 0, _items.size() - 1)
	select_index(nearest, true)


func _animate_to(target: float) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(_set_scroll, _scroll, target, 0.22)


func _set_scroll(v: float) -> void:
	_scroll = v
	_layout_cards()


func _layout_cards() -> void:
	if _cards.is_empty():
		return
	var center_x := size.x * 0.5
	var center_y := size.y * 0.5
	var step := CARD_W + CARD_GAP
	for i in _cards.size():
		var card: PanelContainer = _cards[i]
		if not is_instance_valid(card):
			continue
		var offset := float(i) - _scroll
		var dist := absf(offset)
		var sc := lerpf(SCALE_FOCUS, SCALE_SIDE, clampf(dist, 0.0, 1.0))
		if dist > 1.0:
			sc = SCALE_SIDE * lerpf(1.0, 0.92, clampf(dist - 1.0, 0.0, 2.0) / 2.0)
		card.scale = Vector2(sc, sc)
		card.position = Vector2(
			center_x + offset * step - CARD_W * 0.5,
			center_y - CARD_H * 0.5 - (6.0 if dist < 0.5 else 0.0)
		)
		card.z_index = int(100.0 - dist * 10.0)
		card.modulate.a = clampf(1.15 - dist * 0.18, 0.35, 1.0)
		var is_focus := dist < 0.5
		if is_focus:
			card.add_theme_stylebox_override("panel", _style_focus)
		else:
			var muted := false
			if i < _items.size():
				muted = bool(_items[i].get("muted", false))
			card.add_theme_stylebox_override("panel", _style_muted if muted else _style_normal)
	# Keep discrete focus in sync when idle
	var tween_idle := _tween == null or not _tween.is_running()
	if not _dragging and tween_idle and not _items.is_empty():
		var nearest := clampi(int(round(_scroll)), 0, _items.size() - 1)
		if nearest != _focus:
			_focus = nearest
