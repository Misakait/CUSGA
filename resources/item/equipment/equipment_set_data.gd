extends Resource
class_name EquipmentSetData

## 一个套装及其分级效果配置，装备件数统计由 EquipmentComponent 完成。

## 与装备 SetType 数组中一致的套装标识；空字符串不激活。
@export var SetType: String = ""

## 达到件数的全部阶级均生效，元素只能新建专属阶级资源。
@export var Tiers: Array[EquipmentSetBonusTier] = []
