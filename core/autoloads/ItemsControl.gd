#这是一个全局脚本

extends Node

var items = {}
var warehouse_to_player: Array[ItemData]
var warehouse_to_player_cnt: Array[int]
var player_to_warehouse: Array[ItemData]
var player_to_warehouse_cnt: Array[int]

func _ready():
	var dir = DirAccess.open("res://items")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var path = "res://items/" + file_name
				var item = load(path)
				if item is ItemData:
					items[item.CardId] = item
			file_name = dir.get_next()
		dir.list_dir_end()

func get_item(id: StringName) -> ItemData:
	return items.get(id, null)
