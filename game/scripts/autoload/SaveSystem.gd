extends Node

const SAVE_PATH := "user://save_demo.json"


func save_game() -> bool:
	if not AppState.game_started:
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save")
		return false
	f.store_string(JSON.stringify(AppState.to_dict()))
	f.close()
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("SaveSystem: no save file at %s" % SAVE_PATH)
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("SaveSystem: cannot open save file for reading")
		return false
	var raw := f.get_as_text()
	f.close()
	if raw.strip_edges() == "":
		push_error("SaveSystem: save file is empty")
		return false
	var json := JSON.new()
	var err := json.parse(raw)
	if err != OK:
		push_error("SaveSystem: corrupt save JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return false
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("SaveSystem: save root must be a dictionary")
		return false
	if int(data.get("save_version", 0)) > AppState.SAVE_VERSION:
		push_error("SaveSystem: save version newer than client")
		return false
	AppState.from_dict(data)
	call_deferred("_emit_game_started_after_load")
	return true


func _emit_game_started_after_load() -> void:
	EventBus.game_started.emit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
