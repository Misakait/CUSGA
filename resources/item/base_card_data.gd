extends Resource

## 卡牌与物品共用的基础显示数据。
##
## 该资源暂不声明 class_name，避免与仍在使用的 C# BaseCardData 全局类型重名。
## 生产资产切换前，调用方仍通过 C# 兼容类型读取旧资源；字段名保持一致以确保
## 后续资源切换不会改变已有 .tres 的序列化键。

## 稳定卡牌标识，用于资源查找、存档和跨语言匹配。
@export var CardId: StringName = &""

## 面向玩家显示的卡牌名称。
@export var CardName: String = ""

## 卡牌或物品图标。
@export var CardIcon: Texture2D

## 面向玩家显示的描述文本。
@export_multiline var Description: String = ""

## 返回卡牌显示名称，保持 C# BaseCardData.DisplayName 的回退语义。
var DisplayName: String:
	get:
		return _resolve_display_name()

## 返回卡牌显示描述，保持 C# BaseCardData.DisplayDescription 的回退语义。
var DisplayDescription: String:
	get:
		return _resolve_display_description()

## 返回卡牌显示图标，保持 C# BaseCardData.DisplayIcon 的回退语义。
var DisplayIcon: Texture2D:
	get:
		return _resolve_display_icon()

## 解析最终显示名称；派生 Resource 可覆盖该钩子而不重复声明属性。
func _resolve_display_name() -> String:
	return CardName

## 解析最终显示描述；派生 Resource 可覆盖该钩子而不重复声明属性。
func _resolve_display_description() -> String:
	return Description

## 解析最终显示图标；派生 Resource 可覆盖该钩子而不重复声明属性。
func _resolve_display_icon() -> Texture2D:
	return CardIcon
