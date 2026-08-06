extends SceneTree
## Headless audio smoke: verify every AUDIO_MANIFEST.csv entry loads a playable
## stream (BGM + SFX), and each SFX can actually be played on its bus without
## errors. This is the automated gate for "SFX 全表可播" (CAS §2 / quality-polish §4).
## Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game -s res://scripts/dev/SmokeAudio.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var errors: PackedStringArray = []

	var audio := root.get_node_or_null("AudioService")
	if audio == null:
		printerr("SMOKE_AUDIO_FAIL: AudioService autoload missing")
		quit(1)
		return

	var by_id: Dictionary = audio.get("_by_id")
	if by_id.is_empty():
		printerr("SMOKE_AUDIO_FAIL: manifest empty")
		quit(1)
		return

	var ids: Array = by_id.keys()
	ids.sort()
	for id_v in ids:
		var id := str(id_v)
		var stream: AudioStream = audio.call("_stream_for", id)
		if stream == null:
			ok = false
			errors.append("stream not loadable: %s" % id)
			continue
		# Loop flags must round-trip for loopable entries.
		var wants_loop: bool = bool(by_id[id].get("loop", false))
		if wants_loop and stream is AudioStreamOggVorbis:
			if not bool(stream.loop):
				ok = false
				errors.append("loop flag lost for %s" % id)
		# BGM entries go through set_bgm (single player); SFX through play_sfx.
		var bus: String = str(by_id[id].get("bus", "SFX"))
		if bus == "BGM":
			audio.call("set_bgm", id)
		else:
			audio.call("play_sfx", id)
		# Give the dummy driver a couple frames to consume the stream.
		await process_frame
		await process_frame

	# Loop SFX path must start/stop cleanly too.
	audio.call("set_muted", false)
	audio.call("play_loop_sfx", "sfx_coin_roll")
	await process_frame
	audio.call("stop_loop_sfx")
	audio.call("stop_bgm")

	if ok and errors.is_empty():
		print("SMOKE_AUDIO_OK (%d streams)" % ids.size())
		quit(0)
	else:
		print("SMOKE_AUDIO_FAIL")
		for e in errors:
			printerr("  - ", e)
		quit(1)
