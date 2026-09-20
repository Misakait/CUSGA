extends Resource

## 天气配置资源的 GDScript 等价实现。
##
## 该资源只保存天气名称、元素伤害修正、作物生长倍率和篝火规则；
## WeatherManager 已切换为 GDScript Autoload，旧 C# 类型仅保留为迁移期兼容输入。

## 天气在界面和日志中显示的名称。
@export var WeatherName: String = "晴天"

## 以 ElementType 整数值为键的元素伤害倍率表；空字典表示不额外修正。
@export var ElementModifiers: Dictionary = {}

## 天气对作物生长速度的乘数，1.0 表示保持原速。
@export var CropGrowthSpeedMultiplier: float = 1.0

## 天气是否可以熄灭篝火。
@export var CanExtinguishCampfire: bool = false
