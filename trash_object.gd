
extends RigidBody3D
class_name TrashObject

signal collected(item_id: String, value: float)

@export var item_id: String = "unknown"
@export var collection_value: float = 1.0
## Weight of the object. Affects hold-to-pickup duration and throw cooldown.
@export var weight: float = 1.0

func _ready() -> void:
	# Adds this object to the group that waterbody.gd watches.
	add_to_group("floatable")
	# Adds this object to the trash group for collection detection.
	add_to_group("trash")

func collect() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_rpc_collect.rpc()
	else:
		_do_collect()


@rpc("any_peer", "call_local", "reliable")
func _rpc_collect() -> void:
	_do_collect()


func _do_collect() -> void:
	if is_queued_for_deletion():
		return
	collected.emit(item_id, collection_value)
	print("Collected: %s (+%.1f SC)" % [item_id, collection_value])
	queue_free()
