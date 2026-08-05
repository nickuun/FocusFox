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
## texture may be "" for a find that's planned but has no sprite yet. It still
## counts toward the journal's progression, so the fox can promise it, but it can't
## be earned or put in the room until there's art — otherwise an invisible prop
## with a live hitbox ends up on the floor. Drop the sprite in, fill the path in
## here, and it arrives on the next launch with no other changes.
const ITEMS := [
	{"id": "mug",       "name": "a mug",             "unlock_min": 30,  "default_x": 792.0, "texture": "res://assets/main_menu/environment/mug.png"},
	{"id": "lamp",      "name": "a lamp",            "unlock_min": 60,  "default_x": 250.0, "texture": ""},
	{"id": "rug",       "name": "a soft rug",        "unlock_min": 120, "default_x": 470.0, "texture": ""},
	{"id": "bookshelf", "name": "a bookshelf",       "unlock_min": 180, "default_x": 120.0, "texture": ""},
	{"id": "blanket",   "name": "a cozy blanket",    "unlock_min": 240, "default_x": 620.0, "texture": ""},
	# Stand-in art: this is the same pot as the menu's desk plant, so you get two of
	# them until there's a fern sprite. Swap the path, not the entry.
	{"id": "fern",      "name": "a potted fern",     "unlock_min": 300, "default_x": 690.0, "texture": "res://assets/main_menu/environment/plant.png"},
	{"id": "painting",  "name": "a little painting", "unlock_min": 360, "default_x": 330.0, "texture": ""},
	{"id": "cushion",   "name": "a warm cushion",    "unlock_min": 420, "default_x": 560.0, "texture": ""},
	{"id": "clock",     "name": "a tiny clock",      "unlock_min": 480, "default_x": 860.0, "texture": ""},
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
