@tool
extends Control
class_name PawIcon

## A little drawn paw print: one pad + four toes. Used for the weekly trail in
## the journal. `active` paws are solid; inactive/future ones fade out.

@export var active := true: set = set_active
@export var paw_color := Color("8a5630"): set = set_paw_color

func set_active(v: bool) -> void:
	active = v
	queue_redraw()

func set_paw_color(c: Color) -> void:
	paw_color = c
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var col := paw_color if active else Color(paw_color.r, paw_color.g, paw_color.b, 0.18)

	# Main pad (a soft rounded blob, approximated with overlapping circles).
	var pad := Vector2(w * 0.5, h * 0.66)
	var pad_r := w * 0.24
	draw_circle(pad, pad_r, col)
	draw_circle(pad + Vector2(-pad_r * 0.55, -pad_r * 0.15), pad_r * 0.72, col)
	draw_circle(pad + Vector2(pad_r * 0.55, -pad_r * 0.15), pad_r * 0.72, col)

	# Four toes arched above the pad.
	var toe_r := w * 0.115
	var toe_y := h * 0.30
	var spread := w * 0.30
	draw_circle(Vector2(w * 0.5 - spread, toe_y + h * 0.07), toe_r * 0.95, col)
	draw_circle(Vector2(w * 0.5 - spread * 0.42, toe_y - h * 0.04), toe_r, col)
	draw_circle(Vector2(w * 0.5 + spread * 0.42, toe_y - h * 0.04), toe_r, col)
	draw_circle(Vector2(w * 0.5 + spread, toe_y + h * 0.07), toe_r * 0.95, col)
