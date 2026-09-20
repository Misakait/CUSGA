extends Resource

## 属性修正值条目的 GDScript 生产实现，等价迁移自 AttributeModifierData.cs。
##
## 字段名与旧 C# 属性逐字一致（Type / Mode / ValuePerStack），因此迁移期两侧对象
## 可以被同一套 C# 字段协议（AttributeModifierDataProtocol）读取。
## Type 与 Mode 继续沿用旧 C# 枚举的整数取值：
## AttributeType.PhysAtk = 0、Speed = 4；AttributeModifierMode.FlatAdd = 0、
## PercentAdd = 1、PercentMul = 2。
## 本脚本刻意不声明 class_name，避免与 C# 类型表里的同名全局类冲突。

## 受该条目影响的属性类型（AttributeType 枚举整数）。
@export var Type: int = 0

## 修正模式（AttributeModifierMode 枚举整数）。
@export var Mode: int = 0

## 这个 Buff 每一层提供多少属性修正值，沿用旧 C# 默认值 0。
@export var ValuePerStack: float = 0.0
