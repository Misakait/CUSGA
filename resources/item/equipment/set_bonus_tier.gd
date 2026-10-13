extends Resource
class_name EquipmentSetBonusTier

## 套装单个阶级的固定属性与标签配置，不持有角色的激活状态。

## 激活本级所需装备件数。
@export var RequiredPieces: int = 0

## 每项选择属性并填写固定浮点加成，同属性条目叠加。
@export var AttributeBonuses: Array[EquipmentSetAttributeBonus] = []

## 阶级激活后赋予的行为标签；撤销时按同一列表移除。
@export var GrantedTags: Array[StringName] = []
