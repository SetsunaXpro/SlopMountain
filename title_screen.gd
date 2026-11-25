# title_screen.gd
# SlopMountain Main Menu Overlay (CanvasLayer, layer = 100)
# Preserves 100% of Co-op Multiplayer (Steam / Noray / LAN), Challenge Mode,
# and DayNightCycle launch hooks while matching the finalized Figma Ranger aesthetic.

class_name TitleScreen
extends CanvasLayer

signal start_shift_pressed(mode: int)

const UIAssets = preload("res://ui_assets.gd")
const UIModals = preload("res://ui_modals.gd")

const BGM_PATH := "res://Music/f@ct Fun days (music or buy menu ost).wav"

var _root: Control = null
var _content: Control = null
var _logo_tex: TextureRect = null
var _logo_base_y: float = 16.0
var _anim_time: float = 0.0
var _bgm_player: AudioStreamPlayer = null

var _modal_overlay: Control = null
var _active_popup: CanvasLayer = null

# Co-op Multiplayer Widgets
var _coop_ip_input: LineEdit = null
var _coop_status_label: Label = null
var _lobby_code_label: Label = null
var _lobby_copy_btn: Button = null
var _lobby_players_label: Label = null
var _lobby_start_btn: Button = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("title_screen")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UIAssets.load_and_apply_settings()
	_build_ui()
	_connect_network_signals()
	_start_bgm()


func _exit_tree() -> void:
	_disconnect_network_signals()
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()


func _process(delta: float) -> void:
	_anim_time += delta
	if is_instance_valid(_logo_tex):
		_logo_tex.position.y = _logo_base_y + sin(_anim_time * 1.65) * 4.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_instance_valid(_modal_overlay) and _modal_overlay.visible:
			_modal_overlay.visible = false
			get_viewport().set_input_as_handled()


# ===========================================================================
# Audio
# ===========================================================================

func _start_bgm() -> void:
	if not ResourceLoader.exists(BGM_PATH):
		return
	var stream := load(BGM_PATH) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "TitleBGM"
	_bgm_player.stream = stream
	_bgm_player.bus = "Music"
	_bgm_player.volume_db = -8.0
	add_child(_bgm_player)
	_bgm_player.play()


# ===========================================================================
# UI Construction
# ===========================================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "TitleRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Full-bleed dark backdrop for non-16:9 monitors
	var outer_bg := ColorRect.new()
	outer_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_bg.color = Color(0.05, 0.08, 0.11, 1.0)
	_root.add_child(outer_bg)

	# 1280 x 720 centered canvas container
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

	# 1. Fullscreen Key Art Background (1280 x 720)
	var bg_tex := UIAssets.create_texture_rect("res://UI/04_title/title_bg_full.png")
	bg_tex.position = Vector2.ZERO
	bg_tex.size = Vector2(1280, 720)
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(bg_tex)

	# 2. SlopMountain Logo (Top-Left, gentle bobbing — scaled to clear START SHIFT plank)
	_logo_tex = UIAssets.create_texture_rect("res://UI/04_title/title_logo_slopmountain.png", true)
	_logo_tex.position = Vector2(46, _logo_base_y)
	_logo_tex.custom_minimum_size = Vector2(460, 193)
	_logo_tex.size = Vector2(460, 193)
	_logo_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_logo_tex)

	# 3. Main Menu Wood Plank Buttons (Positioned cleanly below logo & above y=676 footer)
	var start_btn := UIAssets.create_wood_button(
		"res://UI/04_title/title_btn_primary_normal.png",
		"START SHIFT  ➔",
		19,
		Color(0.98, 0.99, 1.0),
		"res://UI/04_title/title_btn_primary_hover.png",
		"black",
		5
	)
	start_btn.position = Vector2(48, 224)
	start_btn.custom_minimum_size = Vector2(346, 80)
	start_btn.size = Vector2(346, 80)
	start_btn.pressed.connect(_on_start_shift_pressed)
	_content.add_child(start_btn)

	var challenge_btn := UIAssets.create_wood_button(
		"res://UI/04_title/title_btn_quit_normal.png",
		"CHALLENGE MODE  🔥",
		15,
		Color(1.0, 0.84, 0.42),
		"res://UI/04_title/title_btn_quit_hover_red.png",
		"black",
		4
	)
	challenge_btn.position = Vector2(52, 298)
	challenge_btn.custom_minimum_size = Vector2(326, 72)
	challenge_btn.size = Vector2(326, 72)
	challenge_btn.pressed.connect(_on_challenge_mode_pressed)
	_content.add_child(challenge_btn)

	var htp_btn := UIAssets.create_wood_button(
		"res://UI/04_title/title_btn_secondary_normal.png",
		"HOW TO PLAY",
		15,
		UIAssets.COL_CREAM,
		"res://UI/04_title/title_btn_secondary_hover.png",
		"black",
		4
	)
	htp_btn.position = Vector2(52, 364)
	htp_btn.custom_minimum_size = Vector2(314, 70)
	htp_btn.size = Vector2(314, 70)
	htp_btn.pressed.connect(_on_how_to_play_pressed)
	_content.add_child(htp_btn)

	var settings_btn := UIAssets.create_wood_button(
		"res://UI/04_title/title_btn_secondary_normal.png",
		"SETTINGS",
		15,
		UIAssets.COL_CREAM,
		"res://UI/04_title/title_btn_secondary_hover.png",
		"black",
		4
	)
	settings_btn.position = Vector2(52, 428)
	settings_btn.custom_minimum_size = Vector2(314, 70)
	settings_btn.size = Vector2(314, 70)
	settings_btn.pressed.connect(_on_settings_pressed)
	_content.add_child(settings_btn)

	var credits_btn := UIAssets.create_wood_button(
		"res://UI/04_title/title_btn_secondary_normal.png",
		"CREDITS",
		15,
		UIAssets.COL_CREAM,
		"res://UI/04_title/title_btn_secondary_hover.png",
		"black",
		4
	)
	credits_btn.position = Vector2(52, 492)
	credits_btn.custom_minimum_size = Vector2(314, 70)
	credits_btn.size = Vector2(314, 70)
	credits_btn.pressed.connect(_on_credits_pressed)
	_content.add_child(credits_btn)

	var quit_btn := UIAssets.create_wood_button(
		"res://UI/04_title/title_btn_quit_normal.png",
		"QUIT GAME",
		14,
		Color(0.95, 0.72, 0.68),
		"res://UI/04_title/title_btn_quit_hover_red.png",
		"black",
		4
	)
	quit_btn.position = Vector2(52, 560)
	quit_btn.custom_minimum_size = Vector2(246, 66)
	quit_btn.size = Vector2(246, 66)
	quit_btn.pressed.connect(_on_quit_pressed)
	_content.add_child(quit_btn)

	# 4. Co-op Multiplayer Panel (Bottom-Right, matte card without outlines or eyebrows)
	_build_coop_panel()

	# 5. Single subtle version tag (bottom-left only)
	var footer_left := UIAssets.create_label(
		"gimersia alpha 0.2.0",
		12, Color(0.84, 0.82, 0.78, 0.56), "semibold",
		HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_CENTER, 0.4
	)
	footer_left.position = Vector2(68, 678)
	footer_left.size = Vector2(320, 22)
	_content.add_child(footer_left)

	# 6. Modal Overlay for Challenge Mode & Co-op Lobby Dialogs
	_modal_overlay = Control.new()
	_modal_overlay.name = "ModalOverlay"
	_modal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_overlay.visible = false
	_root.add_child(_modal_overlay)

	var modal_dim := ColorRect.new()
	modal_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_dim.color = Color(0.03, 0.05, 0.08, 0.76)
	_modal_overlay.add_child(modal_dim)


func _build_coop_panel() -> void:
	var coop_panel := PanelContainer.new()
	coop_panel.name = "CoopPanel"
	coop_panel.position = Vector2(894, 434)
	coop_panel.custom_minimum_size = Vector2(328, 206)
	coop_panel.size = Vector2(328, 206)
	var coop_style := StyleBoxFlat.new()
	coop_style.bg_color = Color(0.09, 0.11, 0.14, 0.88)
	coop_style.set_border_width_all(0)
	coop_style.set_corner_radius_all(10)
	coop_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	coop_style.shadow_size = 12
	coop_style.shadow_offset = Vector2(0, 4)
	coop_style.content_margin_left = 18
	coop_style.content_margin_right = 18
	coop_style.content_margin_top = 16
	coop_style.content_margin_bottom = 14
	coop_panel.add_theme_stylebox_override("panel", coop_style)
	_content.add_child(coop_panel)

	var coop_vbox := VBoxContainer.new()
	coop_vbox.add_theme_constant_override("separation", 9)
	coop_panel.add_child(coop_vbox)

	var coop_title := UIAssets.create_label(
		"Co-op Multiplayer",
		15, UIAssets.COL_CREAM, "extrabold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.4
	)
	coop_vbox.add_child(coop_title)

	var host_btn := _create_panel_button("Host Online", Color(0.18, 0.46, 0.72), Color(0.24, 0.56, 0.86))
	host_btn.custom_minimum_size = Vector2(0, 36)
	host_btn.pressed.connect(_on_host_coop_pressed)
	coop_vbox.add_child(host_btn)

	var host_lan_btn := _create_panel_button("Host LAN (Port 7777)", Color(0.20, 0.25, 0.30), Color(0.28, 0.34, 0.40))
	host_lan_btn.custom_minimum_size = Vector2(0, 34)
	host_lan_btn.pressed.connect(_on_host_lan_pressed)
	coop_vbox.add_child(host_lan_btn)

	var join_hbox := HBoxContainer.new()
	join_hbox.add_theme_constant_override("separation", 8)
	coop_vbox.add_child(join_hbox)

	_coop_ip_input = LineEdit.new()
	_coop_ip_input.text = "127.0.0.1"
	_coop_ip_input.placeholder_text = "Room Code / IP"
	_coop_ip_input.custom_minimum_size = Vector2(0, 36)
	_coop_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coop_ip_input.add_theme_font_override("font", UIAssets.get_font("semibold"))
	_coop_ip_input.add_theme_font_size_override("font_size", 13)
	_coop_ip_input.add_theme_color_override("font_color", UIAssets.COL_CREAM)
	var input_sb := StyleBoxFlat.new()
	input_sb.bg_color = Color(0.05, 0.06, 0.09, 0.94)
	input_sb.set_border_width_all(0)
	input_sb.set_corner_radius_all(6)
	input_sb.content_margin_left = 12
	input_sb.content_margin_right = 8
	_coop_ip_input.add_theme_stylebox_override("normal", input_sb)
	var input_foc: StyleBoxFlat = input_sb.duplicate()
	input_foc.bg_color = Color(0.08, 0.10, 0.14, 0.98)
	_coop_ip_input.add_theme_stylebox_override("focus", input_foc)
	join_hbox.add_child(_coop_ip_input)

	var join_btn := _create_panel_button("Join", Color(0.78, 0.48, 0.14), Color(0.90, 0.58, 0.18))
	join_btn.custom_minimum_size = Vector2(78, 36)
	join_btn.pressed.connect(_on_join_coop_pressed)
	join_hbox.add_child(join_btn)

	_coop_status_label = UIAssets.create_label(
		"", 11, UIAssets.COL_GOLD, "semibold",
		HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER
	)
	_coop_status_label.custom_minimum_size = Vector2(0, 14)
	coop_vbox.add_child(_coop_status_label)


func _create_panel_button(label_text: String, bg_col: Color, hov_col: Color, txt_col: Color = Color.WHITE) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", UIAssets.get_font("bold"))
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.58, 0.62))

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	btn.add_theme_stylebox_override("normal", sb)

	var sb_h: StyleBoxFlat = sb.duplicate()
	sb_h.bg_color = hov_col
	btn.add_theme_stylebox_override("hover", sb_h)

	var sb_p: StyleBoxFlat = sb.duplicate()
	sb_p.bg_color = bg_col.darkened(0.16)
	sb_p.shadow_size = 0
	btn.add_theme_stylebox_override("pressed", sb_p)

	var sb_d: StyleBoxFlat = sb.duplicate()
	sb_d.bg_color = Color(0.16, 0.18, 0.22, 0.75)
	sb_d.shadow_size = 0
	btn.add_theme_stylebox_override("disabled", sb_d)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


# ===========================================================================
# Network Signal Wiring (Safe even if NetworkManager is absent in preview)
# ===========================================================================

func _connect_network_signals() -> void:
	if NetworkManager == null:
		return
	if not NetworkManager.connection_succeeded.is_connected(_on_coop_connected):
		NetworkManager.connection_succeeded.connect(_on_coop_connected)
	if not NetworkManager.connection_failed.is_connected(_on_coop_failed):
		NetworkManager.connection_failed.connect(_on_coop_failed)
	if not NetworkManager.noray_room_ready.is_connected(_on_noray_room_ready):
		NetworkManager.noray_room_ready.connect(_on_noray_room_ready)
	if not NetworkManager.player_connected.is_connected(_on_lobby_players_changed):
		NetworkManager.player_connected.connect(_on_lobby_players_changed)
	if not NetworkManager.player_disconnected.is_connected(_on_lobby_players_changed):
		NetworkManager.player_disconnected.connect(_on_lobby_players_changed)
	if not NetworkManager.coop_match_started.is_connected(_on_coop_match_started):
		NetworkManager.coop_match_started.connect(_on_coop_match_started)


func _disconnect_network_signals() -> void:
	if NetworkManager == null:
		return
	if NetworkManager.connection_succeeded.is_connected(_on_coop_connected):
		NetworkManager.connection_succeeded.disconnect(_on_coop_connected)
	if NetworkManager.connection_failed.is_connected(_on_coop_failed):
		NetworkManager.connection_failed.disconnect(_on_coop_failed)
	if NetworkManager.noray_room_ready.is_connected(_on_noray_room_ready):
		NetworkManager.noray_room_ready.disconnect(_on_noray_room_ready)
	if NetworkManager.player_connected.is_connected(_on_lobby_players_changed):
		NetworkManager.player_connected.disconnect(_on_lobby_players_changed)
	if NetworkManager.player_disconnected.is_connected(_on_lobby_players_changed):
		NetworkManager.player_disconnected.disconnect(_on_lobby_players_changed)
	if NetworkManager.coop_match_started.is_connected(_on_coop_match_started):
		NetworkManager.coop_match_started.disconnect(_on_coop_match_started)


# ===========================================================================
# Button Handlers & Co-op Lobby Modals
# ===========================================================================

func _on_start_shift_pressed() -> void:
	_launch_game(0)


func _on_challenge_mode_pressed() -> void:
	_show_challenge_modal()


func _on_how_to_play_pressed() -> void:
	if is_instance_valid(_active_popup):
		_active_popup.queue_free()
	_active_popup = UIModals.open_how_to_play(get_tree().root)


func _on_settings_pressed() -> void:
	if is_instance_valid(_active_popup):
		_active_popup.queue_free()
	_active_popup = UIModals.open_settings(get_tree().root)


func _on_credits_pressed() -> void:
	if is_instance_valid(_active_popup):
		_active_popup.queue_free()
	_active_popup = UIModals.open_credits(get_tree().root)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_host_coop_pressed() -> void:
	if NetworkManager == null:
		return
	var err := NetworkManager.host_game()
	if err != OK:
		if is_instance_valid(_coop_status_label):
			_coop_status_label.text = "Failed to host (port busy?)"
		return
	_show_host_lobby_modal()


func _on_host_lan_pressed() -> void:
	if NetworkManager == null:
		return
	var err := NetworkManager.host_lan_game()
	if err != OK:
		if is_instance_valid(_coop_status_label):
			_coop_status_label.text = "Failed to host LAN (port 7777 busy?)"
		return
	_show_host_lobby_modal("LAN / VPN Mode — Join via 127.0.0.1 or LAN IP (Port 7777)")


func _on_join_coop_pressed() -> void:
	if NetworkManager == null:
		return
	var target := "127.0.0.1"
	if is_instance_valid(_coop_ip_input) and not _coop_ip_input.text.strip_edges().is_empty():
		target = _coop_ip_input.text.strip_edges()
	var err := NetworkManager.join_by_code_or_ip(target)
	if err != OK:
		if is_instance_valid(_coop_status_label):
			_coop_status_label.text = "Invalid code or could not start client"
		return
	if is_instance_valid(_coop_status_label):
		_coop_status_label.text = "Connecting..."


func _on_coop_connected() -> void:
	if is_instance_valid(_coop_status_label):
		_coop_status_label.text = "Connected!"
	_show_client_waiting_modal()


func _on_coop_failed() -> void:
	if is_instance_valid(_coop_status_label):
		_coop_status_label.text = "Connection failed!"


func _on_coop_match_started(mode: int) -> void:
	if is_instance_valid(_modal_overlay):
		_modal_overlay.visible = false
	_launch_game(mode)


func _show_host_lobby_modal(initial_status: String = "") -> void:
	_clear_modal()
	_modal_overlay.visible = true

	var panel := _create_ranger_modal_panel(Vector2(640, 360), Color(0.84, 0.62, 0.22))
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := UIAssets.create_label(
		"CO-OP LOBBY — WAITING FOR RANGERS",
		19, UIAssets.COL_GOLD, "black", HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.45
	)
	vbox.add_child(title)

	var code_box := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.05, 0.07, 0.10, 0.95)
	csb.border_color = Color(0.32, 0.44, 0.58, 0.7)
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(6)
	csb.set_content_margin_all(10)
	code_box.add_theme_stylebox_override("panel", csb)
	vbox.add_child(code_box)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	code_box.add_child(code_row)

	_lobby_code_label = UIAssets.create_label("", 13, UIAssets.COL_GOLD, "mono")
	if not initial_status.is_empty():
		_lobby_code_label.text = initial_status
	elif not NetworkManager.room_code.is_empty():
		_lobby_code_label.text = "Room ID: %s" % NetworkManager.room_code
	else:
		_lobby_code_label.text = "Room ID: Connecting to Noray..."
	_lobby_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_lobby_code_label)

	_lobby_copy_btn = _create_panel_button("COPY CODE", Color(0.18, 0.46, 0.72), Color(0.26, 0.58, 0.88))
	_lobby_copy_btn.custom_minimum_size = Vector2(114, 34)
	_lobby_copy_btn.disabled = NetworkManager.room_code.is_empty()
	_lobby_copy_btn.pressed.connect(func():
		if not NetworkManager.room_code.is_empty():
			DisplayServer.clipboard_set(NetworkManager.room_code)
			_lobby_copy_btn.text = "COPIED!"
	)
	code_row.add_child(_lobby_copy_btn)

	var hint := UIAssets.create_label(
		"LAN / VPN players can also join via your IP on Port 7777 (local: 127.0.0.1).",
		12, Color(0.72, 0.78, 0.84), "semibold", HORIZONTAL_ALIGNMENT_CENTER
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	_lobby_players_label = UIAssets.create_label("", 15, UIAssets.COL_CREAM, "black", HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_lobby_players_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_lobby_start_btn = _create_panel_button("WAITING FOR PLAYER...", Color(0.16, 0.52, 0.28), Color(0.22, 0.66, 0.36))
	_lobby_start_btn.custom_minimum_size = Vector2(236, 44)
	_lobby_start_btn.pressed.connect(func():
		NetworkManager.start_coop_match(0)
	)
	btn_row.add_child(_lobby_start_btn)

	var cancel_btn := _create_panel_button("CLOSE ROOM", Color(0.56, 0.18, 0.16), Color(0.74, 0.24, 0.20))
	cancel_btn.custom_minimum_size = Vector2(146, 44)
	cancel_btn.pressed.connect(func():
		NetworkManager.leave_game()
		_modal_overlay.visible = false
	)
	btn_row.add_child(cancel_btn)

	_refresh_lobby_state()


func _show_client_waiting_modal() -> void:
	_clear_modal()
	_modal_overlay.visible = true

	var panel := _create_ranger_modal_panel(Vector2(520, 220), UIAssets.COL_GREEN_LIGHT)
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var lbl := UIAssets.create_label(
		"Connected to Host!\nWaiting for host to start the shift...",
		16, Color(0.72, 1.0, 0.80), "bold", HORIZONTAL_ALIGNMENT_CENTER
	)
	vbox.add_child(lbl)

	var leave_btn := _create_panel_button("LEAVE ROOM", Color(0.56, 0.18, 0.16), Color(0.74, 0.24, 0.20))
	leave_btn.custom_minimum_size = Vector2(160, 42)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.pressed.connect(func():
		NetworkManager.leave_game()
		_modal_overlay.visible = false
	)
	vbox.add_child(leave_btn)


func _on_noray_room_ready(success: bool, room_id: String, status_msg: String) -> void:
	if is_instance_valid(_lobby_code_label):
		if success:
			if status_msg.contains("Steam"):
				_lobby_code_label.text = "Steam Lobby ID: %s  (%s)" % [room_id, status_msg]
			else:
				_lobby_code_label.text = "Room ID: %s  (Local: 127.0.0.1:%d)" % [room_id, Noray.local_port]
		else:
			_lobby_code_label.text = status_msg
	if is_instance_valid(_lobby_copy_btn):
		_lobby_copy_btn.disabled = room_id.is_empty()


func _on_lobby_players_changed(_peer_id: int) -> void:
	_refresh_lobby_state()


func _refresh_lobby_state() -> void:
	if NetworkManager == null:
		return
	var guest_count := NetworkManager.spawned_players.size()
	var total := 1 + guest_count
	if is_instance_valid(_lobby_players_label):
		if guest_count == 0:
			_lobby_players_label.text = "Players in room: 1 / 5 (Waiting for another player...)"
			_lobby_players_label.add_theme_color_override("font_color", UIAssets.COL_GOLD)
		else:
			_lobby_players_label.text = "Players in room: %d / 5 (Ready!)" % total
			_lobby_players_label.add_theme_color_override("font_color", UIAssets.COL_GREEN_LIGHT)
	if is_instance_valid(_lobby_start_btn):
		_lobby_start_btn.disabled = (guest_count == 0)
		_lobby_start_btn.text = "WAITING FOR PLAYER..." if guest_count == 0 else "START SHIFT  ➔"


func _show_challenge_modal() -> void:
	_clear_modal()
	_modal_overlay.visible = true

	var panel := _create_ranger_modal_panel(Vector2(640, 410), Color(0.92, 0.34, 0.22))
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := UIAssets.create_label(
		"🔥 CHALLENGE GAMEMODE: DAILY EVENT RUSH 🔥",
		17, Color(1.0, 0.48, 0.32), "black", HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER, 0.5
	)
	vbox.add_child(title)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(0.92, 0.34, 0.22, 0.45)
	vbox.add_child(sep)

	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_override("font", UIAssets.get_font("semibold"))
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", UIAssets.COL_CREAM)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.text = "Are you ready for the ultimate Ranger trial?\nIn Challenge Mode, normal shift contracts are suspended:\n\n" \
		+ "• EACH DAY IS A RANDOM EMERGENCY EVENT!\n" \
		+ "• Face Expeditions, Wildlife Taming, Pest Hunting, Gold Rush, Surprise Audits, and Colossus Bosses back-to-back!\n" \
		+ "• Day 8 Finale: The Evernight Colossus Boss Fight.\n" \
		+ "• No standard contracts — pure survival & event mastery!"
	vbox.add_child(desc)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 18)
	vbox.add_child(btn_hbox)

	var start_chal_btn := UIAssets.create_wood_button(
		"res://UI/02_shop/btn_audit_red_wood.png",
		"START CHALLENGE  🔥",
		15,
		Color.WHITE,
		"",
		"black",
		5
	)
	start_chal_btn.custom_minimum_size = Vector2(268, 74)
	start_chal_btn.pressed.connect(func():
		_modal_overlay.visible = false
		_launch_game(1)
	)
	btn_hbox.add_child(start_chal_btn)

	var cancel_btn := UIAssets.create_wood_button(
		"res://UI/05_modals/btn_modal_brown_wood.png",
		"CANCEL",
		14,
		UIAssets.COL_CREAM,
		"",
		"black",
		5
	)
	cancel_btn.custom_minimum_size = Vector2(168, 68)
	cancel_btn.pressed.connect(func():
		_modal_overlay.visible = false
	)
	btn_hbox.add_child(cancel_btn)


func _create_ranger_modal_panel(panel_size: Vector2, _border_col: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_bottom = panel_size.y * 0.5

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.97)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _launch_game(mode: int) -> void:
	emit_signal("start_shift_pressed", mode)
	if is_instance_valid(_bgm_player):
		var bgm_tw := create_tween()
		bgm_tw.tween_property(_bgm_player, "volume_db", -40.0, 0.25)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func():
		var dnc = get_tree().get_first_node_in_group("day_night_cycle")
		if dnc:
			if "event_system" in dnc and dnc.event_system and dnc.event_system.has_method("set_game_mode"):
				dnc.event_system.set_game_mode(mode)
			elif dnc.has_method("set_game_mode"):
				dnc.set_game_mode(mode)
			if dnc.has_method("open_quota_selection"):
				dnc.open_quota_selection()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		queue_free()
	)


func _clear_modal() -> void:
	for child in _modal_overlay.get_children():
		if not (child is ColorRect):
			child.queue_free()
