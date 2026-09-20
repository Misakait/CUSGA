extends Resource

## 调试开局配置中的固定物品堆叠条目。
##
## 生产 InventoryComponent 与 BattleDeckComponent 已接收通用 Resource 物品和
## GDScript ItemStack，因此固定物品统一创建生产堆叠；旧 C# 物品派生资源仍可作为输入。

## 生产库存使用的 GDScript 堆叠脚本。
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")

## 堆叠引用的物品数据，可使用 GDScript 普通物品或现有 C# ItemData 派生资源。
@export var Item: Resource

## 创建堆叠时写入的物品数量；非正值沿用旧实现并返回空结果。
@export_range(1, 999, 1) var Amount: int = 1

## 创建堆叠后是否立即生成装备随机属性。
@export var RollRandomStats: bool = true


## 根据当前配置创建生产库存可接收的物品堆叠。
## 返回值：配置无效时返回 null，否则返回生产 GDScript ItemStack 实例。
func CreateStack() -> RefCounted:
	if Item == null or Amount <= 0:
		return null

	## 保留原始 Item Resource 身份，避免堆叠、合成与商店的引用比较发生变化。
	var stack := ITEM_STACK_SCRIPT.new() as RefCounted
	stack.call("SetItem", Item, Amount)
	if RollRandomStats:
		stack.call("RollRandomStats")
	return stack
