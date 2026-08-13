extends Node
## Engine-version ratchet for UTC time round-trips (GDLC Playtest #3):
## parse_iso_to_unix / _unix_to_iso / game_date_string / now_iso must be
## T-separated and UTC-stable across machine TZ (Godot 4.3+ fixed the Time
## API; this pins the contract so a future engine bump fails loudly).
## Run: Godot --headless --path game res://tests/verify_timezone.tscn

const _Tickets = preload("res://scripts/systems/TicketService.gd")

var _failures: PackedStringArray = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		print("FAIL: ", message)


func _ready() -> void:
	await get_tree().process_frame
	_check(GameClock.parse_iso_to_unix("2025-03-01T10:00:00Z") == 1740823200.0,
			"parse_iso_to_unix 2025-03-01T10:00:00Z != 1740823200")
	_check(GameClock.parse_iso_to_unix("2025-03-01T00:00:00Z") == 1740787200.0,
			"parse_iso_to_unix 2025-03-01T00:00:00Z != 1740787200")
	var saved := GameClock.unix_time
	GameClock.set("unix_time", 1740787199.0)
	_check(GameClock.game_date_string() == "2025-02-28",
			"game_date_string at 1740787199 != 2025-02-28 (midnight boundary)")
	_check(_Tickets._unix_to_iso(1740823200.0) == "2025-03-01T10:00:00Z",
			"_unix_to_iso round-trip broken: %s" % _Tickets._unix_to_iso(1740823200.0))
	GameClock.set("unix_time", 1740823200.0)
	_check(GameClock.now_iso().begins_with("2025-03-01T"),
			"now_iso must be T-separated ISO, got: %s" % GameClock.now_iso())
	GameClock.set("unix_time", saved)
	if _failures.is_empty():
		print("VERIFY_TIMEZONE_OK")
		get_tree().quit(0)
	else:
		print("VERIFY_TIMEZONE_FAIL")
		get_tree().quit(1)
