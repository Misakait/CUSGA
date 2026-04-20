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

    public override void Execute(SkillExecutionContext context)
    {
        if (context == null)
        {
            GD.PushError($"{nameof(DamageEffect)} executed with null context.");
            return;
        }


        foreach (var targetInfo in context.Targets)
        {
            var target = targetInfo.Unit;
            if (target == null)
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
                Damage = BaseDamage,
                Type = Type,
                Element = Element
            };

            receiver.ReceiveDamage(payload);

            GD.Print($"[伤害效果] {context.Source.Name} 对 {target.Name} 发起攻击，基础伤害：{BaseDamage}");
        }
    }
}
