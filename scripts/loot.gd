class_name Loot
extends Node3D
## A pickup lying in the world. kind: weapon / ammo / heal / grenade / armor / backpack

var kind := ""
var id := ""
var count := 1
var rarity := 0
var mag := -1
var t := randf() * 10.0
var body: MeshInstance3D
var label: Label3D


func setup(p_kind: String, p_id: String, p_count: int, p_rarity: int, p_mag: int = -1) -> void:
	kind = p_kind
	id = p_id
	count = p_count
	rarity = p_rarity
	mag = p_mag
	add_to_group("loot")
	var rc: Color = WeaponDB.RARITY[rarity]["color"]
	var col := rc
	var size := Vector3(0.35, 0.25, 0.35)
	match kind:
		"weapon":
			size = Vector3(0.18, 0.2, 0.7)
		"ammo":
			col = Color(0.9, 0.75, 0.2)
		"heal":
			col = Color(0.9, 0.15, 0.15) if id == "medkit" else Color(0.95, 0.95, 0.95)
		"grenade":
			col = Color(0.2, 0.45, 0.2)
			size = Vector3(0.25, 0.25, 0.25)
		"armor":
			col = Color(0.3, 0.4, 0.6)
			size = Vector3(0.45, 0.4, 0.2)
		"backpack":
			col = Color(0.45, 0.3, 0.15)
			size = Vector3(0.4, 0.5, 0.3)

	body = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	bm.material = mat
	body.mesh = bm
	body.position.y = 0.55
	add_child(body)

	# Light beam coloured by rarity so loot is visible from afar
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 5.0
	cm.cap_top = false
	cm.cap_bottom = false
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(rc.r, rc.g, rc.b, 0.3)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.material = bmat
	beam.mesh = cm
	beam.position.y = 2.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.font_size = 36
	label.outline_size = 8
	label.no_depth_test = true
	label.modulate = rc
	label.position.y = 1.2
	label.visibility_range_end = 10.0
	add_child(label)
	refresh()


func refresh() -> void:
	var text := WeaponDB.display_name(kind, id, rarity)
	if kind != "weapon" and count > 1:
		text += " x%d" % count
	label.text = text


func _process(delta: float) -> void:
	t += delta
	body.position.y = 0.55 + sin(t * 2.0) * 0.08
	body.rotate_y(delta * 1.2)
