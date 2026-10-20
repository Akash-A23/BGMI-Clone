class_name Hud
extends CanvasLayer
## All UI is built in code: health/armor, ammo, kills, alive count, match timer,
## zone info, crosshair + hit marker, minimap, inventory window, kill feed, end screen.

var game
var root: Control
var hp_bar: ProgressBar
var armor_bar: ProgressBar
var hp_label: Label
var kills_label: Label
var alive_label: Label
var timer_label: Label
var zone_label: Label
var weapon_label: Label
var ammo_label: Label
var items_label: Label
var prompt_label: Label
var msg_label: Label
var center_label: Label
var action_label: Label
var action_bar: ProgressBar
var crosshair: Crosshair
var minimap: Minimap
var minimap_vp: SubViewport
var minimap_cam: Camera3D
var damage_rect: ColorRect
var feed_box: VBoxContainer
var inv_panel: PanelContainer
var inv_list: VBoxContainer
var end_panel: PanelContainer
var msg_t := 0.0
var dmg_t := 0.0
var help_t := 20.0
var help_label: Label


# ---------------------------------------------------------- inner controls
class Crosshair extends Control:
	var gap := 8.0
	var hit_t := 0.0
	var head := false

	func _process(delta: float) -> void:
		hit_t = maxf(0.0, hit_t - delta)
		queue_redraw()

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.95)
		draw_line(Vector2(-gap - 10, 0), Vector2(-gap, 0), c, 2.0)
		draw_line(Vector2(gap, 0), Vector2(gap + 10, 0), c, 2.0)
		draw_line(Vector2(0, -gap - 10), Vector2(0, -gap), c, 2.0)
		draw_line(Vector2(0, gap), Vector2(0, gap + 10), c, 2.0)
		draw_circle(Vector2.ZERO, 1.5, c)
		if hit_t > 0.0:
			var hc := Color(1, 0.2, 0.2) if head else Color(1, 1, 1)
			for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(s * 7.0, s * 15.0, hc, 2.5)


class Minimap extends Control:
	var game
	var cam_size := 130.0

	func _process(_d: float) -> void:
		queue_redraw()

	func to_map(p: Vector3) -> Vector2:
		var pl = game.player
		var d: Vector3 = p - pl.global_position
		var right: Vector3 = pl.global_transform.basis.x
		var fwd: Vector3 = -pl.global_transform.basis.z
		var mx := d.dot(right)
		var my := d.dot(fwd)
		return size * 0.5 + Vector2(mx, -my) * (size.x / cam_size)

	func _draw() -> void:
		if game == null or game.player == null:
			return
		var c := size * 0.5
		var scale_px: float = size.x / cam_size
		# safe zone circle
		var zc := to_map(Vector3(game.zone_center.x, 0.0, game.zone_center.y))
		draw_arc(zc, float(game.zone_radius) * scale_px, 0.0, TAU, 96, Color(0.3, 0.6, 1.0, 0.95), 2.5)
		# nearby enemies (short-range radar)
		for f in get_tree().get_nodes_in_group("fighters"):
			if f == game.player:
				continue
			var d: float = game.player.global_position.distance_to(f.global_position)
			if d < 45.0:
				draw_circle(to_map(f.global_position), 3.5, Color(1, 0.25, 0.2))
		# player arrow
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(-6, 6), c + Vector2(6, 6)]), Color.WHITE)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.8), false, 2.0)


# ------------------------------------------------------------------- setup
func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	damage_rect = ColorRect.new()
	damage_rect.color = Color(0.8, 0.0, 0.0, 0.0)
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	# top-left: match info
	var tl := _corner(Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN)
	timer_label = _label(tl, "00:00", 28)
	kills_label = _label(tl, "Kills: 0", 24)
	alive_label = _label(tl, "Alive: 0", 24)
	zone_label = _label(tl, "", 18)

	# top-right: minimap + kill feed
	var top_right := _corner(Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_BEGIN)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(210, 210)
	top_right.add_child(holder)
	minimap_vp = SubViewport.new()
	minimap_vp.size = Vector2i(256, 256)
	minimap_vp.world_3d = get_viewport().find_world_3d()
	minimap_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(minimap_vp)
	minimap_cam = Camera3D.new()
	minimap_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_cam.size = 130.0
	minimap_cam.far = 400.0
	minimap_cam.cull_mask = 1  # layer 2 (zone wall) is hidden from the minimap
	var menv := Environment.new()
	menv.background_mode = Environment.BG_COLOR
	menv.background_color = Color(0.05, 0.08, 0.05)
	menv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	menv.ambient_light_color = Color(1, 1, 1)
	menv.ambient_light_energy = 0.6
	minimap_cam.environment = menv
	minimap_vp.add_child(minimap_cam)
	minimap_cam.current = true
	var tex := TextureRect.new()
	tex.texture = minimap_vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tex)
	minimap = Minimap.new()
	minimap.game = game
	minimap.clip_contents = true
	minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(minimap)
	feed_box = VBoxContainer.new()
	feed_box.alignment = BoxContainer.ALIGNMENT_END
	top_right.add_child(feed_box)

	# bottom-left: health / armor
	var bl := _corner(Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_END)
	hp_label = _label(bl, "", 18)
	hp_bar = _bar(bl, Color(0.25, 0.85, 0.3))
	armor_bar = _bar(bl, Color(0.35, 0.6, 1.0))
	items_label = _label(bl, "", 16)

	# bottom-right: weapon + ammo
	var br := _corner(Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_END)
	weapon_label = _label(br, "", 20)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label = _label(br, "", 40)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# bottom-centre: prompts + action progress
	var bc := _corner(Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_END)
	help_label = _label(bc, "WASD move | Shift sprint | C/Ctrl crouch | Z prone | Space jump | LMB shoot | RMB aim | R reload | 1/2 or wheel switch weapon | F pick up | G grenade | H heal | I/Tab inventory | Esc free mouse", 14)
	prompt_label = _label(bc, "", 22)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_label = _label(bc, "", 18)
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_bar = _bar(bc, Color(1, 0.85, 0.3))
	action_bar.custom_minimum_size = Vector2(260, 12)
	action_bar.max_value = 1.0
	action_bar.visible = false

	# top-centre: big message + small message
	var tc := _corner(Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 80)
	tc.add_child(spacer)
	center_label = _label(tc, "", 48)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label = _label(tc, "", 22)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# inventory window
	inv_panel = PanelContainer.new()
	inv_panel.set_anchors_preset(Control.PRESET_CENTER)
	inv_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inv_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	inv_panel.visible = false
	root.add_child(inv_panel)
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 14)
	inv_panel.add_child(margin)
	inv_list = VBoxContainer.new()
	margin.add_child(inv_list)


func _corner(h: int, v: int) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 16)
	root.add_child(m)
	var b := VBoxContainer.new()
	b.size_flags_horizontal = h
	b.size_flags_vertical = v
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(b)
	return b


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(280, 16)
	b.show_percentage = false
	b.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


# -------------------------------------------------------------- public API
func msg(text: String) -> void:
	msg_label.text = text
	msg_t = 2.5


func set_center(text: String) -> void:
	center_label.text = text


func set_prompt(text: String) -> void:
	prompt_label.text = text


func set_action(label: String, frac: float) -> void:
	action_label.text = label
	action_bar.visible = frac >= 0.0
	action_bar.value = clampf(frac, 0.0, 1.0)


func flash_damage() -> void:
	dmg_t = 0.45


func hitmarker(head: bool) -> void:
	crosshair.hit_t = 0.2
	crosshair.head = head


func feed(text: String) -> void:
	var l := _label(feed_box, text, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	get_tree().create_timer(6.0).timeout.connect(l.queue_free)
	if feed_box.get_child_count() > 6:
		feed_box.get_child(0).queue_free()


func show_end(title: String, stats: String) -> void:
	inv_panel.visible = false
	end_panel = PanelContainer.new()
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(end_panel)
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 28)
	end_panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	var t := _label(v, title, 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _label(v, stats, 24)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := Button.new()
	b.text = "Play again"
	b.custom_minimum_size = Vector2(200, 44)
	b.pressed.connect(func(): get_tree().reload_current_scene())
	v.add_child(b)


# --------------------------------------------------------------- inventory
func refresh_inventory(only_if_open: bool = false) -> void:
	if only_if_open and not inv_panel.visible:
		return
	if game == null or game.player == null:
		return
	var p = game.player
	for c in inv_list.get_children():
		inv_list.remove_child(c)
		c.queue_free()
	_label(inv_list, "BACKPACK   %.1f / %.0f" % [p.weight(), p.capacity], 24)
	_label(inv_list, "Armor: %d" % int(p.armor), 18)
	_label(inv_list, "-- Weapons --", 18)
	for slot in [1, 2]:
		var w = p.slots[slot]
		var title := "Primary" if slot == 1 else "Secondary"
		if w == null:
			_row("%s: (empty)" % title, [])
		else:
			var d: Dictionary = WeaponDB.WEAPONS[w["id"]]
			var txt := "%s: %s  [%d/%d]" % [title, WeaponDB.display_name("weapon", w["id"], w["rarity"]), int(w["mag"]), int(d["mag"])]
			_row(txt, [["Equip", Callable(p, "equip").bind(slot)], ["Drop", Callable(p, "drop_weapon").bind(slot)]])
	_label(inv_list, "-- Items --", 18)
	for id in p.inv:
		var n: int = p.inv[id]
		if n <= 0:
			continue
		var info: Dictionary = WeaponDB.ITEMS[id]
		var btns := []
		if info["kind"] != "ammo":
			btns.append(["Use", Callable(p, "use_item").bind(id)])
		btns.append(["Drop 1", Callable(p, "drop_item").bind(id, 1)])
		btns.append(["Drop all", Callable(p, "drop_item").bind(id, n)])
		_row("%s x%d" % [info["name"], n], btns)
	var close := Button.new()
	close.text = "Close (I)"
	close.pressed.connect(func(): game.toggle_inventory())
	inv_list.add_child(close)


func _row(text: String, buttons: Array) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(340, 0)
	h.add_child(l)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		h.add_child(btn)
	inv_list.add_child(h)


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	msg_t -= delta
	if msg_t <= 0.0:
		msg_label.text = ""
	dmg_t = maxf(0.0, dmg_t - delta)
	damage_rect.color.a = dmg_t * 0.7
	help_t -= delta
	help_label.visible = help_t > 0.0

	hp_bar.value = p.hp
	armor_bar.value = p.armor
	hp_label.text = "HP %d    ARMOR %d" % [ceili(p.hp), int(p.armor)]
	kills_label.text = "Kills: %d" % p.kills
	alive_label.text = "Alive: %d" % game.alive_count()
	var mt: int = int(game.match_time)
	timer_label.text = "%02d:%02d" % [mt / 60, mt % 60]
	weapon_label.text = p.weapon_text()
	ammo_label.text = p.ammo_text()
	items_label.text = "Bandage %d   Medkit %d   Grenade %d" % [p.inv["bandage"], p.inv["medkit"], p.inv["grenade"]]
	if game.outside_zone(p.global_position):
		zone_label.text = "OUTSIDE THE ZONE - taking damage!"
		zone_label.modulate = Color(1, 0.3, 0.3)
	else:
		zone_label.text = "Zone radius: %dm" % int(game.zone_radius)
		zone_label.modulate = Color(0.6, 0.8, 1)
	crosshair.gap = 6.0 + p.current_spread() * 500.0

	var fwd: Vector3 = -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	minimap_cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, fwd), p.global_position + Vector3.UP * 150.0)
