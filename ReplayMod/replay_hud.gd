extends Control

@export var theater: NodePath
@onready var _theater: Node = get_node(theater)

# Top bar
@onready var level_label: Label = %ReplayLevelLabel
@onready var time_label: Label = %ReplayTimeLabel
@onready var camera_button: Button = %ReplayCameraButton
@onready var replay_picker: Button = %ReplayPickerButton
@onready var exit_replay: Button = %ReplayExitButton

# Timeline
@onready var scrub_bar: HSlider = %ReplayScrubBar
@onready var event_track: EventTrack = %ReplayEventTrack
@onready var current_time_label: Label = %ReplayCurrentTime
@onready var total_time_label: Label = %ReplayTotalTime

# Playback Controls
@onready var play_pause_button: Button = %ReplayPlayPause
@onready var prev_event_button: Button = %ReplayPrevEvent
@onready var next_event_button: Button = %ReplayNextEvent

# Speed Controls
@onready var speed_label: Label = %ReplaySpeedLabel
@onready var speed_down: Button = %ReplaySpeedDown
@onready var speed_up: Button = %ReplaySpeedUp

# Speed Presets
@onready var speed_presets: HBoxContainer = %ReplaySpeedPresets

# Event Toaster
@onready var event_toast: Label = %ReplayEventToast

# Key Hints
@onready var key_hints: VBoxContainer = %ReplayKeyHints
@onready var freecam_key_hints: VBoxContainer = %ReplayCamHints



var _dragging := false
var _replay_length := 1.0
var _events: Array = []
var _last_toast_time := -1.0
var _toast_tween: Tween
var _toast_base_position: Vector2

const SPEED_PRESETS := [0.25, 0.5, 1.0, 1.5, 2.0]
var preset_speed_buttons: Array[Button] = []



func _ready() -> void:
	anchor_right = 1.0

	# Set toasties to just above Bottom Controls
	_toast_base_position = event_toast.position

	# Connect theater sig
	_theater.loaded.connect(_on_loaded)
	_theater.events_ready.connect(_on_events_ready)
	_theater.level_loaded.connect(func(name): level_label.text = name)

	# Scrub Bar
	scrub_bar.min_value = 0.0
	scrub_bar.max_value = 1.0
	scrub_bar.step = 0.001
	scrub_bar.drag_started.connect(func(): _dragging = true)
	scrub_bar.drag_ended.connect(func(_v):
		_dragging = false
		_theater.seek(scrub_bar.value * _replay_length)
	)

	# Playback Buttons
	play_pause_button.pressed.connect(_toggle_play)
	prev_event_button.pressed.connect(_theater.jump_to_prev_event)
	next_event_button.pressed.connect(_theater.jump_to_next_event)
	# IShowSpeed Buttons
	speed_down.pressed.connect(func(): _nudge_speed(-1))
	speed_up.pressed.connect(func(): _nudge_speed(1))

	# Camera Toggle
	camera_button.pressed.connect(_toggle_camera)

	# Replay Picker
	replay_picker.pressed.connect(_choose_replay)
	
	# Exit Replay
	exit_replay.pressed.connect(_theater.exit_replay_viewer)

	# Key Hints
	key_hints.visible = true
	freecam_key_hints.visible = false

	# Preset Speed Buttons
	for speed in SPEED_PRESETS:
		var button := Button.new()

		button.text = "%.2fx" % speed
		button.pressed.connect(_set_speed.bind(speed))

		speed_presets.add_child(button)
		preset_speed_buttons.append(button)

	# Init UI state
	_update_play_button()
	_update_speed_label()
	_update_camera_button()

	# Fade
	modulate = Color.TRANSPARENT
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.4)

func _process(_delta: float) -> void:
	if _replay_length <= 0.0 or _theater == null:
		return

	var current: float = _theater.current_time()
	var frac := clampf(current / _replay_length, 0.0, 1.0)

	# Update Scrub Bar (only when not dragging)
	if not _dragging:
		scrub_bar.set_block_signals(true)
		scrub_bar.value = frac
		scrub_bar.set_block_signals(false)

	# Update eveent track (draws the fill & ticks)
	event_track.update_state(current, _replay_length, _events)

	# Update Time Labels
	current_time_label.text = _format_time(current)
	total_time_label.text = _format_time(_replay_length)
	time_label.text = "%s / %s" % [_format_time(current), _format_time(_replay_length)]

	# Update play button state if changed externally
	var is_playing: bool = _theater.is_playing()
	if (play_pause_button.text == "Play" and is_playing) or (play_pause_button.text == "Pause" and not is_playing):
		_update_play_button()

	# Event Toasts -> Shown when crossing event threshold
	_check_event_toasts(current)

func _input(event: InputEvent) -> void:
	if _theater == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if !_theater.free_cam_active:
					_toggle_play()
			KEY_LEFT:
				if event.shift_pressed:
					_theater.jump_to_prev_event()
				else:
					_theater.seek(max(0.0, _theater.current_time() - 5.0))
			KEY_RIGHT:
				if event.shift_pressed:
					_theater.jump_to_next_event()
				else:
					_theater.seek(min(_replay_length, _theater.current_time() + 5.0))
			KEY_F:
				_toggle_camera()
			KEY_H:
				visible = !visible
			KEY_COMMA:
				_nudge_speed(-1)
			KEY_PERIOD:
				_nudge_speed(1)
			KEY_P:
				_choose_replay()

func _on_loaded(length: float) -> void:
	_replay_length = max(length, 0.001)
	scrub_bar.value = 0.0
	event_track.update_state(0.0, _replay_length, _events)

func _on_events_ready(events: Array) -> void:
	_events = events
	event_track.update_state(_theater.current_time(), _replay_length, _events)

func _check_event_toasts(current_time: float) -> void:
	for e in _events:
		var dt: float = current_time - e.time
		if dt >= 0.0 and dt < 0.15 and not is_equal_approx(e.time, _last_toast_time):
			_show_toast(e.method)
			_last_toast_time = e.time
			break

func _show_toast(text: String) -> void:
	event_toast.text = text
	event_toast.modulate = Color.WHITE

	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()

	event_toast.position = _toast_base_position

	_toast_tween = create_tween().set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(event_toast, "modulate", Color(1, 1, 1, 0), 1.5)
	_toast_tween.parallel().tween_property(event_toast, "position:y", event_toast.position.y - 30, 1.5)

func _toggle_play() -> void:
	_theater.toggle_play()
	_update_play_button()

func _update_play_button() -> void:
	var playing: bool = _theater.is_playing()
	play_pause_button.text = "Pause" if playing else "Play"

func _nudge_speed(direction: int) -> void:
	_theater.nudge_rate(direction)
	_update_speed_label()

func _set_speed(v: float) -> void:
	_theater.set_rate(v)
	_update_speed_label()

func _update_speed_label() -> void:
	var rate: float = _theater.get_speed()
	speed_label.text = "%.2fx" % rate
	for i in SPEED_PRESETS.size():
		preset_speed_buttons[i].modulate = Color.WHITE if is_equal_approx(rate, SPEED_PRESETS[i]) else Color(1, 1, 1, 0.35)

func _choose_replay() -> void:
	_theater._show_replay_picker()

func _toggle_camera() -> void:
	key_hints.visible = !key_hints.visible
	freecam_key_hints.visible = !freecam_key_hints.visible
	_theater.toggle_freecam()
	_update_camera_button()

func _update_camera_button() -> void:
	var free: bool = _theater.free_cam_active
	camera_button.text = "Free CAM" if free else "POV CAM"
	camera_button.modulate = Color(0.5, 1.0, 0.5) if free else Color.WHITE

func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	var ms := int((seconds - floor(seconds)) * 100)

	return "%02d:%02d:%02d" % [mins, secs, ms]
