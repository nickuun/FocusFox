extends RefCounted
class_name DenCatalog

## The den's find list and the pure logic over it — the single source of truth for
## what exists, what it's called and when it arrives.
##
## Data and static helpers only, deliberately free of autoloads and scene state, so
## anything can read it: the Den node that places finds, the journal that promises
## them, and the tools/ scripts that run outside a running game.

## Keep sorted by unlock_min — next_find() walks the list in order.
##
## unlock_min = focus minutes needed before a find comes home.
##
## mount is "floor" (the default, so it can be left off) or "wall". A floor find
## falls and settles under gravity; a wall find hangs where it's put. A wall find
## also needs a default_y, because there's no floor to land on — see Den.FLOOR_Y
## for where the floor ones come to rest.
##
## surface marks a find you can stand other finds on top of. Opt-in rather than
## derived from the art, because "has a flat top" isn't something a sprite knows:
## a rug is flat and 40px tall, so treating every find as a surface would leave a
## mug resting 40px up in the air on top of it instead of on the floor over it.
##
## texture may be "" for a find that's planned but has no sprite yet. It still
## counts toward the journal's progression, so the fox can promise it, but it can't
## be earned or put in the room until there's art — otherwise an invisible prop
## with a live hitbox ends up on the floor. Drop the sprite in, fill the path in
## here, and it arrives on the next launch with no other changes.
const ITEMS := [
	{"id": "mug",       "name": "a mug",             "unlock_min": 30,  "default_x": 800.0, "texture": "res://assets/main_menu/environment/mug.png"},
	{"id": "lamp",      "name": "a lamp",            "unlock_min": 60,  "default_x": 215.0, "texture": "res://assets/main_menu/environment/lamp.png"},
	{"id": "rug",       "name": "a soft rug",        "unlock_min": 120, "default_x": 470.0, "texture": "res://assets/main_menu/environment/rug.png"},
	# Kept clear of the menu's own desk plant, which is authored into world.tscn at
	# x=135 and is 101 wide — a bookshelf at the left edge buries it entirely.
	{"id": "bookshelf", "name": "a bookshelf",       "unlock_min": 180, "default_x": 320.0, "texture": "res://assets/main_menu/environment/bookshelf.png",
		"surface": true},
	{"id": "blanket",   "name": "a cozy blanket",    "unlock_min": 240, "default_x": 615.0, "texture": "res://assets/main_menu/environment/blanket.png"},
	{"id": "fern",      "name": "a potted fern",     "unlock_min": 300, "default_x": 700.0, "texture": "res://assets/main_menu/environment/fern.png"},
	{"id": "painting",  "name": "a little painting", "unlock_min": 360, "default_x": 330.0, "texture": "res://assets/main_menu/environment/painting.png",
		"mount": "wall", "default_y": 205.0},
	# The art file is pillow.png; the find has always been "cushion" to the save
	# file and the achievements, so the id stays put.
	{"id": "cushion",   "name": "a warm cushion",    "unlock_min": 420, "default_x": 545.0, "texture": "res://assets/main_menu/environment/pillow.png"},
	{"id": "clock",     "name": "a tiny clock",      "unlock_min": 480, "default_x": 830.0, "texture": "res://assets/main_menu/environment/clock.png",
		"mount": "wall", "default_y": 180.0},
]


static func size() -> int:
	return ITEMS.size()


static func find(id: String) -> Dictionary:
	for item in ITEMS:
		if item["id"] == id:
			return item
	return {}


## A planned find with no sprite yet can't be earned — see the ITEMS note above.
static func has_art(item: Dictionary) -> bool:
	var path := str(item.get("texture", ""))
	return path != "" and ResourceLoader.exists(path)


## Hangs on the wall rather than resting on the floor. Everything without an
## explicit mount is a floor find.
static func is_wall(item: Dictionary) -> bool:
	return str(item.get("mount", "floor")) == "wall"


## Other finds can be stood on top of this one — see the `surface` note above.
static func is_surface(item: Dictionary) -> bool:
	return bool(item.get("surface", false))


## What the fox is bringing home next: the first find whose focus threshold hasn't
## been reached, plus the window of focus time it sits in so the journal can draw a
## bar across it. Empty once every threshold has been passed.
##
## Deliberately blind to whether a find has art — the journal promises what the
## catalog says, and a missing sprite is our problem, not the player's.
static func next_find(focus_seconds: float) -> Dictionary:
	var focus_min := int(focus_seconds / 60.0)
	var previous := 0
	for item in ITEMS:
		var at := int(item["unlock_min"])
		if focus_min < at:
			return {
				"name": str(item.get("name", "a find")),
				"at_min": at,
				"from_min": previous,
				"remaining": at - focus_min,
				"done": focus_min - previous,
				"window": maxi(1, at - previous),
			}
		previous = at
	return {}
