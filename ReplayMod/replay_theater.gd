# Standalone replay viwer.
# NOTE: This never references or connects to Fired/JUMPED/scoring signals.
# 	It only 'reads' Animation data and drives it's own rig, so it can never
# 	be mistaken for a live run or trip leaderboard/save hooks.
extends Node3D

@export var speed_min := 0.05
@export var speed_max := 2.00
@export var speed_step := 0.25
@export var pitch_track_idx := 5 # SpineLook:XRot (confirm against loaded anim if changes)

@export var freecam_speed := 5.0

@onready var anim_player: AnimationPlayer = $GhostRig/ReplayGhostPlayer
@onready var replay_rig: Node3D = $GhostRig/BunnyGal
@onready var pov_camera: Camera3D = $GhostRig/BunnyGal/ReplayPovCamera
@onready var free_camera: Camera3D = $ReplayFreeCamera
@onready var path_line: MeshInstance3D = $ReplayPathLine


const LEVELS_DIR := "res://Scenes/Levels/"
const MAIN_MENU := "res://Scenes/UI/menu.tscn"

var _loaded_anim: Animation = null
var current_events: Array = [] # [{ time: float, method: String }]
var free_cam_active := false
var _freecam_mouse_motion := Vector2.ZERO

signal loaded(length: float)
signal events_ready(events: Array)
signal level_loaded(display_name: String)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Exempts the ReplayTheater when pausing as world state is paused.
	Audio.voplayer.stop()

	# Was encountering errors.
	if anim_player == null:
		anim_player = get_node_or_null("ReplayGhostPlayer")
	if anim_player == null:
		anim_player = get_node_or_null("%ReplayGhostPlayer")
	if anim_player == null:
		push_error("ReplayTheater: Cannot find AnimationPlayer. Tried: GhostRig/ReplayGhostPlayer, ReplayGhostPlayer, %ReplayGhostPlayer :(")
		push_error("Actual children: ", get_children())
		if has_node("GhostRig"):
			push_error("GhostRig children: ", get_node("GhostRig").get_children())
		return

	pov_camera.current = true
	free_camera.current = false

	_show_replay_picker()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if _loaded_anim == null:
		return
	if pitch_track_idx < 0 or pitch_track_idx >= _loaded_anim.get_track_count():
		return

	var pitch = _loaded_anim.value_track_interpolate(pitch_track_idx, anim_player.current_animation_position)
	pov_camera.rotation.x = -pitch
	pov_camera.rotation.y = PI
	pov_camera.fov = Config.FOV

########################################
# START OF REPLAY PICKER FUNCTIONS
########################################
func _reset_for_new_replay() -> void:
	anim_player.stop()
	_loaded_anim = null
	current_events.clear()
	path_line.mesh = null
	free_cam_active = false
	get_tree().paused = false

	for child in get_tree().get_nodes_in_group("replay_dynamic"):
		child.queue_free()

func load_replay(res_path: String) -> void:
	var anim := ReplayFile.load_animation(res_path)
	if anim == null:
		return

	_smoooth_interpolation(anim)

	var lib := anim_player.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)
	if lib.has_animation("LevelBackdrop"):
		lib.remove_animation("LevelBackdrop")
	lib.add_animation("LevelBackdrop", anim)

	anim_player.play("LevelBackdrop")
	anim_player.pause()        # Starts paused (UI drives playback going forward)

	_loaded_anim = anim
	_extract_events(anim)
	_build_path_line(anim)

	if anim.get_track_count() > 0 and anim.track_get_type(0) == Animation.TYPE_POSITION_3D:
		var start_pos: Vector3 = anim.track_get_key_value(0, 0)
		var last_key := anim.track_get_key_count(0) - 1
		print(" first keyframe pos: ", start_pos)
		print(" last keyframe pos: ", anim.track_get_key_value(0, last_key))

		free_camera.global_position = start_pos + Vector3(0, 3, 8)
		free_camera.look_at(start_pos, Vector3.UP)

	loaded.emit(anim.length)
	events_ready.emit(current_events)

func _show_replay_picker() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = ["*.res ; Ghost Replay Files"]
	dialog.size = Vector2i(700, 450)
	dialog.add_to_group("replay_dialogs")

	var ghosts_dir := _get_ghosts_dir()
	if ghosts_dir != "" and DirAccess.dir_exists_absolute(ghosts_dir):
		dialog.current_dir = ghosts_dir
		dialog.current_path = ghosts_dir
	else:
		push_warning("Couldn't find Ghosts folder automatically; Defaulting to file dialog.")

	add_child(dialog)
	dialog.file_selected.connect(_on_replay_picked)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _get_ghosts_dir() -> String:
	if "savelocation" in global and global.savelocation != "":
		var globalized := ProjectSettings.globalize_path(global.savelocation + "Ghosts/")
		return globalized
	return _find_ghosts_dir_by_regex()

func _find_ghosts_dir_by_regex() -> String:
	var base := OS.get_user_data_dir() # .../AppData/Roamin/CICADAMATA
	var dir := DirAccess.open(base)
	if dir == null:
		return ""

	var steam_id_pattern := RegEx.new()
	steam_id_pattern.compile("^\\d{17}$") # Steam64 IDs always 17 digits

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and steam_id_pattern.search(name):
			dir.list_dir_end()
			return base + "/" + name + "/Ghosts/"
		name = dir.get_next()
	dir.list_dir_end()

	return ""

# I haven't gone beyond 2_1 so I'm unsure whether bonus level & ghost filenames differ
func _on_replay_picked(res_path: String) -> void:
	for d in get_tree().get_nodes_in_group("replay_dialogs"):
		d.queue_free()

	if _loaded_anim != null:
		_reset_for_new_replay()

	var level_id := res_path.get_file().get_basename() # lvl_1_3.res -> lvl_1_3
	var level_path := _find_level_path(level_id)

	#if not ResourceLoader.exists(level_path):
	if level_path == "":
		push_warning("No matching level for '%s' (looked for %s); loading replay without level :/")
	else:
		_load_level(level_path)

	if ResourceLoader.exists(res_path):
		load_replay(res_path)
	else:
		print("Path not found: ", res_path)

func _find_level_path(level_id: String) -> String:
	var direct := LEVELS_DIR + level_id + ".tscn"
	if ResourceLoader.exists(direct):
		return direct
	return _search_dir_for_level(LEVELS_DIR, level_id)

func _search_dir_for_level(dir_path: String, level_id: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""

	# abandon_all_hope subdir levels (can you play these? idk)
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			var found := _search_dir_for_level(full, level_id)
			if found != "":
				dir.list_dir_end()
				return found
		elif name == level_id + ".tscn":
			dir.list_dir_end()
			return full
		name = dir.get_next()

	dir.list_dir_end()
	return ""
########################################
# END OF REPLAY PICKER FUNCTIONS
########################################


########################################
# START OF REPLAY HELPER FUNCTIONS
########################################
func _load_level(level_path: String) -> void:
	if not ResourceLoader.exists(level_path):
		print("Level not found: ", level_path)
		return

	var level_scene := load(level_path) as PackedScene
	var level: Node = level_scene.instantiate()
	level.name = "LevelBackdrop"
	level.add_to_group("replay_dynamic")
	add_child(level)

	await get_tree().process_frame # Let player_spawn.gd finish spawn first

	var live_player: Node = level.get_node_or_null("Player")

	# Get rid of live player
	if live_player:
		# When reloading a replay we reassign global._player.
		# Speaking audio is finished, error is thrown in
		#		ship.gd#143 `global._player.ship_done = true` because
		#		the player is freed when reloading a replay.
		global._player = live_player
		live_player.set_physics_process(false)
		live_player.set_process(false)
		live_player.set_process_input(false)
		if live_player.has_method("hide"):
			live_player.hide()
		if live_player is Node3D:
			live_player.global_position = Vector3(0, -10000, 0)

	# We are the ghost; avoids duplicating nodes
	if get_node_or_null("Ghost"):
		get_node("Ghost").queue_free()

	global.showmouse = true
	print("Level loaded: ", level_path)

	var level_id := level_path.get_file().get_basename()
	level_loaded.emit(_display_name_for_level(level_id))

func _display_name_for_level(level_id: String) -> String:
	var world_level_re := RegEx.new()
	world_level_re.compile("^lvl_(\\d+)_(\\d+)$")
	var m := world_level_re.search(level_id)
	if m:
		return "WORLD %s - LEVEL %s" % [m.get_string(1), m.get_string(2)]

	if level_id.begins_with("proto_"):
		var proto_re := RegEx.new()
		proto_re.compile("^proto_(\\d+)_(\\d+)$")
		var pm := proto_re.search(level_id)
		if pm:
			return "PROTOTYPE %s-%s" % [pm.get_string(1), pm.get_string(2)]
		return "PROTOTYPE: " + level_id.trim_prefix("proto_").capitalize()

	if level_id.begins_with("bonus_"):
		return "Bonus: " + level_id.trim_prefix("bonus_").capitalize()

	if level_id.begins_with("lvl_"):
		# Catch: chickendimension, debug, rain, end, etc.
		return level_id.trim_prefix("lvl_").capitalize()

	return level_id.capitalize()

func _smoooth_interpolation(anim: Animation) -> void:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_METHOD:
			#anim.track_set_interpolation_type(i, Animation.INTERPOLATION_LINEAR) # For '1:1' replay
			anim.track_set_interpolation_type(i, Animation.INTERPOLATION_CUBIC)   # For a 'smoother' replay

func _extract_events(anim: Animation) -> void:
	current_events.clear()
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_METHOD:
			for k in anim.track_get_key_count(i):
				var t: float = anim.track_get_key_time(i, k)
				var payload: Dictionary = anim.track_get_key_value(i, k)
				current_events.append({"time": t, "method": payload.get("method", "?")})

	current_events.sort_custom(func(a,b): return a.time < b.time)

func _silence_subtitles() -> void:
	if UI and UI.has_node("Subtitles/AnimationPlayer"):
		var subtitle_player: AnimationPlayer = UI.get_node("Subtitles/AnimationPlayer")
		subtitle_player.stop()
		if UI.has_node("Subtitles"):
			UI.get_node("Subtitles").hide()

# Ghost Line Pathing
func _build_path_line(anim: Animation) -> void:
	var pos_track := -1
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			pos_track = i
			break
	if pos_track == -1:
		return

	var points: PackedVector3Array = []
	for k in anim.track_get_key_count(pos_track):
		points.append(anim.track_get_key_value(pos_track, k))

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	path_line.mesh = mesh

func exit_replay_viewer() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	global._player = null
	get_tree().change_scene_to_file(MAIN_MENU)
########################################
# END OF REPLAY HELPER FUNCTIONS
########################################


########################################
# Player Controls
########################################
func seek(t: float) -> void:
	anim_player.seek(t, true)
func set_rate(r: float) -> void:
	anim_player.speed_scale = clamp(r, speed_min, speed_max)
func nudge_rate(direction: int) -> void:
	set_rate(anim_player.speed_scale + direction * speed_step)
func toggle_play() -> void:
	_silence_subtitles()
	#if free_cam_active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		#return
	if anim_player.is_playing():
		anim_player.pause()
		get_tree().paused = true
	else:
		anim_player.play()
		get_tree().paused = false
func current_time() -> float:
	if anim_player == null:
		return 0.0
	return anim_player.current_animation_position
func length() -> float:
	return anim_player.current_animation_length
func jump_to_next_event() -> void:
	var t := current_time()
	for e in current_events:
		if e.time > t + 0.001:
			seek(e.time)
			return
	seek(length())
func jump_to_prev_event() -> void:
	var t := current_time()
	for i in range(current_events.size() - 1, -1, -1):
		if current_events[i].time < t - 0.001:
			seek(current_events[i].time)
			return
	seek(0.0)


########################################
# Free Cam
#	Logic taken from elysiaisalive's freecam mod
#	Github: elysiaisalive/cicadamata-mataviewer
########################################
func toggle_freecam() -> void:
	free_cam_active = !free_cam_active
	free_camera.current = free_cam_active
	pov_camera.current = !free_cam_active

	global.showmouse = false if free_cam_active else true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if free_cam_active else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if not free_cam_active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		global.showmouse = true if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else false

		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_freecam_mouse_motion = event.relative
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			freecam_speed = max(1.0, freecam_speed + 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			freecam_speed = max(1.0, freecam_speed - 1.0)

	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not free_cam_active:
		return

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = -_freecam_mouse_motion * Config.SENSITIVITY
		_freecam_mouse_motion = Vector2.ZERO
		free_camera.rotation.x += motion.y
		free_camera.rotation.y += motion.x
		free_camera.rotation.x = clampf(free_camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	var input_dir := Input.get_vector("left", "right", "forward", "back").normalized()
	var move_dir := free_camera.global_basis * Vector3(input_dir.x, 0, input_dir.y)
	var y_input := Input.get_axis("stomp", "jump")
	move_dir += free_camera.global_basis * Vector3(0, y_input, 0)

	free_camera.global_position += move_dir * freecam_speed * delta


########################################
# Animation Player
########################################
func is_playing() -> bool:
	if anim_player == null:
		return false
	return anim_player.is_playing()
func get_speed() -> float:
	if anim_player == null:
		return 1.0
	return anim_player.speed_scale
