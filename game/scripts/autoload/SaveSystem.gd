extends Node
## Validated saves, atomic replacement and one last-known-good recovery copy.
const SAVE_PATH := "user://save_demo.json"
var _blocked_paths: Dictionary = {}
var _dirty: bool = false
var _cooldown: float = 0.0
var flight_in_progress: bool = false

func _ready() -> void:
	EventBus.cash_changed.connect(_schedule)
	EventBus.inventory_changed.connect(_schedule)
	EventBus.ticket_purchased.connect(_schedule)
	EventBus.game_started.connect(_schedule)

func _schedule() -> void:
	_dirty = true
	_cooldown = 0.8

func _process(delta: float) -> void:
	if not _dirty or flight_in_progress:
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_dirty = false
		if AppState.game_started and not _blocked_paths.has(_path_for(AppState.game_mode)) and not save_game():
			EventBus.tutorial_hint.emit("存档失败，上一份存档已保留，请重试。")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if AppState.game_started and not flight_in_progress:
			save_game()


func _path_for(mode: String) -> String:
	if mode == "challenge":
		return "user://save_challenge.json"
	if mode == "collector":
		return "user://save_collector.json"
	return SAVE_PATH

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func validate(data: Variant) -> Dictionary:
	if not data is Dictionary or not _number(data.get("save_version", 0)):
		return {}
	if float(data.get("save_version", 0)) != floor(float(data.get("save_version", 0))) or float(data.get("save_version", 0)) < 0 or int(data.get("save_version", 0)) > AppState.SAVE_VERSION:
		return {}
	if not _number(data.get("cash_usd")) or float(data.cash_usd) < 0:
		return {}
	if not data.get("current_airport_id") is String or DataService.get_airport(data.current_airport_id).is_empty():
		return {}
	var defaults: Dictionary = AppState.to_dict()
	var clean: Dictionary = {}
	for key in data:
		if not defaults.has(key):
			continue
		var v: Variant = data[key]
		var expected: Variant = defaults[key]
		if typeof(expected) in [TYPE_FLOAT, TYPE_INT]:
			if not _number(v):
				return {}
		elif typeof(v) != typeof(expected):
			return {}
		clean[key] = v
	for row in clean.get("inventory", []):
		if not row is Dictionary or not row.get("product_id") is String or DataService.get_product(row.product_id).is_empty():
			return {}
		for key in ["qty", "unit_cost", "purchased_unix"]:
			if not _number(row.get(key)) or float(row[key]) < 0:
				return {}
		if float(row.qty) != floor(float(row.qty)) or row.qty <= 0 or row.qty > 1000000:
			return {}
		for key in ["quality", "cold_protected_hours"]:
			if row.has(key) and not _number(row[key]):
				return {}
		if row.has("in_cargo") and not row.in_cargo is bool:
			return {}
	for key in ["visited_airports", "visited_cities", "visited_countries", "tutorial_flags", "unlocked_achievements"]:
		for value in clean.get(key, {}).values():
			if not value is bool:
				return {}
	for ticket in clean.get("held_tickets", []):
		if not ticket is Dictionary:
			return {}
		for key in ["origin_airport_id", "destination_airport_id"]:
			if not ticket.get(key) is String or DataService.get_airport(ticket[key]).is_empty():
				return {}
		for key in ["scheduled_departure_utc", "scheduled_arrival_utc"]:
			if not _valid_utc(ticket.get(key)):
				return {}
		if GameClock.parse_iso_to_unix(ticket.scheduled_arrival_utc) < GameClock.parse_iso_to_unix(ticket.scheduled_departure_utc):
			return {}
		for key in ["is_connection_leg", "enables_cold_chain", "cargo_promotion_applied"]:
			if ticket.has(key) and not ticket[key] is bool:
				return {}
		for key in ["total_paid", "ledger_paid", "ticket_price", "duration_minutes", "distance_km", "extra_kg", "cargo_kg", "cargo_blocks", "stops"]:
			if ticket.has(key) and (not _number(ticket[key]) or float(ticket[key]) < 0):
				return {}
		if float(ticket.get("ledger_paid", 0)) > float(ticket.get("total_paid", 0)):
			return {}
		for key in ["flight_instance_id", "marketing_flight_number", "airline_name", "cabin", "origin_iata", "destination_iata"]:
			if ticket.has(key) and not ticket[key] is String:
				return {}
		for key in ["connection_leg", "mct_minutes", "layover_minutes"]:
			if ticket.has(key) and (not _number(ticket[key]) or float(ticket[key]) < 0):
				return {}
		if ticket.has("stop_airports"):
			if not ticket.stop_airports is Array:
				return {}
			for stop in ticket.stop_airports:
				if not stop is String:
					return {}
	for key in ["travel_log", "sell_transactions"]:
		for row in clean.get(key, []):
			if not row is Dictionary:
				return {}
	for tx in clean.get("sell_transactions", []):
		for key in ["sell_city", "product_id"]:
			if tx.has(key) and not tx[key] is String:
				return {}
		for key in ["qty", "total_revenue", "total_unit_cost", "margin", "timestamp"]:
			if tx.has(key) and not _number(tx[key]):
				return {}
	for row in clean.get("travel_log", []):
		for key in ["distance", "ticket_price", "cargo_value", "profit_after_arrival", "cash_on_arrival", "stops"]:
			if row.has(key) and not _number(row[key]):
				return {}
	var challenge: Dictionary = clean.get("challenge", {})
	for key in ["start_unix", "deadline_unix"]:
		if challenge.has(key) and not _number(challenge[key]):
			return {}
	if challenge.has("result") and not challenge.result is Dictionary:
		return {}
	if challenge.has("ended") and not challenge.ended is bool:
		return {}
	for key in challenge.get("result", {}):
		var value: Variant = challenge.result[key]
		if key == "grade":
			if not value is String:
				return {}
		elif not _number(value):
			return {}
	for value in clean.get("demand_pressure", {}).values():
		if not _number(value) or value < 0 or value > 1:
			return {}
	var stats: Dictionary = clean.get("stats", {})
	for key in stats:
		if not defaults.stats.has(key):
			continue
		if defaults.stats[key] is Dictionary:
			if not stats[key] is Dictionary:
				return {}
			for value in stats[key].values():
				if key == "extreme_airports":
					if not value is String:
						return {}
				elif not value is bool:
					return {}
		elif not _number(stats[key]):
			return {}
	if clean.get("game_mode", "sandbox") not in ["sandbox", "challenge", "collector"]:
		return {}
	return clean

func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return null
	return json.data

func save_game() -> bool:
	if not AppState.game_started or flight_in_progress:
		return false
	var data := AppState.to_dict()
	if validate(data).is_empty():
		push_warning("SaveSystem: state validation failed; previous save retained")
		return false
	var path := _path_for(AppState.game_mode)
	# Check both copies on every write, even when the player never selected Load.
	for candidate in [path, path + ".bak"]:
		if _is_newer(_read(candidate)):
			_blocked_paths[path] = true
			return false
	_blocked_paths.erase(path)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or validate(_read(temporary)).is_empty():
		return false
	if not validate(_read(path)).is_empty():
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak")) != OK:
			return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) == OK

func load_game() -> bool:
	var path := _path_for(AppState.game_mode)
	var raw: Variant = _read(path)
	if _is_newer(raw) or _is_newer(_read(path + ".bak")):
		_blocked_paths[path] = true
		push_warning("SaveSystem: newer save preserved; update the game before saving")
		return false
	_blocked_paths.erase(path)
	var data := validate(raw)
	if data.is_empty():
		data = validate(_read(path + ".bak"))
		if data.is_empty():
			return false
		push_warning("SaveSystem: recovered last-known-good backup")
	AppState.from_dict(data)
	call_deferred("_emit_game_started_after_load")
	return true

func _emit_game_started_after_load() -> void:
	EventBus.game_started.emit()

func has_save(mode: String = "") -> bool:
	var path := _path_for(mode if mode != "" else AppState.game_mode)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")

func _is_newer(raw: Variant) -> bool:
	return raw is Dictionary and _number(raw.get("save_version")) and raw.save_version > AppState.SAVE_VERSION

func _valid_utc(value: Variant) -> bool:
	if not value is String:
		return false
	var pattern := RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?$")
	if pattern.search(value) == null:
		return false
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	if year < 1970 or month < 1 or month > 12:
		return false
	var days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day >= 1 and day <= int(days[month - 1]) and int(value.substr(11, 2)) < 24 and int(value.substr(14, 2)) < 60 and int(value.substr(17, 2)) < 60
