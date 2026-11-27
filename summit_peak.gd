# summit_peak.gd
# Placeable Area3D Summit Peak landmark for the "expedition" random event.
# Place summit_peak.tscn (or an Area3D with this script) anywhere on your map's peak.

class_name SummitPeak
extends Area3D

signal flag_planted

@export var trigger_radius: float = 4.5

var is_expedition_active: bool = false
var is_flag_planted: bool = false

var _visual_root: Node3D = null
var _prompt_label: Label3D = null
var _beacon_mesh: MeshInstance3D = null
var _flag_mesh: CSGBox3D = null
var _ghost_flag_mesh: CSGBox3D = null
var _player_nearby: bool = false
var _player_ref: Node = null


func _ready() -> void:
	add_to_group("summit_peak")
	_ensure_collision_shape()
	_build_flagpole_visuals()

	if not body_entered.is_connected(_on_trigger_body_entered):
		body_entered.connect(_on_trigger_body_entered)
	if not body_exited.is_connected(_on_trigger_body_exited):
		body_exited.connect(_on_trigger_body_exited)

	# Stay hidden/inactive until the Expedition event activates it
	deactivate_expedition()


func _ensure_collision_shape() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var col := CollisionShape3D.new()
	col.name = "SummitTriggerShape"
	col.position = Vector3(0, 1.5, 0)
	var sphere := SphereShape3D.new()
	sphere.radius = trigger_radius
	col.shape = sphere
	add_child(col)


func _build_flagpole_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "FlagpoleVisuals"
	add_child(_visual_root)

	# Flagpole Base & Pole (ground level at Y = 0)
	var pole_base := CSGCylinder3D.new()
	pole_base.radius = 0.45
	pole_base.height = 0.35
	pole_base.position = Vector3(0, 0.175, 0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.28, 0.26, 0.24)
	base_mat.roughness = 0.85
	pole_base.material = base_mat
	_visual_root.add_child(pole_base)

	var pole := CSGCylinder3D.new()
	pole.radius = 0.08
	pole.height = 4.0
	pole.position = Vector3(0, 2.0, 0)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.85, 0.75, 0.3)
	pole_mat.metallic = 0.8
	pole.material = pole_mat
	_visual_root.add_child(pole)

	# Ghost flag preview (visible before planting so player sees where to plant)
	_ghost_flag_mesh = CSGBox3D.new()
	_ghost_flag_mesh.size = Vector3(1.4, 0.8, 0.05)
	_ghost_flag_mesh.position = Vector3(0.7, 3.5, 0)
	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(1.0, 0.88, 0.25, 0.45)
	_ghost_flag_mesh.material = ghost_mat
	_visual_root.add_child(_ghost_flag_mesh)

	# Flag (initially hidden, unfurls on plant)
	_flag_mesh = CSGBox3D.new()
	_flag_mesh.size = Vector3(1.4, 0.8, 0.05)
	_flag_mesh.position = Vector3(0.7, 3.5, 0)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.15, 0.55, 0.95)
	flag_mat.roughness = 0.4
	_flag_mesh.material = flag_mat
	_flag_mesh.visible = false
	_visual_root.add_child(_flag_mesh)

	# Sky Beacon Light (tall unshaded glowing pillar so player can spot the peak from afar)
	_beacon_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.8
	cyl.height = 140.0
	_beacon_mesh.mesh = cyl
	_beacon_mesh.position = Vector3(0, 72.0, 0)

	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.50)
	_beacon_mesh.material_override = beacon_mat
	_visual_root.add_child(_beacon_mesh)

	# Prompt Label
	_prompt_label = Label3D.new()
	_prompt_label.position = Vector3(0, 2.7, 0)
	_prompt_label.font_size = 34
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.text = "🚩 SUMMIT PEAK\nClimb to plant flag!"
	_prompt_label.modulate = Color(1.0, 0.9, 0.3)
	_visual_root.add_child(_prompt_label)


func activate_expedition() -> void:
	is_expedition_active = true
	is_flag_planted = false
	_player_nearby = false
	monitoring = true
	if is_instance_valid(_visual_root):
		_visual_root.visible = true
	if is_instance_valid(_ghost_flag_mesh):
		_ghost_flag_mesh.visible = true
	if is_instance_valid(_flag_mesh):
		_flag_mesh.visible = false
		_flag_mesh.scale = Vector3.ONE
	if is_instance_valid(_beacon_mesh) and _beacon_mesh.material_override:
		var mat := _beacon_mesh.material_override as StandardMaterial3D
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.50)
	if is_instance_valid(_prompt_label):
		_prompt_label.text = "🚩 SUMMIT PEAK\nClimb to plant flag!"
		_prompt_label.modulate = Color(1.0, 0.9, 0.3)
		_prompt_label.visible = true

	# Check if player is already standing inside the Area3D when event starts
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_player_ref = body
			_player_nearby = true
			if is_instance_valid(_prompt_label):
				_prompt_label.text = "🚩 SUMMIT PEAK\n[E] Plant Ranger Flag!"
			break


func deactivate_expedition() -> void:
	is_expedition_active = false
	is_flag_planted = false
	_player_nearby = false
	monitoring = false
	if is_instance_valid(_visual_root):
		_visual_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_expedition_active or not _player_nearby or is_flag_planted:
		return
	if is_instance_valid(_player_ref) and _player_ref.has_method("is_any_menu_open") and _player_ref.is_any_menu_open():
		return
	var pressed := false
	if InputMap.has_action("interact") and event.is_action_pressed("interact"):
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_E or event.physical_keycode == KEY_E):
		pressed = true
	if pressed:
		get_viewport().set_input_as_handled()
		plant_flag()


func _on_trigger_body_entered(body: Node) -> void:
	if not is_expedition_active:
		return
	if body.is_in_group("player"):
		_player_ref = body
		_player_nearby = true
		if not is_flag_planted and is_instance_valid(_prompt_label):
			_prompt_label.text = "🚩 SUMMIT PEAK\n[E] Plant Ranger Flag!"
			_prompt_label.visible = true


func _on_trigger_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		if is_expedition_active and not is_flag_planted and is_instance_valid(_prompt_label):
			_prompt_label.text = "🚩 SUMMIT PEAK\nClimb to plant flag!"


func plant_flag() -> void:
	if not is_expedition_active or is_flag_planted:
		return
	if is_instance_valid(_player_ref) and ("has_summit_flag" in _player_ref) and not bool(_player_ref.has_summit_flag):
		if _player_ref.has_method("_show_feedback"):
			_player_ref._show_feedback("🚩 You need the Ranger Flag from your inventory!")
		return
	is_flag_planted = true
	if is_instance_valid(_player_ref) and _player_ref.has_method("consume_summit_flag"):
		_player_ref.consume_summit_flag()
	if is_instance_valid(_ghost_flag_mesh):
		_ghost_flag_mesh.visible = false
	if is_instance_valid(_flag_mesh):
		_flag_mesh.visible = true
		var tw := create_tween()
		_flag_mesh.scale = Vector3(0.01, 0.01, 0.01)
		tw.tween_property(_flag_mesh, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if is_instance_valid(_prompt_label):
		_prompt_label.text = "🚩 CONQUERED!\nRanger Flag Planted!"
		_prompt_label.modulate = Color(0.3, 1.0, 0.5)

	if _beacon_mesh and _beacon_mesh.material_override:
		var mat := _beacon_mesh.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.2, 1.0, 0.4, 0.6)

	if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback("🚩 SUMMIT CONQUERED! Ranger Flag Planted on Peak!")

	flag_planted.emit()
