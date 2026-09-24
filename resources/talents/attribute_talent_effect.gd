extends "res://resources/talents/talent_effect.gd"

## 为玩家指定属性增加永久数值的天赋效果。

## AttributeType 的固定显示名称，顺序与 C# 枚举 0..14 保持一致。
const ATTRIBUTE_NAMES: Array[String] = [
	"PhysAtk",
	"PhysDef",
	"MagPower",
	"MagResist",
	"Speed",
	"MaxHealth",
	"MaxEnergy",
	"FixedPhysPenetration",
	"PhysPenetrationRate",
	"FixedMagicPenetration",
	"MagicPenetrationRate",
	"CritRate",
	"CritDamage",
	"EvasionRate",
	"LifestealRate",
]

## 需要增加的 AttributeType 固定整数值。
@export_enum(
	"PhysAtk:0",
	"PhysDef:1",
	"MagPower:2",
	"MagResist:3",
	"Speed:4",
	"MaxHealth:5",
	"MaxEnergy:6",
	"FixedPhysPenetration:7",
	"PhysPenetrationRate:8",
	"FixedMagicPenetration:9",
	"MagicPenetrationRate:10",
	"CritRate:11",
	"CritDamage:12",
	"EvasionRate:13",
	"LifestealRate:14",
) var TargetAttribute: int = 0

## 永久增加的固定数值。
@export var BonusValue: float = 0.0


## 对玩家身上的属性组件应用永久加成。
##
## 解析顺序刻意是「先稳定属性协议、再场景路径兜底」：
## 玩家的属性组件既可能由玩家脚本用属性名暴露（player.gd 的 `Attributes`），
## 也可能只是挂在组件子节点下。只认其中一种写法会让另一侧的接线静默失效 ——
## 本函数此前只查玩家根下的 `AttributeComponent`，而 player.tscn 的实际布局是
## `Components/AttributeComponent`，于是属性类天赋从不生效且不留任何日志。
##
## 参数 target_player：接收效果的玩家节点。
## 返回值：无。
func Apply(target_player: Node) -> void:
	# 属性协议优先：与 tag_talent_effect.gd 读 TagComponent 的方式保持对称。
	# 必须显式标注类型：`get()` 返回 Variant，用 `:=` 推断会触发本项目
	# 把 inference_on_variant 当错误处理的解析失败。
	var attribute_component: Node = target_player.get("Attributes") as Node
	if attribute_component == null:
		attribute_component = target_player.get_node_or_null("Components/AttributeComponent")
	if attribute_component == null:
		# 不静默返回：接线断裂必须留下可诊断的痕迹，否则表现为「天赋选了没反应」。
		push_warning(
			"AttributeTalentEffect: 在 %s 上找不到属性组件（已尝试 Attributes 属性与 Components/AttributeComponent），本次加成未生效。"
			% target_player.name
		)
		return

	attribute_component.call("AddPermanentBonus", TargetAttribute, BonusValue)
	var attribute_name := str(TargetAttribute)
	if TargetAttribute >= 0 and TargetAttribute < ATTRIBUTE_NAMES.size():
		attribute_name = ATTRIBUTE_NAMES[TargetAttribute]
	print("天赋生效：%s 永久增加了 %s！" % [attribute_name, BonusValue])
