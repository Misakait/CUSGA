extends Resource

## 由玩家标签触发的通道驻守概率修正。
##
## 该资源只保存可编辑配置；标签匹配与概率合并由
## passage_guard_probability_provider.gd 负责，旧 C# 资源仍可作为兼容输入。

## 触发该修正所需的标签；空标签表示始终生效。
@export var RequiredTag: StringName = &""

## 固定概率点修正值，使用 0 到 1 的小数表示。
@export_range(-1.0, 1.0, 0.01) var AdditiveChance: float = 0.0

## 应用于基础概率与加法修正之和的乘法倍率。
@export_range(0.0, 10.0, 0.01) var Multiplier: float = 1.0
