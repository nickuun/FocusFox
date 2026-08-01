extends Node2D
class_name Den

## The fox's home IS the den. Earned items appear in the launcher room as
## draggable, throwable doodads (reusing ThrowableProp). Items unlock by focus
## time; the player can fling them around and their resting spot is remembered.

const THROWABLE := preload("res://src/world/throwable_prop.gd")
const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")
const PATH := "user://focus_fox_den.cfg"
const FLOOR_Y := 384.0

# Catalog of den finds. unlock_min = focus minutes needed before it shows up.
const ITEMS := [
	{"id": "mug", "name": "a mug", "texture": "res://assets/main_menu/environment/mug.png", "unlock_min": 30, "default_x": 792.0},
]

var _items := {}         # id -> Sprite2D (ThrowableProp)
var _positions := {}     # id -> Vector2 (saved resting spot)
var _interacting := {}   # id -> bool (true between grab and settle)
var _banner: Label


func _ready() -> void:
	_load_positions()
	_banner = Label.new()
	_banner.add_theme_font_override("font", FONT)
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_color", Color(0.30, 0.19, 0.11))
	_banner.position = Vector2(160, 150)
	_banner.size = Vector2(640, 40)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.z_index = 70
	_banner.modulate.a = 0.0
	add_child(_banner)


## Shows any items unlocked by the current focus time. allow_reveal animates +
## celebrates items that pop in during play (vs. ones already earned at startup).
func refresh(focus_seconds: float, allow_reveal: bool) -> void:
	var focus_min := int(focus_seconds / 60.0)
	for item in ITEMS:
		var id: String = item["id"]
		if focus_min >= int(item["unlock_min"]) and not _items.has(id):
			_create_item(item, allow_reveal)
	if allow_reveal:
		Achievements.on_item_unlocked(_items.size())


func reset_layout() -> void:
	for id in _items:
		(_items[id] as Node).queue_free()
	_items.clear()
	_positions.clear()
	_interacting.clear()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


# --- Item creation ---------------------------------------------------------

func _create_item(item: Dictionary, reveal: bool) -> void:
	var id: String = item["id"]
	var tex: Texture2D = load(item["texture"])
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.set_script(THROWABLE)
	spr.position = _positions.get(id, Vector2(item["default_x"], FLOOR_Y))

	var area := Area2D.new()
	area.name = "Area2D"
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = tex.get_size() if tex != null else Vector2(48, 48)
	col.shape = shape
	area.add_child(col)
	spr.add_child(area)
	add_child(spr)  # entering the tree runs ThrowableProp._ready

	_items[id] = spr
	_interacting[id] = false
	spr.grabbed.connect(_on_item_grabbed.bind(id))
	spr.settled.connect(_on_item_settled.bind(id))

	if reveal:
		_reveal(spr, item)


func _reveal(spr: Sprite2D, item: Dictionary) -> void:
	spr.modulate.a = 0.0
	spr.scale = Vector2(0.4, 0.4)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(spr, "modulate:a", 1.0, 0.4)
	tw.tween_property(spr, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("unlock")
	_show_banner("Your fox brought home %s!" % item.get("name", "a find"))


func _show_banner(text: String) -> void:
	_banner.text = text
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(2.2)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)


# --- Interaction + persistence --------------------------------------------

func _on_item_grabbed(id: String) -> void:
	_interacting[id] = true
	Audio.play("grab")


func _on_item_settled(id: String) -> void:
	if _interacting.get(id, false):
		_interacting[id] = false
		Audio.play("drop")
	_save_positions()


func _save_positions() -> void:
	var cfg := ConfigFile.new()
	for id in _items:
		cfg.set_value("pos", id, (_items[id] as Node2D).position)
	cfg.save(PATH)


func _load_positions() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for id in cfg.get_section_keys("pos"):
		var p = cfg.get_value("pos", id)
		if p is Vector2:
			_positions[id] = p
