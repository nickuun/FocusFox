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
## The owner must be the host window from create_host(), never the launcher. See
## create_host() for why.


## Creates the window that owns every overlay. It is 1x1, parked off every monitor
## and never drawn to; its only job is to be an owner that the user can't touch.
##
## Windows hides a window's owned children whenever that window is minimized. The
## launcher therefore cannot be the owner: minimizing it to check the timer, or to
## get it out of the way, would take the fox down with it. The host is never
## minimized, so the fox survives anything that happens to the launcher.
##
## The cost is one extra taskbar/alt-tab entry, because an unowned visible window
## always gets one — and the host has to stay unowned, otherwise a launcher
## minimize would cascade through it to the overlays. Callers should hook its
## focus_entered so that activating that entry opens the launcher.
static func create_host(parent: Node) -> Window:
	var host := Window.new()
	host.name = "OverlayHost"
	host.title = "Focus Fox"
	host.size = Vector2i(1, 1)
	host.borderless = true
	host.transparent = true
	host.transparent_bg = true
	host.unresizable = true
	host.gui_embed_subwindows = false
	host.visible = false
	parent.add_child(host)
	host.position = offscreen_point()
	host.show()
	return host


## Creates a hidden, borderless, transparent, always-on-top overlay window that
## carries no taskbar or alt-tab presence. `host` must be the create_host() window.
## Call claim() after each show().
static func create(host: Window, node_name: String, size: Vector2i) -> Window:
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
	# Parenting under the host is what makes the host the transient parent, and so
	# the owner, of this window.
	host.add_child(window)
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
