# evil_critter.gd
# Feral scrap beast that raids trash piles and must be hunted down with thrown items.
# Used for the "open_season" random event.

class_name EvilCritter
extends CharacterBody3D

signal critter_defeated
signal critter_health_changed(current: float, max_v: float)

var max_hp: float = 100.0
var current_hp: float = 100.0
var is_defeated: bool = false

var _hp_label: Label3D = null
var _body_mesh: CSGBox3D = null
var _wander_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _player_ref: Node = null

func _ready() -> void:
	add_to_group("critters")
	add_to_group("evil_critter")
	add_to_group("evil_critters")
	add_to_group("event_mobs")
	_build_evil_mesh()
	_pick_new_target()


func _build_evil_mesh() -> void:
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.18, 0.12, 0.22) # Feral dark scrap purple
	dark_mat.roughness = 0.6
	dark_mat.metallic = 0.4

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.15, 0.15)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.1, 0.1)
	eye_mat.emission_energy_multiplier = 3.0

	var spine_mat := StandardMaterial3D.new()
	spine_mat.albedo_color = Color(0.85, 0.25, 0.25)
	spine_mat.roughness = 0.5

	# Main Body
	_body_mesh = CSGBox3D.new()
	_body_mesh.size = Vector3(0.9, 0.6, 1.1)
	_body_mesh.position = Vector3(0, 0.4, 0)
	_body_mesh.material = dark_mat
	add_child(_body_mesh)

	# Spines on back
	for z_off in [-0.2, 0.1, 0.4]:
		var spine := CSGBox3D.new()
		spine.size = Vector3(0.15, 0.35, 0.15)
		spine.position = Vector3(0, 0.4, z_off)
		spine.rotation_degrees = Vector3(-25, 0, 0)
		spine.material = spine_mat
		_body_mesh.add_child(spine)

	# Feral Head
	var head := CSGBox3D.new()
	head.size = Vector3(0.65, 0.5, 0.6)
	head.position = Vector3(0, 0.15, -0.6)
	head.material = dark_mat
	_body_mesh.add_child(head)

	# Glowing Red Eyes
	var eye_l := CSGSphere3D.new()
	eye_l.radius = 0.09
	eye_l.position = Vector3(-0.2, 0.1, -0.28)
	eye_l.material = eye_mat
	head.add_child(eye_l)

	var eye_r := CSGSphere3D.new()
	eye_r.radius = 0.09
	eye_r.position = Vector3(0.2, 0.1, -0.28)
	eye_r.material = eye_mat
	head.add_child(eye_r)

	# Collision
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 0.8, 1.4)
	col.shape = box
	col.position = Vector3(0, 0.4, 0)
	add_child(col)

	# Hitbox Area (detects thrown props)
	var hitbox := Area3D.new()
	var h_col := CollisionShape3D.new()
	var h_box := BoxShape3D.new()
	h_box.size = Vector3(1.6, 1.2, 1.8)
	h_col.shape = h_box
	h_col.position = Vector3(0, 0.5, 0)
	hitbox.add_child(h_col)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_child(hitbox)

	# 3D HP Floating Label
	_hp_label = Label3D.new()
	_hp_label.position = Vector3(0, 1.4, 0)
	_hp_label.font_size = 32
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.text = "👹 FERAL PEST [ 100 / 100 HP ]"
	_hp_label.modulate = Color(1.0, 0.35, 0.35)
	add_child(_hp_label)


var _net_pos: Vector3 = Vector3.ZERO
var _net_rot_y: float = 0.0
var _net_sync_accum: float = 0.0
var stun_timer: float = 0.0


func apply_stun(duration: float) -> void:
	if NetworkManager.is_multiplayer_active():
		_rpc_stun.rpc(duration)
	else:
		_do_stun(duration)


@rpc("any_peer", "call_local", "reliable")
func _rpc_stun(duration: float) -> void:
	_do_stun(duration)


func _do_stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)
	if is_instance_valid(_hp_label):
		_hp_label.text = "⚡ STUNNED! [ %d / %d HP ]" % [int(current_hp), int(max_hp)]


func _physics_process(delta: float) -> void:
	if is_defeated:
		return

	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		if stun_timer == 0.0 and is_instance_valid(_hp_label):
			_hp_label.text = "👹 FERAL PEST [ %d / %d HP ]" % [int(current_hp), int(max_hp)]

	if not NetworkManager.is_host():
		var t := clampf(delta * 12.0, 0.0, 1.0)
		global_position = global_position.lerp(_net_pos, t)
		rotation.y = lerp_angle(rotation.y, _net_rot_y, t)
		return

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	if stun_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		if NetworkManager.is_multiplayer_active():
			_net_sync_accum += delta
			if _net_sync_accum >= 0.05:
				_net_sync_accum = 0.0
				_rpc_sync_pose.rpc(global_position, rotation.y)
		return

	# Check if lured by a nearby Hostile Trap
	var trap_target: Node3D = null
	var best_trap_dist := INF
	for trap in get_tree().get_nodes_in_group("hostile_traps"):
		if trap is Node3D and is_instance_valid(trap) and trap.get("_cooldown_timer") == 0.0:
			var r: float = trap.get("attract_radius") if trap.get("attract_radius") != null else 24.0
			var d := global_position.distance_to(trap.global_position)
			if d <= r and d < best_trap_dist:
				best_trap_dist = d
				trap_target = trap

	if trap_target:
		_wander_target = trap_target.global_position
	else:
		# Feral erratic scuttle AI
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_new_target()

	var to_tgt: Vector3 = _wander_target - global_position
	to_tgt.y = 0.0
	if to_tgt.length() > 0.5:
		var dir := to_tgt.normalized()
		velocity.x = dir.x * 3.8
		velocity.z = dir.z * 3.8
		look_at(global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()

	if NetworkManager.is_multiplayer_active():
		_net_sync_accum += delta
		if _net_sync_accum >= 0.05:
			_net_sync_accum = 0.0
			_rpc_sync_pose.rpc(global_position, rotation.y)


func _pick_new_target() -> void:
	_wander_timer = randf_range(1.5, 3.2)
	_wander_target = global_position + Vector3(randf_range(-7.0, 7.0), 0, randf_range(-7.0, 7.0))


func _on_hitbox_body_entered(body: Node) -> void:
	if is_defeated:
		return
	if not body is RigidBody3D:
		return

	var rb := body as RigidBody3D
	# Only take damage if the object was thrown / has notable velocity
	if rb.linear_velocity.length() < 2.5:
		return

	var is_compacted: bool = rb.is_in_group("compacted") or rb.name.containsn("compact")
	var dmg: float = 50.0 if is_compacted else 25.0

	take_damage(dmg, is_compacted)

	# Bounce the thrown prop off
	rb.apply_impulse(-rb.linear_velocity.normalized() * 4.0 + Vector3.UP * 3.0)


func take_damage(amount: float, was_critical: bool = false) -> void:
	if is_defeated:
		return

	current_hp = maxf(0.0, current_hp - amount)

	# Hit flash
	var orig_color = Color(0.18, 0.12, 0.22)
	if _body_mesh and _body_mesh.material:
		var mat := _body_mesh.material as StandardMaterial3D
		mat.albedo_color = Color(1.0, 0.3, 0.3)
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color", orig_color, 0.2)

	# Shake / jump back
	velocity = -transform.basis.z * 5.0 + Vector3.UP * 4.0

	# Update HP label
	var pct: int = int((current_hp / max_hp) * 100.0)
	var crit_tag := " 💥 CRIT!" if was_critical else ""
	_hp_label.text = "👹 FERAL PEST [ %d / %d HP ]%s" % [int(current_hp), int(max_hp), crit_tag]
	critter_health_changed.emit(current_hp, max_hp)

	if _player_ref == null:
		_player_ref = _get_nearest_player()
	if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback("💥 Hit Feral Pest! -%.0f HP (%d%% remaining)" % [amount, pct])

	if current_hp <= 0.0:
		die()


func die() -> void:
	is_defeated = true
	_hp_label.text = "☠️ DEFEATED!"
	_hp_label.modulate = Color(0.4, 1.0, 0.4)

	# Award bonus SlopCredits to player
	if is_instance_valid(_player_ref) and "slop_credit" in _player_ref:
		_player_ref.slop_credit += 22.0
		if _player_ref.has_signal("slop_credit_changed"):
			_player_ref.slop_credit_changed.emit(_player_ref.slop_credit, 22.0)
		if _player_ref.has_method("_show_feedback"):
			_player_ref._show_feedback("🏆 HUNT COMPLETE! Feral Pest Defeated! (+$22 SC)")

	# Shrink / explode animation
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		critter_defeated.emit()
		queue_free()
	)


func _get_nearest_player() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node3D and is_instance_valid(p):
			var d := global_position.distance_squared_to(p.global_position)
			if d < best_dist:
				best_dist = d
				best = p
	if best == null:
		best = get_tree().get_first_node_in_group("player") as Node3D
	return best


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_pose(pos: Vector3, rot_y: float) -> void:
	_net_pos = pos
	_net_rot_y = rot_y
