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
		# v0.2 i18n-copy: sell feedback pools must resolve in zh_CN.csv
		for key in ["sell_console_1", "sell_console_5", "sell_console_big_loss",
				"celebration_w1_1", "celebration_w2_3",
				"sell_result_title_l2", "sell_result_title_w2",
				"sell_result_title_w2_discovery", "sell_result_milestone",
				"sell_result_continue"]:
			if not bool(i18n.call("has_key", key)):
				ok = false
				errors.append("i18n key missing: %s" % key)

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
		# v0.2 MR3: verify new BGM and SFX
		for mrid in ["bgm_market", "bgm_menu", "bgm_night",
				"sfx_loss", "sfx_loss_light", "sfx_big_win", "sfx_grand_slam", "sfx_coin_roll"]:
			if not by_id.has(mrid):
				ok = false
				errors.append("%s missing from manifest" % mrid)
		# Every manifest row should resolve to an on-disk OGG
		for aid in by_id.keys():
			var rel: String = str(by_id[aid].get("filename", ""))
			var path := "res://assets/audio/" + rel
			if not FileAccess.file_exists(path):
				ok = false
				errors.append("audio file missing for %s: %s" % [aid, path])
		audio.call("play_loop_sfx", "sfx_coin_roll")
		audio.call("stop_loop_sfx")

	if data != null:
		var cities: Dictionary = data.get("cities_by_id")
		if cities.size() < 20:
			ok = false
			errors.append("expected ≥20 cities, got %d" % cities.size())
		var tags: Dictionary = data.get("product_market_tags")
		if tags.size() < 1:
			ok = false
			errors.append("product_market_tags empty")
		var transfers: Array = data.get("_transfer_keys")
		if transfers.size() < 1:
			ok = false
			errors.append("transfer_edges empty")

	var ach := root.get_node_or_null("AchievementSystem")
	if ach == null:
		ok = false
		errors.append("AchievementSystem autoload missing")
	elif int(ach.get("definitions").size()) < 30:
		ok = false
		errors.append("AchievementSystem definitions < 30")

	if not FileAccess.file_exists("res://data/achievements.json"):
		ok = false
		errors.append("achievements.json missing")

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
			# A2 art integration: typed dirs + key loaders
			for art_path in [
				"res://assets/brand/app_icon.webp",
				"res://assets/brand/logo_mark.webp",
				"res://assets/brand/logo_wordmark_zh.webp",
				"res://assets/brand/splash.webp",
				"res://assets/icons/icon_market_32.webp",
				"res://assets/icons/achievements/icon_ach_flight_first_64.webp",
				"res://assets/products/product_generic_placeholder_64.webp",
				"res://assets/cities/city_shanghai_hero_720.webp",
				"res://assets/anim/flight_transition/anim_flight_takeoff.webp",
			]:
				if not FileAccess.file_exists(art_path) and not ResourceLoader.exists(art_path):
					ok = false
					errors.append("art missing: %s" % art_path)
			var ui_tex: Texture2D = icf.call("get_ui_icon", "ic_hot") as Texture2D
			if ui_tex == null:
				ok = false
				errors.append("get_ui_icon(ic_hot) failed")
			var hero: Texture2D = icf.call("get_city_hero", "shanghai") as Texture2D
			if hero == null:
				ok = false
				errors.append("get_city_hero(shanghai) failed")
			for mood in ["worried", "celebrating"]:
				var portrait_path := "res://assets/portraits/portrait_%s_64.png" % mood
				if not FileAccess.file_exists(portrait_path):
					ok = false
					errors.append("portrait missing: %s" % portrait_path)
				var pt: Texture2D = icf.call("get_portrait", mood) as Texture2D
				if pt == null:
					ok = false
					errors.append("get_portrait(%s) failed" % mood)
			var popup_scene: PackedScene = load("res://scenes/PopupEvent.tscn") as PackedScene
			if popup_scene == null:
				ok = false
				errors.append("PopupEvent.tscn missing")
			var ach_tex: Texture2D = icf.call("get_achievement_icon", "icon_ach_flight_first_64", true) as Texture2D
			if ach_tex == null:
				ok = false
				errors.append("get_achievement_icon failed")
			var brand: Texture2D = icf.call("get_brand", "logo") as Texture2D
			if brand == null:
				ok = false
				errors.append("get_brand(logo) failed")
			var fx: Texture2D = icf.call("get_transition_art", "takeoff") as Texture2D
			if fx == null:
				ok = false
				errors.append("get_transition_art(takeoff) failed")

	var globe_script := "res://scripts/render/GlobeController.gd"
	if not FileAccess.file_exists(globe_script):
		ok = false
		errors.append("GlobeController missing")
	else:
		var src := FileAccess.get_file_as_string(globe_script)
		for marker in ["_build_grid_overlay", "_make_pin_mesh", "earth_albedo_placeholder", "set_plane_on_route"]:
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
