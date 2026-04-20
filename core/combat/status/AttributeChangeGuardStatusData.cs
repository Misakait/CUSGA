using Godot;
using CUSGA.core.attributes;

namespace CUSGA.core.combat.status;
// 属性变化拦截 Buff
[GlobalClass]
public partial class AttributeChangeGuardStatusData : StatusEffectData
{
    [Export] public AttributeType TargetAttribute { get; set; }
    [Export] public AttributeChangeDirection Direction { get; set; } = AttributeChangeDirection.Any;

    // true = 直接取消这次属性变化
    [Export] public bool CancelChange { get; set; } = false;

    // 例如 0.5 = 属性变化量减半，2.0 = 属性变化量翻倍
    [Export] public float DeltaMultiplier { get; set; } = 1f;

    [Export] public bool EnableMinValue { get; set; } = false;
    [Export] public float MinValue { get; set; } = 0f;

    [Export] public bool EnableMaxValue { get; set; } = false;
    [Export] public float MaxValue { get; set; } = 0f;

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new AttributeChangeGuardStatusInstance(this, source, owner);
    }
}
