extends "res://resources/item/item_data.gd"

## 资源卡的生产 GDScript Resource 实现。
##
## 旧 C# ResourceCardData 没有额外字段或行为，只继承 ItemData 的通用物品数据。
## 资源卡继续使用 ItemData 的字段、显示回退、堆叠上限和商店价格默认值，
## 这样切换脚本不会改变配方、地形掉落或调试装载中的序列化数据。
