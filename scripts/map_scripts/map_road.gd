extends Node2D

@export_dir var home_road: String
@export_dir var forest_road: String
@export_dir var cave_road: String
@export_dir var farm_road: String 
@export_dir var boss_room_road: String

func from_name_get_road(name: String):
	match name:
		"home":
			return home_road
		"forest":
			return forest_road
		"cave":
			return cave_road
		"farm":
			return farm_road
		"boss_room":
			return boss_room_road
		_:
			return "void";
