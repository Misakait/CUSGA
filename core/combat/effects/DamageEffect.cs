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
    public SkillEffectTargetScope TargetScope { get; set; }
            = SkillEffectTargetScope.PrimaryOnly;

    [Export] public float PrimaryDamageMultiplier { get; set; } = 1.0f;

    [Export] public float SecondaryDamageMultiplier { get; set; } = 1.0f;

    public override void Execute(SkillExecutionContext context)
    {
        if (context == null)
        {
            GD.PushError($"{nameof(DamageEffect)} executed with null context.");
            return;
        }
        GD.Print("TargetScope:", TargetScope, "Executing DamageEffect");
        foreach (var target in SkillEffectTargetScopeUtility.SelectTargets(context, TargetScope))
        {
            if (target.Unit == null)
            {
                continue;
            }

            var damage = CalculateDamageForTarget(target);

            ApplyDamageToNode(
                source: context.Source,
                target: target.Unit,
                damage: damage
            );
        }
    }
    private int CalculateDamageForTarget(SkillEffectTargetSelection target)
    {
        float multiplier;

        if (target.IsSource)
        {
            multiplier = PrimaryDamageMultiplier;
        }
        else
        {
            multiplier = target.Role switch
            {
                SkillTargetRole.Primary => PrimaryDamageMultiplier,
                SkillTargetRole.Secondary => SecondaryDamageMultiplier,
                _ => 1.0f
            };
        }

        return Mathf.Max(0, Mathf.RoundToInt(BaseDamage * multiplier));
    }

    private void ApplyDamageToNode(Node source, Node target, int damage)
    {
        if (damage <= 0)
        {
            return;
        }

        var receiver = target.GetNodeOrNull<DamageReceiverComponent>(
            "Components/DamageReceiverComponent"
        );

        if (receiver == null)
        {
            GD.PushWarning($"Target '{target.Name}' has no DamageReceiverComponent.");
            return;
        }

        var payload = new DamagePayload
        {
            Source = source,
            Target = target,
            Damage = damage,
            Type = Type,
            Element = Element
        };

        receiver.ReceiveDamage(payload);

        GD.Print($"[伤害效果] {source.Name} 对 {target.Name} 造成 {damage} 点伤害，基础伤害：{BaseDamage}");
    }
}
