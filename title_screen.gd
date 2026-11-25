# title_screen.gd
# Main menu screen matching Mockup 1: "Lets Clean Up! SlopMountain"
# Features Start Shift, How To Play, Settings, Credits, and Quit Game.

class_name TitleScreen
extends CanvasLayer

signal start_shift_pressed(mode: int)

const UIAssets = preload("res://ui_assets.gd")

var _root: Control = null
var _modal_overlay: Control = null
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
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "TitleRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# 1280 x 720 centered container
	var content := Control.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_CENTER)
	content.offset_left = -640
	content.offset_right = 640
	content.offset_top = -360
	content.offset_bottom = 360
	content.custom_minimum_size = Vector2(1280, 720)
	content.size = Vector2(1280, 720)
	_root.add_child(content)

	# Fullscreen Background (1280 x 720)
	var bg_tex := UIAssets.create_texture_rect("res://UI/04_title/title_bg_full.png")
	bg_tex.position = Vector2.ZERO
	bg_tex.size = Vector2(1280, 720)
	content.add_child(bg_tex)

	# SlopMountain Logo (Top-Left)
	var logo_tex := UIAssets.create_texture_rect("res://UI/04_title/title_logo_slopmountain.png")
	logo_tex.position = Vector2(55, 30)
	logo_tex.custom_minimum_size = Vector2(480, 201)
	logo_tex.size = Vector2(480, 201)
	logo_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(logo_tex)

	# Buttons Stack
	var btn_vbox := VBoxContainer.new()
	btn_vbox.position = Vector2(70, 255)
	btn_vbox.custom_minimum_size = Vector2(340, 380)
	btn_vbox.add_theme_constant_override("separation", 8)
	content.add_child(btn_vbox)

	# 1. START SHIFT -> (Standard Mode)
	var start_btn := UIAssets.create_hover_button(
		"res://UI/04_title/title_btn_primary_normal.png",
		"res://UI/04_title/title_btn_primary_hover.png",
		"START SHIFT  →",
		16,
		Color(0.95, 0.98, 1.0),
		Vector2(320, 56)
	)
	start_btn.pressed.connect(_on_start_shift_pressed)
	btn_vbox.add_child(start_btn)

	# 1b. CHALLENGE MODE -> (Event Rush: Every day is a random event)
	var challenge_btn := UIAssets.create_hover_button(
		"res://UI/04_title/title_btn_quit_normal.png",
		"res://UI/04_title/title_btn_quit_hover_red.png",
		"CHALLENGE MODE  🔥",
		15,
		Color(1.0, 0.82, 0.40),
		Vector2(310, 52)
	)
	challenge_btn.pressed.connect(_on_challenge_mode_pressed)
	btn_vbox.add_child(challenge_btn)

	# 2. HOW TO PLAY
	var htp_btn := UIAssets.create_hover_button(
		"res://UI/04_title/title_btn_secondary_normal.png",
		"res://UI/04_title/title_btn_secondary_hover.png",
		"HOW TO PLAY",
		14,
		Color(0.92, 0.88, 0.82),
		Vector2(295, 50)
	)
	htp_btn.pressed.connect(_on_how_to_play_pressed)
	btn_vbox.add_child(htp_btn)

	# 3. SETTINGS
	var settings_btn := UIAssets.create_hover_button(
		"res://UI/04_title/title_btn_secondary_normal.png",
		"res://UI/04_title/title_btn_secondary_hover.png",
		"SETTINGS",
		14,
		Color(0.92, 0.88, 0.82),
		Vector2(295, 50)
	)
	settings_btn.pressed.connect(_on_settings_pressed)
	btn_vbox.add_child(settings_btn)

	# 4. CREDITS
	var credits_btn := UIAssets.create_hover_button(
		"res://UI/04_title/title_btn_secondary_normal.png",
		"res://UI/04_title/title_btn_secondary_hover.png",
		"CREDITS",
		14,
		Color(0.92, 0.88, 0.82),
		Vector2(295, 50)
	)
	credits_btn.pressed.connect(_on_credits_pressed)
	btn_vbox.add_child(credits_btn)

	# 5. QUIT GAME
	var quit_btn := UIAssets.create_hover_button(
		"res://UI/04_title/title_btn_quit_normal.png",
		"res://UI/04_title/title_btn_quit_hover_red.png",
		"QUIT GAME",
		13,
		Color(0.85, 0.50, 0.45),
		Vector2(235, 44)
	)
	quit_btn.pressed.connect(_on_quit_pressed)
	btn_vbox.add_child(quit_btn)

	# --- CO-OP MULTIPLAYER PANEL (Right side) --------------------------------
	var coop_panel := PanelContainer.new()
	coop_panel.position = Vector2(910, 445)
	coop_panel.custom_minimum_size = Vector2(300, 195)
	var coop_style := StyleBoxFlat.new()
	coop_style.bg_color = Color(0.06, 0.09, 0.14, 0.86)
	coop_style.border_color = Color(0.28, 0.52, 0.78, 0.8)
	coop_style.set_border_width_all(2)
	coop_style.set_corner_radius_all(8)
	coop_style.set_content_margin_all(14)
	coop_panel.add_theme_stylebox_override("panel", coop_style)
	content.add_child(coop_panel)

	var coop_vbox := VBoxContainer.new()
	coop_vbox.add_theme_constant_override("separation", 8)
	coop_panel.add_child(coop_vbox)

	var coop_title := Label.new()
	coop_title.text = "CO-OP (ONLINE / LAN)"
	coop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coop_title.add_theme_font_size_override("font_size", 14)
	coop_title.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	coop_vbox.add_child(coop_title)

	var host_btn := Button.new()
	host_btn.text = "HOST CO-OP (ONLINE)"
	host_btn.custom_minimum_size = Vector2(0, 34)
	host_btn.pressed.connect(_on_host_coop_pressed)
	coop_vbox.add_child(host_btn)

	var host_lan_btn := Button.new()
	host_lan_btn.text = "HOST LAN (PORT 7777)"
	host_lan_btn.custom_minimum_size = Vector2(0, 30)
	host_lan_btn.pressed.connect(_on_host_lan_pressed)
	coop_vbox.add_child(host_lan_btn)

	var join_hbox := HBoxContainer.new()
	join_hbox.add_theme_constant_override("separation", 6)
	coop_vbox.add_child(join_hbox)

	_coop_ip_input = LineEdit.new()
	_coop_ip_input.text = "127.0.0.1"
	_coop_ip_input.placeholder_text = "Room Code or IP"
	_coop_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_hbox.add_child(_coop_ip_input)

	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.custom_minimum_size = Vector2(76, 34)
	join_btn.pressed.connect(_on_join_coop_pressed)
	join_hbox.add_child(join_btn)

	_coop_status_label = Label.new()
	_coop_status_label.text = ""
	_coop_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coop_status_label.add_theme_font_size_override("font_size", 12)
	_coop_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))
	coop_vbox.add_child(_coop_status_label)

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

	# --- FOOTER LABELS -----------------------------------------------------
	var footer_left := Label.new()
	footer_left.text = "v0.1 PROTOTYPE  //  GIMERSIA INSPIRE 2026"
	footer_left.position = Vector2(85, 672)
	footer_left.size = Vector2(400, 24)
	footer_left.add_theme_color_override("font_color", Color(0.48, 0.52, 0.58, 0.75))
	footer_left.add_theme_font_size_override("font_size", 12)
	content.add_child(footer_left)

	var footer_right := Label.new()
	footer_right.text = "SLOPMOUNTAIN  //  RANGER UNIT 01"
	footer_right.position = Vector2(880, 672)
	footer_right.size = Vector2(320, 24)
	footer_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_right.add_theme_color_override("font_color", Color(0.48, 0.52, 0.58, 0.75))
	footer_right.add_theme_font_size_override("font_size", 12)
	content.add_child(footer_right)

	# Modal Overlay for Popups (How to Play, Settings, Credits)
	_modal_overlay = Control.new()
	_modal_overlay.name = "ModalOverlay"
	_modal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.visible = false
	_root.add_child(_modal_overlay)

	var modal_dim := ColorRect.new()
	modal_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_dim.color = Color(0, 0, 0, 0.7)
	_modal_overlay.add_child(modal_dim)


func _on_start_shift_pressed() -> void:
	_launch_game(0) # Standard Mode


func _on_host_coop_pressed() -> void:
	var err := NetworkManager.host_game()
	if err != OK:
		if is_instance_valid(_coop_status_label):
			_coop_status_label.text = "Failed to host (port busy?)"
		return
	_show_host_lobby_modal()


func _on_host_lan_pressed() -> void:
	var err := NetworkManager.host_lan_game()
	if err != OK:
		if is_instance_valid(_coop_status_label):
			_coop_status_label.text = "Failed to host LAN (port 7777 busy?)"
		return
	_show_host_lobby_modal("LAN / VPN Mode — Join via 127.0.0.1 or LAN IP (Port 7777)")


func _on_join_coop_pressed() -> void:
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

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -185
	panel.offset_bottom = 185
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.96)
	style.border_color = Color(0.28, 0.58, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "🌐 CO-OP LOBBY — WAITING FOR PLAYERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
	vbox.add_child(title)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	vbox.add_child(code_row)

	_lobby_code_label = Label.new()
	if not initial_status.is_empty():
		_lobby_code_label.text = initial_status
	elif not NetworkManager.room_code.is_empty():
		_lobby_code_label.text = "Room ID: %s" % NetworkManager.room_code
	else:
		_lobby_code_label.text = "Room ID: Connecting to Noray..."
	_lobby_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_code_label.add_theme_font_size_override("font_size", 14)
	_lobby_code_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	code_row.add_child(_lobby_code_label)

	_lobby_copy_btn = Button.new()
	_lobby_copy_btn.text = "COPY CODE"
	_lobby_copy_btn.custom_minimum_size = Vector2(110, 34)
	_lobby_copy_btn.disabled = NetworkManager.room_code.is_empty()
	_lobby_copy_btn.pressed.connect(func():
		if not NetworkManager.room_code.is_empty():
			DisplayServer.clipboard_set(NetworkManager.room_code)
			_lobby_copy_btn.text = "COPIED!"
	)
	code_row.add_child(_lobby_copy_btn)

	var hint := Label.new()
	hint.text = "LAN / VPN players can also join via your IP on Port 7777 (local: 127.0.0.1)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.76, 0.84))
	vbox.add_child(hint)

	_lobby_players_label = Label.new()
	_lobby_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_players_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_lobby_players_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_lobby_start_btn = Button.new()
	_lobby_start_btn.custom_minimum_size = Vector2(220, 44)
	_lobby_start_btn.pressed.connect(func():
		NetworkManager.start_coop_match(0)
	)
	btn_row.add_child(_lobby_start_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CLOSE ROOM"
	cancel_btn.custom_minimum_size = Vector2(130, 44)
	cancel_btn.pressed.connect(func():
		NetworkManager.leave_game()
		_modal_overlay.visible = false
	)
	btn_row.add_child(cancel_btn)

	_refresh_lobby_state()


func _show_client_waiting_modal() -> void:
	_clear_modal()
	_modal_overlay.visible = true

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -110
	panel.offset_bottom = 110
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.96)
	style.border_color = Color(0.35, 0.85, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "✅ Connected to Host!\nWaiting for host to start the shift..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.75, 1.0, 0.82))
	vbox.add_child(lbl)

	var leave_btn := Button.new()
	leave_btn.text = "LEAVE ROOM"
	leave_btn.custom_minimum_size = Vector2(150, 40)
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
	var guest_count := NetworkManager.spawned_players.size()
	var total := 1 + guest_count
	if is_instance_valid(_lobby_players_label):
		if guest_count == 0:
			_lobby_players_label.text = "Players in room: 1 / 5 (Waiting for another player...)"
			_lobby_players_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			_lobby_players_label.text = "Players in room: %d / 5 (Ready!)" % total
			_lobby_players_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	if is_instance_valid(_lobby_start_btn):
		_lobby_start_btn.disabled = (guest_count == 0)
		_lobby_start_btn.text = "WAITING FOR PLAYER..." if guest_count == 0 else "START SHIFT  →"


func _on_challenge_mode_pressed() -> void:
	_show_challenge_modal()


func _show_challenge_modal() -> void:
	_clear_modal()
	_modal_overlay.visible = true

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -210
	panel.offset_bottom = 210

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.12, 0.98)
	sb.border_color = Color(0.95, 0.35, 0.20)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "🔥 CHALLENGE GAMEMODE: DAILY EVENT RUSH 🔥"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.30))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "Are you ready for the ultimate Ranger trial?\nIn Challenge Mode, normal shift contracts are suspended:\n\n" \
		+ "• EACH DAY IS A RANDOM EMERGENCY EVENT!\n" \
		+ "• Face Expeditions, Wildlife Taming, Pest Hunting, Gold Rush, Surprise Audits, and Colossus Bosses back-to-back!\n" \
		+ "• Day 8 Finale: The Evernight Colossus Boss Fight.\n" \
		+ "• No standard contracts — pure survival & event mastery!"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.92, 0.90, 0.88))
	vbox.add_child(desc)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_hbox)

	var start_chal_btn := UIAssets.create_textured_button(
		"res://UI/02_shop/btn_audit_red_wood.png",
		"START CHALLENGE  🔥",
		14,
		Color.WHITE,
		"",
		Vector2(220, 50)
	)
	start_chal_btn.pressed.connect(func():
		_modal_overlay.visible = false
		_launch_game(1) # Challenge Mode
	)
	btn_hbox.add_child(start_chal_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(100, 44)
	cancel_btn.pressed.connect(func():
		_modal_overlay.visible = false
	)
	btn_hbox.add_child(cancel_btn)


func _launch_game(mode: int) -> void:
	emit_signal("start_shift_pressed", mode)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.3)
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


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_how_to_play_pressed() -> void:
	_show_modal("HOW TO PLAY",
		"📋 CONTROLS & OBJECTIVES:\n\n" +
		"• [W, A, S, D]: Move around the park.\n" +
		"• [SPACE]: Jump / Climb steep trash piles.\n" +
		"• [SHIFT]: Sprint across long trails.\n" +
		"• [LEFT CLICK / E]: Pick up trash and place in backpack.\n" +
		"• [RIGHT CLICK]: Throw held trash into matching bins / machines.\n" +
		"• [Q]: Open Contract Board (Choose Daily Quota & Modifiers).\n" +
		"• [B]: Open Mossy's Junkyard Outpost (Mod Shop).\n" +
		"• [M]: Machine Shop (Crusher, Burner, Composter).\n" +
		"• [N]: Hold to end day early once quota is achieved!\n\n" +
		"⚠️ Complete the daily quota before sunset or Taman Nasional will be shut down!"
	)


func _on_settings_pressed() -> void:
	_clear_modal()
	_modal_overlay.visible = true

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -180
	panel.offset_bottom = 180

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.96)
	sb.border_color = Color(0.35, 0.65, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	vbox.add_child(title)

	# Master Volume
	var vol_box := HBoxContainer.new()
	var vol_lbl := Label.new()
	vol_lbl.text = "Master Volume:"
	vol_lbl.custom_minimum_size = Vector2(140, 0)
	vol_box.add_child(vol_lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v): AudioServer.set_bus_volume_db(0, linear_to_db(v)))
	vol_box.add_child(slider)
	vbox.add_child(vol_box)

	# Fullscreen Toggle
	var fs_check := CheckButton.new()
	fs_check.text = "Fullscreen Mode"
	fs_check.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	fs_check.toggled.connect(func(pressed):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
		)
	)
	vbox.add_child(fs_check)

	# Close Button
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.pressed.connect(func(): _modal_overlay.visible = false)
	vbox.add_child(close_btn)


func _on_credits_pressed() -> void:
	_show_modal("CREDITS",
		"🌲 SLOPMOUNTAIN // RANGER UNIT 01 🌲\n\n" +
		"Game Design & Development:\n" +
		"GIMERSIA INSPIRE 2026 TEAM\n\n" +
		"Art & UI Design:\n" +
		"SlopMountain Ranger Art Team\n\n" +
		"Audio & Music:\n" +
		"SlopMountain Ambient & Boss Fight Soundscapes\n\n" +
		"Special Thanks to All Park Rangers Keeping Nature Clean!"
	)


func _show_modal(modal_title: String, body_text: String) -> void:
	_clear_modal()
	_modal_overlay.visible = true

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -200
	panel.offset_bottom = 200

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.96)
	sb.border_color = Color(0.35, 0.65, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	_modal_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = modal_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	vbox.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	vbox.add_child(body)

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.pressed.connect(func(): _modal_overlay.visible = false)
	vbox.add_child(close_btn)


func _clear_modal() -> void:
	for child in _modal_overlay.get_children():
		if not (child is ColorRect):
			child.queue_free()
