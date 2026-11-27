# ui_assets.gd
# Centralized loader, bundled font registry, wood-plank button factory, and settings store
# for SlopMountain UI textures in res://UI/

class_name UIAssets

static var _cache: Dictionary = {}
static var _font_cache: Dictionary = {}

# Shared palette matching Figma SlopMountain Ranger / Scrapbook aesthetic
const COL_CREAM       := Color(0.96, 0.94, 0.87, 1.0)
const COL_CREAM_DARK  := Color(0.84, 0.79, 0.69, 1.0)
const COL_INK         := Color(0.12, 0.14, 0.17, 1.0)
const COL_INK_MUTED   := Color(0.36, 0.32, 0.27, 1.0)
const COL_AMBER       := Color(0.96, 0.75, 0.22, 1.0)
const COL_GOLD        := Color(0.98, 0.82, 0.28, 1.0)
const COL_GREEN       := Color(0.18, 0.56, 0.28, 1.0)
const COL_GREEN_LIGHT := Color(0.38, 0.88, 0.50, 1.0)
const COL_CRIMSON     := Color(0.76, 0.18, 0.16, 1.0)
const COL_CRIMSON_HI  := Color(0.98, 0.38, 0.34, 1.0)
const COL_BLUE_INK    := Color(0.16, 0.42, 0.66, 1.0)

const SETTINGS_PATH := "user://slopmountain_settings.cfg"

const RESOLUTION_PRESETS := [
	{"key": "1280x720",  "short": "720p",  "label": "1280×720",  "size": Vector2i(1280, 720)},
	{"key": "1366x768",  "short": "768p",  "label": "1366×768",  "size": Vector2i(1366, 768)},
	{"key": "1920x1080", "short": "1080p", "label": "1920×1080", "size": Vector2i(1920, 1080)},
]

static var _settings_loaded: bool = false
static var settings: Dictionary = {
	"master_vol": 0.85,
	"music_vol": 0.75,
	"sfx_vol": 0.90,
	"fullscreen": false,
	"resolution": "1280x720",
	"screen_shake": true,
}


# ---------------------------------------------------------------------------
# Texture & Font Loading
# ---------------------------------------------------------------------------

## Loads or retrieves a cached Texture2D from res://UI/...
## Supports both normal ResourceLoader and direct FileAccess/Image fallback.
static func get_tex(res_path: String) -> Texture2D:
	if _cache.has(res_path):
		return _cache[res_path]

	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		var res = load(res_path)
		if res is Texture2D:
			tex = res

	if tex == null:
		var global_p := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(global_p):
			var img := Image.load_from_file(global_p)
			if img and not img.is_empty():
				tex = ImageTexture.create_from_image(img)

	if tex != null:
		_cache[res_path] = tex
	return tex


## Loads a bundled Rubik typography face ("black", "extrabold", "bold", "semibold")
## Note: "mono" intentionally maps to Rubik-Bold so zero AI-style monospace fonts appear in-game.
static func get_font(style: String = "bold") -> Font:
	if _font_cache.has(style):
		return _font_cache[style]

	var path_map := {
		"black": "res://UI/fonts/Rubik-Black.ttf",
		"extrabold": "res://UI/fonts/Rubik-ExtraBold.ttf",
		"bold": "res://UI/fonts/Rubik-Bold.ttf",
		"semibold": "res://UI/fonts/Rubik-SemiBold.ttf",
		"mono": "res://UI/fonts/Rubik-Bold.ttf",
	}
	var res_path: String = path_map.get(style, "res://UI/fonts/Rubik-Bold.ttf")
	var font: Font = null

	if ResourceLoader.exists(res_path):
		var res = load(res_path)
		if res is Font:
			font = res

	if font == null:
		var global_p := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(global_p):
			var ff := FontFile.new()
			if ff.load_dynamic_font(global_p) == OK:
				font = ff

	if font == null:
		font = ThemeDB.fallback_font

	_font_cache[style] = font
	return font


## Checks for an optional custom card pixel-art PNG at res://UI/03_cards/art/<id>.png
static func get_card_art(item_id: String) -> Texture2D:
	var candidates := [
		"res://UI/03_cards/art/%s.png" % item_id,
		"res://UI/03_cards/art/card_%s.png" % item_id,
	]
	for p in candidates:
		var tex := get_tex(p)
		if tex != null:
			return tex
	return null


# ---------------------------------------------------------------------------
# Control Builders
# ---------------------------------------------------------------------------

## Creates a TextureRect that strictly preserves native texture dimensions and aspect ratio
static func create_texture_rect(res_path: String, expand: bool = false) -> TextureRect:
	var tr := TextureRect.new()
	if expand:
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		tr.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP
	var tex := get_tex(res_path)
	tr.texture = tex
	if tex and not expand:
		tr.custom_minimum_size = tex.get_size()
		tr.size = tex.get_size()
	return tr


## Styled Label helper with bundled font + optional crisp shadow
static func create_label(
	text: String,
	font_size: int = 14,
	color: Color = COL_CREAM,
	font_style: String = "bold",
	h_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	v_align: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER,
	shadow_alpha: float = 0.0
) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = h_align
	lbl.vertical_alignment = v_align
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", get_font(font_style))
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if shadow_alpha > 0.0:
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, shadow_alpha))
		lbl.add_theme_constant_override("shadow_offset_x", 0)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	return lbl


## Styled wrapped Label helper — sets autowrap & box size BEFORE text so Godot wraps cleanly
static func create_wrapped_label(
	text: String,
	pos: Vector2,
	box_size: Vector2,
	font_size: int = 12,
	color: Color = COL_INK,
	font_style: String = "semibold",
	h_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	v_align: VerticalAlignment = VERTICAL_ALIGNMENT_TOP
) -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.clip_text = false
	lbl.position = pos
	lbl.custom_minimum_size = box_size
	lbl.size = box_size
	lbl.horizontal_alignment = h_align
	lbl.vertical_alignment = v_align
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", get_font(font_style))
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.text = text
	return lbl


## Backward-compatible textured button matching Fahri's 6-arg signature
static func create_textured_button(
	res_path: String,
	title_text: String = "",
	font_size: int = 15,
	font_col: Color = Color.WHITE,
	hover_path: String = "",
	custom_size: Vector2 = Vector2.ZERO
) -> Button:
	var btn := create_wood_button(res_path, title_text, font_size, font_col, hover_path, "black", 4)
	if custom_size != Vector2.ZERO:
		btn.custom_minimum_size = custom_size
		btn.size = custom_size
	return btn


## Dedicated helper for buttons with explicit normal and hover texture paths
static func create_hover_button(
	normal_path: String,
	hover_path: String,
	title_text: String = "",
	font_size: int = 15,
	font_col: Color = Color.WHITE,
	custom_size: Vector2 = Vector2.ZERO
) -> Button:
	return create_textured_button(normal_path, title_text, font_size, font_col, hover_path, custom_size)


## Creates a wooden-plank Button supporting separate normal & hover PNGs and shadow-padding centering
static func create_wood_button(
	normal_path: String,
	title_text: String = "",
	font_size: int = 16,
	font_col: Color = COL_CREAM,
	hover_path: String = "",
	font_style: String = "black",
	bottom_inset: int = 4
) -> Button:
	var btn := Button.new()
	btn.text = title_text
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", get_font(font_style))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", Color.WHITE if font_col.get_luminance() > 0.35 else font_col)
	btn.add_theme_color_override("font_pressed_color", font_col.darkened(0.12))
	btn.add_theme_color_override("font_disabled_color", Color(0.62, 0.58, 0.52, 0.85))
	btn.add_theme_color_override("font_focus_color", font_col)

	if font_col.get_luminance() > 0.35:
		btn.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.50))
		btn.add_theme_constant_override("shadow_offset_x", 0)
		btn.add_theme_constant_override("shadow_offset_y", 2)

	var tex := get_tex(normal_path)
	var hov_tex := get_tex(hover_path) if hover_path != "" else null
	if tex:
		var tex_sz := tex.get_size()
		btn.custom_minimum_size = tex_sz
		btn.size = tex_sz

		var sb_norm := StyleBoxTexture.new()
		sb_norm.texture = tex
		sb_norm.content_margin_bottom = bottom_inset
		btn.add_theme_stylebox_override("normal", sb_norm)

		var sb_hov := StyleBoxTexture.new()
		sb_hov.texture = hov_tex if hov_tex != null else tex
		if hov_tex == null:
			sb_hov.modulate_color = Color(1.10, 1.08, 1.04, 1.0)
		sb_hov.content_margin_bottom = bottom_inset
		btn.add_theme_stylebox_override("hover", sb_hov)

		var sb_press := StyleBoxTexture.new()
		sb_press.texture = hov_tex if hov_tex != null else tex
		sb_press.modulate_color = Color(0.86, 0.84, 0.82, 1.0)
		sb_press.content_margin_top = 2
		sb_press.content_margin_bottom = max(0, bottom_inset - 2)
		btn.add_theme_stylebox_override("pressed", sb_press)

		var sb_dis := StyleBoxTexture.new()
		sb_dis.texture = tex
		sb_dis.modulate_color = Color(0.62, 0.60, 0.58, 0.85)
		sb_dis.content_margin_bottom = bottom_inset
		btn.add_theme_stylebox_override("disabled", sb_dis)

		var sb_foc := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override("focus", sb_foc)

	return btn


## Creates a 1280x720 centered canvas wrapper inside a full-rect Control
static func create_canvas_root(parent: Node, root_name: String = "UIRoot") -> Control:
	var root := Control.new()
	root.name = root_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)

	var content := Control.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.offset_left = -640
	content.offset_right = 640
	content.offset_top = -360
	content.offset_bottom = 360
	content.custom_minimum_size = Vector2(1280, 720)
	content.size = Vector2(1280, 720)
	content.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(content)
	return content


# ---------------------------------------------------------------------------
# Persistent Settings (Audio Buses, Fullscreen, Screen Shake)
# ---------------------------------------------------------------------------

static func ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


static func _get_resolution_size(res_key: String) -> Vector2i:
	for preset in RESOLUTION_PRESETS:
		if preset["key"] == res_key:
			return preset["size"]
	return Vector2i(1280, 720)


static func _is_valid_resolution(res_key: String) -> bool:
	for preset in RESOLUTION_PRESETS:
		if preset["key"] == res_key:
			return true
	return false


static func load_and_apply_settings() -> void:
	ensure_audio_buses()
	if not _settings_loaded:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			settings["master_vol"] = clampf(float(cfg.get_value("audio", "master_vol", 0.85)), 0.0, 1.0)
			settings["music_vol"] = clampf(float(cfg.get_value("audio", "music_vol", 0.75)), 0.0, 1.0)
			settings["sfx_vol"] = clampf(float(cfg.get_value("audio", "sfx_vol", 0.90)), 0.0, 1.0)
			settings["fullscreen"] = bool(cfg.get_value("display", "fullscreen", false))
			var saved_res := str(cfg.get_value("display", "resolution", "1280x720"))
			settings["resolution"] = saved_res if _is_valid_resolution(saved_res) else "1280x720"
			settings["screen_shake"] = bool(cfg.get_value("gameplay", "screen_shake", true))
		_settings_loaded = true
	apply_settings()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_vol", settings["master_vol"])
	cfg.set_value("audio", "music_vol", settings["music_vol"])
	cfg.set_value("audio", "sfx_vol", settings["sfx_vol"])
	cfg.set_value("display", "fullscreen", settings["fullscreen"])
	cfg.set_value("display", "resolution", settings.get("resolution", "1280x720"))
	cfg.set_value("gameplay", "screen_shake", settings["screen_shake"])
	cfg.save(SETTINGS_PATH)


static func apply_settings() -> void:
	ensure_audio_buses()
	_apply_bus_volume("Master", float(settings.get("master_vol", 0.85)))
	_apply_bus_volume("Music", float(settings.get("music_vol", 0.75)))
	_apply_bus_volume("SFX", float(settings.get("sfx_vol", 0.90)))

	if DisplayServer.get_name() != "headless":
		var ml := Engine.get_main_loop()
		var win: Window = (ml as SceneTree).root if ml is SceneTree else null
		var want_fs: bool = bool(settings.get("fullscreen", false))
		var cur_mode := DisplayServer.window_get_mode()
		if want_fs:
			if cur_mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN and cur_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
				if win != null:
					win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		else:
			if cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				if win != null:
					win.mode = Window.MODE_WINDOWED
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var target_size := _get_resolution_size(str(settings.get("resolution", "1280x720")))
			if DisplayServer.window_get_size() != target_size:
				DisplayServer.window_set_size(target_size)
				var screen_idx := DisplayServer.window_get_current_screen()
				var usable := DisplayServer.screen_get_usable_rect(screen_idx)
				var pos := usable.position + (usable.size - target_size) / 2
				pos.x = maxi(pos.x, usable.position.x)
				pos.y = maxi(pos.y, usable.position.y)
				DisplayServer.window_set_position(pos)


static func _apply_bus_volume(bus_name: String, linear_val: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped := clampf(linear_val, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.005)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(clamped, 0.0001)))


# ---------------------------------------------------------------------------
# Global BGM Music Manager (Attached lazily to SceneTree.root — zero project.godot edits)
# ---------------------------------------------------------------------------

const BGM_TRACKS := {
	"menu":     {"path": "res://Music/f@ct Fun days (music or buy menu ost).wav",        "db": -8.0},
	"gameplay": {"path": "res://Music/Rwi  Wavetones Pororoca(main gameplay music).wav", "db": -8.0},
	"boss":     {"path": "res://Music/tdhr (Untitled) (boss fight ost).wav",             "db": -7.0},
	"fail":     {"path": "res://Music/last flashback raymaster (run fail ost).wav",      "db": -7.0},
}


static func get_music_manager() -> Node:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return null
	var tree := ml as SceneTree
	if tree.root == null:
		return null
	var mgr := tree.root.get_node_or_null("SlopMusicManager")
	if mgr != null and is_instance_valid(mgr) and not mgr.is_queued_for_deletion():
		return mgr
	if tree.root.has_meta("_slop_music_mgr"):
		var pending = tree.root.get_meta("_slop_music_mgr")
		if pending is Node and is_instance_valid(pending) and not pending.is_queued_for_deletion():
			return pending
	load_and_apply_settings()
	mgr = MusicController.new()
	mgr.name = "SlopMusicManager"
	tree.root.set_meta("_slop_music_mgr", mgr)
	tree.root.call_deferred("add_child", mgr)
	return mgr


static func sync_bgm() -> void:
	var mgr := get_music_manager()
	if mgr != null and mgr.has_method("request_sync"):
		mgr.request_sync()


static func play_bgm(track_key: String, fade_sec: float = 0.55) -> void:
	var mgr := get_music_manager()
	if mgr != null and mgr.has_method("play_track"):
		mgr.play_track(track_key, fade_sec)


class MusicController extends Node:
	var _p_a: AudioStreamPlayer = null
	var _p_b: AudioStreamPlayer = null
	var _active_player: AudioStreamPlayer = null
	var _current_track: String = ""
	var _is_ducked: bool = false
	var _fade_tween: Tween = null
	var _duck_tween: Tween = null
	var _stream_cache: Dictionary = {}
	var _poll_accum: float = 0.0

	func _ready() -> void:
		var root := get_tree().root if get_tree() != null else null
		if root != null:
			var existing := root.get_node_or_null("SlopMusicManager")
			if existing != null and existing != self and is_instance_valid(existing) and not existing.is_queued_for_deletion():
				queue_free()
				return
		process_mode = Node.PROCESS_MODE_ALWAYS
		UIAssets.load_and_apply_settings()
		_p_a = _make_player("BGMChannelA")
		_p_b = _make_player("BGMChannelB")
		_active_player = _p_a
		call_deferred("_evaluate_and_apply")

	func _make_player(n: String) -> AudioStreamPlayer:
		var p := AudioStreamPlayer.new()
		p.name = n
		p.bus = "Music"
		p.volume_db = -45.0
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.finished.connect(func():
			if p == _active_player and _current_track != "" and p.stream != null:
				p.play()
		)
		add_child(p)
		return p

	func _process(delta: float) -> void:
		_poll_accum += delta
		if _poll_accum >= 0.15:
			_poll_accum = 0.0
			_evaluate_and_apply()

	func request_sync() -> void:
		if is_inside_tree():
			call_deferred("_evaluate_and_apply")

	func _is_group_visible(group_name: String) -> bool:
		var tree := get_tree()
		if tree == null:
			return false
		for n in tree.get_nodes_in_group(group_name):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				if n is CanvasLayer:
					if n.visible:
						return true
				elif n is CanvasItem:
					if n.visible:
						return true
				else:
					return true
		return false

	func _get_first_active_in_group(group_name: String) -> Node:
		var tree := get_tree()
		if tree == null:
			return null
		for n in tree.get_nodes_in_group(group_name):
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				return n
		return null

	func _evaluate_and_apply() -> void:
		if not is_inside_tree():
			return
		var target_track: String = ""
		var want_duck: bool = false

		# 1. Title Screen always plays upbeat Menu/Outpost OST
		if _is_group_visible("title_screen"):
			target_track = "menu"
		else:
			var dnc := _get_first_active_in_group("day_night_cycle")
			var dnc_state: String = ""
			if dnc != null and dnc.has_method("get_music_state"):
				dnc_state = str(dnc.get_music_state())

			# 2. End-of-day Settlement Modals take priority over active gameplay
			if dnc_state == "fail":
				target_track = "fail"
			elif dnc_state == "win":
				target_track = "menu"
			# 3. Contract Board (Boss Day -> Boss OST, Normal -> Menu/Outpost OST)
			elif _is_group_visible("quota_menu"):
				var qm := _get_first_active_in_group("quota_menu")
				if qm != null and ("is_boss_day" in qm) and bool(qm.is_boss_day):
					target_track = "boss"
				else:
					target_track = "menu"
			# 4. Mod Shop / Heavy Machinery Workshop
			elif _is_group_visible("buy_menu") or _is_group_visible("machine_buy_menu"):
				target_track = "menu"
			# 5. Active Gameplay (Boss/Event OST vs Main Gameplay OST)
			elif dnc_state == "boss":
				target_track = "boss"
				want_duck = _is_group_visible("pause_menu")
			elif dnc_state == "gameplay":
				target_track = "gameplay"
				want_duck = _is_group_visible("pause_menu")

		if target_track != "" and target_track != _current_track:
			play_track(target_track, 0.55)
		if want_duck != _is_ducked:
			_set_ducked(want_duck)

	func _load_stream(track_key: String) -> AudioStream:
		if _stream_cache.has(track_key):
			return _stream_cache[track_key]
		if not UIAssets.BGM_TRACKS.has(track_key):
			return null
		var path: String = str(UIAssets.BGM_TRACKS[track_key]["path"])
		if not ResourceLoader.exists(path):
			return null
		var stream := load(path) as AudioStream
		if stream != null:
			_stream_cache[track_key] = stream
		return stream

	func play_track(track_key: String, fade_sec: float = 0.55) -> void:
		if not is_inside_tree():
			return
		if track_key == _current_track and _active_player != null and _active_player.playing:
			return
		var stream := _load_stream(track_key)
		if stream == null:
			return

		var target_db: float = float(UIAssets.BGM_TRACKS[track_key].get("db", -8.0))
		if _is_ducked:
			target_db -= 6.0

		var outgoing := _active_player
		var incoming := _p_b if _active_player == _p_a else _p_a
		_active_player = incoming
		_current_track = track_key

		if _duck_tween != null and _duck_tween.is_valid():
			_duck_tween.kill()
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()

		incoming.stream = stream
		if fade_sec <= 0.0:
			incoming.volume_db = target_db
			incoming.play()
			if outgoing != null and outgoing != incoming and outgoing.playing:
				outgoing.stop()
			return

		incoming.volume_db = -42.0
		incoming.play()

		_fade_tween = create_tween()
		_fade_tween.set_parallel(true)
		_fade_tween.tween_property(incoming, "volume_db", target_db, fade_sec)
		if outgoing != null and outgoing != incoming and outgoing.playing:
			_fade_tween.tween_property(outgoing, "volume_db", -45.0, fade_sec)
			_fade_tween.chain().tween_callback(func():
				if outgoing != _active_player:
					outgoing.stop()
			)

	func _set_ducked(duck: bool) -> void:
		_is_ducked = duck
		if _active_player == null or _current_track == "" or not UIAssets.BGM_TRACKS.has(_current_track):
			return
		var base_db: float = float(UIAssets.BGM_TRACKS[_current_track].get("db", -8.0))
		var target_db: float = base_db - 6.0 if duck else base_db
		if _duck_tween != null and _duck_tween.is_valid():
			_duck_tween.kill()
		_duck_tween = create_tween()
		_duck_tween.tween_property(_active_player, "volume_db", target_db, 0.22)
