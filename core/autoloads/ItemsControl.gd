#这是一个全局脚本

extends Node

## 物品数据的跨语言字段协议；普通物品已由 GDScript 提供，装备与技能卡仍可来自 C#。
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

#存放cardid对应的item -- {cardID：itemdata}
var items: Dictionary = {}

#局外仓库的东西带入游戏
var warehouse_to_player: Array[Resource] = []
var warehouse_to_player_cnt: Array[int] = []

#游戏的东西带入局外仓库
var player_to_warehouse: Array[Resource] = []
var player_to_warehouse_cnt: Array[int] = []

## 节点就绪时建立 CardId 到原始物品 Resource 的索引。
func _ready() -> void:
	items = load_all_items_from_items_folder()

## 递归加载生产物品目录。
## 返回值：以稳定 CardId 为键、原始 Resource 为值的字典。
func load_all_items_from_items_folder() -> Dictionary:
	var loaded_items: Dictionary = {}
	load_items_recursively("res://items", loaded_items)
	return loaded_items

## 把目录中的 ItemData 兼容资源加入给定索引。
## 参数 dir_path：需要扫描的 res:// 目录。
## 参数 target_items：接收 CardId → Resource 映射的字典。
func load_items_recursively(dir_path: String, target_items: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			var full_path: String = dir_path + "/" + file_name

			# 跳过当前目录和上级目录的标记
			if file_name != "." and file_name != "..":
				# 如果是目录，递归进入
				if dir.current_is_dir():
					load_items_recursively(full_path, target_items)
				# 如果是 .tres 文件，加载它
				elif file_name.ends_with(".tres"):
					var item: Resource = load(full_path) as Resource
					if bool(ITEM_DATA_COMPAT.call("is_item_resource", item)):
						var card_id: StringName = ITEM_DATA_COMPAT.call("get_card_id", item, &"")
						if not card_id.is_empty():
							target_items[card_id] = item

			file_name = dir.get_next()
		dir.list_dir_end()

## 按稳定 CardId 返回原始物品 Resource。
## 参数 id：物品的 CardId。
## 返回值：找到时返回 GDScript 或 C# 物品 Resource，否则返回 null。
func get_item(id: StringName) -> Resource:
	return items.get(id, null) as Resource
