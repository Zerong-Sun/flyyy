extends Control
## Opening loading page: presents the poem while the main scene loads in a thread.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const MIN_DISPLAY_SECONDS := 4.0
const _Colors = preload("res://themes/DemoColors.gd")

var _elapsed: float = 0.0
var _load_requested: bool = false
var _transitioning: bool = false
var _progress_bar: ProgressBar
var _status_label: Label
var _poem_scroll: ScrollContainer
var _auto_scroll := true
var _scroll_accum: float = 0.0


func _ready() -> void:
	_build_ui()
	modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, 0.45)
	var err := ResourceLoader.load_threaded_request(MAIN_SCENE_PATH)
	if err != OK:
		_show_error()
		return
	_load_requested = true


func _process(delta: float) -> void:
	if not _load_requested or _transitioning:
		return
	_auto_scroll_poem(delta)
	_elapsed += delta
	var load_progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, load_progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var resource_progress := 0.0
			if not load_progress.is_empty():
				resource_progress = float(load_progress[0])
			var time_progress := minf(_elapsed / MIN_DISPLAY_SECONDS, 0.95)
			_progress_bar.value = maxf(resource_progress, time_progress) * 100.0
		ResourceLoader.THREAD_LOAD_LOADED:
			_progress_bar.value = minf(_elapsed / MIN_DISPLAY_SECONDS, 1.0) * 100.0
			if _elapsed >= MIN_DISPLAY_SECONDS:
				_finish_loading()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_error()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = _Colors.BG_DEEP
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var content := VBoxContainer.new()
	content.anchor_left = 0.5
	content.anchor_right = 0.5
	content.anchor_top = 0.5
	content.anchor_bottom = 0.5
	content.offset_left = -380.0
	content.offset_right = 380.0
	content.offset_top = -250.0
	content.offset_bottom = 250.0
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	add_child(content)

	var game_title := Label.new()
	game_title.text = I18nService.t("ui.new_game.game_title")
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.add_theme_font_size_override("font_size", 34)
	game_title.add_theme_color_override("font_color", _Colors.ICE)
	content.add_child(game_title)

	var poem_title := Label.new()
	poem_title.text = I18nService.t("ui.loading.poem_title")
	poem_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	poem_title.add_theme_font_size_override("font_size", 18)
	poem_title.add_theme_color_override("font_color", _Colors.ACCENT_TEAL)
	content.add_child(poem_title)

	_poem_scroll = ScrollContainer.new()
	_poem_scroll.custom_minimum_size = Vector2(0, 300)
	_poem_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_poem_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_poem_scroll.scroll_ended.connect(_on_poem_scroll_ended)
	content.add_child(_poem_scroll)

	var poem := Label.new()
	poem.text = I18nService.t("ui.loading.poem").replace("\\n", "\n")
	poem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	poem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	poem.custom_minimum_size = Vector2(736, 0)
	poem.add_theme_font_size_override("font_size", 17)
	poem.add_theme_constant_override("line_spacing", 8)
	poem.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	_poem_scroll.add_child(poem)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	content.add_child(spacer)

	_status_label = Label.new()
	_status_label.text = I18nService.t("ui.loading.status")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", _Colors.TEXT_SECONDARY)
	content.add_child(_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 8)
	_progress_bar.show_percentage = false
	_progress_bar.value = 0.0
	content.add_child(_progress_bar)


func _finish_loading() -> void:
	_transitioning = true
	var packed = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH)
	if not packed is PackedScene:
		_show_error()
		return
	var fade_out := create_tween()
	fade_out.tween_property(self, "modulate:a", 0.0, 0.35)
	await fade_out.finished
	get_tree().change_scene_to_packed(packed as PackedScene)


func _show_error() -> void:
	_load_requested = false
	_transitioning = false
	_status_label.text = I18nService.t("ui.loading.error")
	_status_label.add_theme_color_override("font_color", _Colors.WARN_RED)


## Gently scrolls the full poem while loading; loops back to the top so the
## text keeps moving on slow machines. Stops once the user scrolls manually.
func _auto_scroll_poem(delta: float) -> void:
	if not _auto_scroll or _poem_scroll == null:
		return
	_scroll_accum += 55.0 * delta
	var step := int(_scroll_accum)
	_scroll_accum -= step
	_poem_scroll.scroll_vertical += step
	var max_scroll := int(_poem_scroll.get_v_scroll_bar().max_value)
	if max_scroll > 0 and _poem_scroll.scroll_vertical >= max_scroll:
		_poem_scroll.scroll_vertical = 0


func _on_poem_scroll_ended() -> void:
	_auto_scroll = false
