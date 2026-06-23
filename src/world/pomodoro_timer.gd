extends Node
class_name PomodoroTimer

## A tiny countdown clock for focus / break sessions.
## Counts down in real seconds and emits ticks so the UI can render MM:SS.

signal tick(remaining: float)
signal finished()
signal paused_changed(paused: bool)

var _remaining := 0.0
var _running := false
var _paused := false
var session_id := ""
var session_label := ""
var total_seconds := 0.0


func start(seconds: float, id: String, label: String) -> void:
	total_seconds = maxf(0.0, seconds)
	_remaining = total_seconds
	session_id = id
	session_label = label
	_running = true
	_paused = false
	tick.emit(_remaining)


func stop() -> void:
	_running = false
	_paused = false
	_remaining = 0.0


func set_paused(paused: bool) -> void:
	if not _running or _paused == paused:
		return
	_paused = paused
	paused_changed.emit(_paused)


func toggle_pause() -> void:
	set_paused(not _paused)


func is_running() -> bool:
	return _running


func is_paused() -> bool:
	return _paused


func remaining() -> float:
	return _remaining


func _process(delta: float) -> void:
	if not _running or _paused:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = 0.0
		_running = false
		tick.emit(0.0)
		finished.emit()
	else:
		tick.emit(_remaining)
