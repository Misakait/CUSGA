extends "res://resources/talents/talent_effect.gd"

## 为玩家增加一层指定标签的天赋效果。

## 天赋生效时赋予玩家的标签。
@export var TagToGrant: StringName


## 将配置的非空标签赋予目标玩家。
##
## 参数 target_player：接收标签的玩家节点。
## 返回值：无。
func Apply(target_player: Node) -> void:
	if TagToGrant == null or TagToGrant.is_empty():
		return

	var tag_component := target_player.get("TagComponent") as Node
	if tag_component == null:
		return
	tag_component.call("AddTag", TagToGrant)
	print("玩家获得了特殊机制词条：" + str(TagToGrant))
