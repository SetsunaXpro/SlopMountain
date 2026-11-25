# ui_modals.gd
# Reusable SlopMountain modal overlays matching Figma 05_modals assets:
# - UIModals.open_pause_menu(parent, player, dnc)
# - UIModals.open_how_to_play(parent)
# - UIModals.open_settings(parent)
# - UIModals.open_credits(parent)

class_name UIModals

const UIAssets = preload("res://ui_assets.gd")


# ===========================================================================
# Static Factory Helpers
# ===========================================================================

static func open_pause_menu(parent: Node, player: Node = null, dnc: Node = null) -> PauseMenuOverlay:
	var modal := PauseMenuOverlay.new()
	modal.player_ref = player
	modal.dnc_ref = dnc
	parent.add_child(modal)
	return modal


static func open_how_to_play(parent: Node) -> HowToPlayOverlay:
	var modal := HowToPlayOverlay.new()
	parent.add_child(modal)
	return modal


static func open_settings(parent: Node) -> SettingsOverlay:
	var modal := SettingsOverlay.new()
	parent.add_child(modal)
	return modal


static func open_credits(parent: Node) -> CreditsOverlay:
	var modal := CreditsOverlay.new()
	parent.add_child(modal)
	return modal


# ===========================================================================
# Shared Helper: Dim Scrim + Wide Modal Corkboard Shell
# ===========================================================================

static func _build_dim_scrim(parent: Control, alpha: float = 0.72) -> ColorRect:
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.04, 0.06, 0.09, alpha)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(scrim)
	return scrim


static func _build_wide_modal_shell(content: Control, title_text: String) -> Dictionary:
	# Corkboard visual bounds: (250, 98, 780x540). PNG is 828x588 (24px shadow padding).
	var board_tex := UIAssets.create_texture_rect("res://UI/05_modals/modal_corkboard_wide.png")
	board_tex.position = Vector2(226, 74)
	board_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(board_tex)

	var board := Control.new()
	board.position = Vector2(250, 98)
	board.size = Vector2(780, 540)
	content.add_child(board)

	# Floating Header Slab (380x54) centered at top edge
	var hdr_tex := UIAssets.create_texture_rect("res://UI/05_modals/header_slab_modal_med.png")
	hdr_tex.position = Vector2(200, -26)
	hdr_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(hdr_tex)

	var hdr_lbl := UIAssets.create_label(
		title_text, 22, UIAssets.COL_CREAM, "black",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.55
	)
	hdr_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hdr_tex.add_child(hdr_lbl)

	# Wide Torn Paper visual bounds inside board: (40, 54, 700x384). PNG is 732x417.
	var paper_tex := UIAssets.create_texture_rect("res://UI/05_modals/paper_modal_wide_empty.png")
	paper_tex.position = Vector2(24, 42)
	paper_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(paper_tex)

	var paper := Control.new()
	paper.position = Vector2(40, 54)
	paper.size = Vector2(700, 384)
	board.add_child(paper)

	return {"board": board, "paper": paper}


# ===========================================================================
# 1. Pause Menu Overlay [ESC] (Multiplayer-safe + TitleScreen overlay return)
# ===========================================================================

class PauseMenuOverlay extends CanvasLayer:
	signal resumed
	signal closed

	var player_ref: Node = null
	var dnc_ref: Node = null
	var _status_label: Label = null
	var _child_popup: CanvasLayer = null
	var _did_pause_tree: bool = false

	func _ready() -> void:
		layer = 50
		process_mode = Node.PROCESS_MODE_ALWAYS
		add_to_group("pause_menu")

		if player_ref == null:
			player_ref = get_tree().get_first_node_in_group("player")
		if dnc_ref == null:
			dnc_ref = get_tree().get_first_node_in_group("day_night_cycle")

		# Only pause SceneTree in singleplayer so co-op multiplayer RPCs keep syncing!
		var is_mp: bool = (NetworkManager != null and NetworkManager.is_multiplayer_active())
		if not is_mp:
			get_tree().paused = true
			_did_pause_tree = true

		if is_instance_valid(player_ref) and player_ref.has_method("release_mouse"):
			player_ref.release_mouse()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_build_ui()
		_refresh_status()

	func _exit_tree() -> void:
		if _did_pause_tree and get_tree():
			get_tree().paused = false
		closed.emit()

	func _unhandled_input(event: InputEvent) -> void:
		if is_instance_valid(_child_popup):
			return
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_on_resume()

	func _build_ui() -> void:
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(root)
		UIModals._build_dim_scrim(root, 0.72)

		var content := Control.new()
		content.set_anchors_preset(Control.PRESET_CENTER)
		content.offset_left = -640
		content.offset_right = 640
		content.offset_top = -360
		content.offset_bottom = 360
		content.size = Vector2(1280, 720)
		root.add_child(content)

		# Compact Corkboard visual: (410, 132, 460x476). PNG is 508x524 (24px shadow pad).
		var board_tex := UIAssets.create_texture_rect("res://UI/05_modals/modal_corkboard_compact.png")
		board_tex.position = Vector2(386, 108)
		board_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(board_tex)

		var board := Control.new()
		board.position = Vector2(410, 132)
		board.size = Vector2(460, 476)
		content.add_child(board)

		# Header Slab (320x54)
		var hdr := UIAssets.create_texture_rect("res://UI/05_modals/header_slab_modal_small.png")
		hdr.position = Vector2(70, -26)
		hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(hdr)

		var hdr_lbl := UIAssets.create_label(
			"PAUSED", 24, UIAssets.COL_CREAM, "black",
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.55
		)
		hdr_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		hdr.add_child(hdr_lbl)

		# Bolted Status Plate (356x42)
		var plate := UIAssets.create_texture_rect("res://UI/05_modals/plate_pause_status_bg.png")
		plate.position = Vector2(52, 52)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(plate)

		_status_label = UIAssets.create_label(
			"DAY 01 / 08   •   SISA 07:00   •   $0", 13, UIAssets.COL_GOLD, "mono",
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.4
		)
		_status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.add_child(_status_label)

		# 1. RESUME SHIFT
		var btn_resume := UIAssets.create_wood_button(
			"res://UI/05_modals/btn_ending_blue_wood.png",
			"RESUME SHIFT  ➔", 17, Color(0.20, 0.12, 0.05), "", "black", 5
		)
		btn_resume.position = Vector2(74, 108)
		btn_resume.pressed.connect(_on_resume)
		board.add_child(btn_resume)

		# 2. RESTART DAY
		var btn_restart := UIAssets.create_wood_button(
			"res://UI/05_modals/btn_ending_brown_wood.png",
			"RESTART DAY", 15, UIAssets.COL_CREAM, "", "black", 5
		)
		btn_restart.position = Vector2(74, 178)
		btn_restart.pressed.connect(_on_restart_day)
		board.add_child(btn_restart)

		# 3. SETTINGS
		var btn_settings := UIAssets.create_wood_button(
			"res://UI/05_modals/btn_ending_brown_wood.png",
			"SETTINGS", 15, UIAssets.COL_CREAM, "", "black", 5
		)
		btn_settings.position = Vector2(74, 248)
		btn_settings.pressed.connect(_on_settings)
		board.add_child(btn_settings)

		# 4. MAIN MENU (Spawns TitleScreen overlay cleanly matching Fahri's architecture)
		var btn_menu := UIAssets.create_wood_button(
			"res://UI/05_modals/btn_ending_red_wood.png",
			"MAIN MENU", 15, Color.WHITE, "", "black", 5
		)
		btn_menu.position = Vector2(74, 318)
		btn_menu.pressed.connect(_on_main_menu)
		board.add_child(btn_menu)

		# Quick-hint footer
		var hint := UIAssets.create_label(
			"Tekan [ESC] untuk melanjutkan permainan", 12, Color(0.95, 0.88, 0.76, 0.85), "semibold",
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.5
		)
		hint.position = Vector2(20, 412)
		hint.size = Vector2(420, 24)
		board.add_child(hint)

	func _refresh_status() -> void:
		if not is_instance_valid(_status_label):
			return
		var day_num: int = 1
		var rem_str: String = "07:00"
		if is_instance_valid(dnc_ref):
			if "current_day" in dnc_ref:
				day_num = int(dnc_ref.current_day)
			if "day_duration_seconds" in dnc_ref and "day_elapsed_seconds" in dnc_ref:
				var rem: float = maxf(0.0, float(dnc_ref.day_duration_seconds) - float(dnc_ref.day_elapsed_seconds))
				rem_str = "%02d:%02d" % [int(rem / 60.0), int(rem) % 60]
		var cash: int = 0
		if is_instance_valid(player_ref) and "slop_credit" in player_ref:
			cash = int(player_ref.slop_credit)
		_status_label.text = "DAY %02d / 08   •   SISA %s   •   $%d" % [day_num, rem_str, cash]

	func _on_resume() -> void:
		if _did_pause_tree:
			get_tree().paused = false
			_did_pause_tree = false
		if is_instance_valid(player_ref) and player_ref.has_method("capture_mouse"):
			player_ref.capture_mouse()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		resumed.emit()
		queue_free()

	func _on_restart_day() -> void:
		if _did_pause_tree:
			get_tree().paused = false
			_did_pause_tree = false
		if is_instance_valid(dnc_ref) and dnc_ref.has_method("retry_current_day"):
			dnc_ref.retry_current_day()
		queue_free()

	func _on_settings() -> void:
		if is_instance_valid(_child_popup):
			return
		_child_popup = UIModals.open_settings(get_tree().root)

	func _on_main_menu() -> void:
		if _did_pause_tree:
			get_tree().paused = false
			_did_pause_tree = false
		if NetworkManager != null and NetworkManager.is_multiplayer_active():
			NetworkManager.leave_game()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		var existing_title = get_tree().get_first_node_in_group("title_screen")
		if not existing_title and get_tree().current_scene:
			var ts_script = load("res://title_screen.gd")
			if ts_script:
				var ts = ts_script.new()
				get_tree().current_scene.add_child(ts)
		queue_free()


# ===========================================================================
# 2. How To Play Popup (Synced with real 3D WASD + M/E/C/B/Q/N controls)
# ===========================================================================

class HowToPlayOverlay extends CanvasLayer:
	signal closed

	func _ready() -> void:
		layer = 110
		process_mode = Node.PROCESS_MODE_ALWAYS
		_build_ui()

	func _exit_tree() -> void:
		closed.emit()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				queue_free()

	func _build_ui() -> void:
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(root)
		UIModals._build_dim_scrim(root, 0.72)

		var content := Control.new()
		content.set_anchors_preset(Control.PRESET_CENTER)
		content.offset_left = -640
		content.offset_right = 640
		content.offset_top = -360
		content.offset_bottom = 360
		content.size = Vector2(1280, 720)
		root.add_child(content)

		var shell := UIModals._build_wide_modal_shell(content, "HOW TO PLAY")
		var board: Control = shell["board"]
		var paper: Control = shell["paper"]

		var vline := ColorRect.new()
		vline.position = Vector2(348, 28)
		vline.size = Vector2(2, 316)
		vline.color = Color(0.55, 0.48, 0.38, 0.35)
		paper.add_child(vline)

		# --- LEFT COLUMN: KONTROL RANGER ---
		var col1_hdr := UIAssets.create_label("KONTROL RANGER", 15, Color(0.28, 0.18, 0.10), "black")
		col1_hdr.position = Vector2(26, 26)
		col1_hdr.size = Vector2(300, 22)
		paper.add_child(col1_hdr)

		var hline1 := ColorRect.new()
		hline1.position = Vector2(26, 52)
		hline1.size = Vector2(302, 2)
		hline1.color = Color(0.32, 0.24, 0.16, 0.45)
		paper.add_child(hline1)

		var controls := [
			["WASD / SPC", "Gerak 3D & melompat naik di lereng gunung"],
			["KLIK KIRI",  "Tahan untuk capit & masukkan sampah ke tas"],
			["RMB / [G]",  "Equip sampah granat [G] & lempar (Klik Kanan)"],
			["E / C / M",  "[E] Interact, [1-6]+[C] Build, [M] Beli Mesin"],
			["B / Q / N",  "[B] Mod Shop, [Q] Kontrak, tahan [N] End Day"],
		]
		for i in range(controls.size()):
			var row_y: float = 72.0 + float(i) * 54.0
			var keycap := UIAssets.create_texture_rect("res://UI/05_modals/keycap_badge_bg.png")
			keycap.position = Vector2(26, row_y)
			paper.add_child(keycap)

			var k_lbl := UIAssets.create_label(
				controls[i][0], 11, UIAssets.COL_CREAM, "mono",
				HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
			)
			k_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			keycap.add_child(k_lbl)

			var d_lbl := UIAssets.create_wrapped_label(
				controls[i][1], Vector2(126, row_y - 3), Vector2(204, 38),
				12, UIAssets.COL_INK, "semibold",
				HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_CENTER
			)
			paper.add_child(d_lbl)

		# --- RIGHT COLUMN: ATURAN SHIFT (3 LANGKAH) ---
		var col2_hdr := UIAssets.create_label("ATURAN SHIFT (3 LANGKAH)", 15, Color(0.28, 0.18, 0.10), "black")
		col2_hdr.position = Vector2(372, 26)
		col2_hdr.size = Vector2(304, 22)
		paper.add_child(col2_hdr)

		var hline2 := ColorRect.new()
		hline2.position = Vector2(372, 52)
		hline2.size = Vector2(302, 2)
		hline2.color = Color(0.32, 0.24, 0.16, 0.45)
		paper.add_child(hline2)

		var steps := [
			["01", "PILIH KONTRAK PAGI", "Setiap pagi pilih 1 dari 3 kertas kontrak (atau voting bareng di Co-op). Makin berat kuota, makin besar bayaran."],
			["02", "MANJAT & SORTIR SEBELUM SENJA", "Kumpulkan sampah & proses di mesin sebelum timer habis. Sortir beruntun menaikkan Streak & Mult!"],
			["03", "BELANJA GADGET & TOOLS MOSSY", "Beli Mod [B], Mesin & Perangkap [M] untuk event. Tekan [ESC] untuk Pause. Gagal kuota = Park Closed!"],
		]
		for i in range(steps.size()):
			var sy: float = 72.0 + float(i) * 92.0
			var badge := Panel.new()
			badge.position = Vector2(372, sy)
			badge.size = Vector2(30, 26)
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = Color(0.24, 0.17, 0.10, 1.0)
			bsb.set_border_width_all(0)
			bsb.set_corner_radius_all(6)
			badge.add_theme_stylebox_override("panel", bsb)
			paper.add_child(badge)

			var b_lbl := UIAssets.create_label(
				str(i + 1), 13, UIAssets.COL_GOLD, "black",
				HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
			)
			b_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			badge.add_child(b_lbl)

			var st_lbl := UIAssets.create_label(steps[i][1], 13, UIAssets.COL_INK, "black")
			st_lbl.position = Vector2(410, sy + 2)
			st_lbl.size = Vector2(266, 22)
			paper.add_child(st_lbl)

			var sb_lbl := UIAssets.create_wrapped_label(
				steps[i][2], Vector2(372, sy + 32), Vector2(300, 56),
				11, UIAssets.COL_INK_MUTED, "semibold",
				HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP
			)
			paper.add_child(sb_lbl)

		var btn_ok := UIAssets.create_wood_button(
			"res://UI/05_modals/btn_modal_blue_wood.png",
			"MENGERTI  ➔", 16, Color(0.20, 0.12, 0.05), "", "black", 5
		)
		btn_ok.position = Vector2(484, 446)
		btn_ok.pressed.connect(queue_free)
		board.add_child(btn_ok)


# ===========================================================================
# 3. Settings Popup (Interactive Audio Sliders + Fullscreen & Screen Shake)
# ===========================================================================

class SettingsOverlay extends CanvasLayer:
	signal closed

	var _toggle_fs_btn: Button = null
	var _toggle_shake_btn: Button = null

	func _ready() -> void:
		layer = 110
		process_mode = Node.PROCESS_MODE_ALWAYS
		UIAssets.load_and_apply_settings()
		_build_ui()

	func _exit_tree() -> void:
		UIAssets.save_settings()
		closed.emit()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				queue_free()

	func _build_ui() -> void:
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(root)
		UIModals._build_dim_scrim(root, 0.72)

		var content := Control.new()
		content.set_anchors_preset(Control.PRESET_CENTER)
		content.offset_left = -640
		content.offset_right = 640
		content.offset_top = -360
		content.offset_bottom = 360
		content.size = Vector2(1280, 720)
		root.add_child(content)

		var shell := UIModals._build_wide_modal_shell(content, "SETTINGS")
		var board: Control = shell["board"]
		var paper: Control = shell["paper"]

		var vline := ColorRect.new()
		vline.position = Vector2(362, 28)
		vline.size = Vector2(2, 316)
		vline.color = Color(0.55, 0.48, 0.38, 0.35)
		paper.add_child(vline)

		# --- LEFT COLUMN: AUDIO ---
		var col1 := UIAssets.create_label("AUDIO", 15, Color(0.28, 0.18, 0.10), "black")
		col1.position = Vector2(26, 26)
		col1.size = Vector2(310, 22)
		paper.add_child(col1)

		var h1 := ColorRect.new()
		h1.position = Vector2(26, 52)
		h1.size = Vector2(312, 2)
		h1.color = Color(0.32, 0.24, 0.16, 0.45)
		paper.add_child(h1)

		_add_industrial_slider(paper, "MASTER VOLUME", "master_vol", 76)
		_add_industrial_slider(paper, "MUSIC / BGM",   "music_vol",  162)
		_add_industrial_slider(paper, "SFX / EFEK",    "sfx_vol",    248)

		# --- RIGHT COLUMN: TAMPILAN & KONTROL ---
		var col2 := UIAssets.create_label("TAMPILAN & KONTROL", 15, Color(0.28, 0.18, 0.10), "black")
		col2.position = Vector2(384, 26)
		col2.size = Vector2(290, 22)
		paper.add_child(col2)

		var h2 := ColorRect.new()
		h2.position = Vector2(384, 52)
		h2.size = Vector2(290, 2)
		h2.color = Color(0.32, 0.24, 0.16, 0.45)
		paper.add_child(h2)

		var fs_lbl := UIAssets.create_label("FULLSCREEN", 14, UIAssets.COL_INK, "black")
		fs_lbl.position = Vector2(384, 84)
		fs_lbl.size = Vector2(180, 24)
		paper.add_child(fs_lbl)

		var fs_sub := UIAssets.create_label("Layar penuh 1280×720", 11, UIAssets.COL_INK_MUTED, "semibold")
		fs_sub.position = Vector2(384, 108)
		fs_sub.size = Vector2(180, 18)
		paper.add_child(fs_sub)

		_toggle_fs_btn = _create_toggle_button(bool(UIAssets.settings["fullscreen"]))
		_toggle_fs_btn.position = Vector2(568, 86)
		_toggle_fs_btn.pressed.connect(_on_toggle_fullscreen)
		paper.add_child(_toggle_fs_btn)

		var sh_lbl := UIAssets.create_label("SCREEN SHAKE", 14, UIAssets.COL_INK, "black")
		sh_lbl.position = Vector2(384, 166)
		sh_lbl.size = Vector2(180, 24)
		paper.add_child(sh_lbl)

		var sh_sub := UIAssets.create_wrapped_label(
			"Efek getar saat melempar / longsor", Vector2(384, 190), Vector2(178, 34),
			11, UIAssets.COL_INK_MUTED, "semibold",
			HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP
		)
		paper.add_child(sh_sub)

		_toggle_shake_btn = _create_toggle_button(bool(UIAssets.settings["screen_shake"]))
		_toggle_shake_btn.position = Vector2(568, 168)
		_toggle_shake_btn.pressed.connect(_on_toggle_shake)
		paper.add_child(_toggle_shake_btn)

		var info_box := Panel.new()
		info_box.position = Vector2(384, 248)
		info_box.size = Vector2(288, 62)
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0.86, 0.80, 0.68, 0.85)
		isb.set_border_width_all(0)
		isb.set_corner_radius_all(8)
		info_box.add_theme_stylebox_override("panel", isb)
		paper.add_child(info_box)

		var p_v := UIAssets.create_label(
			"Kontrol: Keyboard (WASD) + Mouse", 13, UIAssets.COL_INK, "bold",
			HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
		)
		p_v.set_anchors_preset(Control.PRESET_FULL_RECT)
		info_box.add_child(p_v)

		var btn_save := UIAssets.create_wood_button(
			"res://UI/05_modals/btn_modal_blue_wood.png",
			"SIMPAN & TUTUP", 15, Color(0.20, 0.12, 0.05), "", "black", 5
		)
		btn_save.position = Vector2(484, 446)
		btn_save.pressed.connect(func():
			UIAssets.save_settings()
			queue_free()
		)
		board.add_child(btn_save)

	func _add_industrial_slider(paper: Control, label_text: String, key: String, pos_y: float) -> void:
		var val: float = float(UIAssets.settings.get(key, 0.8))

		var title := UIAssets.create_label(label_text, 13, UIAssets.COL_INK, "black")
		title.position = Vector2(26, pos_y)
		title.size = Vector2(220, 20)
		paper.add_child(title)

		var pct_lbl := UIAssets.create_label(
			"%d%%" % int(round(val * 100.0)), 13, UIAssets.COL_BLUE_INK, "mono",
			HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER
		)
		pct_lbl.position = Vector2(246, pos_y)
		pct_lbl.size = Vector2(90, 20)
		paper.add_child(pct_lbl)

		var track := UIAssets.create_texture_rect("res://UI/05_modals/slider_track_bg.png")
		track.position = Vector2(26, pos_y + 30)
		paper.add_child(track)

		var fill_bar := TextureProgressBar.new()
		fill_bar.position = Vector2(28, pos_y + 32)
		fill_bar.size = Vector2(306, 12)
		fill_bar.min_value = 0.0
		fill_bar.max_value = 1.0
		fill_bar.step = 0.01
		fill_bar.value = val
		fill_bar.texture_progress = UIAssets.get_tex("res://UI/05_modals/slider_fill_amber.png")
		fill_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(fill_bar)

		var slider := HSlider.new()
		slider.position = Vector2(26, pos_y + 24)
		slider.size = Vector2(310, 28)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = val
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var empty_sb := StyleBoxEmpty.new()
		slider.add_theme_stylebox_override("slider", empty_sb)
		slider.add_theme_stylebox_override("grabber_area", empty_sb)
		slider.add_theme_stylebox_override("grabber_area_highlight", empty_sb)
		var knob_tex := UIAssets.get_tex("res://UI/05_modals/slider_knob_metal.png")
		if knob_tex:
			slider.add_theme_icon_override("grabber", knob_tex)
			slider.add_theme_icon_override("grabber_highlight", knob_tex)
			slider.add_theme_icon_override("grabber_disabled", knob_tex)

		slider.value_changed.connect(func(new_val: float):
			UIAssets.settings[key] = new_val
			fill_bar.value = new_val
			pct_lbl.text = "%d%%" % int(round(new_val * 100.0))
			UIAssets.apply_settings()
		)
		paper.add_child(slider)

	func _create_toggle_button(is_on: bool) -> Button:
		var path := "res://UI/05_modals/toggle_btn_on.png" if is_on else "res://UI/05_modals/toggle_btn_off.png"
		var txt := "ON" if is_on else "OFF"
		var col := Color.WHITE if is_on else Color(0.75, 0.78, 0.82)
		return UIAssets.create_wood_button(path, txt, 13, col, "", "black", 0)

	func _refresh_toggle_visual(btn: Button, is_on: bool) -> void:
		var path := "res://UI/05_modals/toggle_btn_on.png" if is_on else "res://UI/05_modals/toggle_btn_off.png"
		var tex := UIAssets.get_tex(path)
		btn.text = "ON" if is_on else "OFF"
		btn.add_theme_color_override("font_color", Color.WHITE if is_on else Color(0.75, 0.78, 0.82))
		if tex:
			for state in ["normal", "hover", "pressed"]:
				var sb := StyleBoxTexture.new()
				sb.texture = tex
				if state == "hover":
					sb.modulate_color = Color(1.1, 1.1, 1.1)
				btn.add_theme_stylebox_override(state, sb)

	func _on_toggle_fullscreen() -> void:
		UIAssets.settings["fullscreen"] = not bool(UIAssets.settings["fullscreen"])
		UIAssets.apply_settings()
		_refresh_toggle_visual(_toggle_fs_btn, bool(UIAssets.settings["fullscreen"]))

	func _on_toggle_shake() -> void:
		UIAssets.settings["screen_shake"] = not bool(UIAssets.settings["screen_shake"])
		_refresh_toggle_visual(_toggle_shake_btn, bool(UIAssets.settings["screen_shake"]))


# ===========================================================================
# 4. Credits Popup (All 5 DavDev 272 Team Members)
# ===========================================================================

class CreditsOverlay extends CanvasLayer:
	signal closed

	func _ready() -> void:
		layer = 110
		process_mode = Node.PROCESS_MODE_ALWAYS
		_build_ui()

	func _exit_tree() -> void:
		closed.emit()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				queue_free()

	func _build_ui() -> void:
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(root)
		UIModals._build_dim_scrim(root, 0.72)

		var content := Control.new()
		content.set_anchors_preset(Control.PRESET_CENTER)
		content.offset_left = -640
		content.offset_right = 640
		content.offset_top = -360
		content.offset_bottom = 360
		content.size = Vector2(1280, 720)
		root.add_child(content)

		var shell := UIModals._build_wide_modal_shell(content, "CREDITS")
		var board: Control = shell["board"]
		var paper: Control = shell["paper"]

		var team_hdr := UIAssets.create_label(
			"Tim DavDev 272", 21, Color(0.24, 0.16, 0.08), "black",
			HORIZONTAL_ALIGNMENT_CENTER
		)
		team_hdr.position = Vector2(30, 26)
		team_hdr.size = Vector2(640, 30)
		paper.add_child(team_hdr)

		var div := ColorRect.new()
		div.position = Vector2(36, 68)
		div.size = Vector2(628, 2)
		div.color = Color(0.35, 0.26, 0.18, 0.32)
		paper.add_child(div)

		var members := [
			["Fahri",             "Team Lead & Game Design",    Vector2(36, 88)],
			["Gary Hardyansyah",  "Project Management",         Vector2(364, 88)],
			["Abudan",            "UI/UX Design & Programming", Vector2(36, 164)],
			["Rocky",             "2D / 3D Art",                Vector2(364, 164)],
			["Adhistya Sunasr",   "Art & Sound Design",         Vector2(200, 240)],
		]
		for m in members:
			var card := Panel.new()
			card.position = m[2]
			card.size = Vector2(300, 64)
			var csb := StyleBoxFlat.new()
			csb.bg_color = Color(0.87, 0.81, 0.69, 0.82)
			csb.set_border_width_all(0)
			csb.set_corner_radius_all(8)
			card.add_theme_stylebox_override("panel", csb)
			paper.add_child(card)

			var n_lbl := UIAssets.create_label(
				m[0], 16, UIAssets.COL_INK, "extrabold", HORIZONTAL_ALIGNMENT_CENTER
			)
			n_lbl.position = Vector2(8, 9)
			n_lbl.size = Vector2(284, 22)
			card.add_child(n_lbl)

			var r_lbl := UIAssets.create_label(
				m[1], 12, Color(0.36, 0.28, 0.20), "semibold", HORIZONTAL_ALIGNMENT_CENTER
			)
			r_lbl.position = Vector2(8, 35)
			r_lbl.size = Vector2(284, 20)
			card.add_child(r_lbl)

		var tech := UIAssets.create_label(
			"Gimersia Inspire 2026 — Universitas Nusa Mandiri", 12, UIAssets.COL_INK_MUTED, "semibold",
			HORIZONTAL_ALIGNMENT_CENTER
		)
		tech.position = Vector2(36, 326)
		tech.size = Vector2(628, 22)
		paper.add_child(tech)

		var btn_close := UIAssets.create_wood_button(
			"res://UI/05_modals/btn_modal_brown_wood.png",
			"TUTUP", 16, UIAssets.COL_CREAM, "", "black", 5
		)
		btn_close.position = Vector2(504, 446)
		btn_close.pressed.connect(queue_free)
		board.add_child(btn_close)
