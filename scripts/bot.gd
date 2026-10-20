class_name Bot
extends CharacterBody3D
## AI enemy: wanders over the navmesh, spots the nearest fighter in line of
## sight, chases it, strafes and shoots. Bots also fight each other.

const GRAVITY := 24.0

var game
var display_name := "Bot"
var hp := 100.0
var dead := false
var kills := 0
var placement := 0
var weapon_id := "ar"

var rig: Humanoid
var agent: NavigationAgent3D
var label: Label3D
var target: Node3D = null
var see_target := false
var lost_t := 99.0
var think_t := randf() * 0.3
var react_t := 0.0
var fire_cd := 1.0
var mag := 30
var reload_t := 0.0
var wander_t := 0.0
var path_t := 0.0
var nav_goal := Vector3.ZERO
var strafe_dir := 1.0
var strafe_t := 0.0
var step_acc := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO


func _ready() -> void:
	add_to_group("fighters")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	rig = Humanoid.new()
	add_child(rig)
	rig.build(Color(0.75 + randf() * 0.2, 0.2 + randf() * 0.2, 0.15))
	rig.set_weapon(weapon_id)
	var d: Dictionary = WeaponDB.WEAPONS[weapon_id]
	mag = d["mag"]

	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.5
	agent.radius = 0.5
	agent.height = 1.8
	agent.avoidance_enabled = false
	add_child(agent)

	label = Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color(1.0, 0.5, 0.4)
	label.position.y = 2.2
	label.no_depth_test = true
	label.visibility_range_end = 40.0
	add_child(label)
	last_pos = global_position


func head_y() -> float:
	return 1.5


func chest_y() -> float:
	return 1.2


func _physics_process(delta: float) -> void:
	if dead or not game.running:
		return
	fire_cd = maxf(0.0, fire_cd - delta)
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.3
		_think()
	lost_t += delta

	var move_dir := Vector3.ZERO
	var speed := 3.0
	var outside: bool = game.outside_zone(global_position)

	if see_target and target != null and is_instance_valid(target):
		var to_t := target.global_position - global_position
		to_t.y = 0.0
		var dist := to_t.length()
		_face(to_t, delta)
		if dist > 22.0:
			_set_goal(target.global_position, delta)
			move_dir = _nav_dir()
			speed = 5.0
		elif dist < 8.0:
			move_dir = -to_t.normalized()
			speed = 2.5
		else:
			strafe_t -= delta
			if strafe_t <= 0.0:
				strafe_t = randf_range(1.0, 2.5)
				strafe_dir = -strafe_dir
			move_dir = to_t.normalized().rotated(Vector3.UP, PI * 0.5) * strafe_dir
			speed = 2.2
		_shoot(delta)
	elif outside:
		_set_goal(Vector3(game.zone_center.x, 0.0, game.zone_center.y), delta)
		move_dir = _nav_dir()
		speed = 5.5
	elif target != null and is_instance_valid(target) and lost_t < 5.0:
		_set_goal(target.global_position, delta)
		move_dir = _nav_dir()
		speed = 5.0
	else:
		target = null
		wander_t -= delta
		if wander_t <= 0.0 or global_position.distance_to(nav_goal) < 2.0:
			wander_t = randf_range(6.0, 12.0)
			nav_goal = game.random_nav_point()
			agent.target_position = nav_goal
		move_dir = _nav_dir()
		speed = 3.2

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	velocity.x = move_toward(velocity.x, move_dir.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, move_dir.z * speed, 30.0 * delta)

	# stuck detection: hop and pick a new goal
	stuck_t += delta
	if stuck_t > 1.5:
		stuck_t = 0.0
		if move_dir.length() > 0.1 and global_position.distance_to(last_pos) < 0.5 and is_on_floor():
			velocity.y = 7.0
			wander_t = 0.0
		last_pos = global_position

	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	if not see_target and move_dir.length() > 0.1:
		_face(move_dir, delta)
	rig.animate(delta, hs, is_on_floor())
	if is_on_floor() and hs > 1.0:
		step_acc += hs * delta
		if step_acc > 2.4:
			step_acc = 0.0
			Sfx.play3d("step", global_position, -4.0)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * delta)


func _set_goal(pos: Vector3, delta: float) -> void:
	path_t -= delta
	nav_goal = pos
	if path_t <= 0.0:
		path_t = 0.5
		agent.target_position = pos


func _nav_dir() -> Vector3:
	if not game.nav_ready:
		var d := nav_goal - global_position
		d.y = 0.0
		return d.normalized() if d.length() > 1.0 else Vector3.ZERO
	if agent.is_navigation_finished():
		return Vector3.ZERO
	var d2 := agent.get_next_path_position() - global_position
	d2.y = 0.0
	return d2.normalized() if d2.length() > 0.05 else Vector3.ZERO


func _los(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _think() -> void:
	var eye := global_position + Vector3(0, 1.5, 0)
	var best: Node3D = null
	var best_d := 55.0
	for f in get_tree().get_nodes_in_group("fighters"):
		if f == self:
			continue
		var d := global_position.distance_to(f.global_position)
		if d < best_d:
			var chest: Vector3 = f.global_position + Vector3(0, f.chest_y(), 0)
			if _los(eye, chest):
				best = f
				best_d = d
	if best != null:
		if target != best or not see_target:
			react_t = randf_range(0.4, 0.9)
		target = best
		lost_t = 0.0
		see_target = true
	else:
		see_target = false


func _shoot(delta: float) -> void:
	var d: Dictionary = WeaponDB.WEAPONS[weapon_id]
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			mag = d["mag"]
			rig.reloading = false
		return
	react_t -= delta
	if react_t > 0.0 or fire_cd > 0.0:
		return
	if mag <= 0:
		reload_t = float(d["reload"]) * 1.2
		rig.reloading = true
		Sfx.play3d("reload", global_position, -6.0)
		return
	var eye := global_position + Vector3(0, 1.5, 0)
	var chest: Vector3 = target.global_position + Vector3(0, target.chest_y(), 0)
	var dir := (chest - eye).normalized()
	var fwd := -global_transform.basis.z
	if fwd.dot(Vector3(dir.x, 0, dir.z).normalized()) < 0.9:
		return  # not facing the target yet
	mag -= 1
	fire_cd = float(d["rate"]) * randf_range(1.6, 2.4)
	var dist := eye.distance_to(chest)
	var spread := 0.015 + dist * 0.0009
	if Vector2(target.velocity.x, target.velocity.z).length() > 1.0:
		spread += 0.02
	dir = game.spread_dir(dir, spread)
	var r: Dictionary = game.fire_ray(self, eye, dir, 90.0, float(d["bot_dmg"]))
	var end_pos: Vector3 = eye + dir * 90.0
	if not r.is_empty():
		end_pos = r["position"]
	game.spawn_tracer(rig.muzzle.global_position, end_pos)
	rig.fire()
	Sfx.play3d(d["sound"], eye, -2.0)


func take_damage(amount: float, attacker = null, _pierce: bool = false) -> void:
	if dead:
		return
	hp -= amount
	if attacker != null and is_instance_valid(attacker) and attacker != self:
		if target == null or not see_target:
			target = attacker
			lost_t = 0.0
	if hp <= 0.0:
		hp = 0.0
		die(attacker)


func die(attacker) -> void:
	dead = true
	collision_layer = 0
	remove_from_group("fighters")
	rig.fall()
	label.visible = false
	game.spawn_death_loot(global_position, weapon_id)
	var a = attacker if (attacker != null and is_instance_valid(attacker)) else null
	game.on_fighter_died(self, a)
	await get_tree().create_timer(8.0).timeout
	queue_free()
