extends RefCounted

## 全局事件总线信号名的 GDScript 等价实现，等价迁移自 core/constants/GDSignals.cs。
##
## 旧 C# 是 static class + readonly StringName 字段。这些名字是跨语言信号契约：Autoload
## GlobalEventBus 与地图系统都按 StringName 连接 / 发射，任一字符变化都会静默失去连接，
## 因此取值必须逐字一致。GDScript 生产脚本继续直接使用字面量 &"..."，本载体负责单一来源
## 与契约锁定（tests/godot/test_core_constants_contract.gd 同时核对旧 C# 与总线声明）。
## 旧 C# 里被注释掉的 OnInventoryToggled 从未生效，本载体不迁移它。

## 玩家获得天赋信号；等价旧 C# GDSignals.OnPlayerAcquiredTalent。
const OnPlayerAcquiredTalent: StringName = &"on_player_acquired_talent"
## 状态变化信号；等价旧 C# GDSignals.OnStatusChanged。
const OnStatusChanged: StringName = &"on_status_changed"
## 实体掉落信号；等价旧 C# GDSignals.OnEntityDropped。
const OnEntityDropped: StringName = &"on_entity_dropped"
## 进入宝库信号；等价旧 C# GDSignals.OnEnteredVault。
const OnEnteredVault: StringName = &"on_entered_vault"
## 进入房间信号；等价旧 C# GDSignals.OnEnteredRoom。
const OnEnteredRoom: StringName = &"on_entered_room"
