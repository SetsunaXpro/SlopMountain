extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal noray_room_ready(success: bool, room_id: String, status_msg: String)
signal coop_match_started(mode: int)
signal quota_votes_updated
signal quota_vote_finalized(winning_idx: int)

const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 4
const PLAYER_SCENE_PATH: String = "res://proto-controller/proto_controller/proto_controller.tscn"
const NORAY_HOST: String = "tomfol.io"
const NORAY_PORT: int = 8890

var spawned_players: Dictionary = {} # peer_id -> Node3D
var placed_machine_records: Dictionary = {} # mid -> { scene_path, pos, rot_y }
var _player_scene: PackedScene = null
var _noray_active: bool = false
var _is_noray_host: bool = false
var _noray_connecting_nat: bool = false
var _noray_target_oid: String = ""
var room_code: String = ""
var steam_available: bool = false
var steam_lobby_id: int = 0
var _steam: Object = null
var quota_votes: Dictionary = {} # peer_id -> contract_idx
var quota_locked: Dictionary = {} # peer_id -> bool


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_steam()


func _process(_delta: float) -> void:
	if steam_available and _steam:
		_steam.call("run_callbacks")


func _init_steam() -> void:
	if OS.has_feature("web"):
		return
	if not ClassDB.class_exists("SteamMultiplayerPeer") or not Engine.has_singleton("Steam"):
		return
	_steam = Engine.get_singleton("Steam")
	var init_res: Dictionary = _steam.call("steamInitEx", 480, false)
	if init_res.get("status", 1) == 0:
		steam_available = true
		_steam.connect("lobby_created", _on_steam_lobby_created)
		_steam.connect("lobby_joined", _on_steam_lobby_joined)
		_steam.connect("join_requested", _on_steam_join_requested)
		print("NetworkManager: Steamworks initialized! Steam Relay ready (AppID 480).")
	else:
		print("NetworkManager: Steam not running (%s) — using Noray / LAN." % str(init_res.get("verbal", "unavailable")))


func is_multiplayer_active() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_host() -> bool:
	return not is_multiplayer_active() or multiplayer.is_server()


func host_game(port: int = DEFAULT_PORT) -> Error:
	if OS.has_feature("web"):
		push_warning("NetworkManager: ENet UDP is unsupported in Web exports; WebRTC/WebSocket transport required.")
		return ERR_UNAVAILABLE
	leave_game()
	if steam_available and _steam:
		_steam.call("createLobby", 2, MAX_CLIENTS + 1) # 2 = LOBBY_TYPE_PUBLIC
		return OK
	_start_noray_host(port)
	return OK


func host_lan_game(port: int = DEFAULT_PORT) -> Error:
	if OS.has_feature("web"):
		push_warning("NetworkManager: ENet UDP is unsupported in Web exports; WebRTC/WebSocket transport required.")
		return ERR_UNAVAILABLE
	leave_game()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("NetworkManager: Failed to host LAN on port %d (err %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	_ensure_host_player_authority()
	print("NetworkManager: Hosting LAN co-op on port %d" % port)
	noray_room_ready.emit(false, "", "LAN / VPN Mode — Join via 127.0.0.1 or LAN IP (Port %d)" % port)
	return OK


func join_by_code_or_ip(input_str: String) -> Error:
	var raw := input_str.strip_edges()
	if raw.is_empty():
		return join_game("127.0.0.1", DEFAULT_PORT)

	if raw.contains(":"):
		var parts := raw.split(":")
		if parts.size() == 2 and parts[1].is_valid_int():
			return join_game(parts[0], parts[1].to_int())

	# If it looks like an IPv4 address (has dots), connect directly via ENet
	if raw.contains("."):
		return join_game(raw, DEFAULT_PORT)

	# Steam Lobby IDs are 64-bit numeric IDs (12+ digits)
	if steam_available and _steam and raw.is_valid_int() and raw.length() >= 12:
		_steam.call("joinLobby", raw.to_int())
		return OK

	# Otherwise treat it as an opaque Noray Room ID (OID)
	_start_noray_client(raw)
	return OK


func join_game(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	if OS.has_feature("web"):
		push_warning("NetworkManager: ENet UDP is unsupported in Web exports; WebRTC/WebSocket transport required.")
		return ERR_UNAVAILABLE
	leave_game()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		push_error("NetworkManager: Failed to join %s:%d (err %d)" % [address, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: Connecting to %s:%d..." % [address, port])
	return OK


func leave_game() -> void:
	for peer_id in spawned_players.keys():
		var p = spawned_players[peer_id]
		if is_instance_valid(p):
			p.queue_free()
	spawned_players.clear()

	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	placed_machine_records.clear()
	quota_votes.clear()
	quota_locked.clear()
	room_code = ""
	_noray_active = false
	_is_noray_host = false
	_noray_connecting_nat = false
	_noray_target_oid = ""
	if Noray.is_connected_to_host():
		Noray.disconnect_from_host()
	if steam_available and _steam and steam_lobby_id != 0:
		_steam.call("leaveLobby", steam_lobby_id)
		steam_lobby_id = 0


func start_coop_match(mode: int = 0) -> void:
	if not is_multiplayer_active():
		coop_match_started.emit(mode)
		return
	if is_host():
		_rpc_start_coop_match.rpc(mode)


@rpc("authority", "call_local", "reliable")
func _rpc_start_coop_match(mode: int) -> void:
	coop_match_started.emit(mode)


func reset_quota_votes() -> void:
	quota_votes.clear()
	quota_locked.clear()
	quota_votes_updated.emit()


func submit_quota_vote(contract_idx: int) -> void:
	if not is_multiplayer_active():
		return
	var my_id := multiplayer.get_unique_id()
	_rpc_submit_quota_vote.rpc(my_id, contract_idx, false)


func lock_quota_vote(contract_idx: int) -> void:
	if not is_multiplayer_active():
		return
	var my_id := multiplayer.get_unique_id()
	_rpc_submit_quota_vote.rpc(my_id, contract_idx, true)


@rpc("any_peer", "call_local", "reliable")
func _rpc_submit_quota_vote(peer_id: int, contract_idx: int, is_locked: bool) -> void:
	quota_votes[peer_id] = contract_idx
	if is_locked:
		quota_locked[peer_id] = true
	quota_votes_updated.emit()

	# If host and all connected peers have locked in, auto-finalize
	if is_host():
		var total_peers := 1 + spawned_players.size()
		if quota_locked.size() >= total_peers:
			resolve_and_start_quota_vote()


func resolve_and_start_quota_vote() -> void:
	if not is_host():
		return
	var counts: Dictionary = {} # idx -> count
	for pid in quota_votes.keys():
		var idx: int = quota_votes[pid]
		counts[idx] = counts.get(idx, 0) + 1

	var host_choice: int = quota_votes.get(1, 1)
	var best_idx: int = host_choice
	var best_count: int = -1
	var tied: bool = false

	for idx in counts.keys():
		var c: int = counts[idx]
		if c > best_count:
			best_count = c
			best_idx = idx
			tied = false
		elif c == best_count:
			tied = true

	# Tie-breaker: goes to the host's choice
	if tied:
		best_idx = host_choice

	_rpc_finalize_quota_vote.rpc(best_idx)


@rpc("authority", "call_local", "reliable")
func _rpc_finalize_quota_vote(winning_idx: int) -> void:
	quota_votes.clear()
	quota_locked.clear()
	quota_vote_finalized.emit(winning_idx)


func _exit_tree() -> void:
	if Noray.is_connected_to_host():
		Noray.disconnect_from_host()
	if steam_available and _steam and steam_lobby_id != 0:
		_steam.call("leaveLobby", steam_lobby_id)
		steam_lobby_id = 0


func _start_noray_host(fallback_port: int) -> void:
	var err := await Noray.connect_to_host(NORAY_HOST, NORAY_PORT)
	if err != OK:
		push_warning("NetworkManager: Noray server unreachable (%s:%d), falling back to LAN ENet port %d." % [NORAY_HOST, NORAY_PORT, fallback_port])
		_host_local_enet(fallback_port, "Noray offline — LAN fallback (Port %d)" % fallback_port)
		return

	Noray.register_host()
	await Noray.on_pid
	var oid: String = Noray.oid
	var reg_err: Error = await Noray.register_remote()
	if reg_err != OK or Noray.local_port <= 0:
		push_warning("NetworkManager: Noray remote registration failed (err %d), falling back to LAN ENet." % reg_err)
		Noray.disconnect_from_host()
		_host_local_enet(fallback_port, "Noray registration failed — LAN fallback (Port %d)" % fallback_port)
		return

	var peer := ENetMultiplayerPeer.new()
	var srv_err := peer.create_server(Noray.local_port, MAX_CLIENTS)
	if srv_err != OK:
		push_error("NetworkManager: Failed to bind ENet server on Noray port %d" % Noray.local_port)
		Noray.disconnect_from_host()
		noray_room_ready.emit(false, "", "Failed to bind local UDP port %d" % Noray.local_port)
		return

	multiplayer.multiplayer_peer = peer
	_ensure_host_player_authority()
	_noray_active = true
	_is_noray_host = true
	room_code = oid

	if not Noray.on_connect_nat.is_connected(_on_noray_host_connect_nat):
		Noray.on_connect_nat.connect(_on_noray_host_connect_nat)
	if not Noray.on_connect_relay.is_connected(_on_noray_host_connect_relay):
		Noray.on_connect_relay.connect(_on_noray_host_connect_relay)

	print("NetworkManager: Hosting via Noray! Room ID (OID): %s (UDP %d)" % [oid, Noray.local_port])
	noray_room_ready.emit(true, oid, "Online via Noray (NAT + Relay)")


func _host_local_enet(port: int, reason: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		noray_room_ready.emit(false, "", "Failed to host on port %d" % port)
		return
	multiplayer.multiplayer_peer = peer
	_ensure_host_player_authority()
	noray_room_ready.emit(false, "", reason)


func _on_noray_host_connect_nat(address: String, port: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer:
		PacketHandshake.over_enet_peer(peer, address, port)


func _on_noray_host_connect_relay(address: String, port: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer:
		PacketHandshake.over_enet_peer(peer, address, port)


func _start_noray_client(oid: String) -> void:
	leave_game()
	_noray_target_oid = oid
	var err := await Noray.connect_to_host(NORAY_HOST, NORAY_PORT)
	if err != OK:
		push_warning("NetworkManager: Could not reach Noray (%s:%d)" % [NORAY_HOST, NORAY_PORT])
		connection_failed.emit()
		return

	Noray.register_host()
	await Noray.on_pid
	var reg_err: Error = await Noray.register_remote()
	if reg_err != OK or Noray.local_port <= 0:
		push_warning("NetworkManager: Noray client port registration failed.")
		Noray.disconnect_from_host()
		connection_failed.emit()
		return

	if not Noray.on_connect_nat.is_connected(_on_noray_client_connect_nat):
		Noray.on_connect_nat.connect(_on_noray_client_connect_nat)
	if not Noray.on_connect_relay.is_connected(_on_noray_client_connect_relay):
		Noray.on_connect_relay.connect(_on_noray_client_connect_relay)

	_noray_active = true
	_is_noray_host = false
	_noray_connecting_nat = true
	Noray.connect_nat(oid)

	# Auto-fallback to Noray Relay if NAT punchthrough doesn't connect within 4 seconds
	get_tree().create_timer(4.0).timeout.connect(func():
		if _noray_connecting_nat and _noray_target_oid == oid:
			if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
				print("NetworkManager: NAT punchthrough timed out, falling back to Noray relay...")
				_noray_connecting_nat = false
				Noray.connect_relay(oid)
				# Timeout if relay also fails to connect within 6 seconds
				get_tree().create_timer(6.0).timeout.connect(func():
					if _noray_active and _noray_target_oid == oid:
						if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
							push_warning("NetworkManager: Noray relay timed out.")
							leave_game()
							connection_failed.emit()
				)
	)


func _on_noray_client_connect_nat(address: String, port: int) -> void:
	if not _noray_active or _is_noray_host:
		return
	_connect_enet_from_noray(address, port)


func _on_noray_client_connect_relay(address: String, port: int) -> void:
	if not _noray_active or _is_noray_host:
		return
	_noray_connecting_nat = false
	_connect_enet_from_noray(address, port)


func _connect_enet_from_noray(address: String, port: int) -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, 0, 0, 0, Noray.local_port)
	if err != OK:
		push_error("NetworkManager: ENet client failed (%s:%d, local_port %d, err %d)" % [address, port, Noray.local_port, err])
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	print("NetworkManager: ENet client connecting to %s:%d from local port %d..." % [address, port, Noray.local_port])
	_send_client_handshake(peer, address, port)


func _send_client_handshake(peer: ENetMultiplayerPeer, address: String, port: int) -> void:
	# PacketHandshake.over_enet_peer aborts when status is CONNECTION_CONNECTING (client),
	# so we send the Noray UDP handshake directly via peer.host while connecting.
	var payload := "$rwx".to_ascii_buffer()
	var elapsed := 0.0
	while elapsed < 3.5:
		if multiplayer.multiplayer_peer != peer:
			return
		var status := peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			return
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return
		if peer.host:
			peer.host.socket_send(address, port, payload)
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1


func _ensure_host_player_authority() -> void:
	var host_player := _find_scene_host_player()
	if host_player:
		host_player.set_multiplayer_authority(1)
		if host_player.has_method("_refresh_multiplayer_authority"):
			host_player._refresh_multiplayer_authority()


func _find_scene_host_player() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var proto := scene.get_node_or_null("ProtoController") as Node3D
	if proto:
		return proto
	return get_tree().get_first_node_in_group("players") as Node3D


func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected: %d" % peer_id)
	if multiplayer.is_server():
		# Tell all existing peers (and host) to spawn this new peer
		_rpc_spawn_player.rpc(peer_id)
		# Tell the new peer to spawn all previously connected remote peers
		for existing_id in spawned_players.keys():
			if existing_id != peer_id:
				_rpc_spawn_player.rpc_id(peer_id, existing_id)
		# Sync any machines already built/relocated before this peer joined
		for mid in placed_machine_records.keys():
			var rec: Dictionary = placed_machine_records[mid]
			_rpc_place_machine.rpc_id(peer_id, mid, rec["scene_path"], rec["pos"], rec["rot_y"])
	player_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer disconnected: %d" % peer_id)
	_despawn_player(peer_id)
	player_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to host as peer %d" % multiplayer.get_unique_id())
	# Host's scene ProtoController has authority 1 (remote puppet on this client)
	var host_player := _find_scene_host_player()
	if host_player:
		host_player.set_multiplayer_authority(1)
		if host_player.has_method("_refresh_multiplayer_authority"):
			host_player._refresh_multiplayer_authority()
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	push_warning("NetworkManager: Connection failed.")
	leave_game()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	push_warning("NetworkManager: Host disconnected.")
	leave_game()
	server_disconnected.emit()
	if get_tree() and get_tree().current_scene:
		get_tree().reload_current_scene()


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_player(peer_id: int) -> void:
	if peer_id == 1:
		return
	if spawned_players.has(peer_id) and is_instance_valid(spawned_players[peer_id]):
		return

	var scene := get_tree().current_scene
	if scene == null:
		return

	if _player_scene == null:
		_player_scene = load(PLAYER_SCENE_PATH) as PackedScene
	if _player_scene == null:
		push_error("NetworkManager: Could not load player scene at %s" % PLAYER_SCENE_PATH)
		return

	var player := _player_scene.instantiate() as Node3D
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	var host_player := _find_scene_host_player()
	var spawn_pos := Vector3.ZERO
	if host_player:
		spawn_pos = host_player.global_position + Vector3(1.8 * (spawned_players.size() + 1), 0.2, 0.0)

	scene.add_child(player)
	if host_player:
		player.global_position = spawn_pos
	spawned_players[peer_id] = player
	print("NetworkManager: Spawned %s (local=%s)" % [player.name, str(player.is_multiplayer_authority())])


func _despawn_player(peer_id: int) -> void:
	if spawned_players.has(peer_id):
		var p = spawned_players[peer_id]
		if is_instance_valid(p):
			p.queue_free()
		spawned_players.erase(peer_id)


func broadcast_team_sc(delta_sc: float) -> void:
	if not is_multiplayer_active() or delta_sc == 0.0:
		return
	_rpc_add_team_sc.rpc(delta_sc)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_add_team_sc(delta_sc: float) -> void:
	var local_player := get_tree().get_first_node_in_group("player")
	if not local_player:
		return
	if "slop_credit" in local_player:
		local_player.slop_credit += delta_sc
	if "daily_sc_earned" in local_player:
		local_player.daily_sc_earned += delta_sc
	if local_player.has_signal("slop_credit_changed"):
		local_player.slop_credit_changed.emit(local_player.slop_credit, delta_sc)
	if local_player.has_method("_update_hud"):
		local_player._update_hud()


func broadcast_place_machine(mid: String, scene_path: String, pos: Vector3, rot_y: float) -> void:
	placed_machine_records[mid] = { "scene_path": scene_path, "pos": pos, "rot_y": rot_y }
	if not is_multiplayer_active():
		return
	_rpc_place_machine.rpc(mid, scene_path, pos, rot_y)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_place_machine(mid: String, scene_path: String, pos: Vector3, rot_y: float) -> void:
	placed_machine_records[mid] = { "scene_path": scene_path, "pos": pos, "rot_y": rot_y }
	var scene := get_tree().current_scene
	if scene == null:
		return

	var existing: Node3D = null
	for cand in get_tree().get_nodes_in_group(mid):
		if cand is Node3D and not cand.name.begins_with("BuildPreview_"):
			existing = cand
			break

	if existing and is_instance_valid(existing):
		existing.global_position = pos
		existing.global_rotation = Vector3(0, rot_y, 0)
		existing.visible = true
		if "process_mode" in existing:
			existing.process_mode = Node.PROCESS_MODE_INHERIT
	elif ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			inst.name = "Machine_%s" % mid
			scene.add_child(inst)
			inst.global_position = pos
			inst.global_rotation = Vector3(0, rot_y, 0)
			inst.add_to_group(mid)


func broadcast_unlock_machine(mid: String) -> void:
	if not is_multiplayer_active():
		return
	_rpc_unlock_machine.rpc(mid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_unlock_machine(mid: String) -> void:
	var local_player := get_tree().get_first_node_in_group("player")
	if not local_player or not ("owned_machines" in local_player):
		return
	if mid not in local_player.owned_machines:
		local_player.owned_machines.append(mid)


func broadcast_throw_trash(scene_path: String, pos: Vector3, rot: Vector3, impulse: Vector3) -> void:
	if not is_multiplayer_active() or scene_path.is_empty():
		return
	_rpc_throw_trash.rpc(scene_path, pos, rot, impulse)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_throw_trash(scene_path: String, pos: Vector3, rot: Vector3, impulse: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null or not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	scene.add_child(inst)
	inst.global_position = pos
	inst.global_rotation = rot
	if inst is RigidBody3D:
		inst.add_to_group("floatable")
		inst.add_to_group("trash")
		inst.apply_impulse(impulse)


func _on_steam_lobby_created(connect_res: int, this_lobby_id: int) -> void:
	if connect_res != 1: # 1 = Steam.RESULT_OK
		push_warning("NetworkManager: Steam lobby creation failed (%d), falling back to Noray." % connect_res)
		_start_noray_host(DEFAULT_PORT)
		return

	steam_lobby_id = this_lobby_id
	_steam.call("setLobbyJoinable", steam_lobby_id, true)
	_steam.call("setLobbyData", steam_lobby_id, "name", "SlopMountain Co-op")

	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		_start_noray_host(DEFAULT_PORT)
		return
	var err: int = peer.call("create_host", 0)
	if err != OK:
		push_warning("NetworkManager: SteamMultiplayerPeer create_host failed (%d), falling back to Noray." % err)
		_start_noray_host(DEFAULT_PORT)
		return

	multiplayer.multiplayer_peer = peer
	_ensure_host_player_authority()
	room_code = str(steam_lobby_id)
	print("NetworkManager: Hosting via Steam Relay! Lobby ID: %s" % room_code)
	noray_room_ready.emit(true, room_code, "Online via Steam Relay")


func _on_steam_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1: # 1 = CHAT_ROOM_ENTER_RESPONSE_SUCCESS
		push_warning("NetworkManager: Failed to join Steam lobby (%d)." % response)
		connection_failed.emit()
		return

	steam_lobby_id = this_lobby_id
	var host_steam_id: int = _steam.call("getLobbyOwner", steam_lobby_id)
	if host_steam_id == _steam.call("getSteamID"):
		return # Host already created server

	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		connection_failed.emit()
		return
	var err: int = peer.call("create_client", host_steam_id, 0)
	if err != OK:
		push_warning("NetworkManager: SteamMultiplayerPeer create_client failed (%d)." % err)
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = peer
	print("NetworkManager: Connecting via Steam Relay to host %d..." % host_steam_id)


func _on_steam_join_requested(this_lobby_id: int, _friend_id: int) -> void:
	if steam_available and _steam:
		leave_game()
		_steam.call("joinLobby", this_lobby_id)
