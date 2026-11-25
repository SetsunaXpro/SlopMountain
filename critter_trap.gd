class_name CritterTrap
extends Node3D

@export var trap_type: String = "hostile" # "hostile" or "peaceful"
@export var attract_radius: float = 24.0
@export var stun_radius: float = 2.8
@export var stun_duration: float = 6.0
@export var recharge_seconds: float = 10.0

var _cooldown_timer: float = 0.0
var _lure_mat: StandardMaterial3D = null
var _status_label: Label3D = null


func _ready() -> void:
	add_to_group("critter_traps")
	if trap_type == "hostile":
		add_to_group("hostile_traps")
	else:
		add_to_group("peaceful_traps")
	_build_visuals()


func _build_visuals() -> void:
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.65
	cyl.height = 0.14
	base.mesh = cyl
	base.position = Vector3(0, 0.07, 0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.22, 0.24, 0.28)
	base_mat.metallic = 0.7
	base.material_override = base_mat
	add_child(base)

	var lure := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	lure.mesh = sph
	lure.position = Vector3(0, 0.42, 0)
	_lure_mat = StandardMaterial3D.new()
	var col := Color(1.0, 0.25, 0.25) if trap_type == "hostile" else Color(0.25, 0.95, 0.55)
	_lure_mat.albedo_color = col
	_lure_mat.emission_enabled = true
	_lure_mat.emission = col
	_lure_mat.emission_energy_multiplier = 2.2
	lure.material_override = _lure_mat
	add_child(lure)

	_status_label = Label3D.new()
	_status_label.position = Vector3(0, 1.05, 0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 28
	_status_label.outline_size = 6
	add_child(_status_label)
	_update_label()


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		if _cooldown_timer == 0.0:
			_update_label()
			if _lure_mat:
				_lure_mat.emission_energy_multiplier = 2.2
		return

	var target_group := "evil_critters" if trap_type == "hostile" else "peaceful_critters"
	for mob in get_tree().get_nodes_in_group(target_group):
		if not (mob is Node3D) or not is_instance_valid(mob):
			continue
		if global_position.distance_to(mob.global_position) <= stun_radius:
			if mob.has_method("apply_stun"):
				mob.apply_stun(stun_duration)
			_cooldown_timer = recharge_seconds
			if _lure_mat:
				_lure_mat.emission_energy_multiplier = 0.2
			_update_label()
			break


func _update_label() -> void:
	if not is_instance_valid(_status_label):
		return
	if _cooldown_timer > 0.0:
		_status_label.text = "⚡ TRIGGERED (Recharging...)"
		_status_label.modulate = Color(1.0, 0.85, 0.3)
	elif trap_type == "hostile":
		_status_label.text = "🪤 HOSTILE TRAP (Active)"
		_status_label.modulate = Color(1.0, 0.4, 0.35)
	else:
		_status_label.text = "🪤 PEACEFUL TRAP (Active)"
		_status_label.modulate = Color(0.4, 1.0, 0.65)
