extends RefCounted

## 时间消耗常量的 GDScript 等价实现，等价迁移自 core/constants/TimeCosts.cs。
##
## 旧 C# 是 static class + int 常量。唯一的代码消费方是 core/autoloads/time_system.gd 的
## MapMoveTimeCost 默认值（10）；EnterScene / ChopTree / PlantSeed 在当前两语言里都没有
## 读取方（已用旧路径扫描确认），但它们是旧数值契约的一部分，继续按原值保留并锁定。

## 地图移动消耗的行动值；等价旧 C# TimeCosts.MapMove。
const MapMove: int = 10
## 进入场景消耗的行动值；等价旧 C# TimeCosts.EnterScene。
const EnterScene: int = 5
## 砍树消耗的行动值；等价旧 C# TimeCosts.ChopTree。
const ChopTree: int = 20
## 播种消耗的行动值；等价旧 C# TimeCosts.PlantSeed。
const PlantSeed: int = 10
