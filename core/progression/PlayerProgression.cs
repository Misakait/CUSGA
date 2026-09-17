using CUSGA.core.shop;
using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.progression;

/// <summary>
/// 持有玩家的容量升级等级（仓库槽位、带入栏数量），并在升级时扣除金币、持久化到本地设置。
/// </summary>
/// <remarks>
/// 为什么需要一个独立的 autoload：等级要跨场景、跨战斗、跨重启保留，而
/// <c>PlayerWallet</c> 只管金币、<c>GlobalWarehouse</c> 管库存内容、<c>SettingsManager</c> 管配置读写，
/// 没有任何一个既有 autoload 拥有「玩家成长等级」这个状态。
/// <para>
/// 对 GDScript 只暴露**具名方法**而不是带枚举参数的方法：GDScript 无法引用 C# 的枚举类型，
/// 用具名方法（<c>GetWarehouseCapacity</c> / <c>TryUpgradeCarrySlots</c> …）比传裸整数清晰得多。
/// </para>
/// </remarks>
public partial class PlayerProgression : Node
{
    /// <summary>本地设置文件中升级等级所属的分组名，与 <c>PlayerWallet</c> 共用。</summary>
    public const string SettingsSection = "player";

    /// <summary>仓库容量等级的存储键。</summary>
    private const string WarehouseLevelKey = "warehouse_level";

    /// <summary>带入栏等级的存储键。</summary>
    private const string CarryLevelKey = "carry_level";

    /// <summary>
    /// 升级成功时发射。
    /// </summary>
    /// <param name="kind">升级项名称，取值 <c>"warehouse_capacity"</c> 或 <c>"carry_slots"</c>。</param>
    /// <param name="value">升级后的数值（仓库槽位数或带入栏数量）。</param>
    [Signal]
    public delegate void UpgradeChangedEventHandler(string kind, int value);

    // 缓存依赖节点：升级会在按下按钮时立刻结算，不应每次沿场景树重新查找。
    private Node _settingsManager;
    private IPlayerWallet _wallet;
    private InventoryComponent _warehouse;

    // 以 (int)UpgradeKind 为下标保存当前等级。
    private readonly int[] _levels = new int[2];

    public override void _Ready()
    {
        _settingsManager = GetNodeOrNull<Node>("/root/SettingsManager");
        if (_settingsManager == null)
        {
            GD.PushError("PlayerProgression: 未找到 SettingsManager，升级等级将只在本次运行内有效。");
        }

        _wallet = GetNodeOrNull<Node>("/root/PlayerWallet") as IPlayerWallet;
        if (_wallet == null)
        {
            GD.PushError("PlayerProgression: 未找到 PlayerWallet，升级将无法扣款。");
        }

        _warehouse = GetNodeOrNull<Node>("/root/GlobalWarehouse") as InventoryComponent;
        if (_warehouse == null)
        {
            GD.PushError("PlayerProgression: 未找到 GlobalWarehouse，仓库容量升级不会生效。");
        }

        _levels[(int)UpgradeKind.WarehouseCapacity] = ReadLevel(UpgradeKind.WarehouseCapacity, WarehouseLevelKey);
        _levels[(int)UpgradeKind.CarrySlots] = ReadLevel(UpgradeKind.CarrySlots, CarryLevelKey);

        // 仓库容量必须在 GlobalWarehouse 完成 _Ready（内部槽位数组建好）之后才能扩容，
        // autoload 的注册顺序保证了这一点。
        ApplyWarehouseCapacity();
    }

    /// <summary>
    /// 读取仓库容量等级。
    /// </summary>
    /// <returns>当前等级。</returns>
    public int GetWarehouseLevel() => GetLevel(UpgradeKind.WarehouseCapacity);

    /// <summary>
    /// 读取当前仓库槽位数。
    /// </summary>
    /// <returns>仓库总槽位数。</returns>
    public int GetWarehouseCapacity() => UpgradeService.GetValue(UpgradeKind.WarehouseCapacity, GetWarehouseLevel());

    /// <summary>
    /// 读取把仓库容量升到下一级所需金币。
    /// </summary>
    /// <returns>升级费用；已满级时返回 0。</returns>
    public int GetWarehouseNextCost() => UpgradeService.GetCost(UpgradeKind.WarehouseCapacity, GetWarehouseLevel());

    /// <summary>
    /// 判断仓库容量是否已经满级。
    /// </summary>
    /// <returns>已满级时为 <see langword="true"/>。</returns>
    public bool IsWarehouseMaxLevel() => UpgradeService.IsMaxLevel(UpgradeKind.WarehouseCapacity, GetWarehouseLevel());

    /// <summary>
    /// 尝试花费金币提升仓库容量。
    /// </summary>
    /// <returns>升级成功时为 <see langword="true"/>；金币不足或已满级时为 <see langword="false"/> 且不产生任何变化。</returns>
    public bool TryUpgradeWarehouse() => TryUpgrade(UpgradeKind.WarehouseCapacity);

    /// <summary>
    /// 读取带入栏等级。
    /// </summary>
    /// <returns>当前等级。</returns>
    public int GetCarryLevel() => GetLevel(UpgradeKind.CarrySlots);

    /// <summary>
    /// 读取当前可带入游戏的物品栏位数量。
    /// </summary>
    /// <returns>带入栏数量。</returns>
    public int GetCarrySlotCount() => UpgradeService.GetValue(UpgradeKind.CarrySlots, GetCarryLevel());

    /// <summary>
    /// 读取把带入栏升到下一级所需金币。
    /// </summary>
    /// <returns>升级费用；已满级时返回 0。</returns>
    public int GetCarryNextCost() => UpgradeService.GetCost(UpgradeKind.CarrySlots, GetCarryLevel());

    /// <summary>
    /// 判断带入栏是否已经满级。
    /// </summary>
    /// <returns>已满级时为 <see langword="true"/>。</returns>
    public bool IsCarryMaxLevel() => UpgradeService.IsMaxLevel(UpgradeKind.CarrySlots, GetCarryLevel());

    /// <summary>
    /// 尝试花费金币扩充带入栏。
    /// </summary>
    /// <returns>升级成功时为 <see langword="true"/>；金币不足或已满级时为 <see langword="false"/> 且不产生任何变化。</returns>
    public bool TryUpgradeCarrySlots() => TryUpgrade(UpgradeKind.CarrySlots);

    /// <summary>
    /// 读取某个升级项的当前等级。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <returns>当前等级。</returns>
    public int GetLevel(UpgradeKind kind) => _levels[(int)kind];

    /// <summary>
    /// 尝试升级某个项目：扣金币、提升等级、持久化并把新容量同步给仓库。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <returns>升级成功时为 <see langword="true"/>。</returns>
    /// <remarks>
    /// 顺序固定为「先校验 → 再扣款 → 最后改状态」。扣款失败时等级必须原封不动，
    /// 否则会出现「没花钱却升了级」。落盘失败不回滚内存值，与 <c>PlayerWallet</c> 的既定契约保持一致。
    /// </remarks>
    private bool TryUpgrade(UpgradeKind kind)
    {
        int level = GetLevel(kind);

        if (UpgradeService.IsMaxLevel(kind, level))
        {
            return false;
        }

        int cost = UpgradeService.GetCost(kind, level);
        if (cost <= 0)
        {
            // 等级与费用表不一致说明规则表被改坏了，报错而不是静默当成免费升级。
            GD.PushError($"PlayerProgression: {KindName(kind)} 在等级 {level} 取不到升级费用。");
            return false;
        }

        if (_wallet == null || !_wallet.TrySpend(cost))
        {
            return false;
        }

        int newLevel = level + 1;
        _levels[(int)kind] = newLevel;
        SaveLevel(kind, newLevel);
        ApplyWarehouseCapacity();

        EmitSignal(SignalName.UpgradeChanged, KindName(kind), UpgradeService.GetValue(kind, newLevel));
        return true;
    }

    /// <summary>
    /// 把当前等级对应的仓库容量同步给全局仓库。
    /// </summary>
    /// <remarks>仓库容量只增不减，因此这里直接下发等级算出的值即可。</remarks>
    private void ApplyWarehouseCapacity()
    {
        if (_warehouse == null)
        {
            return;
        }

        _warehouse.SetCapacity(UpgradeService.GetValue(UpgradeKind.WarehouseCapacity, GetWarehouseLevel()));
    }

    /// <summary>
    /// 从本地设置读取一个升级等级。
    /// </summary>
    /// <param name="kind">升级项，用于收窄合法范围。</param>
    /// <param name="key">存储键。</param>
    /// <returns>通过校验的等级；缺失或非法时返回 0。</returns>
    private int ReadLevel(UpgradeKind kind, string key)
    {
        if (_settingsManager == null)
        {
            return 0;
        }

        Variant stored = _settingsManager.Call("get_setting", SettingsSection, key, 0);

        // 首次运行时 SettingsManager 会原样返回默认值 0，因此这两种数值类型是唯一合法形态。
        if (stored.VariantType != Variant.Type.Int && stored.VariantType != Variant.Type.Float)
        {
            GD.PushWarning($"PlayerProgression: 存档中的 {key} 不是数值，已回退到 0 级。");
            return 0;
        }

        int raw = stored.AsInt32();
        int clamped = UpgradeService.ClampLevel(kind, raw);

        // 只在确实越界时告警：负数或超出上限说明存档被改过，静默收窄会让问题难以发现。
        if (clamped != raw)
        {
            GD.PushWarning($"PlayerProgression: 存档中的 {key} 为 {raw}，已收窄到 {clamped}。");
        }

        return clamped;
    }

    /// <summary>
    /// 把一个升级等级写入本地设置。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <param name="level">要保存的等级。</param>
    private void SaveLevel(UpgradeKind kind, int level)
    {
        if (_settingsManager == null)
        {
            return;
        }

        Variant saved = _settingsManager.Call("set_setting", SettingsSection, LevelKey(kind), level);
        if (saved.VariantType != Variant.Type.Bool || !saved.AsBool())
        {
            GD.PushWarning($"PlayerProgression: {LevelKey(kind)} 未能写入本地设置文件，本次运行内仍然有效。");
        }
    }

    /// <summary>
    /// 读取某个升级项的存储键。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <returns>稳定的英文存储键。</returns>
    private static string LevelKey(UpgradeKind kind) =>
        kind switch
        {
            UpgradeKind.WarehouseCapacity => WarehouseLevelKey,
            UpgradeKind.CarrySlots => CarryLevelKey,
            _ => "unknown",
        };

    /// <summary>
    /// 读取某个升级项的信号名称。
    /// </summary>
    /// <param name="kind">升级项。</param>
    /// <returns>供 GDScript 判断的信号名。</returns>
    private static string KindName(UpgradeKind kind) =>
        kind switch
        {
            UpgradeKind.WarehouseCapacity => "warehouse_capacity",
            UpgradeKind.CarrySlots => "carry_slots",
            _ => "unknown",
        };
}
