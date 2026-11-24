# quota_menu.gd
# Quota / Contract selection screen presented before each day starts.
# Uses raw HD UI textures in res://UI/02_shop/ and res://UI/03_cards/

class_name QuotaMenu extends CanvasLayer

const UIAssets = preload("res://ui_assets.gd")

signal day_started(contract_data: Dictionary)
signal contract_selected(contract_data: Dictionary)

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
const C_AMBER          := Color(0.88, 0.62, 0.12, 1.0)
const C_WHITE          := Color(1.0, 1.0, 1.0, 1.0)

const REROLL_COST: int = 2
const MAX_DAYS: int = 8

# ---------------------------------------------------------------------------
# Predefined Quota/Quest templates
# ---------------------------------------------------------------------------
const BOSS_MODIFIERS: Array[Dictionary] = [
	{
		"title": "Inspection Day",
		"desc": "Inspektur Mossy memeriksa! Kuota ketat sebelum senja tiba.",
		"quota_mult": 2.2,
		"serial": "SCRAP-ID // 08-PIGGY",
		"icon": "boss"
	},
	{
		"title": "Toxic Inspection",
		"desc": "Sampah berbahaya terdeteksi! Kuota x2.0, fokus amankan danau.",
		"quota_mult": 2.0,
		"serial": "SCRAP-ID // 09-TOXIC",
		"icon": "toxic"
	},
	{
		"title": "Scrap Rush Day",
		"desc": "Hari sibuk outpost! Selesaikan kuota berat untuk bonus patroli.",
		"quota_mult": 1.8,
		"serial": "SCRAP-ID // 10-RUSH",
		"icon": "rush"
	}
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _player = null
var _dnc: DayNightCycle = null

var _cards_data: Array[Dictionary] = []
var _selected_index: int = 0
var _card_nodes: Array[Control] = []
var _card_selection_glows: Array[ReferenceRect] = []
var _skip_buttons: Array[Button] = []
var _boss_btn: Button = null

var _sc_label: Label = null
var _day_label: Label = null
var _dlg_label: Label = null
var _root: Control = null
var _cards_hbox: HBoxContainer = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	_resolve_references()
	_init_cards_data()
	_build_ui()
	_refresh_header()
	_update_card_selection_visuals()

	# Hide GameHUD while quota menu is open
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


# ---------------------------------------------------------------------------
# Data Initialization
# ---------------------------------------------------------------------------

func _init_cards_data() -> void:
	var base_q: float = 15.0
	if _dnc != null and _dnc.has_method("get_current_quota"):
		base_q = _dnc.get_current_quota()

	_cards_data.clear()

	# Card 1: Low quota (Standard / Easy)
	_cards_data.append({
		"title": "Low quota",
		"rarity": "COMMON",
		"cost_badge": "$4",
		"upper_text": "Multiplier bonus naik +0.15 per sampah yang disortir benar.",
		"lower_text": "Dapatkan +15p SlopCredit",
		"serial": "SCRAP-ID // 01-VEST",
		"quota_target": maxf(10.0, base_q * 0.8),
		"skip_reward": 15.0,
		"is_boss": false,
		"is_skipped": false,
		"icon": "quota_low"
	})

	# Card 2: Low quota / Balanced quota
	_cards_data.append({
		"title": "Low quota",
		"rarity": "COMMON",
		"cost_badge": "$4",
		"upper_text": "Multiplier bonus naik +0.15 per sampah yang disortir benar.",
		"lower_text": "Dapatkan +15p SlopCredit",
		"serial": "SCRAP-ID // 02-CRUSH",
		"quota_target": base_q,
		"skip_reward": 15.0,
		"is_boss": false,
		"is_skipped": false,
		"icon": "quota_mid"
	})

	# Card 3: Inspection Day (Boss quota - cannot skip, can reroll)
	var boss_template: Dictionary = BOSS_MODIFIERS[0]
	_cards_data.append({
		"title": boss_template["title"],
		"rarity": "COMMON",
		"cost_badge": "$4",
		"upper_text": boss_template["desc"],
		"lower_text": "Target Kuota: %.0f KG" % (base_q * float(boss_template["quota_mult"])),
		"serial": boss_template["serial"],
		"quota_target": base_q * float(boss_template["quota_mult"]),
		"skip_reward": 0.0,
		"is_boss": true,
		"is_skipped": false,
		"icon": "boss",
		"boss_idx": 0
	})


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var font: Font = ThemeDB.fallback_font

	_root = Control.new()
	_root.name = "QuotaRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

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
	_root.add_child(content)

	# Full-screen HD Backdrop & Workbench Background (1280 x 720)
	var bg_tex := UIAssets.create_texture_rect("res://UI/02_shop/shop_bg_full.png")
	bg_tex.position = Vector2.ZERO
	bg_tex.size = Vector2(1280, 720)
	content.add_child(bg_tex)

	# --- TOP HEADER BAR ----------------------------------------------------
	# Funds Plate (Left: 186 x 52)
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

	# Outpost Title Plate (Center: 586 x 52)
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

	# Day Plate (Right: 186 x 52)
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
	_dlg_label.text = "🐸 Mossy: \"Pilih target kuota sebelum senja tiba, Ranger!\""
	_dlg_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dlg_label.offset_left = 20
	_dlg_label.offset_right = -20
	_dlg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dlg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dlg_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
	_dlg_label.add_theme_font_size_override("font_size", 15)
	dlg_bg.add_child(_dlg_label)

	# --- MAIN CARDS CONTAINER (OVER WORKBENCH) -----------------------------
	_cards_hbox = HBoxContainer.new()
	_cards_hbox.position = Vector2(252, 128)
	_cards_hbox.custom_minimum_size = Vector2(775, 490)
	_cards_hbox.size = Vector2(775, 490)
	_cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_hbox.add_theme_constant_override("separation", 32)
	content.add_child(_cards_hbox)

	_render_cards()

	# --- BOTTOM BAR --------------------------------------------------------
	# Shop Shortcut Button (Left: 246 x 58)
	var shop_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_reroll_bg.png",
		"🛍️ MOD SHOP [B]",
		15,
		Color.WHITE
	)
	shop_btn.position = Vector2(32, 646)
	shop_btn.custom_minimum_size = Vector2(246, 58)
	shop_btn.size = Vector2(246, 58)
	shop_btn.pressed.connect(_on_shop_pressed)
	content.add_child(shop_btn)

	# Machine Shop Shortcut Button (Center-Left: 246 x 58)
	var mach_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_reroll_bg.png",
		"⚙️ MACHINES [M]",
		15,
		Color.WHITE
	)
	mach_btn.position = Vector2(298, 646)
	mach_btn.custom_minimum_size = Vector2(246, 58)
	mach_btn.size = Vector2(246, 58)
	mach_btn.pressed.connect(_on_mach_pressed)
	content.add_child(mach_btn)

	# START DAY Button (Right: 246 x 58)
	var start_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_start_day_bg.png",
		"START DAY →",
		17,
		Color.WHITE
	)
	start_btn.position = Vector2(1002, 646)
	start_btn.custom_minimum_size = Vector2(246, 58)
	start_btn.size = Vector2(246, 58)
	start_btn.pressed.connect(_on_start_day_pressed)
	content.add_child(start_btn)


# ---------------------------------------------------------------------------
# Card Construction
# ---------------------------------------------------------------------------

func _render_cards() -> void:
	if not is_instance_valid(_cards_hbox):
		return
	for child in _cards_hbox.get_children():
		child.queue_free()

	_card_nodes.clear()
	_card_selection_glows.clear()
	_skip_buttons.clear()
	_boss_btn = null

	for i in range(_cards_data.size()):
		var data: Dictionary = _cards_data[i]
		var card := _build_single_card(i, data)
		_cards_hbox.add_child(card)


func _build_single_card(card_idx: int, data: Dictionary) -> Control:
	var card_column := Control.new()
	card_column.custom_minimum_size = Vector2(237, 470)
	card_column.size = Vector2(237, 470)
	card_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_card_nodes.append(card_column)

	# Card base container (237 x 382)
	var card_base := Control.new()
	card_base.position = Vector2(0, 0)
	card_base.custom_minimum_size = Vector2(237, 382)
	card_base.size = Vector2(237, 382)
	card_column.add_child(card_base)

	# 1. Base HD Card Texture (237 x 382)
	var card_bg := UIAssets.create_texture_rect("res://UI/03_cards/card_blind_base_empty.png")
	card_bg.position = Vector2.ZERO
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(card_bg)

	# Selection Glow Frame
	var glow := ReferenceRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.border_color = Color(0.96, 0.74, 0.18, 1.0)
	glow.border_width = 4.0
	glow.editor_only = false
	glow.visible = (card_idx == _selected_index)
	card_base.add_child(glow)
	_card_selection_glows.append(glow)

	# Click overlay to select card
	var click_btn := Button.new()
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.flat = true
	click_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	click_btn.pressed.connect(_on_card_clicked.bind(card_idx))
	card_base.add_child(click_btn)

	# 2. Rarity Tape (Top-Left: 96 x 42) — Text is baked on texture
	var rarity_str: String = str(data.get("rarity", "COMMON")).to_lower()
	var tape_path := "res://UI/03_cards/tape_rarity_%s.png" % rarity_str
	var tape_tex := UIAssets.create_texture_rect(tape_path)
	tape_tex.position = Vector2(4, 2)
	tape_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(tape_tex)

	# 3. Gold Stamp Badge (Top-Right: 51 x 51)
	var stamp_tex := UIAssets.create_texture_rect("res://UI/03_cards/card_stamp_gold_empty.png")
	stamp_tex.position = Vector2(178, 2)
	stamp_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_base.add_child(stamp_tex)

	var badge_lbl := Label.new()
	badge_lbl.text = str(data.get("cost_badge", "$4"))
	badge_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_color_override("font_color", Color(0.14, 0.10, 0.05))
	badge_lbl.add_theme_font_size_override("font_size", 14)
	stamp_tex.add_child(badge_lbl)

	# 4. Blueprint Art Area Icon (x: 25, y: 50, w: 186, h: 122)
	var icon_lbl := Label.new()
	var icon_hint := str(data.get("icon", ""))
	var icon_char := "📋"
	match icon_hint:
		"quota_low":
			icon_char = "⚖️"
		"quota_mid":
			icon_char = "📋"
		"boss":
			icon_char = "🔍"
		"toxic":
			icon_char = "☣️"
		"rush":
			icon_char = "🚀"
	icon_lbl.text = icon_char
	icon_lbl.position = Vector2(25, 60)
	icon_lbl.size = Vector2(186, 100)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 42)
	card_base.add_child(icon_lbl)

	# 5. Title Banner (y: 182..214)
	var title_lbl := Label.new()
	title_lbl.text = str(data.get("title", "Low quota"))
	title_lbl.position = Vector2(18, 184)
	title_lbl.size = Vector2(201, 30)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.88))
	title_lbl.add_theme_font_size_override("font_size", 15)
	card_base.add_child(title_lbl)

	# 6. Upper White Box: Modifier / Condition (y: 224..276)
	var up_box := MarginContainer.new()
	up_box.position = Vector2(24, 224)
	up_box.custom_minimum_size = Vector2(189, 52)
	up_box.size = Vector2(189, 52)

	var up_lbl := Label.new()
	up_lbl.text = str(data.get("upper_text", ""))
	up_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	up_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	up_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	up_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	up_lbl.add_theme_color_override("font_color", Color(0.14, 0.14, 0.16))
	up_lbl.add_theme_font_size_override("font_size", 11)
	up_box.add_child(up_lbl)
	card_base.add_child(up_box)

	# 7. OR Divider text (y: 278..290)
	var or_lbl := Label.new()
	or_lbl.text = "OR"
	or_lbl.position = Vector2(20, 276)
	or_lbl.size = Vector2(197, 16)
	or_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_lbl.add_theme_color_override("font_color", Color(0.35, 0.28, 0.20))
	or_lbl.add_theme_font_size_override("font_size", 10)
	card_base.add_child(or_lbl)

	# 8. Lower White Box: Skip / Bonus payout (y: 294..366)
	var low_box := MarginContainer.new()
	low_box.position = Vector2(24, 294)
	low_box.custom_minimum_size = Vector2(189, 72)
	low_box.size = Vector2(189, 72)

	var low_lbl := Label.new()
	low_lbl.text = str(data.get("lower_text", "Dapatkan +15p SlopCredit"))
	low_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	low_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	low_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	low_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	low_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	low_lbl.add_theme_color_override("font_color", Color(0.14, 0.14, 0.16))
	low_lbl.add_theme_font_size_override("font_size", 11)
	low_box.add_child(low_lbl)
	card_base.add_child(low_box)

	# 9. Action Button (Positioned directly under card base at y: 396)
	var is_boss: bool = bool(data.get("is_boss", false))
	var is_skipped: bool = bool(data.get("is_skipped", false))

	if not is_boss:
		var skip_btn := UIAssets.create_textured_button(
			"res://UI/02_shop/btn_yellow_bg.png",
			"SKIPPED" if is_skipped else "Skip",
			15,
			Color(0.14, 0.10, 0.05)
		)
		skip_btn.position = Vector2(30.5, 396)
		skip_btn.custom_minimum_size = Vector2(176, 42)
		skip_btn.size = Vector2(176, 42)
		skip_btn.disabled = is_skipped
		if is_skipped:
			skip_btn.modulate = Color(0.5, 0.5, 0.5, 0.8)
		else:
			skip_btn.pressed.connect(_on_skip_pressed.bind(card_idx))
		card_column.add_child(skip_btn)
		_skip_buttons.append(skip_btn)
	else:
		_boss_btn = UIAssets.create_textured_button(
			"res://UI/02_shop/btn_reroll_bg.png",
			"🎲 REROLL ($%d)" % REROLL_COST,
			14,
			Color.WHITE
		)
		_boss_btn.position = Vector2(-4.5, 388)
		_boss_btn.custom_minimum_size = Vector2(246, 58)
		_boss_btn.size = Vector2(246, 58)
		var can_afford: bool = _player != null and _player.slop_credit >= REROLL_COST
		_boss_btn.disabled = not can_afford
		_boss_btn.pressed.connect(_on_boss_reroll_pressed)
		card_column.add_child(_boss_btn)

	return card_column


# ---------------------------------------------------------------------------
# Visual Selection State
# ---------------------------------------------------------------------------

func _update_card_selection_visuals() -> void:
	for i in range(_card_selection_glows.size()):
		var glow: ReferenceRect = _card_selection_glows[i]
		if not is_instance_valid(glow):
			continue
		var is_sel: bool = (i == _selected_index)
		glow.visible = is_sel


func _refresh_header() -> void:
	if _sc_label and _player:
		_sc_label.text = "$%.0f" % _player.slop_credit
	elif _sc_label:
		_sc_label.text = "$0"

	var cur_d: int = 1
	if _dnc:
		cur_d = _dnc.current_day
	if _day_label:
		_day_label.text = "DAY %d / %d" % [cur_d, MAX_DAYS]

	if _boss_btn:
		var can_reroll: bool = _player != null and _player.slop_credit >= REROLL_COST
		_boss_btn.disabled = not can_reroll
		_boss_btn.modulate = Color.WHITE if can_reroll else Color(0.5, 0.5, 0.5, 0.75)


# ---------------------------------------------------------------------------
# Interactions & Callbacks
# ---------------------------------------------------------------------------

func _on_card_clicked(idx: int) -> void:
	if idx < 0 or idx >= _cards_data.size():
		return
	if bool(_cards_data[idx].get("is_skipped", false)):
		return

	_selected_index = idx
	_update_card_selection_visuals()
	contract_selected.emit(_cards_data[idx])


func _on_skip_pressed(idx: int) -> void:
	if idx < 0 or idx >= _cards_data.size():
		return
	var data: Dictionary = _cards_data[idx]
	if bool(data.get("is_skipped", false)):
		return

	var reward: float = float(data.get("skip_reward", 15.0))
	if _player != null:
		_player.slop_credit += reward
		if _player.has_signal("slop_credit_changed"):
			_player.slop_credit_changed.emit(_player.slop_credit, reward)
		if _player.has_method("_show_feedback"):
			_player._show_feedback("💰 +%.0f SC (Quota Skipped!)" % reward)

	data["is_skipped"] = true
	_cards_data[idx] = data

	_refresh_header()
	_render_cards()
	_update_card_selection_visuals()


func _on_boss_reroll_pressed() -> void:
	if _player == null:
		return
	if _player.slop_credit < REROLL_COST:
		return

	_player.slop_credit -= REROLL_COST
	if _player.has_signal("slop_credit_changed"):
		_player.slop_credit_changed.emit(_player.slop_credit, -float(REROLL_COST))

	var cur_idx: int = int(_cards_data[2].get("boss_idx", 0))
	var next_idx: int = (cur_idx + 1) % BOSS_MODIFIERS.size()
	var b_data: Dictionary = BOSS_MODIFIERS[next_idx]

	var base_q: float = 15.0
	if _dnc:
		base_q = _dnc.get_current_quota()

	_cards_data[2]["title"] = b_data["title"]
	_cards_data[2]["upper_text"] = b_data["desc"]
	_cards_data[2]["serial"] = b_data["serial"]
	_cards_data[2]["quota_target"] = base_q * float(b_data["quota_mult"])
	_cards_data[2]["lower_text"] = "Target Kuota: %.0f KG" % (base_q * float(b_data["quota_mult"]))
	_cards_data[2]["icon"] = b_data["icon"]
	_cards_data[2]["boss_idx"] = next_idx

	_refresh_header()
	_render_cards()
	_update_card_selection_visuals()


func _on_shop_pressed() -> void:
	if _player and _player.has_method("toggle_buy_menu"):
		_player.toggle_buy_menu()
		queue_free()


func _on_mach_pressed() -> void:
	if _player and _player.has_method("toggle_machine_menu"):
		_player.toggle_machine_menu()
		queue_free()


func _on_start_day_pressed() -> void:
	var chosen: Dictionary = _cards_data[_selected_index]
	var is_skip: bool = bool(chosen.get("is_skipped", false))

	if _dnc != null:
		if is_skip:
			_dnc.custom_day_quota = 0.0
		else:
			_dnc.custom_day_quota = float(chosen.get("quota_target", 15.0))

		if "is_waiting_for_day_start" in _dnc:
			_dnc.is_waiting_for_day_start = false

	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud and hud.has_method("update_quota"):
		var target: float = 0.0 if is_skip else float(chosen.get("quota_target", 15.0))
		hud.update_quota(0.0, target, "KG")

	if _player and _player.has_method("_show_feedback"):
		if is_skip:
			_player._show_feedback("☀️ Day Started! Quota was skipped.")
		else:
			_player._show_feedback("📋 Contract: %s (Target: %.0f KG)" % [chosen.get("title", "Quota"), chosen.get("quota_target", 15.0)])

	day_started.emit(chosen)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()
