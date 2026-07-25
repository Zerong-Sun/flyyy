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
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	AppState.from_dict(data)
	EventBus.game_started.emit()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
