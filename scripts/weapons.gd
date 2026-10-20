class_name WeaponDB
extends RefCounted
## Static data tables: weapons, rarity tiers and stackable inventory items.

const WEAPONS := {
	"pistol": {
		"name": "Pistol", "slot": 2, "dmg": 24.0, "rate": 0.26, "mag": 12, "reload": 1.5,
		"spread": 0.010, "recoil": 0.012, "auto": false, "pellets": 1, "ammo": "9mm",
		"range": 120.0, "sound": "shot_pistol", "len": 0.25, "color": Color(0.18, 0.18, 0.2), "bot_dmg": 9.0,
	},
	"ar": {
		"name": "Assault Rifle", "slot": 1, "dmg": 27.0, "rate": 0.11, "mag": 30, "reload": 2.3,
		"spread": 0.014, "recoil": 0.010, "auto": true, "pellets": 1, "ammo": "5.56",
		"range": 250.0, "sound": "shot_ar", "len": 0.8, "color": Color(0.25, 0.27, 0.22), "bot_dmg": 8.0,
	},
	"smg": {
		"name": "SMG", "slot": 1, "dmg": 16.0, "rate": 0.07, "mag": 35, "reload": 1.9,
		"spread": 0.030, "recoil": 0.006, "auto": true, "pellets": 1, "ammo": "9mm",
		"range": 120.0, "sound": "shot_smg", "len": 0.5, "color": Color(0.2, 0.2, 0.25), "bot_dmg": 6.0,
	},
	"shotgun": {
		"name": "Shotgun", "slot": 1, "dmg": 11.0, "rate": 0.85, "mag": 6, "reload": 2.8,
		"spread": 0.060, "recoil": 0.040, "auto": false, "pellets": 8, "ammo": "12ga",
		"range": 60.0, "sound": "shot_shotgun", "len": 0.85, "color": Color(0.35, 0.22, 0.12), "bot_dmg": 20.0,
	},
}

const RARITY := [
	{"name": "Common", "mult": 1.0, "color": Color(0.85, 0.85, 0.85)},
	{"name": "Uncommon", "mult": 1.1, "color": Color(0.3, 0.9, 0.35)},
	{"name": "Rare", "mult": 1.25, "color": Color(0.3, 0.55, 1.0)},
	{"name": "Epic", "mult": 1.4, "color": Color(0.75, 0.35, 1.0)},
]

const ITEMS := {
	"9mm": {"name": "9mm Ammo", "weight": 0.1, "kind": "ammo"},
	"5.56": {"name": "5.56 Ammo", "weight": 0.15, "kind": "ammo"},
	"12ga": {"name": "12ga Shells", "weight": 0.3, "kind": "ammo"},
	"bandage": {"name": "Bandage", "weight": 1.0, "kind": "heal"},
	"medkit": {"name": "Medkit", "weight": 4.0, "kind": "heal"},
	"grenade": {"name": "Grenade", "weight": 3.0, "kind": "grenade"},
}


static func display_name(kind: String, id: String, rarity: int) -> String:
	var rname: String = RARITY[rarity]["name"]
	match kind:
		"weapon":
			var wname: String = WEAPONS[id]["name"]
			return "%s (%s)" % [wname, rname]
		"armor":
			return "Body Armor (%s)" % rname
		"backpack":
			return "Backpack (%s)" % rname
		_:
			var iname: String = ITEMS[id]["name"]
			return iname
