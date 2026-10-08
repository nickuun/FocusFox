extends SceneTree

func _initialize() -> void:
	call_deferred("check")

func make_basket(data := {}) -> WoolBasket:
	var basket := WoolBasket.new()
	basket.texture = load("res://assets/main_menu/environment/wool/empty-wool-basket.png")
	basket.centered = false
	basket.offset = Vector2(-48, -64)
	basket.position = Vector2(300, 367)
	basket.bound_left = 60
	basket.bound_right = 900
	basket.drag_floor = 450
	basket.floor_provider = func(_x, _y): return 367.0
	var area := Area2D.new()
	area.name = "Area2D"
	basket.add_child(area)
	basket.restore_contents(data)
	root.add_child(basket)
	return basket

func check() -> void:
	var basket := make_basket()
	assert(basket._balls.size() == 4)
	for ball in basket._balls:
		assert(not ball.is_processing())
	basket.rest_at(basket.position)
	# Pull white out and leave it on the floor.
	var before_grab := basket._balls[0].global_position
	basket._balls[0]._begin_drag()
	assert(basket._balls[0].get_parent() == root)
	assert(basket._balls[0].global_position == before_grab)
	assert(basket._balls[0]._drag_offset == basket._balls[0].position - basket._balls[0]._mouse())
	basket._balls[0]._dragging = false
	basket._balls[0].position = Vector2(420, 367)
	basket._release_wool(0)
	basket._balls[0].rest_at(Vector2(420, 367))
	var loose_world := basket._balls[0].global_position
	var packed_world := basket._balls[1].global_position
	basket.position.x += 90
	basket._process(0.0)
	assert(basket._balls[0].global_position.is_equal_approx(loose_world))
	assert(basket._balls[1].global_position.is_equal_approx(packed_world + Vector2(90, 0)))
	# Move white into blue's slot: blue moves to the vacant white slot.
	basket._grab_wool(0)
	basket._balls[0].position = basket.position + basket.SLOTS[1]
	basket._release_wool(0)
	assert(basket._slots[0] == 1 and basket._slots[1] == 0)
	assert(basket._balls[0].get_parent() == basket)
	assert(not basket._balls[0].is_processing())
	# Save a mixed packed/loose arrangement and reconstruct it.
	basket._grab_wool(2)
	basket._balls[2].position = basket.position + Vector2(-100, 0)
	basket._release_wool(2)
	basket._balls[2].rest_at(basket.position + Vector2(-100, 0))
	var data := basket.save_contents()
	var restored := make_basket(data)
	assert(restored._slots == basket._slots)
	assert(restored._balls[2].global_position == basket._balls[2].global_position)
	# Loose wool lands on the floor and supports another ball.
	var loose_x := restored._balls[2].position.x
	assert(is_equal_approx(restored._wool_floor(loose_x, 267, 2), 367.0))
	restored._balls[2].rest_at(Vector2(loose_x, 367))
	restored._grab_wool(3)
	assert(is_equal_approx(restored._wool_floor(loose_x, 300, 3), 340.0))
	restored.tidy_contents()
	assert(restored._slots == [0, 1, 2, 3])
	for ball in restored._balls:
		assert(ball.get_parent() == restored)
		assert(not ball.is_processing())
	restored.stop_contents()
	assert(not restored._balls[0].is_processing())
	basket.free()
	restored.free()
	# Load after autoload registration, exercising the real catalog/den creation path.
	# Exercise drawer placement without writing to the player's save files.
	var den_script := GDScript.new()
	den_script.source_code = 'extends "res://src/world/den.gd"\nfunc _save() -> void:\n\tpass\nfunc _load() -> void:\n\tpass\n'
	assert(den_script.reload() == OK)
	var den: Node2D = den_script.new()
	root.add_child(den)
	var item: Dictionary = DenCatalog.find("wool_basket")
	den._create_item(item, false)
	assert(den._items["wool_basket"] is WoolBasket)
	assert(den._items["wool_basket"].texture.get_width() == 96)
	assert(den._texture_for(item).get_height() == 74)
	den._earned["wool_basket"] = true
	var original: WoolBasket = den._items["wool_basket"]
	original._grab_wool(0)
	var loose_ball := original._balls[0]
	den.store("wool_basket")
	assert(loose_ball.is_queued_for_deletion())
	den.place("wool_basket", Vector2(500, 367))
	var unpacked: WoolBasket = den._items["wool_basket"]
	assert(unpacked._slots == [0, 1, 2, 3])
	for ball in unpacked._balls:
		assert(ball.get_parent() == unpacked and not ball.is_processing())
	den.free()
	print("PASS: stable detach, basket movement, slot swaps, save/restore, stacking, tidy, drawer repacking and resized assets")
	quit()
