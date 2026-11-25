# event_system.gd
# Manages random daily events (Expedition, Make Peace, Open Season, Gold Rush, Evernight, Inspection Day).
# Ensures in an 8-day working week:
# - Exactly 1 random event occurs between Day 4 and Day 7.
# - Exactly 1 guaranteed climax/boss event occurs at the end of the week (Day 8).
# - Exactly 2 random events are experienced in a working week.

class_name EventSystem
extends Node

const SummitPeakScript = preload("res://summit_peak.gd")
const PeacefulCritterScript = preload("res://peaceful_critter.gd")
const EvilCritterScript = preload("res://evil_critter.gd")
const EvernightBossScript = preload("res://evernight_boss.gd")

signal event_started(event_data: Dictionary)
signal event_progress_updated(current: float, target: float, status_text: String)
signal event_completed(event_id: String)

enum GameMode { STANDARD = 0, CHALLENGE = 1 }
var current_game_mode: int = GameMode.STANDARD

# Reference to DayNightCycle
var dnc: Node = null

# Weekly schedule: { day_number (int): event_id (String) }
var scheduled_events: Dictionary = {}

# Active Event State
var active_event_id: String = ""
var is_event_active: bool = false
var is_event_completed: bool = false
var event_progress: float = 0.0
var event_target: float = 1.0

# Spawned active entities
var active_spawned_nodes: Array[Node] = []

# ---------------------------------------------------------------------------
# Event Catalog Definitions
# ---------------------------------------------------------------------------
const EVENT_CATALOG: Dictionary = {
	"expedition": {
		"id": "expedition",
		"tag": "EXPEDITION",
		"subtag": "SPECIAL EVENT · SUMMIT EXPEDITION\n! WAJIB / TIDAK BISA SKIP",
		"title": "EXPEDITION: SUMMIT FLAG",
		"desc": "Mendaki ke puncak tertinggi SlopMountain dan tancapkan Bendera Ranger di puncak!",
		"rule_warning": "▲ ATURAN EVENT: JALUR TERJAL & ANGIN KENCANG!\nBawa bendera ke puncak tiang di puncak bukit sebelum senja tiba.",
		"time_str": "02:30",
		"payout": 20,
		"reward": "★ 1× Summit Badge (+0.10 Mult)",
		"icon": "res://UI/03_cards/icon_contract_haul.png",
		"quota_target": 1.0,
		"target_unit": "FLAG",
		"is_boss": true,
		"dialogue": "Inspector: \"Hanya ranger tertangguh yang mampu menancapkan bendera di puncak tertinggi SlopMountain!\""
	},
	"make_peace": {
		"id": "make_peace",
		"tag": "MAKE PEACE",
		"subtag": "SPECIAL EVENT · WILDLIFE ENCOUNTER\n! WAJIB / TIDAK BISA SKIP",
		"title": "EVENT: MAKE PEACE",
		"desc": "Jinakkan satwa liar ramah di taman dengan memberi makan 3 sampah organik / buah / kompos.",
		"rule_warning": "▲ ATURAN EVENT: DEKATI PERLAHAN!\nBeri makan 3 camilan organik agar satwa liar jinak dan menjadi kawan setia.",
		"time_str": "02:30",
		"payout": 18,
		"reward": "★ 1× Critter Friend Charm (Bunga +$2 SC)",
		"icon": "res://UI/03_cards/icon_contract_organic.png",
		"quota_target": 3.0,
		"target_unit": "HEARTS",
		"is_boss": true,
		"dialogue": "Inspector: \"Satwa liar outpost butuh kawan! Beri makan dan jinakkan sebelum hari usai!\""
	},
	"open_season": {
		"id": "open_season",
		"tag": "OPEN SEASON",
		"subtag": "SPECIAL EVENT · PEST CONTROL\n! WAJIB / TIDAK BISA SKIP",
		"title": "EVENT: OPEN SEASON",
		"desc": "Buru & usir monster hama sampah liar yang mengacau di outpost dengan lemparan sampah!",
		"rule_warning": "▲ ATURAN EVENT: SERANG DENGAN SAMPAH KERAS!\nLempar kaleng, botol, atau balok daur ulang untuk mengalahkan hama liar.",
		"time_str": "02:30",
		"payout": 22,
		"reward": "★ 1× Hunter's Badge (+15% Throw Force)",
		"icon": "res://UI/03_cards/icon_contract_metal.png",
		"quota_target": 100.0,
		"target_unit": "HP",
		"is_boss": true,
		"dialogue": "Inspector: \"Hama liar menyerbu tumpukan sampah! Ambil sampah dan lempar sampai hama itu kabur!\""
	},
	"gold_rush": {
		"id": "gold_rush",
		"tag": "GOLD RUSH",
		"subtag": "SPECIAL EVENT · MARKET BOOM\n! WAJIB / TIDAK BISA SKIP",
		"title": "EVENT: GOLD RUSH",
		"desc": "Jual sampah & produk daur ulang senilai $25 SC ke Mossy / Garbage Seller hari ini!",
		"rule_warning": "▲ ATURAN EVENT: KOMPAKSIKAN UNTUK CUAN BESAR!\nManfaatkan Crusher & Burner untuk melipatgandakan nilai jual sampah.",
		"time_str": "02:30",
		"payout": 20,
		"reward": "★ 1× Gold Rush Trophy (+0.15 Multiplier)",
		"icon": "res://UI/03_cards/icon_contract_audit.png",
		"quota_target": 25.0,
		"target_unit": "SC",
		"is_boss": true,
		"dialogue": "Mossy: \"Hari ini harga scrap lagi meroket, Ranger! Kumpulkan $25 penjualan dan raih bonus gila-gilaan!\""
	},
	"evernight": {
		"id": "evernight",
		"tag": "EVERNIGHT",
		"subtag": "BOSS EVENT · THE FINAL HARVEST\n! WAJIB / TIDAK BISA SKIP",
		"title": "BOSS: THE EVERNIGHT COLOSSUS",
		"desc": "Malam abadi turun! Hadapi raksasa sampah purba yang bangkit dari SlopMountain.",
		"rule_warning": "▲ ATURAN BOSS: HANYA SAMPAH RECYCLE YANG MEMPAN!\nLempar Compacted Metal, Compacted Plastic, atau Kompos padat untuk melukai Boss!",
		"time_str": "02:30",
		"payout": 35,
		"reward": "★ 1× Ranger Champion Trophy (+0.25 Mult)",
		"icon": "res://UI/03_cards/icon_contract_audit.png",
		"quota_target": 300.0,
		"target_unit": "HP",
		"is_boss": true,
		"dialogue": "The Inspector: \"LANGIT GELAP! Raksasa sampah Evernight bangkit! Hancurkan dia dengan balok daur ulang sekarang juga!\""
	},
	"inspection_day": {
		"id": "inspection_day",
		"tag": "INSPECTION DAY",
		"subtag": "BOSS EVENT · DAY 4 AUDIT\n! WAJIB / TIDAK BISA SKIP",
		"title": "EVENT: SURPRISE AUDIT",
		"desc": "Semua jenis sampah (Haul) — Sidak Kebersihan",
		"rule_warning": "▲ ATURAN BOSS: SALAH TONG = -20 KG KUOTA!\nSetiap salah sortir mereset Streak & memotong progres kg.",
		"time_str": "02:30",
		"payout": 18,
		"reward": "★ 1× Summit Stamp (+0.05 Mult)",
		"icon": "res://UI/03_cards/icon_contract_audit.png",
		"quota_target": 480.0,
		"target_unit": "KG",
		"is_boss": true,
		"dialogue": "The Inspector: \"Hari ini event wajib! Penuhi kuota audit atau Taman Nasional resmi ditutup!\""
	}
}


func _ready() -> void:
	add_to_group("event_system")
	init_weekly_schedule()


## Sets the active game mode (0 = Standard, 1 = Challenge) and regenerates schedule
func set_game_mode(mode: int) -> void:
	current_game_mode = mode
	init_weekly_schedule()


## Generates the schedule: In Challenge mode, each day is a random event!
func init_weekly_schedule() -> void:
	scheduled_events.clear()

	if current_game_mode == GameMode.CHALLENGE:
		var challenge_pool := ["expedition", "make_peace", "open_season", "gold_rush", "inspection_day"]
		challenge_pool.shuffle()
		for day in range(1, 8):
			if day - 1 < challenge_pool.size():
				scheduled_events[day] = challenge_pool[day - 1]
			else:
				var prev: String = scheduled_events.get(day - 1, "")
				var candidates: Array = []
				for e in ["expedition", "make_peace", "open_season", "gold_rush", "inspection_day"]:
					if e != prev:
						candidates.append(e)
				scheduled_events[day] = candidates.pick_random()
		scheduled_events[8] = "evernight"
		print("EventSystem [CHALLENGE MODE]: Generated schedule with an event EVERY single day: %s" % str(scheduled_events))
	else:
		# Standard Mode: 2 events (1 mid-week Day 4-7, 1 Day 8 climax)
		var mid_week_day: int = randi_range(4, 7)
		var mid_pool := ["expedition", "make_peace", "open_season", "gold_rush", "inspection_day"]
		var mid_event: String = mid_pool.pick_random()
		scheduled_events[mid_week_day] = mid_event
		scheduled_events[8] = "evernight"
		print("EventSystem [STANDARD MODE]: Weekly schedule generated! Mid-week Day %d [%s], End-of-week Day 8 [evernight]" % [mid_week_day, mid_event])


func is_event_day(day_num: int) -> bool:
	if current_game_mode == GameMode.CHALLENGE:
		return true
	return scheduled_events.has(day_num)


func get_event_for_day(day_num: int) -> String:
	if scheduled_events.has(day_num):
		return scheduled_events[day_num]
	if current_game_mode == GameMode.CHALLENGE:
		var pool := ["expedition", "make_peace", "open_season", "gold_rush", "inspection_day", "evernight"]
		var picked: String = pool.pick_random()
		scheduled_events[day_num] = picked
		return picked
	return ""


func get_event_data_for_day(day_num: int) -> Dictionary:
	var eid: String = get_event_for_day(day_num)
	if eid != "" and EVENT_CATALOG.has(eid):
		var data: Dictionary = EVENT_CATALOG[eid].duplicate()
		if current_game_mode == GameMode.CHALLENGE:
			data["subtag"] = "CHALLENGE EVENT · DAY %d\n! WAJIB / TIDAK BISA SKIP" % day_num
		return data
	return {}


## Activates the event gameplay when the shift starts
func start_event(event_id: String) -> void:
	if NetworkManager.is_multiplayer_active() and NetworkManager.is_host():
		_rpc_start_event.rpc(event_id)
	_do_start_event(event_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_start_event(event_id: String) -> void:
	_do_start_event(event_id)


func _do_start_event(event_id: String) -> void:
	cleanup_event_entities()

	if not EVENT_CATALOG.has(event_id):
		return

	active_event_id = event_id
	is_event_active = true
	is_event_completed = false
	event_progress = 0.0

	var edata: Dictionary = EVENT_CATALOG[event_id]
	event_target = edata.get("quota_target", 1.0)

	var world = get_tree().current_scene

	match event_id:
		"expedition":
			_spawn_expedition_landmark(world)
		"make_peace":
			_spawn_peaceful_critter(world)
		"open_season":
			_spawn_evil_critter(world)
		"gold_rush":
			_setup_gold_rush_listener()
		"evernight":
			_spawn_evernight_boss(world)
		"inspection_day":
			pass

	event_started.emit(edata)
	print("EventSystem: Event [%s] started successfully!" % event_id)


# ---------------------------------------------------------------------------
# Event Spawners & Mechanics
# ---------------------------------------------------------------------------

func _spawn_expedition_landmark(world: Node) -> void:
	var peak = SummitPeakScript.new()
	peak.name = "SummitPeakLandmark"
	peak.position = Vector3(0, 0, -28.0)
	world.add_child(peak)
	active_spawned_nodes.append(peak)

	peak.flag_planted.connect(func():
		complete_event("expedition")
	)


var _make_peace_tamed_count: int = 0
var _open_season_defeated_count: int = 0


func _get_hidden_forest_spawn(world: Node, min_dist: float, max_dist: float, seed_offset: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("event_%s_%d" % [active_event_id, seed_offset])
	var angle := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(min_dist, max_dist)
	var x := cos(angle) * dist
	var z := sin(angle) * dist
	var y := 0.5
	if world is Node3D:
		var space := (world as Node3D).get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -50.0, z))
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				y = hit.position.y + 0.5
	return Vector3(x, y, z)


func _spawn_footstep_trail(world: Node, target_pos: Vector3, trail_color: Color) -> void:
	var start_pos := target_pos.normalized() * 10.0
	start_pos.y = target_pos.y
	var total_dist := start_pos.distance_to(target_pos)
	var steps := maxi(4, int(total_dist / 4.5))
	var dir := (target_pos - start_pos).normalized()

	for s in range(steps):
		var t := float(s) / float(steps)
		var p := start_pos.lerp(target_pos, t)
		var side := -1.0 if (s % 2 == 0) else 1.0
		var perp := Vector3(-dir.z, 0.0, dir.x) * (0.35 * side)
		p += perp

		if world is Node3D:
			var space := (world as Node3D).get_world_3d().direct_space_state
			if space:
				var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.z), Vector3(p.x, -40.0, p.z))
				q.collision_mask = 1
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					p.y = hit.position.y + 0.04

		var step_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.32, 0.04, 0.52)
		step_mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = trail_color
		mat.emission_enabled = true
		mat.emission = trail_color
		mat.emission_energy_multiplier = 0.85
		step_mesh.material_override = mat
		world.add_child(step_mesh)
		step_mesh.global_position = p
		step_mesh.look_at(p + dir, Vector3.UP)
		active_spawned_nodes.append(step_mesh)


func _spawn_peaceful_critter(world: Node) -> void:
	_make_peace_tamed_count = 0
	var needed := 2
	for i in range(needed):
		var critter = PeacefulCritterScript.new()
		critter.name = "PeacefulCritterMob_%d" % i
		var spawn_pos := _get_hidden_forest_spawn(world, 38.0, 58.0, i + 10)
		world.add_child(critter)
		critter.global_position = spawn_pos
		active_spawned_nodes.append(critter)
		_spawn_footstep_trail(world, spawn_pos, Color(0.35, 0.9, 0.45))

		critter.critter_tamed.connect(func():
			_make_peace_tamed_count += 1
			event_progress = float(_make_peace_tamed_count)
			event_target = float(needed)
			event_progress_updated.emit(float(_make_peace_tamed_count), float(needed), "🐾 Tamed: %d / %d" % [_make_peace_tamed_count, needed])
			if _make_peace_tamed_count >= needed:
				complete_event("make_peace")
		)

		critter.critter_fed.connect(func(cur: int, max_v: int):
			event_progress_updated.emit(float(_make_peace_tamed_count), float(needed), "🐾 Tamed: %d / %d (Feeding %d/%d)" % [_make_peace_tamed_count, needed, cur, max_v])
		)


func _spawn_evil_critter(world: Node) -> void:
	_open_season_defeated_count = 0
	var needed := 2
	for i in range(needed):
		var critter = EvilCritterScript.new()
		critter.name = "EvilCritterMob_%d" % i
		var spawn_pos := _get_hidden_forest_spawn(world, 38.0, 58.0, i + 30)
		world.add_child(critter)
		critter.global_position = spawn_pos
		active_spawned_nodes.append(critter)
		_spawn_footstep_trail(world, spawn_pos, Color(0.95, 0.25, 0.2))

		critter.critter_defeated.connect(func():
			_open_season_defeated_count += 1
			event_progress = float(_open_season_defeated_count)
			event_target = float(needed)
			event_progress_updated.emit(float(_open_season_defeated_count), float(needed), "👹 Pests Defeated: %d / %d" % [_open_season_defeated_count, needed])
			if _open_season_defeated_count >= needed:
				complete_event("open_season")
		)

		critter.critter_health_changed.connect(func(cur: float, max_v: float):
			event_progress_updated.emit(float(_open_season_defeated_count), float(needed), "👹 Pests: %d/%d (HP %d/%d)" % [_open_season_defeated_count, needed, int(cur), int(max_v)])
		)


func _setup_gold_rush_listener() -> void:
	# Listen to all GarbageSellers in scene
	var sellers = get_tree().get_nodes_in_group("garbage_seller")
	for s in sellers:
		if s.has_signal("garbage_sold") and not s.garbage_sold.is_connected(_on_seller_garbage_sold):
			s.garbage_sold.connect(_on_seller_garbage_sold)


func _on_seller_garbage_sold(_items: int, total_sc: float) -> void:
	if not is_event_active or active_event_id != "gold_rush" or is_event_completed:
		return

	event_progress += total_sc
	event_progress_updated.emit(event_progress, event_target, "Sold $%.1f / $%.1f SC" % [event_progress, event_target])

	if event_progress >= event_target:
		complete_event("gold_rush")


func _spawn_evernight_boss(world: Node) -> void:
	var boss = EvernightBossScript.new()
	boss.name = "EvernightBossTitan"
	var spawn_pos := _get_hidden_forest_spawn(world, 46.0, 66.0, 99)
	world.add_child(boss)
	boss.global_position = spawn_pos
	active_spawned_nodes.append(boss)
	_spawn_footstep_trail(world, spawn_pos, Color(0.85, 0.08, 0.12))

	boss.boss_defeated.connect(func():
		complete_event("evernight")
	)

	boss.boss_health_changed.connect(func(cur: float, max_v: float):
		event_progress = max_v - cur
		event_target = max_v
		event_progress_updated.emit(cur, max_v, "Boss HP: %d / %d" % [int(cur), int(max_v)])
	)


func complete_event(event_id: String) -> void:
	if is_event_completed:
		return
	is_event_completed = true

	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("_show_feedback"):
		player._show_feedback("🎉 EVENT COMPLETED: %s!" % event_id.to_upper().replace("_", " "))

	event_completed.emit(event_id)


func cleanup_event_entities() -> void:
	for node in active_spawned_nodes:
		if is_instance_valid(node):
			node.queue_free()
	active_spawned_nodes.clear()
	is_event_active = false
	active_event_id = ""
