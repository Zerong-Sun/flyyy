extends Node
## UTC game clock. 1 real second = 6 game minutes (360x).

const GAME_MINUTES_PER_REAL_SECOND := 6.0
const BASELINE_UNIX := 1740787200  # 2025-03-01 00:00:00 UTC

var unix_time: float = BASELINE_UNIX
var paused: bool = true  # paused until new game starts
var _focus_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if paused or _focus_paused:
		return
	unix_time += delta * GAME_MINUTES_PER_REAL_SECOND * 60.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_paused = true
		EventBus.clock_paused_changed.emit(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_paused = false
		EventBus.clock_paused_changed.emit(paused)


func start_clock() -> void:
	paused = false


func set_paused(p: bool) -> void:
	paused = p
	EventBus.clock_paused_changed.emit(paused or _focus_paused)


func jump_to_unix(t: float) -> void:
	unix_time = max(unix_time, t)


func add_minutes(m: float) -> void:
	unix_time += m * 60.0


func now_iso() -> String:
	return Time.get_datetime_string_from_unix_time(int(unix_time), true) + "Z"


func game_date_string() -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func format_local(tz_name: String) -> String:
	var off: float = offset_hours_for(tz_name)
	var local_unix := unix_time + off * 3600.0
	return Time.get_datetime_string_from_unix_time(int(local_unix), true)


func local_hour_for(tz_name: String) -> int:
	var off: float = offset_hours_for(tz_name)
	return int(fposmod((unix_time + off * 3600.0) / 3600.0, 24.0))


func offset_hours_for(tz_name: String) -> float:
	var table: Dictionary = DataService.tz_offsets.get(tz_name, {})
	var d: String = game_date_string()
	if table.has(d):
		return float(table[d])
	# nearest known day or fixed fallback
	if not table.is_empty():
		var keys: Array = table.keys()
		keys.sort()
		if d < str(keys[0]):
			return float(table[keys[0]])
		return float(table[keys[keys.size() - 1]])
	return _fallback_offset_hours(tz_name)


func _fallback_offset_hours(tz_name: String) -> float:
	match tz_name:
		"America/New_York":
			return -4.0
		"America/Chicago":
			return -5.0
		"America/Denver":
			return -6.0
		"America/Los_Angeles":
			return -7.0
		"Europe/London":
			return 0.0
		"Europe/Paris", "Europe/Amsterdam", "Europe/Berlin":
			return 1.0
		"Europe/Istanbul":
			return 3.0
		"Asia/Dubai":
			return 4.0
		"Asia/Bangkok":
			return 7.0
		"Asia/Shanghai", "Asia/Singapore", "Asia/Hong_Kong":
			return 8.0
		"Asia/Tokyo", "Asia/Seoul":
			return 9.0
		_:
			return 0.0


func parse_iso_to_unix(iso: String) -> float:
	var s := iso.strip_edges().trim_suffix("Z")
	var parts := s.split("T")
	if parts.size() != 2:
		return unix_time
	var d := parts[0].split("-")
	var t := parts[1].split(":")
	if d.size() < 3 or t.size() < 2:
		return unix_time
	var dict := {
		"year": int(d[0]),
		"month": int(d[1]),
		"day": int(d[2]),
		"hour": int(t[0]),
		"minute": int(t[1]),
		"second": int(float(t[2])) if t.size() > 2 else 0,
	}
	return float(Time.get_unix_time_from_datetime_dict(dict))
