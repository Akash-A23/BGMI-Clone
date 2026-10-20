extends Node3D
## World builder + match manager.
## Builds the terrain, trees, rocks, houses, loot, zone, player and bots entirely in code.

const HALF := 160.0          # half the map size (metres)
const RES := 120             # terrain grid resolution
const PAD_R := 13.0          # flattened ground around each house
const BOT_COUNT := 11
const ZONE_START := 140.0
const ZONE_END := 12.0
const ZONE_DELAY := 40.0
const ZONE_SHRINK_TIME := 300.0

var noise: FastNoiseLite
var pads: Array[Vector3] = []
var obstacles: Array[Vector3] = []
var nav: NavigationRegion3D
var player: Player
var hud: Hud
var zone_mesh: MeshInstance3D

var nav_ready := false
var started := false
var running := false
var match_over := false
var ui_open := false
var countdown := 3.0
var counting := false
var match_time := 0.0
var zone_center := Vector2.ZERO
var zone_radius := ZONE_START
var zone_tick := 0.0


func _ready() -> void:
	randomize()
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.007
	noise.fractal_octaves = 3
	zone_center = Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))

	_make_environment()
	_pick_pads()
	nav = NavigationRegion3D.new()
	add_child(nav)
	_build_terrain()
	_build_trees()
	_build_rocks()
	_build_buildings()
	_build_boundary()
	_build_zone_visual()

	hud = Hud.new()
	hud.game = self
	add_child(hud)

	_scatter_loot()
	_spawn_player()
	_spawn_bots()
	hud.set_center("Generating map...")
	_bake_nav()


# ------------------------------------------------------------ environment
func _make_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.0015
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


# ----------------------------------------------------------------- terrain
func raw_height(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * 18.0
	var r := Vector2(x, z).length()
	h += smoothstep(HALF * 0.75, HALF, r) * 25.0
	return h


func height_at(x: float, z: float) -> float:
	var h := raw_height(x, z)
	for p in pads:
		var d := Vector2(x - p.x, z - p.z).length()
		var t := 1.0 - smoothstep(PAD_R * 0.7, PAD_R, d)
		if t > 0.0:
			h = lerpf(h, p.y, t)
	return h


func road_dist(x: float, z: float) -> float:
	var d1 := absf(x - sin(z * 0.02) * 30.0)
	var d2 := absf(z - cos(x * 0.025) * 25.0)
	return minf(d1, d2)


func near_pad(x: float, z: float, r: float) -> bool:
	for p in pads:
		if Vector2(x - p.x, z - p.z).length() < r:
			return true
	return false


func _pick_pads() -> void:
	var tries := 0
	while pads.size() < 9 and tries < 800:
		tries += 1
		var x := randf_range(-105.0, 105.0)
		var z := randf_range(-105.0, 105.0)
		if road_dist(x, z) < 10.0:
			continue
		var ok := true
		for p in pads:
			if Vector2(x - p.x, z - p.z).length() < 45.0:
				ok = false
		var h := raw_height(x, z)
		if ok and h < 12.0 and h > -4.0:
			pads.append(Vector3(x, h, z))


func _terrain_color(x: float, z: float, h: float) -> Color:
	var e := 1.5
	var slope := (absf(height_at(x + e, z) - height_at(x - e, z)) + absf(height_at(x, z + e) - height_at(x, z - e))) / (2.0 * e)
	if road_dist(x, z) < 3.5:
		return Color(0.38, 0.35, 0.32)
	if slope > 0.75 or h > 22.0:
		return Color(0.42, 0.4, 0.38)
	if h < -5.0:
		return Color(0.76, 0.7, 0.46)
	var v := noise.get_noise_2d(x * 6.0, z * 6.0) * 0.07
	return Color(0.27 + v, 0.5 + v, 0.2 + v * 0.5)


func _build_terrain() -> void:
	var step := HALF * 2.0 / RES
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RES + 1:
		for i in RES + 1:
			var x := -HALF + i * step
			var z := -HALF + j * step
			var h := height_at(x, z)
			st.set_color(_terrain_color(x, z, h))
			st.add_vertex(Vector3(x, h, z))
	for j in RES:
		for i in RES:
			var a := j * (RES + 1) + i
			var b := a + 1
			var c := a + RES + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	nav.add_child(body)


func _build_trees() -> void:
	var trunk_xf: Array[Transform3D] = []
	var leaf_xf: Array[Transform3D] = []
	var body := StaticBody3D.new()
	nav.add_child(body)
	var tries := 0
	while trunk_xf.size() < 320 and tries < 4000:
		tries += 1
		var x := randf_range(-HALF + 14.0, HALF - 14.0)
		var z := randf_range(-HALF + 14.0, HALF - 14.0)
		if road_dist(x, z) < 6.0 or near_pad(x, z, PAD_R + 2.0):
			continue
		var h := height_at(x, z)
		if h > 17.0 or h < -5.0:
			continue
		var s := randf_range(0.8, 1.6)
		var basis := Basis.from_scale(Vector3(s, s, s))
		trunk_xf.append(Transform3D(basis, Vector3(x, h + 1.5 * s, z)))
		leaf_xf.append(Transform3D(basis, Vector3(x, h + 4.2 * s, z)))
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4 * s
		cyl.height = 5.0
		cs.shape = cyl
		cs.position = Vector3(x, h + 2.5, z)
		body.add_child(cs)
		obstacles.append(Vector3(x, 0, z))

	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.28
	tm.height = 3.0
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.4, 0.26, 0.14)
	tm.material = tmat
	var lm := CylinderMesh.new()
	lm.top_radius = 0.0
	lm.bottom_radius = 1.7
	lm.height = 4.5
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.1, 0.38, 0.16)
	lm.material = lmat
	_multimesh(tm, trunk_xf)
	_multimesh(lm, leaf_xf)


func _multimesh(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)  # visual only; colliders live in the nav region


func _static_box(parent: Node, size: Vector3, xf: Transform3D, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = xf
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)
	return body


func _build_rocks() -> void:
	var n := 0
	var tries := 0
	while n < 45 and tries < 1000:
		tries += 1
		var x := randf_range(-HALF + 14.0, HALF - 14.0)
		var z := randf_range(-HALF + 14.0, HALF - 14.0)
		if road_dist(x, z) < 6.0 or near_pad(x, z, PAD_R + 2.0):
			continue
		var h := height_at(x, z)
		var sz := Vector3(randf_range(1.5, 4.0), randf_range(1.2, 3.0), randf_range(1.5, 4.0))
		var basis := Basis(Vector3.UP, randf() * TAU)
		var g := randf_range(0.4, 0.55)
		_static_box(nav, sz, Transform3D(basis, Vector3(x, h + sz.y * 0.3, z)), Color(g, g, g * 1.05))
		obstacles.append(Vector3(x, 0, z))
		n += 1


# --------------------------------------------------------------- buildings
func _house(p: Vector3) -> void:
	var rot := float(randi() % 4) * PI * 0.5
	var base := Transform3D(Basis(Vector3.UP, rot), Vector3(p.x, p.y + 0.05, p.z))
	var w := 9.0
	var d := 7.0
	var h := 3.2
	var t := 0.3
	var wall := Color(0.76, 0.7, 0.6)
	var dark := Color(0.35, 0.3, 0.28)
	_static_box(nav, Vector3(w + 0.6, 0.3, d + 0.6), base * Transform3D(Basis(), Vector3(0, -0.15, 0)), dark)
	_static_box(nav, Vector3(w, h, t), base * Transform3D(Basis(), Vector3(0, h * 0.5, -d * 0.5)), wall)
	_static_box(nav, Vector3(t, h, d), base * Transform3D(Basis(), Vector3(-w * 0.5, h * 0.5, 0)), wall)
	_static_box(nav, Vector3(t, h, d), base * Transform3D(Basis(), Vector3(w * 0.5, h * 0.5, 0)), wall)
	# front wall with a 2m door
	var seg := (w - 2.0) * 0.5
	_static_box(nav, Vector3(seg, h, t), base * Transform3D(Basis(), Vector3(-(1.0 + seg * 0.5), h * 0.5, d * 0.5)), wall)
	_static_box(nav, Vector3(seg, h, t), base * Transform3D(Basis(), Vector3(1.0 + seg * 0.5, h * 0.5, d * 0.5)), wall)
	_static_box(nav, Vector3(2.0, h - 2.4, t), base * Transform3D(Basis(), Vector3(0, 2.4 + (h - 2.4) * 0.5, d * 0.5)), wall)
	_static_box(nav, Vector3(w + 0.6, 0.3, d + 0.6), base * Transform3D(Basis(), Vector3(0, h + 0.15, 0)), dark)
	_static_box(nav, Vector3(1.6, 0.8, 0.8), base * Transform3D(Basis(), Vector3(-2.5, 0.4, -2.0)), Color(0.45, 0.3, 0.18))
	# loot inside
	for off in [Vector3(-3.0, 0, 1.0), Vector3(3.0, 0, -1.5), Vector3(0.5, 0, -2.5), Vector3(-1.0, 0, 2.0)]:
		var wp: Vector3 = base * off
		var roll := _loot_roll(1)
		spawn_loot(roll["kind"], roll["id"], roll["count"], roll["rarity"], roll["mag"], wp)


func _build_buildings() -> void:
	for p in pads:
		_house(p)


func _build_boundary() -> void:
	var half := HALF - 4.0
	for side in [Vector3(half, 0, 0), Vector3(-half, 0, 0), Vector3(0, 0, half), Vector3(0, 0, -half)]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.0, 120.0, HALF * 2.0) if absf(side.x) > 0.0 else Vector3(HALF * 2.0, 120.0, 2.0)
		cs.shape = bs
		body.add_child(cs)
		body.position = side + Vector3(0, 30, 0)
		add_child(body)


func _build_zone_visual() -> void:
	zone_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 120.0
	cm.radial_segments = 96
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.45, 1.0, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = mat
	zone_mesh.mesh = cm
	zone_mesh.layers = 2  # visible to the main camera only, not the minimap
	zone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zone_mesh)


# -------------------------------------------------------------------- loot
func _loot_roll(rarity_bias: int = 0) -> Dictionary:
	var rr := randf()
	var rarity := 0
	if rr > 0.94:
		rarity = 3
	elif rr > 0.80:
		rarity = 2
	elif rr > 0.55:
		rarity = 1
	rarity = mini(3, rarity + (1 if (rarity_bias > 0 and randf() < 0.3) else 0))
	var r := randf()
	if r < 0.24:
		var id: String = ["ar", "smg", "shotgun", "pistol", "ar", "smg"].pick_random()
		var d: Dictionary = WeaponDB.WEAPONS[id]
		return {"kind": "weapon", "id": id, "count": 1, "rarity": rarity, "mag": int(d["mag"])}
	elif r < 0.55:
		var ammo: String = ["9mm", "5.56", "12ga", "5.56", "9mm"].pick_random()
		return {"kind": "ammo", "id": ammo, "count": randi_range(20, 60), "rarity": 0, "mag": -1}
	elif r < 0.72:
		return {"kind": "heal", "id": "bandage", "count": randi_range(1, 3), "rarity": 0, "mag": -1}
	elif r < 0.80:
		return {"kind": "heal", "id": "medkit", "count": 1, "rarity": 0, "mag": -1}
	elif r < 0.88:
		return {"kind": "grenade", "id": "grenade", "count": randi_range(1, 2), "rarity": 0, "mag": -1}
	elif r < 0.95:
		return {"kind": "armor", "id": "armor", "count": 1, "rarity": rarity, "mag": -1}
	return {"kind": "backpack", "id": "backpack", "count": 1, "rarity": rarity, "mag": -1}


func spawn_loot(kind: String, id: String, count: int, rarity: int, mag: int, pos: Vector3) -> Loot:
	var l := Loot.new()
	add_child(l)
	l.setup(kind, id, count, rarity, mag)
	l.global_position = pos
	return l


func _scatter_loot() -> void:
	for i in 110:
		var pos := _free_spot(135.0)
		var roll := _loot_roll()
		spawn_loot(roll["kind"], roll["id"], roll["count"], roll["rarity"], roll["mag"], pos)


func spawn_death_loot(pos: Vector3, weapon_id: String) -> void:
	var d: Dictionary = WeaponDB.WEAPONS[weapon_id]
	var rr := 1 if randf() < 0.4 else 0
	spawn_loot("weapon", weapon_id, 1, rr, randi_range(5, int(d["mag"])), pos + Vector3(0.6, 0, 0))
	spawn_loot("ammo", d["ammo"], randi_range(15, 40), 0, -1, pos + Vector3(-0.6, 0, 0.4))
	if randf() < 0.6:
		spawn_loot("heal", "bandage", randi_range(1, 2), 0, -1, pos + Vector3(0, 0, -0.7))


func _free_spot(radius: float) -> Vector3:
	var x := 0.0
	var z := 0.0
	for i in 80:
		var a := randf() * TAU
		var r := sqrt(randf()) * radius
		x = cos(a) * r
		z = sin(a) * r
		var ok := true
		if near_pad(x, z, 9.5):
			ok = false
		for o in obstacles:
			if Vector2(x - o.x, z - o.z).length() < 3.0:
				ok = false
				break
		if ok and absf(x) < HALF - 10.0 and absf(z) < HALF - 10.0:
			break
	return Vector3(x, height_at(x, z), z)


# ----------------------------------------------------------- spawn fighters
func _spawn_player() -> void:
	player = Player.new()
	player.game = self
	add_child(player)
	var s := _free_spot(110.0)
	player.global_position = s + Vector3(0, 0.3, 0)
	player.rotation.y = randf() * TAU


func _spawn_bots() -> void:
	for i in BOT_COUNT:
		var b := Bot.new()
		b.game = self
		b.display_name = "Bot %d" % (i + 1)
		b.weapon_id = ["ar", "ar", "smg", "shotgun", "pistol"].pick_random()
		add_child(b)
		var s := _free_spot(130.0)
		for k in 10:
			if Vector2(s.x - player.global_position.x, s.z - player.global_position.z).length() > 30.0:
				break
			s = _free_spot(130.0)
		b.global_position = s + Vector3(0, 0.3, 0)
		b.rotation.y = randf() * TAU


# --------------------------------------------------------------- navigation
func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.cell_size = 0.5
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.5)
	nav.navigation_mesh = nm
	nav.bake_finished.connect(_on_bake_finished)
	nav.bake_navigation_mesh(true)
	get_tree().create_timer(25.0).timeout.connect(_on_bake_finished)  # safety net


func _on_bake_finished() -> void:
	if started:
		return
	started = true
	nav_ready = nav.navigation_mesh != null and nav.navigation_mesh.get_polygon_count() > 0
	if not nav_ready:
		push_warning("Navmesh bake produced no polygons - bots fall back to straight-line movement.")
	counting = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.refresh_inventory(true)


func random_nav_point() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * maxf(zone_radius * 0.9, 5.0)
	var x := zone_center.x + cos(a) * r
	var z := zone_center.y + sin(a) * r
	x = clampf(x, -HALF + 12.0, HALF - 12.0)
	z = clampf(z, -HALF + 12.0, HALF - 12.0)
	var p := Vector3(x, height_at(x, z), z)
	if nav_ready:
		p = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
	return p


# ------------------------------------------------------------ combat helpers
func spread_dir(dir: Vector3, spread: float) -> Vector3:
	var b := dir.cross(Vector3.UP)
	if b.length() < 0.001:
		return dir
	b = b.normalized()
	var u := b.cross(dir).normalized()
	var a := randf() * TAU
	var r := spread * sqrt(randf())
	return (dir + (b * cos(a) + u * sin(a)) * r).normalized()


func fire_ray(shooter, origin: Vector3, dir: Vector3, range_: float, dmg: float) -> Dictionary:
	var ex: Array[RID] = [shooter.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * range_, 3, ex)
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return r
	var hit_pos: Vector3 = r["position"]
	spawn_spark(hit_pos)
	var c = r["collider"]
	if c != null and c.has_method("take_damage"):
		var dist := origin.distance_to(hit_pos)
		var amount := dmg * lerpf(1.0, 0.65, clampf(dist / range_, 0.0, 1.0))
		var head: bool = (hit_pos.y - c.global_position.y) > c.head_y()
		if head:
			amount *= 1.8
		r["hit_char"] = true
		r["headshot"] = head
		c.take_damage(amount, shooter)
	return r


func spawn_tracer(a: Vector3, b: Vector3) -> void:
	var m := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	m.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.5)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	get_tree().create_timer(0.05).timeout.connect(m.queue_free)


func spawn_spark(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.3)
	sm.material = mat
	m.mesh = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	get_tree().create_timer(0.12).timeout.connect(m.queue_free)


func throw_grenade(thrower, pos: Vector3, vel: Vector3) -> void:
	var g := RigidBody3D.new()
	g.collision_layer = 4
	g.collision_mask = 1
	g.mass = 0.5
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.15
	cs.shape = sp
	g.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.3, 0.15)
	sm.material = mat
	mi.mesh = sm
	g.add_child(mi)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	g.physics_material_override = pm
	add_child(g)
	g.global_position = pos
	g.linear_velocity = vel
	get_tree().create_timer(2.5).timeout.connect(_explode.bind(g, thrower))


func _explode(g, thrower) -> void:
	if not is_instance_valid(g):
		return
	var pos: Vector3 = g.global_position
	g.queue_free()
	Sfx.play3d("explosion", pos)
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = mat
	m.mesh = sm
	add_child(m)
	m.global_position = pos
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3(7, 7, 7), 0.25)
	tw.tween_callback(m.queue_free)
	var who = thrower if is_instance_valid(thrower) else null
	for f in get_tree().get_nodes_in_group("fighters"):
		var d: float = (f.global_position + Vector3(0, 1.0, 0)).distance_to(pos)
		if d < 9.0:
			f.take_damage(140.0 * (1.0 - d / 9.0), who)


# --------------------------------------------------------------- match flow
func alive_count() -> int:
	return get_tree().get_nodes_in_group("fighters").size()


func outside_zone(pos: Vector3) -> bool:
	return Vector2(pos.x - zone_center.x, pos.z - zone_center.y).length() > zone_radius


func toggle_inventory() -> void:
	if match_over:
		return
	ui_open = not ui_open
	hud.inv_panel.visible = ui_open
	if ui_open:
		hud.refresh_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_fighter_died(victim, killer) -> void:
	var kname := "The zone"
	if killer != null and killer != victim:
		killer.kills += 1
		kname = killer.display_name
	hud.feed("%s eliminated %s" % [kname, victim.display_name])
	var alive := alive_count()
	victim.placement = alive + 1
	if match_over:
		return
	if victim == player:
		_end_match(false)
	elif alive <= 1:
		_end_match(true)


func _end_match(won: bool) -> void:
	match_over = true
	running = false
	ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var mt := int(match_time)
	var stats := "Placement: #%d   Kills: %d   Survived: %02d:%02d" % [1 if won else player.placement, player.kills, mt / 60, mt % 60]
	hud.set_center("")
	hud.show_end("WINNER WINNER!" if won else "ELIMINATED", stats)


func _clear_center() -> void:
	if not match_over:
		hud.set_center("")


func _process(delta: float) -> void:
	if counting:
		countdown -= delta
		if countdown > 0.0:
			hud.set_center(str(ceili(countdown)))
		else:
			counting = false
			running = true
			hud.set_center("GO!")
			get_tree().create_timer(1.2).timeout.connect(_clear_center)
	if running:
		match_time += delta
		var prog := clampf((match_time - ZONE_DELAY) / ZONE_SHRINK_TIME, 0.0, 1.0)
		zone_radius = lerpf(ZONE_START, ZONE_END, prog)
		zone_tick += delta
		if zone_tick >= 1.0:
			zone_tick = 0.0
			var dmg := 1.5 + 4.0 * prog
			for f in get_tree().get_nodes_in_group("fighters"):
				if outside_zone(f.global_position):
					f.take_damage(dmg, null, true)
	zone_mesh.scale = Vector3(zone_radius, 1.0, zone_radius)
	zone_mesh.position = Vector3(zone_center.x, 30.0, zone_center.y)
