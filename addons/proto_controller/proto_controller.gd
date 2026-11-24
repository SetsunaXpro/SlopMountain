# ProtoController v1.0 by Brackeys (Modified for Gimrsia)
# CC0 License
# Intended for rapid prototyping of first-person games.

extends CharacterBody3D

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = false
## Can we press to enter freefly mode (noclip)?
@export var can_freefly : bool = false

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Normal speed.
@export var base_speed : float = 7.0
## Speed of jump.
@export var jump_velocity : float = 4.5
## How fast do we run?
@export var sprint_speed : float = 10.0
## How fast do we freefly?
@export var freefly_speed : float = 25.0

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "move_left"
## Name of Input Action to move Right.
@export var input_right : String = "move_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "move_front"
## Name of Input Action to move Backward.
@export var input_back : String = "move_back"
## Name of Input Action to Jump.
@export var input_jump : String = "ui_accept"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"
## Name of Input Action to toggle freefly mode.
@export var input_freefly : String = "freefly"

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider

@export_group("Pickup Settings")
@export var pickup_distance: float = 5.0
@export var throw_force: float = 15.0

var held_object: RigidBody3D = null

@onready var pickup_ray: RayCast3D = $Head/PickupRay
@onready var hold_position: Marker3D = $Head/HoldPosition

# ===========================================================================
# Trash Bag / Inventory & SlopCredit (SC)
# ===========================================================================
@export_group("Trash Bag & Inventory")
## Total SlopCredit (SC) score/currency collected
@export var slop_credit: float = 0.0
## Max items the trash bag can hold (0 = unlimited)
@export var max_bag_capacity: int = 0
## Whether to generate the built-in HUD
@export var show_hud: bool = true

## Inventory counts: { item_id (String): count (int) }
var trash_bag: Dictionary = {}
## Detailed list of items collected: Array of { "id": String, "value": float, "weight": float, "scene_path": String }
var trash_inventory_items: Array[Dictionary] = []
var total_items_in_bag: int = 0

## Daily stats tracked for Day/Night summary
var daily_sc_earned: float = 0.0
var daily_items_bagged: int = 0
var day_start_slop_credit: float = 0.0

# ===========================================================================
# Perk / Mod variables  (set by BuyMenu when player purchases upgrades)
# ===========================================================================
## Extra score multiplier bonus added per item correctly sorted (HI-VIS VEST)
var extra_mult_per_item: float = 0.0
## Weight multiplier for metal/can items toward quota (CAN CRUSHER)
var metal_weight_multiplier: float = 1.0
## Whether Piggy Jar end-of-day interest is active
var piggy_jar_active: bool = false
## Bonus pickup range added on top of base (MAGNET GLOVE)
var pickup_range_bonus: float = 0.0
## Tracks which perks have been purchased (prevents duplicate buys)
var owned_perks: Array[String] = []
## Tracks which machines have been purchased / deployed
var owned_machines: Array[String] = []

# Buy Menu reference (Items / Mods)
var buy_menu: BuyMenu = null
# Machine Buy Menu reference (Machinery)
var machine_menu: CanvasLayer = null
# Quota Menu reference
var quota_menu_instance: CanvasLayer = null

signal slop_credit_changed(total_sc: float, added_sc: float)
signal item_bagged(item_id: String, value: float, total_sc: float)

# ===========================================================================
# Trash Grenade / Haul Settings
# ===========================================================================
@export_group("Trash Grenade & Haul")
## Action name or fallback key (G) to equip trash as a grenade
@export var input_equip_trash: String = "equip_trash"
## Velocity when hauled like a grenade
@export var grenade_throw_force: float = 22.0
## Upward arc bias for grenade trajectory (higher = more arced lob)
@export var grenade_arc_pitch: float = 0.25
## Angular spin speed on grenade release
@export var grenade_spin_speed: float = 14.0
## Offset relative to head for the ready position (bottom-right grenade hand pose)
@export var ready_offset: Vector3 = Vector3(0.35, -0.28, -0.65)
## If true, throwing an equipped item deducts its value from SlopCredit
@export var throw_costs_credit: bool = true

var is_trash_grenade_equipped: bool = false
var equipped_trash_data: Dictionary = {}

const TRASH_SCENE_FALLBACKS: Dictionary = {
	"plastic": "res://plastic.tscn",
	"can": "res://Trash_can.tscn",
	"bottle": "res://bottle.tscn",
	"trash": "res://trash_object.tscn"
}

# ===========================================================================
# Interaction & Weight-Based Cooldowns (Minecraft-style)
# ===========================================================================
@export_group("Interaction & Cooldowns")
## Base time in seconds required to pick up trash
@export var base_pickup_time: float = 0.3
## Additional pickup time in seconds per unit of object weight
@export var pickup_time_per_weight: float = 0.4
## Base cooldown in seconds after throwing
@export var base_throw_cooldown: float = 0.35
## Additional throw cooldown in seconds per unit of object weight
@export var throw_cooldown_per_weight: float = 0.35

# Hold-to-pickup state
var _current_pickup_target: Object = null
var _pickup_hold_timer: float = 0.0

# End-day hold state (Hold [N] to end day early)
var _end_day_hold_timer: float = 0.0
const END_DAY_HOLD_DURATION: float = 1.0

# Throw cooldown state
var throw_cooldown_timer: float = 0.0
var throw_cooldown_duration: float = 0.5

# HUD References
var game_hud: GameHUD = null
var _hud_layer: CanvasLayer = null
var _hud_sc_label: Label = null
var _hud_bag_label: Label = null
var _hud_equipped_label: Label = null
var _hud_prompt_label: Label = null
var _hud_toast_label: Label = null
var _hud_toast_tween: Tween = null
var _action_bar: ProgressBar = null
var _action_bar_style_fill: StyleBoxFlat = null


func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	pickup_ray.target_position = Vector3(0, 0, -pickup_distance)
	add_to_group("player")  # Waterbody script uses this group for water physics
	_ensure_day_night_cycle()
	_setup_hud()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse controls
	if event is InputEventMouseButton and event.pressed:
		# Left click: Capture mouse or handle non-hold interactions
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not mouse_captured:
				var dnc = get_tree().get_first_node_in_group("day_night_cycle")
				if dnc and dnc.is_night and dnc._night_modal and dnc._night_modal.visible:
					return
				capture_mouse()
			else:
				# If holding an equipped grenade, holster it back to bag
				if is_trash_grenade_equipped:
					holster_equipped_grenade()
				# If holding a normal physics object, drop it
				elif held_object:
					drop_object()
				else:
					# If aiming at a non-trash RigidBody3D, pick it up directly
					pickup_ray.force_raycast_update()
					if pickup_ray.is_colliding():
						var object = pickup_ray.get_collider()
						if object is RigidBody3D and not is_trash_object(object):
							held_object = object
							held_object.freeze = true
							held_object.global_position = hold_position.global_position

		# Right click: Haul grenade or throw held object
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_captured:
				throw_object()

	# Key controls
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			toggle_equip_trash_grenade()
		elif event.keycode == KEY_B:
			toggle_buy_menu()
		elif event.keycode == KEY_M:
			toggle_machine_menu()
		elif event.keycode == KEY_Q:
			toggle_quota_menu()
		elif event.keycode == KEY_N:
			var dnc = get_tree().get_first_node_in_group("day_night_cycle")
			if dnc and not dnc.is_night and not dnc.is_waiting_for_day_start:
				_show_feedback("🌅 Hold [N] to End Day Early")

	if InputMap.has_action(input_equip_trash) and event.is_action_pressed(input_equip_trash):
		toggle_equip_trash_grenade()

	# Escape releases mouse
	if event.is_action_pressed("ui_cancel"):
		release_mouse()

	# Look around
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)

	# Toggle freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()


func _physics_process(delta: float) -> void:
	update_held_object()
	_process_action_cooldown(delta)
	_process_hold_pickup(delta)
	_process_end_day_hold(delta)
	_update_aim_prompt()

	# If freeflying, handle freefly and nothing else
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		motion *= freefly_speed * delta
		move_and_collide(motion)
		return
	
	# Apply gravity to velocity
	if has_gravity:
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Apply jumping
	if can_jump:
		if Input.is_action_just_pressed(input_jump) and is_on_floor():
			velocity.y = jump_velocity

	# Modify speed based on sprinting
	if can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if move_dir:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.y = 0
	
	# Use velocity to actually move
	move_and_slide()


## Rotate us to look around.
func rotate_look(rot_input : Vector2):
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func enable_freefly():
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO


func disable_freefly():
	collider.disabled = false
	freeflying = false


func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Checks if some Input Actions haven't been created.
func check_input_mappings():
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Movement disabled. No InputAction found for input_forward: " + input_forward)
		can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Movement disabled. No InputAction found for input_back: " + input_back)
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Freefly disabled. No InputAction found for input_freefly: " + input_freefly)
		can_freefly = false


# ===========================================================================
# Collection & Interaction Mechanics
# ===========================================================================

## Helper to determine if an object is collectible trash
func is_trash_object(object: Object) -> bool:
	if not is_instance_valid(object):
		return false
	return object is TrashObject or object.is_in_group("trash") or object.has_method("collect")


## Safely reads an object's weight (from weight property or RigidBody3D mass)
func _get_object_weight(object: Object) -> float:
	if not is_instance_valid(object):
		return 1.0
	if "weight" in object:
		return maxf(0.1, float(object.weight))
	elif object is RigidBody3D:
		return maxf(0.1, float((object as RigidBody3D).mass))
	return 1.0


## Collects the given object into the player's trash bag and adds its value to SlopCredit
func bag_object(object: Node) -> void:
	if not is_instance_valid(object):
		return

	if max_bag_capacity > 0 and total_items_in_bag >= max_bag_capacity:
		_show_feedback("Trash bag is full! (%d/%d)" % [total_items_in_bag, max_bag_capacity])
		return

	var id: String = "trash"
	var val: float = 1.0
	var w: float = _get_object_weight(object)
	var scene_path: String = ""

	if "item_id" in object:
		id = str(object.item_id)
	if "collection_value" in object:
		val = float(object.collection_value)
	if object.scene_file_path != "":
		scene_path = object.scene_file_path
	elif TRASH_SCENE_FALLBACKS.has(id):
		scene_path = TRASH_SCENE_FALLBACKS[id]
	else:
		scene_path = "res://plastic.tscn"

	# If currently holding this object, clear reference
	if held_object == object:
		held_object = null
		is_trash_grenade_equipped = false
		equipped_trash_data = {}

	# Add to inventory & SlopCredit
	var mult: float = 1.0
	if is_instance_valid(game_hud):
		mult = game_hud.current_mult
	var final_val: float = val * mult

	trash_bag[id] = trash_bag.get(id, 0) + 1
	trash_inventory_items.append({
		"id": id,
		"value": final_val,
		"weight": w,
		"scene_path": scene_path
	})
	total_items_in_bag += 1
	slop_credit += final_val
	daily_items_bagged += 1
	daily_sc_earned += final_val

	slop_credit_changed.emit(slop_credit, final_val)
	item_bagged.emit(id, final_val, slop_credit)

	if mult > 1.0:
		_show_feedback("+%.1f SC (%s - %.1fkg | ×%.1f)" % [final_val, id.capitalize(), w, mult])
	else:
		_show_feedback("+%.1f SC (%s - %.1fkg)" % [final_val, id.capitalize(), w])
	_update_hud()

	# Remove from world
	if object.has_method("collect"):
		object.collect()
	else:
		object.queue_free()


# ===========================================================================
# Hold-to-Pickup & Cooldown Processors (Minecraft-Style)
# ===========================================================================

## Handles holding the Left Mouse Button to pick up trash objects over time
func _process_hold_pickup(delta: float) -> void:
	if not mouse_captured:
		_reset_pickup_hold()
		return

	# If holding an item or grenade, hold-to-pickup is inactive
	if held_object:
		_reset_pickup_hold()
		return

	# Check if Left Mouse Button is actively held down
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pickup_ray.force_raycast_update()
		if pickup_ray.is_colliding():
			var target = pickup_ray.get_collider()
			if is_trash_object(target):
				if _current_pickup_target != target:
					_current_pickup_target = target
					_pickup_hold_timer = 0.0

				var w: float = _get_object_weight(target)
				var required_time: float = maxf(0.1, base_pickup_time + w * pickup_time_per_weight)

				_pickup_hold_timer += delta
				var progress: float = clampf(_pickup_hold_timer / required_time, 0.0, 1.0)

				# Green progress bar filling up like breaking a block in Minecraft
				_show_action_bar(progress, Color(0.25, 0.95, 0.45, 0.95))

				if progress >= 1.0:
					bag_object(target)
					_reset_pickup_hold()
				return

	# Reset if mouse button released or no longer looking at trash
	if _pickup_hold_timer > 0.0:
		_reset_pickup_hold()


func _reset_pickup_hold() -> void:
	_pickup_hold_timer = 0.0
	_current_pickup_target = null
	if throw_cooldown_timer <= 0.0:
		_hide_action_bar()


## Handles action cooldown (e.g. after throwing)
func _process_action_cooldown(delta: float) -> void:
	if throw_cooldown_timer > 0.0:
		throw_cooldown_timer = maxf(0.0, throw_cooldown_timer - delta)
		# Only show cooldown bar if not actively holding to pick up trash
		if _pickup_hold_timer <= 0.0:
			var recovery: float = 1.0 - (throw_cooldown_timer / throw_cooldown_duration)
			_show_action_bar(recovery, Color(0.9, 0.92, 0.98, 0.9))
			if throw_cooldown_timer <= 0.0:
				_hide_action_bar()


## Handles holding [N] key to end the day early (calls sunset)
func _process_end_day_hold(delta: float) -> void:
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if not dnc or dnc.is_night or dnc.get("is_waiting_for_day_start"):
		if _end_day_hold_timer > 0.0:
			_end_day_hold_timer = 0.0
			_hide_action_bar()
		return

	# Check if player is holding the N key
	if Input.is_key_pressed(KEY_N):
		# Avoid conflicting if player is actively holding mouse to pickup trash
		if _pickup_hold_timer > 0.0:
			return

		_end_day_hold_timer += delta
		var progress: float = clampf(_end_day_hold_timer / END_DAY_HOLD_DURATION, 0.0, 1.0)
		# Golden-orange hazard action bar for calling sunset
		_show_action_bar(progress, Color(1.0, 0.65, 0.15, 0.95))

		if is_instance_valid(_hud_prompt_label):
			_hud_prompt_label.text = "🌅 Ending Day Early... (%.0f%%)" % (progress * 100.0)
			_hud_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1.0))
			_hud_prompt_label.visible = true

		if _end_day_hold_timer >= END_DAY_HOLD_DURATION:
			_end_day_hold_timer = 0.0
			_hide_action_bar()
			if is_instance_valid(_hud_prompt_label):
				_hud_prompt_label.visible = false
			_show_feedback("🌅 Ending day early... Calling sunset!")
			if dnc.has_method("end_day_early"):
				dnc.end_day_early()
	else:
		if _end_day_hold_timer > 0.0:
			_end_day_hold_timer = 0.0
			if _pickup_hold_timer <= 0.0 and throw_cooldown_timer <= 0.0:
				_hide_action_bar()
			if is_instance_valid(_hud_prompt_label):
				_hud_prompt_label.visible = false


# ===========================================================================
# Grenade Equip & Throw System
# ===========================================================================

## Equips a random item from the trash bag into the ready position, or holsters if already equipped
func toggle_equip_trash_grenade() -> void:
	# If an equipped grenade is already out, holster it back into the bag
	if is_trash_grenade_equipped and held_object:
		holster_equipped_grenade()
		return

	# If currently carrying a normal physics object, drop it first
	if held_object:
		drop_object()

	# Check if we have anything in the trash bag
	if trash_inventory_items.is_empty():
		_show_feedback("Trash bag is empty! Pick up trash first.")
		return

	# Pick a random item from the bag
	var rand_index: int = randi() % trash_inventory_items.size()
	var item_data: Dictionary = trash_inventory_items.pop_at(rand_index)

	# Decrement aggregate count
	var id: String = item_data.get("id", "trash")
	if trash_bag.has(id):
		trash_bag[id] -= 1
		if trash_bag[id] <= 0:
			trash_bag.erase(id)
	total_items_in_bag = max(0, total_items_in_bag - 1)

	# Instantiate the scene
	var scene_path: String = item_data.get("scene_path", "")
	var scene: PackedScene = null
	if scene_path != "" and ResourceLoader.exists(scene_path):
		scene = load(scene_path)
	elif ResourceLoader.exists("res://plastic.tscn"):
		scene = load("res://plastic.tscn")
	elif ResourceLoader.exists("res://trash_object.tscn"):
		scene = load("res://trash_object.tscn")

	if not scene:
		_show_feedback("Could not load trash scene!")
		trash_inventory_items.append(item_data)
		trash_bag[id] = trash_bag.get(id, 0) + 1
		total_items_in_bag += 1
		_update_hud()
		return

	var instance = scene.instantiate()
	if not instance is RigidBody3D:
		instance.queue_free()
		return

	# Add to current scene
	get_tree().current_scene.add_child(instance)

	held_object = instance as RigidBody3D
	is_trash_grenade_equipped = true
	equipped_trash_data = item_data

	_position_ready_object()
	var w: float = item_data.get("weight", 1.0)
	_show_feedback("Equipped %s (%.1fkg) - Grenade ready!" % [id.capitalize(), w])
	_update_hud()


## Returns the currently equipped grenade back into the trash bag
func holster_equipped_grenade() -> void:
	if not is_trash_grenade_equipped:
		return

	if held_object and is_instance_valid(held_object):
		held_object.queue_free()
		held_object = null

	if not equipped_trash_data.is_empty():
		var id: String = equipped_trash_data.get("id", "trash")
		trash_inventory_items.append(equipped_trash_data)
		trash_bag[id] = trash_bag.get(id, 0) + 1
		total_items_in_bag += 1
		_show_feedback("Holstered %s back into bag" % id.capitalize())
		equipped_trash_data = {}

	is_trash_grenade_equipped = false
	_update_hud()


## Positions the equipped grenade in the first-person ready pose (bottom-right of view)
func _position_ready_object() -> void:
	if not held_object or not is_instance_valid(held_object):
		return

	held_object.freeze = true
	held_object.collision_layer = 0
	held_object.collision_mask = 0

	var target_tf := head.global_transform
	target_tf.origin = head.global_transform * ready_offset

	# Angled posture like holding a grenade
	target_tf.basis = target_tf.basis.rotated(target_tf.basis.x, deg_to_rad(20))
	target_tf.basis = target_tf.basis.rotated(target_tf.basis.y, deg_to_rad(-25))

	held_object.global_transform = target_tf


# Keep the object in front of the player or in ready position
func update_held_object():
	if held_object:
		if not is_instance_valid(held_object):
			held_object = null
			is_trash_grenade_equipped = false
			equipped_trash_data = {}
			_update_hud()
			return

		if is_trash_grenade_equipped:
			_position_ready_object()
		else:
			held_object.global_transform = hold_position.global_transform
			held_object.freeze = true
			held_object.collision_layer = 0
			held_object.collision_mask = 0


# Drop the object
func drop_object():
	if held_object:
		if is_trash_grenade_equipped:
			holster_equipped_grenade()
			return
		held_object.freeze = false
		held_object.collision_layer = 1
		held_object.collision_mask = 1
		held_object = null


# Throw the object (Right-Click)
func throw_object():
	if not held_object:
		return

	# Cannot throw while on cooldown
	if throw_cooldown_timer > 0.0:
		return

	var object = held_object
	held_object = null

	# Spawn slightly in front of head so it doesn't collide with player
	var spawn_pos: Vector3 = head.global_position - head.global_basis.z * 0.85 + head.global_basis.y * -0.15
	object.global_position = spawn_pos

	object.freeze = false
	object.collision_layer = 1
	object.collision_mask = 1
	object.add_collision_exception_with(self)

	# Ensure it can float in water and be re-collected
	object.add_to_group("floatable")
	object.add_to_group("trash")

	# Calculate weight-based throw cooldown
	var w: float = 1.0
	if is_trash_grenade_equipped and not equipped_trash_data.is_empty():
		w = equipped_trash_data.get("weight", 1.0)
	else:
		w = _get_object_weight(object)

	throw_cooldown_duration = maxf(0.15, base_throw_cooldown + w * throw_cooldown_per_weight)
	throw_cooldown_timer = throw_cooldown_duration

	if is_trash_grenade_equipped:
		# GRENADE HAUL: Upward arc + high velocity + spinning tumble
		var throw_direction = (-head.global_basis.z + Vector3.UP * grenade_arc_pitch).normalized()
		object.linear_velocity = throw_direction * grenade_throw_force

		# Intense grenade tumble spin
		var spin_axis = (-head.global_basis.x + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))).normalized()
		object.angular_velocity = spin_axis * grenade_spin_speed

		var id: String = equipped_trash_data.get("id", "trash")
		var val: float = equipped_trash_data.get("value", 1.0)

		if throw_costs_credit:
			slop_credit = maxf(0.0, slop_credit - val)
			slop_credit_changed.emit(slop_credit, -val)

		_show_feedback("Hauled %s like a grenade!" % id.capitalize())

		is_trash_grenade_equipped = false
		equipped_trash_data = {}
		_update_hud()
	else:
		# Standard drop/throw for regular physics props
		var throw_direction = -head.global_basis.z
		object.linear_velocity = throw_direction * throw_force
		object.angular_velocity = Vector3.ZERO


# ===========================================================================
# Economy & Inventory Helpers
# ===========================================================================

## Spend SlopCredit (e.g. for upgrades or shops). Returns true if successful.
func spend_slop_credit(amount: float) -> bool:
	if amount <= 0.0:
		return false
	if slop_credit >= amount:
		slop_credit -= amount
		slop_credit_changed.emit(slop_credit, -amount)
		_update_hud()
		return true
	return false


## Returns a duplicate of the trash bag inventory counts
func get_trash_bag_contents() -> Dictionary:
	return trash_bag.duplicate()


## Clear the trash bag (e.g. after depositing in a bin/recycler)
func empty_trash_bag() -> Dictionary:
	var contents := trash_bag.duplicate()
	trash_bag.clear()
	trash_inventory_items.clear()
	total_items_in_bag = 0
	_update_hud()
	return contents


# ===========================================================================
# In-Game HUD (Reticle, Action Bar, SlopCredit, Bag Count, Aim Prompt)
# ===========================================================================

func _setup_hud() -> void:
	if not show_hud:
		return

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "TrashBagHUD"
	add_child(_hud_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)

	# 1. Center Crosshair
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-15, -15)
	crosshair.size = Vector2(30, 30)
	crosshair.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	# 2. Action / Cooldown Bar (under crosshair, Minecraft-style)
	_action_bar = ProgressBar.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER)
	_action_bar.position = Vector2(-22, 18)
	_action_bar.size = Vector2(44, 6)
	_action_bar.show_percentage = false
	_action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_bar.min_value = 0.0
	_action_bar.max_value = 1.0
	_action_bar.value = 0.0
	_action_bar.visible = false

	var ab_bg := StyleBoxFlat.new()
	ab_bg.bg_color = Color(0.04, 0.05, 0.07, 0.8)
	ab_bg.border_color = Color(0.25, 0.3, 0.35, 0.9)
	ab_bg.set_border_width_all(1)
	ab_bg.corner_radius_top_left = 2
	ab_bg.corner_radius_top_right = 2
	ab_bg.corner_radius_bottom_left = 2
	ab_bg.corner_radius_bottom_right = 2
	_action_bar.add_theme_stylebox_override("background", ab_bg)

	_action_bar_style_fill = StyleBoxFlat.new()
	_action_bar_style_fill.bg_color = Color(0.25, 0.95, 0.45, 0.95)
	_action_bar_style_fill.corner_radius_top_left = 1
	_action_bar_style_fill.corner_radius_top_right = 1
	_action_bar_style_fill.corner_radius_bottom_left = 1
	_action_bar_style_fill.corner_radius_bottom_right = 1
	_action_bar.add_theme_stylebox_override("fill", _action_bar_style_fill)

	root.add_child(_action_bar)

	# 3. Aim Interaction Prompt
	_hud_prompt_label = Label.new()
	_hud_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_hud_prompt_label.position = Vector2(-200, 30)
	_hud_prompt_label.size = Vector2(400, 30)
	_hud_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_prompt_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55, 0.95))
	_hud_prompt_label.add_theme_font_size_override("font_size", 15)
	_hud_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_prompt_label.visible = false
	root.add_child(_hud_prompt_label)

	# 4. Toast notification for collected / hauled items
	_hud_toast_label = Label.new()
	_hud_toast_label.set_anchors_preset(Control.PRESET_CENTER)
	_hud_toast_label.position = Vector2(-200, -60)
	_hud_toast_label.size = Vector2(400, 30)
	_hud_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_toast_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25, 1.0))
	_hud_toast_label.add_theme_font_size_override("font_size", 18)
	_hud_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_toast_label.modulate.a = 0.0
	root.add_child(_hud_toast_label)

	# 5. Top-Left Inventory / Score Panel
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.06, 0.08, 0.12, 0.75)
	style_box.border_color = Color(0.2, 0.35, 0.45, 0.6)
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.content_margin_left = 16
	style_box.content_margin_top = 10
	style_box.content_margin_right = 16
	style_box.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style_box)
	panel.visible = false # Hidden in favor of the industrial GameHUD
	root.add_child(panel)

	# Instantiate Industrial Art GameHUD
	game_hud = GameHUD.new()
	game_hud.name = "GameHUD"
	add_child(game_hud)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_hud_sc_label = Label.new()
	_hud_sc_label.text = "SlopCredit: 0.0 SC"
	_hud_sc_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2, 1.0))
	_hud_sc_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_hud_sc_label)

	_hud_bag_label = Label.new()
	_hud_bag_label.text = "Trash Bag: 0 items"
	_hud_bag_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.9))
	_hud_bag_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_hud_bag_label)

	_hud_equipped_label = Label.new()
	_hud_equipped_label.text = "Ready: [G] to equip"
	_hud_equipped_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.85))
	_hud_equipped_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_hud_equipped_label)

	_update_hud()


func _show_action_bar(progress: float, fill_color: Color) -> void:
	if not is_instance_valid(_action_bar):
		return
	_action_bar.value = clampf(progress, 0.0, 1.0)
	if is_instance_valid(_action_bar_style_fill):
		_action_bar_style_fill.bg_color = fill_color
	_action_bar.visible = true


func _hide_action_bar() -> void:
	if is_instance_valid(_action_bar):
		_action_bar.visible = false
		_action_bar.value = 0.0


func _update_hud() -> void:
	if is_instance_valid(game_hud):
		game_hud._refresh_inventory_from_player(self)

	if not is_instance_valid(_hud_sc_label):
		return
	_hud_sc_label.text = "SlopCredit: %.1f SC" % slop_credit
	if max_bag_capacity > 0:
		_hud_bag_label.text = "Trash Bag: %d / %d items" % [total_items_in_bag, max_bag_capacity]
	else:
		_hud_bag_label.text = "Trash Bag: %d items" % total_items_in_bag

	if is_instance_valid(_hud_equipped_label):
		if is_trash_grenade_equipped and not equipped_trash_data.is_empty():
			var item_name: String = equipped_trash_data.get("id", "trash").capitalize()
			var item_wt: float = equipped_trash_data.get("weight", 1.0)
			_hud_equipped_label.text = "💣 Ready: %s (%.1fkg)" % [item_name, item_wt]
			_hud_equipped_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35, 1.0))
		else:
			if total_items_in_bag > 0:
				_hud_equipped_label.text = "Ready: None ([G] to equip)"
				_hud_equipped_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.85))
			else:
				_hud_equipped_label.text = "Ready: Empty bag"
				_hud_equipped_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.6))


func _show_feedback(msg: String) -> void:
	if not is_instance_valid(_hud_toast_label):
		return
	_hud_toast_label.text = msg
	_hud_toast_label.modulate.a = 1.0
	if _hud_toast_tween and _hud_toast_tween.is_valid():
		_hud_toast_tween.kill()
	_hud_toast_tween = create_tween()
	_hud_toast_tween.tween_property(_hud_toast_label, "modulate:a", 0.0, 1.0).set_delay(0.6)


func _update_aim_prompt() -> void:
	if not is_instance_valid(_hud_prompt_label):
		return

	# If currently holding N to end day early, keep that prompt visible
	if _end_day_hold_timer > 0.0:
		return

	# If grenade is equipped, prioritize showing the throw instruction & cooldown status
	if is_trash_grenade_equipped:
		var item_name: String = equipped_trash_data.get("id", "Trash").capitalize()
		var item_wt: float = equipped_trash_data.get("weight", 1.0)
		if throw_cooldown_timer > 0.0:
			_hud_prompt_label.text = "Cooldown... | [G] Holster"
			_hud_prompt_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
		else:
			_hud_prompt_label.text = "[R-Click] Haul %s (%.1fkg) | [G] Holster" % [item_name, item_wt]
			_hud_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35, 1.0))
		_hud_prompt_label.visible = true
		return

	# Show throw cooldown if still cooling down
	if throw_cooldown_timer > 0.0 and _pickup_hold_timer <= 0.0:
		_hud_prompt_label.text = "Cooldown..."
		_hud_prompt_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
		_hud_prompt_label.visible = true
		return

	# Standard collection / pickup prompts
	_hud_prompt_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55, 0.95))
	if pickup_ray and pickup_ray.is_colliding():
		var target = pickup_ray.get_collider()
		if is_trash_object(target):
			var item_name: String = target.item_id.capitalize() if "item_id" in target else "Trash"
			var item_val: float = target.collection_value if "collection_value" in target else 1.0
			var item_wt: float = _get_object_weight(target)
			_hud_prompt_label.text = "[Hold L-Click] Bag %s (+%.1f SC | %.1fkg)" % [item_name, item_val, item_wt]
			_hud_prompt_label.visible = true
			return
		elif target is RigidBody3D and not held_object:
			_hud_prompt_label.text = "[L-Click] Pick Up"
			_hud_prompt_label.visible = true
			return

	_hud_prompt_label.visible = false


# ===========================================================================
# Day / Night Callbacks
# ===========================================================================

## Called when the DayNightCycle transitions to a new day
func on_new_day_started() -> void:
	# Piggy Jar end-of-day interest: +$1 per $5 of total SC
	if piggy_jar_active and slop_credit >= 5.0:
		var interest: float = floorf(slop_credit / 5.0)
		slop_credit += interest
		slop_credit_changed.emit(slop_credit, interest)
		_show_feedback("🐷 Piggy Jar: +%.0f SC interest!" % interest)

	day_start_slop_credit = slop_credit
	daily_items_bagged = 0
	daily_sc_earned = 0.0
	_show_feedback("☀️ Good morning! New day has begun.")


## Called when the day is retried after a failed sunset quota
func on_day_retried() -> void:
	slop_credit = day_start_slop_credit
	daily_items_bagged = 0
	daily_sc_earned = 0.0
	_update_hud()
	_show_feedback("🔄 Day restarted! Meet the quota before sunset.")


func _ensure_day_night_cycle() -> void:
	var existing = get_tree().get_first_node_in_group("day_night_cycle")
	if not existing:
		var dnc = DayNightCycle.new()
		dnc.name = "DayNightCycle"
		get_tree().current_scene.add_child.call_deferred(dnc)


# ===========================================================================
# Buy Menus (Items & Machines)
# ===========================================================================

## Toggle the buy shop open / closed (B key)
func toggle_buy_menu() -> void:
	if is_instance_valid(buy_menu):
		# Already open — close it
		buy_menu.queue_free()
		buy_menu = null
		capture_mouse()
		return

	# Close any other open menus first
	if is_instance_valid(machine_menu):
		machine_menu.queue_free()
		machine_menu = null
	if is_instance_valid(quota_menu_instance):
		quota_menu_instance.queue_free()
		quota_menu_instance = null

	# Open the menu
	var menu := BuyMenu.new()
	menu._player = self
	menu._dnc = get_tree().get_first_node_in_group("day_night_cycle")
	# Wire day_started signal so the menu can kick off the day
	menu.day_started.connect(_on_buy_menu_day_started)
	get_tree().current_scene.add_child(menu)
	buy_menu = menu
	release_mouse()


## Toggle the Machine buy shop open / closed (M key)
func toggle_machine_menu() -> void:
	if is_instance_valid(machine_menu):
		machine_menu.queue_free()
		machine_menu = null
		capture_mouse()
		return

	# Close any other open menus first
	if is_instance_valid(buy_menu):
		buy_menu.queue_free()
		buy_menu = null
	if is_instance_valid(quota_menu_instance):
		quota_menu_instance.queue_free()
		quota_menu_instance = null

	var mm_script = load("res://machine_buy_menu.gd")
	if mm_script:
		var menu = mm_script.new()
		menu._player = self
		menu._dnc = get_tree().get_first_node_in_group("day_night_cycle")
		menu.day_started.connect(_on_buy_menu_day_started)
		get_tree().current_scene.add_child(menu)
		machine_menu = menu
		release_mouse()


func _on_buy_menu_day_started() -> void:
	# Menu closes itself — just capture mouse again
	capture_mouse()


## Toggle the Quota / Quest selection menu open / closed (Q key)
func toggle_quota_menu() -> void:
	if is_instance_valid(quota_menu_instance):
		quota_menu_instance.queue_free()
		quota_menu_instance = null
		capture_mouse()
		return

	# Close other menus first
	if is_instance_valid(buy_menu):
		buy_menu.queue_free()
		buy_menu = null
	if is_instance_valid(machine_menu):
		machine_menu.queue_free()
		machine_menu = null

	var qm_script = load("res://quota_menu.gd")
	if qm_script:
		var qm = qm_script.new()
		qm._player = self
		qm._dnc = get_tree().get_first_node_in_group("day_night_cycle")
		get_tree().current_scene.add_child(qm)
		quota_menu_instance = qm
		release_mouse()





func _deferred_check_day_night_cycle() -> void:
	var existing = get_tree().get_first_node_in_group("day_night_cycle")
	if not existing:
		var dnc = DayNightCycle.new()
		dnc.name = "DayNightCycle"
		get_tree().current_scene.add_child(dnc)
