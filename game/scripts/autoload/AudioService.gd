extends Node
## Demo audio: loads AUDIO_MANIFEST.csv, plays BGM/SFX on named buses.

const MANIFEST_PATH := "res://assets/audio/AUDIO_MANIFEST.csv"
const AUDIO_ROOT := "res://assets/audio/"
const SFX_POOL_SIZE := 6
const BGM_DUCK_DB := -6.0
const BGM_DEFAULT_LINEAR := 0.7
const SFX_DEFAULT_LINEAR := 1.0

var _by_id: Dictionary = {}  # id -> {filename, bus, loop, ...}
var _streams: Dictionary = {}  # id -> AudioStream
var _bgm_player: AudioStreamPlayer
var _sfx_pool: Array = []  # AudioStreamPlayer
var _sfx_cursor: int = 0
var _muted: bool = false
var _bgm_linear: float = BGM_DEFAULT_LINEAR
var _sfx_linear: float = SFX_DEFAULT_LINEAR
var _bgm_base_db: float = -3.0
var _ducked: bool = false


func _ready() -> void:
	_ensure_buses()
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	_load_manifest()
	set_bus_volume("BGM", _bgm_linear)
	set_bus_volume("SFX", _sfx_linear)
	set_bus_volume("UI", _sfx_linear)
	set_bus_volume("Transition", _sfx_linear)


func _ensure_buses() -> void:
	var needed := ["BGM", "SFX", "UI", "Transition"]
	for name in needed:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
	var bgm_i := AudioServer.get_bus_index("BGM")
	if bgm_i >= 0:
		_bgm_base_db = AudioServer.get_bus_volume_db(bgm_i)


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("AudioService: missing %s" % MANIFEST_PATH)
		return
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return
	var header := f.get_csv_line()
	var idx := {}
	for i in header.size():
		idx[str(header[i])] = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.is_empty() or row[0] == "" or (idx.has("id") and row[0] == "id"):
			continue
		var id := row[idx.get("id", 0)]
		var filename := row[idx.get("filename", 1)] if row.size() > 1 else ""
		var bus := row[idx.get("bus", 9)] if row.size() > 9 else "SFX"
		var loop_flag := row[idx.get("loop", 6)] if row.size() > 6 else "false"
		_by_id[id] = {
			"filename": filename,
			"bus": bus,
			"loop": str(loop_flag).to_lower() == "true",
		}


func _stream_for(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	if not _by_id.has(id):
		return null
	var rel: String = str(_by_id[id].filename)
	var path := AUDIO_ROOT + rel
	var stream: AudioStream = null
	# Prefer runtime Ogg loader (works before Godot Import generates .import)
	if path.ends_with(".ogg") and FileAccess.file_exists(path):
		stream = AudioStreamOggVorbis.load_from_file(path)
	elif ResourceLoader.exists(path):
		stream = load(path)
	if stream == null:
		push_warning("AudioService: missing stream %s" % path)
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = bool(_by_id[id].loop)
	_streams[id] = stream
	return stream


func play_sfx(id: String) -> void:
	if _muted:
		return
	var stream := _stream_for(id)
	if stream == null:
		return
	var bus := "SFX"
	if _by_id.has(id):
		bus = str(_by_id[id].get("bus", "SFX"))
	var p: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	p.bus = bus
	p.stream = stream
	p.play()
	if bus == "Transition":
		_set_bgm_ducked(true)


func set_bgm(id: String) -> void:
	var stream := _stream_for(id)
	if stream == null:
		return
	_bgm_player.stream = stream
	if not _muted:
		_bgm_player.play()


func stop_bgm() -> void:
	_bgm_player.stop()


func set_muted(on: bool) -> void:
	_muted = on
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), on)
	if on:
		_bgm_player.stop()
	elif _bgm_player.stream != null:
		_bgm_player.play()


func is_muted() -> bool:
	return _muted


func set_bus_volume(bus: String, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	if bus == "BGM":
		_bgm_linear = linear
	elif bus in ["SFX", "UI", "Transition"]:
		_sfx_linear = linear
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var db := linear_to_db(maxf(linear, 0.0001))
	if bus == "BGM":
		_bgm_base_db = db
		if _ducked:
			db += BGM_DUCK_DB
	AudioServer.set_bus_volume_db(idx, db)


func end_transition_duck() -> void:
	_set_bgm_ducked(false)


func _set_bgm_ducked(on: bool) -> void:
	_ducked = on
	var idx := AudioServer.get_bus_index("BGM")
	if idx < 0:
		return
	var db := _bgm_base_db + (BGM_DUCK_DB if on else 0.0)
	AudioServer.set_bus_volume_db(idx, db)
