class_name Humanoid
extends Node3D
## Blocky character model with procedural animation (walk cycle, aim pose,
## weapon recoil, reload pose, crouch, prone, death fall) and a muzzle flash.
## Origin is at the feet, the character faces -Z.

var rig: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var weapon_mount: Node3D
var weapon_parts: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
var phase := 0.0
var flash_t := 0.0
var recoil := 0.0
var reloading := false
var crouch_t := 0.0
var prone_t := 0.0
var armed := false


func build(shirt: Color) -> void:
	rig = Node3D.new()
	add_child(rig)
	var skin := Color(0.9, 0.72, 0.58)
	var pants := Color(0.2, 0.22, 0.3)
	_box(rig, Vector3(0.5, 0.6, 0.28), Vector3(0, 1.1, 0), shirt)
	_box(rig, Vector3(0.26, 0.26, 0.26), Vector3(0, 1.58, 0), skin)
	_box(rig, Vector3(0.3, 0.1, 0.3), Vector3(0, 1.74, 0), Color(0.15, 0.2, 0.15))  # helmet
	leg_l = _limb(Vector3(-0.13, 0.8, 0), Vector3(0.18, 0.8, 0.2), pants)
	leg_r = _limb(Vector3(0.13, 0.8, 0), Vector3(0.18, 0.8, 0.2), pants)
	arm_l = _limb(Vector3(-0.34, 1.38, 0), Vector3(0.13, 0.6, 0.13), shirt)
	arm_r = _limb(Vector3(0.34, 1.38, 0), Vector3(0.13, 0.6, 0.13), shirt)

	weapon_mount = Node3D.new()
	weapon_mount.position = Vector3(0.12, 1.25, -0.3)
	rig.add_child(weapon_mount)
	weapon_parts = Node3D.new()
	weapon_mount.add_child(weapon_parts)
	muzzle = Node3D.new()
	weapon_mount.add_child(muzzle)

	flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.85, 0.3)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.7, 0.2)
	fm.emission_energy_multiplier = 4.0
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = fm
	flash.mesh = sm
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(flash)
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.7, 0.3)
	flash_light.light_energy = 2.5
	flash_light.omni_range = 6.0
	flash_light.visible = false
	muzzle.add_child(flash_light)
	set_weapon("")


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	b.material = mat
	m.mesh = b
	m.position = pos
	parent.add_child(m)
	return m


func _limb(pivot_pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	rig.add_child(pivot)
	_box(pivot, size, Vector3(0, -size.y * 0.5, 0), color)
	return pivot


func set_weapon(id: String) -> void:
	for c in weapon_parts.get_children():
		c.queue_free()
	if id == "":
		armed = false
		weapon_mount.visible = false
		return
	armed = true
	weapon_mount.visible = true
	var d: Dictionary = WeaponDB.WEAPONS[id]
	var l: float = d["len"]
	var col: Color = d["color"]
	var dark := Color(0.08, 0.08, 0.08)
	_box(weapon_parts, Vector3(0.06, 0.1, l * 0.7), Vector3(0, 0, -l * 0.4), col)
	_box(weapon_parts, Vector3(0.03, 0.03, l * 0.45), Vector3(0, 0.02, -l * 0.85), dark)
	_box(weapon_parts, Vector3(0.05, 0.2, 0.08), Vector3(0, -0.14, -l * 0.3), dark)
	_box(weapon_parts, Vector3(0.05, 0.12, l * 0.25), Vector3(0, -0.02, l * 0.0), col.darkened(0.3))
	muzzle.position = Vector3(0, 0.02, -l * 1.1)


func fire() -> void:
	recoil = 1.0
	flash_t = 0.05
	flash.visible = true
	flash_light.visible = true
	flash.rotation = Vector3(randf() * 3.0, randf() * 3.0, randf() * 3.0)


func fall() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rig, "rotation:x", 1.5, 0.5)
	tw.tween_property(rig, "position:y", 0.25, 0.5)
	weapon_mount.visible = false


func animate(delta: float, speed: float, on_floor: bool) -> void:
	var s := clampf(speed / 6.0, 0.0, 1.3)
	if speed > 0.5 and on_floor:
		phase += delta * (4.0 + speed * 1.5)
	var swing := sin(phase) * 0.9 * s
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	if armed:
		var aim := 1.35
		arm_l.rotation = Vector3(aim, -0.35, 0)
		arm_r.rotation = Vector3(aim, 0.35, 0)
	else:
		arm_l.rotation = Vector3(-swing * 0.8, 0, 0)
		arm_r.rotation = Vector3(swing * 0.8, 0, 0)
	if prone_t > 0.01 or crouch_t > 0.01:
		rig.scale.y = lerpf(1.0, 0.72, crouch_t)
		rig.rotation.x = lerpf(0.0, -1.45, prone_t)
		rig.position.y = lerpf(0.0, 0.18, prone_t)
	recoil = move_toward(recoil, 0.0, delta * 10.0)
	weapon_mount.position.z = -0.3 + recoil * 0.07
	weapon_mount.rotation.x = recoil * 0.12 + (-0.6 if reloading else 0.0)
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			flash.visible = false
			flash_light.visible = false
