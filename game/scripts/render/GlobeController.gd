extends Node3D
class_name GlobeController

const EARTH_RADIUS := 10.0

signal airport_clicked(airport_id: String)

@onready var earth: MeshInstance3D = $Earth
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var airports_root: Node3D = $Airports
@onready var routes_root: Node3D = $Routes

var _yaw := 0.5
var _pitch := 0.3
var _distance := 28.0
var _dragging := false
var _airport_nodes: Dictionary = {}
var _selected_id: String = ""


func _ready() -> void:
	_build_earth()
	_spawn_airports()
	_update_camera()
	EventBus.airport_selected.connect(_on_selected)
	EventBus.game_started.connect(_on_game_started)


func _build_earth() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = EARTH_RADIUS
	mesh.height = EARTH_RADIUS * 2.0
	mesh.radial_segments = 64
	mesh.rings = 32
	earth.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.55)
	mat.roughness = 0.85
	mat.metallic = 0.05
	earth.material_override = mat
	# Simple continent tint via second slightly smaller? Keep single sphere for Demo.


func latlon_to_vec(lat: float, lon: float, radius: float = EARTH_RADIUS) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	var x := radius * cos(la) * cos(lo)
	var y := radius * sin(la)
	var z := radius * cos(la) * sin(lo)
	return Vector3(x, y, z)


func _spawn_airports() -> void:
	for c in airports_root.get_children():
		c.queue_free()
	_airport_nodes.clear()
	for a in DataService.airports:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.4, 0.05)
		mi.material_override = mat
		var pos := latlon_to_vec(float(a.latitude), float(a.longitude), EARTH_RADIUS + 0.08)
		mi.position = pos
		mi.name = str(a.airport_id)
		airports_root.add_child(mi)
		_airport_nodes[a.airport_id] = mi


func _on_game_started() -> void:
	focus_airport(AppState.current_airport_id)


func _on_selected(airport_id: String) -> void:
	_selected_id = airport_id
	_update_markers()
	draw_routes_from(airport_id)


func focus_airport(airport_id: String) -> void:
	var a: Dictionary = DataService.get_airport(airport_id)
	if a.is_empty():
		return
	var pos := latlon_to_vec(float(a.latitude), float(a.longitude), EARTH_RADIUS)
	# Orient pivot toward airport
	_yaw = atan2(pos.z, pos.x)
	_pitch = asin(clampf(pos.y / EARTH_RADIUS, -1.0, 1.0))
	_distance = 22.0
	_update_camera()
	EventBus.airport_selected.emit(airport_id)


func _update_markers() -> void:
	for id in _airport_nodes.keys():
		var mi: MeshInstance3D = _airport_nodes[id]
		var mat: StandardMaterial3D = mi.material_override
		if id == AppState.current_airport_id:
			mat.albedo_color = Color(0.2, 1.0, 0.45)
		elif id == _selected_id:
			mat.albedo_color = Color(1.0, 0.45, 0.2)
		elif AppState.visited_airports.has(id):
			mat.albedo_color = Color(0.6, 0.85, 1.0)
		else:
			mat.albedo_color = Color(1.0, 0.85, 0.2)


func draw_routes_from(origin_id: String) -> void:
	for c in routes_root.get_children():
		c.queue_free()
	var origin: Dictionary = DataService.get_airport(origin_id)
	if origin.is_empty():
		return
	var oiata := str(origin.iata)
	for r_v in DataService.routes:
		var r: Dictionary = r_v
		if str(r.get("origin")) != oiata:
			continue
		var dest: Dictionary = {}
		for a_v in DataService.airports:
			var a: Dictionary = a_v
			if str(a.get("iata")) == str(r.get("destination")):
				dest = a
				break
		if dest.is_empty():
			continue
		_add_great_circle(origin, dest)


func draw_trip_route(origin_id: String, dest_id: String) -> void:
	for c in routes_root.get_children():
		c.queue_free()
	var o := DataService.get_airport(origin_id)
	var d := DataService.get_airport(dest_id)
	if o.is_empty() or d.is_empty():
		return
	_add_great_circle(o, d, Color(1.0, 0.55, 0.15), 0.06)


func _add_great_circle(a: Dictionary, b: Dictionary, color: Color = Color(0.4, 0.85, 1.0, 0.85), width: float = 0.035) -> void:
	var p0 := latlon_to_vec(float(a.latitude), float(a.longitude), 1.0).normalized()
	var p1 := latlon_to_vec(float(b.latitude), float(b.longitude), 1.0).normalized()
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var steps := 48
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := _slerp(p0, p1, t).normalized() * (EARTH_RADIUS + 0.15)
		imm.surface_set_color(color)
		imm.surface_add_vertex(p)
	imm.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = imm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	routes_root.add_child(mi)
	# ignore unused width in ImmediateMesh line


func _slerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	var dot := clampf(a.dot(b), -1.0, 1.0)
	var theta := acos(dot)
	if absf(theta) < 0.001:
		return a.lerp(b, t)
	var s1 := sin((1.0 - t) * theta) / sin(theta)
	var s2 := sin(t * theta) / sin(theta)
	return a * s1 + b * s2


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.2, 1.2)
	_distance = clampf(_distance, 14.0, 45.0)
	camera_pivot.rotation = Vector3(_pitch, _yaw, 0)
	camera.position = Vector3(0, 0, _distance)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				if mb.double_click:
					_try_pick()
					if _selected_id != "":
						focus_airport(_selected_id)
				else:
					_try_pick()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance -= 1.5
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance += 1.5
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch -= mm.relative.y * 0.005
		_update_camera()


func _try_pick() -> void:
	var cam := camera
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var best_id := ""
	var best_dist := 0.35
	for id in _airport_nodes.keys():
		var mi: MeshInstance3D = _airport_nodes[id]
		var to_point := mi.global_position - from
		var proj := to_point.dot(dir)
		if proj < 0:
			continue
		var closest := from + dir * proj
		var d := closest.distance_to(mi.global_position)
		if d < best_dist:
			best_dist = d
			best_id = id
	if best_id != "":
		EventBus.airport_selected.emit(best_id)
		airport_clicked.emit(best_id)
