# machine_buy_menu.gd
# Mossy's Junkyard Outpost — Heavy Machinery Workshop
# Opens with M key (toggled by ProtoController) or via shop navigation buttons.
# Unlike the item/mod buy menu which is randomized, the machine catalog is FIXED.
# Uses raw HD UI textures in res://UI/02_shop/ and res://UI/03_cards/

class_name MachineBuyMenu extends CanvasLayer

const UIAssets = preload("res://ui_assets.gd")

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal day_started
signal machine_purchased(machine_id: String)
signal closed

# ---------------------------------------------------------------------------
# Fixed Machine Catalog Definition
# ---------------------------------------------------------------------------
const MACHINE_CATALOG: Array[Dictionary] = [
	{
		"id": "metal_crusher",
		"name": "METAL CRUSHER",
		"rarity": "UNCOMMON",
		"cost": 15,
		"serial": "MACH-ID // 01-CRUSH",
		"desc": "Menghancurkan & memadatkan 3 sampah logam menjadi Kompak Metal Cube bernilai tinggi ($8 SC).",
		"icon": "crusher",
		"scene_path": "res://metal_crusher.tscn",
		"spawn_offset": Vector3(-3.5, 0.0, 3.9)
	},
	{
		"id": "plastic_burner",
		"name": "PLASTIC BURNER",
		"rarity": "UNCOMMON",
		"cost": 12,
		"serial": "MACH-ID // 02-BURN",
		"desc": "Membakar & melelehkan 3 sampah plastik menjadi Kompak Plastic Cube padat bernilai ($6 SC).",
		"icon": "burner",
		"scene_path": "res://plastic_burner.tscn",
		"spawn_offset": Vector3(-5.2, 0.0, 0.0)
	},
	{
		"id": "composter",
		"name": "COMPOSTER",
		"rarity": "COMMON",
		"cost": 8,
		"serial": "MACH-ID // 03-COMP",
		"desc": "Mengolah 5 sampah organik menjadi Pupuk Kompos ($3 SC) yang menumbuhkan pohon di outpost.",
		"icon": "composter",
		"scene_path": "res://composter.tscn",
		"spawn_offset": Vector3(3.5, 0.0, 2.5)
	},
]

# Mossy dialogue lines for machinery
const MOSSY_MACHINERY_LINES: Array[String] = [
	"\"Mesin industri siap dipasang untuk memproses sampah outpost-mu, Ranger!\"",
	"\"Metal Crusher & Plastic Burner bikin sampah bernilai berlipat ganda!\"",
	"\"Composter bikin sampah organik jadi pohon rindang di outpost.\"",
	"\"Peralatan berat ini investasi terbaik untuk ranger tangguh!\"",
	"\"Mesin otomatis menghemat waktu dan memaksimalkan kuota harian!\"",
]

const MAX_DAYS: int = 8

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _player = null
var _dnc = null
var _buy_buttons: Array[Button] = []
var _sc_label: Label = null
var _day_label: Label = null
var _dlg_label: Label = null
var _mod_shop_btn: Button = null
var _close_btn: Button = null
var _cards_hbox: HBoxContainer = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	_resolve_references()
	_sync_existing_world_machines()
	_build_ui()
	_rebuild_cards()
	_refresh_header()

	# Hide GameHUD while machine buy menu is open
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = false


func _exit_tree() -> void:
	# Restore GameHUD on close
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = true


func _resolve_references() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _dnc == null:
		_dnc = get_tree().get_first_node_in_group("day_night_cycle")


## Automatically registers any pre-placed machines in the world as owned
func _sync_existing_world_machines() -> void:
	if _player == null or not is_inside_tree():
		return
	var tree = get_tree()
	if not tree:
		return
	if not ("owned_machines" in _player):
		_player.set("owned_machines", [])

	for machine_data in MACHINE_CATALOG:
		var mid: String = machine_data["id"]
		if mid not in _player.owned_machines:
			var node = tree.get_first_node_in_group(mid)
			if node != null and is_instance_valid(node):
				_player.owned_machines.append(mid)


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.name = "MachineShopRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# 1280 x 720 centered canvas container
	var content := Control.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.offset_left = -640
	content.offset_right = 640
	content.offset_top = -360
	content.offset_bottom = 360
	content.custom_minimum_size = Vector2(1280, 720)
	content.size = Vector2(1280, 720)
	root.add_child(content)

	# Full-screen HD Backdrop & Workbench Background (1280 x 720)
	var bg_tex := UIAssets.create_texture_rect("res://UI/02_shop/shop_bg_full.png")
	bg_tex.position = Vector2.ZERO
	bg_tex.size = Vector2(1280, 720)
	content.add_child(bg_tex)

	# --- TOP HEADER BAR ----------------------------------------------------
	# 1. Funds Plate (Left: 186 x 52)
	var funds_bg := UIAssets.create_texture_rect("res://UI/02_shop/shop_header_funds_bg.png")
	funds_bg.position = Vector2(32, 12)
	funds_bg.size = Vector2(186, 52)
	content.add_child(funds_bg)

	_sc_label = Label.new()
	_sc_label.text = "$0"
	_sc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sc_label.add_theme_color_override("font_color", Color(0.96, 0.85, 0.25))
	_sc_label.add_theme_font_size_override("font_size", 18)
	funds_bg.add_child(_sc_label)

	# 2. Outpost Title Plate (Center: 586 x 52)
	var title_bg := UIAssets.create_texture_rect("res://UI/02_shop/shop_header_title_bg.png")
	title_bg.position = Vector2(347, 12)
	title_bg.size = Vector2(586, 52)
	content.add_child(title_bg)

	var title_lbl := Label.new()
	title_lbl.text = "MOSSY'S HEAVY MACHINERY WORKSHOP"
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	title_lbl.add_theme_font_size_override("font_size", 19)
	title_bg.add_child(title_lbl)

	# 3. Day Plate (Right: 186 x 52)
	var day_bg := UIAssets.create_texture_rect("res://UI/02_shop/shop_header_day_bg.png")
	day_bg.position = Vector2(1062, 12)
	day_bg.size = Vector2(186, 52)
	content.add_child(day_bg)

	_day_label = Label.new()
	_day_label.text = "DAY 1 / 8"
	_day_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_label.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	_day_label.add_theme_font_size_override("font_size", 16)
	day_bg.add_child(_day_label)

	# --- DIALOGUE STRIP (886 x 48) -----------------------------------------
	var dlg_bg := UIAssets.create_texture_rect("res://UI/02_shop/shop_dialogue_bg.png")
	dlg_bg.position = Vector2(197, 72)
	dlg_bg.size = Vector2(886, 48)
	content.add_child(dlg_bg)

	_dlg_label = Label.new()
	_dlg_label.text = "🐸 Mossy: \"Mesin industri siap dipasang untuk memproses sampah outpost-mu, Ranger!\""
	_dlg_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dlg_label.offset_left = 20
	_dlg_label.offset_right = -20
	_dlg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dlg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dlg_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
	_dlg_label.add_theme_font_size_override("font_size", 15)
	dlg_bg.add_child(_dlg_label)

	# --- CARDS CONTAINER (OVER THE WORKBENCH) ------------------------------
	_cards_hbox = HBoxContainer.new()
	_cards_hbox.name = "CardsHBox"
	_cards_hbox.position = Vector2(252, 134)
	_cards_hbox.custom_minimum_size = Vector2(775, 480)
	_cards_hbox.size = Vector2(775, 480)
	_cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_hbox.add_theme_constant_override("separation", 32)
	content.add_child(_cards_hbox)

	# --- BOTTOM BUTTONS ----------------------------------------------------
	# Switch to Mod Shop Button (Left: 246 x 58)
	_mod_shop_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_reroll_bg.png",
		"🛍️  MOD SHOP [B]",
		16,
		Color.WHITE
	)
	_mod_shop_btn.position = Vector2(32, 646)
	_mod_shop_btn.custom_minimum_size = Vector2(246, 58)
	_mod_shop_btn.size = Vector2(246, 58)
	_mod_shop_btn.pressed.connect(_on_mod_shop_pressed)
	content.add_child(_mod_shop_btn)

	# Close / Start Day Button (Right: 246 x 58)
	_close_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_start_day_bg.png",
		"START DAY →",
		17,
		Color.WHITE
	)
	_close_btn.position = Vector2(1002, 646)
	_close_btn.custom_minimum_size = Vector2(246, 58)
	_close_btn.size = Vector2(246, 58)
	_close_btn.pressed.connect(_on_close_pressed)
	content.add_child(_close_btn)


# ---------------------------------------------------------------------------
# Card Building (Fixed Roster)
# ---------------------------------------------------------------------------

func _rebuild_cards() -> void:
	if not is_instance_valid(_cards_hbox):
		return
	for c in _cards_hbox.get_children():
		c.queue_free()
	_buy_buttons.clear()

	for machine in MACHINE_CATALOG:
		var card := _build_card(machine)
		_cards_hbox.add_child(card)


func _build_card(machine: Dictionary) -> Control:
	var card_node := Control.new()
	card_node.custom_minimum_size = Vector2(237, 382)
	card_node.size = Vector2(237, 382)
	card_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 1. Base HD Card Texture (237 x 382)
	var card_bg := UIAssets.create_texture_rect("res://UI/03_cards/card_mod_base_empty.png")
	card_bg.position = Vector2.ZERO
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_node.add_child(card_bg)

	# 2. Rarity / Category Tape (Top-Left: 96 x 42) — Text baked into texture
	var rarity_str: String = machine.get("rarity", "COMMON").to_lower()
	var tape_path := "res://UI/03_cards/tape_rarity_%s.png" % rarity_str
	var tape_tex := UIAssets.create_texture_rect(tape_path)
	tape_tex.position = Vector2(4, 2)
	tape_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_node.add_child(tape_tex)

	# 3. Gold Stamp Badge (Top-Right: 51 x 51)
	var stamp_tex := UIAssets.create_texture_rect("res://UI/03_cards/card_stamp_gold_empty.png")
	stamp_tex.position = Vector2(178, 2)
	stamp_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_node.add_child(stamp_tex)

	var cost_lbl := Label.new()
	cost_lbl.text = "$%d" % machine.get("cost", 0)
	cost_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color(0.14, 0.10, 0.05))
	cost_lbl.add_theme_font_size_override("font_size", 14)
	stamp_tex.add_child(cost_lbl)

	# 4. Blueprint Art Icon in the center box (x: 25, y: 52, w: 186, h: 120)
	var icon_lbl := Label.new()
	var icon_map := {
		"crusher": "⚙️",
		"burner": "🔥",
		"composter": "🌱",
	}
	icon_lbl.text = icon_map.get(machine.get("icon", ""), "🏭")
	icon_lbl.position = Vector2(25, 52)
	icon_lbl.size = Vector2(186, 120)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 46)
	card_node.add_child(icon_lbl)

	# 5. Machine Name in the title banner (y: 182..214)
	var name_lbl := Label.new()
	name_lbl.text = machine.get("name", "MACHINE")
	name_lbl.position = Vector2(18, 184)
	name_lbl.size = Vector2(201, 30)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	name_lbl.add_theme_font_size_override("font_size", 15)
	card_node.add_child(name_lbl)

	# 6. Description inside MarginContainer with clean autowrap (x: 24, y: 224, w: 189, h: 78)
	var desc_box := MarginContainer.new()
	desc_box.position = Vector2(24, 224)
	desc_box.custom_minimum_size = Vector2(189, 78)
	desc_box.size = Vector2(189, 78)

	var desc_lbl := Label.new()
	desc_lbl.text = machine.get("desc", "")
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_color_override("font_color", Color(0.14, 0.14, 0.16))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_box.add_child(desc_lbl)
	card_node.add_child(desc_box)

	# 7. Serial Number (y: 308)
	var serial_lbl := Label.new()
	serial_lbl.text = machine.get("serial", "")
	serial_lbl.position = Vector2(20, 308)
	serial_lbl.size = Vector2(197, 16)
	serial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	serial_lbl.add_theme_color_override("font_color", Color(0.42, 0.44, 0.48))
	serial_lbl.add_theme_font_size_override("font_size", 9)
	card_node.add_child(serial_lbl)

	# 8. BUY Button using btn_yellow_bg.png (176 x 42) positioned at y: 328
	var owned: bool = _is_machine_owned(machine.get("id", ""))
	var can_buy: bool = _player != null and _player.slop_credit >= machine.get("cost", 0)

	var btn_txt := "✓ DEPLOYED" if owned else ("BUY $%d" % machine.get("cost", 0))
	var buy_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_yellow_bg.png",
		btn_txt,
		15,
		Color(0.14, 0.10, 0.05)
	)
	buy_btn.position = Vector2(30.5, 328)
	buy_btn.custom_minimum_size = Vector2(176, 42)
	buy_btn.size = Vector2(176, 42)

	if owned or not can_buy:
		buy_btn.disabled = true
	else:
		buy_btn.pressed.connect(_on_buy_machine_pressed.bind(machine))

	card_node.add_child(buy_btn)
	_buy_buttons.append(buy_btn)

	return card_node


# ---------------------------------------------------------------------------
# Purchasing & Machine Deployment
# ---------------------------------------------------------------------------

func _is_machine_owned(mid: String) -> bool:
	if _player and "owned_machines" in _player:
		return mid in _player.owned_machines
	return false


func _on_buy_machine_pressed(machine: Dictionary) -> void:
	if _player == null:
		return

	var mid: String = machine.get("id", "")
	var cost: int = machine.get("cost", 0)

	if _player.slop_credit < cost:
		return

	# Deduct funds
	_player.slop_credit -= cost
	if _player.has_signal("slop_credit_changed"):
		_player.slop_credit_changed.emit(_player.slop_credit, -float(cost))

	# Register machine
	if not ("owned_machines" in _player):
		_player.set("owned_machines", [])
	if mid not in _player.owned_machines:
		_player.owned_machines.append(mid)

	# Deploy machine in the game world
	_deploy_machine(machine)

	# Feedback
	if _player.has_method("_show_feedback"):
		_player._show_feedback("⚙️ %s Deployed at Outpost!" % machine.get("name", "Machine"))

	machine_purchased.emit(mid)

	_refresh_header()
	_rebuild_cards()


func _deploy_machine(machine: Dictionary) -> void:
	if not is_inside_tree():
		return

	var mid: String = machine.get("id", "")
	var scene_path: String = machine.get("scene_path", "")

	var tree = get_tree()
	if not tree:
		return

	# Check if machine already exists in scene
	var existing = tree.get_first_node_in_group(mid)
	if existing and is_instance_valid(existing):
		existing.visible = true
		if "process_mode" in existing:
			existing.process_mode = Node.PROCESS_MODE_INHERIT
		return

	# Otherwise instantiate into scene
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return

	var packed := load(scene_path) as PackedScene
	if not packed:
		return

	var instance = packed.instantiate()
	if not instance is Node3D:
		instance.queue_free()
		return

	# Determine deployment location
	var world_root = tree.current_scene if tree.current_scene else tree.root
	var spawn_pos := Vector3.ZERO

	if machine.has("spawn_offset"):
		spawn_pos = machine["spawn_offset"]
	elif _player and _player is Node3D:
		# Deploy in front of player
		spawn_pos = _player.global_position - _player.global_transform.basis.z * 4.0
		spawn_pos.y = _player.global_position.y

	world_root.add_child(instance)
	instance.global_position = spawn_pos


# ---------------------------------------------------------------------------
# Navigation & Header
# ---------------------------------------------------------------------------

func _refresh_header() -> void:
	if _sc_label and _player:
		_sc_label.text = "$%.0f" % _player.slop_credit
	elif _sc_label:
		_sc_label.text = "$0"

	if _day_label and _dnc:
		_day_label.text = "DAY %d / %d" % [_dnc.current_day, MAX_DAYS]
	elif _day_label:
		_day_label.text = "DAY 1 / %d" % MAX_DAYS

	if _dlg_label:
		var day_idx := 0
		if _dnc:
			day_idx = clamp(_dnc.current_day - 1, 0, MOSSY_MACHINERY_LINES.size() - 1)
		_dlg_label.text = "🐸 Mossy: " + MOSSY_MACHINERY_LINES[day_idx]


func _on_mod_shop_pressed() -> void:
	if _player and _player.has_method("toggle_buy_menu"):
		_player.toggle_buy_menu()
	queue_free()


func _on_close_pressed() -> void:
	day_started.emit()
	closed.emit()
	if _player and _player.has_method("capture_mouse"):
		_player.capture_mouse()
	queue_free()
