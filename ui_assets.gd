# ui_assets.gd
# Centralized loader and caching utility for the raw HD UI textures in res://UI/

class_name UIAssets

static var _cache: Dictionary = {}

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


## Creates a TextureRect that strictly preserves native texture dimensions and aspect ratio
static func create_texture_rect(res_path: String, expand: bool = false) -> TextureRect:
	var tr := TextureRect.new()
	var tex := get_tex(res_path)
	tr.texture = tex
	if tex:
		tr.custom_minimum_size = tex.get_size()
		tr.size = tex.get_size()
	if expand:
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		tr.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP
	return tr


## Creates a Button styled with a Texture background (normal, hover, pressed, disabled)
## Enforces exact 1:1 pixel dimensions so textures are NEVER stretched.
static func create_textured_button(
	res_path: String,
	title_text: String = "",
	font_size: int = 15,
	font_col: Color = Color.WHITE
) -> Button:
	var btn := Button.new()
	btn.text = title_text
	btn.add_theme_font_override("font", ThemeDB.fallback_font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", font_col)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.85))
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 0.7))

	var tex := get_tex(res_path)
	if tex:
		var tex_sz := tex.get_size()
		btn.custom_minimum_size = tex_sz
		btn.size = tex_sz

		var sb_norm := StyleBoxTexture.new()
		sb_norm.texture = tex
		btn.add_theme_stylebox_override("normal", sb_norm)

		var sb_hov := StyleBoxTexture.new()
		sb_hov.texture = tex
		sb_hov.modulate_color = Color(1.15, 1.15, 1.15)
		btn.add_theme_stylebox_override("hover", sb_hov)

		var sb_press := StyleBoxTexture.new()
		sb_press.texture = tex
		sb_press.modulate_color = Color(0.85, 0.85, 0.85)
		btn.add_theme_stylebox_override("pressed", sb_press)

		var sb_dis := StyleBoxTexture.new()
		sb_dis.texture = tex
		sb_dis.modulate_color = Color(0.70, 0.68, 0.65, 0.90)
		btn.add_theme_stylebox_override("disabled", sb_dis)
		btn.add_theme_color_override("font_disabled_color", Color(0.48, 0.44, 0.40, 0.95))

		var sb_foc := StyleBoxTexture.new()
		sb_foc.texture = tex
		btn.add_theme_stylebox_override("focus", sb_foc)

	return btn
