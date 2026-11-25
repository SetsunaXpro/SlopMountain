# game_hud.gd
# Industrial / Retro-Utility In-Game HUD using raw HD textures in res://UI/01_hud/
# Preserves 100% of Fahri's Event HUD Panel & EventSystem hooks while delivering
# pixel-accurate odometer alignment, crisp bundled typography, two-tone Haul Quota,
# live owned_perks sync, and clean bottom bar spacing alongside the Machine Hotbar.

class_name GameHUD
extends CanvasLayer

const UIAssets = preload("res://ui_assets.gd")

const COL_AMBER      := Color(0.96, 0.68, 0.16, 1.0)
const COL_AMBER_DARK := Color(0.74, 0.44, 0.12, 1.0)
const COL_GREEN      := Color(0.32, 0.90, 0.48, 1.0)
const COL_TEXT_LIGHT := Color(0.90, 0.92, 0.96, 1.0)
const COL_TEXT_DIM   := Color(0.45, 0.50, 0.58, 1.0)

# References
var quota_val_label: RichTextLabel = null
var quota_progress_bar: TextureProgressBar = null
var time_label: Label = null
var time_sub_label: Label = null
var end_day_btn: Button = null
var _end_day_sb_normal: StyleBoxFlat = null
var _end_day_sb_hover: StyleBoxFlat = null
var streak_counter: Control = null
var mult_label: Label = null
var inventory_panel: Control = null
var perks_panel: Control = null
var _inventory_slots: Array = []
var _perk_slot_widgets: Array = []
var _last_owned_perks_sig: String = ""

# Event HUD Panel (Fahri's EventSystem integration)
var event_panel: PanelContainer = null
var event_title_label: Label = null
var event_sub_label: Label = null
var event_hp_bar: ProgressBar = null

# Live values
var current_quota_val: float = 0.0
var max_quota_val: float = 100.0
var quota_unit: String = "SC"
var current_streak: int = 0
var current_mult: float = 1.0


func _ready() -> void:
	layer = 10
	add_to_group("game_hud")
	_build_hud_layout()
	_connect_to_systems()


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_sync_perks_if_changed(player)

	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if not dnc:
		return

	if dnc.has_signal("time_updated") and not dnc.time_updated.is_connected(_on_dnc_time_updated):
		dnc.time_updated.connect(_on_dnc_time_updated)
	if dnc.has_signal("day_started") and not dnc.day_started.is_connected(_on_dnc_day_started):
		dnc.day_started.connect(_on_dnc_day_started)
	if dnc.has_signal("night_started") and not dnc.night_started.is_connected(_on_dnc_night_started):
		dnc.night_started.connect(_on_dnc_night_started)

	var cur: float = 0.0
	var tgt: float = 100.0
	var quota_passed: bool = false
	if dnc.has_method("get_daily_progress_amount") and dnc.has_method("get_current_quota"):
		cur = float(dnc.get_daily_progress_amount())
		tgt = float(dnc.get_current_quota())
		quota_passed = (cur >= tgt)
		var unit: String = "SC"
		if "quota_type" in dnc:
			unit = "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC"
		update_quota(cur, tgt, unit)

	if "day_duration_seconds" in dnc and "day_elapsed_seconds" in dnc:
		if not dnc.is_night:
			var remaining_seconds: float = maxf(0.0, float(dnc.day_duration_seconds) - float(dnc.day_elapsed_seconds))
			var rem_min: int = int(remaining_seconds / 60.0)
			var rem_sec: int = int(remaining_seconds) % 60
			var time_str := "%02d:%02d" % [rem_min, rem_sec]
			update_time_display(time_str, false, quota_passed)
		else:
			update_time_display("00:00", true, quota_passed)

	if is_instance_valid(end_day_btn):
		var is_waiting: bool = bool(dnc.get("is_waiting_for_day_start")) if "is_waiting_for_day_start" in dnc else false
		end_day_btn.visible = (not dnc.is_night) and (not is_waiting)
		if quota_passed:
			end_day_btn.text = "✓  HOLD [N] END DAY • MET"
			end_day_btn.add_theme_color_override("font_color", COL_GREEN)
			if _end_day_sb_normal:
				_end_day_sb_normal.border_color = COL_GREEN
		else:
			end_day_btn.text = "HOLD [N]  END DAY"
			end_day_btn.add_theme_color_override("font_color", COL_AMBER)
			if _end_day_sb_normal:
				_end_day_sb_normal.border_color = COL_AMBER_DARK

	# Sync EventSystem state if active
	if dnc and "event_system" in dnc and dnc.event_system:
		var es = dnc.event_system
		if es.has_signal("event_started") and not es.event_started.is_connected(_on_event_started):
			_connect_event_system(es)
		_update_event_display(es)


func _build_hud_layout() -> void:
	var root := Control.new()
	root.name = "HUD_Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 1. Top-Left: Haul Quota Panel (264 x 64)
	root.add_child(_create_haul_quota_panel())

	# 2. Top-Center: Sunset Timer Plaque, Sleek End Day Tag, & Event HUD Panel
	root.add_child(_create_time_banner())
	end_day_btn = _create_end_day_button()
	root.add_child(end_day_btn)
	event_panel = _create_event_panel()
	root.add_child(event_panel)

	# 3. Top-Right: Mechanical Streak Counter (167 x 171)
	root.add_child(_create_streak_panel())

	# 4. Bottom-Left: Pack Caddy Slots (#1 - #4) (307 x 127)
	inventory_panel = _create_inventory_panel()
	root.add_child(inventory_panel)

	# 5. Bottom-Right: Equipped Gear / Perk Rail (5 slots) (322 x 127)
	perks_panel = _create_perks_panel()
	root.add_child(perks_panel)

	# 6. Bottom-Center: Subtle Keybind Strip (sits cleanly beneath Machine Hotbar)
	root.add_child(_create_keybind_hint_bar())


func _connect_to_systems() -> void:
	call_deferred("_deferred_connect")


func _deferred_connect() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("item_bagged") and not player.item_bagged.is_connected(_on_player_item_bagged):
			player.item_bagged.connect(_on_player_item_bagged)
		_refresh_inventory_from_player(player)
		sync_perks_from_player(player)

	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		if dnc.has_signal("time_updated") and not dnc.time_updated.is_connected(_on_dnc_time_updated):
			dnc.time_updated.connect(_on_dnc_time_updated)
		if dnc.has_signal("day_started") and not dnc.day_started.is_connected(_on_dnc_day_started):
			dnc.day_started.connect(_on_dnc_day_started)
		if dnc.has_signal("night_started") and not dnc.night_started.is_connected(_on_dnc_night_started):
			dnc.night_started.connect(_on_dnc_night_started)
		if "event_system" in dnc and dnc.event_system:
			_connect_event_system(dnc.event_system)


# ===========================================================================
# 1. Top-Left: Haul Quota Panel (264 x 64)
# ===========================================================================

func _create_haul_quota_panel() -> Control:
	var container := Control.new()
	container.position = Vector2(22, 18)
	container.custom_minimum_size = Vector2(264, 64)
	container.size = Vector2(264, 64)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_quota_bg.png")
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg_tex)

	quota_val_label = RichTextLabel.new()
	quota_val_label.bbcode_enabled = true
	quota_val_label.scroll_active = false
	quota_val_label.fit_content = false
	quota_val_label.position = Vector2(108, 10)
	quota_val_label.size = Vector2(134, 22)
	quota_val_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quota_val_label.add_theme_font_override("normal_font", UIAssets.get_font("mono"))
	quota_val_label.add_theme_font_override("bold_font", UIAssets.get_font("black"))
	quota_val_label.add_theme_font_size_override("normal_font_size", 11)
	quota_val_label.add_theme_font_size_override("bold_font_size", 12)
	container.add_child(quota_val_label)

	quota_progress_bar = TextureProgressBar.new()
	quota_progress_bar.position = Vector2(22, 37)
	quota_progress_bar.custom_minimum_size = Vector2(219, 16)
	quota_progress_bar.size = Vector2(219, 16)
	quota_progress_bar.nine_patch_stretch = false
	quota_progress_bar.texture_progress = UIAssets.get_tex("res://UI/01_hud/hud_quota_fill.png")
	quota_progress_bar.min_value = 0.0
	quota_progress_bar.max_value = 100.0
	quota_progress_bar.value = 0.0
	quota_progress_bar.step = 0.1
	quota_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(quota_progress_bar)

	update_quota(0.0, max_quota_val, quota_unit)
	return container


# ===========================================================================
# 2. Top-Center: Sunset Timer Banner & Sleek End Day Tag (298 x 72)
# ===========================================================================

func _create_time_banner() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	container.offset_left = -149
	container.offset_right = 149
	container.offset_top = 12
	container.offset_bottom = 84
	container.custom_minimum_size = Vector2(298, 72)
	container.size = Vector2(298, 72)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var plaque_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_timer_bg.png")
	plaque_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(plaque_tex)

	time_label = UIAssets.create_label(
		"☀ 07:00", 26, Color(0.14, 0.11, 0.08, 1.0), "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	time_label.position = Vector2(0, 10)
	time_label.size = Vector2(298, 34)
	container.add_child(time_label)

	# Legacy hidden node reference so baked "UNTIL SUNSET" texture is never overwritten
	time_sub_label = Label.new()
	time_sub_label.visible = false
	container.add_child(time_sub_label)

	return container


func _create_end_day_button() -> Button:
	var btn := Button.new()
	btn.text = "HOLD [N]  END DAY"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", UIAssets.get_font("mono"))
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", COL_AMBER)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	btn.offset_left = -104
	btn.offset_right = 104
	btn.offset_top = 86
	btn.offset_bottom = 108
	btn.custom_minimum_size = Vector2(208, 22)
	btn.size = Vector2(208, 22)

	_end_day_sb_normal = StyleBoxFlat.new()
	_end_day_sb_normal.bg_color = Color(0.09, 0.11, 0.14, 0.88)
	_end_day_sb_normal.border_color = COL_AMBER_DARK
	_end_day_sb_normal.set_border_width_all(1)
	_end_day_sb_normal.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", _end_day_sb_normal)

	_end_day_sb_hover = _end_day_sb_normal.duplicate()
	_end_day_sb_hover.bg_color = Color(0.16, 0.19, 0.24, 0.96)
	_end_day_sb_hover.border_color = COL_AMBER
	btn.add_theme_stylebox_override("hover", _end_day_sb_hover)
	btn.add_theme_stylebox_override("pressed", _end_day_sb_hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.pressed.connect(_on_end_day_btn_pressed)
	return btn


func _on_end_day_btn_pressed() -> void:
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and dnc.has_method("end_day_early"):
		dnc.end_day_early()


# ===========================================================================
# 3. Top-Right: Mechanical Streak Counter & Multiplier (167 x 171)
# ===========================================================================

func _create_streak_panel() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	container.offset_left = -189
	container.offset_right = -22
	container.offset_top = 14
	container.offset_bottom = 185
	container.custom_minimum_size = Vector2(167, 171)
	container.size = Vector2(167, 171)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var streak_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_streak_clicker_bg.png")
	streak_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(streak_tex)

	streak_counter = OdometerWidget.new()
	streak_counter.position = Vector2.ZERO
	streak_counter.size = Vector2(167, 171)
	container.add_child(streak_counter)

	mult_label = UIAssets.create_label(
		"MULT: ×1.0", 14, Color(0.14, 0.10, 0.05, 1.0), "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	mult_label.position = Vector2(22, 114)
	mult_label.size = Vector2(123, 34)
	container.add_child(mult_label)

	return container


# ===========================================================================
# 4. Bottom-Left: Pack Caddy Inventory Slots (#1 - #4) (307 x 127)
# ===========================================================================

func _create_inventory_panel() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	container.offset_left = 22
	container.offset_right = 329
	container.offset_top = -147
	container.offset_bottom = -20
	container.custom_minimum_size = Vector2(307, 127)
	container.size = Vector2(307, 127)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var caddy_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_pack_caddy_bg.png")
	caddy_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(caddy_tex)

	# 4 slots * 66 + 3 * 6 = 282px -> centered horizontally at x = 13, y = 17
	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.position = Vector2(13, 17)
	hbox.custom_minimum_size = Vector2(282, 94)
	hbox.size = Vector2(282, 94)
	hbox.add_theme_constant_override("separation", 6)
	container.add_child(hbox)

	_inventory_slots.clear()
	for i in range(4):
		var slot := InventorySlotWidget.new()
		slot.slot_number = i + 1
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(slot)
		_inventory_slots.append(slot)

	return container


# ===========================================================================
# 5. Bottom-Right: Active Gear / Perks Rail (322 x 127)
# ===========================================================================

func _create_perks_panel() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	container.offset_left = -344
	container.offset_right = -22
	container.offset_top = -147
	container.offset_bottom = -20
	container.custom_minimum_size = Vector2(322, 127)
	container.size = Vector2(322, 127)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rail_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_equipped_rail_bg.png")
	rail_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(rail_tex)

	# 5 slots * 58 + 4 * 3 = 302px -> centered horizontally at x = 10, y = 17
	var hbox := HBoxContainer.new()
	hbox.position = Vector2(10, 17)
	hbox.custom_minimum_size = Vector2(302, 94)
	hbox.size = Vector2(302, 94)
	hbox.add_theme_constant_override("separation", 3)
	container.add_child(hbox)

	_perk_slot_widgets.clear()
	for _i in range(5):
		var slot_empty := PerkSlotWidget.new()
		slot_empty.set_empty()
		slot_empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(slot_empty)
		_perk_slot_widgets.append(slot_empty)

	return container


# ===========================================================================
# 6. Bottom-Center: Subtle Keybind Strip (clear of Machine Hotbar)
# ===========================================================================

func _create_keybind_hint_bar() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -268
	panel.offset_right = 268
	panel.offset_top = -28
	panel.offset_bottom = -6
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.68)
	sb.border_color = Color(0.45, 0.34, 0.22, 0.48)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := UIAssets.create_label(
		"[B] Mod Shop   •   [M] Mesin   •   [Q] Kontrak   •   [G] Granat   •   [ESC] Pause",
		10, Color(0.88, 0.86, 0.80, 0.90), "mono",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	panel.add_child(lbl)
	return panel


# ===========================================================================
# Event HUD Panel & EventSystem Integration (100% Preserved + Styled)
# ===========================================================================

func _create_event_panel() -> PanelContainer:
	event_panel = PanelContainer.new()
	event_panel.name = "EventHUDPanel"
	event_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_panel.offset_left = -204
	event_panel.offset_right = 204
	event_panel.offset_top = 120
	event_panel.custom_minimum_size = Vector2(408, 54)
	event_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_panel.visible = false

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.92)
	sb.border_color = Color(0.92, 0.36, 0.24, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	event_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_panel.add_child(vbox)

	event_title_label = UIAssets.create_label(
		"EVENT TITLE", 12, UIAssets.COL_GOLD, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	vbox.add_child(event_title_label)

	event_sub_label = UIAssets.create_label(
		"Objective status...", 11, COL_TEXT_LIGHT, "semibold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	vbox.add_child(event_sub_label)

	event_hp_bar = ProgressBar.new()
	event_hp_bar.custom_minimum_size = Vector2(376, 9)
	event_hp_bar.min_value = 0.0
	event_hp_bar.max_value = 100.0
	event_hp_bar.value = 100.0
	event_hp_bar.show_percentage = false
	event_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.14, 0.16, 0.20, 0.90)
	sb_bg.set_corner_radius_all(3)
	event_hp_bar.add_theme_stylebox_override("background", sb_bg)
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = Color(0.90, 0.28, 0.20, 1.0)
	sb_fill.set_corner_radius_all(3)
	event_hp_bar.add_theme_stylebox_override("fill", sb_fill)
	vbox.add_child(event_hp_bar)

	return event_panel


func _connect_event_system(es: Node) -> void:
	if not es.event_started.is_connected(_on_event_started):
		es.event_started.connect(_on_event_started)
	if not es.event_progress_updated.is_connected(_on_event_progress_updated):
		es.event_progress_updated.connect(_on_event_progress_updated)
	if not es.event_completed.is_connected(_on_event_completed):
		es.event_completed.connect(_on_event_completed)


func _on_event_started(event_data: Dictionary) -> void:
	if not is_instance_valid(event_panel):
		return
	event_panel.visible = true
	var is_challenge := false
	var dnc = get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and "event_system" in dnc and dnc.event_system and "current_game_mode" in dnc.event_system:
		is_challenge = (dnc.event_system.current_game_mode == 1)

	var title: String = str(event_data.get("title", "EVENT"))
	if is_challenge:
		event_title_label.text = "🔥 CHALLENGE: " + title
		event_title_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.30))
	else:
		event_title_label.text = "★ " + title
		event_title_label.add_theme_color_override("font_color", UIAssets.COL_GOLD)

	event_sub_label.text = str(event_data.get("desc", ""))
	event_sub_label.add_theme_color_override("font_color", COL_TEXT_LIGHT)
	var target: float = float(event_data.get("quota_target", 1.0))
	var unit: String = str(event_data.get("target_unit", ""))
	if unit == "HP":
		event_hp_bar.visible = true
		event_hp_bar.max_value = target
		event_hp_bar.value = target
	elif unit == "FLAG":
		event_hp_bar.visible = false
		event_sub_label.text = "🚩 Tancapkan Bendera di tiang puncak tertinggi!"
	elif unit == "HEARTS":
		event_hp_bar.visible = true
		event_hp_bar.max_value = target
		event_hp_bar.value = 0.0
		event_sub_label.text = "🐾 Beri 3 camilan organik untuk menjinakkan (0/3)"
	elif unit == "SC":
		event_hp_bar.visible = true
		event_hp_bar.max_value = target
		event_hp_bar.value = 0.0
		event_sub_label.text = "💰 Jual sampah & produk daur ulang ($0 / $25 SC)"
	else:
		event_hp_bar.visible = false


func _on_event_progress_updated(cur: float, target: float, status_text: String) -> void:
	if not is_instance_valid(event_panel):
		return
	if status_text != "":
		event_sub_label.text = status_text
	if event_hp_bar.visible:
		event_hp_bar.max_value = target
		event_hp_bar.value = cur


func _on_event_completed(_event_id: String) -> void:
	if not is_instance_valid(event_panel):
		return
	event_title_label.text = "🎉 EVENT COMPLETED!"
	event_title_label.add_theme_color_override("font_color", COL_GREEN)
	event_sub_label.text = "Target terpenuhi! Siap pulang saat senja."
	event_sub_label.add_theme_color_override("font_color", COL_GREEN)
	if is_instance_valid(event_hp_bar):
		event_hp_bar.visible = false


func _update_event_display(es: Node) -> void:
	if not is_instance_valid(event_panel):
		return
	event_panel.visible = bool(es.is_event_active)


# ===========================================================================
# Public API & Live Sync
# ===========================================================================

func update_quota(current: float, target: float, unit: String = "SC") -> void:
	current_quota_val = current
	max_quota_val = maxf(1.0, target)
	quota_unit = unit

	if is_instance_valid(quota_val_label):
		var cur_int := int(current)
		var max_int := int(target)
		var cur_col := "#52E67A" if current >= target and target > 0.0 else "#F5AE24"
		quota_val_label.text = "[right][color=%s][b]%03d[/b][/color] [color=#7A8290]/[/color] [color=#F2F4F8][b]%d[/b][/color] [color=#F5AE24]%s[/color][/right]" % [
			cur_col, cur_int, max_int, unit
		]

	if is_instance_valid(quota_progress_bar):
		var pct := clampf((current / max_quota_val) * 100.0, 0.0, 100.0)
		quota_progress_bar.value = pct
		quota_progress_bar.modulate = Color(0.55, 1.25, 0.68) if pct >= 100.0 else Color.WHITE


func sync_perks_from_player(player: Node) -> void:
	if player == null or not ("owned_perks" in player):
		return
	var owned: Array = player.owned_perks
	for i in range(_perk_slot_widgets.size()):
		if i < owned.size():
			equip_perk(i, str(owned[i]))
		else:
			_perk_slot_widgets[i].set_empty()
	_last_owned_perks_sig = ",".join(owned)


func _sync_perks_if_changed(player: Node) -> void:
	if not ("owned_perks" in player):
		return
	var sig := ",".join(player.owned_perks)
	if sig != _last_owned_perks_sig:
		sync_perks_from_player(player)


func equip_perk(slot_index: int, perk_id: String) -> void:
	if slot_index < 0 or slot_index >= _perk_slot_widgets.size():
		return
	var slot: PerkSlotWidget = _perk_slot_widgets[slot_index]
	match perk_id:
		"hivis_vest":
			slot.set_perk("hivis_vest", "HI-VIS", "COMMON")
		"can_crusher":
			slot.set_perk("can_crusher", "CRUSH", "COMMON")
		"piggy_jar":
			slot.set_perk("piggy_jar", "PIGGY", "UNCOMMON")
		"speed_boots":
			slot.set_perk("speed_boots", "BOOTS", "COMMON")
		"magnet_glove":
			slot.set_perk("magnet_glove", "MAGNET", "UNCOMMON")
		"big_bag":
			slot.set_perk("big_bag", "BIG BAG", "COMMON")
		_:
			slot.set_perk(perk_id, perk_id.to_upper().substr(0, 7), "COMMON")


func update_streak(count: int) -> void:
	current_streak = count
	current_mult = 1.0 + float(count) * 0.1
	if is_instance_valid(streak_counter):
		streak_counter.set_value(current_streak)
	if is_instance_valid(mult_label):
		mult_label.text = "MULT: ×%.1f" % current_mult


func update_time_display(time_str: String, is_night: bool = false, is_quota_met: bool = false) -> void:
	if is_instance_valid(time_label):
		var prefix := "🌙 " if is_night else ("✓ " if is_quota_met else "☀ ")
		time_label.text = prefix + time_str
		if is_night:
			time_label.add_theme_color_override("font_color", Color(0.55, 0.14, 0.12))
		elif is_quota_met:
			time_label.add_theme_color_override("font_color", Color(0.10, 0.42, 0.18))
		else:
			time_label.add_theme_color_override("font_color", Color(0.14, 0.11, 0.08))


# ===========================================================================
# System Signal Callbacks
# ===========================================================================

func _on_player_item_bagged(_item_id: String, _value: float, _total_sc: float) -> void:
	update_streak(current_streak + 1)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		_refresh_inventory_from_player(player)

	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and dnc.has_method("get_daily_progress_amount"):
		var cur := float(dnc.get_daily_progress_amount())
		var tgt := float(dnc.get_current_quota())
		update_quota(cur, tgt, "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC")


func _on_dnc_time_updated(_day_progress: float, _hour: int, _minute: int) -> void:
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		var remaining_seconds: float = maxf(0.0, dnc.day_duration_seconds - dnc.day_elapsed_seconds)
		var rem_min: int = int(remaining_seconds / 60.0)
		var rem_sec: int = int(remaining_seconds) % 60
		var time_str := "%02d:%02d" % [rem_min, rem_sec]
		var cur := float(dnc.get_daily_progress_amount())
		var tgt := float(dnc.get_current_quota())
		update_time_display(time_str, dnc.is_night, cur >= tgt)
		update_quota(cur, tgt, "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC")


func _on_dnc_day_started(_day_number: int) -> void:
	update_streak(0)
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		update_quota(0.0, dnc.get_current_quota(), "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC")


func _on_dnc_night_started(_day_number: int, _quota_met: bool) -> void:
	update_time_display("00:00", true)


func _refresh_inventory_from_player(player: Node) -> void:
	if _inventory_slots.is_empty():
		return

	var items: Array = []
	if "trash_inventory_items" in player:
		items = player.trash_inventory_items

	for i in range(_inventory_slots.size()):
		var slot_widget: InventorySlotWidget = _inventory_slots[i] as InventorySlotWidget
		if not slot_widget:
			continue
		if i < items.size():
			var item_data: Dictionary = items[items.size() - 1 - i]
			var id_str: String = str(item_data.get("id", "trash")).to_lower()
			if id_str.contains("can") or id_str.contains("metal"):
				slot_widget.set_item(InventorySlotWidget.ItemType.METAL, "METAL")
			elif id_str.contains("bottle") or id_str.contains("glass"):
				slot_widget.set_item(InventorySlotWidget.ItemType.GLASS, "GLASS")
			elif id_str.contains("plastic"):
				slot_widget.set_item(InventorySlotWidget.ItemType.PLASTIC, "PLASTIC")
			else:
				slot_widget.set_item(InventorySlotWidget.ItemType.OTHER, id_str.to_upper().substr(0, 7))
		else:
			slot_widget.set_empty()


# ===========================================================================
# Widgets
# ===========================================================================

## 4-Digit Mechanical Odometer aligned pixel-accurately inside hud_streak_clicker_bg.png
class OdometerWidget extends Control:
	const SLOT_XS := [28.0, 56.0, 84.0, 112.0]
	const SLOT_Y  := 45.0
	const SLOT_W  := 23.0
	const SLOT_H  := 34.0

	var value: int = 0
	var _digit_labels: Array[Label] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_digit_labels.clear()
		for i in range(4):
			var lbl := UIAssets.create_label(
				"0", 20, Color(0.42, 0.46, 0.52, 0.85), "mono",
				HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
			)
			lbl.position = Vector2(SLOT_XS[i], SLOT_Y)
			lbl.size = Vector2(SLOT_W, SLOT_H)
			add_child(lbl)
			_digit_labels.append(lbl)
		set_value(value)

	func set_value(v: int) -> void:
		value = clampi(v, 0, 9999)
		var str_val := "%04d" % value
		var seen_nonzero := false
		for i in range(min(4, _digit_labels.size())):
			var ch := str_val[i]
			if ch != "0":
				seen_nonzero = true
			var is_highlight: bool = (i == 3) or seen_nonzero
			var col := Color(0.98, 0.64, 0.14, 1.0) if (i == 3) else (Color(0.92, 0.94, 0.96, 1.0) if is_highlight else Color(0.42, 0.46, 0.52, 0.80))
			_digit_labels[i].text = ch
			_digit_labels[i].add_theme_color_override("font_color", col)


## Bottom-Left Inventory Slot (#1 - #4) with HD empty/filled textures (66 x 94)
class InventorySlotWidget extends Control:
	enum ItemType { EMPTY, METAL, GLASS, PLASTIC, OTHER }

	var slot_number: int = 1
	var item_type: ItemType = ItemType.EMPTY
	var item_name: String = "EMPTY"

	var _bg_rect: TextureRect = null
	var _icon_label: Label = null
	var _num_label: Label = null
	var _item_label: Label = null

	func _ready() -> void:
		custom_minimum_size = Vector2(66, 94)
		size = Vector2(66, 94)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		_bg_rect = UIAssets.create_texture_rect("res://UI/01_hud/hud_pack_slot_empty.png")
		_bg_rect.position = Vector2.ZERO
		_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg_rect)

		_num_label = UIAssets.create_label(
			"#%d" % slot_number, 9, Color(0.48, 0.54, 0.62, 1.0), "mono",
			HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER
		)
		_num_label.position = Vector2(4, 4)
		_num_label.size = Vector2(56, 14)
		add_child(_num_label)

		_icon_label = Label.new()
		_icon_label.text = ""
		_icon_label.position = Vector2(0, 18)
		_icon_label.size = Vector2(66, 48)
		_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_icon_label.add_theme_font_size_override("font_size", 26)
		_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon_label)

		_item_label = UIAssets.create_label(
			"EMPTY", 9, Color(0.36, 0.41, 0.48, 1.0), "black",
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
		)
		_item_label.position = Vector2(0, 72)
		_item_label.size = Vector2(66, 16)
		add_child(_item_label)

	func set_item(type: ItemType, label_text: String) -> void:
		item_type = type
		item_name = label_text
		if is_instance_valid(_bg_rect):
			_bg_rect.texture = UIAssets.get_tex("res://UI/01_hud/hud_pack_slot_filled.png")
		if is_instance_valid(_item_label):
			_item_label.text = label_text
			match type:
				ItemType.METAL:
					_item_label.add_theme_color_override("font_color", Color(0.96, 0.62, 0.12))
					if is_instance_valid(_icon_label): _icon_label.text = "🥫"
				ItemType.GLASS:
					_item_label.add_theme_color_override("font_color", Color(0.24, 0.88, 0.44))
					if is_instance_valid(_icon_label): _icon_label.text = "🍾"
				ItemType.PLASTIC:
					_item_label.add_theme_color_override("font_color", Color(0.28, 0.68, 0.96))
					if is_instance_valid(_icon_label): _icon_label.text = "🧴"
				_:
					_item_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
					if is_instance_valid(_icon_label): _icon_label.text = "📦"

	func set_empty() -> void:
		item_type = ItemType.EMPTY
		item_name = "EMPTY"
		if is_instance_valid(_bg_rect):
			_bg_rect.texture = UIAssets.get_tex("res://UI/01_hud/hud_pack_slot_empty.png")
		if is_instance_valid(_icon_label):
			_icon_label.text = ""
		if is_instance_valid(_item_label):
			_item_label.text = "EMPTY"
			_item_label.add_theme_color_override("font_color", Color(0.36, 0.41, 0.48, 1.0))


## Bottom-Right Active Gear / Perk Slot with HD gadget slot rarity textures (58 x 94)
class PerkSlotWidget extends Control:
	var perk_id: String = ""
	var perk_title: String = "EMPTY"
	var rarity: String = "COMMON"

	var _bg_rect: TextureRect = null
	var _art_rect: TextureRect = null
	var _icon_label: Label = null
	var _title_label: Label = null

	func _ready() -> void:
		custom_minimum_size = Vector2(58, 94)
		size = Vector2(58, 94)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		_bg_rect = UIAssets.create_texture_rect("res://UI/01_hud/hud_gadget_slot_common.png")
		_bg_rect.position = Vector2.ZERO
		_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg_rect)

		_art_rect = TextureRect.new()
		_art_rect.position = Vector2(7, 18)
		_art_rect.size = Vector2(44, 44)
		_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art_rect.visible = false
		add_child(_art_rect)

		_icon_label = Label.new()
		_icon_label.text = ""
		_icon_label.position = Vector2(0, 16)
		_icon_label.size = Vector2(58, 48)
		_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_icon_label.add_theme_font_size_override("font_size", 26)
		_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon_label)

		_title_label = UIAssets.create_label(
			perk_title, 8, Color(0.40, 0.45, 0.52, 1.0), "black",
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
		)
		_title_label.position = Vector2(0, 72)
		_title_label.size = Vector2(58, 16)
		add_child(_title_label)

		_update_visuals()

	func set_perk(id: String, title: String, perk_rarity: String = "COMMON") -> void:
		perk_id = id
		perk_title = title
		rarity = perk_rarity
		_update_visuals()

	func set_empty() -> void:
		perk_id = ""
		perk_title = "EMPTY"
		rarity = "COMMON"
		_update_visuals()

	func _update_visuals() -> void:
		if not is_instance_valid(_bg_rect):
			return

		var tex_path := "res://UI/01_hud/hud_gadget_slot_common.png"
		match rarity.to_upper():
			"UNCOMMON":
				tex_path = "res://UI/01_hud/hud_gadget_slot_uncommon.png"
			"RARE":
				tex_path = "res://UI/01_hud/hud_gadget_slot_rare.png"
			"LEGENDARY":
				tex_path = "res://UI/01_hud/hud_gadget_slot_legendary.png"
			_:
				tex_path = "res://UI/01_hud/hud_gadget_slot_common.png"

		_bg_rect.texture = UIAssets.get_tex(tex_path)

		if perk_id == "":
			_bg_rect.modulate = Color(0.50, 0.52, 0.56, 0.62)
			if is_instance_valid(_art_rect):
				_art_rect.visible = false
			if is_instance_valid(_icon_label):
				_icon_label.text = ""
				_icon_label.visible = true
			if is_instance_valid(_title_label):
				_title_label.text = "EMPTY"
				_title_label.add_theme_color_override("font_color", Color(0.36, 0.40, 0.46))
		else:
			_bg_rect.modulate = Color.WHITE
			var custom_art := UIAssets.get_card_art(perk_id)
			if custom_art != null and is_instance_valid(_art_rect):
				_art_rect.texture = custom_art
				_art_rect.visible = true
				if is_instance_valid(_icon_label):
					_icon_label.visible = false
			else:
				if is_instance_valid(_art_rect):
					_art_rect.visible = false
				var icon_char := "⚙️"
				match perk_id:
					"hivis_vest":
						icon_char = "🦺"
					"piggy_jar":
						icon_char = "🐷"
					"can_crusher":
						icon_char = "🔩"
					"speed_boots":
						icon_char = "👟"
					"magnet_glove":
						icon_char = "🧲"
					"big_bag":
						icon_char = "🎒"
				if is_instance_valid(_icon_label):
					_icon_label.text = icon_char
					_icon_label.visible = true
			if is_instance_valid(_title_label):
				_title_label.text = perk_title
				_title_label.add_theme_color_override("font_color", Color(0.94, 0.91, 0.82))
