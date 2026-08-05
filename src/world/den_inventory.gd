extends Control
class_name DenInventory

## The den's item drawer — a bar of everything the fox has brought home, which
## slides in over the menu's button row. It's one or the other, the buttons or
## the drawer, with a pull tab left peeking at the right edge to call it back in.
##
## Laid out in absolute pixels at the art's native size, the same way
## fox_settings_panel.gd is: MenuLayer's design viewport is 1:1 with the 960x540
## window, so none of this art gets resampled. BODY_Y is picked so the body
## covers the whole button row and sits flush with the window's bottom edge.
##
## Items come out by press-and-hold — pressing a cell lifts a ghost of the item
## onto the cursor, and releasing it anywhere outside the drawer asks the den to
## put the real one there. Releasing back over the drawer cancels. The inverse
## lives in den.gd: a find dragged onto the open drawer gets stored again.

## The player wants `id` placed at `at`, in menu design space. The den decides
## whether that's a legal spot.
signal place_requested(id: String, at: Vector2)
signal opened_changed(is_open: bool)

const FONT := preload("res://assets/not_sprites/pixel_operator/PixelOperator.ttf")
const BODY_BG := preload("res://assets/inventory/den inventory ui/tiltable-background.png")
const TAB_BG := preload("res://assets/inventory/den inventory ui/category-tab.png")
const CELL_BG := preload("res://assets/inventory/den inventory ui/item-cell.png")
const CELL_BG_HOVER := preload("res://assets/inventory/den inventory ui/item-cell-highlighted.png")
const ARROW := preload("res://assets/inventory/den inventory ui/side-buttons.png")

# Sampled off the art so the body reads as one piece with the tab and the cells.
const BORDER := Color("7c5130")
const EDGE_LIGHT := Color("ffecd0")
const INK := Color("4a3222")
const INK_SOFT := Color("8a705c")
## Empty slots keep their frame but sit back a shade, so a half-full bar reads as
## room to grow rather than as missing art.
const EMPTY_TINT := Color(0.94, 0.91, 0.87)
## What's already out in the room sits back, but only just — most of what you own
## is usually out, and a barful of ghosts reads as a disabled drawer.
const PLACED_ICON_ALPHA := 0.55

const VIEW := Vector2(960.0, 540.0)
## The body is as tall as the arrow art and flush with the window's bottom edge,
## which puts its top edge at 410 — below the den's floor line (384) and over the
## whole button row (424..484).
const BODY_H := 130.0
const BODY_Y := VIEW.y - BODY_H
const HANDLE_SIZE := Vector2(57.0, 130.0)
## The tab stays parked at the right edge, so the body stops short of it.
const BODY_W := VIEW.x - HANDLE_SIZE.x
const TAB_SIZE := Vector2(245.0, 45.0)
const TAB_X := 26.0
const CELL_SIZE := Vector2(93.0, 94.0)
const CELL_STEP := 100.0
const PER_PAGE := 7
const ARROW_GAP := 12.0
## The paging arrow and the pull tab are the same sprite pointing the same way, so
## the strip is parked left of centre to keep a gap between the two rather than
## leaving them side by side looking like one control. _right_edge() does the rest.
const HANDLE_CLEAR := 44.0
## Longest edge an icon may take inside a cell. 74 is deliberate: the den art runs
## a little under 100px, and this lets a clean 3/4 reduction through — see
## _icon_size(), which snaps rather than fitting exactly to keep pixels lined up.
const ICON_BOX := 74.0
const ICON_RATIOS: Array[float] = [1.0, 0.75, 2.0 / 3.0, 0.5, 0.4, 1.0 / 3.0, 0.25]
## The ghost rides a touch larger than the cell icon so it reads as lifted.
const GHOST_LIFT := 1.14
const SLIDE_TIME := 0.34

const STRIP_W := CELL_STEP * float(PER_PAGE - 1) + CELL_SIZE.x
const NEXT_ARROW_X := BODY_W - HANDLE_CLEAR - HANDLE_SIZE.x
const STRIP_X := NEXT_ARROW_X - ARROW_GAP - STRIP_W
const PREV_ARROW_X := STRIP_X - ARROW_GAP - HANDLE_SIZE.x
const CELL_Y := (BODY_H - CELL_SIZE.y) * 0.5

var _body: Control
var _handle_art: TextureRect
var _page_label: Label
var _prev_arrow: Control
var _next_arrow: Control
## One per visible slot, rebuilt in place on refresh() rather than re-created:
## {root: Control, bg: TextureRect, icon: TextureRect, id: String}
var _cells: Array[Dictionary] = []

var _entries: Array = []
var _page := 0
var _open := false
var _slide: Tween

var _dragging := false
var _drag_id := ""
var _drag_cell := -1
var _ghost: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Only the body, the tab and the cells should ever swallow a click.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_open(false, true)


# --- Construction ----------------------------------------------------------

func _build() -> void:
	_body = Control.new()
	_body.name = "Body"
	_body.size = Vector2(BODY_W, BODY_H)
	# Stops the Play/Quit buttons underneath being poked through the drawer.
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_body)

	# The fill is a flat swatch, so scaling it can't smear anything.
	var fill := TextureRect.new()
	fill.texture = BODY_BG
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.size = Vector2(BODY_W, BODY_H)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(fill)

	# The tab art carries its own border, and where it meets the body the fill has
	# to run straight through — so the body's top edge is drawn either side of it.
	_top_edge(0.0, TAB_X)
	_top_edge(TAB_X + TAB_SIZE.x, BODY_W - TAB_X - TAB_SIZE.x)
	_right_edge()

	_build_tab()

	_prev_arrow = _arrow(PREV_ARROW_X, true, _on_prev_pressed)
	_next_arrow = _arrow(NEXT_ARROW_X, false, _on_next_pressed)

	for i in PER_PAGE:
		_cells.append(_build_cell(i))

	_build_handle()


## The dark rule plus the light bevel under it, matching the tab art's own edge.
func _top_edge(x: float, w: float) -> void:
	if w <= 0.0:
		return
	var rule := ColorRect.new()
	rule.color = BORDER
	rule.position = Vector2(x, 0.0)
	rule.size = Vector2(w, 3.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(rule)

	var bevel := ColorRect.new()
	bevel.color = EDGE_LIGHT
	bevel.position = Vector2(x, 3.0)
	bevel.size = Vector2(w, 2.0)
	bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(bevel)


## Where the body stops. The body and the pull tab are cut from the same cream, so
## without this the panel looks like it runs off the window and the paging arrow
## beside the tab reads as its twin instead of as a control inside the panel.
func _right_edge() -> void:
	var bevel := ColorRect.new()
	bevel.color = EDGE_LIGHT
	bevel.position = Vector2(BODY_W - 5.0, 3.0)
	bevel.size = Vector2(2.0, BODY_H - 3.0)
	bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(bevel)

	var rule := ColorRect.new()
	rule.color = BORDER
	rule.position = Vector2(BODY_W - 3.0, 0.0)
	rule.size = Vector2(3.0, BODY_H)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(rule)


func _build_tab() -> void:
	# Only the tab's straight middle may stretch; its mitred corners have to stay
	# their authored size.
	var tab := NinePatchRect.new()
	tab.texture = TAB_BG
	tab.patch_margin_left = 14
	tab.patch_margin_right = 14
	tab.patch_margin_top = 8
	# The tab's bottom is open so its fill flows into the body's.
	tab.patch_margin_bottom = 0
	tab.position = Vector2(TAB_X, -TAB_SIZE.y)
	tab.size = TAB_SIZE
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(tab)

	var title := Label.new()
	title.text = "Unlocked Items"
	title.position = Vector2(TAB_X + 18.0, -TAB_SIZE.y + 6.0)
	title.size = Vector2(TAB_SIZE.x - 76.0, TAB_SIZE.y - 8.0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", INK)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font_on(title, 21)
	_body.add_child(title)

	# Hidden until there's actually more than one page to be on.
	_page_label = Label.new()
	_page_label.position = Vector2(TAB_X + TAB_SIZE.x - 58.0, -TAB_SIZE.y + 6.0)
	_page_label.size = Vector2(44.0, TAB_SIZE.y - 8.0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.add_theme_color_override("font_color", INK_SOFT)
	_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font_on(_page_label, 15)
	_body.add_child(_page_label)


## The paging arrows and the pull tab are the same sprite; it points right, so
## anything pointing left is the same art flipped.
func _arrow(x: float, flip: bool, on_pressed: Callable) -> Control:
	var holder := Control.new()
	holder.position = Vector2(x, (BODY_H - HANDLE_SIZE.y) * 0.5)
	holder.size = HANDLE_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(holder)

	var art := TextureRect.new()
	art.texture = ARROW
	art.flip_h = flip
	art.size = HANDLE_SIZE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(art)

	var hit := Button.new()
	hit.flat = true
	hit.size = HANDLE_SIZE
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(on_pressed)
	holder.add_child(hit)

	return holder


func _build_cell(index: int) -> Dictionary:
	var root := Control.new()
	root.position = Vector2(STRIP_X + CELL_STEP * float(index), CELL_Y)
	root.size = CELL_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.add_child(root)

	var bg := TextureRect.new()
	bg.texture = CELL_BG
	bg.size = CELL_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)

	var cell := {"root": root, "bg": bg, "icon": icon, "id": ""}
	root.gui_input.connect(_on_cell_input.bind(index))
	root.mouse_entered.connect(_on_cell_hover.bind(index, true))
	root.mouse_exited.connect(_on_cell_hover.bind(index, false))
	return cell


## Always parked at the right edge whether the drawer is in or out, so there's one
## fixed place to reach for. Only the arrow turns around.
func _build_handle() -> void:
	var holder := Control.new()
	holder.name = "Handle"
	holder.position = Vector2(VIEW.x - HANDLE_SIZE.x, BODY_Y)
	holder.size = HANDLE_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	_handle_art = TextureRect.new()
	_handle_art.texture = ARROW
	_handle_art.size = HANDLE_SIZE
	_handle_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_handle_art)

	var hit := Button.new()
	hit.flat = true
	hit.size = HANDLE_SIZE
	hit.focus_mode = Control.FOCUS_NONE
	hit.tooltip_text = "Den items"
	hit.pressed.connect(toggle)
	holder.add_child(hit)


# --- Open / close ----------------------------------------------------------

func is_open() -> bool:
	return _open


func toggle() -> void:
	set_open(not _open)


func set_open(open: bool) -> void:
	if _open == open:
		return
	Audio.play("open" if open else "close")
	_apply_open(open, false)


func _apply_open(open: bool, instant: bool) -> void:
	_open = open
	# Closed, the arrow points back into the window: pull me in. Open, it points
	# out at the edge it would leave through.
	_handle_art.flip_h = not open
	if not open:
		_cancel_drag()
	var to_x := 0.0 if open else VIEW.x
	if _slide != null and _slide.is_valid():
		_slide.kill()
	if instant:
		_body.position = Vector2(to_x, BODY_Y)
	else:
		_body.position.y = BODY_Y
		_slide = create_tween()
		_slide.tween_property(_body, "position:x", to_x, SLIDE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	opened_changed.emit(open)


# --- Contents --------------------------------------------------------------

## `entries` is the den's unlocked list: {id, name, texture, placed}.
func refresh(entries: Array) -> void:
	# Snapshot first: paging calls this back with our own array, and clearing the
	# argument in place would leave nothing to copy.
	_entries = entries.duplicate()
	_relayout()


func _relayout() -> void:
	var pages := _page_count()
	_page = clampi(_page, 0, pages - 1)

	for i in _cells.size():
		_paint_cell(i)

	var paged := pages > 1
	_prev_arrow.visible = paged
	_next_arrow.visible = paged
	_page_label.visible = paged
	_page_label.text = "%d/%d" % [_page + 1, pages]


func _page_count() -> int:
	return maxi(1, ceili(float(_entries.size()) / float(PER_PAGE)))


func _paint_cell(index: int) -> void:
	var cell := _cells[index]
	var entry := _entry_at(index)
	var bg := cell["bg"] as TextureRect
	var icon := cell["icon"] as TextureRect
	var root := cell["root"] as Control

	if entry.is_empty():
		cell["id"] = ""
		bg.texture = CELL_BG
		bg.self_modulate = EMPTY_TINT
		icon.visible = false
		# Nothing to pick up, so the slot shouldn't eat clicks or light up.
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	cell["id"] = entry["id"]
	bg.texture = CELL_BG
	bg.self_modulate = Color.WHITE
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.tooltip_text = str(entry.get("name", ""))

	var tex := entry.get("texture") as Texture2D
	icon.visible = tex != null
	if tex == null:
		return
	icon.texture = tex
	icon.size = _icon_size(tex)
	icon.position = (CELL_SIZE - icon.size) * 0.5
	# A find that's already out in the room sits back, so at a glance you can see
	# what's on the shelf and what's still in the drawer.
	var out: bool = bool(entry.get("placed", false)) or cell["id"] == _drag_id
	icon.modulate.a = PLACED_ICON_ALPHA if out else 1.0


func _entry_at(index: int) -> Dictionary:
	var i := _page * PER_PAGE + index
	if i < 0 or i >= _entries.size():
		return {}
	return _entries[i] as Dictionary


## Pixel art shrunk by an arbitrary factor drops rows unevenly, so pick the
## largest tidy fraction that fits instead and only fall back to an exact fit for
## art far bigger than the cell.
func _icon_size(tex: Texture2D) -> Vector2:
	var src := tex.get_size()
	var longest := maxf(src.x, src.y)
	if longest <= 0.0:
		return CELL_SIZE
	for r in ICON_RATIOS:
		if longest * r <= ICON_BOX:
			return src * r
	return src * (ICON_BOX / longest)


func _on_prev_pressed() -> void:
	_step_page(-1)


func _on_next_pressed() -> void:
	_step_page(1)


func _step_page(delta: int) -> void:
	var next := posmod(_page + delta, _page_count())
	if next == _page:
		return
	_page = next
	Audio.play("click")
	_relayout()


# --- Drag out --------------------------------------------------------------

func _on_cell_hover(index: int, inside: bool) -> void:
	var cell := _cells[index]
	if str(cell["id"]) == "":
		return
	(cell["bg"] as TextureRect).texture = CELL_BG_HOVER if inside else CELL_BG


func _on_cell_input(event: InputEvent, index: int) -> void:
	if _dragging or not _open:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var entry := _entry_at(index)
	if entry.is_empty():
		return
	_begin_drag(entry, index)
	accept_event()


func _begin_drag(entry: Dictionary, index: int) -> void:
	var tex := entry.get("texture") as Texture2D
	if tex == null:
		return
	_dragging = true
	_drag_id = str(entry["id"])
	_drag_cell = index

	_ghost = TextureRect.new()
	_ghost.texture = tex
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_SCALE
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.size = _icon_size(tex) * GHOST_LIFT
	_ghost.modulate.a = 0.9
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Added last and lifted, so it rides over the drawer as well as the room.
	_ghost.z_index = 10
	add_child(_ghost)
	_follow_mouse()

	# The cell reads as emptied while its item is on the cursor.
	_paint_cell(index)
	Audio.play("grab")
	set_process(true)


func _process(_delta: float) -> void:
	if _dragging:
		_follow_mouse()
	else:
		set_process(false)


func _follow_mouse() -> void:
	if is_instance_valid(_ghost):
		_ghost.position = get_global_mouse_position() - _ghost.size * 0.5


## Runs ahead of the GUI, which is what we want: the release ends the drag
## wherever it happens, cell or not.
func _input(event: InputEvent) -> void:
	if not _dragging or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	var at := get_global_mouse_position()
	var id := _drag_id
	if contains_point(at):
		_cancel_drag()
	else:
		_finish_drag()
		place_requested.emit(id, at)
	get_viewport().set_input_as_handled()


## True for anywhere the drawer itself occupies while it's open — the body, its
## tab and the pull handle. Dropping here means "not in the room": a cell drag
## cancels, and den.gd uses the same test to store a find dragged back in.
func contains_point(p: Vector2) -> bool:
	if not _open:
		return false
	var body := Rect2(_body.position, Vector2(BODY_W, BODY_H))
	var tab := Rect2(_body.position + Vector2(TAB_X, -TAB_SIZE.y), TAB_SIZE)
	var handle := Rect2(VIEW.x - HANDLE_SIZE.x, BODY_Y, HANDLE_SIZE.x, HANDLE_SIZE.y)
	return body.has_point(p) or tab.has_point(p) or handle.has_point(p)


func _cancel_drag() -> void:
	if not _dragging:
		return
	var cell_index := _drag_cell
	var ghost := _ghost
	_clear_drag()
	if cell_index >= 0 and cell_index < _cells.size():
		_paint_cell(cell_index)
	if not is_instance_valid(ghost):
		return
	# Slides back to the slot it came from rather than blinking out, so a misdrop
	# reads as "put back" instead of "lost".
	var to := ghost.position
	if cell_index >= 0 and cell_index < _cells.size():
		var home := _cells[cell_index]["root"] as Control
		to = _body.position + home.position + (CELL_SIZE - ghost.size) * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ghost, "position", to, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(ghost.queue_free)


func _finish_drag() -> void:
	var cell_index := _drag_cell
	var ghost := _ghost
	_clear_drag()
	if cell_index >= 0 and cell_index < _cells.size():
		_paint_cell(cell_index)
	if is_instance_valid(ghost):
		ghost.queue_free()


func _clear_drag() -> void:
	_dragging = false
	_drag_id = ""
	_drag_cell = -1
	_ghost = null
	set_process(false)


# --- Art helpers -----------------------------------------------------------

func _font_on(c: Control, size: int) -> void:
	c.add_theme_font_override("font", FONT)
	c.add_theme_font_size_override("font_size", size)
