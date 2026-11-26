# buy_menu.gd
# Mossy's Junkyard Outpost — Mod Shop Screen [B]
# Preserves 100% of Co-op team SC sync & Fahri's player perk fields while
# rendering clean Opsi 3 Dark Wood cards on the Ranger Corkboard.

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
var _sc_label: Label = null
var _day_label: Label = null
var _dlg_label: Label = null
var _reroll_btn: Button = null
var _machines_btn: Button = null
var _start_btn: Button = null

var _root: Control = null
var _content: Control = null
var _cards_container: Control = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("buy_menu")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_resolve_references()
	_build_ui()
	_refresh_offers()
	_refresh_header()

	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = false
	UIAssets.sync_bgm()
	UIAssets.play_sfx("open", 0.03)


func _exit_tree() -> void:
	# GameHUD self-syncs visibility every frame; only restore if no other menu/modal is active
	var tree := get_tree()
	if tree:
		var any_other := false
		for grp in ["title_screen", "buy_menu", "machine_buy_menu", "quota_menu", "pause_menu", "ui_modal_popup"]:
			for n in tree.get_nodes_in_group(grp):
				if n != self and is_instance_valid(n) and not n.is_queued_for_deletion():
					any_other = true
					break
		var hud = tree.get_first_node_in_group("game_hud")
		if hud and not any_other:
			hud.visible = true
	UIAssets.sync_bgm()


func _resolve_references() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _dnc == null:
		_dnc = get_tree().get_first_node_in_group("day_night_cycle")


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ShopRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Full-bleed dark wood backdrop for ultrawide monitors
	var outer_bg := ColorRect.new()
	outer_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_bg.color = Color(0.08, 0.06, 0.05, 1.0)
	_root.add_child(outer_bg)

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

	# 1. Dawn Wall Background (1280 x 720)
	var bg_tex := UIAssets.create_texture_rect("res://UI/02_shop/bg_dawn_wall.png")
	bg_tex.position = Vector2.ZERO
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(bg_tex)

	# 2. Ranger Corkboard (1200 x 562)
	var corkboard := UIAssets.create_texture_rect("res://UI/02_shop/ranger_corkboard.png")
	corkboard.position = Vector2(40, 84)
	corkboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(corkboard)

	# 3. Top Header Bar
	_build_header_bar()

	# 4. Mod Cards Container on Corkboard
	_cards_container = Control.new()
	_cards_container.position = Vector2(40, 84)
	_cards_container.size = Vector2(1200, 562)
	_content.add_child(_cards_container)

	# 5. Mossy Quote Strip inside Bottom of Corkboard
	var dlg_box := HBoxContainer.new()
	dlg_box.position = Vector2(90, 594)
	dlg_box.size = Vector2(1100, 32)
	dlg_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dlg_box.add_theme_constant_override("separation", 8)
	dlg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(dlg_box)

	var frog_icon := Label.new()
	frog_icon.text = "🐸"
	frog_icon.add_theme_font_size_override("font_size", 16)
	dlg_box.add_child(frog_icon)

	var day_idx: int = clampi((_dnc.current_day - 1) if _dnc else 0, 0, MOSSY_LINES.size() - 1)
	_dlg_label = UIAssets.create_label(
		"Mossy: " + MOSSY_LINES[day_idx],
		13, Color(1.0, 0.90, 0.58), "bold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.65
	)
	dlg_box.add_child(_dlg_label)

	# 6. Bottom Wood Action Bar
	_build_bottom_bar()


# ===========================================================================
# Header Bar (Day Plate, Shop Slab, Funds Plate)
# ===========================================================================

func _build_header_bar() -> void:
	# 1. Day Plate (Left: 216 x 48)
	var day_plate := UIAssets.create_texture_rect("res://UI/02_shop/plate_day_bg.png")
	day_plate.position = Vector2(44, 18)
	day_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(day_plate)

	_day_label = UIAssets.create_label(
		"DAY 01 / 08", 16, UIAssets.COL_CREAM, "mono",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	_day_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	day_plate.add_child(_day_label)

	# 2. Center Slab: MOSSY'S JUNKYARD OUTPOST (540 x 58)
	var title_slab := UIAssets.create_texture_rect("res://UI/02_shop/header_slab_shop_bg.png")
	title_slab.position = Vector2(370, 14)
	title_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(title_slab)

	var title_lbl := UIAssets.create_label(
		"MOSSY'S JUNKYARD OUTPOST", 21, Color(0.18, 0.13, 0.09), "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_slab.add_child(title_lbl)

	# 3. Funds Plate (Right: 180 x 48)
	var funds_plate := UIAssets.create_texture_rect("res://UI/02_shop/plate_funds_bg.png")
	funds_plate.position = Vector2(1056, 18)
	funds_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(funds_plate)

	_sc_label = UIAssets.create_label(
		"$14", 19, UIAssets.COL_GOLD, "mono",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	_sc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	funds_plate.add_child(_sc_label)


# ===========================================================================
# Mod Cards Construction (Opsi 3 Dark Wood — Clean Blueprint & Wood Frame)
# ===========================================================================

func _rebuild_cards() -> void:
	if not is_instance_valid(_cards_container):
		return
	for child in _cards_container.get_children():
		child.queue_free()
	_buy_buttons.clear()

	# 3 cards (230px wide) symmetrically centered inside 1200px corkboard (margins 195px, gap 60px)
	var card_x_offsets := [195.0, 485.0, 775.0]
	for i in range(_current_offers.size()):
		var perk: Dictionary = _current_offers[i]
		var card_x: float = card_x_offsets[i] if i < card_x_offsets.size() else 195.0 + float(i) * 290.0
		_build_single_card(i, perk, card_x)


func _build_single_card(index: int, perk: Dictionary, pos_x: float) -> void:
	var card_w := 230.0
	var card_h := 380.0

	var card_base := Control.new()
	card_base.position = Vector2(pos_x, 34.0)
	card_base.custom_minimum_size = Vector2(card_w, card_h)
	card_base.size = Vector2(card_w, card_h)
	_cards_container.add_child(card_base)

	# 1. Base Opsi 3 Dark Wood Card Texture (230 x 380 — blueprint & name bar baked in!)
	var card_bg := UIAssets.create_texture_rect("res://UI/03_cards/card_mod_base_empty.png")
	card_bg.position = Vector2.ZERO
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(card_bg)

	# 2. Rarity Tape (Top-Left: 90 x 28 — texture is empty, render crisp rarity text!)
	var rarity_upper: String = str(perk.get("rarity", "COMMON")).to_upper()
	var tape_path := "res://UI/03_cards/tape_rarity_%s.png" % rarity_upper.to_lower()
	var tape_tex := UIAssets.create_texture_rect(tape_path)
	tape_tex.position = Vector2(8, 6)
	tape_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(tape_tex)

	var rarity_lbl := UIAssets.create_label(
		rarity_upper, 10, Color.WHITE, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.55
	)
	rarity_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	tape_tex.add_child(rarity_lbl)

	# 3. Price Plate Tag (Top-Right: 68 x 28)
	var price_plate := UIAssets.create_texture_rect("res://UI/03_cards/card_price_plate_empty.png")
	price_plate.position = Vector2(card_w - 76, 6)
	price_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(price_plate)

	var cost_lbl := UIAssets.create_label(
		"$%d" % int(perk.get("cost", 0)), 14, UIAssets.COL_GOLD, "mono",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	cost_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	price_plate.add_child(cost_lbl)

	# 4. Card Pixel-Art Window (186x115 exact fit inside card's baked artwork slot)
	var art_slot := Control.new()
	art_slot.position = Vector2(22, 46)
	art_slot.size = Vector2(186, 115)
	art_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(art_slot)

	var custom_art := UIAssets.get_card_art(str(perk.get("id", "")))
	if custom_art != null:
		var art_tr := TextureRect.new()
		art_tr.texture = custom_art
		art_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tr.stretch_mode = TextureRect.STRETCH_SCALE
		art_tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_slot.add_child(art_tr)
	else:
		var icon_map := {
			"vest": "🦺",
			"crusher": "🔩",
			"piggy": "🐷",
			"boots": "👟",
			"magnet": "🧲",
			"bag": "🎒",
		}
		var icon_lbl := Label.new()
		icon_lbl.text = icon_map.get(str(perk.get("icon", "")), "📦")
		icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 46)
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_slot.add_child(icon_lbl)

	# 5. Item Name directly on baked dark wood banner (y: 170..202)
	var name_lbl := UIAssets.create_label(
		str(perk.get("name", "ITEM")), 14, UIAssets.COL_CREAM, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	name_lbl.position = Vector2(18, 171)
	name_lbl.size = Vector2(194, 30)
	card_base.add_child(name_lbl)

	# 6. Wrapped Description Text cleanly inside cream body (y: 214..326)
	var desc_lbl := UIAssets.create_wrapped_label(
		str(perk.get("desc", "")),
		Vector2(22, 216),
		Vector2(186, 114),
		12, UIAssets.COL_INK, "semibold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	card_base.add_child(desc_lbl)

	# 7. Native Amber Wood BUY Button directly beneath card (222 x 74 w/ 16px shadow pad)
	var can_buy: bool = _player != null and _player.slop_credit >= int(perk.get("cost", 0))
	var owned: bool = _player != null and str(perk.get("id", "")) in _get_owned_perks()

	var btn_txt := "✓ OWNED" if owned else ("BUY  $%d" % int(perk.get("cost", 0)))
	var buy_btn := UIAssets.create_wood_button(
		"res://UI/02_shop/btn_buy_amber_wood.png",
		btn_txt,
		15,
		Color(0.20, 0.12, 0.05) if not owned else Color(0.14, 0.42, 0.20),
		"",
		"black",
		4
	)
	buy_btn.position = Vector2(pos_x + 4.0, 422.0)
	buy_btn.disabled = owned or (not can_buy)
	buy_btn.set_meta("suppress_default_click_sfx", true)
	buy_btn.pressed.connect(_on_buy_pressed.bind(perk, index))
	_cards_container.add_child(buy_btn)
	_buy_buttons.append(buy_btn)


# ===========================================================================
# Bottom Action Bar (Reroll, Heavy Machinery Shortcut, Start Day)
# ===========================================================================

func _build_bottom_bar() -> void:
	# 1. Reroll Button (Left: native 282 x 82)
	_reroll_btn = UIAssets.create_wood_button(
		"res://UI/02_shop/btn_reroll_green_wood.png",
		"REROLL  ($%d)" % REROLL_COST,
		15,
		Color.WHITE,
		"",
		"black",
		5
	)
	_reroll_btn.position = Vector2(30, 638)
	_reroll_btn.set_meta("suppress_default_click_sfx", true)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	_content.add_child(_reroll_btn)

	# 2. Switch to Heavy Machinery Workshop [M] (Center)
	_machines_btn = UIAssets.create_wood_button(
		"res://UI/02_shop/btn_contract_brown_wood.png",
		"MACHINES  [M]",
		14,
		UIAssets.COL_CREAM,
		"",
		"black",
		5
	)
	_machines_btn.custom_minimum_size = Vector2(268, 72)
	_machines_btn.size = Vector2(268, 72)
	_machines_btn.position = Vector2(506, 643)
	_machines_btn.pressed.connect(_on_machine_shop_pressed)
	_content.add_child(_machines_btn)

	# 3. Start Day / Resume Shift Button (Right: native 302 x 82 sunlit amber wood)
	_start_btn = UIAssets.create_wood_button(
		"res://UI/02_shop/btn_start_blue_wood.png",
		"START DAY  ➔",
		16,
		Color(0.20, 0.12, 0.05),
		"",
		"black",
		5
	)
	_start_btn.position = Vector2(948, 638)
	_start_btn.pressed.connect(_on_start_day_pressed)
	_content.add_child(_start_btn)


# ===========================================================================
# Shop Logic & Interactions (100% Preserved from 3e26359)
# ===========================================================================

func _refresh_offers() -> void:
	_current_offers.clear()
	var unowned: Array[Dictionary] = []
	var owned_ids := _get_owned_perks()

	for p in PERK_POOL:
		if not (p.get("id", "") in owned_ids):
			unowned.append(p)

	unowned.shuffle()

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

	if is_instance_valid(_start_btn):
		if _dnc != null and _dnc.is_waiting_for_day_start:
			_start_btn.text = "START DAY  ➔"
		elif _dnc != null and _dnc.is_night:
			_start_btn.text = "CLOSE SHOP  ➔"
		else:
			_start_btn.text = "RESUME SHIFT  ➔"


func _on_buy_pressed(perk: Dictionary, card_index: int) -> void:
	var cost: int = int(perk.get("cost", 0))
	if _player == null or _player.slop_credit < cost:
		UIAssets.play_sfx("error", 0.02)
		_set_mossy_text("Mossy: \"Duitmu kurang, Ranger! Bersihkan sampah lagi!\"")
		return

	UIAssets.play_sfx("buy", 0.05)
	if _player.has_method("spend_slop_credit"):
		_player.spend_slop_credit(float(cost))
	else:
		_player.slop_credit -= float(cost)
	if NetworkManager != null:
		NetworkManager.broadcast_team_sc(-float(cost))

	_apply_perk_effect(str(perk.get("id", "")))

	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		if hud.has_method("sync_perks_from_player"):
			hud.sync_perks_from_player(_player)
		elif hud.has_method("equip_perk"):
			var slot_idx: int = mini(card_index, 4)
			hud.equip_perk(slot_idx, str(perk.get("id", "")))

	emit_signal("item_purchased", str(perk.get("id", "")))
	_refresh_header()
	_rebuild_cards()
	_set_mossy_text("Mossy: \"Pilihan bagus! Mod %s terpasang!\"" % str(perk.get("name", "")))


func _on_reroll_pressed() -> void:
	if _player == null or _player.slop_credit < REROLL_COST:
		UIAssets.play_sfx("error", 0.02)
		_set_mossy_text("Mossy: \"Reroll butuh $%d, uangmu kurang!\"" % REROLL_COST)
		return

	UIAssets.play_sfx("reroll", 0.06)
	if _player.has_method("spend_slop_credit"):
		_player.spend_slop_credit(float(REROLL_COST))
	else:
		_player.slop_credit -= float(REROLL_COST)
	if NetworkManager != null:
		NetworkManager.broadcast_team_sc(-float(REROLL_COST))

	_refresh_offers()
	_refresh_header()
	_set_mossy_text("Mossy: \"Stok baru keluar dari gudang!\"")


func _on_machine_shop_pressed() -> void:
	if _player != null and _player.has_method("toggle_machine_menu"):
		_player.toggle_machine_menu()
	else:
		queue_free()


func _on_start_day_pressed() -> void:
	emit_signal("day_started")
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func():
		var dnc = get_tree().get_first_node_in_group("day_night_cycle")
		if dnc:
			dnc.is_waiting_for_day_start = false
		if _player != null and _player.has_method("capture_mouse"):
			_player.capture_mouse()
		else:
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
