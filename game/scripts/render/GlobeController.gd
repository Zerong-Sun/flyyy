extends Node3D
class_name GlobeController
## Demo globe: code-generated earth albedo, pin markers, lat/lon grid, plane tip.

const EARTH_RADIUS := 10.0
const GRID_RADIUS := 10.08
const PIN_HEIGHT := 0.42

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
var _label_nodes: Dictionary = {}
var _selected_id: String = ""
var _routes_origin_id: String = ""
var _routes_visible: bool = false
var _grid_mi: MeshInstance3D
var _plane_mi: MeshInstance3D
var _plane_visible_for_trip: bool = false

# Earth texture is pre-rendered by tools/generate_earth_placeholder.py and loaded from disk.


func _ready() -> void:
	_build_earth()
	_build_grid_overlay()
	_spawn_airports()
	_build_plane_marker()
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
	mat.roughness = 0.9
	mat.metallic = 0.0
	var tex_path := "res://assets/earth/earth_albedo_day_2k.png"
	if not ResourceLoader.exists(tex_path):
		tex_path = "res://assets/earth/earth_albedo_placeholder.png"
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		if tex:
			mat.albedo_texture = tex
			earth.material_override = mat
			return
	# Fallback: minimal-gradient sphere (no procedural generation at runtime)
	push_warning("GlobeController: earth texture missing at %s, using fallback gradient" % tex_path)
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.12, 0.42, 0.55))
	img.set_pixel(1, 0, Color(0.38, 0.36, 0.24))
	var fallback := ImageTexture.create_from_image(img)
	mat.albedo_texture = fallback
	earth.material_override = mat


func _build_grid_overlay() -> void:
	var imm := ImmediateMesh.new()
	var grid_color := Color(0.85, 0.92, 0.98, 0.22)
	# Meridians every 15°
	for lon_i in range(-180, 180, 15):
		imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for lat_i in range(-90, 91, 3):
			var p := latlon_to_vec(float(lat_i), float(lon_i), GRID_RADIUS)
			imm.surface_set_color(grid_color)
			imm.surface_add_vertex(p)
		imm.surface_end()
	# Parallels every 15°
	for lat_i in range(-75, 76, 15):
		imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for lon_i in range(-180, 181, 3):
			var p2 := latlon_to_vec(float(lat_i), float(lon_i), GRID_RADIUS)
			imm.surface_set_color(grid_color)
			imm.surface_add_vertex(p2)
		imm.surface_end()
	_grid_mi = MeshInstance3D.new()
	_grid_mi.name = "GridOverlay"
	_grid_mi.mesh = imm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 1)
	_grid_mi.material_override = mat
	add_child(_grid_mi)
	_update_grid_fade()


func _update_grid_fade() -> void:
	if _grid_mi == null or _grid_mi.material_override == null:
		return
	# Far: faint; near: more visible (CAS: 远景淡、近景显)
	var t := inverse_lerp(45.0, 14.0, _distance)
	var alpha := lerpf(0.08, 0.35, clampf(t, 0.0, 1.0))
	var mat := _grid_mi.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.85, 0.92, 0.98, alpha)


const LON_OFFSET_DEG := 180.0  # align texture lon=-180 (U=0) with SphereMesh seam at +Z

func latlon_to_vec(lat: float, lon: float, radius: float = EARTH_RADIUS) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon + LON_OFFSET_DEG)
	var x := radius * cos(la) * sin(lo)
	var y := radius * sin(la)
	var z := radius * cos(la) * cos(lo)
	return Vector3(x, y, z)


func _make_pin_mesh() -> ArrayMesh:
	## Low-poly map pin: stem cylinder + round head (≤200 tris target).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_cylinder(st, 0.04, 0.04, 0.28, 8, Vector3(0, 0.14, 0))
	_add_icosphere(st, 0.11, Vector3(0, 0.34, 0))
	st.generate_normals()
	return st.commit()


func _add_cylinder(st: SurfaceTool, r_bottom: float, r_top: float, height: float, sides: int, center: Vector3) -> void:
	var y0 := center.y - height * 0.5
	var y1 := center.y + height * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * r_bottom, y0, sin(a0) * r_bottom)
		var b1 := Vector3(cos(a1) * r_bottom, y0, sin(a1) * r_bottom)
		var t0 := Vector3(cos(a0) * r_top, y1, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, y1, sin(a1) * r_top)
		# Side
		st.add_vertex(b0)
		st.add_vertex(t0)
		st.add_vertex(t1)
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(b1)
	# Caps (simple fan)
	var bc := Vector3(0, y0, 0)
	var tc := Vector3(0, y1, 0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * r_bottom, y0, sin(a0) * r_bottom)
		var b1 := Vector3(cos(a1) * r_bottom, y0, sin(a1) * r_bottom)
		st.add_vertex(bc)
		st.add_vertex(b1)
		st.add_vertex(b0)
		var t0 := Vector3(cos(a0) * r_top, y1, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, y1, sin(a1) * r_top)
		st.add_vertex(tc)
		st.add_vertex(t0)
		st.add_vertex(t1)


func _add_icosphere(st: SurfaceTool, radius: float, center: Vector3) -> void:
	## Lat/lon UV sphere (low rings) as pin head.
	var rings := 6
	var segs := 8
	for r in rings:
		var v0 := float(r) / float(rings)
		var v1 := float(r + 1) / float(rings)
		var lat0 := lerpf(-PI * 0.5, PI * 0.5, v0)
		var lat1 := lerpf(-PI * 0.5, PI * 0.5, v1)
		for s in segs:
			var u0 := float(s) / float(segs)
			var u1 := float(s + 1) / float(segs)
			var lon0 := u0 * TAU
			var lon1 := u1 * TAU
			var p00 := center + Vector3(cos(lat0) * cos(lon0), sin(lat0), cos(lat0) * sin(lon0)) * radius
			var p01 := center + Vector3(cos(lat0) * cos(lon1), sin(lat0), cos(lat0) * sin(lon1)) * radius
			var p10 := center + Vector3(cos(lat1) * cos(lon0), sin(lat1), cos(lat1) * sin(lon0)) * radius
			var p11 := center + Vector3(cos(lat1) * cos(lon1), sin(lat1), cos(lat1) * sin(lon1)) * radius
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)


func _spawn_airports() -> void:
	for c in airports_root.get_children():
		c.queue_free()
	_airport_nodes.clear()
	_label_nodes.clear()
	var pin_mesh := _make_pin_mesh()
	for a in DataService.airports:
		var mi := MeshInstance3D.new()
		mi.mesh = pin_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.58, 0.62)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.1, 0.12)
		mat.emission_energy_multiplier = 0.6
		mi.material_override = mat
		var pos := latlon_to_vec(float(a.latitude), float(a.longitude), EARTH_RADIUS + 0.02)
		mi.position = pos
		# Orient pin: local +Y points outward from globe
		var outward := pos.normalized()
		var tangent := Vector3.UP.cross(outward)
		if tangent.length_squared() < 0.001:
			tangent = Vector3.RIGHT.cross(outward)
		tangent = tangent.normalized()
		var bitangent := outward.cross(tangent).normalized()
		mi.basis = Basis(tangent, outward, bitangent)
		mi.name = str(a.airport_id)
		airports_root.add_child(mi)
		_airport_nodes[a.airport_id] = mi
		var lab := Label3D.new()
		lab.text = str(a.get("iata", ""))
		lab.font_size = 48
		lab.pixel_size = 0.008
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = pos.normalized() * (EARTH_RADIUS + 0.55)
		lab.visible = false
		lab.modulate = Color(1, 0.95, 0.7)
		airports_root.add_child(lab)
		_label_nodes[a.airport_id] = lab


func _build_plane_marker() -> void:
	## Tiny triangle stand-in for ICON_PLANE_TINY (CAS §1.2.B).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.28, 0, 0)
	var left := Vector3(-0.16, 0, 0.12)
	var right := Vector3(-0.16, 0, -0.12)
	var top := Vector3(-0.05, 0.08, 0)
	# Top face
	st.add_vertex(tip)
	st.add_vertex(left)
	st.add_vertex(top)
	st.add_vertex(tip)
	st.add_vertex(top)
	st.add_vertex(right)
	# Bottom
	st.add_vertex(tip)
	st.add_vertex(right)
	st.add_vertex(left)
	st.generate_normals()
	_plane_mi = MeshInstance3D.new()
	_plane_mi.name = "PlaneMarker"
	_plane_mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.7, 0.2)
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plane_mi.material_override = mat
	_plane_mi.visible = false
	add_child(_plane_mi)


func set_plane_on_route(origin: Dictionary, dest: Dictionary, t: float = 0.5) -> void:
	if origin.is_empty() or dest.is_empty():
		_plane_mi.visible = false
		_plane_visible_for_trip = false
		return
	var p0 := latlon_to_vec(float(origin.latitude), float(origin.longitude), 1.0).normalized()
	var p1 := latlon_to_vec(float(dest.latitude), float(dest.longitude), 1.0).normalized()
	var p := _slerp(p0, p1, clampf(t, 0.0, 1.0)).normalized()
	_plane_mi.position = p * (EARTH_RADIUS + 0.35)
	var ahead := _slerp(p0, p1, clampf(t + 0.02, 0.0, 1.0)).normalized()
	var tangent := (ahead - p).normalized()
	if tangent.length_squared() > 0.0001:
		_plane_mi.look_at(_plane_mi.position + tangent, p)
	_plane_mi.visible = true
	_plane_visible_for_trip = true


func clear_plane_marker() -> void:
	if _plane_mi:
		_plane_mi.visible = false
	_plane_visible_for_trip = false


func _on_game_started() -> void:
	focus_airport(AppState.current_airport_id)


func _on_selected(airport_id: String) -> void:
	_selected_id = airport_id
	_update_markers()
	draw_routes_from(airport_id)


func set_routes_visible(show_routes: bool) -> void:
	if show_routes:
		if _selected_id != "":
			draw_routes_from(_selected_id)
	else:
		clear_routes()


func toggle_routes() -> bool:
	if _routes_visible:
		clear_routes()
		return false
	if _selected_id != "":
		draw_routes_from(_selected_id)
	return _routes_visible


func focus_airport(airport_id: String) -> void:
	var a: Dictionary = DataService.get_airport(airport_id)
	if a.is_empty():
		return
	var pos := latlon_to_vec(float(a.latitude), float(a.longitude), EARTH_RADIUS)
	_yaw = atan2(pos.z, pos.x)
	_pitch = asin(clampf(pos.y / EARTH_RADIUS, -1.0, 1.0))
	_distance = 22.0
	_update_camera()
	EventBus.airport_selected.emit(airport_id)


func _update_markers() -> void:
	for id in _airport_nodes.keys():
		var mi: MeshInstance3D = _airport_nodes[id]
		var mat: StandardMaterial3D = mi.material_override
		var lab: Label3D = _label_nodes.get(id)
		var show_label: bool = id == _selected_id or id == AppState.current_airport_id
		if lab:
			lab.visible = show_label
		if id == AppState.current_airport_id:
			mat.albedo_color = Color(0.2, 1.0, 0.45)
			mat.emission = Color(0.1, 0.5, 0.2)
		elif id == _selected_id:
			mat.albedo_color = Color(1.0, 0.45, 0.2)
			mat.emission = Color(0.6, 0.2, 0.05)
		elif AppState.visited_airports.has(id):
			mat.albedo_color = Color(1.0, 0.85, 0.2)
			mat.emission = Color(0.6, 0.4, 0.05)
		else:
			mat.albedo_color = Color(0.55, 0.58, 0.62)
			mat.emission = Color(0.1, 0.1, 0.12)


func clear_routes() -> void:
	for c in routes_root.get_children():
		c.queue_free()
	_routes_visible = false
	_routes_origin_id = ""
	if not _plane_visible_for_trip:
		clear_plane_marker()


func draw_routes_from(origin_id: String) -> void:
	clear_routes()
	clear_plane_marker()
	var origin: Dictionary = DataService.get_airport(origin_id)
	if origin.is_empty():
		return
	var oiata := str(origin.get("iata", "")).to_upper()
	if oiata == "":
		return
	var drawn := 0
	for r_v in DataService.routes:
		var r: Dictionary = r_v
		var dest_iata := str(r.get("destination", "")).to_upper()
		if str(r.get("origin", "")).to_upper() != oiata:
			continue
		if dest_iata == "" or dest_iata == oiata:
			continue  # no self-loops
		var dest: Dictionary = DataService.get_airport_by_iata(dest_iata)
		if dest.is_empty():
			continue
		_add_great_circle(origin, dest)
		drawn += 1
		if drawn >= 24:
			break
	_routes_origin_id = origin_id
	_routes_visible = drawn > 0


func draw_trip_route(origin_id: String, dest_id: String) -> void:
	clear_routes()
	var o := DataService.get_airport(origin_id)
	var d := DataService.get_airport(dest_id)
	if o.is_empty() or d.is_empty():
		return
	if str(o.get("airport_id", "")) == str(d.get("airport_id", "")):
		return
	_add_great_circle(o, d, Color(1.0, 0.55, 0.15), 0.06)
	set_plane_on_route(o, d, 0.35)
	_routes_origin_id = origin_id
	_routes_visible = true


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
	var _w := width  # reserved for thicker ribbons later


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
	_update_grid_fade()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				var picked := _pick_nearest_airport_id()
				if mb.double_click:
					# Double-click: select + camera focus on the hit airport.
					if picked != "":
						focus_airport(picked)
						airport_clicked.emit(picked)
				elif picked != "":
					EventBus.airport_selected.emit(picked)
					airport_clicked.emit(picked)
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


func _pick_nearest_airport_id() -> String:
	var cam := camera
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var best_id := ""
	var best_dist := 0.45
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
	return best_id
