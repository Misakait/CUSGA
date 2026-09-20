@tool
extends McpTestSuite

## FactionComponent GDScript 生产迁移的行为契约套件。

## 待验证的阵营组件脚本。
const FACTION_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/faction_component.gd")


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：阵营组件契约套件名。
func suite_name() -> String:
	return "faction_component_contract"


## 验证默认阵营和三个固定枚举整数值均可无损保存。
## 返回值：无。
func test_faction_component_preserves_enum_values() -> void:
	## 待验证的阵营组件实例。
	var component := FACTION_COMPONENT_SCRIPT.new() as Node
	assert_eq(component.get("Faction"), 0, "默认阵营必须保持 Hostile=0。")
	component.set("Faction", 1)
	assert_eq(component.get("Faction"), 1, "PlayerSummon 必须保持整数值 1。")
	component.set("Faction", 2)
	assert_eq(component.get("Faction"), 2, "Neutral 必须保持整数值 2。")
	component.free()
