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

static var _settings_loaded: bool = false
static var settings: Dictionary = {
	"master_vol": 0.85,
	"music_vol": 0.75,
	"sfx_vol": 0.90,
	"fullscreen": false,
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


static func load_and_apply_settings() -> void:
	ensure_audio_buses()
	if not _settings_loaded:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			settings["master_vol"] = clampf(float(cfg.get_value("audio", "master_vol", 0.85)), 0.0, 1.0)
			settings["music_vol"] = clampf(float(cfg.get_value("audio", "music_vol", 0.75)), 0.0, 1.0)
			settings["sfx_vol"] = clampf(float(cfg.get_value("audio", "sfx_vol", 0.90)), 0.0, 1.0)
			settings["fullscreen"] = bool(cfg.get_value("display", "fullscreen", false))
			settings["screen_shake"] = bool(cfg.get_value("gameplay", "screen_shake", true))
		_settings_loaded = true
	apply_settings()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_vol", settings["master_vol"])
	cfg.set_value("audio", "music_vol", settings["music_vol"])
	cfg.set_value("audio", "sfx_vol", settings["sfx_vol"])
	cfg.set_value("display", "fullscreen", settings["fullscreen"])
	cfg.set_value("gameplay", "screen_shake", settings["screen_shake"])
	cfg.save(SETTINGS_PATH)


static func apply_settings() -> void:
	ensure_audio_buses()
	_apply_bus_volume("Master", float(settings.get("master_vol", 0.85)))
	_apply_bus_volume("Music", float(settings.get("music_vol", 0.75)))
	_apply_bus_volume("SFX", float(settings.get("sfx_vol", 0.90)))

	if DisplayServer.get_name() != "headless":
		var want_fs: bool = bool(settings.get("fullscreen", false))
		var cur_mode := DisplayServer.window_get_mode()
		if want_fs and cur_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not want_fs and cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


static func _apply_bus_volume(bus_name: String, linear_val: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped := clampf(linear_val, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.005)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(clamped, 0.0001)))
