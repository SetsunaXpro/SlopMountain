extends Node3D

@export_group("Trash Settings")
@export var TrashScenes: Array[PackedScene] = []
@export var TrashCount: int = 70

@export_group("Pile Shape")
@export var PileRadius: float = 0.5
@export var PileHeight: float = 10.0
@export var SpawnHeight: float = 10.0

@export_group("Randomization")
@export var MinScale: float = 0.0
@export var MaxScale: float = 0.0

var _rng := RandomNumberGenerator.new()
var _pile_seed: int = -1
var _generated: bool = false


func _ready() -> void:
	# In multiplayer, only the host/server picks the seed and generates immediately;
	# clients receive the seed from the host so both have identical trash piles.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_rng.randomize()
	_pile_seed = _rng.randi()
	print("Trash generator started! (seed=%d)" % _pile_seed)
	GeneratePile(_pile_seed)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if not NetworkManager.player_connected.is_connected(_on_peer_connected):
			NetworkManager.player_connected.connect(_on_peer_connected)


func _on_peer_connected(peer_id: int) -> void:
	if _pile_seed >= 0:
		_rpc_generate_with_seed.rpc_id(peer_id, _pile_seed)


@rpc("authority", "call_remote", "reliable")
func _rpc_generate_with_seed(seed_value: int) -> void:
	if _generated:
		return
	GeneratePile(seed_value)


func GeneratePile(seed_value: int = -1) -> void:
	if _generated:
		return
	_generated = true
	if seed_value >= 0:
		_rng.seed = seed_value

	print("GeneratePile() called!")

	if TrashScenes == null or TrashScenes.is_empty():
		push_warning("No trash scenes assigned in Inspector!")
		return

	print("Trash scenes assigned: ", TrashScenes.size())

	for i in range(TrashCount):
		var random_index: int = _rng.randi_range(0, TrashScenes.size() - 1)
		var selected_scene: PackedScene = TrashScenes[random_index]

		if selected_scene == null:
			push_warning("Trash scene at index %d is NULL!" % random_index)
			continue

		var trash := selected_scene.instantiate() as Node3D
		if trash == null:
			push_warning("Trash scene root must inherit Node3D!")
			continue

		trash.name = "Trash_%d" % i
		trash.top_level = true
		add_child(trash)

		var angle: float = _rng.randf_range(0.0, TAU)
		var distance: float = sqrt(_rng.randf()) * PileRadius

		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance

		var height_factor: float = 1.0 - (distance / maxf(PileRadius, 0.001))
		var y: float = _rng.randf_range(0.3, SpawnHeight) + height_factor * PileHeight

		trash.global_position = to_global(Vector3(x, y, z))
		trash.global_rotation = Vector3(
			_rng.randf_range(-PI, PI),
			_rng.randf_range(-PI, PI),
			_rng.randf_range(-PI, PI)
		)

		var s: float = _rng.randf_range(MinScale, MaxScale)
		if s > 0.0:
			trash.scale = Vector3.ONE * s

	print("Successfully spawned %d trash objects!" % TrashCount)
