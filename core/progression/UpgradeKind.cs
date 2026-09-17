namespace CUSGA.core.progression;

/// <summary>
/// 可用金币升级的项目。
/// </summary>
/// <remarks>
/// 对 GDScript 不暴露本枚举：<c>PlayerProgression</c> 用具名方法
/// （<c>GetWarehouseCapacity</c> / <c>TryUpgradeCarrySlots</c> …）对外提供能力，
/// 因此界面侧不会依赖这些数值。已有成员的数值仍不允许重排，只能追加。
/// </remarks>
public enum UpgradeKind
{
    /// <summary>局外仓库的槽位数量。</summary>
    WarehouseCapacity = 0,

    /// <summary>可带入游戏的物品栏位数量。</summary>
    CarrySlots = 1,
}
