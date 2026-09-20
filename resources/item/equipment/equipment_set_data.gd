extends Resource

## 一组装备套装及其分级效果的配置 Resource。
##
## 本脚本不负责统计已装备件数。迁移期间 Tiers 使用通用 Resource 数组，使旧 C#
## SetBonusTier 与新的 GDScript tier 可以并行作为兼容输入。

## 套装类型的整数值；None/Wooden/Stone/Iron 对应 0..3。
@export var SetType: int = 0

## 套装的全部分级效果；数组顺序保持检查器中的序列化顺序。
@export var Tiers: Array[Resource] = []
