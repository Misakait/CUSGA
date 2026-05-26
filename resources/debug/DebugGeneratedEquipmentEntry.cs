using Godot;
using CUSGA.core.attributes;
using CUSGA.core.constants;
using CUSGA.core.inventory;
using CUSGA.resources.item.equipment;

namespace CUSGA.resources.debugging;

/// <summary>
/// 用于在 Debug 初始背包中动态生成测试装备的配置资源。
/// </summary>
/// <remarks>
/// 该资源把检查器中配置的单条装备信息转换成 <see cref="ItemStack"/>，方便快速验证装备属性、槽位和随机属性流程。
/// </remarks>
[GlobalClass]
public partial class DebugGeneratedEquipmentEntry : Resource
{
    /// <summary>
    /// 获取或设置 Debug 装备允许放入的装备槽位。
    /// </summary>
    [Export] public EquipmentSlot Slot { get; set; } = EquipmentSlot.Weapon;

    /// <summary>
    /// 获取或设置 Debug 装备显示名称。
    /// </summary>
    [Export] public string CardName { get; set; } = "测试装备";

    /// <summary>
    /// 获取或设置 Debug 装备描述文本。
    /// </summary>
    [Export(PropertyHint.MultilineText)] public string Description { get; set; } = "Debug generated equipment.";

    /// <summary>
    /// 获取或设置 Debug 装备图标。
    /// </summary>
    [Export] public Texture2D CardIcon { get; set; }

    /// <summary>
    /// 获取或设置 Debug 装备提供的五维属性类型。
    /// </summary>
    [Export] public AttributeType BonusAttribute { get; set; } = AttributeType.PhysAtk;

    /// <summary>
    /// 获取或设置 Debug 装备随机属性范围；默认物攻已按 100 基准从 1 点等比放大到 10 点。
    /// </summary>
    [Export] public Vector2I BonusRange { get; set; } = new(10, 10);

    /// <summary>
    /// 获取或设置创建堆叠时是否立即为装备掷随机属性。
    /// </summary>
    [Export] public bool RollRandomStats { get; set; } = true;

    /// <summary>
    /// 创建一份包含当前 Debug 装备配置的物品堆叠。
    /// </summary>
    /// <returns>返回已写入装备数据，并按配置决定是否掷随机属性的 <see cref="ItemStack"/>。</returns>
    public ItemStack CreateStack()
    {
        EquipmentData equipment = new()
        {
            CardId = new StringName($"debug_{Slot}_{CardName}"),
            CardName = CardName,
            Description = Description,
            CardIcon = CardIcon
        };

        equipment.ValidSlots.Add(Slot);
        equipment.AttributeBonuses[BonusAttribute] = BonusRange;

        ItemStack stack = new();
        stack.SetItem(equipment, 1);
        if (RollRandomStats)
        {
            stack.RollRandomStats();
        }

        return stack;
    }
}
