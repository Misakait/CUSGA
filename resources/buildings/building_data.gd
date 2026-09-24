extends "res://resources/item/item_data.gd"

## 可放置建筑牌的数据定义，继承物品协议以复用库存、商店和配方。
## 实例状态由 RoomBuildingStore 保存，不得写回多人共享的资源配置。

## 策略基类，保证扩展实现完整的提示、预检与同步效果协议。
const INTERACTION_SCRIPT: GDScript = preload("res://resources/buildings/building_interaction.gd")
## 复用生产掉落表，拆除材料与地形掉落使用相同物品堆叠协议。
const LOOT_TABLE_SCRIPT: GDScript = preload("res://resources/loot/loot_table.gd")

## 建筑交互策略；继承 building_interaction.gd，新增建筑时直接替换资源。
@export var Interaction: Resource
## 地面占用尺寸，单位为世界像素；影响重叠检查与默认图标大小。
@export var Footprint: Vector2 = Vector2(64.0, 64.0)
## 玩家与建筑中心的最大交互距离，单位为世界像素，运行时可调整。
@export_range(1.0, 1000.0) var InteractionRadius: float = 120.0
## 玩家允许放置建筑的最大距离，避免隔着房间远程建造。
@export_range(1.0, 1000.0) var PlacementRadius: float = 220.0
## 可选独立表现场景；根节点需继承 building_view.gd，空值使用默认表现。
@export var WorldScene: PackedScene
## 是否允许玩家长按拆除，特殊剧情建筑可关闭；运行时可调整。
@export var Destructible: bool = true
## 拆除需要持续按住左键的真实秒数，与行动值消耗独立；运行时可调整。
@export_range(0.1, 30.0, 0.1) var DemolitionHoldSeconds: float = 1.0
## 拆除时生成的生产掉落表；空值表示无掉落，不应用采集产量加成。
@export var DestructionLoot: Resource


## 判断配置能否作为建筑使用；无参数，返回配置是否完整。
func IsBuildingCard() -> bool:
	return Interaction is INTERACTION_SCRIPT and Footprint.is_finite() \
		and Footprint.x > 0.0 and Footprint.y > 0.0 \
		and is_finite(InteractionRadius) and InteractionRadius > 0.0 \
		and is_finite(PlacementRadius) and PlacementRadius > 0.0


## 校验拆除配置；无参数，返回时长和掉落表是否合法。
func CanDemolish() -> bool:
	return Destructible and is_finite(DemolitionHoldSeconds) and DemolitionHoldSeconds > 0.0 \
		and (DestructionLoot == null or DestructionLoot is LOOT_TABLE_SCRIPT)
