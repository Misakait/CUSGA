using Godot;
using CUSGA.core.attributes;
using CUSGA.core.constants;
using CUSGA.core.inventory;
using CUSGA.resources.item.equipment;

namespace CUSGA.resources.debugging;

[GlobalClass]
public partial class DebugGeneratedEquipmentEntry : Resource
{
    [Export] public EquipmentSlot Slot { get; set; } = EquipmentSlot.Weapon;
    [Export] public string CardName { get; set; } = "测试装备";
    [Export(PropertyHint.MultilineText)] public string Description { get; set; } = "Debug generated equipment.";
    [Export] public Texture2D CardIcon { get; set; }
    [Export] public AttributeType BonusAttribute { get; set; } = AttributeType.PhysAtk;
    [Export] public Vector2I BonusRange { get; set; } = new(1, 1);
    [Export] public bool RollRandomStats { get; set; } = true;

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
