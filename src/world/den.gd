extends Node2D
class_name Den

## The fox's home IS the den. Earned items appear in the launcher room as
## draggable, throwable doodads (reusing ThrowableProp). Items unlock by focus
## time; the player can fling them around and their resting spot is remembered.
##
## An item is in one of two places. It's *out* — a live prop in the room — or it's
## *stored* in the drawer (den_inventory.gd), which is where everything unlocked
## can be picked from. The fox brings a new find home itself, so it starts out and
## celebrates; after that the drawer decides, and the choice persists.
##
## Positions, what's out, and what's ever been earned all live in one ConfigFile.
## Saves written before the drawer existed only recorded positions, so on load
## anything with a position is taken to be an earned item that was out.

const THROWABLE := preload("res://src/world/throwable_prop.gd")
const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")
const PATH := "user://focus_fox_den.cfg"
const FLOOR_Y := 384.0

## The find list itself lives in DenCatalog, which is plain data plus static
## helpers so the journal and the tools/ scripts can read it too. This node owns
## only what's stateful: which finds are home and where they're sitting.
const ITEMS := DenCatalog.ITEMS

## Keeps a dropped find inside the room and clear of the drawer, which owns the
## bottom 130px of the window.
const ROOM_MARGIN := 48.0
const ROOM_BOTTOM := 400.0

## Fires whenever what's out in the room changes, so the drawer can restate itself.
signal placement_changed

## Hit test for the drawer, handed over by world.gd. A find let go over the open
## drawer goes back into it.
var store_zone := Callable()

var _items := {}         # id -> Sprite2D (ThrowableProp), only while it's out
var _positions := {}     # id -> Vector2 (saved resting spot)
var _interacting := {}   # id -> bool (true between grab and settle)
var _placed := {}        # id -> bool (out in the room rather than in the drawer)
var _earned := {}        # id -> true once the focus time has ever been reached
var _textures := {}      # id -> Texture2D, so refreshes don't re-load the art
var _banner: Label


func _ready() -> void:
	_load()
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


## Brings the room in line with the current focus time: anything newly earned is
## carried home (animated + celebrated when allow_reveal is set), and anything the
## player left out is put back where it was.
func refresh(focus_seconds: float, allow_reveal: bool) -> void:
	var focus_min := int(focus_seconds / 60.0)
	for item in ITEMS:
		var id: String = item["id"]
		if focus_min < int(item["unlock_min"]):
			continue
		if not DenCatalog.has_art(item):
			continue  # promised by the journal, but there's no sprite to place yet
		var first_time: bool = not bool(_earned.get(id, false))
		if first_time:
			# The fox drops a new find in the room itself. Only once — after that
			# it's the player's to store.
			_earned[id] = true
			_placed[id] = true
		if _placed.get(id, false) and not _items.has(id):
			_create_item(item, allow_reveal and first_time)
	if not _earned.is_empty():
		Achievements.on_item_unlocked(_earned.size())
	_save()
	placement_changed.emit()


func reset_layout() -> void:
	for id in _items:
		(_items[id] as Node).queue_free()
	_items.clear()
	_positions.clear()
	_interacting.clear()
	_placed.clear()
	_earned.clear()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	placement_changed.emit()


# --- Drawer API ------------------------------------------------------------

## Everything the fox has ever brought home, in catalog order, for the drawer to
## lay out: {id, name, texture, placed}.
func unlocked_entries() -> Array:
	var out := []
	for item in ITEMS:
		var id: String = item["id"]
		if not _earned.get(id, false):
			continue
		out.append({
			"id": id,
			"name": str(item.get("name", "a find")),
			"texture": _texture_for(item),
			"placed": is_placed(id),
		})
	return out


func is_placed(id: String) -> bool:
	return _placed.get(id, false)


## Thin passes through to the catalog, so the journal only has to know about the den.
func next_find(focus_seconds: float) -> Dictionary:
	return DenCatalog.next_find(focus_seconds)


func catalog_size() -> int:
	return DenCatalog.size()


## How many finds have actually made it home.
func found_count() -> int:
	return _earned.size()


## Puts a find out in the room at `at`, moving it if it's already out. It rests
## exactly there — the drawer is how you choose where things live.
func place(id: String, at: Vector2) -> void:
	if not _earned.get(id, false):
		return
	var item := DenCatalog.find(id)
	if item.is_empty():
		return
	var spot := _clamp_to_room(at)
	_positions[id] = spot
	_placed[id] = true
	if _items.has(id):
		(_items[id] as Node2D).call("rest_at", spot)
	else:
		# _create_item reads the spot straight back out of _positions.
		_create_item(item, false)
	Audio.play("drop")
	_save()
	placement_changed.emit()


## Takes a find out of the room and back into the drawer.
func store(id: String) -> void:
	if not _items.has(id):
		return
	var spr := _items[id] as Node2D
	_placed[id] = false
	_items.erase(id)
	_interacting.erase(id)

	# It's on its way out, so stop it simulating and stop it catching clicks while
	# it shrinks away.
	spr.set_process(false)
	var area := spr.get_node_or_null("Area2D") as Area2D
	if area != null:
		area.input_pickable = false

	var tw := create_tween().set_parallel(true)
	tw.tween_property(spr, "scale", Vector2(0.3, 0.3), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(spr, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(spr.queue_free)

	Audio.play("close")
	_save()
	placement_changed.emit()


func _texture_for(item: Dictionary) -> Texture2D:
	var id: String = item["id"]
	if not _textures.has(id):
		_textures[id] = load(item["texture"]) if DenCatalog.has_art(item) else null
	return _textures[id]


func _clamp_to_room(at: Vector2) -> Vector2:
	var view := get_viewport_rect().size
	return Vector2(
		clampf(at.x, ROOM_MARGIN, view.x - ROOM_MARGIN),
		clampf(at.y, ROOM_MARGIN, ROOM_BOTTOM)
	)


# --- Item creation ---------------------------------------------------------

func _create_item(item: Dictionary, reveal: bool) -> void:
	var id: String = item["id"]
	var tex := _texture_for(item)
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
	spr.released.connect(_on_item_released.bind(id))
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


## Dropping a find on the open drawer is how you put it away again.
##
## The cursor decides, not the prop: a prop can't be dragged below the floor it
## rests on, so it never physically reaches the drawer sitting underneath. Where
## you let go is what you meant.
func _on_item_released(id: String) -> void:
	if not store_zone.is_valid() or not _items.has(id):
		return
	if store_zone.call(get_global_mouse_position()):
		_interacting[id] = false
		store(id)


func _on_item_settled(id: String) -> void:
	if _interacting.get(id, false):
		_interacting[id] = false
		Audio.play("drop")
	if _items.has(id):
		_positions[id] = (_items[id] as Node2D).position
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _items:
		_positions[id] = (_items[id] as Node2D).position
	for id in _positions:
		cfg.set_value("pos", id, _positions[id])
	for id in _earned:
		cfg.set_value("earned", id, true)
		cfg.set_value("placed", id, _placed.get(id, false))
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	if cfg.has_section("pos"):
		for id in cfg.get_section_keys("pos"):
			var p = cfg.get_value("pos", id)
			if p is Vector2:
				_positions[id] = p
	if cfg.has_section("earned"):
		for id in cfg.get_section_keys("earned"):
			_earned[id] = true
			_placed[id] = bool(cfg.get_value("placed", id, true))
	else:
		# Pre-drawer save: it only knew about positions, and everything it had a
		# position for was an earned item sitting out in the room.
		for id in _positions:
			_earned[id] = true
			_placed[id] = true
