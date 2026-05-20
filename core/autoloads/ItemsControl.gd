#这是一个全局脚本

extends Node

#存放cardid对应的item -- {cardID：itemdata}
var items = {}

#局外仓库的东西带入游戏
var warehouse_to_player: Array[ItemData]
var warehouse_to_player_cnt: Array[int]

#游戏的东西带入局外仓库
var player_to_warehouse: Array[ItemData]
var player_to_warehouse_cnt: Array[int]

func _ready():
	items = load_all_items_from_items_folder()

func load_all_items_from_items_folder():
	var items = {}
	load_items_recursively("res://items", items)
	return items

func load_items_recursively(dir_path: String, items: Dictionary):
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			var full_path = dir_path + "/" + file_name

			# 跳过当前目录和上级目录的标记
			if file_name != "." and file_name != "..":
				# 如果是目录，递归进入
				if dir.current_is_dir():
					load_items_recursively(full_path, items)
				# 如果是 .tres 文件，加载它
				elif file_name.ends_with(".tres"):
					var item = load(full_path)
					if item is ItemData:
						items[item.CardId] = item

			file_name = dir.get_next()
		dir.list_dir_end()

func get_item(id: StringName) -> ItemData:
	return items.get(id, null)
