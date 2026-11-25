# buy_menu.gd
# Mossy's Junkyard Outpost — Mod Shop Screen
# Accurately reproduces Mockup 4 using raw HD UI textures in res://UI/02_shop/ and res://UI/03_cards/

class_name BuyMenu
extends CanvasLayer

signal day_started
signal item_purchased(item_id: String)

const UIAssets = preload("res://ui_assets.gd")

const REROLL_COST: int = 2
const MAX_DAYS: int = 8

# Perk pool definition matching game balance and mockups
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
		"serial": "SCRAP-ID // 08-PIGGY",
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

# State
var _player = null
var _dnc: DayNightCycle = null

var _current_offers: Array[Dictionary] = []
var _buy_buttons: Array[Button] = []
var _button_glows: Array[ReferenceRect] = []
var _sc_label: Label = null
var _day_label: Label = null
var _dlg_label: Label = null
var _reroll_btn: Button = null
var _start_btn: Button = null

var _root: Control = null
var _content: Control = null
var _cards_container: Control = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_resolve_references()
	_build_ui()
	_refresh_offers()
	_refresh_header()

	# Hide GameHUD while buy menu is open
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = false


func _exit_tree() -> void:
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = true


func _resolve_references() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _dnc == null:
		_dnc = get_tree().get_first_node_in_group("day_night_cycle")


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ShopRoot"
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

	# 1. Fullscreen Dawn Wall Background (1280 x 720)
	var bg_tex := UIAssets.create_texture_rect("res://UI/02_shop/bg_dawn_wall.png")
	bg_tex.position = Vector2.ZERO
	bg_tex.size = Vector2(1280, 720)
	_content.add_child(bg_tex)

	# 2. Ranger Corkboard in Center (1200 x 562)
	var corkboard := UIAssets.create_texture_rect("res://UI/02_shop/ranger_corkboard.png")
	corkboard.position = Vector2(40, 76)
	corkboard.size = Vector2(1200, 562)
	_content.add_child(corkboard)

	# 3. Top Header Bar
	_build_header_bar()

	# 4. Mod Cards Container on Corkboard
	_cards_container = Control.new()
	_cards_container.position = Vector2(40, 76)
	_cards_container.size = Vector2(1200, 562)
	_content.add_child(_cards_container)

	# 5. Bottom Controls (Reroll, Mossy Dialogue, Start Day)
	_build_bottom_bar()


# ===========================================================================
# Header Bar (Day Plate, Shop Slab, Funds Plate)
# ===========================================================================
func _build_header_bar() -> void:
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

	# 2. Center Slab: MOSSY'S JUNKYARD OUTPOST (540 x 58)
	var title_slab := UIAssets.create_texture_rect("res://UI/02_shop/header_slab_shop_bg.png")
	title_slab.position = Vector2(370, 14)
	title_slab.size = Vector2(540, 58)
	_content.add_child(title_slab)

	var title_lbl := Label.new()
	title_lbl.text = "MOSSY'S JUNKYARD OUTPOST"
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


# ===========================================================================
# Mod Cards Construction
# ===========================================================================
func _rebuild_cards() -> void:
	if not is_instance_valid(_cards_container):
		return
	for child in _cards_container.get_children():
		child.queue_free()
	_buy_buttons.clear()
	_button_glows.clear()

	var card_x_offsets := [190.0, 520.0, 850.0]

	for i in range(_current_offers.size()):
		var perk: Dictionary = _current_offers[i]
		var card_x: float = card_x_offsets[i] if i < card_x_offsets.size() else 190.0 + (i * 330.0)
		_build_single_card(i, perk, card_x)


func _build_single_card(index: int, perk: Dictionary, pos_x: float) -> void:
	var card_w := 230.0
	var card_h := 380.0

	var card_base := Control.new()
	card_base.position = Vector2(pos_x, 40.0)
	card_base.custom_minimum_size = Vector2(card_w, card_h)
	card_base.size = Vector2(card_w, card_h)
	_cards_container.add_child(card_base)

	# 1. Base Card Texture (230 x 380)
	var card_bg := UIAssets.create_texture_rect("res://UI/03_cards/card_mod_base_empty.png")
	card_bg.position = Vector2.ZERO
	card_bg.size = Vector2(card_w, card_h)
	card_base.add_child(card_bg)

	# 2. Rarity Tape (Top-Left: 90 x 28)
	var rarity_str: String = perk.get("rarity", "COMMON").to_lower()
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
	cost_lbl.text = "$%d" % perk.get("cost", 0)
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

	# Blueprint Camera / Fixture Screw at Top Center
	var fixture_dot := ColorRect.new()
	fixture_dot.position = Vector2(92, 4)
	fixture_dot.size = Vector2(14, 6)
	fixture_dot.color = Color(0.4, 0.45, 0.5)
	grid_panel.add_child(fixture_dot)

	# Icon in Center of Blueprint Box
	var icon_lbl := Label.new()
	var icon_map := {
		"vest": "🦺",
		"crusher": "🔩",
		"piggy": "🐷",
		"boots": "👟",
		"magnet": "🧲",
		"bag": "🎒",
	}
	icon_lbl.text = icon_map.get(perk.get("icon", ""), "📦")
	icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 38)
	grid_panel.add_child(icon_lbl)

	# 5. Item Name Banner (y: 172)
	var name_box := PanelContainer.new()
	name_box.position = Vector2(16, 172)
	name_box.size = Vector2(198, 30)
	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.18, 0.14, 0.10, 0.95)
	sb_n.set_corner_radius_all(2)
	name_box.add_theme_stylebox_override("panel", sb_n)
	card_base.add_child(name_box)

	var name_lbl := Label.new()
	name_lbl.text = perk.get("name", "ITEM")
	name_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", Color(0.96, 0.94, 0.90))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_box.add_child(name_lbl)

	# 6. Description Text (y: 212)
	var desc_lbl := Label.new()
	desc_lbl.text = perk.get("desc", "")
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
	serial_lbl.text = perk.get("serial", "")
	serial_lbl.position = Vector2(16, 348)
	serial_lbl.size = Vector2(198, 16)
	serial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	serial_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.48))
	serial_lbl.add_theme_font_size_override("font_size", 9)
	card_base.add_child(serial_lbl)

	# 8. BUY Button positioned BELOW the card (btn_buy_amber_wood.png)
	var can_buy: bool = _player != null and _player.slop_credit >= perk.get("cost", 0)
	var owned: bool = _player != null and perk.get("id", "") in _get_owned_perks()

	var btn_txt := "✓ OWNED" if owned else ("BUY $%d" % perk.get("cost", 0))
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
	buy_btn.pressed.connect(_on_buy_pressed.bind(perk, index))
	_cards_container.add_child(buy_btn)
	_buy_buttons.append(buy_btn)

	# Cyan highlight glow around button when focused/selected (like in Mockup 4 for center card)
	var btn_glow := ReferenceRect.new()
	btn_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_glow.border_color = Color(0.20, 0.65, 0.98, 1.0)
	btn_glow.border_width = 2.5
	btn_glow.editor_only = false
	btn_glow.visible = (index == 1) # Highlight center card by default like Mockup 4
	buy_btn.add_child(btn_glow)
	_button_glows.append(btn_glow)


# ===========================================================================
# Bottom Bar (Reroll, Mossy Quote, Start Day)
# ===========================================================================
func _build_bottom_bar() -> void:
	# 1. Reroll Button (Left: 250 x 58)
	_reroll_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_reroll_green_wood.png",
		"🎲  REROLL ($%d)" % REROLL_COST,
		14,
		Color.WHITE,
		"",
		Vector2(240, 56)
	)
	_reroll_btn.position = Vector2(50, 648)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	_content.add_child(_reroll_btn)

	# 2. Dialogue Strip in Center
	var dlg_box := HBoxContainer.new()
	dlg_box.position = Vector2(320, 656)
	dlg_box.size = Vector2(620, 40)
	dlg_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dlg_box.add_theme_constant_override("separation", 10)
	_content.add_child(dlg_box)

	var frog_icon := Label.new()
	frog_icon.text = "🐸"
	frog_icon.add_theme_font_size_override("font_size", 18)
	dlg_box.add_child(frog_icon)

	_dlg_label = Label.new()
	_dlg_label.text = "Mossy: \"Pilih satu mod sebelum senja tiba, Ranger!\""
	_dlg_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.40))
	_dlg_label.add_theme_font_size_override("font_size", 13)
	_dlg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dlg_box.add_child(_dlg_label)

	# 3. Start Day Button on Right (302 x 82, fitted 260 x 56)
	_start_btn = UIAssets.create_textured_button(
		"res://UI/02_shop/btn_start_blue_wood.png",
		"START DAY  →",
		15,
		Color.WHITE,
		"",
		Vector2(260, 56)
	)
	_start_btn.position = Vector2(965, 648)
	_start_btn.pressed.connect(_on_start_day_pressed)
	_content.add_child(_start_btn)


# ===========================================================================
# Shop Logic & Interactions
# ===========================================================================
func _refresh_offers() -> void:
	_current_offers.clear()
	var unowned: Array[Dictionary] = []
	var owned_ids := _get_owned_perks()

	for p in PERK_POOL:
		if not (p.get("id", "") in owned_ids):
			unowned.append(p)

	unowned.shuffle()

	# Pick 3 items (or fallback to pool if few left)
	var count: int = mini(3, unowned.size())
	for i in range(count):
		_current_offers.append(unowned[i])

	while _current_offers.size() < 3 and PERK_POOL.size() > 0:
		var p = PERK_POOL[_current_offers.size() % PERK_POOL.size()]
		if not (_current_offers.has(p)):
			_current_offers.append(p)
		else:
			break

	_rebuild_cards()


func _refresh_header() -> void:
	var funds: int = 14
	if _player != null and "slop_credit" in _player:
		funds = int(_player.slop_credit)

	if is_instance_valid(_sc_label):
		_sc_label.text = "$%d" % funds

	var cur_day: int = 1
	if _dnc != null:
		cur_day = _dnc.current_day
	if is_instance_valid(_day_label):
		_day_label.text = "DAY %02d / %02d" % [cur_day, MAX_DAYS]

	if is_instance_valid(_reroll_btn):
		_reroll_btn.disabled = (funds < REROLL_COST)


func _on_buy_pressed(perk: Dictionary, card_index: int) -> void:
	var cost: int = perk.get("cost", 0)
	if _player == null or _player.slop_credit < cost:
		_set_mossy_text("Mossy: \"Duitmu kurang, Ranger! Bersihkan sampah lagi!\"")
		return

	# Deduct cost
	if _player.has_method("spend_slop_credit"):
		_player.spend_slop_credit(float(cost))
	else:
		_player.slop_credit -= float(cost)
	NetworkManager.broadcast_team_sc(-float(cost))

	# Apply perk effect to player
	_apply_perk_effect(perk.get("id", ""))

	# Equip visual icon in GameHUD
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud and hud.has_method("equip_perk"):
		var slot_idx: int = mini(card_index, 4)
		hud.equip_perk(slot_idx, perk.get("id", ""))

	emit_signal("item_purchased", perk.get("id", ""))

	# Select this button glow
	for i in range(_button_glows.size()):
		if is_instance_valid(_button_glows[i]):
			_button_glows[i].visible = (i == card_index)

	_refresh_header()
	_rebuild_cards()
	_set_mossy_text("Mossy: \"Pilihan bagus! Mod %s terpasang!\"" % perk.get("name", ""))


func _on_reroll_pressed() -> void:
	if _player == null or _player.slop_credit < REROLL_COST:
		_set_mossy_text("Mossy: \"Reroll butuh $%d, uangmu kurang!\"" % REROLL_COST)
		return

	if _player.has_method("spend_slop_credit"):
		_player.spend_slop_credit(float(REROLL_COST))
	else:
		_player.slop_credit -= float(REROLL_COST)
	NetworkManager.broadcast_team_sc(-float(REROLL_COST))

	_refresh_offers()
	_refresh_header()
	_set_mossy_text("Mossy: \"Stok baru keluar dari gudang!\"")


func _on_start_day_pressed() -> void:
	emit_signal("day_started")
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		var dnc = get_tree().get_first_node_in_group("day_night_cycle")
		if dnc:
			dnc.is_waiting_for_day_start = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		queue_free()
	)


func _set_mossy_text(text: String) -> void:
	if is_instance_valid(_dlg_label):
		_dlg_label.text = text


func _get_owned_perks() -> Array:
	if _player != null and "owned_perks" in _player:
		return _player.owned_perks
	return []


func _apply_perk_effect(perk_id: String) -> void:
	if _player == null:
		return

	if "owned_perks" in _player and not (perk_id in _player.owned_perks):
		_player.owned_perks.append(perk_id)

	match perk_id:
		"hivis_vest":
			if "streak_mult_bonus" in _player:
				_player.streak_mult_bonus += 0.15
		"can_crusher":
			if "metal_weight_mult" in _player:
				_player.metal_weight_mult = 1.5
		"piggy_jar":
			if "has_piggy_bank" in _player:
				_player.has_piggy_bank = true
		"speed_boots":
			if "speed_bonus" in _player:
				_player.speed_bonus += 0.20
		"magnet_glove":
			if "pickup_range" in _player:
				_player.pickup_range += 2.0
		"big_bag":
			if "bag_capacity" in _player:
				_player.bag_capacity += 10
