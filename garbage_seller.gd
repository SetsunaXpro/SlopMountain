# garbage_seller.gd
# Machine: Garbage Seller
# Sells all trash from the player's inventory in exchange for SlopCredit.

class_name GarbageSeller
extends Area3D

signal garbage_sold(total_items: int, total_sc: float)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@export_group("Sell Prices")
## Base price per generic trash item
@export var base_price: float = 1.0
## Price multiplier for metal items
@export var metal_multiplier: float = 1.5
## Price multiplier for plastic items
@export var plastic_multiplier: float = 1.2
## Price multiplier for organic items
@export var organic_multiplier: float = 0.8
## Price multiplier for glass/bottle items
@export var glass_multiplier: float = 1.3
## Price for compacted metal cubes
@export var compacted_metal_price: float = 8.0
## Price for compacted plastic cubes
@export var compacted_plastic_price: float = 6.0
## Price for compost bags
@export var compost_price: float = 3.0

@export_group("Interaction")
@export var interact_distance: float = 3.5
@export var input_interact: String = "interact"

# ---------------------------------------------------------------------------
# Internal State
# ---------------------------------------------------------------------------
var _player_ref: Node = null
var _player_nearby: bool = false
var _prompt_label: Label3D = null
var _sell_cooldown: float = 0.0


func _ready() -> void:
	add_to_group("machines")
	add_to_group("garbage_seller")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = get_node_or_null("PromptLabel3D") as Label3D
	if not _prompt_label:
		_prompt_label = Label3D.new()
		_prompt_label.name = "PromptLabel3D"
		_prompt_label.font_size = 36
		_prompt_label.modulate = Color(1.0, 0.85, 0.2, 1.0)
		_prompt_label.outline_render_priority = 1
		_prompt_label.position = Vector3(0, 2.0, 0)
		_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_prompt_label.no_depth_test = true
		_prompt_label.visible = false
		add_child(_prompt_label)


func _process(delta: float) -> void:
	_check_player_proximity()
	_update_prompt()

	if _sell_cooldown > 0.0:
		_sell_cooldown = maxf(0.0, _sell_cooldown - delta)

	if _player_nearby and _sell_cooldown <= 0.0:
		if InputMap.has_action(input_interact) and Input.is_action_just_pressed(input_interact):
			_sell_all_garbage()


func _check_player_proximity() -> void:
	if not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
		if not _player_ref:
			_player_nearby = false
			return

	var dist := global_position.distance_to(_player_ref.global_position)
	_player_nearby = (dist <= interact_distance)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_nearby or not is_instance_valid(_player_ref) or _sell_cooldown > 0.0:
		return

	var pressed := false
	if InputMap.has_action(input_interact) and event.is_action_pressed(input_interact):
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.physical_keycode == KEY_E:
			pressed = true

	if pressed:
		_sell_all_garbage()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "ProtoController":
		_player_ref = body
		_player_nearby = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_ref:
		_check_player_proximity()


# ---------------------------------------------------------------------------
# Sell Pricing & Logic
# ---------------------------------------------------------------------------

func _get_item_price(id_str: String) -> float:
	id_str = id_str.to_lower()

	if id_str.contains("compacted_metal"):
		return compacted_metal_price
	if id_str.contains("compacted_plastic"):
		return compacted_plastic_price
	if id_str.contains("compost"):
		return compost_price

	if id_str.contains("can") or id_str.contains("metal") or id_str.contains("kaleng"):
		return base_price * metal_multiplier
	if id_str.contains("plastic") or id_str.contains("plastik"):
		return base_price * plastic_multiplier
	if id_str.contains("bottle") or id_str.contains("glass") or id_str.contains("botol"):
		return base_price * glass_multiplier
	if _is_organic(id_str):
		return base_price * organic_multiplier

	return base_price


func _is_organic(id_str: String) -> bool:
	var keywords := [
		"kulit_pisang", "pisang", "banana", "organic", "organik",
		"food", "makanan", "leaf", "daun", "fruit", "buah", "bananapeel"
	]
	for kw in keywords:
		if id_str.contains(kw):
			return true
	return false


func _sell_all_garbage() -> void:
	if not is_instance_valid(_player_ref):
		return

	if not "trash_inventory_items" in _player_ref:
		_notify_player("No inventory found on player!")
		return

	var items: Array = _player_ref.trash_inventory_items
	if items.is_empty():
		_notify_player("💼 Trash bag is empty! (Hold L-Click on trash to collect first)")
		return

	var total_sc: float = 0.0
	var total_items: int = items.size()

	for item in items:
		var id: String = str(item.get("id", "trash"))
		total_sc += _get_item_price(id)

	var mult: float = 1.0
	var game_hud = get_tree().get_first_node_in_group("game_hud")
	if game_hud and "current_mult" in game_hud:
		mult = game_hud.current_mult
	total_sc *= mult

	_player_ref.slop_credit += total_sc
	if "daily_sc_earned" in _player_ref:
		_player_ref.daily_sc_earned += total_sc

	_player_ref.trash_bag.clear()
	_player_ref.trash_inventory_items.clear()
	_player_ref.total_items_in_bag = 0

	if _player_ref.has_signal("slop_credit_changed"):
		_player_ref.slop_credit_changed.emit(_player_ref.slop_credit, total_sc)

	if _player_ref.has_method("_update_hud"):
		_player_ref._update_hud()

	var msg := "💰 Sold %d item(s) for +%.1f SC!" % [total_items, total_sc]
	if mult > 1.0:
		msg += " (×%.1f streak bonus)" % mult
	_notify_player(msg)
	garbage_sold.emit(total_items, total_sc)

	_sell_cooldown = 0.5


func _update_prompt() -> void:
	if not _prompt_label:
		return

	if _player_nearby:
		_prompt_label.visible = true
		var item_count: int = 0
		var est_sc: float = 0.0

		if is_instance_valid(_player_ref) and "trash_inventory_items" in _player_ref:
			var items: Array = _player_ref.trash_inventory_items
			item_count = items.size()
			for item in items:
				var id: String = str(item.get("id", "trash"))
				est_sc += _get_item_price(id)

		if item_count > 0:
			_prompt_label.text = "[E] Sell %d Trash (+%.1f SC)" % [item_count, est_sc]
		else:
			_prompt_label.text = "[E] Seller (Bag Empty)"
	else:
		_prompt_label.visible = false


func _notify_player(msg: String) -> void:
	if is_instance_valid(_player_ref) and _player_ref.has_method("_show_feedback"):
		_player_ref._show_feedback(msg)
	print("GarbageSeller: %s" % msg)
