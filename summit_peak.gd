# summit_peak.gd
# Spawns a climbable summit peak landmark with a flagpole at the top.
# Used for the "expedition" random event.

class_name SummitPeak
extends Node3D

signal flag_planted

var is_flag_planted: bool = false
var _prompt_label: Label3D = null
var _beacon_mesh: MeshInstance3D = null
var _flag_mesh: CSGBox3D = null
var _player_nearby: bool = false
var _player_ref: Node = null

func _ready() -> void:
	add_to_group("summit_peak")
	_build_peak_geometry()


func _build_peak_geometry() -> void:
	# 1. Base Mountain Slabs (Tiered rock stairs leading to the peak)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.32, 0.30, 0.28)
	rock_mat.roughness = 0.9

	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.85, 0.88, 0.92)
	snow_mat.roughness = 0.6

	# Tier 1 Base
	var t1 := CSGBox3D.new()
	t1.size = Vector3(14.0, 3.0, 14.0)
	t1.position = Vector3(0, 1.5, 0)
	t1.use_collision = true
	t1.material = rock_mat
	add_child(t1)

	# Tier 2 Mid
	var t2 := CSGBox3D.new()
	t2.size = Vector3(10.0, 3.5, 10.0)
	t2.position = Vector3(0, 4.75, 0)
	t2.use_collision = true
	t2.material = rock_mat
	add_child(t2)

	# Tier 3 High
	var t3 := CSGBox3D.new()
	t3.size = Vector3(6.5, 4.0, 6.5)
	t3.position = Vector3(0, 8.5, 0)
	t3.use_collision = true
	t3.material = rock_mat
	add_child(t3)

	# Tier 4 Peak Platform
	var t4 := CSGBox3D.new()
	t4.size = Vector3(4.0, 3.0, 4.0)
	t4.position = Vector3(0, 12.0, 0)
	t4.use_collision = true
	t4.material = snow_mat
	add_child(t4)

	# Rock steps winding up the mountain so the player can jump/walk up
	var step_coords := [
		Vector3(0, 0.5, 7.5),
		Vector3(2.5, 1.8, 6.5),
		Vector3(5.0, 3.2, 4.0),
		Vector3(5.5, 4.5, 0.5),
		Vector3(4.5, 5.8, -3.5),
		Vector3(1.5, 7.2, -4.5),
		Vector3(-2.5, 8.5, -4.0),
		Vector3(-3.5, 10.0, -1.0),
		Vector3(-2.0, 11.5, 1.5),
		Vector3(0, 13.0, 1.0)
	]
	for i in range(step_coords.size()):
		var step := CSGBox3D.new()
		step.size = Vector3(2.2, 0.6, 2.2)
		step.position = step_coords[i]
		step.use_collision = true
		step.material = rock_mat
		add_child(step)

	# 2. Flagpole Base & Pole (at Y = 13.5)
	var pole_base := CSGCylinder3D.new()
	pole_base.radius = 0.5
	pole_base.height = 0.5
	pole_base.position = Vector3(0, 13.75, 0)
	pole_base.use_collision = true
	add_child(pole_base)

	var pole := CSGCylinder3D.new()
	pole.radius = 0.08
	pole.height = 4.0
	pole.position = Vector3(0, 16.0, 0)
	pole.use_collision = true
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.85, 0.75, 0.3)
	pole_mat.metallic = 0.8
	pole.material = pole_mat
	add_child(pole)

	# Flag (initially hidden, unfurls on plant)
	_flag_mesh = CSGBox3D.new()
	_flag_mesh.size = Vector3(1.4, 0.8, 0.05)
	_flag_mesh.position = Vector3(0.7, 17.5, 0)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.15, 0.55, 0.95)
	flag_mat.roughness = 0.4
	_flag_mesh.material = flag_mat
	_flag_mesh.visible = false
	add_child(_flag_mesh)

	# 3. Sky Beacon Light (tall unshaded glowing pillar into clouds so player can see it from far away)
	_beacon_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.25
	cyl.height = 60.0
	_beacon_mesh.mesh = cyl
	_beacon_mesh.position = Vector3(0, 43.5, 0)

	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.45)
	_beacon_mesh.material_override = beacon_mat
	add_child(_beacon_mesh)

	# 4. Trigger Area at peak
	var trigger := Area3D.new()
	trigger.position = Vector3(0, 14.5, 0)
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.5
	col.shape = sphere
	trigger.add_child(col)
	trigger.body_entered.connect(_on_trigger_body_entered)
	trigger.body_exited.connect(_on_trigger_body_exited)
	add_child(trigger)

	# Prompt Label
	_prompt_label = Label3D.new()
	_prompt_label.position = Vector3(0, 15.5, 0)
	_prompt_label.font_size = 32
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.text = "🚩 SUMMIT PEAK\n[E] Plant Ranger Flag!"
	_prompt_label.modulate = Color(1.0, 0.9, 0.3)
	_prompt_label.visible = false
	add_child(_prompt_label)


func _process(_delta: float) -> void:
	if _player_nearby and not is_flag_planted:
		if Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_E):
			plant_flag()


func _on_trigger_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_ref = body
		_player_nearby = true
		if not is_flag_planted:
			_prompt_label.visible = true


func _on_trigger_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		_prompt_label.visible = false


func plant_flag() -> void:
	if is_flag_planted:
		return
	is_flag_planted = true
	_flag_mesh.visible = true

	# Pop tween animation for the flag
	var tw := create_tween()
	_flag_mesh.scale = Vector3(0.01, 0.01, 0.01)
	tw.tween_property(_flag_mesh, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_prompt_label.text = "🚩 CONQUERED!\nRanger Flag Planted!"
	_prompt_label.modulate = Color(0.3, 1.0, 0.5)

	# Change beacon to victory green
	if _beacon_mesh and _beacon_mesh.material_override:
		var mat := _beacon_mesh.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.2, 1.0, 0.4, 0.6)

	if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback("🚩 SUMMIT CONQUERED! Ranger Flag Planted on Peak!")

	flag_planted.emit()
