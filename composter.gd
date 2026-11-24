# composter.gd
# Machine: Composter
# Accepts organic trash from player inventory and produces compost bags.
# When a compost bag lands on the ground, it plants a tree sapling that grows over days.

class_name Composter
extends Area3D

signal processing_started(item_count: int)
signal processing_finished(compost_produced: int)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@export_group("Machine Settings")
## How many organic items are needed to produce one compost bag
@export var items_per_compost: int = 5
## Time in seconds to compost a batch
@export var process_duration: float = 5.0

@export_group("Tree Growth")
## How many in-game days for a sapling to reach full size
@export var growth_days: int = 3
## Scale of the sapling when first planted (fraction of full size)
@export var sapling_scale: float = 0.2
## Full-grown tree scale
@export var full_tree_scale: float = 1.0

@export_group("Interaction")
@export var interact_distance: float = 3.5
@export var input_interact: String = "interact"

@export_group("Visual Feedback")
@export var eject_force: float = 4.0
@export var eject_up_force: float = 3.0

# ---------------------------------------------------------------------------
# Internal State
# ---------------------------------------------------------------------------
var _organic_buffer: int = 0
var _is_processing: bool = false
var _process_timer: float = 0.0
var _player_ref: Node = null
var _player_nearby: bool = false

var _prompt_label: Label3D = null
var output_point: Node3D = null


func _ready() -> void:
	add_to_group("machines")
	add_to_group("composter")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	output_point = get_node_or_null("OutputPoint")
	if not output_point:
		output_point = Marker3D.new()
		output_point.name = "OutputPoint"
		output_point.position = Vector3(1.2, 0.6, 0.0)
		add_child(output_point)

	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = get_node_or_null("PromptLabel3D") as Label3D
	if not _prompt_label:
		_prompt_label = Label3D.new()
		_prompt_label.name = "PromptLabel3D"
		_prompt_label.font_size = 36
		_prompt_label.modulate = Color(0.35, 1.0, 0.45, 1.0)
		_prompt_label.outline_render_priority = 1
		_prompt_label.position = Vector3(0, 2.0, 0)
		_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_prompt_label.no_depth_test = true
		_prompt_label.visible = false
		add_child(_prompt_label)


func _process(delta: float) -> void:
	_check_player_proximity()
	_update_prompt()

	if _player_nearby and not _is_processing:
		if InputMap.has_action(input_interact) and Input.is_action_just_pressed(input_interact):
			_try_deposit_organic()

	if _is_processing:
		_process_timer += delta
		if _process_timer >= process_duration:
			_finish_processing()


func _check_player_proximity() -> void:
	if not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
		if not _player_ref:
			_player_nearby = false
			return

	var dist := global_position.distance_to(_player_ref.global_position)
	_player_nearby = (dist <= interact_distance)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_nearby or not is_instance_valid(_player_ref):
		return

	var pressed := false
	if InputMap.has_action(input_interact) and event.is_action_pressed(input_interact):
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.physical_keycode == KEY_E:
			pressed = true

	if pressed:
		_try_deposit_organic()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "ProtoController":
		_player_ref = body
		_player_nearby = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_ref:
		_check_player_proximity()


# ---------------------------------------------------------------------------
# Deposit Organic Items
# ---------------------------------------------------------------------------

func _is_organic_item(id_str: String) -> bool:
	id_str = id_str.to_lower()
	var organic_keywords := [
		"kulit_pisang", "pisang", "banana", "organic", "organik",
		"food", "makanan", "leaf", "daun", "fruit", "buah",
		"compost", "bio", "sayur", "vegetable", "bananapeel"
	]
	for kw in organic_keywords:
		if id_str.contains(kw):
			return true
	return false


func _try_deposit_organic() -> void:
	if _is_processing:
		_notify_player("🌿 Composter is processing... Wait!")
		return

	if not is_instance_valid(_player_ref):
		_notify_player("Player not found!")
		return

	if not "trash_inventory_items" in _player_ref:
		_notify_player("No inventory found on player!")
		return

	var items: Array = _player_ref.trash_inventory_items
	var organic_indices: Array[int] = []

	for i in range(items.size()):
		var item: Dictionary = items[i]
		var id_str: String = str(item.get("id", "")).to_lower()
		if _is_organic_item(id_str):
			organic_indices.append(i)

	if organic_indices.is_empty():
		_notify_player("🌿 No organic trash in your bag! (Bag banana peels or food first)")
		return

	var deposited: int = 0
	organic_indices.reverse()
	for idx in organic_indices:
		var item_data: Dictionary = items[idx]
		var id: String = item_data.get("id", "trash")

		_player_ref.trash_inventory_items.remove_at(idx)
		if "trash_bag" in _player_ref and _player_ref.trash_bag.has(id):
			_player_ref.trash_bag[id] -= 1
			if _player_ref.trash_bag[id] <= 0:
				_player_ref.trash_bag.erase(id)
		if "total_items_in_bag" in _player_ref:
			_player_ref.total_items_in_bag = max(0, _player_ref.total_items_in_bag - 1)
		deposited += 1

	_organic_buffer += deposited

	if _player_ref.has_method("_update_hud"):
		_player_ref._update_hud()

	_notify_player("🌿 Deposited %d organic item(s). Buffer: %d / %d" % [deposited, _organic_buffer, items_per_compost])

	if _organic_buffer >= items_per_compost and not _is_processing:
		_start_processing()


func _start_processing() -> void:
	_is_processing = true
	_process_timer = 0.0
	processing_started.emit(_organic_buffer)
	_notify_player("🌿 Composter activated! Fermenting compost...")


func _finish_processing() -> void:
	var compost_to_produce: int = _organic_buffer / items_per_compost
	var leftover: int = _organic_buffer % items_per_compost
	_organic_buffer = leftover

	for i in range(compost_to_produce):
		_spawn_compost(i)

	_is_processing = false
	_process_timer = 0.0
	processing_finished.emit(compost_to_produce)
	_notify_player("✅ Produced %d Compost Bag(s)! Toss onto the ground to plant trees." % compost_to_produce)


func _spawn_compost(index: int) -> void:
	var spawn_pos: Vector3 = output_point.global_position if output_point else global_position + Vector3(1.2, 0.6, 0.0)
	spawn_pos += Vector3(0, float(index) * 0.4, randf_range(-0.2, 0.2))

	var body := RigidBody3D.new()
	body.name = "CompostBag"
	body.mass = 2.0

	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.4, 0.3, 0.4)
	col_shape.shape = box_shape
	body.add_child(col_shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.4, 0.3, 0.4)
	mesh.mesh = box_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.25, 0.12, 1.0)
	mat.roughness = 0.95
	mesh.material_override = mat
	body.add_child(mesh)

	var growth_d: int = growth_days
	var sap_s: float = sapling_scale
	var full_s: float = full_tree_scale

	var script_text := """
extends RigidBody3D

var item_id: String = "compost"
var collection_value: float = 2.0
var weight: float = 2.0
var _planted: bool = false
var _ground_timer: float = 0.0

func _ready() -> void:
	add_to_group("floatable")
	add_to_group("trash")
	contact_monitor = true
	max_contacts_reported = 4

func _physics_process(delta: float) -> void:
	if _planted:
		return
	if get_contact_count() > 0 and linear_velocity.length() < 0.4:
		_ground_timer += delta
		if _ground_timer >= 2.0:
			_plant_tree()
	else:
		_ground_timer = 0.0

func _plant_tree() -> void:
	if _planted:
		return
	_planted = true

	var plant_pos := global_position
	var tree_grower := Node3D.new()
	tree_grower.name = "GrowingTree"
	tree_grower.set_script(_create_tree_grower_script())
	tree_grower.set_meta("growth_days", %d)
	tree_grower.set_meta("sapling_scale", %.2f)
	tree_grower.set_meta("full_scale", %.2f)
	get_tree().current_scene.add_child(tree_grower)
	tree_grower.global_position = plant_pos

	print("Compost: Tree planted at %%s!" %% str(plant_pos))
	queue_free()

func _create_tree_grower_script() -> GDScript:
	var src := \"\"\"
extends Node3D

var days_planted: int = 0
var growth_days: int = 3
var sapling_scale: float = 0.2
var full_scale: float = 1.0
var _tree_mesh: Node3D = null

func _ready() -> void:
	growth_days = get_meta("growth_days", 3)
	sapling_scale = get_meta("sapling_scale", 0.2)
	full_scale = get_meta("full_scale", 1.0)
	add_to_group("growing_trees")
	_create_simple_tree()
	_update_growth()

	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and dnc.has_signal("day_started"):
		dnc.day_started.connect(_on_day_started)

func _on_day_started(day_number: int) -> void:
	days_planted += 1
	_update_growth()
	print("GrowingTree: Day %%d. Scale: %%.2f" %%%% [day_number, _tree_mesh.scale.y])

func _update_growth() -> void:
	var t: float = clampf(float(days_planted) / float(growth_days), 0.0, 1.0)
	var s: float = lerpf(sapling_scale, full_scale, t)
	if _tree_mesh:
		_tree_mesh.scale = Vector3.ONE * s

func _create_simple_tree() -> void:
	_tree_mesh = Node3D.new()
	_tree_mesh.name = "TreeModel"
	add_child(_tree_mesh)

	var trunk_mesh := MeshInstance3D.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.25
	trunk.height = 2.5
	trunk_mesh.mesh = trunk
	trunk_mesh.position = Vector3(0, 1.25, 0)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.1)
	trunk_mesh.material_override = trunk_mat
	_tree_mesh.add_child(trunk_mesh)

	var canopy_mesh := MeshInstance3D.new()
	var canopy := SphereMesh.new()
	canopy.radius = 1.2
	canopy.height = 2.0
	canopy_mesh.mesh = canopy
	canopy_mesh.position = Vector3(0, 3.0, 0)
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.18, 0.6, 0.25)
	canopy_mesh.material_override = canopy_mat
	_tree_mesh.add_child(canopy_mesh)
\"\"\"
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s

func collect() -> void:
	queue_free()
""" % [growth_d, sap_s, full_s]

	var script := GDScript.new()
	script.source_code = script_text
	script.reload()
	body.set_script(script)

	get_tree().current_scene.add_child(body)
	body.global_position = spawn_pos

	var dir: Vector3 = (output_point.global_position - global_position).normalized() if output_point else Vector3(1, 0.5, 0).normalized()
	body.apply_impulse(dir * eject_force + Vector3.UP * eject_up_force)


func _update_prompt() -> void:
	if not _prompt_label:
		return

	if _player_nearby and not _is_processing:
		_prompt_label.visible = true
		if _organic_buffer > 0:
			_prompt_label.text = "[E] Deposit Organic (%d/%d)" % [_organic_buffer, items_per_compost]
		else:
			_prompt_label.text = "[E] Deposit Organic Trash"
	elif _is_processing:
		_prompt_label.visible = true
		var pct: int = int(clampf(_process_timer / process_duration, 0.0, 1.0) * 100)
		_prompt_label.text = "🌿 Composting... %d%%" % pct
	else:
		_prompt_label.visible = false


func _notify_player(msg: String) -> void:
	if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback(msg)
	print("Composter: %s" % msg)
