# metal_crusher.gd
# Machine: Metal Crusher
# Accepts metal trash items from player inventory and produces compacted metal cubes.

class_name MetalCrusher
extends Area3D

signal processing_started(item_count: int)
signal processing_finished(cubes_produced: int)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@export_group("Machine Settings")
## How many metal items are needed to produce one compacted cube
@export var items_per_cube: int = 3
## Time in seconds to process one batch into a cube
@export var process_duration: float = 3.0
## Scene to instantiate as the output cube (leave empty for auto-generated cube)
@export var compacted_metal_cube_scene: PackedScene = null

@export_group("Interaction")
## Interaction radius (works as fallback even without collision shape)
@export var interact_distance: float = 3.5
## Input action name for interacting
@export var input_interact: String = "interact"

@export_group("Visual Feedback")
## Ejection force applied to the output cube
@export var eject_force: float = 5.0
## Upward bias when ejecting
@export var eject_up_force: float = 3.0

# ---------------------------------------------------------------------------
# Internal State
# ---------------------------------------------------------------------------
var _metal_buffer: int = 0
var _is_processing: bool = false
var _process_timer: float = 0.0
var _player_ref: Node = null
var _player_nearby: bool = false

var _prompt_label: Label3D = null
var output_point: Node3D = null


func _ready() -> void:
	add_to_group("machines")
	add_to_group("metal_crusher")

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
		_prompt_label.modulate = Color(1.0, 0.88, 0.3, 1.0)
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
			_try_deposit_metal()

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
		_try_deposit_metal()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "ProtoController":
		_player_ref = body
		_player_nearby = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_ref:
		_check_player_proximity()


# ---------------------------------------------------------------------------
# Deposit Metal Items
# ---------------------------------------------------------------------------

func _is_metal_item(id_str: String) -> bool:
	id_str = id_str.to_lower()
	var metal_words := ["can", "metal", "kaleng", "besi", "crush", "tin"]
	for w in metal_words:
		if id_str.contains(w):
			return true
	return false


func _try_deposit_metal() -> void:
	if _is_processing:
		_notify_player("⚙️ Crusher is processing... Wait!")
		return

	if not is_instance_valid(_player_ref):
		_notify_player("Player not found!")
		return

	if not "trash_inventory_items" in _player_ref:
		_notify_player("No inventory found on player!")
		return

	var items: Array = _player_ref.trash_inventory_items
	var metal_indices: Array[int] = []

	for i in range(items.size()):
		var item: Dictionary = items[i]
		var id_str: String = str(item.get("id", "")).to_lower()
		if _is_metal_item(id_str):
			metal_indices.append(i)

	if metal_indices.is_empty():
		_notify_player("🔩 No metal trash in your bag! (Hold L-Click to bag cans first)")
		return

	var deposited: int = 0
	metal_indices.reverse()
	for idx in metal_indices:
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

	_metal_buffer += deposited

	if _player_ref.has_method("_update_hud"):
		_player_ref._update_hud()

	_notify_player("🔩 Deposited %d metal item(s). Buffer: %d / %d" % [deposited, _metal_buffer, items_per_cube])

	if _metal_buffer >= items_per_cube and not _is_processing:
		_start_processing()


func _start_processing() -> void:
	_is_processing = true
	_process_timer = 0.0
	processing_started.emit(_metal_buffer)
	_notify_player("⚙️ Crusher activated! Compacting metal...")


func _finish_processing() -> void:
	var cubes_to_produce: int = _metal_buffer / items_per_cube
	var leftover: int = _metal_buffer % items_per_cube
	_metal_buffer = leftover

	for i in range(cubes_to_produce):
		_spawn_compacted_cube(i)

	_is_processing = false
	_process_timer = 0.0
	processing_finished.emit(cubes_to_produce)
	_notify_player("✅ Produced %d Compacted Metal Cube(s)!" % cubes_to_produce)


func _spawn_compacted_cube(index: int) -> void:
	var spawn_pos: Vector3 = output_point.global_position if output_point else global_position + Vector3(1.2, 0.6, 0.0)
	spawn_pos += Vector3(0, float(index) * 0.4, randf_range(-0.2, 0.2))

	if compacted_metal_cube_scene:
		var instance = compacted_metal_cube_scene.instantiate()
		get_tree().current_scene.add_child(instance)
		instance.global_position = spawn_pos
		if instance is RigidBody3D:
			var dir := (output_point.global_position - global_position).normalized()
			instance.apply_impulse(dir * eject_force + Vector3.UP * eject_up_force)
	else:
		_spawn_default_metal_cube(spawn_pos)


func _spawn_default_metal_cube(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "CompactedMetalCube"
	body.mass = 3.0

	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.4, 0.4, 0.4)
	col_shape.shape = box_shape
	body.add_child(col_shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.4, 0.4, 0.4)
	mesh.mesh = box_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.7, 0.75, 1.0)
	mat.metallic = 0.9
	mat.roughness = 0.25
	mesh.material_override = mat
	body.add_child(mesh)

	var script_text := """
extends RigidBody3D
var item_id: String = "compacted_metal"
var collection_value: float = 5.0
var weight: float = 3.0

func _ready() -> void:
	add_to_group("floatable")
	add_to_group("trash")
	add_to_group("compacted")

func collect() -> void:
	queue_free()
"""
	var script := GDScript.new()
	script.source_code = script_text
	script.reload()
	body.set_script(script)

	get_tree().current_scene.add_child(body)
	body.global_position = pos

	var dir: Vector3 = (output_point.global_position - global_position).normalized() if output_point else Vector3(1, 0.5, 0).normalized()
	body.apply_impulse(dir * eject_force + Vector3.UP * eject_up_force)


func _update_prompt() -> void:
	if not _prompt_label:
		return

	if _player_nearby and not _is_processing:
		_prompt_label.visible = true
		if _metal_buffer > 0:
			_prompt_label.text = "[E] Deposit Metal (%d/%d)" % [_metal_buffer, items_per_cube]
		else:
			_prompt_label.text = "[E] Deposit Metal Trash"
	elif _is_processing:
		_prompt_label.visible = true
		var pct: int = int(clampf(_process_timer / process_duration, 0.0, 1.0) * 100)
		_prompt_label.text = "⚙️ Crushing... %d%%" % pct
	else:
		_prompt_label.visible = false


func _notify_player(msg: String) -> void:
	if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback(msg)
	print("MetalCrusher: %s" % msg)
