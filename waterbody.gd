# waterbody.gd
# Attach this script to the Waterbody MeshInstance3D node.
#
# Features:
#  - Multi-octave sine wave simulation for realistic water surface height
#  - Buoyancy + drag + uprighting for any RigidBody3D in the "floatable" group
#  - Wave displacement forces (objects drift with the current)
#  - Player (CharacterBody3D) water physics: slow movement, buoyancy, swimming

extends MeshInstance3D

# ---------------------------------------------------------------------------
# Wave Settings
# ---------------------------------------------------------------------------
@export_group("Waves")
## Base height of the water surface (world Y).
## Auto-computed from the mesh AABB but can be overridden.
@export var water_base_y: float = 0.0
## Amplitude of the primary wave (how high/low it peaks).
@export var wave_amplitude: float = 0.4
## Speed of the primary wave.
@export var wave_speed: float = 0.8
## Horizontal scale of the primary wave (larger = wider waves).
@export var wave_scale: float = 0.05
## A second smaller wave layered on top for complexity.
@export var wave2_amplitude: float = 0.15
@export var wave2_speed: float = 1.4
@export var wave2_scale: float = 0.09
## Direction the waves travel (normalized XZ).
@export var wave_direction: Vector2 = Vector2(1.0, 0.6)

# ---------------------------------------------------------------------------
# Floatable RigidBody3D Settings
# ---------------------------------------------------------------------------
@export_group("Buoyancy - Objects")
## Upward force per unit of submersion depth.
@export var buoyancy_force: float = 30.0
## Linear drag while submerged.
@export var water_linear_drag: float = 3.0
## Angular drag while submerged.
@export var water_angular_drag: float = 2.0
## Torque trying to keep objects upright (0 = free tumble).
@export var uprighting_torque: float = 3.0
## Horizontal push applied by the wave current.
@export var wave_drift_force: float = 1.5

# ---------------------------------------------------------------------------
# Player (CharacterBody3D) Settings
# ---------------------------------------------------------------------------
@export_group("Buoyancy - Player")
## Name of the player node's group so we can find it.
@export var player_group: String = "player"
## Fraction of normal move speed when swimming (0–1).
@export var swim_speed_multiplier: float = 0.45
## Upward velocity added per frame to keep player afloat.
@export var player_buoyancy: float = 6.0
## How deep the player must be before swimming kicks in.
@export var player_submersion_threshold: float = 0.6

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _water_base_y: float = 0.0        # resolved after _ready
var _time: float = 0.0
var _body_saved: Dictionary = {}      # RigidBody3D → { linear_damp, angular_damp }
var _wave_dir: Vector3 = Vector3.ZERO

func _ready() -> void:
	call_deferred("_compute_base_y")

func _compute_base_y() -> void:
	var local_aabb: AABB = get_aabb()
	var top_y := -INF
	for xi in [local_aabb.position.x, local_aabb.end.x]:
		for yi in [local_aabb.position.y, local_aabb.end.y]:
			for zi in [local_aabb.position.z, local_aabb.end.z]:
				var world_pt: Vector3 = global_transform * Vector3(xi, yi, zi)
				if world_pt.y > top_y:
					top_y = world_pt.y
	_water_base_y = top_y if water_base_y == 0.0 else water_base_y
	_wave_dir = Vector3(wave_direction.normalized().x, 0.0, wave_direction.normalized().y)
	print("Waterbody: base surface Y = %.3f" % _water_base_y)

# Returns the wave-displaced surface Y at a given world XZ position.
func get_surface_y(world_pos: Vector3) -> float:
	var d1 := world_pos.x * wave_scale + world_pos.z * wave_scale * 0.7
	var d2 := world_pos.x * wave2_scale * 1.1 + world_pos.z * wave2_scale
	var h := wave_amplitude * sin(d1 + _time * wave_speed)
	h    += wave2_amplitude * sin(d2 - _time * wave2_speed + 1.3)
	return _water_base_y + h

func _physics_process(delta: float) -> void:
	_time += delta

	_process_floatables(delta)
	_process_player(delta)

# ---------------------------------------------------------------------------
# Floatable RigidBody3D objects
# ---------------------------------------------------------------------------
func _process_floatables(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("floatable"):
		if not node is RigidBody3D:
			continue
		var body := node as RigidBody3D
		if body.freeze:
			continue

		var surface_y := get_surface_y(body.global_position)
		var depth := surface_y - body.global_position.y

		if depth > 0.0:
			# Buoyancy
			body.apply_central_force(Vector3.UP * buoyancy_force * depth)

			# Wave drift — push gently in wave direction
			body.apply_central_force(_wave_dir * wave_drift_force * depth)

			# Uprighting torque
			if uprighting_torque > 0.0:
				var up_world := body.global_transform.basis.y
				var correction := up_world.cross(Vector3.UP)
				if correction.length_squared() > 0.001:
					body.apply_torque(correction * uprighting_torque)

			# Water drag
			body.linear_damp  = water_linear_drag
			body.angular_damp = water_angular_drag
			body.sleeping = false

			if not _body_saved.has(body):
				_body_saved[body] = {
					"linear_damp":  body.linear_damp,
					"angular_damp": body.angular_damp
				}
		else:
			if _body_saved.has(body):
				var s = _body_saved[body]
				body.linear_damp  = s["linear_damp"]
				body.angular_damp = s["angular_damp"]
				_body_saved.erase(body)

# ---------------------------------------------------------------------------
# Player (CharacterBody3D)
# ---------------------------------------------------------------------------
func _process_player(delta: float) -> void:
	var players := get_tree().get_nodes_in_group(player_group)
	for node in players:
		if not node is CharacterBody3D:
			continue
		var player := node as CharacterBody3D

		var surface_y    := get_surface_y(player.global_position)
		var submersion   := surface_y - player.global_position.y

		if submersion > player_submersion_threshold:
			# --- Slow horizontal movement ---
			player.velocity.x *= 1.0 - (delta * 6.0 * swim_speed_multiplier)
			player.velocity.z *= 1.0 - (delta * 6.0 * swim_speed_multiplier)

			# --- Buoyancy: float the player upward toward surface ---
			# Clamp so we don't catapult them above water
			var buoy_vel := player_buoyancy * submersion * delta
			player.velocity.y += buoy_vel
			player.velocity.y  = minf(player.velocity.y, 2.5)  # cap rise speed

			# --- Gentle wave bob ---
			var bob := wave_amplitude * 0.3 * sin(_time * wave_speed)
			player.velocity.y += bob * delta
