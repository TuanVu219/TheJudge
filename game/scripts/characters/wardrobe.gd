class_name Wardrobe
extends RefCounted

## Wardrobe and Skin Customization System for THE JUDGE
## Provides modular customization: Body Color, Hats, Glasses, Hairstyles, and Outfits.

const BODY_COLORS: Array[Dictionary] = [
	{"id": "mint", "name": "Mint Green", "color": Color("#6ee0a7"), "base": "mint"},
	{"id": "peach", "name": "Peach Orange", "color": Color("#ff945e"), "base": "peach"},
	{"id": "sky", "name": "Sky Blue", "color": Color("#61b8ff"), "base": "sky"},
	{"id": "lemon", "name": "Lemon Yellow", "color": Color("#ffd643"), "base": "peach"},
	{"id": "berry", "name": "Berry Pink", "color": Color("#ff7eaf"), "base": "peach"},
	{"id": "lavender", "name": "Lavender Purple", "color": Color("#b88aff"), "base": "sky"},
]

const HATS: Array[Dictionary] = [
	{"id": "none", "name": "None"},
	{"id": "tiny_hat", "name": "Tiny Hat"},
	{"id": "feather", "name": "Feather"},
	{"id": "party_cone", "name": "Party Cone"},
	{"id": "crown", "name": "Crown"},
	{"id": "headband", "name": "Headband"},
	{"id": "chef_hat", "name": "Chef Hat"},
]

const GLASSES: Array[Dictionary] = [
	{"id": "none", "name": "None"},
	{"id": "round", "name": "Round Glasses"},
	{"id": "sunglasses", "name": "Cool Sunglasses"},
	{"id": "nerd", "name": "Thick Nerd"},
	{"id": "monocle", "name": "Monocle"},
]

const HAIRSTYLES: Array[Dictionary] = [
	{"id": "bald", "name": "Bald"},
	{"id": "sprout", "name": "Sprout"},
	{"id": "tuft", "name": "Tuft Hair"},
	{"id": "afro", "name": "Afro Puff"},
	{"id": "spiky", "name": "Spiky Hair"},
]

const OUTFITS: Array[Dictionary] = [
	{"id": "classic", "name": "Classic Blue", "color": Color("#1fa4b8"), "is_overalls": false},
	{"id": "overalls", "name": "Denim Overalls", "color": Color("#28528c"), "is_overalls": true},
	{"id": "sporty", "name": "Sporty Red", "color": Color("#d9383a"), "is_overalls": true},
	{"id": "golden", "name": "Golden Royal", "color": Color("#f39c12"), "is_overalls": true},
	{"id": "dark", "name": "Night Tuxedo", "color": Color("#1e272e"), "is_overalls": false},
	{"id": "pastel", "name": "Pastel Diaper", "color": Color("#ffb8b8"), "is_overalls": false},
]

const SAVE_PATH := "user://player_wardrobe.json"


static func default_skin() -> Dictionary:
	return {
		"color": "mint",
		"hat": "tiny_hat",
		"glasses": "none",
		"hair": "bald",
		"outfit": "classic"
	}


static func get_body_color_def(id: String) -> Dictionary:
	for def in BODY_COLORS:
		if def["id"] == id:
			return def
	return BODY_COLORS[0]


static func get_hat_def(id: String) -> Dictionary:
	for def in HATS:
		if def["id"] == id:
			return def
	return HATS[0]


static func get_glasses_def(id: String) -> Dictionary:
	for def in GLASSES:
		if def["id"] == id:
			return def
	return GLASSES[0]


static func get_hair_def(id: String) -> Dictionary:
	for def in HAIRSTYLES:
		if def["id"] == id:
			return def
	return HAIRSTYLES[0]


static func get_outfit_def(id: String) -> Dictionary:
	for def in OUTFITS:
		if def["id"] == id:
			return def
	return OUTFITS[0]


static func get_base_character_id(skin: Dictionary) -> String:
	var color_id := str(skin.get("color", "mint"))
	var def := get_body_color_def(color_id)
	return str(def.get("base", "mint"))


static func serialize(skin: Dictionary) -> String:
	var c := str(skin.get("color", "mint"))
	var h := str(skin.get("hat", "none"))
	var g := str(skin.get("glasses", "none"))
	var hr := str(skin.get("hair", "bald"))
	var o := str(skin.get("outfit", "classic"))
	return "%s.%s.%s.%s.%s" % [c, h, g, hr, o]


static func deserialize(code: String) -> Dictionary:
	var parts := code.split(".")
	if parts.size() < 5:
		return default_skin()
	return {
		"color": parts[0],
		"hat": parts[1],
		"glasses": parts[2],
		"hair": parts[3],
		"outfit": parts[4]
	}


static func encode_to_display_name(display_name: String, skin: Dictionary) -> String:
	var clean := clean_name(display_name)
	return "%s#%s" % [clean, serialize(skin)]


static func decode_from_display_name(raw: String) -> Dictionary:
	var hash_idx := raw.find("#")
	if hash_idx == -1:
		return {
			"name": raw.strip_edges(),
			"skin": default_skin()
		}
	var name_part := raw.substr(0, hash_idx).strip_edges()
	var code_part := raw.substr(hash_idx + 1).strip_edges()
	return {
		"name": name_part if not name_part.is_empty() else "Player",
		"skin": deserialize(code_part)
	}


static func clean_name(raw: String) -> String:
	var hash_idx := raw.find("#")
	if hash_idx != -1:
		raw = raw.substr(0, hash_idx)
	var trimmed := raw.strip_edges()
	return trimmed if not trimmed.is_empty() else "Player"


static func save_local_wardrobe(skin: Dictionary, player_name: String) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		var data := {
			"name": clean_name(player_name),
			"skin": skin
		}
		file.store_string(JSON.stringify(data))


static func load_local_wardrobe() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {
			"name": "Player",
			"skin": default_skin()
		}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {
			"name": "Player",
			"skin": default_skin()
		}
	var json_str := file.get_as_text()
	var json := JSON.new()
	if json.parse(json_str) == OK and json.data is Dictionary:
		var data: Dictionary = json.data
		var skin: Dictionary = data.get("skin", default_skin())
		var name_str := str(data.get("name", "Player"))
		return {
			"name": clean_name(name_str),
			"skin": skin
		}
	return {
		"name": "Player",
		"skin": default_skin()
	}
