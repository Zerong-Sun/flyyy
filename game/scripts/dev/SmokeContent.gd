extends SceneTree
## Headless smoke: load I18n + Audio autoloads, play one SFX, quit.
## Run: Godot --headless --path game -s res://scripts/dev/SmokeContent.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var errors: PackedStringArray = []

	var i18n := root.get_node_or_null("I18nService")
	var audio := root.get_node_or_null("AudioService")
	var data := root.get_node_or_null("DataService")
	if i18n == null:
		ok = false
		errors.append("I18nService autoload missing")
	if audio == null:
		ok = false
		errors.append("AudioService autoload missing")
	if data == null:
		ok = false
		errors.append("DataService autoload missing")

	if i18n != null:
		if not bool(i18n.get("loaded")):
			ok = false
			errors.append("I18nService not loaded")
		var city_label: String = i18n.call("t", "ui.tab.city")
		if city_label != "城市":
			ok = false
			errors.append("ui.tab.city mismatch: %s" % city_label)
		var tip: String = i18n.call("tutorial", "new_game")
		if tip.is_empty():
			ok = false
			errors.append("tutorial new_game empty")
		if str(i18n.get("attribution_body")).is_empty():
			ok = false
			errors.append("attribution empty")
		var disc: String = i18n.call("disclaimer")
		if disc.find("公开航空数据重建") < 0:
			ok = false
			errors.append("disclaimer missing")

	if audio != null:
		audio.call("play_sfx", "sfx_ui_click")
		audio.call("set_bgm", "bgm_globe_day")
		var by_id: Dictionary = audio.get("_by_id")
		if by_id.is_empty():
			ok = false
			errors.append("AudioService manifest empty")
		elif not by_id.has("bgm_globe_day"):
			ok = false
			errors.append("bgm_globe_day missing from manifest")

	if data != null:
		var cities: Dictionary = data.get("cities_by_id")
		if cities.size() != 20:
			ok = false
			errors.append("expected 20 cities, got %d" % cities.size())

	if not FileAccess.file_exists("res://assets/fonts/NotoSansSC-Regular.otf"):
		ok = false
		errors.append("NotoSansSC font missing")
	if not FileAccess.file_exists("res://themes/ThemeFactory.gd"):
		ok = false
		errors.append("ThemeFactory missing")
	else:
		var tf: GDScript = load("res://themes/ThemeFactory.gd") as GDScript
		if tf == null:
			ok = false
			errors.append("ThemeFactory load failed")
		else:
			var theme: Theme = tf.call("build") as Theme
			if theme == null or theme.default_font_size < 10:
				ok = false
				errors.append("ThemeFactory.build failed")

	if not FileAccess.file_exists("res://themes/IconFactory.gd"):
		ok = false
		errors.append("IconFactory missing")
	else:
		var icf: GDScript = load("res://themes/IconFactory.gd") as GDScript
		if icf == null:
			ok = false
			errors.append("IconFactory load failed")
		else:
			var ids: PackedStringArray = icf.call("all_ids")
			if ids.size() < 19:
				ok = false
				errors.append("IconFactory expected ≥19 icons, got %d" % ids.size())
			var tex: ImageTexture = icf.call("make_texture", "ic_flight", 24) as ImageTexture
			if tex == null:
				ok = false
				errors.append("IconFactory.make_texture failed")

	var globe_script := "res://scripts/render/GlobeController.gd"
	if not FileAccess.file_exists(globe_script):
		ok = false
		errors.append("GlobeController missing")
	else:
		var src := FileAccess.get_file_as_string(globe_script)
		for marker in ["_build_grid_overlay", "_make_pin_mesh", "_CONTINENT_BLOBS", "set_plane_on_route"]:
			if src.find(marker) < 0:
				ok = false
				errors.append("GlobeController missing %s" % marker)

	if ok:
		print("SMOKE_CONTENT_OK")
		quit(0)
	else:
		print("SMOKE_CONTENT_FAIL")
		for e in errors:
			printerr("  - ", e)
		quit(1)
