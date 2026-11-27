# machine_buy_menu.gd
# Mossy's Junkyard Outpost — Heavy Machinery & Tools Workshop [M]
# Fixes the stacked 2-row BUY button & corkboard overflow bug while preserving
# 100% of all 6 machines/traps/compass + Co-op unlock & build-mode logic.

class_name MachineBuyMenu
extends CanvasLayer

const UIAssets = preload("res://ui_assets.gd")

signal day_started
signal machine_purchased(machine_id: String)
signal closed

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

const MOSSY_MACHINERY_LINES: Array[String] = [
	"\"Mesin industri & perangkap siap dipasang di outpost-mu, Ranger!\"",
	"\"Metal Crusher & Plastic Burner bikin sampah bernilai berlipat ganda!\"",
	"\"Composter bikin sampah organik jadi pohon rindang di outpost.\"",
	"\"Peralatan berat & perangkap event investasi terbaik buat ranger tangguh!\"",
	"\"Scroll ke bawah atau klik tombol halaman untuk lihat Perangkap & Kompas!\"",
]

const MAX_DAYS: int = 8
const ROW_STEP_Y: float = 474.0

# State
var _player = null
var _dnc: DayNightCycle = null
var _buy_buttons: Array[Button] = []
var _sc_label: Label = null
var _day_label: Label = null
var _dlg_label: Label = null
var _mod_shop_btn: Button = null
var _close_btn: Button = null
var _row_toggle_btn: Button = null
var _scroll: ScrollContainer = null
var _cards_container: Control = null

var _root: Control = null
var _content: Control = null
var _showing_row2: bool = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("machine_buy_menu")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_resolve_references()
	_sync_existing_world_machines()
	_build_ui()
	_rebuild_cards()
	_refresh_header()

	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = false
	UIAssets.sync_bgm()
	UIAssets.play_sfx("open", 0.03)


func _exit_tree() -> void:
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


func _sync_existing_world_machines() -> void:
	if _player == null:
		return
	if not ("owned_machines" in _player):
		_player.set("owned_machines", [])

	var tree = get_tree()
	if not tree:
		return

	for m in MACHINE_CATALOG:
		var mid: String = m.get("id", "")
		var node = tree.get_first_node_in_group(mid)
		if node and is_instance_valid(node):
			if mid not in _player.owned_machines:
				_player.owned_machines.append(mid)


# ===========================================================================
# UI Construction
# ===========================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "MachineShopRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

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

	# 2. Ranger Corkboard (1200 x 562 at y=84)
	var corkboard := UIAssets.create_texture_rect("res://UI/02_shop/ranger_corkboard.png")
	corkboard.position = Vector2(40, 84)
	corkboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(corkboard)

	# 3. Top Header Bar
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

	var title_slab := UIAssets.create_texture_rect("res://UI/02_shop/header_slab_shop_bg.png")
	title_slab.position = Vector2(370, 14)
	title_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(title_slab)

	var title_lbl := UIAssets.create_label(
		"HEAVY MACHINERY WORKSHOP", 20, Color(0.18, 0.13, 0.09), "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_slab.add_child(title_lbl)

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

	# 4. Inset Clipped ScrollContainer STRICTLY INSIDE corkboard wooden bezel!
	# Corkboard interior: x=68..1212 (w=1144), y=108..582 (h=474), leaving y=588..624 for footer strip.
	_scroll = ScrollContainer.new()
	_scroll.name = "CatalogScroll"
	_scroll.position = Vector2(68, 108)
	_scroll.custom_minimum_size = Vector2(1144, 474)
	_scroll.size = Vector2(1144, 474)
	_scroll.clip_contents = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_style_scrollbar(_scroll)
	_content.add_child(_scroll)

	_cards_container = Control.new()
	_cards_container.custom_minimum_size = Vector2(1124, 956)
	_cards_container.size = Vector2(1124, 956)
	_scroll.add_child(_cards_container)

	# 5. Corkboard Footer Bar: Mossy Quote (Left) + Row 1/2 Quick Jump Pill (Right)
	var footer_strip := Control.new()
	footer_strip.position = Vector2(72, 588)
	footer_strip.size = Vector2(1136, 32)
	_content.add_child(footer_strip)

	var dlg_box := HBoxContainer.new()
	dlg_box.position = Vector2(8, 0)
	dlg_box.size = Vector2(820, 32)
	dlg_box.add_theme_constant_override("separation", 8)
	dlg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_strip.add_child(dlg_box)

	var gear_icon := Label.new()
	gear_icon.text = "⚙️"
	gear_icon.add_theme_font_size_override("font_size", 16)
	dlg_box.add_child(gear_icon)

	_dlg_label = UIAssets.create_label(
		"Mossy: \"Mesin industri & perangkap siap dipasang di outpost-mu, Ranger!\"",
		12, Color(1.0, 0.90, 0.58), "bold",
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_CENTER, 0.65
	)
	dlg_box.add_child(_dlg_label)

	# Quick Row Toggle Pill (solid dark wood pill, zero wireframe border)
	_row_toggle_btn = Button.new()
	_row_toggle_btn.text = "▼  Traps & Compass (2/2)"
	_row_toggle_btn.position = Vector2(884, 2)
	_row_toggle_btn.size = Vector2(244, 28)
	_row_toggle_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_row_toggle_btn.add_theme_font_override("font", UIAssets.get_font("bold"))
	_row_toggle_btn.add_theme_font_size_override("font_size", 12)
	_row_toggle_btn.add_theme_color_override("font_color", UIAssets.COL_GOLD)
	_row_toggle_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.18, 0.13, 0.09, 0.94)
	rsb.set_border_width_all(0)
	rsb.set_corner_radius_all(6)
	rsb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	rsb.shadow_size = 4
	rsb.shadow_offset = Vector2(0, 2)
	_row_toggle_btn.add_theme_stylebox_override("normal", rsb)
	var rsb_h: StyleBoxFlat = rsb.duplicate()
	rsb_h.bg_color = Color(0.28, 0.20, 0.13, 0.98)
	_row_toggle_btn.add_theme_stylebox_override("hover", rsb_h)
	_row_toggle_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_row_toggle_btn.pressed.connect(_on_toggle_row_pressed)
	footer_strip.add_child(_row_toggle_btn)

	# 6. Bottom Action Bar
	_mod_shop_btn = UIAssets.create_wood_button(
		"res://UI/02_shop/btn_contract_brown_wood.png",
		"MOD SHOP  [B]",
		14,
		UIAssets.COL_CREAM,
		"",
		"black",
		5
	)
	_mod_shop_btn.custom_minimum_size = Vector2(268, 72)
	_mod_shop_btn.size = Vector2(268, 72)
	_mod_shop_btn.position = Vector2(36, 643)
	_mod_shop_btn.pressed.connect(_on_mod_shop_pressed)
	_content.add_child(_mod_shop_btn)

	var hint_lbl := UIAssets.create_label(
		"Tekan [1-6] pilih mesin/perangkap, lalu [C] untuk pasang di dunia",
		12, Color(0.88, 0.83, 0.74, 0.82), "semibold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.5
	)
	hint_lbl.position = Vector2(314, 666)
	hint_lbl.size = Vector2(624, 24)
	_content.add_child(hint_lbl)

	_close_btn = UIAssets.create_wood_button(
		"res://UI/02_shop/btn_start_blue_wood.png",
		"START DAY  ➔",
		16,
		Color(0.20, 0.12, 0.05),
		"",
		"black",
		5
	)
	_close_btn.position = Vector2(948, 638)
	_close_btn.pressed.connect(_on_close_pressed)
	_content.add_child(_close_btn)


func _style_scrollbar(scroll: ScrollContainer) -> void:
	var vbar := scroll.get_v_scroll_bar()
	if not vbar:
		return
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.14, 0.10, 0.07, 0.65)
	sb_bg.set_corner_radius_all(4)
	sb_bg.content_margin_left = 4
	sb_bg.content_margin_right = 4
	vbar.add_theme_stylebox_override("scroll", sb_bg)

	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = Color(0.82, 0.58, 0.20, 0.88)
	sb_grab.set_corner_radius_all(4)
	vbar.add_theme_stylebox_override("grabber", sb_grab)

	var sb_hov: StyleBoxFlat = sb_grab.duplicate()
	sb_hov.bg_color = Color(0.96, 0.72, 0.28, 1.0)
	vbar.add_theme_stylebox_override("grabber_highlight", sb_hov)
	vbar.add_theme_stylebox_override("grabber_pressed", sb_hov)


func scroll_to_row(row_index: int) -> void:
	if not is_instance_valid(_scroll):
		return
	_showing_row2 = (row_index > 0)
	var target_y := int(ROW_STEP_Y) if _showing_row2 else 0
	_scroll.scroll_vertical = target_y
	if is_instance_valid(_row_toggle_btn):
		_row_toggle_btn.text = "▲  Machines (1/2)" if _showing_row2 else "▼  Traps & Compass (2/2)"


func _on_toggle_row_pressed() -> void:
	_showing_row2 = not _showing_row2
	var target_y := int(ROW_STEP_Y) if _showing_row2 else 0
	if is_instance_valid(_scroll):
		var tw := create_tween()
		tw.tween_property(_scroll, "scroll_vertical", target_y, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_row_toggle_btn):
		_row_toggle_btn.text = "▲  Machines (1/2)" if _showing_row2 else "▼  Traps & Compass (2/2)"


# ===========================================================================
# Card Building (2 Rows x 3 Columns, Properly Positioned BUY Buttons)
# ===========================================================================

func _rebuild_cards() -> void:
	if not is_instance_valid(_cards_container):
		return
	for c in _cards_container.get_children():
		c.queue_free()
	_buy_buttons.clear()

	# 3 cards (230px wide) symmetrically centered inside 1124px scroll canvas (margins 147px, gap 70px)
	var card_x_offsets := [147.0, 447.0, 747.0]

	for i in range(MACHINE_CATALOG.size()):
		var machine: Dictionary = MACHINE_CATALOG[i]
		var col := i % 3
		var row := i / 3
		var card_x: float = card_x_offsets[col]
		var card_y: float = 12.0 + float(row) * ROW_STEP_Y
		_build_card(machine, card_x, card_y)


func _build_card(machine: Dictionary, pos_x: float, pos_y: float = 12.0) -> void:
	var card_w := 230.0
	var card_h := 380.0

	var card_base := Control.new()
	card_base.position = Vector2(pos_x, pos_y)
	card_base.custom_minimum_size = Vector2(card_w, card_h)
	card_base.size = Vector2(card_w, card_h)
	_cards_container.add_child(card_base)

	# 1. Base Opsi 3 Dark Wood Card Texture (230 x 380)
	var card_bg := UIAssets.create_texture_rect("res://UI/03_cards/card_mod_base_empty.png")
	card_bg.position = Vector2.ZERO
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(card_bg)

	# 2. Rarity Tape (Top-Left: 90 x 28 — render crisp rarity text!)
	var rarity_upper: String = str(machine.get("rarity", "COMMON")).to_upper()
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
		"$%d" % int(machine.get("cost", 0)), 14, UIAssets.COL_GOLD, "mono",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	cost_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	price_plate.add_child(cost_lbl)

	# 4. Blueprint Window Art (Fits directly inside card's baked blueprint cutout)
	var art_slot := Control.new()
	art_slot.position = Vector2(22, 46)
	art_slot.size = Vector2(186, 114)
	art_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(art_slot)

	var custom_art := UIAssets.get_card_art(str(machine.get("id", "")))
	if custom_art != null:
		var art_tr := TextureRect.new()
		art_tr.texture = custom_art
		art_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_slot.add_child(art_tr)
	else:
		var icon_map := {
			"crusher": "⚙️",
			"burner": "🔥",
			"composter": "🌱",
			"trap_hostile": "🪤",
			"trap_peaceful": "🌿",
			"compass": "🧭",
		}
		var icon_lbl := Label.new()
		icon_lbl.text = icon_map.get(str(machine.get("icon", "")), "🏭")
		icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 46)
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_slot.add_child(icon_lbl)

	# 5. Machine Name directly on baked dark wood banner
	var name_lbl := UIAssets.create_label(
		str(machine.get("name", "MACHINE")), 13, UIAssets.COL_CREAM, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	name_lbl.position = Vector2(16, 171)
	name_lbl.size = Vector2(198, 30)
	card_base.add_child(name_lbl)

	# 6. Wrapped Description Text cleanly inside cream body
	var desc_lbl := UIAssets.create_wrapped_label(
		str(machine.get("desc", "")),
		Vector2(22, 214),
		Vector2(186, 118),
		11, UIAssets.COL_INK, "semibold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	card_base.add_child(desc_lbl)

	# 7. Native Amber Wood BUY Button positioned relative to THIS card's pos_y!
	var mid: String = str(machine.get("id", ""))
	var owned: bool = _is_machine_owned(mid)
	var can_buy: bool = _player != null and _player.slop_credit >= int(machine.get("cost", 0))

	var owned_txt := "✓ EQUIPPED" if mid == "critter_compass" else "✓ OWNED [C]"
	var btn_txt := owned_txt if owned else ("BUY  $%d" % int(machine.get("cost", 0)))
	var buy_btn := UIAssets.create_wood_button(
		"res://UI/02_shop/btn_buy_amber_wood.png",
		btn_txt,
		15,
		Color(0.20, 0.12, 0.05) if not owned else Color(0.14, 0.42, 0.20),
		"",
		"black",
		4
	)
	buy_btn.position = Vector2(pos_x + 4.0, pos_y + 382.0)
	buy_btn.disabled = owned or (not can_buy)
	buy_btn.set_meta("suppress_default_click_sfx", true)
	if not owned and can_buy:
		buy_btn.pressed.connect(_on_buy_machine_pressed.bind(machine))

	_cards_container.add_child(buy_btn)
	_buy_buttons.append(buy_btn)


# ===========================================================================
# Purchasing & Machine Deployment (100% Preserved from 3e26359)
# ===========================================================================

func _is_machine_owned(mid: String) -> bool:
	if _player and "owned_machines" in _player:
		return mid in _player.owned_machines
	return false


func _on_buy_machine_pressed(machine: Dictionary) -> void:
	if _player == null:
		return

	var mid: String = machine.get("id", "")
	var cost: int = int(machine.get("cost", 0))

	if _player.slop_credit < cost:
		UIAssets.play_sfx("error", 0.02)
		return

	UIAssets.play_sfx("buy", 0.05)
	_player.slop_credit -= cost
	if _player.has_signal("slop_credit_changed"):
		_player.slop_credit_changed.emit(_player.slop_credit, -float(cost))
	if NetworkManager != null:
		NetworkManager.broadcast_team_sc(-float(cost))

	if mid == "critter_compass":
		if "has_compass" in _player:
			_player.has_compass = true
	if not ("owned_machines" in _player):
		_player.set("owned_machines", [])
	if mid not in _player.owned_machines:
		_player.owned_machines.append(mid)
	if NetworkManager != null:
		NetworkManager.broadcast_unlock_machine(mid)

	if mid != "critter_compass" and _player.has_method("select_machine_by_id"):
		_player.select_machine_by_id(mid)
	if _player.has_method("_update_hud"):
		_player._update_hud()

	if _player.has_method("_show_feedback"):
		if mid == "critter_compass":
			_player._show_feedback("🧭 %s Equipped! Event targets will now be tracked!" % machine.get("name", "Compass"))
		else:
			_player._show_feedback("⚙️ %s Purchased! Press [1-5] to select, [C] to build!" % machine.get("name", "Machine"))

	machine_purchased.emit(mid)
	_refresh_header()
	_rebuild_cards()
	if is_instance_valid(_dlg_label):
		if mid == "critter_compass":
			_dlg_label.text = "Mossy: \"Tracker Compass aktif! Arah mob event langsung muncul di HUD atas!\""
		else:
			_dlg_label.text = "Mossy: \"%s siap dipakai! Tekan [1-5] lalu [C] di dunia!\"" % str(machine.get("name", "Alat"))


func _deploy_machine(machine: Dictionary) -> void:
	if not is_inside_tree():
		return

	var mid: String = machine.get("id", "")
	var scene_path: String = machine.get("scene_path", "")

	var tree = get_tree()
	if not tree:
		return

	var existing = tree.get_first_node_in_group(mid)
	if existing and is_instance_valid(existing):
		existing.visible = true
		if "process_mode" in existing:
			existing.process_mode = Node.PROCESS_MODE_INHERIT
		return

	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return

	var packed := load(scene_path) as PackedScene
	if not packed:
		return

	var instance = packed.instantiate()
	if not instance is Node3D:
		instance.queue_free()
		return

	var world_root = tree.current_scene if tree.current_scene else tree.root
	var spawn_pos := Vector3.ZERO

	if machine.has("spawn_offset"):
		spawn_pos = machine["spawn_offset"]
	elif _player and _player is Node3D:
		spawn_pos = _player.global_position - _player.global_transform.basis.z * 4.0
		spawn_pos.y = _player.global_position.y

	world_root.add_child(instance)
	instance.global_position = spawn_pos


# ===========================================================================
# Navigation & Header
# ===========================================================================

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
			day_idx = clampi(_dnc.current_day - 1, 0, MOSSY_MACHINERY_LINES.size() - 1)
		_dlg_label.text = "Mossy: " + MOSSY_MACHINERY_LINES[day_idx]

	if is_instance_valid(_close_btn):
		if _dnc != null and _dnc.is_waiting_for_day_start:
			_close_btn.text = "START DAY  ➔"
		elif _dnc != null and _dnc.is_night:
			_close_btn.text = "CLOSE SHOP  ➔"
		else:
			_close_btn.text = "RESUME SHIFT  ➔"


func _on_mod_shop_pressed() -> void:
	if _player and _player.has_method("toggle_buy_menu"):
		_player.toggle_buy_menu()
	if not is_queued_for_deletion():
		queue_free()


func _on_close_pressed() -> void:
	if _dnc != null:
		_dnc.is_waiting_for_day_start = false
	day_started.emit()
	closed.emit()
	if _player and _player.has_method("capture_mouse"):
		_player.capture_mouse()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()
