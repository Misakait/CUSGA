using CUSGA.entities.components;
using CUSGA.core.constants;
using Godot;
using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class DamageEffect : CardEffect
{
    [Export] public int BaseDamage { get; set; } = 10;

    [Export] public DamageType Type { get; set; } = DamageType.Physical;

    [Export] public ElementType Element { get; set; } = ElementType.None;
    [Export]
    public SkillEffectTargetFilter TargetFilter { get; set; } = SkillEffectTargetFilter.AllTargets;

    [Export] public float PrimaryDamageMultiplier { get; set; } = 1.0f;

    [Export] public float SecondaryDamageMultiplier { get; set; } = 1.0f;

    public override void Execute(SkillExecutionContext context)
    {
        if (context == null)
        {
            GD.PushError($"{nameof(DamageEffect)} executed with null context.");
            return;
        }


        foreach (var targetInfo in context.Targets)
        {
            if (targetInfo == null)
                continue;

            if (!SkillEffectTargetFilterUtility.Matches(TargetFilter, targetInfo))
                continue;

            var target = targetInfo.Unit;
            if (target == null)
                continue;

            float damage = CalculateDamageForTarget(targetInfo);
            if (damage <= 0f)
                continue;

            var receiver = target.GetNodeOrNull<DamageReceiverComponent>("Components/DamageReceiverComponent");

            if (receiver == null)
            {
                GD.PushWarning($"Target '{target.Name}' has no DamageReceiverComponent.");
                continue;
            }

            var payload = new DamagePayload
            {
                Source = context.Source,
                Target = target,
                Damage = (int)damage,
                Type = Type,
                Element = Element
            };

            receiver.ReceiveDamage(payload);

            GD.Print($"[伤害效果] {context.Source.Name} 对 {target.Name} 发起攻击，基础伤害：{BaseDamage}");
        }
    }
    private float CalculateDamageForTarget(SkillTarget target)
    {
        float multiplier = target.Role switch
        {
            SkillTargetRole.Primary => PrimaryDamageMultiplier,
            SkillTargetRole.Secondary => SecondaryDamageMultiplier,
            _ => 1.0f
        };

        return Mathf.Max(0f, BaseDamage * multiplier);
    }
}
