# peaceful_critter.gd
# Cute mountain critter that wanders peacefully and can be tamed by feeding organic trash.
# Used for the "make_peace" random event.

class_name PeacefulCritter
extends CharacterBody3D

signal critter_tamed
signal critter_fed(hearts_fed: int, max_hearts: int)

var is_tamed: bool = false
var hearts_fed: int = 0
const HEARTS_NEEDED: int = 3

var _prompt_label: Label3D = null
var _player_nearby: bool = false
var _player_ref: Node = null

var _wander_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _body_mesh: CSGBox3D = null

func _ready() -> void:
	add_to_group("critters")
	add_to_group("peaceful_critter")
	add_to_group("peaceful_critters")
	add_to_group("event_mobs")
	_build_critter_mesh()
	_pick_new_wander_target()


func _build_critter_mesh() -> void:
	var critter_mat := StandardMaterial3D.new()
	critter_mat.albedo_color = Color(0.42, 0.68, 0.38) # Cute mossy green / meadow fur
	critter_mat.roughness = 0.8

	var belly_mat := StandardMaterial3D.new()
	belly_mat.albedo_color = Color(0.92, 0.88, 0.78)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.08, 0.08, 0.10)
	eye_mat.metallic = 0.9
	eye_mat.roughness = 0.1

	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.95, 0.45, 0.55)

	# Main Body
	_body_mesh = CSGBox3D.new()
	_body_mesh.size = Vector3(0.65, 0.45, 0.85)
	_body_mesh.position = Vector3(0, 0.35, 0)
	_body_mesh.material = critter_mat
	add_child(_body_mesh)

	# Belly
	var belly := CSGBox3D.new()
	belly.size = Vector3(0.55, 0.25, 0.7)
	belly.position = Vector3(0, -0.1, 0)
	belly.material = belly_mat
	_body_mesh.add_child(belly)

	# Head
	var head := CSGBox3D.new()
	head.size = Vector3(0.45, 0.38, 0.45)
	head.position = Vector3(0, 0.15, -0.45)
	head.material = critter_mat
	_body_mesh.add_child(head)

	# Nose
	var nose := CSGBox3D.new()
	nose.size = Vector3(0.12, 0.1, 0.12)
	nose.position = Vector3(0, -0.05, -0.25)
	nose.material = nose_mat
	head.add_child(nose)

	# Eyes
	var eye_l := CSGSphere3D.new()
	eye_l.radius = 0.06
	eye_l.position = Vector3(-0.16, 0.08, -0.2)
	eye_l.material = eye_mat
	head.add_child(eye_l)

	var eye_r := CSGSphere3D.new()
	eye_r.radius = 0.06
	eye_r.position = Vector3(0.16, 0.08, -0.2)
	eye_r.material = eye_mat
	head.add_child(eye_r)

	# Ears
	var ear_l := CSGBox3D.new()
	ear_l.size = Vector3(0.12, 0.18, 0.08)
	ear_l.position = Vector3(-0.18, 0.25, 0.05)
	ear_l.material = nose_mat
	head.add_child(ear_l)

	var ear_r := CSGBox3D.new()
	ear_r.size = Vector3(0.12, 0.18, 0.08)
	ear_r.position = Vector3(0.18, 0.25, 0.05)
	ear_r.material = nose_mat
	head.add_child(ear_r)

	# Tail
	var tail := CSGCylinder3D.new()
	tail.radius = 0.08
	tail.height = 0.35
	tail.position = Vector3(0, 0.1, 0.45)
	tail.rotation_degrees = Vector3(45, 0, 0)
	tail.material = critter_mat
	_body_mesh.add_child(tail)

	# Collision
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.6, 1.0)
	col.shape = box
	col.position = Vector3(0, 0.35, 0)
	add_child(col)

	# Interaction Area
	var area := Area3D.new()
	var area_col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	area_col.shape = sphere
	area.add_child(area_col)
	area.body_entered.connect(_on_player_entered)
	area.body_exited.connect(_on_player_exited)
	add_child(area)

	# Prompt Label
	_prompt_label = Label3D.new()
	_prompt_label.position = Vector3(0, 1.2, 0)
	_prompt_label.font_size = 28
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.text = "🌿 Mountain Possum\n[E] Feed Snack (0/3 ❤️)"
	_prompt_label.modulate = Color(0.95, 0.85, 0.35)
	_prompt_label.visible = false
	add_child(_prompt_label)


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


func _physics_process(delta: float) -> void:
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)

	if not NetworkManager.is_host():
		var t := clampf(delta * 12.0, 0.0, 1.0)
		global_position = global_position.lerp(_net_pos, t)
		rotation.y = lerp_angle(rotation.y, _net_rot_y, t)
		if _player_nearby and not is_tamed:
			if Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_E):
				feed_critter()
		return

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	if stun_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
	elif is_tamed and is_instance_valid(_player_ref):
		# Follow player affectionately
		var to_p: Vector3 = _player_ref.global_position - global_position
		to_p.y = 0.0
		if to_p.length() > 2.5:
			var dir := to_p.normalized()
			velocity.x = dir.x * 3.5
			velocity.z = dir.z * 3.5
			look_at(global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
		else:
			velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
	else:
		# Check if lured by a nearby Peaceful Trap
		var trap_target: Node3D = null
		var best_trap_dist := INF
		for trap in get_tree().get_nodes_in_group("peaceful_traps"):
			if trap is Node3D and is_instance_valid(trap) and trap.get("_cooldown_timer") == 0.0:
				var r: float = trap.get("attract_radius") if trap.get("attract_radius") != null else 24.0
				var d := global_position.distance_to(trap.global_position)
				if d <= r and d < best_trap_dist:
					best_trap_dist = d
					trap_target = trap

		if trap_target:
			_wander_target = trap_target.global_position
		else:
			# Wander around gently
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				_pick_new_wander_target()

		var to_tgt: Vector3 = _wander_target - global_position
		to_tgt.y = 0.0
		if to_tgt.length() > 0.5:
			var dir := to_tgt.normalized()
			velocity.x = dir.x * 1.5
			velocity.z = dir.z * 1.5
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

	if _player_nearby and not is_tamed:
		if Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_E):
			feed_critter()


func _pick_new_wander_target() -> void:
	_wander_timer = randf_range(2.5, 5.0)
	_wander_target = global_position + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))


func _on_player_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_ref = body
		_player_nearby = true
		_update_prompt()
		_prompt_label.visible = true


func _on_player_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		_prompt_label.visible = false


func _update_prompt() -> void:
	if is_tamed:
		_prompt_label.text = "❤️ Tamed Companion!\n(Following you)"
		_prompt_label.modulate = Color(0.3, 1.0, 0.5)
	else:
		_prompt_label.text = "🌿 Mountain Possum\n[E] Feed Snack (%d/%d ❤️)" % [hearts_fed, HEARTS_NEEDED]
		_prompt_label.modulate = Color(1.0, 0.85, 0.3)


func feed_critter() -> void:
	if is_tamed:
		return

	# Deduct 1 organic item or snack if available on player
	if is_instance_valid(_player_ref) and "trash_bag" in _player_ref:
		for organic_id in ["banana", "banana_peel", "kulit_pisang", "apple", "organic", "compost"]:
			if _player_ref.trash_bag.get(organic_id, 0) > 0:
				_player_ref.trash_bag[organic_id] -= 1
				_player_ref.total_items_in_bag = maxi(0, _player_ref.total_items_in_bag - 1)
				_player_ref._update_hud()
				break

	hearts_fed += 1

	# Happy hop bounce animation
	var tw := create_tween()
	tw.tween_property(_body_mesh, "position:y", 0.75, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body_mesh, "position:y", 0.35, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback("❤️ The critter enjoyed the snack! (%d/%d)" % [hearts_fed, HEARTS_NEEDED])

	_update_prompt()
	critter_fed.emit(hearts_fed, HEARTS_NEEDED)

	if hearts_fed >= HEARTS_NEEDED:
		is_tamed = true
		_update_prompt()
		if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
			_player_ref._show_feedback("🎉 CRITTER TAMED! A loyal friend now journeys with you!")
		critter_tamed.emit()

	if NetworkManager.is_multiplayer_active():
		_rpc_sync_feed.rpc(hearts_fed, is_tamed)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_pose(pos: Vector3, rot_y: float) -> void:
	_net_pos = pos
	_net_rot_y = rot_y


@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_feed(new_hearts: int, tamed: bool) -> void:
	hearts_fed = new_hearts
	is_tamed = tamed
	_update_prompt()
	critter_fed.emit(hearts_fed, HEARTS_NEEDED)
	if is_tamed:
		critter_tamed.emit()
