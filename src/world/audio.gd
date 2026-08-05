extends Node

## Global, autoloaded audio manager. Plays one-shot UI/feedback SFX through a
## small pool of players and manages a single looping ambience track. Volume and
## mute are owned here and persisted by world.gd.

const SFX := {
	"click": preload("res://assets/audio/sfx/click.ogg"),
	"start": preload("res://assets/audio/sfx/start.ogg"),
	"complete": preload("res://assets/audio/sfx/complete.ogg"),
	"open": preload("res://assets/audio/sfx/open.ogg"),
	"close": preload("res://assets/audio/sfx/close.ogg"),
	"grab": preload("res://assets/audio/sfx/grab.ogg"),
	"drop": preload("res://assets/audio/sfx/drop.ogg"),
	"back": preload("res://assets/audio/sfx/back.ogg"),
	"unlock": preload("res://assets/audio/sfx/unlock.mp3"),
}
const AMBIENCE := {
	"focus": preload("res://assets/audio/ambience/focus.wav"),
}

var muted := false
var volume := 0.8        # master SFX level, 0..1
var ambience_volume := 0.45

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambient: AudioStreamPlayer


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	add_child(_ambient)
	# Loop any WAV ambience tracks.
	for key in AMBIENCE:
		var s = AMBIENCE[key]
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD


func play(name: String, pitch := 1.0) -> void:
	if muted or not SFX.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = SFX[name]
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(clampf(volume, 0.0001, 1.0))
	p.play()


func play_ambient(name: String) -> void:
	if muted or not AMBIENCE.has(name):
		return
	var stream: AudioStream = AMBIENCE[name]
	if _ambient.playing and _ambient.stream == stream:
		return
	_ambient.stream = stream
	_ambient.volume_db = linear_to_db(clampf(ambience_volume, 0.0001, 1.0))
	_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		_ambient.stop()


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)


func set_ambience_volume(value: float) -> void:
	ambience_volume = clampf(value, 0.0, 1.0)
	if _ambient.playing:
		_ambient.volume_db = linear_to_db(clampf(ambience_volume, 0.0001, 1.0))
