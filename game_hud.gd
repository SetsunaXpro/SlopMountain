# game_hud.gd
# Implements the custom industrial/retro-utility HUD using raw HD UI textures in res://UI/01_hud/
# - Top-Left: Haul Quota with hud_quota_bg and hud_quota_fill TextureProgressBar
# - Top-Center: Time Until Sunset with hud_timer_bg bronze plaque and End Day button
# - Top-Right: 4-digit mechanical Streak Counter with hud_streak_clicker_bg
# - Bottom-Left: Inventory quick-slots with hud_pack_caddy_bg, hud_pack_slot_empty/filled
# - Bottom-Right: 5 Gear/Perk slots with hud_equipped_rail_bg and hud_gadget_slot_*

class_name GameHUD
extends CanvasLayer

const UIAssets = preload("res://ui_assets.gd")

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
const COL_AMBER := Color(0.96, 0.62, 0.12, 1.0)
const COL_AMBER_DARK := Color(0.82, 0.44, 0.10, 1.0)
const COL_TEXT_LIGHT := Color(0.88, 0.90, 0.94, 1.0)
const COL_TEXT_DIM := Color(0.42, 0.46, 0.54, 1.0)

# References
var quota_val_label: Label = null
var quota_progress_bar: TextureProgressBar = null
var time_label: Label = null
var time_sub_label: Label = null
var end_day_btn: Button = null
var streak_counter: Control = null
var mult_label: Label = null
var inventory_panel: Control = null
var perks_panel: Control = null
var _inventory_slots: Array = []
var _perk_slot_widgets: Array = []

# Live values
var current_quota_val: float = 0.0
var max_quota_val: float = 100.0
var quota_unit: String = "KG"
var current_streak: int = 0
var current_mult: float = 1.0

# ---------------------------------------------------------------------------
# Initialization & Setup
# ---------------------------------------------------------------------------
func _ready() -> void:
	layer = 10
	add_to_group("game_hud")
	_build_hud_layout()
	_connect_to_systems()


func _process(_delta: float) -> void:
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if not dnc:
		return

	# Ensure system signals are connected if DNC spawned after GameHUD
	if dnc.has_signal("time_updated") and not dnc.time_updated.is_connected(_on_dnc_time_updated):
		dnc.time_updated.connect(_on_dnc_time_updated)
	if dnc.has_signal("day_started") and not dnc.day_started.is_connected(_on_dnc_day_started):
		dnc.day_started.connect(_on_dnc_day_started)
	if dnc.has_signal("night_started") and not dnc.night_started.is_connected(_on_dnc_night_started):
		dnc.night_started.connect(_on_dnc_night_started)

	# Keep haul quota in sync in real-time
	var cur: float = 0.0
	var tgt: float = 100.0
	var quota_passed: bool = false
	if dnc.has_method("get_daily_progress_amount") and dnc.has_method("get_current_quota"):
		cur = float(dnc.get_daily_progress_amount())
		tgt = float(dnc.get_current_quota())
		quota_passed = (cur >= tgt)
		var unit: String = "KG"
		if "quota_type" in dnc:
			unit = "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC"
		update_quota(cur, tgt, unit)

	# Update countdown timer on top of the screen in real-time
	if "day_duration_seconds" in dnc and "day_elapsed_seconds" in dnc:
		if not dnc.is_night:
			var remaining_seconds: float = maxf(0.0, float(dnc.day_duration_seconds) - float(dnc.day_elapsed_seconds))
			var rem_min: int = int(remaining_seconds / 60.0)
			var rem_sec: int = int(remaining_seconds) % 60
			var time_str := "%02d:%02d" % [rem_min, rem_sec]
			update_time_display(time_str, false, quota_passed)
		else:
			update_time_display("00:00", true, quota_passed)

	# Update End Day button state
	if is_instance_valid(end_day_btn):
		var is_waiting: bool = bool(dnc.get("is_waiting_for_day_start")) if "is_waiting_for_day_start" in dnc else false
		end_day_btn.visible = (not dnc.is_night) and (not is_waiting)
		if quota_passed:
			end_day_btn.text = "🌅 END DAY [N] (QUOTA MET)"
			end_day_btn.modulate = Color(0.4, 1.0, 0.6)
		else:
			end_day_btn.text = "🌅 END DAY [N]"
			end_day_btn.modulate = Color(1.0, 0.85, 0.4)


func _build_hud_layout() -> void:
	var root := Control.new()
	root.name = "HUD_Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 1. Top-Left: Haul Quota Panel (264 x 64)
	root.add_child(_create_haul_quota_panel())

	# 2. Top-Center: Time Banner (298 x 72) & End Day Button
	root.add_child(_create_time_banner())

	end_day_btn = _create_end_day_button()
	root.add_child(end_day_btn)

	# 3. Top-Right: Streak Counter Panel (167 x 171)
	root.add_child(_create_streak_panel())

	# 4. Bottom-Left: Inventory Slots (307 x 127)
	inventory_panel = _create_inventory_panel()
	root.add_child(inventory_panel)

	# 5. Bottom-Right: Active Gear / Perks Panel (322 x 127)
	perks_panel = _create_perks_panel()
	root.add_child(perks_panel)


func _connect_to_systems() -> void:
	call_deferred("_deferred_connect")


func _deferred_connect() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("item_bagged"):
			player.item_bagged.connect(Callable(self, "_on_player_item_bagged"))
		_refresh_inventory_from_player(player)

	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		if dnc.has_signal("time_updated"):
			dnc.time_updated.connect(Callable(self, "_on_dnc_time_updated"))
		if dnc.has_signal("day_started"):
			dnc.day_started.connect(Callable(self, "_on_dnc_day_started"))
		if dnc.has_signal("night_started"):
			dnc.night_started.connect(Callable(self, "_on_dnc_night_started"))


# ===========================================================================
# 1. Top-Left: Haul Quota Panel (264 x 64)
# ===========================================================================
func _create_haul_quota_panel() -> Control:
	var container := Control.new()
	container.position = Vector2(24, 20)
	container.custom_minimum_size = Vector2(264, 64)
	container.size = Vector2(264, 64)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HD Panel Texture
	var bg_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_quota_bg.png")
	container.add_child(bg_tex)

	# "000 / 100 KG" label (Positioned on the right of the baked "HAUL QUOTA" title)
	quota_val_label = Label.new()
	quota_val_label.text = "000 / 100 KG"
	quota_val_label.position = Vector2(110, 10)
	quota_val_label.size = Vector2(134, 20)
	quota_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quota_val_label.add_theme_color_override("font_color", COL_TEXT_LIGHT)
	quota_val_label.add_theme_font_size_override("font_size", 12)
	container.add_child(quota_val_label)

	# Hazard Striped Progress Bar using hud_quota_fill.png (219 x 16)
	quota_progress_bar = TextureProgressBar.new()
	quota_progress_bar.position = Vector2(22, 36)
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

	return container


# ===========================================================================
# 2. Top-Center: Time Until Sunset Banner & End Day Button (298 x 72)
# ===========================================================================
func _create_time_banner() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	container.offset_left = -149
	container.offset_right = 149
	container.offset_top = 10
	container.offset_bottom = 82
	container.custom_minimum_size = Vector2(298, 72)
	container.size = Vector2(298, 72)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HD Bronze Plaque Texture
	var plaque_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_timer_bg.png")
	container.add_child(plaque_tex)

	# Big Bold Time Display
	time_label = Label.new()
	time_label.text = "02:15"
	time_label.position = Vector2(0, 12)
	time_label.size = Vector2(298, 30)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.add_theme_color_override("font_color", Color(0.18, 0.14, 0.10, 1.0))
	time_label.add_theme_font_size_override("font_size", 24)
	container.add_child(time_label)

	# Subtitle (Only shown during NIGHTFALL or when QUOTA MET so baked UNTIL SUNSET is untouched)
	time_sub_label = Label.new()
	time_sub_label.text = ""
	time_sub_label.position = Vector2(0, 44)
	time_sub_label.size = Vector2(298, 16)
	time_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_sub_label.add_theme_color_override("font_color", Color(0.36, 0.26, 0.16, 1.0))
	time_sub_label.add_theme_font_size_override("font_size", 10)
	container.add_child(time_sub_label)

	return container


func _create_end_day_button() -> Button:
	var btn := Button.new()
	btn.text = "🌅 END DAY [N]"
	btn.add_theme_font_override("font", ThemeDB.fallback_font)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", COL_AMBER)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	btn.offset_left = -80
	btn.offset_right = 80
	btn.offset_top = 88
	btn.offset_bottom = 112
	btn.custom_minimum_size = Vector2(160, 24)
	btn.size = Vector2(160, 24)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.92)
	sb.border_color = COL_AMBER_DARK
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)

	var sb_hov: StyleBoxFlat = sb.duplicate()
	sb_hov.bg_color = Color(0.20, 0.24, 0.32, 0.98)
	sb_hov.border_color = COL_AMBER
	btn.add_theme_stylebox_override("hover", sb_hov)

	btn.pressed.connect(_on_end_day_btn_pressed)
	return btn


func _on_end_day_btn_pressed() -> void:
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and dnc.has_method("end_day_early"):
		dnc.end_day_early()


# ===========================================================================
# 3. Top-Right: Streak Counter & Multiplier Panel (167 x 171)
# ===========================================================================
func _create_streak_panel() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	container.offset_left = -187
	container.offset_right = -20
	container.offset_top = 14
	container.offset_bottom = 185
	container.custom_minimum_size = Vector2(167, 171)
	container.size = Vector2(167, 171)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HD Streak Clicker Background Texture
	var streak_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_streak_clicker_bg.png")
	container.add_child(streak_tex)

	# 4-Digit Odometer Display positioned precisely inside baked cutout slots (x:23, y:43, w:121, h:39)
	streak_counter = OdometerWidget.new()
	streak_counter.position = Vector2(23, 43)
	streak_counter.custom_minimum_size = Vector2(121, 39)
	streak_counter.size = Vector2(121, 39)
	container.add_child(streak_counter)

	# Multiplier Badge positioned precisely inside baked bottom amber box (x:22, y:114, w:122, h:33)
	mult_label = Label.new()
	mult_label.text = "MULT: ×1.0"
	mult_label.position = Vector2(22, 114)
	mult_label.size = Vector2(122, 33)
	mult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mult_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mult_label.add_theme_color_override("font_color", Color(0.14, 0.10, 0.05, 1.0))
	mult_label.add_theme_font_size_override("font_size", 15)
	container.add_child(mult_label)

	return container


# ===========================================================================
# 4. Bottom-Left: Inventory Slots (#1 - #4) (307 x 127)
# ===========================================================================
func _create_inventory_panel() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	container.offset_left = 24
	container.offset_right = 331
	container.offset_top = -147
	container.offset_bottom = -20
	container.custom_minimum_size = Vector2(307, 127)
	container.size = Vector2(307, 127)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HD Pack Caddy Background Texture
	var caddy_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_pack_caddy_bg.png")
	container.add_child(caddy_tex)

	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.position = Vector2(16, 16)
	hbox.custom_minimum_size = Vector2(276, 94)
	hbox.size = Vector2(276, 94)
	hbox.add_theme_constant_override("separation", 4)
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
# 5. Bottom-Right: Active Gear / Perks Panel (322 x 127)
# ===========================================================================
func _create_perks_panel() -> Control:
	var container := Control.new()
	container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	container.offset_left = -342
	container.offset_right = -20
	container.offset_top = -147
	container.offset_bottom = -20
	container.custom_minimum_size = Vector2(322, 127)
	container.size = Vector2(322, 127)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HD Equipped Rail Background Texture
	var rail_tex := UIAssets.create_texture_rect("res://UI/01_hud/hud_equipped_rail_bg.png")
	container.add_child(rail_tex)

	var hbox := HBoxContainer.new()
	hbox.position = Vector2(16, 16)
	hbox.custom_minimum_size = Vector2(290, 94)
	hbox.size = Vector2(290, 94)
	hbox.add_theme_constant_override("separation", 0)
	container.add_child(hbox)

	_perk_slot_widgets.clear()

	# Slot 0: Default Hi-Vis vest
	var slot_hivis := PerkSlotWidget.new()
	slot_hivis.set_perk("hivis_vest", "HI-VIS", "COMMON")
	slot_hivis.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot_hivis.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(slot_hivis)
	_perk_slot_widgets.append(slot_hivis)

	# Slot 1: Default Piggy bank
	var slot_piggy := PerkSlotWidget.new()
	slot_piggy.set_perk("piggy_jar", "PIGGY", "UNCOMMON")
	slot_piggy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot_piggy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(slot_piggy)
	_perk_slot_widgets.append(slot_piggy)

	# Slots 2, 3, 4: Empty slots
	for i in range(3):
		var slot_empty := PerkSlotWidget.new()
		slot_empty.set_empty()
		slot_empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(slot_empty)
		_perk_slot_widgets.append(slot_empty)

	return container


# ===========================================================================
# Public API & Updates
# ===========================================================================

func update_quota(current: float, target: float, unit: String = "KG") -> void:
	current_quota_val = current
	max_quota_val = maxf(1.0, target)
	quota_unit = unit

	if is_instance_valid(quota_val_label):
		var cur_int := int(current)
		var max_int := int(target)
		quota_val_label.text = "%03d / %d %s" % [cur_int, max_int, unit]

	if is_instance_valid(quota_progress_bar):
		var pct := clampf((current / max_quota_val) * 100.0, 0.0, 100.0)
		quota_progress_bar.value = pct
		if pct >= 100.0:
			quota_progress_bar.modulate = Color(0.6, 1.2, 0.7)
		else:
			quota_progress_bar.modulate = Color(1.0, 1.0, 1.0)


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
			slot.set_perk(perk_id, perk_id.to_upper(), "COMMON")


func update_streak(count: int) -> void:
	current_streak = count
	current_mult = 1.0 + float(count) * 0.1

	if is_instance_valid(streak_counter):
		streak_counter.set_value(current_streak)

	if is_instance_valid(mult_label):
		mult_label.text = "MULT: ×%.1f" % current_mult


func update_time_display(time_str: String, is_night: bool = false, is_quota_met: bool = false) -> void:
	if is_instance_valid(time_label):
		time_label.text = time_str
	if is_instance_valid(time_sub_label):
		if is_night:
			time_sub_label.text = "NIGHTFALL"
			time_sub_label.add_theme_color_override("font_color", Color(0.75, 0.25, 0.25))
		elif is_quota_met:
			time_sub_label.text = "QUOTA MET"
			time_sub_label.add_theme_color_override("font_color", Color(0.15, 0.55, 0.25))
		else:
			# Baked "UNTIL SUNSET" texture is visible, keep empty so no text clashes
			time_sub_label.text = ""


# ===========================================================================
# System Signal Callbacks
# ===========================================================================

func _on_player_item_bagged(item_id: String, value: float, total_sc: float) -> void:
	update_streak(current_streak + 1)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		_refresh_inventory_from_player(player)

	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc and dnc.has_method("get_daily_progress_amount"):
		var cur := float(dnc.get_daily_progress_amount())
		var tgt := float(dnc.get_current_quota())
		update_quota(cur, tgt, "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC")


func _on_dnc_time_updated(day_progress: float, hour: int, minute: int) -> void:
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		var remaining_seconds: float = maxf(0.0, dnc.day_duration_seconds - dnc.day_elapsed_seconds)
		var rem_min: int = int(remaining_seconds / 60.0)
		var rem_sec: int = int(remaining_seconds) % 60
		var time_str := "%02d:%02d" % [rem_min, rem_sec]
		update_time_display(time_str, dnc.is_night)

		var cur := float(dnc.get_daily_progress_amount())
		var tgt := float(dnc.get_current_quota())
		update_quota(cur, tgt, "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC")


func _on_dnc_day_started(day_number: int) -> void:
	update_streak(0)
	var dnc := get_tree().get_first_node_in_group("day_night_cycle")
	if dnc:
		update_quota(0.0, dnc.get_current_quota(), "KG" if dnc.quota_type == DayNightCycle.QuotaType.ITEM_COUNT else "SC")


func _on_dnc_night_started(day_number: int, quota_met: bool) -> void:
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
			var id_str: String = item_data.get("id", "trash").to_lower()
			if id_str.contains("can") or id_str.contains("metal"):
				slot_widget.set_item(InventorySlotWidget.ItemType.METAL, "METAL")
			elif id_str.contains("bottle") or id_str.contains("glass"):
				slot_widget.set_item(InventorySlotWidget.ItemType.GLASS, "GLASS")
			elif id_str.contains("plastic"):
				slot_widget.set_item(InventorySlotWidget.ItemType.PLASTIC, "PLASTIC")
			else:
				slot_widget.set_item(InventorySlotWidget.ItemType.OTHER, id_str.to_upper())
		else:
			slot_widget.set_empty()


# ===========================================================================
# Widgets
# ===========================================================================

## 4-Digit Odometer Flip Box [ 0 | 0 | 0 | 4 ] (121 x 39)
## Renders digit text directly inside the 4 slots cutout in hud_streak_clicker_bg.png
class OdometerWidget extends Control:
	var value: int = 4

	func _init() -> void:
		custom_minimum_size = Vector2(121, 39)
		size = Vector2(121, 39)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: int) -> void:
		value = v
		queue_redraw()

	func _draw() -> void:
		var slot_w := 28.0
		var gap := 3.0
		var font := ThemeDB.fallback_font
		var str_val := "%04d" % clampi(value, 0, 9999)

		for i in range(4):
			var pos := Vector2(float(i) * (slot_w + gap), 0)
			var is_active := (i == 3) or (int(str_val[i]) > 0)
			var char_col := Color(0.96, 0.62, 0.12, 1.0) if is_active else Color(0.40, 0.44, 0.50, 0.8)
			# Subtle center seam line across the digit
			draw_line(pos + Vector2(2, 19), pos + Vector2(slot_w - 2, 19), Color(0.04, 0.05, 0.06, 0.7), 1.0)
			draw_string(font, pos + Vector2(0, 26), str_val[i], HORIZONTAL_ALIGNMENT_CENTER, int(slot_w), 20, char_col)


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

		_bg_rect = UIAssets.create_texture_rect("res://UI/01_hud/hud_pack_slot_empty.png")
		_bg_rect.position = Vector2.ZERO
		_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg_rect)

		_num_label = Label.new()
		_num_label.text = "#%d" % slot_number
		_num_label.position = Vector2(4, 4)
		_num_label.size = Vector2(58, 14)
		_num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_num_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
		_num_label.add_theme_font_size_override("font_size", 9)
		add_child(_num_label)

		# Icon label rendered ON TOP of the background texture
		_icon_label = Label.new()
		_icon_label.text = ""
		_icon_label.position = Vector2(0, 18)
		_icon_label.size = Vector2(66, 48)
		_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_icon_label.add_theme_font_size_override("font_size", 24)
		add_child(_icon_label)

		_item_label = Label.new()
		_item_label.text = "EMPTY"
		_item_label.position = Vector2(0, 72)
		_item_label.size = Vector2(66, 16)
		_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_item_label.add_theme_color_override("font_color", Color(0.35, 0.40, 0.48, 1.0))
		_item_label.add_theme_font_size_override("font_size", 9)
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
					_item_label.add_theme_color_override("font_color", Color(0.20, 0.85, 0.40))
					if is_instance_valid(_icon_label): _icon_label.text = "🍾"
				ItemType.PLASTIC:
					_item_label.add_theme_color_override("font_color", Color(0.25, 0.65, 0.95))
					if is_instance_valid(_icon_label): _icon_label.text = "🧴"
				_:
					_item_label.add_theme_color_override("font_color", Color(0.90, 0.85, 0.70))
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
			_item_label.add_theme_color_override("font_color", Color(0.35, 0.40, 0.48, 1.0))


## Bottom-Right Active Gear / Perk Slot with HD gadget slot rarity textures (58 x 94)
class PerkSlotWidget extends Control:
	var perk_id: String = ""
	var perk_title: String = "EMPTY"
	var rarity: String = "COMMON"

	var _bg_rect: TextureRect = null
	var _icon_label: Label = null
	var _title_label: Label = null

	func _ready() -> void:
		custom_minimum_size = Vector2(58, 94)
		size = Vector2(58, 94)

		_bg_rect = UIAssets.create_texture_rect("res://UI/01_hud/hud_gadget_slot_common.png")
		_bg_rect.position = Vector2.ZERO
		_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg_rect)

		# Icon label rendered ON TOP of the background texture
		_icon_label = Label.new()
		_icon_label.text = ""
		_icon_label.position = Vector2(0, 16)
		_icon_label.size = Vector2(58, 48)
		_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_icon_label.add_theme_font_size_override("font_size", 26)
		add_child(_icon_label)

		_title_label = Label.new()
		_title_label.text = perk_title
		_title_label.position = Vector2(0, 72)
		_title_label.size = Vector2(58, 16)
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_label.add_theme_color_override("font_color", Color(0.40, 0.45, 0.52, 1.0))
		_title_label.add_theme_font_size_override("font_size", 9)
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
			_bg_rect.modulate = Color(0.5, 0.5, 0.5, 0.6)
			if is_instance_valid(_icon_label):
				_icon_label.text = ""
			if is_instance_valid(_title_label):
				_title_label.text = "EMPTY"
				_title_label.add_theme_color_override("font_color", Color(0.32, 0.36, 0.42))
		else:
			_bg_rect.modulate = Color.WHITE
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
					icon_char = "🛍️"
			if is_instance_valid(_icon_label):
				_icon_label.text = icon_char
			if is_instance_valid(_title_label):
				_title_label.text = perk_title
				_title_label.add_theme_color_override("font_color", Color(0.90, 0.88, 0.80))
