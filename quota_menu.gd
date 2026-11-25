# quota_menu.gd
# Contract Board / Quota selection screen presented before each day starts.
# Accurately reproduces Mockup 2 (Inspection Day Boss Event) and Mockup 3 (Standard Contract Board)
# using raw HD UI textures in res://UI/02_shop/ and res://UI/03_cards/

class_name QuotaMenu
extends CanvasLayer

signal day_started(contract_data: Dictionary)
signal contract_selected(contract_data: Dictionary)

const UIAssets = preload("res://ui_assets.gd")

const MAX_DAYS: int = 8

# Colors
const COL_WHITE        := Color(1.0, 1.0, 1.0, 1.0)
const COL_DARK_TEXT    := Color(0.18, 0.14, 0.12, 1.0)
const COL_AMBER        := Color(0.96, 0.65, 0.15, 1.0)
const COL_RED          := Color(0.85, 0.22, 0.18, 1.0)
const COL_BLUE         := Color(0.18, 0.58, 0.92, 1.0)
const COL_GREEN        := Color(0.20, 0.68, 0.35, 1.0)
const COL_MUTED        := Color(0.48, 0.44, 0.40, 1.0)

# State
var _player = null
var _dnc: DayNightCycle = null

var is_boss_day: bool = false
var active_event_data: Dictionary = {}
var _selected_index: int = 1 # Standard contract selected by default
var _contracts_data: Array[Dictionary] = []
var _contract_nodes: Array[Control] = []
var _selection_glows: Array[ReferenceRect] = []
var _pilih_buttons: Array[Button] = []

# Top bar widgets
var _day_label: Label = null
var _boss_tag_label: Label = null
var _funds_label: Label = null

# Bottom bar widgets
var _dialogue_label: Label = null
var _start_shift_btn: Button = null

var _root: Control = null
var _content: Control = null
var _papers_container: Control = null


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_resolve_references()
	_determine_day_type()
	_init_contracts_data()
	_build_ui()
	_refresh_top_bar()
	_update_contract_selection_visuals()

	# Hide HUD while contract board is open
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = false

	if NetworkManager.is_multiplayer_active():
		if not NetworkManager.quota_votes_updated.is_connected(_refresh_vote_ui):
			NetworkManager.quota_votes_updated.connect(_refresh_vote_ui)
		if not NetworkManager.quota_vote_finalized.is_connected(_on_coop_vote_finalized):
			NetworkManager.quota_vote_finalized.connect(_on_coop_vote_finalized)
		if NetworkManager.is_host():
			NetworkManager.reset_quota_votes()
		NetworkManager.submit_quota_vote(_selected_index)
		_refresh_vote_ui()


func _exit_tree() -> void:
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = true


func _resolve_references() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _dnc == null:
		_dnc = get_tree().get_first_node_in_group("day_night_cycle")


func _determine_day_type() -> void:
	var day := 1
	if _dnc != null:
		day = _dnc.current_day

	active_event_data = {}
	var es: Node = null
	if _dnc and "event_system" in _dnc and _dnc.event_system:
		es = _dnc.event_system
	else:
		es = get_tree().get_first_node_in_group("event_system")

	if es and es.is_event_day(day):
		is_boss_day = true
		active_event_data = es.get_event_data_for_day(day)
	else:
		# Fallback if no EventSystem present
		is_boss_day = (day % 4 == 0)
		if is_boss_day:
			active_event_data = {
				"id": "inspection_day",
				"tag": "INSPECTION DAY",
				"subtag": "BOSS EVENT · DAY %d\n! WAJIB / TIDAK BISA SKIP" % day,
				"title": "EVENT: SURPRISE AUDIT",
				"desc": "Semua jenis sampah (Haul) — Sidak Kebersihan",
				"rule_warning": "▲ ATURAN BOSS: SALAH TONG = -20 KG KUOTA!\nSetiap salah sortir mereset Streak & memotong progres kg.",
				"payout": 18,
				"reward": "★ 1× Summit Stamp (+0.05 Mult)",
				"icon": "res://UI/03_cards/icon_contract_audit.png",
				"quota_target": 480.0,
				"target_unit": "KG",
				"dialogue": "The Inspector: \"Hari ini event wajib! Penuhi kuota audit atau Taman Nasional resmi ditutup!\""
			}


func _init_contracts_data() -> void:
	var current_day := 1
	var base_q: float = 15.0
	if _dnc != null:
		current_day = _dnc.current_day
		base_q = _dnc.get_current_quota()

	_contracts_data.clear()

	if is_boss_day:
		var event_id: String = active_event_data.get("id", "inspection_day")
		var event_tag: String = active_event_data.get("tag", "INSPECTION DAY")
		var event_subtag: String = active_event_data.get("subtag", "BOSS EVENT · DAY %d\n! WAJIB / TIDAK BISA SKIP" % current_day)
		var event_title: String = active_event_data.get("title", "EVENT: SURPRISE AUDIT")
		var event_desc: String = active_event_data.get("desc", "Semua jenis sampah (Haul) — Sidak Kebersihan")
		var rule_warn: String = active_event_data.get("rule_warning", "▲ ATURAN BOSS: SALAH TONG = -20 KG KUOTA!")
		var payout_amt: int = active_event_data.get("payout", 20)
		var reward_str: String = active_event_data.get("reward", "★ 1× Summit Stamp (+0.05 Mult)")
		var icon_p: String = active_event_data.get("icon", "res://UI/03_cards/icon_contract_audit.png")
		var quota_tgt: float = active_event_data.get("quota_target", maxf(480.0, base_q * 2.8))
		var t_unit: String = active_event_data.get("target_unit", "KG")

		_contracts_data.append({
			"id": event_id,
			"type": "BOSS",
			"tag": event_tag,
			"subtag": event_subtag,
			"quota_target": quota_tgt,
			"target_unit": t_unit,
			"time_str": "02:30",
			"icon": icon_p,
			"title": event_title,
			"desc": event_desc,
			"rule_warning": rule_warn,
			"payout": payout_amt,
			"boss_reward": reward_str,
			"bg_tex": "res://UI/03_cards/contract_torn_boss_red_empty.png",
			"btn_tex": "res://UI/02_shop/btn_contract_boss_red_wood.png",
			"btn_text": "✓ KONTRAK %s WAJIB" % event_tag,
			"dialogue": active_event_data.get("dialogue", ""),
			"is_boss": true
		})
		_selected_index = 0
	else:
		# Standard 3-Contract Board (Mockup 3)
		# 1. Easy / Low Quota
		var easy_q := maxf(15.0, roundf(base_q * 0.8))
		_contracts_data.append({
			"type": "EASY",
			"tag": "LOW QUOTA",
			"subtag": "EASY ×0.8",
			"quota_target": easy_q,
			"time_str": "02:30",
			"icon": "res://UI/03_cards/icon_contract_haul.png",
			"title": "MISI: HAUL",
			"desc": "Semua jenis sampah",
			"condition_title": "CUACA",
			"condition_desc": "Cerah (aman)",
			"payout": 5,
			"stamp_reward": "1× Trailhead",
			"bg_tex": "res://UI/03_cards/contract_torn_easy_empty.png",
			"tag_color": COL_GREEN,
			"is_boss": false
		})

		# 2. Standard / Tin Tally (Selected by default)
		var std_q := maxf(20.0, roundf(base_q * 1.0))
		_contracts_data.append({
			"type": "STANDARD",
			"tag": "STANDARD",
			"subtag": "NORMAL ×1.0\n✓ DIPILIH",
			"quota_target": std_q,
			"time_str": "02:30",
			"icon": "res://UI/03_cards/icon_contract_metal.png",
			"title": "MISI: TIN TALLY",
			"desc": "Khusus sampah logam",
			"condition_title": "MEDAN",
			"condition_desc": "Normal",
			"payout": 8,
			"stamp_reward": "1× Tin Stamp",
			"bg_tex": "res://UI/03_cards/contract_torn_standard_empty.png",
			"tag_color": COL_BLUE,
			"is_boss": false
		})

		# 3. High Quota / Compost Run
		var hard_q := maxf(30.0, roundf(base_q * 1.4))
		_contracts_data.append({
			"type": "HARD",
			"tag": "HIGH QUOTA",
			"subtag": "HARD ×1.4",
			"quota_target": hard_q,
			"time_str": "02:30",
			"icon": "res://UI/03_cards/icon_contract_organic.png",
			"title": "MISI: COMPOST RUN",
			"desc": "Khusus sampah organik",
			"condition_warning": "▲ ANGIN KENCANG (+$2)\nSampah ringan mudah terbang",
			"payout": 14,
			"stamp_reward": "2× Compost",
			"bg_tex": "res://UI/03_cards/contract_torn_hard_empty.png",
			"tag_color": COL_RED,
			"is_boss": false
		})
		_selected_index = 1


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ContractBoardRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 1280 x 720 Centered Content Canvas
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

	# 1. Fullscreen Wall Background
	var wall_path := "res://UI/02_shop/bg_boss_wall.png" if is_boss_day else "res://UI/02_shop/bg_dawn_wall.png"
	var wall_bg := UIAssets.create_texture_rect(wall_path)
	wall_bg.position = Vector2.ZERO
	wall_bg.size = Vector2(1280, 720)
	_content.add_child(wall_bg)

	# 2. Ranger Corkboard (1200 x 562)
	var corkboard := UIAssets.create_texture_rect("res://UI/02_shop/ranger_corkboard.png")
	corkboard.position = Vector2(40, 76)
	corkboard.size = Vector2(1200, 562)
	_content.add_child(corkboard)

	# 3. Top Header Bar
	_build_top_header()

	# 4. Corkboard Papers (Either 1 Boss Paper or 3 Standard Papers)
	_papers_container = Control.new()
	_papers_container.name = "PapersContainer"
	_papers_container.position = Vector2(40, 76)
	_papers_container.size = Vector2(1200, 562)
	_content.add_child(_papers_container)

	if is_boss_day:
		_build_boss_paper()
	else:
		_build_standard_papers()

	# 5. Bottom Dialogue Strip & Start Shift Button
	_build_bottom_bar()


# ===========================================================================
# Top Header Bar
# ===========================================================================
func _build_top_header() -> void:
	# 1. Left Plate: DAY 0X / 08 (216 x 48)
	var day_plate := UIAssets.create_texture_rect("res://UI/02_shop/plate_day_bg.png")
	day_plate.position = Vector2(48, 16)
	day_plate.size = Vector2(216, 48)
	_content.add_child(day_plate)

	_day_label = Label.new()
	_day_label.text = "DAY 01 / 08"
	_day_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_size_override("font_size", 16)
	_day_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	day_plate.add_child(_day_label)

	# 2. Center Slab Header (440 x 58)
	var header_slab_tex := "res://UI/02_shop/header_slab_boss_bg.png" if is_boss_day else "res://UI/02_shop/header_slab_contract_bg.png"
	var header_slab := UIAssets.create_texture_rect(header_slab_tex)
	header_slab.position = Vector2(420, 14)
	header_slab.size = Vector2(440, 58)
	_content.add_child(header_slab)

	var header_title := Label.new()
	var tag_title: String = active_event_data.get("tag", "INSPECTION DAY") if is_boss_day else "CONTRACT BOARD"
	header_title.text = tag_title
	header_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_title.add_theme_font_size_override("font_size", 18)
	header_title.add_theme_color_override("font_color", Color(0.96, 0.95, 0.90) if is_boss_day else Color(0.20, 0.16, 0.12))
	header_slab.add_child(header_title)

	# 3. Right Plate: Split Boss / Funds plate (284 x 48)
	var split_plate := UIAssets.create_texture_rect("res://UI/02_shop/plate_boss_cash_split_bg.png")
	split_plate.position = Vector2(948, 16)
	split_plate.size = Vector2(284, 48)
	_content.add_child(split_plate)

	_boss_tag_label = Label.new()
	_boss_tag_label.position = Vector2(10, 0)
	_boss_tag_label.size = Vector2(160, 48)
	_boss_tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var is_challenge := false
	if _dnc != null and "event_system" in _dnc and _dnc.event_system and "current_game_mode" in _dnc.event_system:
		is_challenge = (_dnc.event_system.current_game_mode == 1)
	if is_challenge:
		_boss_tag_label.text = "🔥 CHALLENGE"
		_boss_tag_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.30))
	else:
		_boss_tag_label.text = ("▲ %s" % active_event_data.get("tag", "EVENT")) if is_boss_day else "▲ BOSS: DAY 8"
		_boss_tag_label.add_theme_color_override("font_color", Color(0.96, 0.40, 0.35) if is_boss_day else Color(0.96, 0.65, 0.20))
	_boss_tag_label.add_theme_font_size_override("font_size", 12)
	split_plate.add_child(_boss_tag_label)

	_funds_label = Label.new()
	_funds_label.position = Vector2(180, 0)
	_funds_label.size = Vector2(94, 48)
	_funds_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_funds_label.text = "$14"
	_funds_label.add_theme_font_size_override("font_size", 16)
	_funds_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.25))
	split_plate.add_child(_funds_label)


# ===========================================================================
# Standard 3 Contracts (Mockup 3)
# ===========================================================================
func _build_standard_papers() -> void:
	_contract_nodes.clear()
	_selection_glows.clear()
	_pilih_buttons.clear()

	var positions := [Vector2(45, 24), Vector2(415, 14), Vector2(805, 24)]
	var sizes := [Vector2(365, 498), Vector2(390, 518), Vector2(365, 512)]

	for i in range(_contracts_data.size()):
		var data: Dictionary = _contracts_data[i]
		var paper_pos: Vector2 = positions[i]
		var paper_size: Vector2 = sizes[i]

		var card := Control.new()
		card.position = paper_pos
		card.custom_minimum_size = paper_size
		card.size = paper_size
		_papers_container.add_child(card)
		_contract_nodes.append(card)

		# Paper Texture
		var bg_tex := UIAssets.create_texture_rect(data["bg_tex"])
		bg_tex.position = Vector2.ZERO
		bg_tex.size = paper_size
		card.add_child(bg_tex)

		# Selection border highlight around the middle / selected contract
		var glow := ReferenceRect.new()
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.border_color = Color(0.20, 0.65, 0.98, 1.0)
		glow.border_width = 3.0
		glow.editor_only = false
		glow.visible = (i == _selected_index)
		card.add_child(glow)
		_selection_glows.append(glow)

		# Click area to select contract
		var click_btn := Button.new()
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		click_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		click_btn.pressed.connect(_on_contract_selected.bind(i))
		card.add_child(click_btn)

		# Content layout inside paper
		var pad_x: float = 28.0
		var eff_w: float = paper_size.x - (pad_x * 2.0)

		# 1. Tag (Top-Left)
		var tag_panel := PanelContainer.new()
		tag_panel.position = Vector2(pad_x, 32)
		tag_panel.custom_minimum_size = Vector2(96, 26)
		var sb_tag := StyleBoxFlat.new()
		sb_tag.bg_color = Color(0, 0, 0, 0)
		sb_tag.border_color = data.get("tag_color", COL_BLUE)
		sb_tag.set_border_width_all(2)
		sb_tag.set_corner_radius_all(4)
		sb_tag.content_margin_left = 6
		sb_tag.content_margin_right = 6
		tag_panel.add_theme_stylebox_override("panel", sb_tag)

		var tag_lbl := Label.new()
		tag_lbl.text = data["tag"]
		tag_lbl.add_theme_font_size_override("font_size", 11)
		tag_lbl.add_theme_color_override("font_color", data.get("tag_color", COL_BLUE))
		tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag_panel.add_child(tag_lbl)
		card.add_child(tag_panel)

		# 2. Subtag (Top-Right)
		var subtag_lbl := Label.new()
		subtag_lbl.text = data["subtag"]
		subtag_lbl.position = Vector2(paper_size.x - pad_x - 120, 30)
		subtag_lbl.size = Vector2(120, 30)
		subtag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		subtag_lbl.add_theme_font_size_override("font_size", 10)
		subtag_lbl.add_theme_color_override("font_color", COL_MUTED)
		card.add_child(subtag_lbl)

		# 3. Quota Amount & Timer
		var quota_lbl := Label.new()
		quota_lbl.text = "%.0f KG" % data["quota_target"]
		quota_lbl.position = Vector2(pad_x, 70)
		quota_lbl.size = Vector2(160, 42)
		quota_lbl.add_theme_font_size_override("font_size", 30)
		quota_lbl.add_theme_color_override("font_color", COL_DARK_TEXT)
		card.add_child(quota_lbl)

		var timer_lbl := Label.new()
		timer_lbl.text = "⏱ 02:30"
		timer_lbl.position = Vector2(paper_size.x - pad_x - 90, 78)
		timer_lbl.size = Vector2(90, 24)
		timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		timer_lbl.add_theme_font_size_override("font_size", 12)
		timer_lbl.add_theme_color_override("font_color", COL_DARK_TEXT)
		card.add_child(timer_lbl)

		# Divider Line
		var div := ColorRect.new()
		div.position = Vector2(pad_x, 120)
		div.size = Vector2(eff_w, 1.5)
		div.color = Color(0.78, 0.74, 0.68, 0.8)
		card.add_child(div)

		# 4. Mission Icon & Info
		var mission_box := HBoxContainer.new()
		mission_box.position = Vector2(pad_x, 134)
		mission_box.size = Vector2(eff_w, 48)
		mission_box.add_theme_constant_override("separation", 10)
		card.add_child(mission_box)

		var icon_tr := UIAssets.create_texture_rect(data["icon"])
		icon_tr.custom_minimum_size = Vector2(40, 40)
		icon_tr.size = Vector2(40, 40)
		mission_box.add_child(icon_tr)

		var m_vbox := VBoxContainer.new()
		m_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m_title := Label.new()
		m_title.text = data["title"]
		m_title.add_theme_font_size_override("font_size", 13)
		m_title.add_theme_color_override("font_color", COL_DARK_TEXT)
		m_vbox.add_child(m_title)

		var m_desc := Label.new()
		m_desc.text = data["desc"]
		m_desc.add_theme_font_size_override("font_size", 10)
		m_desc.add_theme_color_override("font_color", COL_MUTED)
		m_vbox.add_child(m_desc)
		mission_box.add_child(m_vbox)

		# 5. Condition / Hazard Box
		var cond_y: float = 196.0
		if data.has("condition_warning"):
			var warn_box := PanelContainer.new()
			warn_box.position = Vector2(pad_x, cond_y)
			warn_box.custom_minimum_size = Vector2(eff_w, 46)
			var sb_w := StyleBoxFlat.new()
			sb_w.bg_color = Color(0.98, 0.92, 0.90, 0.5)
			sb_w.border_color = Color(0.85, 0.35, 0.30, 0.8)
			sb_w.set_border_width_all(1)
			sb_w.set_corner_radius_all(3)
			sb_w.content_margin_left = 8
			sb_w.content_margin_right = 8
			sb_w.content_margin_top = 4
			sb_w.content_margin_bottom = 4
			warn_box.add_theme_stylebox_override("panel", sb_w)

			var w_lbl := Label.new()
			w_lbl.text = data["condition_warning"]
			w_lbl.add_theme_font_size_override("font_size", 10)
			w_lbl.add_theme_color_override("font_color", Color(0.80, 0.22, 0.18))
			warn_box.add_child(w_lbl)
			card.add_child(warn_box)
			cond_y += 54
		else:
			var cond_row := HBoxContainer.new()
			cond_row.position = Vector2(pad_x, cond_y)
			cond_row.size = Vector2(eff_w, 24)
			var c_t := Label.new()
			c_t.text = data.get("condition_title", "MEDAN")
			c_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c_t.add_theme_font_size_override("font_size", 11)
			c_t.add_theme_color_override("font_color", COL_MUTED)
			cond_row.add_child(c_t)

			var c_d := Label.new()
			c_d.text = data.get("condition_desc", "Normal")
			c_d.add_theme_font_size_override("font_size", 11)
			c_d.add_theme_color_override("font_color", COL_DARK_TEXT)
			cond_row.add_child(c_d)
			card.add_child(cond_row)
			cond_y += 32

		# Divider 2
		var div2 := ColorRect.new()
		div2.position = Vector2(pad_x, cond_y + 10)
		div2.size = Vector2(eff_w, 1.0)
		div2.color = Color(0.82, 0.78, 0.72, 0.7)
		card.add_child(div2)

		# 6. Payout & Stamp Rewards
		var pay_row := HBoxContainer.new()
		pay_row.position = Vector2(pad_x, cond_y + 20)
		pay_row.size = Vector2(eff_w, 24)
		var p_t := Label.new()
		p_t.text = "BAYARAN"
		p_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_t.add_theme_font_size_override("font_size", 11)
		p_t.add_theme_color_override("font_color", COL_MUTED)
		pay_row.add_child(p_t)

		var p_v := Label.new()
		p_v.text = "+$%d" % data["payout"]
		p_v.add_theme_font_size_override("font_size", 13)
		p_v.add_theme_color_override("font_color", Color(0.18, 0.58, 0.22))
		pay_row.add_child(p_v)
		card.add_child(pay_row)

		var stamp_row := HBoxContainer.new()
		stamp_row.position = Vector2(pad_x, cond_y + 50)
		stamp_row.size = Vector2(eff_w, 24)
		var s_t := Label.new()
		s_t.text = "STEMPEL"
		s_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s_t.add_theme_font_size_override("font_size", 11)
		s_t.add_theme_color_override("font_color", COL_MUTED)
		stamp_row.add_child(s_t)

		var s_v := Label.new()
		s_v.text = data["stamp_reward"]
		s_v.add_theme_font_size_override("font_size", 11)
		s_v.add_theme_color_override("font_color", COL_BLUE if i == 1 else COL_DARK_TEXT)
		stamp_row.add_child(s_v)
		card.add_child(stamp_row)

		# 7. Action Button on Paper (PILIH KONTRAK / ✓ KONTRAK DIPILIH)
		var is_selected := (i == _selected_index)
		var btn_path := "res://UI/02_shop/btn_contract_blue_wood.png" if is_selected else "res://UI/02_shop/btn_contract_brown_wood.png"
		var btn_txt := "✓ KONTRAK DIPILIH" if is_selected else "PILIH KONTRAK"
		var pilih_btn := UIAssets.create_textured_button(
			btn_path,
			btn_txt,
			13,
			COL_WHITE,
			"",
			Vector2(eff_w, 48)
		)
		pilih_btn.position = Vector2(pad_x, paper_size.y - 70)
		pilih_btn.pressed.connect(_on_contract_selected.bind(i))
		card.add_child(pilih_btn)
		_pilih_buttons.append(pilih_btn)


# ===========================================================================
# Inspection Day Boss Event Paper (Mockup 2)
# ===========================================================================
func _build_boss_paper() -> void:
	_contract_nodes.clear()
	_selection_glows.clear()
	_pilih_buttons.clear()

	var data: Dictionary = _contracts_data[0]
	var paper_size := Vector2(483, 510)
	var paper_pos := Vector2(358, 16)

	var card := Control.new()
	card.position = paper_pos
	card.custom_minimum_size = paper_size
	card.size = paper_size
	_papers_container.add_child(card)
	_contract_nodes.append(card)

	# Red-pinned Boss Contract Paper
	var bg_tex := UIAssets.create_texture_rect(data["bg_tex"])
	bg_tex.position = Vector2.ZERO
	bg_tex.size = paper_size
	card.add_child(bg_tex)

	var pad_x: float = 40.0
	var eff_w: float = paper_size.x - (pad_x * 2.0)

	# 1. Inspection Day Tag (Top-Left)
	var tag_panel := PanelContainer.new()
	tag_panel.position = Vector2(pad_x, 34)
	tag_panel.custom_minimum_size = Vector2(130, 28)
	var sb_tag := StyleBoxFlat.new()
	sb_tag.bg_color = Color(0, 0, 0, 0)
	sb_tag.border_color = COL_RED
	sb_tag.set_border_width_all(2)
	sb_tag.set_corner_radius_all(4)
	sb_tag.content_margin_left = 8
	sb_tag.content_margin_right = 8
	tag_panel.add_theme_stylebox_override("panel", sb_tag)

	var tag_lbl := Label.new()
	tag_lbl.text = data["tag"]
	tag_lbl.add_theme_font_size_override("font_size", 12)
	tag_lbl.add_theme_color_override("font_color", COL_RED)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_panel.add_child(tag_lbl)
	card.add_child(tag_panel)

	# 2. Subtag (Top-Right)
	var subtag_lbl := Label.new()
	subtag_lbl.text = data["subtag"]
	subtag_lbl.position = Vector2(paper_size.x - pad_x - 180, 26)
	subtag_lbl.size = Vector2(180, 40)
	subtag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	subtag_lbl.add_theme_font_size_override("font_size", 10)
	subtag_lbl.add_theme_color_override("font_color", COL_RED)
	card.add_child(subtag_lbl)

	# 3. Quota Amount & Timer
	var quota_lbl := Label.new()
	var unit: String = data.get("target_unit", "KG")
	if unit == "SC":
		quota_lbl.text = "$%.0f SC" % data["quota_target"]
	elif unit == "FLAG":
		quota_lbl.text = "1× FLAG"
	elif unit == "HEARTS":
		quota_lbl.text = "3× HEARTS"
	elif unit == "HP":
		quota_lbl.text = "%.0f HP" % data["quota_target"]
	else:
		quota_lbl.text = "%.0f KG" % data["quota_target"]
	quota_lbl.position = Vector2(pad_x, 78)
	quota_lbl.size = Vector2(200, 46)
	quota_lbl.add_theme_font_size_override("font_size", 34)
	quota_lbl.add_theme_color_override("font_color", COL_RED)
	card.add_child(quota_lbl)

	var timer_lbl := Label.new()
	timer_lbl.text = "⏱ 02:30"
	timer_lbl.position = Vector2(paper_size.x - pad_x - 100, 88)
	timer_lbl.size = Vector2(100, 26)
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_lbl.add_theme_font_size_override("font_size", 13)
	timer_lbl.add_theme_color_override("font_color", COL_DARK_TEXT)
	card.add_child(timer_lbl)

	# Divider 1
	var div := ColorRect.new()
	div.position = Vector2(pad_x, 134)
	div.size = Vector2(eff_w, 1.5)
	div.color = Color(0.85, 0.70, 0.68, 0.8)
	card.add_child(div)

	# 4. Mission Icon & Info
	var mission_box := HBoxContainer.new()
	mission_box.position = Vector2(pad_x, 146)
	mission_box.size = Vector2(eff_w, 48)
	mission_box.add_theme_constant_override("separation", 12)
	card.add_child(mission_box)

	var icon_tr := UIAssets.create_texture_rect(data["icon"])
	icon_tr.custom_minimum_size = Vector2(40, 40)
	icon_tr.size = Vector2(40, 40)
	mission_box.add_child(icon_tr)

	var m_vbox := VBoxContainer.new()
	m_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m_title := Label.new()
	m_title.text = data["title"]
	m_title.add_theme_font_size_override("font_size", 13)
	m_title.add_theme_color_override("font_color", COL_DARK_TEXT)
	m_vbox.add_child(m_title)

	var m_desc := Label.new()
	m_desc.text = data["desc"]
	m_desc.add_theme_font_size_override("font_size", 10)
	m_desc.add_theme_color_override("font_color", COL_MUTED)
	m_vbox.add_child(m_desc)
	mission_box.add_child(m_vbox)

	# 5. Red Boss Warning Box
	var warn_box := PanelContainer.new()
	warn_box.position = Vector2(pad_x, 212)
	warn_box.custom_minimum_size = Vector2(eff_w, 56)
	var sb_w := StyleBoxFlat.new()
	sb_w.bg_color = Color(0.98, 0.90, 0.88, 0.6)
	sb_w.border_color = COL_RED
	sb_w.set_border_width_all(1)
	sb_w.set_corner_radius_all(4)
	sb_w.content_margin_left = 10
	sb_w.content_margin_right = 10
	sb_w.content_margin_top = 6
	sb_w.content_margin_bottom = 6
	warn_box.add_theme_stylebox_override("panel", sb_w)

	var w_lbl := Label.new()
	w_lbl.text = data["rule_warning"]
	w_lbl.add_theme_font_size_override("font_size", 10)
	w_lbl.add_theme_color_override("font_color", COL_RED)
	warn_box.add_child(w_lbl)
	card.add_child(warn_box)

	# Divider 2
	var div2 := ColorRect.new()
	div2.position = Vector2(pad_x, 280)
	div2.size = Vector2(eff_w, 1.0)
	div2.color = Color(0.85, 0.70, 0.68, 0.7)
	card.add_child(div2)

	# 6. Payout & Boss Reward
	var pay_row := HBoxContainer.new()
	pay_row.position = Vector2(pad_x, 292)
	pay_row.size = Vector2(eff_w, 24)
	var p_t := Label.new()
	p_t.text = "BAYARAN"
	p_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_t.add_theme_font_size_override("font_size", 11)
	p_t.add_theme_color_override("font_color", COL_MUTED)
	pay_row.add_child(p_t)

	var p_v := Label.new()
	p_v.text = "+$%d" % data["payout"]
	p_v.add_theme_font_size_override("font_size", 14)
	p_v.add_theme_color_override("font_color", Color(0.18, 0.58, 0.22))
	pay_row.add_child(p_v)
	card.add_child(pay_row)

	var boss_r_row := HBoxContainer.new()
	boss_r_row.position = Vector2(pad_x, 324)
	boss_r_row.size = Vector2(eff_w, 24)
	var b_t := Label.new()
	b_t.text = "HADIAH BOSS"
	b_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_t.add_theme_font_size_override("font_size", 11)
	b_t.add_theme_color_override("font_color", COL_MUTED)
	boss_r_row.add_child(b_t)

	var b_v := Label.new()
	b_v.text = data["boss_reward"]
	b_v.add_theme_font_size_override("font_size", 12)
	b_v.add_theme_color_override("font_color", Color(0.70, 0.22, 0.85))
	boss_r_row.add_child(b_v)
	card.add_child(boss_r_row)

	# 7. Red Action Button on Paper (✓ KONTRAK AUDIT WAJIB)
	var audit_contract_btn := UIAssets.create_textured_button(
		data["btn_tex"],
		data["btn_text"],
		14,
		COL_WHITE,
		"",
		Vector2(eff_w, 54)
	)
	audit_contract_btn.position = Vector2(pad_x, paper_size.y - 78)
	card.add_child(audit_contract_btn)


# ===========================================================================
# Bottom Bar (Dialogue + Start Shift Action Button)
# ===========================================================================
func _build_bottom_bar() -> void:
	# 1. Dialogue Line on Left
	var dlg_box := HBoxContainer.new()
	dlg_box.position = Vector2(50, 660)
	dlg_box.size = Vector2(880, 42)
	dlg_box.add_theme_constant_override("separation", 10)
	_content.add_child(dlg_box)

	var avatar := Label.new()
	avatar.text = "📋" if is_boss_day else "🤠"
	avatar.add_theme_font_size_override("font_size", 18)
	dlg_box.add_child(avatar)

	_dialogue_label = Label.new()
	if is_boss_day:
		var dlg_default: String = "The Inspector: \"Hari ini event wajib! Penuhi kuota audit atau Taman Nasional resmi ditutup!\""
		_dialogue_label.text = active_event_data.get("dialogue", dlg_default)
	else:
		_dialogue_label.text = "Chief Ranger: \"Pilih 1 kertas kontrak di papan, lalu mulai shift!\""
	_dialogue_label.add_theme_font_size_override("font_size", 13)
	_dialogue_label.add_theme_color_override("font_color", Color(0.96, 0.40, 0.35) if is_boss_day else Color(0.95, 0.82, 0.40))
	_dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dlg_box.add_child(_dialogue_label)

	# 2. Start Shift / Mulai Audit Button on Right
	var btn_tex := "res://UI/02_shop/btn_audit_red_wood.png" if is_boss_day else "res://UI/02_shop/btn_start_blue_wood.png"
	var tag_title: String = active_event_data.get("tag", "AUDIT")
	var btn_title := ("MULAI %s  →" % tag_title) if is_boss_day else "MULAI SHIFT  →"
	_start_shift_btn = UIAssets.create_textured_button(
		btn_tex,
		btn_title,
		15,
		COL_WHITE,
		"",
		Vector2(260, 56)
	)
	_start_shift_btn.position = Vector2(965, 648)
	_start_shift_btn.pressed.connect(_on_start_shift_confirmed)
	_content.add_child(_start_shift_btn)


# ===========================================================================
# Updates & Selection Handling
# ===========================================================================
func _refresh_top_bar() -> void:
	var cur_day := 1
	var is_challenge := false
	if _dnc != null:
		cur_day = _dnc.current_day
		if "event_system" in _dnc and _dnc.event_system and "current_game_mode" in _dnc.event_system:
			is_challenge = (_dnc.event_system.current_game_mode == 1)
	if is_instance_valid(_day_label):
		_day_label.text = ("🔥 DAY %02d / %02d" if is_challenge else "DAY %02d / %02d") % [cur_day, MAX_DAYS]

	var funds: int = 14
	if _player != null and "slop_credit" in _player:
		funds = int(_player.slop_credit)
	if is_instance_valid(_funds_label):
		_funds_label.text = "$%d" % funds

	if is_challenge and is_instance_valid(_boss_tag_label):
		_boss_tag_label.text = "🔥 CHALLENGE"
		_boss_tag_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.30))


func _on_contract_selected(idx: int) -> void:
	if idx < 0 or idx >= _contracts_data.size():
		return
	_selected_index = idx
	_update_contract_selection_visuals()
	emit_signal("contract_selected", _contracts_data[_selected_index])
	if NetworkManager.is_multiplayer_active():
		NetworkManager.submit_quota_vote(_selected_index)


func _update_contract_selection_visuals() -> void:
	if is_boss_day:
		return

	for i in range(_selection_glows.size()):
		var glow: ReferenceRect = _selection_glows[i]
		if is_instance_valid(glow):
			glow.visible = (i == _selected_index)

	for i in range(_pilih_buttons.size()):
		var btn: Button = _pilih_buttons[i]
		if is_instance_valid(btn):
			var is_sel := (i == _selected_index)
			btn.text = "✓ KONTRAK DIPILIH" if is_sel else "PILIH KONTRAK"
			var tex_p := "res://UI/02_shop/btn_contract_blue_wood.png" if is_sel else "res://UI/02_shop/btn_contract_brown_wood.png"
			var tex := UIAssets.get_tex(tex_p)
			if tex:
				var sb := StyleBoxTexture.new()
				sb.texture = tex
				btn.add_theme_stylebox_override("normal", sb)


func _on_start_shift_confirmed() -> void:
	if NetworkManager.is_multiplayer_active():
		if NetworkManager.is_host():
			NetworkManager.resolve_and_start_quota_vote()
		else:
			NetworkManager.lock_quota_vote(_selected_index)
			if is_instance_valid(_start_shift_btn):
				_start_shift_btn.disabled = true
				_start_shift_btn.text = "LOCKED ✓ (Waiting...)"
		return
	_finalize_shift_start()


func _on_coop_vote_finalized(winning_idx: int) -> void:
	if _contracts_data.size() > 0:
		_selected_index = clampi(winning_idx, 0, _contracts_data.size() - 1)
	_finalize_shift_start()


func _refresh_vote_ui() -> void:
	if not NetworkManager.is_multiplayer_active() or is_boss_day:
		return

	var counts: Dictionary = {}
	for pid in NetworkManager.quota_votes.keys():
		var idx: int = NetworkManager.quota_votes[pid]
		counts[idx] = counts.get(idx, 0) + 1

	for i in range(_pilih_buttons.size()):
		var btn: Button = _pilih_buttons[i]
		if is_instance_valid(btn):
			var c: int = counts.get(i, 0)
			var is_sel := (i == _selected_index)
			var prefix := "✓ YOUR VOTE" if is_sel else "VOTE"
			btn.text = "%s (%d)" % [prefix, c]

	var total_peers := 1 + NetworkManager.spawned_players.size()
	var locked_count := NetworkManager.quota_locked.size()
	if is_instance_valid(_dialogue_label):
		_dialogue_label.text = "🗳️ Co-op Quota Vote (%d/%d locked in) — Ties go to the Host!" % [locked_count, total_peers]
	if is_instance_valid(_start_shift_btn) and not _start_shift_btn.disabled:
		_start_shift_btn.text = "RESOLVE VOTE & START" if NetworkManager.is_host() else "LOCK IN VOTE"


func _finalize_shift_start() -> void:
	var chosen_contract: Dictionary = _contracts_data[_selected_index]

	# Apply custom quota target and modifiers to DayNightCycle
	if _dnc != null:
		_dnc.custom_day_quota = float(chosen_contract.get("quota_target", 15.0))
		_dnc.is_waiting_for_day_start = false

	# Apply boss penalties / contract modifiers to Player if applicable
	if _player != null and chosen_contract.get("is_boss", false):
		if "is_boss_day" in _player:
			_player.is_boss_day = true

	emit_signal("day_started", chosen_contract)

	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		queue_free()
	)
