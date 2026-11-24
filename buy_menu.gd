# buy_menu.gd
# Mossy's Junkyard Outpost — Mod Shop
# Opens with B key (toggled by ProtoController) or between days.
# Uses raw HD UI textures in res://UI/02_shop/ and res://UI/03_cards/

class_name BuyMenu extends CanvasLayer

const UIAssets = preload("res://ui_assets.gd")

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal day_started
signal item_purchased(item_id: String)

# ---------------------------------------------------------------------------
# Perk pool definition
# ---------------------------------------------------------------------------
const PERK_POOL: Array[Dictionary] = [
	{
		"id": "hivis_vest",
		"name": "HI-VIS VEST",
		"rarity": "COMMON",
		"cost": 4,
		"serial": "SCRAP-ID // 01-VEST",
		"desc": "Multiplier bonus naik +0.15 per sampah yang disortir benar.",
		"icon": "vest"
	},
	{
		"id": "can_crusher",
		"name": "CAN CRUSHER",
		"rarity": "COMMON",
		"cost": 5,
		"serial": "SCRAP-ID // 02-CRUSH",
		"desc": "Sampah Logam (Metal) dihitung bernilai x1.5 kg lebih berat ke kuota.",
		"icon": "crusher"
	},
	{
		"id": "piggy_jar",
		"name": "PIGGY JAR",
		"rarity": "UNCOMMON",
		"cost": 6,
		"serial": "SCRAP-ID // 03-PIGGY",
		"desc": "Di akhir hari patroli, dapat bonus bunga +$1 per simpanan $5 uang.",
		"icon": "piggy"
	},
	{
		"id": "speed_boots",
		"name": "SPEED BOOTS",
		"rarity": "COMMON",
		"cost": 3,
		"serial": "SCRAP-ID // 04-BOOT",
		"desc": "Kecepatan bergerak naik +20%. Lari lebih cepat bersihkan area.",
		"icon": "boots"
	},
	{
		"id": "magnet_glove",
		"name": "MAGNET GLOVE",
		"rarity": "UNCOMMON",
		"cost": 7,
		"serial": "SCRAP-ID // 05-MAGN",
		"desc": "Jangkauan pickup bertambah +2m. Raih sampah dari kejauhan.",
		"icon": "magnet"
	},
	{
		"id": "big_bag",
		"name": "BIG BAG",
		"rarity": "COMMON",
		"cost": 4,
		"serial": "SCRAP-ID // 06-BAG",
		"desc": "Kapasitas trash bag bertambah +10 slot. Tampung lebih banyak.",
		"icon": "bag"
	},
]

# Mossy dialogue lines
const MOSSY_LINES: Array[String] = [
	"\"Pilih satu mod sebelum senja tiba, Ranger!\"",
	"\"Stok terbatas, ambil yang terbaik!\"",
	"\"Hari makin gelap — belanja cepat!\"",
	"\"Barang bagus untuk ranger tangguh!\"",
	"\"Kalau mau bersih, perlu alat yang tepat.\"",
	"\"Sisa hari masih panjang, jangan buang waktu!\"",
	"\"Upgrade-mu hari ini bisa menentukan segalanya!\"",
	"\"Hari terakhir! Pastikan kamu siap, bos!\"",
]

const REROLL_COST: int = 2
const MAX_DAYS: int = 8

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _player = null
var _dnc = null
var _current_offers: Array[Dictionary] = []
var _buy_buttons: Array[Button] = []
var _sc_label: Label = null
var _day_label: Label = null
var _dlg_label: Label = null
var _reroll_btn: Button = null
var _start_btn: Button = null
var _cards_hbox: HBoxContainer = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	_resolve_references()
	_build_ui()
	_refresh_offers()
	_refresh_header()

	# Hide GameHUD while buy menu is open
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


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.name = "ShopRoot"
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
	title_lbl.text = "MOSSY'S JUNKYARD OUTPOST"
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	title_lbl.add_theme_font_size_override("font_size", 20)
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
	_dlg_label.text = "🐸 Mossy: \"Pilih satu mod sebelum senja tiba, Ranger!\""
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
	# REROLL Button (246 x 58)
	_reroll_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_reroll_bg.png",
		"🎲  REROLL ($%d)" % REROLL_COST,
		16,
		Color.WHITE
	)
	_reroll_btn.position = Vector2(32, 646)
	_reroll_btn.custom_minimum_size = Vector2(246, 58)
	_reroll_btn.size = Vector2(246, 58)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	content.add_child(_reroll_btn)

	# MACHINES Button (246 x 58)
	var mach_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_reroll_bg.png",
		"⚙️  MACHINES [M]",
		16,
		Color.WHITE
	)
	mach_btn.position = Vector2(298, 646)
	mach_btn.custom_minimum_size = Vector2(246, 58)
	mach_btn.size = Vector2(246, 58)
	mach_btn.pressed.connect(_on_machine_shop_pressed)
	content.add_child(mach_btn)

	# START DAY Button (246 x 58)
	_start_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_start_day_bg.png",
		"START DAY →",
		17,
		Color.WHITE
	)
	_start_btn.position = Vector2(1002, 646)
	_start_btn.custom_minimum_size = Vector2(246, 58)
	_start_btn.size = Vector2(246, 58)
	_start_btn.pressed.connect(_on_start_day_pressed)
	content.add_child(_start_btn)


# ---------------------------------------------------------------------------
# Card Building
# ---------------------------------------------------------------------------

func _rebuild_cards() -> void:
	if not is_instance_valid(_cards_hbox):
		return
	for c in _cards_hbox.get_children():
		c.queue_free()
	_buy_buttons.clear()

	for perk in _current_offers:
		var card := _build_card(perk)
		_cards_hbox.add_child(card)


func _build_card(perk: Dictionary) -> Control:
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

	# 2. Rarity Tape (Top-Left: 96 x 42) — Text is already baked on texture
	var rarity_str: String = perk.get("rarity", "COMMON").to_lower()
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
	cost_lbl.text = "$%d" % perk.get("cost", 0)
	cost_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color(0.14, 0.10, 0.05))
	cost_lbl.add_theme_font_size_override("font_size", 14)
	stamp_tex.add_child(cost_lbl)

	# 4. Blueprint Art Icon in the center box (x: 25, y: 50, w: 186, h: 122)
	var icon_lbl := Label.new()
	var icon_map := {
		"vest": "🦺",
		"crusher": "🔩",
		"piggy": "🐷",
		"boots": "👟",
		"magnet": "🧲",
		"bag": "🛍",
	}
	icon_lbl.text = icon_map.get(perk.get("icon", ""), "📦")
	icon_lbl.position = Vector2(25, 60)
	icon_lbl.size = Vector2(186, 100)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 42)
	card_node.add_child(icon_lbl)

	# 5. Item Name in the title banner (y: 182..214)
	var name_lbl := Label.new()
	name_lbl.text = perk.get("name", "ITEM")
	name_lbl.position = Vector2(18, 184)
	name_lbl.size = Vector2(201, 30)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	name_lbl.add_theme_font_size_override("font_size", 15)
	card_node.add_child(name_lbl)

	# 6. Description inside the light cream box (x: 24, y: 224, w: 189, h: 78)
	var desc_box := MarginContainer.new()
	desc_box.position = Vector2(24, 224)
	desc_box.custom_minimum_size = Vector2(189, 78)
	desc_box.size = Vector2(189, 78)

	var desc_lbl := Label.new()
	desc_lbl.text = perk.get("desc", "")
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
	serial_lbl.text = perk.get("serial", "")
	serial_lbl.position = Vector2(20, 308)
	serial_lbl.size = Vector2(197, 16)
	serial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	serial_lbl.add_theme_color_override("font_color", Color(0.42, 0.44, 0.48))
	serial_lbl.add_theme_font_size_override("font_size", 9)
	card_node.add_child(serial_lbl)

	# 8. BUY Button using btn_yellow_bg.png (176 x 42) positioned at y: 328
	var can_buy: bool = _player != null and _player.slop_credit >= perk.get("cost", 0)
	var owned: bool = _player != null and perk.get("id", "") in _get_owned_perks()

	var btn_txt := "✓ OWNED" if owned else ("BUY $%d" % perk.get("cost", 0))
	var buy_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_yellow_bg.png",
		btn_txt,
		15,
		Color(0.14, 0.10, 0.05)
	)
	buy_btn.position = Vector2(30.5, 328)
	buy_btn.custom_minimum_size = Vector2(176, 42)
	buy_btn.size = Vector2(176, 42)

	if not can_buy or owned:
		buy_btn.disabled = true
	else:
		buy_btn.pressed.connect(_on_buy_pressed.bind(perk.get("id", ""), perk.get("cost", 0)))

	card_node.add_child(buy_btn)
	_buy_buttons.append(buy_btn)

	return card_node


# ---------------------------------------------------------------------------
# Data / State
# ---------------------------------------------------------------------------

func _refresh_offers() -> void:
	var owned: Array = _get_owned_perks()
	var available: Array[Dictionary] = []
	for p in PERK_POOL:
		if p["id"] not in owned:
			available.append(p)

	available.shuffle()
	_current_offers = available.slice(0, min(3, available.size()))
	_rebuild_cards()
	_refresh_header()


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
			day_idx = clamp(_dnc.current_day - 1, 0, MOSSY_LINES.size() - 1)
		_dlg_label.text = "🐸 Mossy: " + MOSSY_LINES[day_idx]

	if _reroll_btn:
		var can_reroll: bool = _player != null and _player.slop_credit >= REROLL_COST
		_reroll_btn.disabled = not can_reroll


func _get_owned_perks() -> Array:
	if _player and "owned_perks" in _player:
		return _player.owned_perks
	return []


# ---------------------------------------------------------------------------
# Button Callbacks
# ---------------------------------------------------------------------------

func _on_buy_pressed(perk_id: String, cost: int) -> void:
	if _player == null:
		return
	if _player.slop_credit < cost:
		return
	var owned: Array = _get_owned_perks()
	if perk_id in owned:
		return

	_player.slop_credit -= cost
	if _player.has_signal("slop_credit_changed"):
		_player.slop_credit_changed.emit(_player.slop_credit, -float(cost))

	if "owned_perks" in _player:
		_player.owned_perks.append(perk_id)

	_apply_perk(_player, perk_id)
	_notify_hud_perk(perk_id)

	item_purchased.emit(perk_id)
	_refresh_header()
	_rebuild_cards()


func _on_reroll_pressed() -> void:
	if _player == null:
		return
	if _player.slop_credit < REROLL_COST:
		return
	_player.slop_credit -= REROLL_COST
	if _player.has_signal("slop_credit_changed"):
		_player.slop_credit_changed.emit(_player.slop_credit, -float(REROLL_COST))
	_refresh_offers()
	_refresh_header()


func _on_machine_shop_pressed() -> void:
	if _player and _player.has_method("toggle_machine_menu"):
		_player.toggle_machine_menu()
	queue_free()


func _on_start_day_pressed() -> void:
	day_started.emit()
	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	var needs_quota: bool = dnc != null and "is_waiting_for_day_start" in dnc and dnc.is_waiting_for_day_start

	if _player and _player.has_method("toggle_buy_menu"):
		_player.toggle_buy_menu()
	else:
		queue_free()

	if needs_quota and dnc != null and dnc.has_method("open_quota_selection"):
		dnc.open_quota_selection()


# ---------------------------------------------------------------------------
# Perk Application
# ---------------------------------------------------------------------------

func _apply_perk(player: Node, perk_id: String) -> void:
	match perk_id:
		"hivis_vest":
			if "extra_mult_per_item" in player:
				player.extra_mult_per_item += 0.15
		"can_crusher":
			if "metal_weight_multiplier" in player:
				player.metal_weight_multiplier = 1.5
		"piggy_jar":
			if "piggy_jar_active" in player:
				player.piggy_jar_active = true
		"speed_boots":
			if "base_speed" in player:
				player.base_speed *= 1.20
		"magnet_glove":
			if "pickup_range_bonus" in player:
				player.pickup_range_bonus += 2.0
			if "pickup_distance" in player:
				player.pickup_distance += 2.0
			if "pickup_ray" in player and player.pickup_ray != null:
				player.pickup_ray.target_position = Vector3(0, 0, -player.pickup_distance)
		"big_bag":
			if "max_bag_capacity" in player:
				if player.max_bag_capacity <= 0:
					player.max_bag_capacity = 10
				else:
					player.max_bag_capacity += 10


func _notify_hud_perk(perk_id: String) -> void:
	var hud = get_tree().get_first_node_in_group("game_hud")
	if not hud:
		return
	if hud.has_method("equip_perk"):
		var slot_map := {
			"hivis_vest": 0,
			"piggy_jar": 1,
			"can_crusher": 2,
			"speed_boots": 3,
			"magnet_glove": 4,
			"big_bag": 4,
		}
		if perk_id in slot_map:
			hud.equip_perk(slot_map[perk_id], perk_id)
