extends Node2D
class_name FeedbackParticles

## FeedbackParticles — parameterized transient particle effects for sell feedback.
## Call FeedbackParticles.play(config) to spawn and auto-free after duration.

static func play(parent: Node, config: Dictionary) -> void:
	var particles := FeedbackParticles.new()
	particles._config = config
	parent.add_child(particles)
	particles._start()

var _config: Dictionary = {}
var _elapsed: float = 0.0

func _start() -> void:
	var count: int = int(_config.get("count", 20))
	var palette: String = str(_config.get("palette", "gold"))
	var duration: float = float(_config.get("duration", 2.0))
	var direction: String = str(_config.get("direction", "right_arc"))

	for i in range(count):
		var dot := ColorRect.new()
		dot.size = Vector2(8, 8)
		match palette:
			"grey":
				dot.color = Color(0.5, 0.5, 0.5, 0.7)
			"gold", "gold_rain":
				dot.color = Color(1.0, 0.84, 0.0, 0.85)
		add_child(dot)

		var start_pos := Vector2(0, 0)
		match direction:
			"down":
				start_pos = Vector2(randf_range(100, 900), 0)
			"right_arc":
				start_pos = Vector2(800, randf_range(200, 600))

		dot.position = start_pos

		var tween := create_tween()
		tween.tween_property(dot, "position", start_pos + Vector2(randf_range(-100, 100), randf_range(200, 500)), duration)
		tween.parallel().tween_property(dot, "modulate:a", 0.0, duration)

	# Gold flash overlay for W2
	if palette == "gold_rain":
		var flash := ColorRect.new()
		flash.color = Color(1.0, 0.84, 0.0, 0.3)
		flash.size = get_viewport().get_visible_rect().size
		flash.position = Vector2.ZERO
		add_child(flash)
		var flash_tween := create_tween()
		flash_tween.tween_property(flash, "modulate:a", 0.0, 0.5)

	# Auto-free after longest tween completes
	await get_tree().create_timer(duration + 0.05).timeout
	queue_free()
