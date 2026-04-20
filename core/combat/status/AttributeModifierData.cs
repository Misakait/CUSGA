using Godot;
using CUSGA.core.attributes;

namespace CUSGA.core.combat.status;

[GlobalClass]
public partial class AttributeModifierData : Resource
{
    [Export] public AttributeType Type { get; set; }
    [Export] public AttributeModifierMode Mode { get; set; }
    // 这个 Buff 每一层提供多少属性修正值
    [Export] public float ValuePerStack { get; set; }
}
