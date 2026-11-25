# day_night_cycle.gd
# Manages the 7-minute Day timer, smooth sun rotation & lighting,
# daily sunset collection quota, night pause state, and transitions.

class_name DayNightCycle
extends Node

signal day_started(day_number: int)
signal night_started(day_number: int, quota_met: bool)
signal time_updated(day_progress: float, hour: int, minute: int)
signal quota_achieved(target_amount: float)
signal quota_failed(collected_amount: float, target_amount: float)

# ---------------------------------------------------------------------------
# Timing Configuration
# ---------------------------------------------------------------------------
@export_group("Cycle Timing")
## Duration of daytime in seconds (default: 420.0s = 7 minutes)
@export var day_duration_seconds: float = 420.0
## Debug speed multiplier (1.0 = real-time 7 mins, 10.0 = 42 seconds for testing)
@export var debug_time_scale: float = 1.0
## Current day number
@export var current_day: int = 1
## Virtual clock hour at sunrise (e.g. 6.0 = 6:00 AM)
@export var sunrise_hour: float = 6.0
## Virtual clock hour when sunset begins (e.g. 19.5 = 7:30 PM)
@export var sunset_hour: float = 19.5

# ---------------------------------------------------------------------------
# Daily Sunset Collection Quota
# ---------------------------------------------------------------------------
@export_group("Daily Sunset Quota")
## Whether the player must collect a quota before sunset
@export var quota_enabled: bool = true

enum QuotaType { SLOP_CREDIT, ITEM_COUNT }
## Whether quota checks SlopCredit earned or total items bagged today
@export var quota_type: QuotaType = QuotaType.SLOP_CREDIT
## Base quota required on Day 1 (e.g. 15.0 SC or 15 items)
@export var base_quota: float = 15.0
## Additional quota required each subsequent day (Day 1: 15, Day 2: 20, etc.)
@export var quota_increase_per_day: float = 5.0

# ---------------------------------------------------------------------------
# Lighting Node References
# ---------------------------------------------------------------------------
@export_group("Lighting References")
## Explicit path to DirectionalLight3D (auto-detected if empty)
@export var sun_node_path: NodePath
## Explicit path to WorldEnvironment (auto-detected if empty)
@export var world_env_path: NodePath

# ---------------------------------------------------------------------------
# Internal State
# ---------------------------------------------------------------------------
var day_elapsed_seconds: float = 0.0
var is_night: bool = false
var _quota_toast_triggered: bool = false

var _sun: DirectionalLight3D = null
var _world_env: WorldEnvironment = null
var _procedural_sky: ProceduralSkyMaterial = null

# Cached original lighting
var _orig_sun_energy: float = 1.0
var _orig_sun_color: Color = Color(1.0, 1.0, 1.0)
var _orig_sky_top: Color = Color(0.35, 0.55, 0.85)
var _orig_sky_horizon: Color = Color(0.66, 0.67, 0.69)
var _orig_ground_horizon: Color = Color(0.66, 0.67, 0.69)
var _orig_sky_energy: float = 1.0

# UI References
var _canvas: CanvasLayer = null
var _hud_card: PanelContainer = null
var _hud_day_label: Label = null
var _hud_time_label: Label = null
var _hud_remaining_label: Label = null
var _hud_quota_label: Label = null
var _hud_day_progress: ProgressBar = null
var _hud_corner_next_btn: Button = null

var _night_modal: Control = null
var _night_title_label: Label = null
var _night_stats_label: Label = null
var _night_next_btn: Button = null
var _night_retry_btn: Button = null
var _night_pay_btn: Button = null
var _night_explore_btn: Button = null

var _fade_rect: ColorRect = null
var _fade_tween: Tween = null

# Quota / Contract Selection State
var is_waiting_for_day_start: bool = false
var custom_day_quota: float = -1.0
var quota_menu: CanvasLayer = null
var event_system: Node = null
var game_mode: int = 0 # 0 = Standard, 1 = Challenge
var _net_time_sync_accum: float = 0.0


func set_game_mode(mode: int) -> void:
	game_mode = mode
	if event_system and event_system.has_method("set_game_mode"):
		event_system.set_game_mode(mode)


func _ready() -> void:
	add_to_group("day_night_cycle")
	var es_script = preload("res://event_system.gd")
	event_system = es_script.new()
	event_system.dnc = self
	add_child(event_system)
	call_deferred("_setup_lighting_references")
	_setup_ui()
	var title = get_tree().get_first_node_in_group("title_screen")
	if title and is_instance_valid(title) and title.is_inside_tree() and title.visible:
		is_waiting_for_day_start = true
		_apply_lighting(0.0)
	else:
		emit_signal("day_started", current_day)
	print("DayNightCycle: Initialized. Day duration: %.1f seconds (~%.1f mins). Day 1 Quota: %.1f" % [day_duration_seconds, day_duration_seconds / 60.0, get_current_quota()])


func _setup_lighting_references() -> void:
	# 1. Resolve DirectionalLight3D
	if sun_node_path and has_node(sun_node_path):
		_sun = get_node(sun_node_path) as DirectionalLight3D
	else:
		_sun = _find_first_node_of_type(get_tree().current_scene, "DirectionalLight3D") as DirectionalLight3D

	if _sun:
		_orig_sun_energy = _sun.light_energy
		_orig_sun_color = _sun.light_color
		print("DayNightCycle: Found sun light '%s'" % _sun.name)
	else:
		push_warning("DayNightCycle: No DirectionalLight3D found in scene!")

	# 2. Resolve WorldEnvironment
	if world_env_path and has_node(world_env_path):
		_world_env = get_node(world_env_path) as WorldEnvironment
	else:
		_world_env = _find_first_node_of_type(get_tree().current_scene, "WorldEnvironment") as WorldEnvironment

	if _world_env and _world_env.environment:
		var env := _world_env.environment
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			_procedural_sky = env.sky.sky_material as ProceduralSkyMaterial
			_orig_sky_top = _procedural_sky.sky_top_color
			_orig_sky_horizon = _procedural_sky.sky_horizon_color
			_orig_ground_horizon = _procedural_sky.ground_horizon_color
			_orig_sky_energy = _procedural_sky.sky_energy_multiplier
			print("DayNightCycle: Found ProceduralSkyMaterial in WorldEnvironment")

	# Initial day lighting
	_apply_lighting(0.0)


func _find_first_node_of_type(root: Node, type_str: String) -> Node:
	if not root:
		return null
	if root.is_class(type_str):
		return root
	for child in root.get_children():
		var found := _find_first_node_of_type(child, type_str)
		if found:
			return found
	return null


## Calculates the required quota for the current day
func get_current_quota() -> float:
	if custom_day_quota >= 0.0:
		return custom_day_quota
	return maxf(1.0, base_quota + float(current_day - 1) * quota_increase_per_day)


## Reads current daily progress from player
func get_daily_progress_amount() -> float:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		if quota_type == QuotaType.SLOP_CREDIT and "daily_sc_earned" in player:
			return float(player.daily_sc_earned)
		elif quota_type == QuotaType.ITEM_COUNT and "daily_items_bagged" in player:
			return float(player.daily_items_bagged)
	return 0.0


func _process(delta: float) -> void:
	# Only pause time if a menu (TitleScreen or QuotaMenu) is actively open and visible
	if is_waiting_for_day_start:
		var has_menu := false
		if is_instance_valid(quota_menu) and quota_menu.is_inside_tree() and quota_menu.visible:
			has_menu = true
		var title = get_tree().get_first_node_in_group("title_screen")
		if title and is_instance_valid(title) and title.is_inside_tree() and title.visible:
			has_menu = true

		if has_menu:
			_apply_lighting(0.0)
			return
		else:
			is_waiting_for_day_start = false

	if not is_night:
		if NetworkManager.is_host():
			day_elapsed_seconds += delta * debug_time_scale
			if NetworkManager.is_multiplayer_active():
				_net_time_sync_accum += delta
				if _net_time_sync_accum >= 0.5:
					_net_time_sync_accum = 0.0
					_rpc_sync_time.rpc(current_day, day_elapsed_seconds, is_night, is_waiting_for_day_start, custom_day_quota)
		else:
			# Clients smoothly advance locally between host sync snapshots
			day_elapsed_seconds = minf(day_elapsed_seconds + delta * debug_time_scale, day_duration_seconds)

		var progress: float = clampf(day_elapsed_seconds / day_duration_seconds, 0.0, 1.0)
		_apply_lighting(progress)
		_update_hud(progress)

		# Check if quota achieved mid-day for toast feedback
		if quota_enabled and not _quota_toast_triggered:
			var collected := get_daily_progress_amount()
			var target := get_current_quota()
			if collected >= target:
				_quota_toast_triggered = true
				emit_signal("quota_achieved", target)
				var player := get_tree().get_first_node_in_group("player")
				if player and player.has_method("_show_feedback"):
					player._show_feedback("🎉 Sunset Quota Met! (%.1f reached)" % collected)

		if NetworkManager.is_host() and day_elapsed_seconds >= day_duration_seconds:
			trigger_night()
	else:
		_update_night_lighting()
		_update_hud(1.0)


# ===========================================================================
# Lighting & Sun Rotation
# ===========================================================================

func _apply_lighting(progress: float) -> void:
	# Check if Evernight boss event is active
	if event_system and event_system.is_event_active and event_system.active_event_id == "evernight":
		_apply_evernight_lighting()
		var clock_hour_e: float = lerpf(sunrise_hour, sunset_hour, progress)
		var h_int: int = int(clock_hour_e)
		var m_int: int = int((clock_hour_e - h_int) * 60.0)
		emit_signal("time_updated", progress, h_int, m_int)
		return

	# Calculate virtual clock hour
	var clock_hour: float = lerpf(sunrise_hour, sunset_hour, progress)
	var hour_int: int = int(clock_hour)
	var minute_int: int = int((clock_hour - hour_int) * 60.0)
	emit_signal("time_updated", progress, hour_int, minute_int)

	# Sun rotation across the sky (East to West)
	if _sun:
		var pitch_deg: float = -15.0 - (60.0 * sin(progress * PI))
		var yaw_deg: float = lerpf(-80.0, 80.0, progress)
		_sun.rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)

		# Color & intensity shifts
		var sun_col: Color
		var sun_energy: float
		if progress < 0.2:
			# Sunrise transition
			var t := progress / 0.2
			sun_col = Color(1.0, 0.72, 0.45).lerp(Color(1.0, 0.98, 0.92), t)
			sun_energy = lerpf(0.6 * _orig_sun_energy, _orig_sun_energy, t)
		elif progress < 0.75:
			# Midday sun
			sun_col = Color(1.0, 0.98, 0.92)
			sun_energy = _orig_sun_energy * 1.1
		else:
			# Sunset / Golden hour transition
			var t := (progress - 0.75) / 0.25
			sun_col = Color(1.0, 0.98, 0.92).lerp(Color(1.0, 0.45, 0.2), t)
			sun_energy = lerpf(_orig_sun_energy * 1.1, 0.2 * _orig_sun_energy, t)

		_sun.light_color = sun_col
		_sun.light_energy = sun_energy

	# Procedural sky tint (restore normal sky when not in Evernight)
	if _world_env and _world_env.environment:
		_world_env.environment.fog_enabled = false
		_world_env.environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	if _procedural_sky:
		_procedural_sky.sky_top_color = _orig_sky_top
		_procedural_sky.ground_horizon_color = _orig_ground_horizon
		if progress < 0.2:
			var t := progress / 0.2
			_procedural_sky.sky_horizon_color = Color(0.9, 0.55, 0.4).lerp(_orig_sky_horizon, t)
			_procedural_sky.sky_energy_multiplier = lerpf(0.7, _orig_sky_energy, t)
		elif progress > 0.75:
			var t := (progress - 0.75) / 0.25
			_procedural_sky.sky_horizon_color = _orig_sky_horizon.lerp(Color(0.85, 0.4, 0.25), t)
			_procedural_sky.sky_energy_multiplier = lerpf(_orig_sky_energy, 0.4, t)
		else:
			_procedural_sky.sky_horizon_color = _orig_sky_horizon
			_procedural_sky.sky_energy_multiplier = _orig_sky_energy


func _apply_evernight_lighting() -> void:
	if _sun:
		_sun.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(45.0), 0.0)
		_sun.light_color = Color(0.95, 0.12, 0.14) # Menacing crimson sun
		_sun.light_energy = 0.55
	if _procedural_sky:
		_procedural_sky.sky_top_color = Color(0.18, 0.01, 0.03)
		_procedural_sky.sky_horizon_color = Color(0.62, 0.06, 0.08)
		_procedural_sky.ground_horizon_color = Color(0.45, 0.05, 0.07)
		_procedural_sky.sky_energy_multiplier = 0.65
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_color = Color(0.75, 0.12, 0.15)
		_world_env.environment.fog_enabled = true
		_world_env.environment.fog_light_color = Color(0.48, 0.05, 0.08)
		_world_env.environment.fog_density = 0.012


func _update_night_lighting() -> void:
	if _sun:
		# Moonlight
		_sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(120.0), 0.0)
		_sun.light_color = Color(0.3, 0.45, 0.75)
		_sun.light_energy = 0.14

	if _procedural_sky:
		_procedural_sky.sky_top_color = Color(0.04, 0.06, 0.12)
		_procedural_sky.sky_horizon_color = Color(0.08, 0.12, 0.22)
		_procedural_sky.sky_energy_multiplier = 0.22


# ===========================================================================
# Night & Quota Settlement Flow
# ===========================================================================

## Ends the current daytime immediately and triggers sunset / night settlement
func end_day_early() -> void:
	if is_night or is_waiting_for_day_start:
		return
	print("DayNightCycle: Player ended day %d early!" % current_day)
	day_elapsed_seconds = day_duration_seconds
	trigger_night()


func trigger_night() -> void:
	if is_night:
		return
	if NetworkManager.is_multiplayer_active() and NetworkManager.is_host():
		_rpc_trigger_night.rpc()
	_do_trigger_night()


@rpc("authority", "call_remote", "reliable")
func _rpc_trigger_night() -> void:
	_do_trigger_night()


func _do_trigger_night() -> void:
	if is_night:
		return
	is_night = true

	# Read daily stats from player
	var items_today: int = 0
	var sc_today: float = 0.0
	var total_sc: float = 0.0

	var player := get_tree().get_first_node_in_group("player")
	if player:
		if "daily_items_bagged" in player:
			items_today = player.daily_items_bagged
		if "daily_sc_earned" in player:
			sc_today = player.daily_sc_earned
		if "slop_credit" in player:
			total_sc = player.slop_credit

	var target_quota: float = get_current_quota()
	var current_collected: float = sc_today if quota_type == QuotaType.SLOP_CREDIT else float(items_today)
	var quota_passed: bool = (not quota_enabled) or (current_collected >= target_quota)

	emit_signal("night_started", current_day, quota_passed)

	var unit_str: String = "SC" if quota_type == QuotaType.SLOP_CREDIT else "items"

	if quota_passed:
		# SUCCESS CASE
		if _night_title_label:
			_night_title_label.text = "🌙 NIGHT HAS FALLEN\n✅ Day %d Quota Met!" % current_day
			_night_title_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55, 1.0))

		if _night_stats_label:
			_night_stats_label.text = "🧺 Trash Bagged Today: %d items\n🪙 Daily Earnings: +%.1f SC\n🎯 Quota: %.1f %s (PASSED!)\n💰 Total SlopCredit: %.1f SC" % [items_today, sc_today, target_quota, unit_str, total_sc]

		if _night_next_btn:
			_night_next_btn.text = "☀️ Start Next Day (Day %d)" % (current_day + 1)
			_night_next_btn.visible = true

		if _night_retry_btn:
			_night_retry_btn.visible = false
		if _night_pay_btn:
			_night_pay_btn.visible = false
		if _hud_corner_next_btn:
			_hud_corner_next_btn.visible = true

		print("DayNightCycle: Quota PASSED (%.1f / %.1f %s). Ready for Next Day." % [current_collected, target_quota, unit_str])
	else:
		# FAILURE CASE
		emit_signal("quota_failed", current_collected, target_quota)
		var shortfall: float = target_quota - current_collected

		if _night_title_label:
			_night_title_label.text = "🌙 SUNSET ARRIVED\n❌ Day %d Quota Failed!" % current_day
			_night_title_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))

		if _night_stats_label:
			_night_stats_label.text = "🧺 Trash Bagged Today: %d items\n🪙 Daily Earnings: +%.1f SC\n🎯 Required Quota: %.1f %s\n⚠️ Short by: %.1f %s!\n💰 Total SlopCredit: %.1f SC" % [items_today, sc_today, target_quota, unit_str, shortfall, unit_str, total_sc]

		if _night_next_btn:
			_night_next_btn.visible = false

		if _night_retry_btn:
			_night_retry_btn.text = "🔄 Retry Day %d" % current_day
			_night_retry_btn.visible = true

		# Allow paying off the deficit if player has enough accumulated SlopCredit
		if _night_pay_btn:
			if quota_type == QuotaType.SLOP_CREDIT and total_sc >= shortfall:
				_night_pay_btn.text = "💸 Pay Shortfall (-%.1f SC) & Continue" % shortfall
				_night_pay_btn.visible = true
			else:
				_night_pay_btn.visible = false

		if _hud_corner_next_btn:
			_hud_corner_next_btn.visible = false

		print("DayNightCycle: Quota FAILED (%.1f / %.1f %s). Player must retry or pay shortfall." % [current_collected, target_quota, unit_str])

	_show_night_modal()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func advance_to_next_day() -> void:
	if NetworkManager.is_multiplayer_active() and NetworkManager.is_host():
		_rpc_advance_to_next_day.rpc()
	_do_advance_to_next_day()


@rpc("authority", "call_remote", "reliable")
func _rpc_advance_to_next_day() -> void:
	_do_advance_to_next_day()


func _do_advance_to_next_day() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_rect.visible = true
	_fade_rect.modulate.a = 0.0

	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "modulate:a", 1.0, 0.5)
	_fade_tween.tween_callback(Callable(self, "_on_fade_black_complete"))
	_fade_tween.tween_property(_fade_rect, "modulate:a", 0.0, 0.6)
	_fade_tween.tween_callback(Callable(self, "_on_fade_in_complete"))


func retry_current_day() -> void:
	if NetworkManager.is_multiplayer_active() and NetworkManager.is_host():
		_rpc_retry_current_day.rpc()
	_do_retry_current_day()


@rpc("authority", "call_remote", "reliable")
func _rpc_retry_current_day() -> void:
	_do_retry_current_day()


func _do_retry_current_day() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_rect.visible = true
	_fade_rect.modulate.a = 0.0

	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "modulate:a", 1.0, 0.5)
	_fade_tween.tween_callback(Callable(self, "_on_fade_retry_complete"))
	_fade_tween.tween_property(_fade_rect, "modulate:a", 0.0, 0.6)
	_fade_tween.tween_callback(Callable(self, "_on_fade_in_complete"))


func pay_shortfall_and_advance() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and "slop_credit" in player:
		var target := get_current_quota()
		var collected := get_daily_progress_amount()
		var shortfall := target - collected
		if player.has_method("spend_slop_credit"):
			player.spend_slop_credit(shortfall)
		else:
			player.slop_credit -= shortfall
	advance_to_next_day()


func _on_fade_black_complete() -> void:
	current_day += 1
	day_elapsed_seconds = 0.0
	is_night = false
	_quota_toast_triggered = false
	custom_day_quota = -1.0

	if event_system:
		event_system.cleanup_event_entities()

	# Reset player daily stats
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("on_new_day_started"):
		player.on_new_day_started()

	_hide_night_modal()
	if _hud_corner_next_btn:
		_hud_corner_next_btn.visible = false

	_apply_lighting(0.0)
	call_deferred("open_quota_selection")


func _on_fade_retry_complete() -> void:
	day_elapsed_seconds = 0.0
	is_night = false
	_quota_toast_triggered = false

	if event_system:
		event_system.cleanup_event_entities()

	# Reset player daily stats for retry
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("on_day_retried"):
		player.on_day_retried()

	_hide_night_modal()
	if _hud_corner_next_btn:
		_hud_corner_next_btn.visible = false

	_apply_lighting(0.0)
	call_deferred("open_quota_selection")


## Opens the Quota/Quest selection screen before the day begins
func open_quota_selection() -> void:
	is_waiting_for_day_start = true
	_apply_lighting(0.0)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if is_instance_valid(quota_menu):
		quota_menu.queue_free()

	var qm_script = load("res://quota_menu.gd")
	if qm_script:
		var qm = qm_script.new()
		qm.day_started.connect(_on_quota_selection_confirmed)
		get_tree().current_scene.add_child(qm)
		quota_menu = qm


func _on_quota_selection_confirmed(contract_data: Dictionary) -> void:
	is_waiting_for_day_start = false
	quota_menu = null

	if contract_data.get("is_boss", false) and event_system:
		event_system.start_event(contract_data.get("id", ""))
		if contract_data.get("id", "") == "evernight":
			_apply_evernight_lighting()

	emit_signal("day_started", current_day)



func _on_fade_in_complete() -> void:
	_fade_rect.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _show_night_modal() -> void:
	if _night_modal:
		_night_modal.visible = true
		_night_modal.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_night_modal, "modulate:a", 1.0, 0.4)


func _hide_night_modal() -> void:
	if _night_modal:
		_night_modal.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if is_night:
		if event is InputEventKey and event.pressed and not event.echo:
			# If quota was met, Space / Enter starts next day
			var collected := get_daily_progress_amount()
			var target := get_current_quota()
			var quota_passed: bool = (not quota_enabled) or (collected >= target)

			if quota_passed:
				if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
					advance_to_next_day()
			else:
				# If quota failed, Space / Enter retries the day
				if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
					retry_current_day()

			if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
				if _night_modal and _night_modal.visible:
					_hide_night_modal()
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ===========================================================================
# UI Construction (HUD Clock, Quota Bar, Night Settlement Modal)
# ===========================================================================

func _setup_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "DayNightUI"
	add_child(_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(root)

	# 1. Top-Right Day/Clock/Quota HUD Card (Replaced by industrial GameHUD)
	_hud_card = PanelContainer.new()
	_hud_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_card.position = Vector2(-235, 24)
	_hud_card.size = Vector2(215, 96)
	_hud_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_card.visible = false

	var card_bg := StyleBoxFlat.new()
	card_bg.bg_color = Color(0.06, 0.08, 0.12, 0.8)
	card_bg.border_color = Color(0.25, 0.35, 0.48, 0.7)
	card_bg.set_border_width_all(2)
	card_bg.corner_radius_top_left = 8
	card_bg.corner_radius_top_right = 8
	card_bg.corner_radius_bottom_left = 8
	card_bg.corner_radius_bottom_right = 8
	card_bg.content_margin_left = 12
	card_bg.content_margin_top = 8
	card_bg.content_margin_right = 12
	card_bg.content_margin_bottom = 8
	_hud_card.add_theme_stylebox_override("panel", card_bg)
	root.add_child(_hud_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_hud_card.add_child(vbox)

	var hbox_top := HBoxContainer.new()
	vbox.add_child(hbox_top)

	_hud_day_label = Label.new()
	_hud_day_label.text = "☀️ Day 1"
	_hud_day_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3, 1.0))
	_hud_day_label.add_theme_font_size_override("font_size", 16)
	hbox_top.add_child(_hud_day_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_top.add_child(spacer)

	_hud_time_label = Label.new()
	_hud_time_label.text = "06:00 AM"
	_hud_time_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.9))
	_hud_time_label.add_theme_font_size_override("font_size", 14)
	hbox_top.add_child(_hud_time_label)

	_hud_remaining_label = Label.new()
	_hud_remaining_label.text = "07:00 remaining"
	_hud_remaining_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 0.75))
	_hud_remaining_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_hud_remaining_label)

	# Day progression bar
	_hud_day_progress = ProgressBar.new()
	_hud_day_progress.custom_minimum_size = Vector2(188, 4)
	_hud_day_progress.show_percentage = false
	_hud_day_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_day_progress.min_value = 0.0
	_hud_day_progress.max_value = 1.0

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.12, 0.16, 0.8)
	_hud_day_progress.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(1.0, 0.75, 0.25, 0.9)
	_hud_day_progress.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(_hud_day_progress)

	# Quota label under progress bar
	_hud_quota_label = Label.new()
	_hud_quota_label.text = "🎯 Quota: 0.0 / 15.0 SC"
	_hud_quota_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28, 0.95))
	_hud_quota_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_hud_quota_label)

	# Corner persistent Next Day button (visible at night if quota passed)
	_hud_corner_next_btn = Button.new()
	_hud_corner_next_btn.text = "☀️ Next Day"
	_hud_corner_next_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_corner_next_btn.position = Vector2(-235, 130)
	_hud_corner_next_btn.size = Vector2(215, 32)
	_hud_corner_next_btn.visible = false
	_hud_corner_next_btn.pressed.connect(Callable(self, "advance_to_next_day"))
	root.add_child(_hud_corner_next_btn)

	# 2. Night Settlement Modal (Centered)
	_night_modal = PanelContainer.new()
	_night_modal.set_anchors_preset(Control.PRESET_CENTER)
	_night_modal.position = Vector2(-200, -165)
	_night_modal.size = Vector2(400, 330)
	_night_modal.visible = false

	var modal_bg := StyleBoxFlat.new()
	modal_bg.bg_color = Color(0.05, 0.07, 0.11, 0.94)
	modal_bg.border_color = Color(0.3, 0.45, 0.65, 0.8)
	modal_bg.set_border_width_all(2)
	modal_bg.corner_radius_top_left = 12
	modal_bg.corner_radius_top_right = 12
	modal_bg.corner_radius_bottom_left = 12
	modal_bg.corner_radius_bottom_right = 12
	modal_bg.content_margin_left = 24
	modal_bg.content_margin_top = 20
	modal_bg.content_margin_right = 24
	modal_bg.content_margin_bottom = 20
	_night_modal.add_theme_stylebox_override("panel", modal_bg)
	root.add_child(_night_modal)

	var m_vbox := VBoxContainer.new()
	m_vbox.add_theme_constant_override("separation", 12)
	_night_modal.add_child(m_vbox)

	_night_title_label = Label.new()
	_night_title_label.text = "🌙 NIGHT HAS FALLEN\nDay 1 Complete"
	_night_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_night_title_label.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0, 1.0))
	_night_title_label.add_theme_font_size_override("font_size", 20)
	m_vbox.add_child(_night_title_label)

	_night_stats_label = Label.new()
	_night_stats_label.text = "🧺 Trash Bagged Today: 0\n🪙 SlopCredit Earned Today: +0.0 SC\n💰 Total SlopCredit: 0.0 SC"
	_night_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_night_stats_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.9))
	_night_stats_label.add_theme_font_size_override("font_size", 14)
	m_vbox.add_child(_night_stats_label)

	# Next Day Button (Enabled on success)
	_night_next_btn = Button.new()
	_night_next_btn.text = "☀️ Start Next Day"
	_night_next_btn.custom_minimum_size = Vector2(0, 42)
	_night_next_btn.add_theme_font_size_override("font_size", 16)
	_night_next_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	_night_next_btn.pressed.connect(Callable(self, "advance_to_next_day"))
	m_vbox.add_child(_night_next_btn)

	# Retry Day Button (Visible on quota failure)
	_night_retry_btn = Button.new()
	_night_retry_btn.text = "🔄 Retry Day"
	_night_retry_btn.custom_minimum_size = Vector2(0, 40)
	_night_retry_btn.add_theme_font_size_override("font_size", 15)
	_night_retry_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45, 1.0))
	_night_retry_btn.visible = false
	_night_retry_btn.pressed.connect(Callable(self, "retry_current_day"))
	m_vbox.add_child(_night_retry_btn)

	# Pay Shortfall Button (Visible on failure if player has enough total balance)
	_night_pay_btn = Button.new()
	_night_pay_btn.text = "💸 Pay Shortfall & Continue"
	_night_pay_btn.custom_minimum_size = Vector2(0, 34)
	_night_pay_btn.add_theme_font_size_override("font_size", 13)
	_night_pay_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1.0))
	_night_pay_btn.visible = false
	_night_pay_btn.pressed.connect(Callable(self, "pay_shortfall_and_advance"))
	m_vbox.add_child(_night_pay_btn)

	_night_explore_btn = Button.new()
	_night_explore_btn.text = "Explore in the Dark (Dismiss)"
	_night_explore_btn.custom_minimum_size = Vector2(0, 26)
	_night_explore_btn.add_theme_font_size_override("font_size", 12)
	_night_explore_btn.pressed.connect(Callable(self, "_on_explore_night_pressed"))
	m_vbox.add_child(_night_explore_btn)

	# 3. Fullscreen Fade Transition Rect
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	root.add_child(_fade_rect)


func _on_explore_night_pressed() -> void:
	_hide_night_modal()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _update_hud(progress: float) -> void:
	if not is_instance_valid(_hud_day_label):
		return

	var collected := get_daily_progress_amount()
	var target := get_current_quota()
	var unit_str := "SC" if quota_type == QuotaType.SLOP_CREDIT else "items"

	# Update Quota Display
	if is_instance_valid(_hud_quota_label):
		if not quota_enabled:
			_hud_quota_label.text = "Quota: Disabled"
			_hud_quota_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.7))
		elif collected >= target:
			if quota_type == QuotaType.SLOP_CREDIT:
				_hud_quota_label.text = "✅ Quota Met: %.1f / %.1f SC" % [collected, target]
			else:
				_hud_quota_label.text = "✅ Quota Met: %d / %d items" % [int(collected), int(target)]
			_hud_quota_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55, 1.0))
		else:
			var pct: int = int(clampf(collected / target, 0.0, 1.0) * 100.0)
			if quota_type == QuotaType.SLOP_CREDIT:
				_hud_quota_label.text = "🎯 Quota: %.1f / %.1f SC (%d%%)" % [collected, target, pct]
			else:
				_hud_quota_label.text = "🎯 Quota: %d / %d (%d%%)" % [int(collected), int(target), pct]
			_hud_quota_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28, 0.95))

	if not is_night:
		_hud_day_label.text = "☀️ Day %d" % current_day
		_hud_day_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3, 1.0))

		var clock_hour: float = lerpf(sunrise_hour, sunset_hour, progress)
		var hour_int: int = int(clock_hour)
		var minute_int: int = int((clock_hour - hour_int) * 60.0)
		var am_pm: String = "AM" if hour_int < 12 else "PM"
		var display_hour: int = hour_int if hour_int <= 12 else hour_int - 12
		if display_hour == 0:
			display_hour = 12

		_hud_time_label.text = "%02d:%02d %s" % [display_hour, minute_int, am_pm]

		var remaining_seconds: float = maxf(0.0, day_duration_seconds - day_elapsed_seconds)
		var rem_min: int = int(remaining_seconds / 60.0)
		var rem_sec: int = int(remaining_seconds) % 60
		_hud_remaining_label.text = "%02d:%02d remaining" % [rem_min, rem_sec]

		_hud_day_progress.value = progress
	else:
		_hud_day_label.text = "🌙 Night %d" % current_day
		_hud_day_label.add_theme_color_override("font_color", Color(0.45, 0.75, 1.0, 1.0))
		_hud_time_label.text = "Nightfall"
		_hud_remaining_label.text = "Waiting for Next Day"
		_hud_day_progress.value = 1.0


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_time(p_day: int, p_elapsed: float, p_is_night: bool, p_waiting: bool, p_custom_quota: float) -> void:
	current_day = p_day
	day_elapsed_seconds = p_elapsed
	is_night = p_is_night
	is_waiting_for_day_start = p_waiting
	custom_day_quota = p_custom_quota
