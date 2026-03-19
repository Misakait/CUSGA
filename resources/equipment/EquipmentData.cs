using Godot;
using Godot.Collections;
using CUSGA.core.attributes;
using CUSGA.core.constants;

namespace CUSGA.resources.equipment;

[GlobalClass]
public partial class EquipmentData : Resource
{
    [Export] public string ItemName { get; set; }
    [Export] public Texture2D Icon { get; set; }

    // 允许装备在哪些槽位（斧头可以同时勾选 Axe 和 Weapon）
    [Export] public Array<EquipmentSlot> ValidSlots { get; set; } = [];

    // 所属套装
    [Export] public EquipmentSet SetType { get; set; } = EquipmentSet.None;

    // 提供的属性加成 { PhysAtk: 10, Speed: -2 }
    [Export] public Dictionary<AttributeType, float> AttributeBonuses { get; set; } = [];

    // 提供的行为标签
    [Export] public Array<StringName> GrantedTags { get; set; } = [];
}
