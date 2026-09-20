extends Resource

## 状态数据的生产 GDScript 实现（旧 C# StatusEffectData 的等价基类）。
##
## GDScript 无法继承 C# 脚本，因此这里以 GDScript 重新声明基类，字段名、默认值与枚举
## 整数取值与旧 C# 逐字一致（StackPolicy.ResetDuration = 0、DurationExpirePolicy.FirstExpired = 0、
## DurationTickTiming.Start = 0）。子类直接 extends 本脚本；运行时的状态实例仍由保留的
## C# StatusEffectInstance 家族承担，子类通过 CreateInstance 构造对应实例。
## 脚本不声明 class_name，避免与仍在使用的 C# StatusEffectData 全局类型重名。

## 状态的唯一标识，用于叠加、刷新、移除和存档定位。
@export var Id: StringName = &""

## 状态在 UI 中显示的名称；为空时 UI 会回退显示 Id。
@export var DisplayName: String = ""

## 状态在悬停提示框中显示的描述文本，用于解释效果、持续时间或其它玩家需要理解的信息。
@export var Description: String = ""

## 状态在 Buff 栏中显示的图标；未配置时 UI 使用兜底图标，避免状态不可见。
@export var Icon: Texture2D

## 状态允许叠加的最大层数；设置为 0 时表示没有层数上限。
@export var MaxStacks: int = 1

## 叠加策略枚举整数，沿用旧 C# 默认值 StackPolicy.ResetDuration。
@export var Policy: int = 0

## 过期策略枚举整数，沿用旧 C# 默认值 DurationExpirePolicy.FirstExpired。
@export var ExpirePolicy: int = 0

## 持续时间扣减时机枚举整数，沿用旧 C# 默认值 DurationTickTiming.Start。
@export var DurationTickTiming: int = 0

## 同一 hook phase 内的默认执行优先级；数值越小越早执行。
@export var DefaultHookPriority: int = 0

## 持续该单位自己的 N 次行动。
@export var InitOwnerTurnDuration: int = 0

## 持续全场 N 次行动，不管是谁行动。
@export var InitGlobalTurnDuration: int = 0

## 所有存活单位都至少行动过一次算一轮，持续 N 轮。
@export var InitRoundDuration: int = 0
