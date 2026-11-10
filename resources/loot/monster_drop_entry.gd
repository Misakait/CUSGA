@tool
extends Resource
class_name MonsterDropEntry

## 怪物掉落池的一项候选结果；空物品也可参与抽奖。
## 物品资源；留空表示本次抽中“空”，不会生成掉落物。
@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "ItemData") var drop_item: Resource
## 本条目在同一池中的相对权重；0 表示不参与抽取。
@export_range(0, 1000000, 1, "or_greater") var drop_weight: int = 1
