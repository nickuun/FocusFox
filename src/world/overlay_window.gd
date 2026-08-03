extends RefCounted
class_name OverlayWindow

## Factory for the app's desktop overlays — the fox, the ball, and whatever props
## we add next. Every overlay goes through here so it stays invisible to the
## window manager.
##
## Why this exists: Windows hands a taskbar button and an alt-tab entry to every
## visible, unowned, non-tool top-level window, and a Godot child Window is
## exactly that. So each overlay used to stack up another entry in the taskbar
## and alt-tab. Giving a window an OS *owner* removes it from both, and the only
## route to an owner from GDScript is transient + exclusive.
##
## Two non-obvious rules, both found the hard way:
##   1. Ownership is dropped whenever the window is shown, because show() re-pushes
##      the node's own flags — and Godot destroys and re-creates the OS window on
##      every hide/show. claim() has to run after every show().
##   2. Godot tracks only one exclusive child per parent Window and pushes an error
##      if a second sibling asks for it. Setting it through DisplayServer applies
##      the OS ownership without that bookkeeping, so any number of overlays can be
##      owned — and each one keeps its own mouse-passthrough region, so they all
##      stay independently clickable.
##
## The owner is the launcher (the root window). That keeps the app to a single
## taskbar/alt-tab entry, which is the whole point — an owner window that is not
## already in the taskbar does not exist, since anything unowned and visible gets
## an entry of its own. The catch is that Windows hides a window's owned children
## whenever the owner is minimized, so the launcher must never actually minimize
## while the fox is out; World parks it off-screen instead and un-minimizes it if
## the OS minimizes it behind our back. See World._hide_to_tray.
##
## Escaping that constraint entirely needs WS_EX_TOOLWINDOW, which needs native
## code — with it the overlays would need no owner at all and this whole
## transient/exclusive dance could go away.


## Creates a hidden, borderless, transparent, always-on-top overlay window that
## carries no taskbar or alt-tab presence. `owner_window` must be the launcher
## (root) window. Call claim() after each show().
static func create(owner_window: Window, node_name: String, size: Vector2i) -> Window:
	var window := Window.new()
	window.name = node_name
	# Never shown to the user (owned windows are absent from the taskbar and
	# alt-tab), but it makes the window identifiable when debugging from outside.
	window.title = node_name
	window.size = size
	window.borderless = true
	window.always_on_top = true
	window.transparent = true
	window.transparent_bg = true
	window.unresizable = true
	window.gui_embed_subwindows = false
	window.visible = false
	# Never taking focus means clicking the fox doesn't pull you out of whatever
	# you were working on — it still receives mouse events, it just won't activate.
	window.set_flag(Window.FLAG_NO_FOCUS, true)
	# Parenting under the launcher is what makes it the transient parent, and so
	# the owner, of this window.
	owner_window.add_child(window)
	# Only valid once the window exists, i.e. after it has entered the tree.
	window.transient = true
	return window


## Re-applies the OS ownership that keeps this window out of the taskbar and
## alt-tab. Cheap and idempotent; call it after every show().
static func claim(window: Window) -> void:
	if not is_instance_valid(window) or not window.visible:
		return
	var id := window.get_window_id()
	if id == DisplayServer.INVALID_WINDOW_ID:
		return
	DisplayServer.window_set_exclusive(id, true)


## A point just past the right edge of the whole virtual desktop, so it clears
## every monitor whichever one is in use.
static func offscreen_point() -> Vector2i:
	var bounds := Rect2i(DisplayServer.screen_get_position(0), DisplayServer.screen_get_size(0))
	for index in DisplayServer.get_screen_count():
		bounds = bounds.merge(Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index)))
	return Vector2i(bounds.end.x + 64, bounds.position.y + 64)
