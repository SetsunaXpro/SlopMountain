# quota_menu.gd
# Contract Board / Inspection & Event Boss selection screen [Q]
# Preserves 100% of Fahri's Co-op Quota Voting, EventSystem integration, and Challenge Mode
# while rendering crisp torn-paper contracts on the Ranger Corkboard (zero cyan boxes / duplicate dividers).

class_name QuotaMenu
extends CanvasLayer

signal day_started(contract_data: Dictionary)
signal contract_selected(contract_data: Dictionary)

const UIAssets = preload("res://ui_assets.gd")

const MAX_DAYS: int = 8

# Colors
const COL_WHITE     := Color(1.0, 1.0, 1.0, 1.0)
const COL_DARK_TEXT := Color(0.14, 0.12, 0.10, 1.0)
const COL_AMBER     := Color(0.96, 0.65, 0.15, 1.0)
const COL_RED       := Color(0.76, 0.18, 0.16, 1.0)
const COL_BLUE      := Color(0.16, 0.46, 0.76, 1.0)
const COL_GREEN     := Color(0.18, 0.56, 0.28, 1.0)
const COL_MUTED     := Color(0.42, 0.37, 0.32, 1.0)

# State
var _player = null
var _dnc: DayNightCycle = null

var force_boss_mode: bool = false
var is_boss_day: bool = false
var active_event_data: Dictionary = {}
var _selected_index: int = 1
var _contracts_data: Array[Dictionary] = []
var _contract_nodes: Array[Control] = []
var _pilih_buttons: Array[Button] = []
var _subtag_labels: Array[Label] = []

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
	if _player and _player.has_method("release_mouse"):
		_player.release_mouse()
	_determine_day_type()
	_init_contracts_data()
	_build_ui()
	_refresh_top_bar()
	_update_contract_selection_visuals()

	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = false

	if NetworkManager != null and NetworkManager.is_multiplayer_active():
		if not NetworkManager.quota_votes_updated.is_connected(_refresh_vote_ui):
			NetworkManager.quota_votes_updated.connect(_refresh_vote_ui)
		if not NetworkManager.quota_vote_finalized.is_connected(_on_coop_vote_finalized):
			NetworkManager.quota_vote_finalized.connect(_on_coop_vote_finalized)
		if NetworkManager.is_host():
			NetworkManager.reset_quota_votes()
		NetworkManager.submit_quota_vote(_selected_index)
		_refresh_vote_ui()


func _exit_tree() -> void:
	if NetworkManager != null:
		if NetworkManager.quota_votes_updated.is_connected(_refresh_vote_ui):
			NetworkManager.quota_votes_updated.disconnect(_refresh_vote_ui)
		if NetworkManager.quota_vote_finalized.is_connected(_on_coop_vote_finalized):
			NetworkManager.quota_vote_finalized.disconnect(_on_coop_vote_finalized)
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = true


func _resolve_references() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _dnc == null:
		_dnc = get_tree().get_first_node_in_group("day_night_cycle")


func _get_duration_str() -> String:
	if _dnc != null and "day_duration_seconds" in _dnc:
		var secs: int = int(_dnc.day_duration_seconds)
		return "%02d:%02d" % [secs / 60, secs % 60]
	return "07:00"


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

	if not force_boss_mode and es and es.is_event_day(day):
		is_boss_day = true
		active_event_data = es.get_event_data_for_day(day)
	else:
		is_boss_day = force_boss_mode or (day % 4 == 0)
		if is_boss_day:
			if es and es.has_method("get_event_data_for_day") and es.is_event_day(day):
				active_event_data = es.get_event_data_for_day(day)
			else:
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
	var dur_str := _get_duration_str()

	if is_boss_day:
		var event_id: String = active_event_data.get("id", "inspection_day")
		var event_tag: String = active_event_data.get("tag", "INSPECTION DAY")
		var event_subtag: String = active_event_data.get("subtag", "BOSS EVENT · DAY %d\n! WAJIB / TIDAK BISA SKIP" % current_day)
		var event_title: String = active_event_data.get("title", "EVENT: SURPRISE AUDIT")
		var event_desc: String = active_event_data.get("desc", "Semua jenis sampah (Haul) — Sidak Kebersihan")
		var rule_warn: String = active_event_data.get("rule_warning", "▲ ATURAN BOSS: SALAH TONG = -20 KG KUOTA!")
		var payout_amt: int = int(active_event_data.get("payout", 20))
		var reward_str: String = active_event_data.get("reward", "★ 1× Summit Stamp (+0.05 Mult)")
		var icon_p: String = active_event_data.get("icon", "res://UI/03_cards/icon_contract_audit.png")
		var quota_tgt: float = float(active_event_data.get("quota_target", maxf(480.0, base_q * 2.8)))
		var t_unit: String = active_event_data.get("target_unit", "KG")

		_contracts_data.append({
			"id": event_id,
			"type": "BOSS",
			"tag": event_tag,
			"subtag": event_subtag,
			"quota_target": quota_tgt,
			"target_unit": t_unit,
			"time_str": dur_str,
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
		var easy_q := maxf(15.0, roundf(base_q * 0.8))
		_contracts_data.append({
			"type": "EASY",
			"tag": "LOW QUOTA",
			"mult_tag": "EASY ×0.8",
			"quota_target": easy_q,
			"time_str": dur_str,
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

		var std_q := maxf(20.0, roundf(base_q * 1.0))
		_contracts_data.append({
			"type": "STANDARD",
			"tag": "STANDARD",
			"mult_tag": "NORMAL ×1.0",
			"quota_target": std_q,
			"time_str": dur_str,
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

		var hard_q := maxf(30.0, roundf(base_q * 1.4))
		_contracts_data.append({
			"type": "HARD",
			"tag": "HIGH QUOTA",
			"mult_tag": "HARD ×1.4",
			"quota_target": hard_q,
			"time_str": dur_str,
			"icon": "res://UI/03_cards/icon_contract_organic.png",
			"title": "MISI: COMPOST RUN",
			"desc": "Khusus sampah organik",
			"condition_warning": "▲ ANGIN KENCANG (+$2) — Sampah ringan mudah terbang",
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
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var outer_bg := ColorRect.new()
	outer_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_bg.color = Color(0.08, 0.05, 0.05, 1.0) if is_boss_day else Color(0.08, 0.06, 0.05, 1.0)
	_root.add_child(outer_bg)

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

	# 1. Wall Background
	var wall_path := "res://UI/02_shop/bg_boss_wall.png" if is_boss_day else "res://UI/02_shop/bg_dawn_wall.png"
	var wall_bg := UIAssets.create_texture_rect(wall_path)
	wall_bg.position = Vector2.ZERO
	wall_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(wall_bg)

	# 2. Ranger Corkboard (1200 x 562)
	var corkboard := UIAssets.create_texture_rect("res://UI/02_shop/ranger_corkboard.png")
	corkboard.position = Vector2(40, 84)
	corkboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(corkboard)

	# 3. Top Header Bar
	_build_top_header()

	# 4. Papers Container
	_papers_container = Control.new()
	_papers_container.name = "PapersContainer"
	_papers_container.position = Vector2.ZERO
	_papers_container.size = Vector2(1280, 720)
	_content.add_child(_papers_container)

	if is_boss_day:
		_build_boss_paper()
	else:
		_build_standard_papers()

	# 5. Bottom Action Bar
	_build_bottom_bar()


# ===========================================================================
# Top Header Bar
# ===========================================================================

func _build_top_header() -> void:
	# 1. Left Plate: DAY 0X / 08 (216 x 48)
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

	# 2. Center Slab Header (440 x 58)
	var header_slab_tex := "res://UI/02_shop/header_slab_boss_bg.png" if is_boss_day else "res://UI/02_shop/header_slab_contract_bg.png"
	var header_slab := UIAssets.create_texture_rect(header_slab_tex)
	header_slab.position = Vector2(420, 14)
	header_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(header_slab)

	var tag_title: String = str(active_event_data.get("tag", "INSPECTION DAY")) if is_boss_day else "CONTRACT BOARD"
	var header_title := UIAssets.create_label(
		tag_title, 21,
		Color(0.98, 0.95, 0.90) if is_boss_day else Color(0.18, 0.13, 0.09),
		"black", HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER,
		0.5 if is_boss_day else 0.0
	)
	header_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_slab.add_child(header_title)

	# 3. Right Split Boss / Funds Plate (284 x 48)
	var split_plate := UIAssets.create_texture_rect("res://UI/02_shop/plate_boss_cash_split_bg.png")
	split_plate.position = Vector2(952, 18)
	split_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(split_plate)

	_boss_tag_label = UIAssets.create_label(
		"▲ BOSS: DAY 8", 12, Color(0.98, 0.72, 0.24), "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.4
	)
	_boss_tag_label.position = Vector2(10, 0)
	_boss_tag_label.size = Vector2(162, 48)
	split_plate.add_child(_boss_tag_label)

	_funds_label = UIAssets.create_label(
		"$14", 18, UIAssets.COL_GOLD, "mono",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	_funds_label.position = Vector2(180, 0)
	_funds_label.size = Vector2(96, 48)
	split_plate.add_child(_funds_label)


# ===========================================================================
# Standard 3 Torn-Paper Contracts (Clean Baked Rules, Zero Cyan Boxes)
# ===========================================================================

func _build_standard_papers() -> void:
	_contract_nodes.clear()
	_pilih_buttons.clear()
	_subtag_labels.clear()

	var x_positions := [84.0, 464.0, 844.0]

	for i in range(min(_contracts_data.size(), 3)):
		var data: Dictionary = _contracts_data[i]
		var is_sel: bool = (i == _selected_index)

		var card := Control.new()
		card.position = Vector2(x_positions[i], 112.0 if is_sel else 124.0)
		card.custom_minimum_size = Vector2(352, 474)
		card.size = Vector2(352, 474)
		_papers_container.add_child(card)
		_contract_nodes.append(card)

		# Torn Paper Texture centered on logical 352x474 frame
		var paper_tex := UIAssets.create_texture_rect(str(data["bg_tex"]))
		paper_tex.name = "PaperTex"
		var tex_sz := paper_tex.size
		paper_tex.position = Vector2((352.0 - tex_sz.x) * 0.5, -14.0)
		paper_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(paper_tex)

		# Full-card invisible click target
		var click_btn := Button.new()
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty_sb := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			click_btn.add_theme_stylebox_override(st, empty_sb)
		click_btn.pressed.connect(_on_contract_selected.bind(i))
		card.add_child(click_btn)

		# 1. Authentic Rubber Ink Stamp Difficulty Badge (Matching Figma 84:4)
		var stamp_cols := [Color(0.114, 0.369, 0.220), Color(0.086, 0.329, 0.522), Color(0.580, 0.118, 0.086)]
		var stamp_rots := [-2.0, -1.2, 1.8]
		var stamp_widths := [126.0, 118.0, 134.0]
		var ink_col: Color = stamp_cols[mini(i, 2)]
		var stamp_box := Panel.new()
		stamp_box.position = Vector2(28, 30)
		stamp_box.size = Vector2(stamp_widths[mini(i, 2)], 28)
		stamp_box.pivot_offset = stamp_box.size * 0.5
		stamp_box.rotation_degrees = stamp_rots[mini(i, 2)]
		stamp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		ssb.border_color = ink_col
		ssb.set_border_width_all(2)
		ssb.set_corner_radius_all(0)
		stamp_box.add_theme_stylebox_override("panel", ssb)
		card.add_child(stamp_box)

		var tag_lbl := UIAssets.create_label(
			str(data["tag"]), 12, ink_col, "black",
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
		)
		tag_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		stamp_box.add_child(tag_lbl)

		# 2. Mult / Selected Subtag (Top-Right, inset to clear corner tape)
		var subtag_lbl := UIAssets.create_label(
			str(data.get("mult_tag", "")), 11, ink_col, "bold",
			HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER
		)
		subtag_lbl.position = Vector2(162, 28)
		subtag_lbl.size = Vector2(140, 32)
		card.add_child(subtag_lbl)
		_subtag_labels.append(subtag_lbl)

		# 3. Big Quota Target & Shift Duration (Colored ink per tier matching Figma)
		var quota_cols := [COL_DARK_TEXT, Color(0.055, 0.302, 0.478), Color(0.561, 0.106, 0.078)]
		var quota_lbl := UIAssets.create_label(
			"%.0f KG" % float(data["quota_target"]), 32, quota_cols[mini(i, 2)], "black"
		)
		quota_lbl.position = Vector2(28, 86)
		quota_lbl.size = Vector2(204, 44)
		card.add_child(quota_lbl)

		var timer_lbl := UIAssets.create_label(
			"⏱ " + str(data.get("time_str", "07:00")), 13, COL_MUTED, "mono",
			HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER
		)
		timer_lbl.position = Vector2(232, 98)
		timer_lbl.size = Vector2(92, 24)
		card.add_child(timer_lbl)

		# 4. Hand-Inked Icon + Mission Title & Description
		var icon_tr := UIAssets.create_texture_rect(str(data["icon"]))
		icon_tr.position = Vector2(28, 154)
		icon_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon_tr)

		var m_title := UIAssets.create_label(str(data["title"]), 14, COL_DARK_TEXT, "black")
		m_title.position = Vector2(80, 154)
		m_title.size = Vector2(244, 22)
		card.add_child(m_title)

		var m_desc := UIAssets.create_label(str(data["desc"]), 11, COL_MUTED, "semibold")
		m_desc.position = Vector2(80, 178)
		m_desc.size = Vector2(244, 20)
		card.add_child(m_desc)

		# 5. Condition Row OR Ink-Stamped Hazard Box (Matching Figma Warning-Ink-Stamp)
		if data.has("condition_warning"):
			var warn_box := Panel.new()
			warn_box.position = Vector2(28, 229)
			warn_box.size = Vector2(296, 40)
			warn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var wsb := StyleBoxFlat.new()
			wsb.bg_color = Color(0.580, 0.118, 0.086, 0.08)
			wsb.border_color = Color(0.620, 0.122, 0.090, 0.92)
			wsb.set_border_width_all(2)
			wsb.set_corner_radius_all(0)
			warn_box.add_theme_stylebox_override("panel", wsb)
			card.add_child(warn_box)

			var w_lbl := UIAssets.create_wrapped_label(
				str(data["condition_warning"]), Vector2(10, 3), Vector2(276, 34),
				10, COL_RED, "bold", HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
			)
			warn_box.add_child(w_lbl)
		else:
			_add_spec_row(card, str(data.get("condition_title", "Cuaca")).capitalize(), str(data.get("condition_desc", "Normal")), 238, COL_DARK_TEXT)

		# 6. Payout & Stamp Spec Rows
		_add_spec_row(card, "Bayaran", "+$%d" % int(data["payout"]), 282, COL_GREEN, "black", 16)
		_add_spec_row(card, "Stempel", str(data["stamp_reward"]), 324, COL_BLUE if i == 1 else COL_DARK_TEXT, "bold", 12)

		# 7. Native Wood Plank Selection Button (328x80 -> visual 296x48 inside paper)
		var btn_path := "res://UI/02_shop/btn_contract_blue_wood.png" if is_sel else "res://UI/02_shop/btn_contract_brown_wood.png"
		var btn_txt := "✓  KONTRAK DIPILIH" if is_sel else "PILIH KONTRAK"
		var pilih_btn := UIAssets.create_wood_button(
			btn_path, btn_txt, 14, Color(0.20, 0.12, 0.05) if is_sel else UIAssets.COL_CREAM, "", "black", 5
		)
		pilih_btn.position = Vector2(12, 358)
		pilih_btn.pressed.connect(_on_contract_selected.bind(i))
		card.add_child(pilih_btn)
		_pilih_buttons.append(pilih_btn)


# ===========================================================================
# Boss / Event Mandatory Torn Paper
# ===========================================================================

func _build_boss_paper() -> void:
	_contract_nodes.clear()
	_pilih_buttons.clear()
	_subtag_labels.clear()

	var data: Dictionary = _contracts_data[0]

	var card := Control.new()
	card.position = Vector2(410, 118)
	card.custom_minimum_size = Vector2(460, 474)
	card.size = Vector2(460, 474)
	_papers_container.add_child(card)
	_contract_nodes.append(card)

	var paper_tex := UIAssets.create_texture_rect(str(data["bg_tex"]))
	paper_tex.position = Vector2((460.0 - paper_tex.size.x) * 0.5, -14.0)
	paper_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper_tex)

	# 1. Authentic Rubber Ink Stamp Event Badge (Matching Figma 119:10)
	var boss_ink := Color(0.580, 0.118, 0.086)
	var stamp := Panel.new()
	stamp.position = Vector2(30, 28)
	stamp.size = Vector2(168, 28)
	stamp.pivot_offset = stamp.size * 0.5
	stamp.rotation_degrees = -2.0
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	ssb.border_color = boss_ink
	ssb.set_border_width_all(2)
	ssb.set_corner_radius_all(0)
	stamp.add_theme_stylebox_override("panel", ssb)
	card.add_child(stamp)

	var tag_lbl := UIAssets.create_label(
		str(data["tag"]), 12, boss_ink, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	tag_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamp.add_child(tag_lbl)

	# 2. Clean Wajib Label (Top-Right)
	var subtag_lbl := UIAssets.create_label(
		"Event Wajib", 12, boss_ink, "bold",
		HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER
	)
	subtag_lbl.position = Vector2(226, 28)
	subtag_lbl.size = Vector2(204, 28)
	card.add_child(subtag_lbl)

	# 3. Quota / Event Target (supports KG, SC, FLAG, HEARTS, HP!)
	var unit: String = str(data.get("target_unit", "KG"))
	var target_text := ""
	if unit == "SC":
		target_text = "$%.0f SC" % float(data["quota_target"])
	elif unit == "FLAG":
		target_text = "1× FLAG"
	elif unit == "HEARTS":
		target_text = "3× HEARTS"
	elif unit == "HP":
		target_text = "%.0f HP" % float(data["quota_target"])
	else:
		target_text = "%.0f KG" % float(data["quota_target"])

	var quota_lbl := UIAssets.create_label(target_text, 34, COL_RED, "black")
	quota_lbl.position = Vector2(30, 86)
	quota_lbl.size = Vector2(270, 44)
	card.add_child(quota_lbl)

	var timer_lbl := UIAssets.create_label(
		"⏱ " + str(data.get("time_str", "07:00")), 14, COL_MUTED, "mono",
		HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER
	)
	timer_lbl.position = Vector2(320, 100)
	timer_lbl.size = Vector2(110, 24)
	card.add_child(timer_lbl)

	# 4. Event Icon & Description
	var icon_path: String = str(data.get("icon", "res://UI/03_cards/icon_contract_audit.png"))
	if UIAssets.get_tex(icon_path) == null:
		icon_path = "res://UI/03_cards/icon_contract_audit.png"
	var icon_tr := UIAssets.create_texture_rect(icon_path, true)
	icon_tr.position = Vector2(30, 152)
	icon_tr.custom_minimum_size = Vector2(44, 44)
	icon_tr.size = Vector2(44, 44)
	icon_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_tr)

	var ev_title := UIAssets.create_label(str(data["title"]), 14, COL_DARK_TEXT, "black")
	ev_title.position = Vector2(84, 152)
	ev_title.size = Vector2(346, 22)
	card.add_child(ev_title)

	var ev_desc := UIAssets.create_wrapped_label(
		str(data["desc"]), Vector2(84, 176), Vector2(346, 36),
		11, COL_MUTED, "semibold", HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP
	)
	card.add_child(ev_desc)

	# 5. Ink-Stamped Boss Warning Box (Matching Figma Warning-Ink-Stamp)
	var warn_box := Panel.new()
	warn_box.position = Vector2(30, 220)
	warn_box.size = Vector2(400, 48)
	warn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.580, 0.118, 0.086, 0.08)
	wsb.border_color = Color(0.620, 0.122, 0.090, 0.92)
	wsb.set_border_width_all(2)
	wsb.set_corner_radius_all(0)
	warn_box.add_theme_stylebox_override("panel", wsb)
	card.add_child(warn_box)

	var w_lbl := UIAssets.create_wrapped_label(
		str(data["rule_warning"]), Vector2(12, 4), Vector2(376, 40),
		10, COL_RED, "bold", HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	warn_box.add_child(w_lbl)

	# 6. Payout & Boss Reward Rows
	_add_spec_row_wide(card, "Bayaran", "+$%d" % int(data["payout"]), 284, COL_GREEN, "black", 17)
	_add_spec_row_wide(card, "Hadiah Boss", str(data["boss_reward"]), 326, Color(0.62, 0.24, 0.74), "bold", 12)

	# 7. Red Boss Plank Button (432x80 -> visual 400x48 inside paper)
	var audit_btn := UIAssets.create_wood_button(
		str(data.get("btn_tex", "res://UI/02_shop/btn_contract_boss_red_wood.png")),
		str(data.get("btn_text", "✓ KONTRAK WAJIB")),
		14, COL_WHITE, "", "black", 5
	)
	audit_btn.position = Vector2(14, 356)
	audit_btn.pressed.connect(_on_start_shift_confirmed)
	card.add_child(audit_btn)


func _add_spec_row(parent: Control, key_txt: String, val_txt: String, y: float, val_col: Color, val_style: String = "bold", val_size: int = 12) -> void:
	var k := UIAssets.create_label(key_txt, 12, COL_MUTED, "bold")
	k.position = Vector2(28, y)
	k.size = Vector2(110, 22)
	parent.add_child(k)

	var v := UIAssets.create_label(val_txt, val_size, val_col, val_style, HORIZONTAL_ALIGNMENT_RIGHT)
	v.position = Vector2(138, y)
	v.size = Vector2(186, 22)
	parent.add_child(v)


func _add_spec_row_wide(parent: Control, key_txt: String, val_txt: String, y: float, val_col: Color, val_style: String = "bold", val_size: int = 12) -> void:
	var k := UIAssets.create_label(key_txt, 12, COL_MUTED, "bold")
	k.position = Vector2(30, y)
	k.size = Vector2(120, 22)
	parent.add_child(k)

	var v := UIAssets.create_label(val_txt, val_size, val_col, val_style, HORIZONTAL_ALIGNMENT_RIGHT)
	v.position = Vector2(150, y)
	v.size = Vector2(280, 22)
	parent.add_child(v)


# ===========================================================================
# Bottom Bar (Shop Shortcuts, Chief/Inspector/Vote Dialogue, Start Shift)
# ===========================================================================

func _build_bottom_bar() -> void:
	# Quick shop navigation buttons on left
	var shop_btn := UIAssets.create_wood_button(
		"res://UI/05_modals/btn_modal_brown_wood.png",
		"MOD SHOP [B]", 13, UIAssets.COL_CREAM, "", "black", 5
	)
	shop_btn.custom_minimum_size = Vector2(204, 68)
	shop_btn.size = Vector2(204, 68)
	shop_btn.position = Vector2(26, 645)
	shop_btn.pressed.connect(_on_shop_shortcut_pressed)
	_content.add_child(shop_btn)

	var mach_btn := UIAssets.create_wood_button(
		"res://UI/05_modals/btn_modal_brown_wood.png",
		"MACHINES [M]", 13, UIAssets.COL_CREAM, "", "black", 5
	)
	mach_btn.custom_minimum_size = Vector2(204, 68)
	mach_btn.size = Vector2(204, 68)
	mach_btn.position = Vector2(236, 645)
	mach_btn.pressed.connect(_on_machines_shortcut_pressed)
	_content.add_child(mach_btn)

	# Dialogue Strip in Center
	var dlg_text := ""
	if is_boss_day:
		var dlg_default := "The Inspector: \"Hari ini event wajib! Penuhi kuota audit atau Taman Nasional resmi ditutup!\""
		dlg_text = str(active_event_data.get("dialogue", dlg_default))
	else:
		dlg_text = "Chief Ranger: \"Pilih 1 kertas kontrak di papan, lalu mulai shift!\""

	_dialogue_label = UIAssets.create_wrapped_label(
		dlg_text, Vector2(458, 650), Vector2(476, 52),
		11, Color(1.0, 0.56, 0.48) if is_boss_day else Color(1.0, 0.90, 0.56),
		"bold", HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	_dialogue_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	_dialogue_label.add_theme_constant_override("shadow_offset_y", 2)
	_content.add_child(_dialogue_label)

	# Start Shift / Mulai Audit / Resolve Vote Button on Right (302 x 82)
	var btn_tex := "res://UI/02_shop/btn_audit_red_wood.png" if is_boss_day else "res://UI/02_shop/btn_start_blue_wood.png"
	var tag_title: String = str(active_event_data.get("tag", "AUDIT"))
	var btn_title := ("MULAI %s  ➔" % tag_title) if is_boss_day else "MULAI SHIFT  ➔"
	_start_shift_btn = UIAssets.create_wood_button(
		btn_tex, btn_title, 15, COL_WHITE if is_boss_day else Color(0.20, 0.12, 0.05), "", "black", 5
	)
	_start_shift_btn.position = Vector2(950, 638)
	_start_shift_btn.pressed.connect(_on_start_shift_confirmed)
	_content.add_child(_start_shift_btn)


func _on_shop_shortcut_pressed() -> void:
	if _player != null and _player.has_method("toggle_buy_menu"):
		_player.toggle_buy_menu()
	queue_free()


func _on_machines_shortcut_pressed() -> void:
	if _player != null and _player.has_method("toggle_machine_menu"):
		_player.toggle_machine_menu()
	queue_free()


# ===========================================================================
# Updates, Selection & Co-op Voting (100% Preserved from 3e26359)
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

	if is_instance_valid(_boss_tag_label):
		if is_challenge:
			_boss_tag_label.text = "🔥 CHALLENGE"
			_boss_tag_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.30))
		elif is_boss_day:
			_boss_tag_label.text = "▲ %s" % str(active_event_data.get("tag", "EVENT"))
			_boss_tag_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.36))
		else:
			_boss_tag_label.text = "▲ BOSS: DAY 8"
			_boss_tag_label.add_theme_color_override("font_color", Color(0.98, 0.72, 0.24))


func _on_contract_selected(idx: int) -> void:
	if idx < 0 or idx >= _contracts_data.size():
		return
	_selected_index = idx
	_update_contract_selection_visuals()
	emit_signal("contract_selected", _contracts_data[_selected_index])
	if NetworkManager != null and NetworkManager.is_multiplayer_active():
		NetworkManager.submit_quota_vote(_selected_index)


func _update_contract_selection_visuals() -> void:
	if is_boss_day:
		return

	for i in range(_contract_nodes.size()):
		var card: Control = _contract_nodes[i]
		if not is_instance_valid(card):
			continue
		var is_sel := (i == _selected_index)
		card.position.y = 110.0 if is_sel else 124.0
		var paper_tex := card.get_node_or_null("PaperTex") as TextureRect
		if paper_tex:
			paper_tex.modulate = Color(1.03, 1.02, 0.99, 1.0) if is_sel else Color(0.90, 0.88, 0.85, 1.0)

	var tier_inks := [Color(0.114, 0.369, 0.220), Color(0.086, 0.329, 0.522), Color(0.580, 0.118, 0.086)]
	for i in range(_subtag_labels.size()):
		var sl: Label = _subtag_labels[i]
		if is_instance_valid(sl) and i < _contracts_data.size():
			var is_sel := (i == _selected_index)
			var base_mult: String = str(_contracts_data[i].get("mult_tag", ""))
			sl.text = (base_mult + "\n✓ DIPILIH") if is_sel else base_mult
			sl.add_theme_color_override("font_color", tier_inks[mini(i, 2)])

	var is_mp := (NetworkManager != null and NetworkManager.is_multiplayer_active())
	for i in range(_pilih_buttons.size()):
		var btn: Button = _pilih_buttons[i]
		if is_instance_valid(btn):
			var is_sel := (i == _selected_index)
			if not is_mp:
				btn.text = "✓  KONTRAK DIPILIH" if is_sel else "PILIH KONTRAK"
			var sel_col := Color(0.20, 0.12, 0.05) if is_sel else UIAssets.COL_CREAM
			btn.add_theme_color_override("font_color", sel_col)
			btn.add_theme_color_override("font_hover_color", sel_col if is_sel else Color.WHITE)
			btn.add_theme_color_override("font_focus_color", sel_col)
			btn.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0 if is_sel else 0.50))
			var tex_p := "res://UI/02_shop/btn_contract_blue_wood.png" if is_sel else "res://UI/02_shop/btn_contract_brown_wood.png"
			var tex := UIAssets.get_tex(tex_p)
			if tex:
				for state in ["normal", "hover", "pressed"]:
					var sb := StyleBoxTexture.new()
					sb.texture = tex
					sb.content_margin_bottom = 5 if state != "pressed" else 3
					if state == "hover":
						sb.modulate_color = Color(1.08, 1.06, 1.04)
					elif state == "pressed":
						sb.content_margin_top = 2
						sb.modulate_color = Color(0.88, 0.86, 0.84)
					btn.add_theme_stylebox_override(state, sb)


func _on_start_shift_confirmed() -> void:
	if NetworkManager != null and NetworkManager.is_multiplayer_active():
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
	if NetworkManager == null or not NetworkManager.is_multiplayer_active() or is_boss_day:
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

	if _dnc != null:
		_dnc.custom_day_quota = float(chosen_contract.get("quota_target", 15.0))
		_dnc.is_waiting_for_day_start = false

	if _player != null and chosen_contract.get("is_boss", false):
		if "is_boss_day" in _player:
			_player.is_boss_day = true

	emit_signal("day_started", chosen_contract)

	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		queue_free()
	)
