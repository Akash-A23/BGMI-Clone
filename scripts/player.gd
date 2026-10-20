class_name Player
extends CharacterBody3D
## Third-person player: movement, stances, health/armor, weapons, inventory.

const WALK := 4.5
const SPRINT := 7.5
const CROUCH_SPEED := 2.4
const PRONE_SPEED := 1.3
const GRAVITY := 24.0
const JUMP := 8.0
const FALL_SAFE := 14.0

var game
var display_name := "You"
var hp := 100.0
var armor := 0.0
var kills := 0
var placement := 0
var dead := false

var sens := 0.0025
var pitch := -0.1
var rig: Humanoid
var pivot: Node3D
var spring: SpringArm3D
var cam: Camera3D
var shape: CapsuleShape3D
var col: CollisionShape3D

# weapons: slot 1 = primary, slot 2 = secondary
var slots := {1: null, 2: null}
var current_slot := 0
var inv := {"9mm": 24, "5.56": 0, "12ga": 0, "bandage": 2, "medkit": 0, "grenade": 1}
var capacity := 60.0

var fire_cd := 0.0
var grenade_cd := 0.0
var bloom := 0.0
var lmb_prev := false
var reloading := false
var reload_t := 0.0
var reload_total := 1.0
var heal_item := ""
var heal_t := 0.0
var heal_total := 1.0

var crouching := false
var prone := false
var aiming := false
var sprinting := false
var step_acc := 0.0
var was_on_floor := true
var pre_vy := 0.0
var nearby: Loot = null


func _ready() -> void:
	add_to_group("fighters")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)

	shape = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	rig = Humanoid.new()
	add_child(rig)
	rig.build(Color(0.2, 0.5, 0.9))

	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.55, 0)
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 3.4
	spring.position = Vector3(0.6, 0.1, 0)
	spring.collision_mask = 1
	spring.margin = 0.05
	var ss := SphereShape3D.new()
	ss.radius = 0.15
	spring.shape = ss
	pivot.add_child(spring)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = 500.0
	spring.add_child(cam)
	cam.current = true
	pivot.rotation.x = pitch

	slots[2] = {"id": "pistol", "rarity": 0, "mag": 12}
	equip(2)


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if dead or game.match_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_I, KEY_TAB:
				game.toggle_inventory()
				return
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				return
	if game.ui_open or not game.running:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sens)
		pitch = clampf(pitch - event.relative.y * sens, -1.2, 1.3)
		pivot.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_weapon()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: equip(1)
			KEY_2: equip(2)
			KEY_R: start_reload()
			KEY_F: pickup_nearby()
			KEY_G: throw_grenade()
			KEY_H: quick_heal()
			KEY_Z: prone = not prone


# ---------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	fire_cd = maxf(0.0, fire_cd - delta)
	grenade_cd = maxf(0.0, grenade_cd - delta)
	bloom = maxf(0.0, bloom - delta * 0.04)

	if dead:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return

	var active: bool = game.running and not game.ui_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var ix := 0.0
	var iz := 0.0
	if active:
		ix = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		iz = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var moving := Vector2(ix, iz).length() > 0.1

	crouching = active and (Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL))
	aiming = active and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	sprinting = active and Input.is_physical_key_pressed(KEY_SHIFT) and iz < -0.1 \
		and not crouching and not prone and not aiming and heal_item == ""

	var spd := WALK
	if sprinting:
		spd = SPRINT
	elif prone:
		spd = PRONE_SPEED
	elif crouching:
		spd = CROUCH_SPEED
	if heal_item != "":
		spd *= 0.6
	var dir := Vector3.ZERO
	if moving:
		dir = (global_transform.basis * Vector3(ix, 0.0, iz)).normalized()

	var on_floor := is_on_floor()
	if on_floor:
		if active and Input.is_physical_key_pressed(KEY_SPACE) and not prone:
			velocity.y = JUMP
		elif velocity.y < 0.0:
			velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta

	var accel := 45.0 if on_floor else 8.0
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * spd, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.y

	pre_vy = velocity.y
	move_and_slide()
	var floor_now := is_on_floor()
	if floor_now and not was_on_floor and pre_vy < -FALL_SAFE:
		var dmg := (-pre_vy - FALL_SAFE) * 6.0
		take_damage(dmg, null, true)
		game.hud.msg("Fall damage: -%d" % int(dmg))
	was_on_floor = floor_now

	# stance: capsule, camera height and model pose
	var target_h := 1.8
	if prone:
		target_h = 0.8
	elif crouching:
		target_h = 1.3
	shape.height = move_toward(shape.height, target_h, delta * 6.0)
	col.position.y = shape.height * 0.5
	var ph := 1.55
	if prone:
		ph = 0.6
	elif crouching:
		ph = 1.15
	pivot.position.y = lerpf(pivot.position.y, ph, delta * 8.0)
	rig.crouch_t = move_toward(rig.crouch_t, 1.0 if (crouching and not prone) else 0.0, delta * 6.0)
	rig.prone_t = move_toward(rig.prone_t, 1.0 if prone else 0.0, delta * 5.0)
	var hs := Vector2(velocity.x, velocity.z).length()
	rig.animate(delta, hs, floor_now)
	cam.fov = lerpf(cam.fov, 50.0 if aiming else (82.0 if sprinting else 75.0), delta * 10.0)

	# footsteps
	if floor_now and hs > 1.0 and not prone:
		step_acc += hs * delta
		if step_acc > 2.2:
			step_acc = 0.0
			Sfx.play2d("step", -16.0 if crouching else (-6.0 if sprinting else -10.0))

	# shooting (hold for auto weapons, click for semi-auto)
	var lmb := active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if lmb:
		var w = current_weapon()
		if w != null:
			var d: Dictionary = WeaponDB.WEAPONS[w["id"]]
			if d["auto"] or not lmb_prev:
				try_fire()
	lmb_prev = lmb

	# timed actions: reload / healing
	var act_label := ""
	var act_frac := -1.0
	if reloading:
		reload_t -= delta
		act_label = "Reloading"
		act_frac = 1.0 - reload_t / reload_total
		if reload_t <= 0.0:
			finish_reload()
	if heal_item != "":
		heal_t -= delta
		act_label = "Using " + String(WeaponDB.ITEMS[heal_item]["name"])
		act_frac = 1.0 - heal_t / heal_total
		if heal_t <= 0.0:
			finish_heal()
	game.hud.set_action(act_label, act_frac)

	# nearest loot for the pickup prompt
	nearby = null
	var best := 3.2
	for l in get_tree().get_nodes_in_group("loot"):
		var dd := global_position.distance_to(l.global_position)
		if dd < best:
			best = dd
			nearby = l
	if nearby != null:
		game.hud.set_prompt("[F] Pick up " + WeaponDB.display_name(nearby.kind, nearby.id, nearby.rarity))
	else:
		game.hud.set_prompt("")


# ---------------------------------------------------------------- health
func take_damage(amount: float, attacker = null, pierce: bool = false) -> void:
	if dead:
		return
	if armor > 0.0 and not pierce:
		var absorbed := minf(armor, amount * 0.5)
		armor -= absorbed
		amount -= absorbed
	hp -= amount
	game.hud.flash_damage()
	Sfx.play2d("hurt", -4.0)
	if hp <= 0.0:
		hp = 0.0
		die(attacker)


func die(attacker) -> void:
	dead = true
	reloading = false
	heal_item = ""
	remove_from_group("fighters")
	rig.fall()
	game.hud.set_action("", -1.0)
	game.hud.set_prompt("")
	var a = attacker if (attacker != null and is_instance_valid(attacker)) else null
	game.on_fighter_died(self, a)


func head_y() -> float:
	return 0.5 if prone else (1.1 if crouching else 1.5)


func chest_y() -> float:
	return 0.35 if prone else (0.85 if crouching else 1.2)


# --------------------------------------------------------------- weapons
func current_weapon():
	if current_slot == 0:
		return null
	return slots[current_slot]


func equip(slot: int) -> void:
	if slots[slot] == null:
		return
	current_slot = slot
	reloading = false
	rig.reloading = false
	var w: Dictionary = slots[slot]
	rig.set_weapon(w["id"])
	fire_cd = 0.25
	game.hud.refresh_inventory()


func cycle_weapon() -> void:
	var other := 1 if current_slot == 2 else 2
	if slots[other] != null:
		equip(other)


func current_spread() -> float:
	var w = current_weapon()
	if w == null:
		return 0.02
	var d: Dictionary = WeaponDB.WEAPONS[w["id"]]
	var s: float = d["spread"]
	var m := 1.0
	if aiming:
		m *= 0.55
	if prone:
		m *= 0.5
	elif crouching:
		m *= 0.7
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 1.0:
		m *= 2.0 if sprinting else 1.5
	if not is_on_floor():
		m *= 2.5
	return s * m + bloom


func try_fire() -> void:
	if fire_cd > 0.0 or reloading or heal_item != "" or dead:
		return
	var w = current_weapon()
	if w == null:
		return
	var d: Dictionary = WeaponDB.WEAPONS[w["id"]]
	if w["mag"] <= 0:
		Sfx.play2d("empty")
		fire_cd = 0.35
		start_reload()
		return
	w["mag"] -= 1
	fire_cd = d["rate"]
	var mult: float = WeaponDB.RARITY[w["rarity"]]["mult"]
	var spread := current_spread()
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var from_pos := rig.muzzle.global_position
	var any_hit := false
	var any_head := false
	for i in int(d["pellets"]):
		var dir: Vector3 = game.spread_dir(fwd, spread)
		var r: Dictionary = game.fire_ray(self, origin, dir, d["range"], float(d["dmg"]) * mult)
		var end_pos: Vector3 = origin + dir * float(d["range"])
		if not r.is_empty():
			end_pos = r["position"]
			if r.get("hit_char", false):
				any_hit = true
				if r.get("headshot", false):
					any_head = true
		game.spawn_tracer(from_pos, end_pos)
	if any_hit:
		game.hud.hitmarker(any_head)
		Sfx.play2d("hit", -6.0)
	rig.fire()
	Sfx.play2d(d["sound"], -3.0)
	bloom = minf(bloom + 0.004, 0.05)
	var kick: float = d["recoil"] * (0.6 if aiming else 1.0)
	pitch = minf(pitch + kick, 1.3)
	rotate_y(randf_range(-0.5, 0.5) * kick)
	pivot.rotation.x = pitch
	game.hud.refresh_inventory(true)


func start_reload() -> void:
	if reloading or heal_item != "" or dead:
		return
	var w = current_weapon()
	if w == null:
		return
	var d: Dictionary = WeaponDB.WEAPONS[w["id"]]
	if w["mag"] >= d["mag"] or inv[d["ammo"]] <= 0:
		return
	reloading = true
	reload_total = d["reload"]
	reload_t = reload_total
	rig.reloading = true
	Sfx.play2d("reload", -4.0)


func finish_reload() -> void:
	reloading = false
	rig.reloading = false
	var w = current_weapon()
	if w == null:
		return
	var d: Dictionary = WeaponDB.WEAPONS[w["id"]]
	var need: int = int(d["mag"]) - int(w["mag"])
	var take: int = mini(need, int(inv[d["ammo"]]))
	w["mag"] += take
	inv[d["ammo"]] -= take
	game.hud.refresh_inventory(true)


func throw_grenade() -> void:
	if inv["grenade"] <= 0 or grenade_cd > 0.0 or dead:
		return
	inv["grenade"] -= 1
	grenade_cd = 1.0
	var origin := global_position + Vector3(0, 1.6, 0) + (-global_transform.basis.z * 0.7)
	var dir := (-cam.global_transform.basis.z + Vector3(0, 0.25, 0)).normalized()
	game.throw_grenade(self, origin, dir * 16.0)
	game.hud.refresh_inventory(true)


# ------------------------------------------------------------- inventory
func weight() -> float:
	var w := 0.0
	for k in inv:
		w += float(inv[k]) * float(WeaponDB.ITEMS[k]["weight"])
	return w


func drop_position() -> Vector3:
	var p := global_position - global_transform.basis.z * 1.5
	return Vector3(p.x, game.height_at(p.x, p.z), p.z)


func pickup_nearby() -> void:
	if nearby == null or not is_instance_valid(nearby) or dead:
		return
	var l: Loot = nearby
	match l.kind:
		"weapon":
			var d: Dictionary = WeaponDB.WEAPONS[l.id]
			var slot: int = d["slot"]
			var old = slots[slot]
			if old != null:
				game.spawn_loot("weapon", old["id"], 1, old["rarity"], old["mag"], drop_position())
			slots[slot] = {"id": l.id, "rarity": l.rarity, "mag": l.mag}
			equip(slot)
			_consume(l)
		"ammo", "heal", "grenade":
			var wgt: float = WeaponDB.ITEMS[l.id]["weight"]
			var can := int(floor((capacity - weight()) / wgt + 0.0001))
			var take := mini(can, l.count)
			if take <= 0:
				game.hud.msg("Backpack full!")
				return
			inv[l.id] += take
			l.count -= take
			if l.count <= 0:
				_consume(l)
			else:
				l.refresh()
				Sfx.play2d("pickup", -6.0)
				game.hud.msg("Backpack full - took %d" % take)
		"armor":
			var value := 40.0 + l.rarity * 20.0
			if armor >= value:
				game.hud.msg("You already have better armor")
				return
			armor = value
			_consume(l)
		"backpack":
			var cap := 60.0 + 20.0 * (l.rarity + 1)
			if capacity >= cap:
				game.hud.msg("You already have a bigger backpack")
				return
			capacity = cap
			_consume(l)
	game.hud.refresh_inventory(true)


func _consume(l: Loot) -> void:
	l.remove_from_group("loot")
	l.queue_free()
	Sfx.play2d("pickup", -4.0)


func drop_item(id: String, n: int) -> void:
	n = mini(n, int(inv.get(id, 0)))
	if n <= 0:
		return
	inv[id] -= n
	var kind: String = WeaponDB.ITEMS[id]["kind"]
	game.spawn_loot(kind, id, n, 0, -1, drop_position())
	game.hud.refresh_inventory(true)


func drop_weapon(slot: int) -> void:
	var w = slots[slot]
	if w == null:
		return
	slots[slot] = null
	game.spawn_loot("weapon", w["id"], 1, w["rarity"], w["mag"], drop_position())
	if current_slot == slot:
		reloading = false
		rig.reloading = false
		var other := 1 if slot == 2 else 2
		if slots[other] != null:
			equip(other)
		else:
			current_slot = 0
			rig.set_weapon("")
	game.hud.refresh_inventory(true)


func use_item(id: String) -> void:
	if heal_item != "" or int(inv.get(id, 0)) <= 0 or dead:
		return
	match id:
		"bandage", "medkit":
			var cap := 75.0 if id == "bandage" else 100.0
			if hp >= cap:
				game.hud.msg("Health is already high")
				return
			heal_item = id
			heal_total = 2.5 if id == "bandage" else 5.0
			heal_t = heal_total
			reloading = false
			rig.reloading = false
		"grenade":
			throw_grenade()


func finish_heal() -> void:
	var id := heal_item
	heal_item = ""
	if int(inv.get(id, 0)) <= 0:
		return
	inv[id] -= 1
	var cap := 75.0 if id == "bandage" else 100.0
	var amount := 25.0 if id == "bandage" else 100.0
	hp = maxf(hp, minf(cap, hp + amount))
	Sfx.play2d("heal", -4.0)
	game.hud.refresh_inventory(true)


func quick_heal() -> void:
	if hp < 75.0 and int(inv["bandage"]) > 0:
		use_item("bandage")
	elif int(inv["medkit"]) > 0:
		use_item("medkit")
	elif int(inv["bandage"]) > 0:
		use_item("bandage")


# ------------------------------------------------------------------ hud
func ammo_text() -> String:
	var w = current_weapon()
	if w == null:
		return "-"
	var d: Dictionary = WeaponDB.WEAPONS[w["id"]]
	return "%d / %d" % [int(w["mag"]), int(inv[d["ammo"]])]


func weapon_text() -> String:
	var w = current_weapon()
	if w == null:
		return "Unarmed"
	return WeaponDB.display_name("weapon", w["id"], w["rarity"])
