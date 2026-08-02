extends Node
## Edge-case check: pressing ESC while the flights search LineEdit has focus
## should NOT close the panel (the LineEdit should consume ui_cancel to release
## focus, not trigger the panel-close shortcut).

func _ready() -> void:
	await _frames(5)
	var airports: Array = DataService.airports
	if airports.is_empty():
		print("SKIP: no airports loaded")
		get_tree().quit(0)
		return
	AppState.reset_new_game(airports[0].airport_id)
	await _frames(5)
	var MainHUD: Control = get_node("../Main/UI")
	MainHUD._show_flights()
	await _frames(10)

	var panel: Control = MainHUD.get("_panel_host")
	var query: LineEdit = MainHUD.get("_flight_query")
	if query == null or not is_instance_valid(query):
		print("SKIP: no _flight_query")
		get_tree().quit(0)
		return
	query.grab_focus()
	await _frames(2)

	var before: bool = panel.visible
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	var after: bool = panel.visible

	print("RESULT ESC-with-LineEdit-focus: before_visible=", before, " after_visible=", after)
	if before and after:
		print("PASS: panel stayed open while LineEdit had focus")
		get_tree().quit(0)
	else:
		print("FAIL: panel closed by ESC while LineEdit had focus — expected focus release first")
		get_tree().quit(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
