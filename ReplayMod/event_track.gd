@tool
class_name EventTrack
extends Control

var events: Array = []
var replay_length: float = 1.0
var current_time: float = 0.0

func _draw() -> void:
	if replay_length <= 0.0 or size.x <= 1.0:
		return

	var w := size.x
	var h := size.y
	var cy := h * 0.5

	draw_rect(Rect2(0, cy - 4, w, 8), Color(0.04, 0.04, 0.08, 1.0))

	var frac := clampf(current_time / replay_length, 0.0, 1.0)
	if frac > 0.0:
		draw_rect(Rect2(0, cy - 4, w * frac, 8), Color(0.0, 0.85, 1.0, 0.35))
		draw_rect(Rect2(w * frac - 1, cy - 4, 2, 8), Color(0.0, 1.0, 1.0, 0.9))

	for e in events:
		var ef := clampf(e.time / replay_length, 0.0, 1.0)
		var ex := ef * w
		var passed: float = e.time <= current_time
		var col := _event_color(e.method)

		if not passed:
			col = Color(col.r, col.g, col.b, 0.25)

		draw_line(Vector2(ex, cy - 10), Vector2(ex, cy + 10), col, 2.0)
		draw_circle(Vector2(ex, cy), 2.5, col)

		var dt := absf(e.time - current_time)
		if dt < 0.1:
			draw_circle(Vector2(ex, cy), 5.0, Color(col.r, col.g, col.b, 0.4))

func _event_color(method: String) -> Color:
	match method.to_lower():
		"jump":
			return Color(0.0, 0.95, 1.0)
		"fire":
			return Color(1.0, 0.25, 0.35)
		_:
			return Color(1.0, 0.85, 0.2)

func update_state(t: float, length: float, evs: Array) -> void:
	current_time = t
	replay_length = length
	events = evs
	queue_redraw()
