# evernight_boss.gd
# Giant Scrap Titan boss fight for the "evernight" event.
# Players defeat it by throwing recycled / compacted trash cubes at it.

class_name EvernightBoss
extends Node3D

signal boss_defeated
signal boss_health_changed(current: float, max_val: float)

var max_hp: float = 300.0
var current_hp: float = 300.0
var is_dead: bool = false

var _hp_label: Label3D = null
var _core_mesh: CSGSphere3D = null
var _player_ref: Node = null
var _attack_timer: float = 6.0
var _ammo_spawn_timer: float = 0.0

func _ready() -> void:
	add_to_group("bosses")
	add_to_group("evernight_boss")
	add_to_group("event_mobs")
	_build_titan_geometry()
	_spawn_compacted_ammo_caches()


func _build_titan_geometry() -> void:
	# Materials
	var rusty_iron := StandardMaterial3D.new()
	rusty_iron.albedo_color = Color(0.25, 0.22, 0.20)
	rusty_iron.metallic = 0.8
	rusty_iron.roughness = 0.5

	var dark_scrap := StandardMaterial3D.new()
	dark_scrap.albedo_color = Color(0.15, 0.14, 0.16)
	dark_scrap.metallic = 0.6
	dark_scrap.roughness = 0.7

	var toxic_core_mat := StandardMaterial3D.new()
	toxic_core_mat.albedo_color = Color(1.0, 0.45, 0.1)
	toxic_core_mat.emission_enabled = true
	toxic_core_mat.emission = Color(1.0, 0.35, 0.05)
	toxic_core_mat.emission_energy_multiplier = 4.0

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.2, 0.95, 1.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.1, 0.85, 1.0)
	eye_mat.emission_energy_multiplier = 4.0

	# 1. Torso Base (Y: 2.5 to 5.5)
	var torso := CSGBox3D.new()
	torso.size = Vector3(3.2, 3.5, 2.2)
	torso.position = Vector3(0, 3.8, 0)
	torso.use_collision = true
	torso.material = rusty_iron
	add_child(torso)

	# 2. Glowing Toxic Heart Core (Center of chest)
	_core_mesh = CSGSphere3D.new()
	_core_mesh.radius = 0.75
	_core_mesh.position = Vector3(0, 0.2, 1.1)
	_core_mesh.material = toxic_core_mat
	torso.add_child(_core_mesh)

	# 3. Smokestacks on shoulders
	for x_side in [-1.3, 1.3]:
		var stack := CSGCylinder3D.new()
		stack.radius = 0.35
		stack.height = 2.0
		stack.position = Vector3(x_side, 2.3, -0.4)
		stack.material = dark_scrap
		torso.add_child(stack)

	# 4. Colossal Head
	var head := CSGBox3D.new()
	head.size = Vector3(1.6, 1.4, 1.5)
	head.position = Vector3(0, 2.3, 0.2)
	head.material = dark_scrap
	torso.add_child(head)

	# Eye Slits
	var eyes := CSGBox3D.new()
	eyes.size = Vector3(1.1, 0.2, 0.1)
	eyes.position = Vector3(0, 0.1, 0.76)
	eyes.material = eye_mat
	head.add_child(eyes)

	# 5. Heavy Hydraulic Arms
	for arm_side in [-1]:
		var arm_l := CSGBox3D.new()
		arm_l.size = Vector3(1.0, 3.2, 1.0)
		arm_l.position = Vector3(-2.1, 0.2, 0.2)
		arm_l.material = rusty_iron
		torso.add_child(arm_l)

	var arm_r := CSGBox3D.new()
	arm_r.size = Vector3(1.0, 3.2, 1.0)
	arm_r.position = Vector3(2.1, 0.2, 0.2)
	arm_r.material = rusty_iron
	torso.add_child(arm_r)

	# 6. Hitbox Area for Detecting Thrown Props
	var hitbox := Area3D.new()
	var h_col := CollisionShape3D.new()
	var h_box := BoxShape3D.new()
	h_box.size = Vector3(5.5, 6.5, 4.5)
	h_col.shape = h_box
	h_col.position = Vector3(0, 3.8, 0)
	hitbox.add_child(h_col)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_child(hitbox)

	# 7. Big Floating 3D Boss Health Bar
	_hp_label = Label3D.new()
	_hp_label.position = Vector3(0, 7.2, 0)
	_hp_label.font_size = 42
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.text = "👹 THE EVERNIGHT COLOSSUS [ 300 / 300 HP ]\n▲ WEAK TO COMPACTED RECYCLED SCRAP!"
	_hp_label.modulate = Color(1.0, 0.35, 0.25)
	add_child(_hp_label)


func _process(delta: float) -> void:
	if is_dead:
		return

	# Slowly face nearest player
	_player_ref = _get_nearest_player()
	if is_instance_valid(_player_ref):
		var target_look: Vector3 = _player_ref.global_position
		target_look.y = global_position.y
		var cur_trans := global_transform
		var desired := cur_trans.looking_at(target_look, Vector3.UP)
		global_transform = cur_trans.interpolate_with(desired, delta * 1.2)

	# Periodic ground stomp shockwave
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = randf_range(8.0, 12.0)
		_perform_stomp()

	# Periodic ammo drop so player never gets stranded
	_ammo_spawn_timer += delta
	if _ammo_spawn_timer >= 15.0:
		_ammo_spawn_timer = 0.0
		_spawn_compacted_ammo_caches()


func _perform_stomp() -> void:
	if is_dead or not is_instance_valid(_player_ref):
		return

	# Camera shake and stomp feedback
	if _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback("⚠️ THE COLOSSUS STOMPS THE GROUND! Earth is shaking!")

	var dist := global_position.distance_to(_player_ref.global_position)
	if dist < 12.0 and _player_ref is CharacterBody3D:
		var push_dir: Vector3 = (_player_ref.global_position - global_position).normalized()
		_player_ref.velocity += push_dir * 8.0 + Vector3.UP * 4.0


func _spawn_compacted_ammo_caches() -> void:
	# Spawns free ammunition boxes of compacted metal and plastic cubes around the outpost
	var offsets := [
		Vector3(-4.0, 0.5, 3.0),
		Vector3(4.0, 0.5, 3.0),
		Vector3(0.0, 0.5, 6.0)
	]
	for offset in offsets:
		var spawn_pos: Vector3 = global_position + offset
		_spawn_ammo_cube(spawn_pos, "compacted_metal" if randf() > 0.5 else "compacted_plastic")


func _spawn_ammo_cube(pos: Vector3, cube_id: String) -> void:
	var body := RigidBody3D.new()
	body.name = "CompactedAmmoCube"
	body.mass = 2.0
	body.position = pos

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	col.shape = box
	body.add_child(col)

	var mesh := CSGBox3D.new()
	mesh.size = Vector3(0.4, 0.4, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.15) if cube_id == "compacted_metal" else Color(0.2, 0.75, 0.95)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.8
	mesh.material = mat
	body.add_child(mesh)

	var script_text := """
extends RigidBody3D
var item_id: String = "%s"
var collection_value: float = 6.0
var weight: float = 2.0
func _ready():
	add_to_group("trash")
	add_to_group("compacted")
func collect():
	queue_free()
""" % cube_id
	var scr := GDScript.new()
	scr.source_code = script_text
	scr.reload()
	body.set_script(scr)

	get_tree().current_scene.add_child(body)


func _on_hitbox_body_entered(body: Node) -> void:
	if is_dead:
		return
	if not body is RigidBody3D:
		return

	var rb := body as RigidBody3D
	if rb.linear_velocity.length() < 2.0:
		return

	# Check if thrown object is compacted recycled scrap vs raw trash
	var is_compacted: bool = rb.is_in_group("compacted") or rb.name.containsn("compact")
	var is_organic_compost: bool = rb.name.containsn("compost") or (rb.get("item_id") == "compost")

	var dmg: float = 0.0
	if is_compacted or is_organic_compost:
		# CRITICAL HIT: 75 HP!
		dmg = 75.0
		take_damage(dmg, true)
	else:
		# Glancing hit: 5 HP chip damage
		dmg = 5.0
		take_damage(dmg, false)

	# Bounce the projectile off violently
	rb.apply_impulse(-rb.linear_velocity.normalized() * 6.0 + Vector3.UP * 4.0)


func take_damage(amount: float, was_critical: bool) -> void:
	if NetworkManager.is_multiplayer_active():
		_rpc_take_damage.rpc(amount, was_critical)
	else:
		_do_take_damage(amount, was_critical)


@rpc("any_peer", "call_local", "reliable")
func _rpc_take_damage(amount: float, was_critical: bool) -> void:
	_do_take_damage(amount, was_critical)


func _do_take_damage(amount: float, was_critical: bool) -> void:
	if is_dead:
		return

	current_hp = maxf(0.0, current_hp - amount)
	boss_health_changed.emit(current_hp, max_hp)

	# Flash glowing core
	if _core_mesh and _core_mesh.material:
		var mat := _core_mesh.material as StandardMaterial3D
		mat.albedo_color = Color(1.0, 1.0, 1.0)
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color", Color(1.0, 0.45, 0.1), 0.25)

	var pct: int = int((current_hp / max_hp) * 100.0)
	if was_critical:
		_hp_label.text = "💥 CRITICAL HIT! [ %d / %d HP ]\n-%.0f HP FROM COMPACTED SCRAP!" % [int(current_hp), int(max_hp), amount]
		_hp_label.modulate = Color(1.0, 0.9, 0.2)
		if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
			_player_ref._show_feedback("💥 CRITICAL HIT ON COLOSSUS! -%.0f HP (%d%% remaining)" % [amount, pct])
	else:
		_hp_label.text = "⚠️ GLANCING HIT -%.0f HP [ %d / %d HP ]\n▲ USE RECYCLED COMPACTED CUBES!" % [amount, int(current_hp), int(max_hp)]
		_hp_label.modulate = Color(1.0, 0.4, 0.3)
		if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
			_player_ref._show_feedback("⚠️ Glancing Hit -%.0f HP. Throw COMPACTED cubes for massive damage!" % amount)

	if current_hp <= 0.0:
		die()


func die() -> void:
	is_dead = true
	_hp_label.text = "🏆 THE EVERNIGHT COLOSSUS DEFEATED!\nSUNLIGHT BREAKS THROUGH THE SKY!"
	_hp_label.modulate = Color(0.3, 1.0, 0.5)

	# Award massive cash bounty
	if is_instance_valid(_player_ref) and "slop_credit" in _player_ref:
		_player_ref.slop_credit += 35.0
		if _player_ref.has_signal("slop_credit_changed"):
			_player_ref.slop_credit_changed.emit(_player_ref.slop_credit, 35.0)
		if _player_ref.has_method("_show_feedback"):
			_player_ref._show_feedback("🏆 VICTORY! Evernight Colossus defeated! (+$35 SC)")

	# Collapse animation
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 4.0, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		boss_defeated.emit()
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
