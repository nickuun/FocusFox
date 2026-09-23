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
##
## --- Animated finds ----------------------------------------------------------
##
## A find with `anim` instead of `texture` is a folder of numbered frames rather than
## one image, and is built as an AnimatedProp rather than a ThrowableProp. `anim` is the
## find's folder name under assets/main_menu/environment/animated/, and `fps` its
## playback rate.
##
## Those frames are generated, not delivered: the artist's folders live outside the repo
## and tools/den_import.py crops and halves them into the tree. See its header — the
## half scale is a stopgap until the set is re-exported at den size, not a decision.
##
## --- Categories ---------------------------------------------------------------
##
## `category` is the drawer tab a find appears under, and must be one of CATEGORIES.
## It is left off for the comforts — the odds and ends that are not furniture, wall art
## or a plant — so the default is what the smallest group gets and everything else says
## so explicitly.
##
## The split is by what a thing IS rather than by how it is mounted, which is why the
## hanging plant is a plant and not wall art despite hanging on the wall. A player
## looking for a plant looks under plants.

const ITEMS := [
	{"id": "desk_plant", "name": "a little desk plant", "unlock_min": 0, "default_x": 135.0,
		"texture": "res://assets/main_menu/environment/plant.png", "category": "plant"},
	{"id": "lamp",      "name": "a lamp",            "unlock_min": 10,  "default_x": 215.0, "texture": "res://assets/main_menu/environment/lamp.png", "category": "furniture"},
	{"id": "rug",       "name": "a soft rug",        "unlock_min": 26, "default_x": 470.0, "texture": "res://assets/main_menu/environment/rug.png", "category": "furniture"},
	{"id": "fern",      "name": "a potted fern",     "unlock_min": 46, "default_x": 700.0, "texture": "res://assets/main_menu/environment/fern.png", "category": "plant"},
	{"id": "mug",       "name": "a mug",             "unlock_min": 69,  "default_x": 800.0, "texture": "res://assets/main_menu/environment/mug.png"},
	{"id": "fireplace_brick", "name": "a brick fireplace", "unlock_min": 94, "default_x": 300.0,
		"anim": "fireplace/brick", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "bookshelf", "name": "a bookshelf",       "unlock_min": 122, "default_x": 320.0, "texture": "res://assets/main_menu/environment/bookshelf.png",
		"surface": true, "category": "furniture"},
	{"id": "painting",  "name": "a little painting", "unlock_min": 151, "default_x": 330.0, "texture": "res://assets/main_menu/environment/painting.png",
		"mount": "wall", "default_y": 205.0, "category": "art"},
	{"id": "cushion",   "name": "a warm cushion",    "unlock_min": 182, "default_x": 545.0, "texture": "res://assets/main_menu/environment/pillow.png"},
	{"id": "blanket",   "name": "a cozy blanket",    "unlock_min": 215, "default_x": 615.0, "texture": "res://assets/main_menu/environment/blanket.png"},
	{"id": "clock",     "name": "a tiny clock",      "unlock_min": 249, "default_x": 830.0, "texture": "res://assets/main_menu/environment/clock.png",
		"mount": "wall", "default_y": 180.0, "category": "art"},
	{"id": "philodendron", "name": "a philodendron", "unlock_min": 284, "default_x": 720.0,
		"rig": "plant_06", "category": "plant"},
	{"id": "abstract_brush_strokes_painting", "name": "an abstract brush strokes painting", "unlock_min": 321, "default_x": 200.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_brush_strokes_painting.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "abstract_black_and_white", "name": "an abstract black and white", "unlock_min": 359, "default_x": 310.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_black_and_white.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "punk_burn_iit_down_poster", "name": "a punk burn iit down poster", "unlock_min": 399, "default_x": 310.0,
		"texture": "res://assets/main_menu/environment/static/posters/punk_burn_iit_down_poster.png",
		"mount": "wall", "default_y": 150.0, "category": "poster"},
	{"id": "abstract_coastal_painting", "name": "an abstract coastal painting", "unlock_min": 439, "default_x": 420.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_coastal_painting.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "abstract_expressionist", "name": "an abstract expressionist", "unlock_min": 480, "default_x": 530.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_expressionist.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "abstract_flowing_lines", "name": "an abstract flowing lines", "unlock_min": 523, "default_x": 640.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_flowing_lines.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "fireplace_stone", "name": "a stone fireplace", "unlock_min": 567, "default_x": 420.0,
		"anim": "fireplace/stone", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "abstract_puzzle_forms", "name": "an abstract puzzle forms", "unlock_min": 611, "default_x": 750.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_puzzle_forms.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "punk_mosh_pit_poster", "name": "a punk mosh pit poster", "unlock_min": 657, "default_x": 420.0,
		"texture": "res://assets/main_menu/environment/static/posters/punk_mosh_pit_poster.png",
		"mount": "wall", "default_y": 190.0, "category": "poster"},
	{"id": "fiddle_plant", "name": "a fiddle-leaf fig", "unlock_min": 703, "default_x": 900.0,
		"anim": "fiddle_plant", "fps": 8.0, "category": "plant"},
	{"id": "abstract_shapes", "name": "an abstract shapes", "unlock_min": 750, "default_x": 860.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_shapes.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "abstract_textured_board", "name": "an abstract textured board", "unlock_min": 799, "default_x": 200.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_textured_board.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "abstract_watercolour", "name": "an abstract watercolour", "unlock_min": 848, "default_x": 310.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abstract_watercolour.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "fireplace_modern", "name": "a modern fireplace", "unlock_min": 897, "default_x": 540.0,
		"anim": "fireplace/modern", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "cottage_couch", "name": "a cottage couch", "unlock_min": 948, "default_x": 520.0,
		"texture": "res://assets/main_menu/environment/static/couches_small/cottage_couch.png",
		"category": "comfort"},
	{"id": "abtract_paint_splatter", "name": "an abtract paint splatter", "unlock_min": 1000, "default_x": 420.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/abtract_paint_splatter.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "punk_punk_poster", "name": "a punk punk poster", "unlock_min": 1052, "default_x": 530.0,
		"texture": "res://assets/main_menu/environment/static/posters/punk_punk_poster.png",
		"mount": "wall", "default_y": 230.0, "category": "poster"},
	{"id": "bohemian_dot_art", "name": "a bohemian dot art", "unlock_min": 1105, "default_x": 530.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/bohemian_dot_art.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "bohemian_painting", "name": "a bohemian painting", "unlock_min": 1158, "default_x": 640.0,
		"texture": "res://assets/main_menu/environment/static/paintings_small/bohemian_painting.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "african_abstract_painting", "name": "an african abstract painting", "unlock_min": 1213, "default_x": 750.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/african_abstract_painting.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "fireplace_gothic", "name": "a gothic fireplace", "unlock_min": 1268, "default_x": 780.0,
		"anim": "fireplace/gothic", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "fireplace_darkwood", "name": "a dark wood fireplace", "unlock_min": 1324, "default_x": 660.0,
		"anim": "fireplace/darkwood", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "couple_painting", "name": "a couple painting", "unlock_min": 1380, "default_x": 860.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/couple_painting.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "punk_poster_death_ray", "name": "a punk poster death ray", "unlock_min": 1437, "default_x": 640.0,
		"texture": "res://assets/main_menu/environment/static/posters/punk_poster_death_ray.png",
		"mount": "wall", "default_y": 150.0, "category": "poster"},
	{"id": "eyptian_painting", "name": "an eyptian painting", "unlock_min": 1495, "default_x": 200.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/eyptian_painting.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "farmlife_painting", "name": "a farmlife painting", "unlock_min": 1554, "default_x": 310.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/farmlife_painting.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "minimalistic_painting_abstract", "name": "a minimalistic painting abstract", "unlock_min": 1613, "default_x": 420.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_abstract.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "minimalistic_painting_bird", "name": "a minimalistic painting bird", "unlock_min": 1673, "default_x": 530.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_bird.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "hanging_plant", "name": "a hanging plant", "unlock_min": 1733, "default_x": 620.0,
		"anim": "hanging_plant", "fps": 8.0, "mount": "wall", "default_y": 196.0, "category": "plant"},
	{"id": "punk_poster_sledge_hammer", "name": "a punk poster sledge hammer", "unlock_min": 1794, "default_x": 750.0,
		"texture": "res://assets/main_menu/environment/static/posters/punk_poster_sledge_hammer.png",
		"mount": "wall", "default_y": 190.0, "category": "poster"},
	{"id": "minimalistic_painting_botanical", "name": "a minimalistic painting botanical", "unlock_min": 1855, "default_x": 640.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_botanical.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "minimalistic_painting_fox_01", "name": "a minimalistic painting fox 01", "unlock_min": 1918, "default_x": 750.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_fox_01.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "fireplace_stove", "name": "a wood-burning stove", "unlock_min": 1980, "default_x": 300.0,
		"anim": "fireplace/stove", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "minimalistic_painting_fox_02", "name": "a minimalistic painting fox 02", "unlock_min": 2044, "default_x": 860.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_fox_02.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "minimalistic_painting_geometric_face", "name": "a minimalistic painting geometric face", "unlock_min": 2107, "default_x": 200.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_geometric_face.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "punk_riot_grrrl_poster", "name": "a punk riot grrrl poster", "unlock_min": 2172, "default_x": 860.0,
		"texture": "res://assets/main_menu/environment/static/posters/punk_riot_grrrl_poster.png",
		"mount": "wall", "default_y": 230.0, "category": "poster"},
	{"id": "minimalistic_painting_geometric_interplay", "name": "a minimalistic painting geometric interplay", "unlock_min": 2237, "default_x": 310.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_geometric_interplay.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "fireplace_industrial", "name": "an industrial fireplace", "unlock_min": 2302, "default_x": 420.0,
		"anim": "fireplace/industrial", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "minimalistic_painting_hand", "name": "a minimalistic painting hand", "unlock_min": 2368, "default_x": 420.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_hand.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "minimalistic_painting_landscape", "name": "a minimalistic painting landscape", "unlock_min": 2435, "default_x": 530.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_landscape.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "pop_art_vibrant_woman_painting", "name": "a pop art vibrant woman painting", "unlock_min": 2502, "default_x": 640.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/pop_art_vibrant_woman_painting.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "minimalistic_painting_pair", "name": "a minimalistic painting pair", "unlock_min": 2570, "default_x": 640.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_pair.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "punk_skull_poster_skull_krusher", "name": "a punk skull poster skull krusher", "unlock_min": 2638, "default_x": 200.0,
		"texture": "res://assets/main_menu/environment/static/posters/punk_skull_poster_skull_krusher.png",
		"mount": "wall", "default_y": 150.0, "category": "poster"},
	{"id": "minimalistic_painting_pottery", "name": "a minimalistic painting pottery", "unlock_min": 2706, "default_x": 750.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_pottery.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "fireplace_concrete", "name": "a concrete fireplace", "unlock_min": 2776, "default_x": 540.0,
		"anim": "fireplace/concrete", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "industrial_couch", "name": "an industrial couch", "unlock_min": 2845, "default_x": 760.0,
		"texture": "res://assets/main_menu/environment/static/couches_small/industrial_couch.png",
		"category": "comfort"},
	{"id": "minimalistic_painting_profile", "name": "a minimalistic painting profile", "unlock_min": 2915, "default_x": 860.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_profile.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "minimalistic_painting_rock_pile", "name": "a minimalistic painting rock pile", "unlock_min": 2986, "default_x": 200.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_rock_pile.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "minimalistic_painting_cat", "name": "a minimalistic painting cat", "unlock_min": 3057, "default_x": 310.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimalistic_painting_cat.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "the_spikes_poster", "name": "a the spikes poster", "unlock_min": 3129, "default_x": 310.0,
		"texture": "res://assets/main_menu/environment/static/posters/the_spikes_poster.png",
		"mount": "wall", "default_y": 190.0, "category": "poster"},
	{"id": "minimlaistic_painting_posed_profile", "name": "a minimlaistic painting posed profile", "unlock_min": 3201, "default_x": 420.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/minimlaistic_painting_posed_profile.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "fireplace_marble", "name": "a marble fireplace", "unlock_min": 3273, "default_x": 660.0,
		"anim": "fireplace/marble", "fps": 12.0, "surface": true, "category": "furniture"},
	{"id": "plant_pianting_minimalistic", "name": "a plant pianting minimalistic", "unlock_min": 3346, "default_x": 530.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/plant_pianting_minimalistic.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "realism_painting_landscape", "name": "a realism painting landscape", "unlock_min": 3419, "default_x": 750.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/realism_painting_landscape.png",
		"mount": "wall", "default_y": 150.0, "category": "art"},
	{"id": "total_anarchy_punk_poster", "name": "a total anarchy punk poster", "unlock_min": 3493, "default_x": 420.0,
		"texture": "res://assets/main_menu/environment/static/posters/total_anarchy_punk_poster.png",
		"mount": "wall", "default_y": 230.0, "category": "poster"},
	{"id": "realsim_plant_painting", "name": "a realsim plant painting", "unlock_min": 3568, "default_x": 860.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/realsim_plant_painting.png",
		"mount": "wall", "default_y": 190.0, "category": "art"},
	{"id": "vibrant_abstract_painting_brush_strokes", "name": "a vibrant abstract painting brush strokes", "unlock_min": 3642, "default_x": 200.0,
		"texture": "res://assets/main_menu/environment/static/paintings_large/vibrant_abstract_painting_brush_strokes.png",
		"mount": "wall", "default_y": 230.0, "category": "art"},
	{"id": "fireplace_victorian", "name": "a victorian fireplace", "unlock_min": 3718, "default_x": 780.0,
		"anim": "fireplace/victorian", "fps": 12.0, "surface": true, "category": "furniture"},
]


## The drawer's tabs, in the order they're shown. Each is {id, label}.
##
## Ordered widest-use first rather than alphabetically: furniture and art are where the
## bulk of the artist's work lands, so they're the two a player reaches for most. The
## comforts are last because they're the leftovers — the three things that are none of
## the others — and DEFAULT_CATEGORY points at them, so a find with no category stated
## falls in with the odds and ends rather than into a tab it doesn't belong in.
const CATEGORIES := [
	{"id": "furniture", "label": "Furniture"},
	{"id": "art",       "label": "Paintings"},
	{"id": "poster",    "label": "Posters"},
	{"id": "plant",     "label": "Plants"},
	{"id": "comfort",   "label": "Comforts"},
]

const DEFAULT_CATEGORY := "comfort"


static func size() -> int:
	return ITEMS.size()


## Which drawer tab this find belongs under. Anything with no category stated, or one
## that isn't in CATEGORIES, falls back to the default rather than vanishing from the
## drawer entirely — a find the player has earned must always be reachable.
static func category_of(item: Dictionary) -> String:
	var id := str(item.get("category", DEFAULT_CATEGORY))
	for category in CATEGORIES:
		if category["id"] == id:
			return id
	return DEFAULT_CATEGORY


static func find(id: String) -> Dictionary:
	for item in ITEMS:
		if item["id"] == id:
			return item
	return {}


## Where an animated find's frames live. Empty for a still one.
const ANIM_DIR := "res://assets/main_menu/environment/animated/"


## Where a rigged plant's parts live.
const RIG_DIR := "res://assets/main_menu/environment/plants/"


## A folder of frames rather than one image — built as an AnimatedProp. See the ITEMS
## note above.
static func is_animated(item: Dictionary) -> bool:
	return str(item.get("anim", "")) != ""


## Parts the engine sways, rather than frames the artist drew — built as a PlantRig.
static func is_rig(item: Dictionary) -> bool:
	return str(item.get("rig", "")) != ""


## The still the drawer and the journal draw for a rigged plant. Written by
## tools/plant_rig.py alongside the parts, because composing a dozen rotated sprites
## for an icon is work the drawer shouldn't be doing per cell.
static func rig_icon(item: Dictionary) -> String:
	if not is_rig(item):
		return ""
	return RIG_DIR + str(item["rig"]) + "/icon.png"


## The first frame of an animated find: what the drawer and the journal draw as its
## icon, and what the den measures to size its hitbox before the prop exists.
##
static func first_frame(item: Dictionary) -> String:
	if not is_animated(item):
		return ""
	return ANIM_DIR + str(item["anim"]) + "/001.png"


## A planned find with no sprite yet can't be earned — see the ITEMS note above.
static func has_art(item: Dictionary) -> bool:
	if is_rig(item):
		return ResourceLoader.exists(rig_icon(item))
	if is_animated(item):
		return ResourceLoader.exists(first_frame(item))
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
