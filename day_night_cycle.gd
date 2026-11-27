# day_night_cycle.gd
# Manages the 7-minute Day timer, smooth sun rotation & Evernight/night lighting,
# daily sunset collection quota, multiplayer RPC sync, and Figma 05_modals Win & Game Over screens.

class_name DayNightCycle
extends Node

const UIAssets = preload("res://ui_assets.gd")

signal day_started(day_number: int)
signal night_started(day_number: int, quota_met: bool)
signal time_updated(day_progress: float, hour: int, minute: int)
signal quota_achieved(target_amount: float)
signal quota_failed(collected_amount: float, target_amount: float)

const MAX_DAYS: int = 8

# ---------------------------------------------------------------------------
# Timing Configuration
# ---------------------------------------------------------------------------
@export_group("Cycle Timing")
@export var day_duration_seconds: float = 420.0
@export var debug_time_scale: float = 1.0
@export var current_day: int = 1
@export var sunrise_hour: float = 6.0
@export var sunset_hour: float = 19.5

# ---------------------------------------------------------------------------
# Daily Sunset Collection Quota
# ---------------------------------------------------------------------------
@export_group("Daily Sunset Quota")
@export var quota_enabled: bool = true

enum QuotaType { SLOP_CREDIT, ITEM_COUNT }
@export var quota_type: QuotaType = QuotaType.SLOP_CREDIT
@export var base_quota: float = 15.0
@export var quota_increase_per_day: float = 5.0

# ---------------------------------------------------------------------------
# Lighting Node References
# ---------------------------------------------------------------------------
@export_group("Lighting References")
@export var sun_node_path: NodePath
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

var _orig_sun_energy: float = 1.0
var _orig_sun_color: Color = Color(1.0, 1.0, 1.0)
var _orig_sky_top: Color = Color(0.35, 0.55, 0.85)
var _orig_sky_horizon: Color = Color(0.66, 0.67, 0.69)
var _orig_ground_horizon: Color = Color(0.66, 0.67, 0.69)
var _orig_sky_energy: float = 1.0

# UI References
var _canvas: CanvasLayer = null
var _fade_canvas: CanvasLayer = null
var _hud_card: PanelContainer = null
var _hud_day_label: Label = null
var _hud_time_label: Label = null
var _hud_remaining_label: Label = null
var _hud_quota_label: Label = null
var _hud_day_progress: ProgressBar = null
var _hud_corner_next_btn: Button = null

var _night_modal: Control = null
var _win_root: Control = null
var _lose_root: Control = null

var _win_header_label: Label = null
var _win_sub_label: Label = null
var _win_big_earn_label: Label = null
var _win_row_vals: Array[Label] = []

var _lose_sub_label: Label = null
var _lose_deficit_label: Label = null
var _lose_deficit_bar: TextureProgressBar = null
var _lose_row_vals: Array[Label] = []

# Preserved button references for backwards compatibility
var _night_next_btn: Button = null
var _night_retry_btn: Button = null
var _night_pay_btn: Button = null
var _night_explore_btn: Button = null

var _fade_rect: ColorRect = null
var _fade_tween: Tween = null

# Quota / Contract Selection & Event State
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
	UIAssets.load_and_apply_settings()
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
	UIAssets.sync_bgm()
	print("DayNightCycle: Initialized. Day duration: %.1f seconds (~%.1f mins). Day 1 Quota: %.1f" % [day_duration_seconds, day_duration_seconds / 60.0, get_current_quota()])


func get_music_state() -> String:
	if is_instance_valid(_night_modal) and _night_modal.visible:
		if is_instance_valid(_lose_root) and _lose_root.visible:
			return "fail"
		if is_instance_valid(_win_root) and _win_root.visible:
			return "win"
	if event_system != null and event_system.is_event_active:
		return "boss"
	return "gameplay"


func _setup_lighting_references() -> void:
	if sun_node_path and has_node(sun_node_path):
		_sun = get_node(sun_node_path) as DirectionalLight3D
	else:
		_sun = _find_first_node_of_type(get_tree().current_scene, "DirectionalLight3D") as DirectionalLight3D

	if _sun:
		_orig_sun_energy = _sun.light_energy
		_orig_sun_color = _sun.light_color
	else:
		push_warning("DayNightCycle: No DirectionalLight3D found in scene!")

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


func get_current_quota() -> float:
	if custom_day_quota >= 0.0:
		return custom_day_quota
	return maxf(1.0, base_quota + float(current_day - 1) * quota_increase_per_day)


func get_daily_progress_amount() -> float:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		if quota_type == QuotaType.SLOP_CREDIT and "daily_sc_earned" in player:
			return float(player.daily_sc_earned)
		elif quota_type == QuotaType.ITEM_COUNT and "daily_items_bagged" in player:
			return float(player.daily_items_bagged)
	return 0.0


func _process(delta: float) -> void:
	if is_waiting_for_day_start:
		var has_menu := false
		if is_instance_valid(quota_menu) and not quota_menu.is_queued_for_deletion() and quota_menu.is_inside_tree() and quota_menu.visible:
			has_menu = true
		var title = get_tree().get_first_node_in_group("title_screen")
		if title and is_instance_valid(title) and not title.is_queued_for_deletion() and title.is_inside_tree() and title.visible:
			has_menu = true

		if has_menu:
			_apply_lighting(0.0)
			return
		else:
			is_waiting_for_day_start = false

	var is_host := (NetworkManager == null) or NetworkManager.is_host()
	var is_mp := (NetworkManager != null) and NetworkManager.is_multiplayer_active()

	if not is_night:
		if is_host:
			day_elapsed_seconds += delta * debug_time_scale
			if is_mp:
				_net_time_sync_accum += delta
				if _net_time_sync_accum >= 0.5:
					_net_time_sync_accum = 0.0
					_rpc_sync_time.rpc(current_day, day_elapsed_seconds, is_night, is_waiting_for_day_start, custom_day_quota)
		else:
			day_elapsed_seconds = minf(day_elapsed_seconds + delta * debug_time_scale, day_duration_seconds)

		var progress: float = clampf(day_elapsed_seconds / day_duration_seconds, 0.0, 1.0)
		_apply_lighting(progress)
		_update_hud(progress)

		if quota_enabled and not _quota_toast_triggered:
			var collected := get_daily_progress_amount()
			var target := get_current_quota()
			if collected >= target:
				_quota_toast_triggered = true
				emit_signal("quota_achieved", target)
				var player := get_tree().get_first_node_in_group("player")
				if player and player.has_method("_show_feedback"):
					player._show_feedback("🎉 Sunset Quota Met! (%.1f reached)" % collected)

		if is_host and day_elapsed_seconds >= day_duration_seconds:
			trigger_night()
	else:
		_update_night_lighting()
		_update_hud(1.0)


# ===========================================================================
# Lighting & Sun Rotation (100% Preserved from 3e26359)
# ===========================================================================

func _apply_lighting(progress: float) -> void:
	if event_system and event_system.is_event_active and event_system.active_event_id == "evernight":
		_apply_evernight_lighting()
		var clock_hour_e: float = lerpf(sunrise_hour, sunset_hour, progress)
		var h_int: int = int(clock_hour_e)
		var m_int: int = int((clock_hour_e - h_int) * 60.0)
		emit_signal("time_updated", progress, h_int, m_int)
		return

	var clock_hour: float = lerpf(sunrise_hour, sunset_hour, progress)
	var hour_int: int = int(clock_hour)
	var minute_int: int = int((clock_hour - hour_int) * 60.0)
	emit_signal("time_updated", progress, hour_int, minute_int)

	if _sun:
		var pitch_deg: float = -15.0 - (60.0 * sin(progress * PI))
		var yaw_deg: float = lerpf(-80.0, 80.0, progress)
		_sun.rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)

		var sun_col: Color
		var sun_energy: float
		if progress < 0.2:
			var t := progress / 0.2
			sun_col = Color(1.0, 0.72, 0.45).lerp(Color(1.0, 0.98, 0.92), t)
			sun_energy = lerpf(0.6 * _orig_sun_energy, _orig_sun_energy, t)
		elif progress < 0.75:
			sun_col = Color(1.0, 0.98, 0.92)
			sun_energy = _orig_sun_energy * 1.1
		else:
			var t := (progress - 0.75) / 0.25
			sun_col = Color(1.0, 0.98, 0.92).lerp(Color(1.0, 0.45, 0.2), t)
			sun_energy = lerpf(_orig_sun_energy * 1.1, 0.2 * _orig_sun_energy, t)

		_sun.light_color = sun_col
		_sun.light_energy = sun_energy

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
		_sun.light_color = Color(0.95, 0.12, 0.14)
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
		_sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(120.0), 0.0)
		_sun.light_color = Color(0.3, 0.45, 0.75)
		_sun.light_energy = 0.14

	if _procedural_sky:
		_procedural_sky.sky_top_color = Color(0.04, 0.06, 0.12)
		_procedural_sky.sky_horizon_color = Color(0.08, 0.12, 0.22)
		_procedural_sky.sky_energy_multiplier = 0.22


# ===========================================================================
# Night & Quota Settlement Flow (100% Preserved RPCs + Figma 05_modals Endings)
# ===========================================================================

func end_day_early() -> void:
	if is_night or is_waiting_for_day_start:
		return
	if event_system != null and event_system.is_event_active and not event_system.is_event_completed:
		var player := get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and player.has_method("_show_feedback"):
			if event_system.active_event_id == "expedition":
				player._show_feedback("🚩 Plant the Ranger Flag at the Summit Peak first!")
			else:
				player._show_feedback("⚠️ Complete the active event first!")
		return
	print("DayNightCycle: Player ended day %d early!" % current_day)
	day_elapsed_seconds = day_duration_seconds
	trigger_night()


func trigger_night() -> void:
	if is_night:
		return
	if NetworkManager != null and NetworkManager.is_multiplayer_active() and NetworkManager.is_host():
		_rpc_trigger_night.rpc()
	_do_trigger_night()


@rpc("authority", "call_remote", "reliable")
func _rpc_trigger_night() -> void:
	_do_trigger_night()


func _do_trigger_night() -> void:
	if is_night:
		return
	is_night = true

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
	if event_system != null and event_system.is_event_active and not event_system.is_event_completed:
		quota_passed = false

	emit_signal("night_started", current_day, quota_passed)

	if quota_passed:
		_populate_win_screen(items_today, sc_today, current_collected, target_quota, total_sc)
	else:
		emit_signal("quota_failed", current_collected, target_quota)
		_populate_lose_screen(items_today, sc_today, current_collected, target_quota, total_sc)

	_show_night_modal()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _populate_win_screen(items_today: int, sc_today: float, collected: float, target: float, total_sc: float) -> void:
	var unit_str := "SC" if quota_type == QuotaType.SLOP_CREDIT else "KG"
	if is_instance_valid(_win_root):
		_win_root.visible = true
	if is_instance_valid(_lose_root):
		_lose_root.visible = false

	var is_final := (current_day >= MAX_DAYS)
	if is_instance_valid(_win_header_label):
		_win_header_label.text = "MOUNTAIN CLEARED!" if is_final else "SHIFT COMPLETE!"
	if is_instance_valid(_win_sub_label):
		_win_sub_label.text = "Laporan Shift — Hari %d dari %d" % [current_day, MAX_DAYS]
	if is_instance_valid(_win_big_earn_label):
		_win_big_earn_label.text = "+$%.1f SC" % sc_today

	var vals := [
		"%d ITEM" % items_today,
		"+$%.1f SC" % sc_today,
		"%.1f / %.1f %s  ✓" % [collected, target, unit_str],
		"$%.1f SC" % total_sc,
	]
	for i in range(min(vals.size(), _win_row_vals.size())):
		if is_instance_valid(_win_row_vals[i]):
			_win_row_vals[i].text = vals[i]

	if is_instance_valid(_night_next_btn):
		_night_next_btn.text = "LANJUT DAY %d  ➔" % (current_day + 1)
		_night_next_btn.visible = true
	if is_instance_valid(_night_retry_btn):
		_night_retry_btn.visible = false
	if is_instance_valid(_night_pay_btn):
		_night_pay_btn.visible = false
	if is_instance_valid(_hud_corner_next_btn):
		_hud_corner_next_btn.visible = true


func _populate_lose_screen(items_today: int, sc_today: float, collected: float, target: float, total_sc: float) -> void:
	var unit_str := "SC" if quota_type == QuotaType.SLOP_CREDIT else "KG"
	var shortfall: float = maxf(0.0, target - collected)
	var pct: float = clampf((collected / maxf(1.0, target)) * 100.0, 0.0, 100.0)

	if is_instance_valid(_win_root):
		_win_root.visible = false
	if is_instance_valid(_lose_root):
		_lose_root.visible = true

	if is_instance_valid(_lose_sub_label):
		_lose_sub_label.text = "Penutupan Sementara — Hari %d dari %d" % [current_day, MAX_DAYS]
	if is_instance_valid(_lose_deficit_label):
		_lose_deficit_label.text = "%.1f / %.1f %s (%d%%)" % [collected, target, unit_str, int(pct)]
	if is_instance_valid(_lose_deficit_bar):
		_lose_deficit_bar.value = pct

	var vals := [
		"%d ITEM" % items_today,
		"+$%.1f SC" % sc_today,
		"-%.1f %s" % [shortfall, unit_str],
		"$%.1f SC" % total_sc,
	]
	for i in range(min(vals.size(), _lose_row_vals.size())):
		if is_instance_valid(_lose_row_vals[i]):
			_lose_row_vals[i].text = vals[i]

	if is_instance_valid(_night_next_btn):
		_night_next_btn.visible = false
	if is_instance_valid(_night_retry_btn):
		_night_retry_btn.text = "COBA LAGI (DAY %d)  ➔" % current_day
		_night_retry_btn.visible = true
	if is_instance_valid(_night_pay_btn):
		if quota_type == QuotaType.SLOP_CREDIT and total_sc >= shortfall and shortfall > 0.0:
			_night_pay_btn.text = "BAYAR DEFISIT (-$%.1f SC)" % shortfall
			_night_pay_btn.visible = true
		else:
			_night_pay_btn.visible = false
	if is_instance_valid(_hud_corner_next_btn):
		_hud_corner_next_btn.visible = false


## Preview helpers for visual verification in Godot
func preview_win_screen(items: int = 18, sc_today: float = 24.5, target: float = 15.0, total_sc: float = 38.0) -> void:
	is_night = true
	_populate_win_screen(items, sc_today, sc_today, target, total_sc)
	_show_night_modal(false)


func preview_gameover_screen(items: int = 4, sc_today: float = 6.0, target: float = 15.0, total_sc: float = 22.0) -> void:
	is_night = true
	_populate_lose_screen(items, sc_today, sc_today, target, total_sc)
	_show_night_modal(false)


func advance_to_next_day() -> void:
	if NetworkManager != null and NetworkManager.is_multiplayer_active() and NetworkManager.is_host():
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
	if NetworkManager != null and NetworkManager.is_multiplayer_active() and NetworkManager.is_host():
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
		var shortfall := maxf(0.0, target - collected)
		if player.has_method("spend_slop_credit"):
			player.spend_slop_credit(shortfall)
		else:
			player.slop_credit -= shortfall
	advance_to_next_day()


func _go_to_main_menu() -> void:
	if NetworkManager != null and NetworkManager.is_multiplayer_active():
		NetworkManager.leave_game()
	_hide_night_modal()
	is_waiting_for_day_start = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var existing_title = get_tree().get_first_node_in_group("title_screen")
	if not existing_title and get_tree().current_scene:
		var ts_script = load("res://title_screen.gd")
		if ts_script:
			var ts = ts_script.new()
			get_tree().current_scene.add_child(ts)


func _on_fade_black_complete() -> void:
	current_day += 1
	day_elapsed_seconds = 0.0
	is_night = false
	_quota_toast_triggered = false
	custom_day_quota = -1.0

	if event_system:
		event_system.cleanup_event_entities()

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

	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("on_day_retried"):
		player.on_day_retried()

	_hide_night_modal()
	if _hud_corner_next_btn:
		_hud_corner_next_btn.visible = false

	_apply_lighting(0.0)
	call_deferred("open_quota_selection")


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


## Fixed: Never recapture cursor while Contract Board / Night Ending is active!
func _on_fade_in_complete() -> void:
	_fade_rect.visible = false
	var menu_open := is_waiting_for_day_start \
		or (is_instance_valid(quota_menu) and not quota_menu.is_queued_for_deletion()) \
		or (_night_modal != null and _night_modal.visible)
	if menu_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _show_night_modal(animate: bool = true) -> void:
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud:
		hud.visible = false
	if _night_modal:
		_night_modal.visible = true
		if animate:
			_night_modal.modulate.a = 0.0
			var tw := create_tween()
			tw.tween_property(_night_modal, "modulate:a", 1.0, 0.35)
		else:
			_night_modal.modulate.a = 1.0
	UIAssets.sync_bgm()


func _hide_night_modal() -> void:
	if _night_modal:
		_night_modal.visible = false
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud and not is_waiting_for_day_start:
		hud.visible = true
	UIAssets.sync_bgm()


func _unhandled_input(event: InputEvent) -> void:
	if is_night and _night_modal and _night_modal.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var collected := get_daily_progress_amount()
			var target := get_current_quota()
			var quota_passed: bool = (not quota_enabled) or (collected >= target)

			if quota_passed:
				if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
					advance_to_next_day()
			else:
				if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
					retry_current_day()

			if event.keycode == KEY_ESCAPE or event.keycode == KEY_TAB:
				_hide_night_modal()
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ===========================================================================
# UI Construction (Legacy Hidden HUD Card + Figma 05_modals Win / Game Over)
# ===========================================================================

func _setup_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "DayNightUI"
	_canvas.layer = 30
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(root)

	# 1. Legacy Top-Right HUD Card (kept hidden for script compatibility)
	_hud_card = PanelContainer.new()
	_hud_card.visible = false
	_hud_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud_card)

	var vbox := VBoxContainer.new()
	_hud_card.add_child(vbox)
	_hud_day_label = Label.new()
	_hud_time_label = Label.new()
	_hud_remaining_label = Label.new()
	_hud_day_progress = ProgressBar.new()
	_hud_quota_label = Label.new()
	vbox.add_child(_hud_day_label)
	vbox.add_child(_hud_time_label)
	vbox.add_child(_hud_remaining_label)
	vbox.add_child(_hud_day_progress)
	vbox.add_child(_hud_quota_label)

	# Corner persistent Next Day button (visible at night if player explores in dark)
	_hud_corner_next_btn = UIAssets.create_wood_button(
		"res://UI/05_modals/btn_modal_blue_wood.png",
		"LANJUT HARI  ➔", 13, Color(0.20, 0.12, 0.05), "", "black", 4
	)
	_hud_corner_next_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_corner_next_btn.offset_left = -224
	_hud_corner_next_btn.offset_right = -18
	_hud_corner_next_btn.offset_top = 194
	_hud_corner_next_btn.offset_bottom = 250
	_hud_corner_next_btn.custom_minimum_size = Vector2(206, 56)
	_hud_corner_next_btn.visible = false
	_hud_corner_next_btn.pressed.connect(Callable(self, "advance_to_next_day"))
	root.add_child(_hud_corner_next_btn)

	# 2. Full-Screen Night Settlement / Win & Game Over Screens (1280 x 720, Figma 05_modals)
	_night_modal = Control.new()
	_night_modal.name = "NightSettlementModal"
	_night_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_night_modal.visible = false
	root.add_child(_night_modal)

	var modal_bg := ColorRect.new()
	modal_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_bg.color = Color(0.04, 0.05, 0.08, 1.0)
	_night_modal.add_child(modal_bg)

	var modal_content := UIAssets.create_canvas_root(_night_modal, "ResultCanvas")

	# --- A. WIN / SHIFT COMPLETE VIEW ---
	_win_root = Control.new()
	_win_root.name = "WinScreen"
	_win_root.size = Vector2(1280, 720)
	_win_root.visible = false
	modal_content.add_child(_win_root)

	var win_bg := UIAssets.create_texture_rect("res://UI/05_modals/bg_win_sunrise.png")
	win_bg.position = Vector2.ZERO
	win_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_root.add_child(win_bg)

	var win_hdr := UIAssets.create_texture_rect("res://UI/05_modals/header_slab_gold_win.png")
	win_hdr.position = Vector2(400, 26)
	win_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_root.add_child(win_hdr)

	_win_header_label = UIAssets.create_label(
		"SHIFT COMPLETE!", 24, Color.WHITE, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.55
	)
	_win_header_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_hdr.add_child(_win_header_label)

	# Victory Certificate Torn Paper (PNG 612x534, logical 580x492 at (350, 108))
	var win_paper_tex := UIAssets.create_texture_rect("res://UI/05_modals/paper_cert_win_empty.png")
	win_paper_tex.position = Vector2(334, 92)
	win_paper_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_root.add_child(win_paper_tex)

	var win_paper := Control.new()
	win_paper.position = Vector2(350, 108)
	win_paper.size = Vector2(580, 492)
	_win_root.add_child(win_paper)

	_win_sub_label = UIAssets.create_label(
		"Laporan Shift — Hari 1 dari 8", 18, Color(0.24, 0.16, 0.08), "extrabold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	_win_sub_label.position = Vector2(32, 30)
	_win_sub_label.size = Vector2(516, 28)
	win_paper.add_child(_win_sub_label)

	_win_big_earn_label = UIAssets.create_label("+$0.0 SC", 38, UIAssets.COL_GREEN, "black")
	_win_big_earn_label.position = Vector2(36, 102)
	_win_big_earn_label.size = Vector2(310, 52)
	win_paper.add_child(_win_big_earn_label)

	# Authentic Angled Green Rubber Ink Stamp (Matching Figma Stamp-Shift-Selesai 188:88)
	var stamp_ink := Color(0.114, 0.369, 0.220)
	var win_stamp := Panel.new()
	win_stamp.position = Vector2(390, 108)
	win_stamp.size = Vector2(154, 34)
	win_stamp.pivot_offset = win_stamp.size * 0.5
	win_stamp.rotation_degrees = -2.0
	var wssb := StyleBoxFlat.new()
	wssb.bg_color = Color(0.114, 0.369, 0.220, 0.10)
	wssb.border_color = stamp_ink
	wssb.set_border_width_all(2)
	wssb.set_corner_radius_all(0)
	win_stamp.add_theme_stylebox_override("panel", wssb)
	win_paper.add_child(win_stamp)

	var ws_lbl := UIAssets.create_label(
		"✓  LULUS KUOTA", 13, stamp_ink, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	ws_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_stamp.add_child(ws_lbl)

	# 4 Victory Stats Rows (aligned to ruled paper lines)
	_win_row_vals.clear()
	var win_keys := ["Sampah Terkumpul", "Hasil Hari Ini", "Target Kuota", "Total Saldo"]
	var win_ys := [218.0, 266.0, 314.0, 362.0]
	for i in range(4):
		var k_lbl := UIAssets.create_label(win_keys[i], 13, UIAssets.COL_INK_MUTED, "bold")
		k_lbl.position = Vector2(36, win_ys[i])
		k_lbl.size = Vector2(220, 24)
		win_paper.add_child(k_lbl)

		var v_col := UIAssets.COL_GREEN if i == 2 else (Color(0.68, 0.44, 0.04) if i == 3 else UIAssets.COL_INK)
		var v_lbl := UIAssets.create_label("-", 15, v_col, "black", HORIZONTAL_ALIGNMENT_RIGHT)
		v_lbl.position = Vector2(256, win_ys[i])
		v_lbl.size = Vector2(288, 24)
		win_paper.add_child(v_lbl)
		_win_row_vals.append(v_lbl)

	# Win Bottom Buttons
	_night_next_btn = UIAssets.create_wood_button(
		"res://UI/05_modals/btn_ending_blue_wood.png",
		"LANJUT DAY 2  ➔", 16, Color(0.20, 0.12, 0.05), "", "black", 5
	)
	_night_next_btn.position = Vector2(334, 616)
	_night_next_btn.pressed.connect(Callable(self, "advance_to_next_day"))
	_win_root.add_child(_night_next_btn)

	var win_menu_btn := UIAssets.create_wood_button(
		"res://UI/05_modals/btn_ending_brown_wood.png",
		"MAIN MENU", 16, UIAssets.COL_CREAM, "", "black", 5
	)
	win_menu_btn.position = Vector2(634, 616)
	win_menu_btn.pressed.connect(Callable(self, "_go_to_main_menu"))
	_win_root.add_child(win_menu_btn)

	# Subtle Explore button top-right
	_night_explore_btn = Button.new()
	_night_explore_btn.text = "Explore Malam [TAB]"
	_night_explore_btn.position = Vector2(1070, 28)
	_night_explore_btn.size = Vector2(180, 32)
	_night_explore_btn.flat = true
	_night_explore_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_night_explore_btn.add_theme_font_override("font", UIAssets.get_font("mono"))
	_night_explore_btn.add_theme_font_size_override("font_size", 11)
	_night_explore_btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 0.80))
	_night_explore_btn.pressed.connect(Callable(self, "_on_explore_night_pressed"))
	_win_root.add_child(_night_explore_btn)

	# --- B. GAME OVER / PARK CLOSED VIEW ---
	_lose_root = Control.new()
	_lose_root.name = "GameOverScreen"
	_lose_root.size = Vector2(1280, 720)
	_lose_root.visible = false
	modal_content.add_child(_lose_root)

	var lose_bg := UIAssets.create_texture_rect("res://UI/05_modals/bg_gameover_closed.png")
	lose_bg.position = Vector2.ZERO
	lose_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lose_root.add_child(lose_bg)

	var lose_hdr := UIAssets.create_texture_rect("res://UI/05_modals/header_slab_hazard_lose.png")
	lose_hdr.position = Vector2(400, 26)
	lose_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lose_root.add_child(lose_hdr)

	var lose_hdr_lbl := UIAssets.create_label(
		"PARK CLOSED", 24, Color.WHITE, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.55
	)
	lose_hdr_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lose_hdr.add_child(lose_hdr_lbl)

	# Crimson Failure Notice Paper (PNG 612x534, logical 580x492 at (350, 108))
	var lose_paper_tex := UIAssets.create_texture_rect("res://UI/05_modals/paper_notice_lose_empty.png")
	lose_paper_tex.position = Vector2(334, 92)
	lose_paper_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lose_root.add_child(lose_paper_tex)

	var lose_paper := Control.new()
	lose_paper.position = Vector2(350, 108)
	lose_paper.size = Vector2(580, 492)
	_lose_root.add_child(lose_paper)

	_lose_sub_label = UIAssets.create_label(
		"Penutupan Sementara — Hari 1 dari 8", 18, UIAssets.COL_CRIMSON, "extrabold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	_lose_sub_label.position = Vector2(32, 30)
	_lose_sub_label.size = Vector2(516, 28)
	lose_paper.add_child(_lose_sub_label)

	# Bolted Quota Deficit Progress Tank (516 x 64)
	var def_bg := UIAssets.create_texture_rect("res://UI/05_modals/quota_deficit_bar_bg.png")
	def_bg.position = Vector2(32, 86)
	def_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lose_paper.add_child(def_bg)

	var def_title := UIAssets.create_label("Progres Kuota", 11, Color(0.82, 0.84, 0.88), "bold")
	def_title.position = Vector2(20, 8)
	def_title.size = Vector2(220, 16)
	def_bg.add_child(def_title)

	_lose_deficit_label = UIAssets.create_label(
		"0.0 / 15.0 SC (0%)", 11, UIAssets.COL_CRIMSON_HI, "bold",
		HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER
	)
	_lose_deficit_label.position = Vector2(246, 8)
	_lose_deficit_label.size = Vector2(250, 16)
	def_bg.add_child(_lose_deficit_label)

	_lose_deficit_bar = TextureProgressBar.new()
	_lose_deficit_bar.position = Vector2(20, 34)
	_lose_deficit_bar.size = Vector2(476, 14)
	_lose_deficit_bar.min_value = 0.0
	_lose_deficit_bar.max_value = 100.0
	_lose_deficit_bar.value = 0.0
	_lose_deficit_bar.texture_progress = UIAssets.get_tex("res://UI/05_modals/quota_deficit_bar_fill.png")
	def_bg.add_child(_lose_deficit_bar)

	# 4 Failure Stats Rows (aligned to ruled paper lines)
	_lose_row_vals.clear()
	var lose_keys := ["Sampah Terkumpul", "Hasil Hari Ini", "Kekurangan Kuota", "Total Saldo"]
	var lose_ys := [218.0, 266.0, 314.0, 362.0]
	for i in range(4):
		var k_lbl := UIAssets.create_label(lose_keys[i], 13, UIAssets.COL_INK_MUTED, "bold")
		k_lbl.position = Vector2(36, lose_ys[i])
		k_lbl.size = Vector2(220, 24)
		lose_paper.add_child(k_lbl)

		var v_col := UIAssets.COL_CRIMSON if i == 2 else UIAssets.COL_INK
		var v_lbl := UIAssets.create_label("-", 15, v_col, "black", HORIZONTAL_ALIGNMENT_RIGHT)
		v_lbl.position = Vector2(256, lose_ys[i])
		v_lbl.size = Vector2(288, 24)
		lose_paper.add_child(v_lbl)
		_lose_row_vals.append(v_lbl)

	# Optional Pay Shortfall Button inside paper footer
	_night_pay_btn = UIAssets.create_wood_button(
		"res://UI/05_modals/btn_ending_blue_wood.png",
		"BAYAR DEFISIT & LANJUT", 14, Color(0.20, 0.12, 0.05), "", "black", 5
	)
	_night_pay_btn.position = Vector2(134, 396)
	_night_pay_btn.visible = false
	_night_pay_btn.pressed.connect(Callable(self, "pay_shortfall_and_advance"))
	lose_paper.add_child(_night_pay_btn)

	# Lose Bottom Buttons
	_night_retry_btn = UIAssets.create_wood_button(
		"res://UI/05_modals/btn_ending_red_wood.png",
		"COBA LAGI (DAY 1)  ➔", 16, Color.WHITE, "", "black", 5
	)
	_night_retry_btn.position = Vector2(334, 616)
	_night_retry_btn.pressed.connect(Callable(self, "retry_current_day"))
	_lose_root.add_child(_night_retry_btn)

	var lose_menu_btn := UIAssets.create_wood_button(
		"res://UI/05_modals/btn_ending_brown_wood.png",
		"MAIN MENU", 16, UIAssets.COL_CREAM, "", "black", 5
	)
	lose_menu_btn.position = Vector2(634, 616)
	lose_menu_btn.pressed.connect(Callable(self, "_go_to_main_menu"))
	_lose_root.add_child(lose_menu_btn)

	# 3. Fullscreen Fade Transition Layer (on top of everything)
	_fade_canvas = CanvasLayer.new()
	_fade_canvas.name = "DayNightFadeLayer"
	_fade_canvas.layer = 90
	_fade_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fade_canvas)

	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	_fade_canvas.add_child(_fade_rect)


func _on_explore_night_pressed() -> void:
	_hide_night_modal()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _update_hud(progress: float) -> void:
	if not is_instance_valid(_hud_day_label):
		return

	var collected := get_daily_progress_amount()
	var target := get_current_quota()

	if is_instance_valid(_hud_quota_label):
		if not quota_enabled:
			_hud_quota_label.text = "Quota: Disabled"
		elif collected >= target:
			_hud_quota_label.text = "✅ Quota Met: %.1f / %.1f" % [collected, target]
		else:
			var pct: int = int(clampf(collected / maxf(1.0, target), 0.0, 1.0) * 100.0)
			_hud_quota_label.text = "🎯 Quota: %.1f / %.1f (%d%%)" % [collected, target, pct]

	if not is_night:
		_hud_day_label.text = "☀️ Day %d" % current_day
		_hud_day_progress.value = progress
	else:
		_hud_day_label.text = "🌙 Night %d" % current_day
		_hud_day_progress.value = 1.0


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_sync_time(p_day: int, p_elapsed: float, p_is_night: bool, p_waiting: bool, p_custom_quota: float) -> void:
	current_day = p_day
	day_elapsed_seconds = p_elapsed
	is_night = p_is_night
	is_waiting_for_day_start = p_waiting
	custom_day_quota = p_custom_quota
