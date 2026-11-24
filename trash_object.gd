
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
	collected.emit(item_id, collection_value)
	print("Collected: %s (+%.1f SC)" % [item_id, collection_value])
	queue_free()
