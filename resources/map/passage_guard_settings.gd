extends Resource

## 保存通道驻守系统的全局配置。
##
## 该 Resource 只保存可序列化数据；概率合并由驻守概率服务完成，怪物解析仍由地图控制器完成。

## 基础驻守概率，使用 0 到 1 的小数表示。
@export_range(0.0, 1.0, 0.01) var BaseGuardChance: float = 0.3

## 拥有该标签时，入夜生成驻守表会跳过 home 相关通道。
@export var HomeProtectionTag: StringName = &""

## 由标签触发的概率修正资源列表。
@export var ProbabilityModifiers: Array[Resource] = []

## 当地图属性没有配置驻守池时使用的默认 encounter 资源列表。
@export var DefaultGuardPool: Array[Resource] = []
