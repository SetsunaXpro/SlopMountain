# machine_buy_menu.gd
# Mossy's Junkyard Outpost — Heavy Machinery Workshop
# Opens with M key (toggled by ProtoController) or via shop navigation buttons.
# Uses raw HD UI textures in res://UI/02_shop/ and res://UI/03_cards/

class_name MachineBuyMenu
extends CanvasLayer

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
	{
		"id": "trap_hostile",
		"name": "HOSTILE TRAP",
		"rarity": "UNCOMMON",
		"cost": 10,
		"serial": "TRAP-ID // 04-HOST",
		"desc": "Memancing Feral Pest dalam radius 24m & melumpuhkannya selama 6 detik saat mendekat.",
		"icon": "trap_hostile",
		"scene_path": "res://trap_hostile.tscn",
		"spawn_offset": Vector3(2.0, 0.0, 4.0)
	},
	{
		"id": "trap_peaceful",
		"name": "PEACEFUL TRAP",
		"rarity": "COMMON",
		"cost": 8,
		"serial": "TRAP-ID // 05-PEAC",
		"desc": "Memancing Mountain Possum dalam radius 24m & menenangkannya selama 6 detik agar mudah diberi makan.",
		"icon": "trap_peaceful",
		"scene_path": "res://trap_peaceful.tscn",
		"spawn_offset": Vector3(-2.0, 0.0, 4.0)
	},
	{
		"id": "critter_compass",
		"name": "TRACKER COMPASS",
		"rarity": "RARE",
		"cost": 10,
		"serial": "GEAR-ID // 06-COMP",
		"desc": "Menampilkan arah & jarak menuju mob event yang bersembunyi di hutan secara real-time.",
		"icon": "compass",
		"scene_path": "",
		"spawn_offset": Vector3.ZERO
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
var _dnc: DayNightCycle = null
var _buy_buttons: Array[Button] = []
var _sc_label: Label = null
var _day_label: Label = null
var _dlg_label: Label = null
var _mod_shop_btn: Button = null
var _close_btn: Button = null
var _cards_container: Control = null

var _root: Control = null
var _content: Control = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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


func _sync_existing_world_machines() -> void:
	if _player == null:
		return
	if not ("owned_machines" in _player):
		_player.set("owned_machines", [])

	var tree = get_tree()
	if not tree:
		return

	# If the level already has machines, consider them owned/deployed
	for m in MACHINE_CATALOG:
		var mid: String = m.get("id", "")
		var node = tree.get_first_node_in_group(mid)
		if node and is_instance_valid(node):
			if mid not in _player.owned_machines:
				_player.owned_machines.append(mid)


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "MachineShopRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 1280 x 720 centered canvas container
	_content = Control.new()
	_content.name = "Content"
	_content.set_anchors_preset(Control.PRESET_CENTER)
	_content.offset_left = -640
	_content.offset_right = 640
	_content.offset_top = -360
	_content.offset_bottom = 360
	_content.custom_minimum_size = Vector2(1280, 720)
	_content.size = Vector2(1280, 720)
	_root.add_child(_content)

	# 1. Full-screen Dawn Wall Background (1280 x 720)
	var bg_tex := UIAssets.create_texture_rect("res://UI/02_shop/bg_dawn_wall.png")
	bg_tex.position = Vector2.ZERO
	bg_tex.size = Vector2(1280, 720)
	_content.add_child(bg_tex)

	# 2. Ranger Corkboard in Center (1200 x 562)
	var corkboard := UIAssets.create_texture_rect("res://UI/02_shop/ranger_corkboard.png")
	corkboard.position = Vector2(40, 76)
	corkboard.size = Vector2(1200, 562)
	_content.add_child(corkboard)

	# --- TOP HEADER BAR ----------------------------------------------------
	# 1. Day Plate (Left: 216 x 48)
	var day_plate := UIAssets.create_texture_rect("res://UI/02_shop/plate_day_bg.png")
	day_plate.position = Vector2(48, 16)
	day_plate.size = Vector2(216, 48)
	_content.add_child(day_plate)

	_day_label = Label.new()
	_day_label.text = "DAY 01 / 08"
	_day_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	_day_label.add_theme_font_size_override("font_size", 16)
	day_plate.add_child(_day_label)

	# 2. Outpost Title Plate (Center: 540 x 58)
	var title_slab := UIAssets.create_texture_rect("res://UI/02_shop/header_slab_shop_bg.png")
	title_slab.position = Vector2(370, 14)
	title_slab.size = Vector2(540, 58)
	_content.add_child(title_slab)

	var title_lbl := Label.new()
	title_lbl.text = "HEAVY MACHINERY WORKSHOP"
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color(0.20, 0.16, 0.12))
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_slab.add_child(title_lbl)

	# 3. Funds Plate (Right: 180 x 48)
	var funds_plate := UIAssets.create_texture_rect("res://UI/02_shop/plate_funds_bg.png")
	funds_plate.position = Vector2(1052, 16)
	funds_plate.size = Vector2(180, 48)
	_content.add_child(funds_plate)

	_sc_label = Label.new()
	_sc_label.text = "$14"
	_sc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sc_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.25))
	_sc_label.add_theme_font_size_override("font_size", 18)
	funds_plate.add_child(_sc_label)

	# --- CARDS CONTAINER ON CORKBOARD (Scrollable 2-row grid) --------------
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 76)
	scroll.size = Vector2(1200, 562)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	_cards_container = Control.new()
	_cards_container.custom_minimum_size = Vector2(1180, 860)
	_cards_container.size = Vector2(1180, 860)
	scroll.add_child(_cards_container)

	# --- BOTTOM BUTTONS ----------------------------------------------------
	# Switch to Mod Shop Button (Left: 240 x 56)
	_mod_shop_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_contract_brown_wood.png",
		"🛍️  MOD SHOP [B]",
		14,
		Color.WHITE,
		"",
		Vector2(240, 56)
	)
	_mod_shop_btn.position = Vector2(50, 648)
	_mod_shop_btn.pressed.connect(_on_mod_shop_pressed)
	_content.add_child(_mod_shop_btn)

	# Center Dialogue
	var dlg_box := HBoxContainer.new()
	dlg_box.position = Vector2(320, 656)
	dlg_box.size = Vector2(620, 40)
	dlg_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dlg_box.add_theme_constant_override("separation", 10)
	_content.add_child(dlg_box)

	var frog_icon := Label.new()
	frog_icon.text = "⚙️"
	frog_icon.add_theme_font_size_override("font_size", 18)
	dlg_box.add_child(frog_icon)

	_dlg_label = Label.new()
	_dlg_label.text = "Mossy: \"Mesin industri siap dipasang untuk memproses sampah outpost-mu!\""
	_dlg_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.40))
	_dlg_label.add_theme_font_size_override("font_size", 13)
	_dlg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dlg_box.add_child(_dlg_label)

	# Close / Start Day Button (Right: 260 x 56)
	_close_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_start_blue_wood.png",
		"START DAY  →",
		15,
		Color.WHITE,
		"",
		Vector2(260, 56)
	)
	_close_btn.position = Vector2(965, 648)
	_close_btn.pressed.connect(_on_close_pressed)
	_content.add_child(_close_btn)


# ---------------------------------------------------------------------------
# Card Building (Fixed Roster)
# ---------------------------------------------------------------------------

func _rebuild_cards() -> void:
	if not is_instance_valid(_cards_container):
		return
	for c in _cards_container.get_children():
		c.queue_free()
	_buy_buttons.clear()

	var card_x_offsets := [190.0, 520.0, 850.0]

	for i in range(MACHINE_CATALOG.size()):
		var machine: Dictionary = MACHINE_CATALOG[i]
		var col := i % 3
		var row := i / 3
		var card_x: float = card_x_offsets[col]
		var card_y: float = 20.0 + float(row) * 415.0
		_build_card(machine, card_x, card_y)


func _build_card(machine: Dictionary, pos_x: float, pos_y: float = 40.0) -> void:
	var card_w := 230.0
	var card_h := 380.0

	var card_base := Control.new()
	card_base.position = Vector2(pos_x, pos_y)
	card_base.custom_minimum_size = Vector2(card_w, card_h)
	card_base.size = Vector2(card_w, card_h)
	_cards_container.add_child(card_base)

	# 1. Base HD Card Texture (230 x 380)
	var card_bg := UIAssets.create_texture_rect("res://UI/03_cards/card_mod_base_empty.png")
	card_bg.position = Vector2.ZERO
	card_bg.size = Vector2(card_w, card_h)
	card_base.add_child(card_bg)

	# 2. Rarity / Category Tape (Top-Left: 90 x 28)
	var rarity_str: String = machine.get("rarity", "COMMON").to_lower()
	var tape_path := "res://UI/03_cards/tape_rarity_%s.png" % rarity_str
	var tape_tex := UIAssets.create_texture_rect(tape_path)
	tape_tex.position = Vector2(6, 4)
	tape_tex.size = Vector2(90, 28)
	card_base.add_child(tape_tex)

	# 3. Price Plate Tag (Top-Right: 68 x 28)
	var price_plate := UIAssets.create_texture_rect("res://UI/03_cards/card_price_plate_empty.png")
	price_plate.position = Vector2(card_w - 74, 4)
	price_plate.size = Vector2(68, 28)
	card_base.add_child(price_plate)

	var cost_lbl := Label.new()
	cost_lbl.text = "$%d" % machine.get("cost", 0)
	cost_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color(0.98, 0.88, 0.25))
	cost_lbl.add_theme_font_size_override("font_size", 13)
	price_plate.add_child(cost_lbl)

	# 4. Blueprint Display Area with Grid (x: 16, y: 44, w: 198, h: 120)
	var grid_panel := PanelContainer.new()
	grid_panel.position = Vector2(16, 44)
	grid_panel.size = Vector2(198, 120)
	var sb_grid := StyleBoxFlat.new()
	sb_grid.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	sb_grid.border_color = Color(0.18, 0.24, 0.34)
	sb_grid.set_border_width_all(1)
	sb_grid.set_corner_radius_all(2)
	grid_panel.add_theme_stylebox_override("panel", sb_grid)
	card_base.add_child(grid_panel)

	# Icon
	var icon_lbl := Label.new()
	var icon_map := {
		"crusher": "⚙️",
		"burner": "🔥",
		"composter": "🌱",
		"trap_hostile": "🪤",
		"trap_peaceful": "🌿",
		"compass": "🧭",
	}
	icon_lbl.text = icon_map.get(machine.get("icon", ""), "🏭")
	icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 42)
	grid_panel.add_child(icon_lbl)

	# 5. Machine Name Banner (y: 172)
	var name_box := PanelContainer.new()
	name_box.position = Vector2(16, 172)
	name_box.size = Vector2(198, 30)
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.18, 0.14, 0.10, 0.95)
	sb_n.set_corner_radius_all(2)
	name_box.add_theme_stylebox_override("panel", sb_n)
	card_base.add_child(name_box)

	var name_lbl := Label.new()
	name_lbl.text = machine.get("name", "MACHINE")
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color(0.96, 0.94, 0.90))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_box.add_child(name_lbl)

	# 6. Description Text (y: 212)
	var desc_lbl := Label.new()
	desc_lbl.text = machine.get("desc", "")
	desc_lbl.position = Vector2(18, 212)
	desc_lbl.size = Vector2(194, 95)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_color_override("font_color", Color(0.18, 0.18, 0.20))
	desc_lbl.add_theme_font_size_override("font_size", 11)
	card_base.add_child(desc_lbl)

	# 7. Serial Number Footer (y: 348)
	var serial_lbl := Label.new()
	serial_lbl.text = machine.get("serial", "")
	serial_lbl.position = Vector2(16, 348)
	serial_lbl.size = Vector2(198, 16)
	serial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	serial_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.48))
	serial_lbl.add_theme_font_size_override("font_size", 9)
	card_base.add_child(serial_lbl)

	# 8. BUY Button positioned BELOW the card (btn_buy_amber_wood.png)
	var owned: bool = _is_machine_owned(machine.get("id", ""))
	var can_buy: bool = _player != null and _player.slop_credit >= machine.get("cost", 0)

	var btn_txt := "✓ OWNED [C]" if owned else ("BUY $%d" % machine.get("cost", 0))
	var buy_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_buy_amber_wood.png",
		btn_txt,
		14,
		Color(0.20, 0.14, 0.08),
		"",
		Vector2(210, 56)
	)
	buy_btn.position = Vector2(pos_x + 10, 436.0)
	buy_btn.disabled = owned or (not can_buy)
	if not owned and can_buy:
		buy_btn.pressed.connect(_on_buy_machine_pressed.bind(machine))

	_cards_container.add_child(buy_btn)
	_buy_buttons.append(buy_btn)


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
	NetworkManager.broadcast_team_sc(-float(cost))

	# Register machine / trap / compass
	if mid == "critter_compass":
		if "has_compass" in _player:
			_player.has_compass = true
	if not ("owned_machines" in _player):
		_player.set("owned_machines", [])
	if mid not in _player.owned_machines:
		_player.owned_machines.append(mid)
	NetworkManager.broadcast_unlock_machine(mid)

	# Select this item on player so pressing C places it immediately
	if mid != "critter_compass" and _player.has_method("select_machine_by_id"):
		_player.select_machine_by_id(mid)

	# Feedback
	if _player.has_method("_show_feedback"):
		_player._show_feedback("⚙️ %s Purchased! Press [1-3] to select, [C] to build!" % machine.get("name", "Machine"))

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
		_day_label.text = "DAY %02d / %02d" % [_dnc.current_day, MAX_DAYS]
	elif _day_label:
		_day_label.text = "DAY 01 / %02d" % MAX_DAYS

	if _dlg_label:
		var day_idx := 0
		if _dnc:
			day_idx = clamp(_dnc.current_day - 1, 0, MOSSY_MACHINERY_LINES.size() - 1)
		_dlg_label.text = "Mossy: " + MOSSY_MACHINERY_LINES[day_idx]


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
