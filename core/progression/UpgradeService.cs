using System;

namespace CUSGA.core.progression;

/// <summary>
/// 容量升级的纯规则表：每一级值多少、升级要花多少金币。
/// </summary>
/// <remarks>
/// 全部是静态纯函数，不依赖 Godot 也不持有状态，因此可以在任何 runner 里直接验证。
/// <para>
/// 数值集中在这里而不是散落在 UI 里：升级按钮要显示「下一级多少钱」，规则层要判断「钱够不够」，
/// 两处必须用同一份数据，否则会出现界面显示 300、实际扣 600 的分裂。
/// </para>
/// </remarks>
public static class UpgradeService
{
    /// <summary>仓库的初始槽位数。</summary>
    public const int WarehouseBaseValue = 27;

    /// <summary>仓库每升一级增加的槽位数（正好是界面里的一行）。</summary>
    public const int WarehouseValuePerLevel = 9;

    /// <summary>仓库容量可升级的次数上限。</summary>
    public const int WarehouseMaxLevel = 3;

    /// <summary>仓库容量各级的升级费用，索引即「升级前的等级」。</summary>
    private static readonly int[] WarehouseCosts = [300, 600, 1000];

    /// <summary>带入栏的初始数量。</summary>
    public const int CarryBaseValue = 5;

    /// <summary>带入栏每升一级增加的数量。</summary>
    public const int CarryValuePerLevel = 1;

    /// <summary>带入栏可升级的次数上限。</summary>
    public const int CarryMaxLevel = 5;

    /// <summary>带入栏各级的升级费用，索引即「升级前的等级」。</summary>
    private static readonly int[] CarryCosts = [200, 350, 550, 800, 1100];

    /// <summary>
    /// 读取某个升级项的最大等级。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <returns>最大等级（正整数）。</returns>
    public static int GetMaxLevel(UpgradeKind kind) =>
        kind switch
        {
            UpgradeKind.WarehouseCapacity => WarehouseMaxLevel,
            UpgradeKind.CarrySlots => CarryMaxLevel,
            _ => 0,
        };

    /// <summary>
    /// 把等级收窄到合法范围。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <param name="level">待校验的等级，可能是来自存档的任意整数。</param>
    /// <returns>落在 <c>[0, GetMaxLevel(kind)]</c> 内的等级。</returns>
    /// <remarks>
    /// 存档是玩家本机文件，可能被手工改成负数或超大值。所有对外入口都先过这一步，
    /// 避免非法等级算出负容量之类的荒唐结果。
    /// </remarks>
    public static int ClampLevel(UpgradeKind kind, int level) => Math.Clamp(level, 0, GetMaxLevel(kind));

    /// <summary>
    /// 计算某个等级对应的实际数值。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <param name="level">当前等级。</param>
    /// <returns>该等级下的仓库槽位数或带入栏数量。</returns>
    public static int GetValue(UpgradeKind kind, int level)
    {
        int clamped = ClampLevel(kind, level);
        return kind switch
        {
            UpgradeKind.WarehouseCapacity => WarehouseBaseValue + (WarehouseValuePerLevel * clamped),
            UpgradeKind.CarrySlots => CarryBaseValue + (CarryValuePerLevel * clamped),
            _ => 0,
        };
    }

    /// <summary>
    /// 判断某个等级是否已经满级。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <param name="level">当前等级。</param>
    /// <returns>已达到最大等级时为 <see langword="true"/>。</returns>
    public static bool IsMaxLevel(UpgradeKind kind, int level) => ClampLevel(kind, level) >= GetMaxLevel(kind);

    /// <summary>
    /// 读取从当前等级升到下一级所需的金币。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <param name="level">当前等级。</param>
    /// <returns>升级费用；已满级时返回 0。</returns>
    public static int GetCost(UpgradeKind kind, int level)
    {
        int clamped = ClampLevel(kind, level);
        if (IsMaxLevel(kind, clamped))
        {
            return 0;
        }

        int[] costs = kind switch
        {
            UpgradeKind.WarehouseCapacity => WarehouseCosts,
            UpgradeKind.CarrySlots => CarryCosts,
            _ => [],
        };

        return clamped < costs.Length ? costs[clamped] : 0;
    }

    /// <summary>
    /// 计算把某个升级项从当前等级升满还需要多少金币。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <param name="level">当前等级。</param>
    /// <returns>剩余升级总花费。</returns>
    public static int GetRemainingTotalCost(UpgradeKind kind, int level)
    {
        int total = 0;
        for (int current = ClampLevel(kind, level); current < GetMaxLevel(kind); current++)
        {
            total += GetCost(kind, current);
        }

        return total;
    }
}
