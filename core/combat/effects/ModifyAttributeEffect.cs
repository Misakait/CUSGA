using CUSGA.entities.components;
using Godot;
using CUSGA.core.combat.skills;
using CUSGA.core.attributes;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class ModifyAttributeEffect : CardEffect
{
    [Export] public AttributeType TargetAttribute { get; set; } = AttributeType.Speed;

    [Export] public float Amount { get; set; } = 20.0f;

    [Export]
    public SkillEffectTargetScope TargetScope { get; set; } = SkillEffectTargetScope.PrimaryOnly;

    public override void Execute(SkillExecutionContext context)
    {
        if (context == null)
        {
            GD.PushError($"{nameof(ModifyAttributeEffect)} executed with null context.");
            return;
        }

        foreach (var target in SkillEffectTargetScopeUtility.SelectTargets(context, TargetScope))
        {
            if (target.Unit == null)
            {
                continue;
            }

            var attrComp = target.Unit.GetNodeOrNull<AttributeComponent>("Components/AttributeComponent");
            if (attrComp == null)
            {
                GD.PushWarning($"Target '{target.Unit.Name}' has no AttributeComponent.");
                continue;
            }

            attrComp.AddPermanentBonus(TargetAttribute, Amount, context.Source);
            GD.Print($"[修改属性效果] {context.Source?.Name} 使 {target.Unit.Name} 的 {TargetAttribute} 增加了 {Amount} 点");
            GD.Print($"✅ 修改后 {target.Unit.Name} 的 {TargetAttribute} = {attrComp.GetEffectiveValue(TargetAttribute)}");
        }
    }
}
